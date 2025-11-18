/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_excel_import.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Read the specified sheet from the specified excel-file into
                  defdata.entry_[SHEET]. 
                  - Variable names are created from the 'label' (first row)
                    in the excel sheet, replaing any occurence (or sequence) of
                    non alphanumeric characters wiht a single underscore.
                    Columns the have data, but no label are ignord.
                  - Rows where the [drop column] is set to 'drop' are not red.
                  The dataset defdata.spec_sheet_meta is updated wiht actual
                  variable names (in the SAS dataset) and which collumn (letter)
                  in the entry-file it comes from, including number of observations
                  for the sheet currently being read.

                  A global macro variabel _LASTDS_&SHEET. is initiated as &OUTDS.
                  (stripped from any 'non english letters or underscore'). This
                  variable is intended to be updated by the modules processing the
                  specific dataset.

Parameters:
  INFILE          : Path/name of the entry-file.
  SHEET           : name of the sheet to read.
  SHEET_METADATA  : name of the sheet-metadata dataset.
                      default: defdata.spec_sheet_meta
  OUTDS           : Name of the output dataset, defule: defdata.entry_[SHEET]
                      (stripped from any 'non english letters or underscore')
  IGNOR_EMPTY_ROWS: When set to 'Y', rows that contain no actual data are deleted.

*******************************************************************************/

%macro p21spec_excel_import(
  infile=&temp_entryfile_path.,
  sheet=,
  sheet_metadata=defdata.spec_sheet_meta,
  outds=defdata.entry_&sheet_ds.,
  ignore_empty_rows=Y,
  cleanup=Y
);

%p21spec_cleanwork(mode = get);

* Create meta dataset based on the specification in the 'columns' paramter ;
* Store the sheet name and number in a macro variables for futurer use ;
%let sheet_ds = %sysfunc(compress(%str(&sheet.),%str(),%str(kn)));

data _import_meta;
  set &sheet_metadata. (where=(upcase(sheet) eq upcase("&sheet."))) end=eof;
  drop in_spec in_data;
  if eof then do;
    call symput('__meta_sheetname',sheet);
    call symput('__meta_sheetnumber',put(sheetn,best.));
  end;
run;

* Import data - with getname = no to force all variables to be character;
proc import datafile = "&infile."
  dbms = xlsx
  out = _raw_import_&sheet_ds. replace;
  sheet = "&sheet.";
  getnames =no;
run;

* Remove rows that are all missing - if 'ignore_empty_rows' is set to 'Y' ;
data _import_&sheet_ds.;
  set _raw_import_&sheet_ds.;
  %if %upcase(&ignore_empty_rows.) eq %str(Y) %then %do;
    if not missing(cats(of _char_));
  %end;
run;

* Transpose first row of the iported data to get a 'import-name(excel column) -> label' ;
* translation table and join import-name onto _IMPORT_META-dataset;
proc transpose data=_import_&sheet_ds.(obs=1) out=_import_&sheet_ds._vars(drop = _label_);
  var _all_;
run;

proc sql noprint;
  create table _prep_column_meta as select
    not missing(i.label) as in_spec,
    not missing(e.col1) as in_data,
    i.*, 
    length(strip(e._name_)) as import_name_length,
    e._name_ as import_name,
    e.col1 as import_label
  from _import_meta as i
  full join _import_&sheet_ds._vars as e
  on e.col1 eq i.label
  order by calculated import_name_length, import_name;
quit;

