/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_finalize_data.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Finalize dataset by ordering the variables (by the order in 
				  dataset specified as SHEET_METADATA) and sort the dataset (by
				  the variables specified in the ORDER paramter). 

Parameters:
  inds            : Name of the input dataset to be porcesed
  SHEET           : Sheet name (to look up metadata in SHEET_METADATA)
  SHEET_METADATA  : Name of the dataset containg sheet-metadata 
                      (Default: defdata.spec_sheet_meta)
  OUTDS           : Name of the output dataset 
					  (Default: defdata.p21_spec_&sheet.)
  ORDER           : Variable to sort the output dataset by. Multiple variables
					  can be provided as a space separted list.
*******************************************************************************/

%macro p21spec_finalize_data(
  inds =,
  sheet =,
  sheet_metadata=defdata.spec_sheet_meta,
  outds = defdata.p21spec_&sheet.,
  order=,
  cleanup = Y
);

%p21spec_cleanwork(mode = get);

* Add library 'work' to INDS if it is only specified as a datset name;
%if %scan(%str(&inds.),1,%str(.)) eq %str(&inds.) %then %do;
  %let inds = work.&inds.;
%end;

* Create a list of columns to include in the exported sheet - if a required ;
* column is not in the input dataset, it will be created with all missing ;
* values, to ensure p21-compatability, but a warn. will be thrown ;
data p21_col_spec;
  set &sheet_metadata.;
  where upcase(sheet) eq upcase("&sheet.");
  keep order name label in_spec read_ignore write_ignore;
  length in_spec 8.;
  in_spec = 1;
  name=upcase(name);
run;

proc sql noprint;
  create table p21_col_data as select
    1 as in_data,
    name
  from dictionary.columns
  where %upcase(catx('.',libname,memname)) eq "%upcase(&inds.)";

  create table p21_col_all as select *
  from p21_col_spec
  natural full join p21_col_data;
quit;

data _p21_write_col;
  set p21_col_all;
  where write_ignore ne 1;

  * Warn if specified variables are not in data;
  if in_spec eq 1 and in_data ne 1 then putlog "%str(W)ARNING: Required P21 column is not in dataset %upcase(&inds.): " name=;
run;

proc sql noprint;
  * Create statements for selecting the required sheet-columns in specified order/apply labels for the final p21-compatible sheet;
  select catx(' ', name, 'label=', quote(strip(label))) into :_final_select_stmt separated by ', '
  from _p21_write_col
  where in_spec eq 1
  order by order;
quit;

* Add (if any) missing P21-requied variables to INDS - to ensure a valid (but partial) P21-spec file can be created ;
proc sql noprint;
  select distinct count(name), name  into :_missing_p21_count, :_add_p21_vars separated by ', '
  from _p21_write_col
  where in_spec eq 1 and in_data ne 1;
quit;

data _p21_final_export;
  set &inds. end=eof;
  %if &_missing_p21_count. ne 0 %then %do;
    call missing(&_add_p21_vars.);
  %end;
run;

* Sort by specified variables ;
%if %str(&order.) ne %str() %then %do;
  proc sort data = _p21_final_export sortseq=linguistic(numeric_collation=on);
    by &order.;
  run;
%end;

proc sql noprint;
  create table &outds. (label="&sheet.") as select
    &_final_select_stmt.
  from _p21_final_export;
quit;

* If the dataset contains 0 observations, add a single all-missing observation to ensure ;
* the sheet i created (wiht no data) in the output file ;
%if &sqlobs. eq 0 %then %do;
  data _dummy;
    dummy=1;
  run;
  data &outds.(drop=dummy);
    set &outds. _dummy;
  run;
%end;

* Clean up work;
%p21spec_cleanwork(mode = clean);

%mend;