data _column_meta;
  length sheet $50 sheetn 8 name $200 order read_order 8 label note $200 import_name $10 read_ignore write_ignore in_spec in_data 8;
  set _prep_column_meta;
  keep sheet--in_data;

  * Delete rows that are not defined in either spec or data (when "something" is written in a column in  ;
  * the entry sheet, but no label (first row) is given - in this case, we do not know what is is and ignore it ;
  where in_spec+in_data gt 0;

  * Populate SHEET, SHEETN and LABEL (+a NOTE and WRITE_IGNORE) for variables that are ;
  * not specifeid but read from the etry file ;
  if in_spec eq 0 and in_data eq 1 then do;
    sheet="&__meta_sheetname.";
    sheetn=input("&__meta_sheetnumber.",best.);
    label=import_label;
    note='Unspecified variable, imported from the entry sheet';
    write_ignore=1;
  end;

  * Set the read order ;
  read_order=(sheetn*100)+_N_;

  * Create valid sas name from the label, by replacing all (sequences of) ;
  * non-alphanumeric charactetrs in the label wiht a _SINGLE_ space, then ;
  * replace space with underscore;
  _label_singlespace = compbl(prxchange('s/[^A-Z0-9_]/ /i', -1, strip(label)));
  name = upcase(tranwrd(strip(_label_singlespace),' ','_'));

run;

* Warn if actual imported column does not match the specified ;
data _null_;
  set _column_meta;
  if read_ignore ne 1 and in_spec eq 1 and in_data eq 0 then do;
    msg = catx(' ', 'Specified column(label)', quote(strip(label)), ' is not in the imported sheet ', quote(upcase("&sheet.")));
    putlog "%str(W)ARNING: " msg;
  end;
run;

proc sql noprint;
  * Concatenate rename statement (from 'excel column' to 'variable name');
  select distinct catx(' ', import_name, '=', name) into: _rename_stmt  separated by ' '
  from _column_meta
  where in_data eq 1;

  * Concatenate label statements ;
  select distinct 
    read_order,
    catx(' ', name, '=', quote(strip(label))) 
  into
    :__nowhere__,
    : _label_stmt separated by ' '
  from _column_meta
  where in_data eq 1
  order by read_order
  ;

  * Concatenate list of columns (for keep/format statements);
  select distinct name into: _columns separated by ' '
  from _column_meta
  where in_data eq 1;

  * Select max number of observations (minus 1 as the first row is the label);
  select count(*)-1 into: _nobs
  from _import_&sheet_ds.;

  * Check for existence of the drop variable;
  select count(name) into: _has_drop trimmed
  from _column_meta
  where upcase(name) eq upcase("&drop_variable.") and in_data eq 1;
quit;


* Replace 'exixting' metadata in the 'spec_sheet_metadata', with the actual ;
* metadata for the sheet currently being processed ;
data &sheet_metadata.;
  set 
    &sheet_metadata. (where=(upcase(sheet) ne upcase("&sheet.")))
    _column_meta (in=actual)
  ;
  if actual then do;
    nobs = &_nobs.;
    SRC_SHEET_COLUMN=import_name;
  end;


  _dummy="";
  drop _: import: ;
run;

* Apply column names (rename from A, B, C... to 'human understandbale' and add a orderinge variable ;
* This step will throw a "standard warn." if a specified column does not exists - could be optimized to ;
* specify "what to do";
data &outds.(keep=_read_order &_columns.);
 /* length _read_order $20.;*/
  label &_label_stmt.;
  set _import_&sheet_ds.(
    %if &_nobs. ge 1 %then %do;
      firstobs=2
    %end;
    rename=(&_rename_stmt.)
  );
  %if &_nobs. eq 0 %then %do;
    stop;
  %end;

  informat &_columns. $2000.;
  format &_columns. $2000.;

  %if &_has_drop. eq 1 %then %do;
    where upcase(&drop_variable.) ne 'DROP';
  %end;
  _read_order = put(_N_, best. -l);
run;

* Declare a global macro variable to hold the name of the name of the latest dataset containg the ;
* name of the sheet currently being processed - to be updated by each module when the update a dataset ;
%global %upcase(_lastds_&sheet_ds.);
%let _lastds_&sheet_ds. = &outds.;

* Clean up work;
%p21spec_cleanwork(mode = clean);

%mend;
