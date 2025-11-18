/*******************************************************************************
Project Name    : general
Program Name    : p21spec_creator.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : This is the main "driver program" of the p21spec-creator 
                  package. The program contains 3 main sections:
                  1. Configuration and data-load - sets up the "environment" and
                     read the contents of the entry-files into SAS datasets 
                     in the 'defdata' library.
                  2. Manipulation of spec sheet-data; this is where all the 
                     "magic" happens, e.g., creation of actual method/comment
                     entries and creatoin of variables form core-groups. This 
                     section is mostly calls to macros that do the actual work.
                  3. Finalization and creation of p21upload-file. The final
                     "sheet-dataset" are stored in the 'defdata' library (for
                     reference/potential future use), and the p21upload-file
                     is re-written - if the p21upload-file exists, and cannot
                     be deleted, a "personal copy" (with leading initials and
                     datetime) is writen                

                  The program is intended to be placed in a folder named 'sdtm'
                  or 'adam' under .\tools\p21spec_creator in the standard milestone
                  folder structure. The sdtm/adam folder must also contain the 
                  autoexec.sas file and a subfolder named 'data' (used for the 
                  'defdata' library.
*******************************************************************************/

*******************************************************************************;
* AUTOEXEC - included for demonstration purpose only ;
* This sections sets a few variables that - in a production envrionemnt - would;
* be set by an autoexec/initialization macro;
*******************************************************************************;
%global _PGMPATH _STUDYID PROGDOC;
* Set the "current folder", from where the program is being executed ;
* (this is where the p21spec_creator code-base, and SAS dataset ;
* containing "define data" are stored - in relevant sub-folders) ;
%let _PGMPATH = S:\Biometrics\CNP\ASND0036\phuse_temp\tools\p21spec_creator\sdtm\;
* Set path to the "trial level documents for programming" folder ;
* (this is where (in subfolders) the "Entry-file" is read from, ;
* and the "Upload-file" is written to) ;
%let PROGDOC = S:\Biometrics\CNP\ASND0036\phuse_temp\progdoc;
* Set the Study-ID ;
* (this is used by the p21spec_creator to drive default names of the "Upload" ;
* and "Entry-file" as well as the name of the "drop-column " ;
%let _STUDYID = PHUSE;
*******************************************************************************;
* End of AUTOEXEC - The remaining program is supposed to be kept as-is ;
* (maybe with a few modificatoins to the "Run configuration" section ;
*******************************************************************************;

*******************************************************************************;
* Run configuration ;
* By default, values are derived from init-variables and/or set to standard ;
* values - in most cases this is expected to work "out of the box", but ;
* in some cases special configuration might be needed.
*******************************************************************************;

* Set working directory - depending on whether program is inculded or run as "stand alone";
* adding backslash to SYSINCLUDEFILEDIR to match the format of _PGMPATH ;
%if "&SYSINCLUDEFILEDIR." ne "" %then %do;
  %let wd = &SYSINCLUDEFILEDIR.\;
%end;
%else %do;
  %let wd = &_PGMPATH.; 
%end;

* Set STUDYCD and SCOPE (SCOPE is expected to be SDTM or ADAM.) ;
%global /readonly __studycd = &_STUDYID.;
%global /readonly __scope = %upcase(%scan(%str(&wd.),-1,%str(\)));

* Set entry/upload file;
%let entryfile = &__scope._Mapping_Specifications_Entry_&__studycd..xlsx;
%let p21uploadfile = P21_UPLOAD_&__scope._Mapping_Specifications_&__studycd..xlsx;

* Set name of 'drop variable';
%let drop_variable = %upcase(&__studycd.);

*******************************************************************************;
* Derive / Set up static configuration and envrionment ;
* (configuration below this point should not be needed) ;
*******************************************************************************;

* Define paths to the tool and data folder;
%global /readonly toolpath = &wd...\macro\;
%global /readonly datapath = &wd.\data;

* Concatenate full paths for the entry and upload file (the upload file is not ;
* readonly, as it might have to be changed in case of access conflicts ;
%global /readonly entryfile_path = &PROGDOC.\&__scope.\&entryfile.;
%global /readonly temp_entryfile_path = &PROGDOC.\&__scope.\_&sysuserid._tmp_entryfile_.xlsx;
%let p21uplfile_path = &PROGDOC.\&__scope.\&p21uploadfile.;
%put &p21uplfile_path.;
* Set various options - most importantly is adding toolpath to sasautos and libname to data;
option 
  validvarname=upcase 
  nomprint nosource mcompilenote=all
  insert=(sasautos="&toolpath.")
;

* Set libname to "define data" - to keep "major temporary" datasets availalble for other use ;
libname defdata "&datapath.";

* Set default auto-vlm-generation variables depending on scope;
%if %str(&__scope.) eq %str(SDTM) %then %do;
  %let default_vlm_target_variables = EGSTRESC, EGSTRESN, EGORRESU, EGSTRESU;
  %let default_vlm_selection_criteria = TESTCD;
%end;
%if %str(&__scope.) eq %str(ADAM) %then %do;
  %let default_vlm_target_variables = AVLA, AVALC;
  %let default_vlm_selection_criteria = PARAMCD;
%end;

* Set a lock to prevent mulgiple users from running the tool simultaneously;
%p21spec_set_lock(lockfile=%str(&wd.\lock.p21spec_creator));

* Specify columns in each sheet. A leading asterisk indicates variables that does not exist in/ ;
* will be ignored from the entry-file (expeted to be 'created' by a p21spec_creator module, and ;
* will be written to the p21-upload-file). A leading hyphen indicates variables that are  ;
* present in, and will be read from entry-sheet, but will not be included in the p21-upload file ;
* intended for non-p21-standard variables used by a p21spec_creator module or other 'meta tasks');
%let col_Define       = 'Attribute', 'Value';
%let col_Datasets     = 'Dataset', 'Label', 'Class', 'SubClass', 'Structure', 'Key Variables', 'Standard', 'Has No Data', 'Repeating', 'Reference Data', 'Comment', 'Developer Notes';
%let col_Variables    = 'Order', 'Dataset', 'Variable', 'Label', 'Data Type', 'Length', 'Significant Digits', 'Format', 'Mandatory', 'Assigned Value', 'Codelist', 'Common', 'Origin', 'Source', 'Pages', 'Method', '-Method Expression Context',  '-Method Expression Code', '-Method Document', '-Method Pages', 'Predecessor', 'Role', 'Has No Data', 'Comment', '-Comment Document', '-Comment Pages', 'Developer Notes', '-Core Group', '*_core_variable_note';
%let col_ValueLevel   = 'Order', 'Dataset', 'Variable', 'Where Clause', 'Label', 'Data Type', 'Length', 'Significant Digits', 'Format', 'Mandatory', 'Assigned Value', 'Codelist', 'Origin', 'Source', 'Pages', 'Method', '-Method Expression Context',  '-Method Expression Code', '-Method Document', '-Method Pages', 'Predecessor', 'Comment', '-Comment Document', '-Comment Pages', 'Developer Notes', 'Qeval';
%let col_Codelists    = 'ID', 'Name', 'NCI Codelist Code', 'Data Type', 'Terminology', 'Comment', 'Order', 'Term', 'NCI Term Code', 'Decoded Value';
%let col_Dictionaries = 'ID', 'Name', 'Data Type', 'Dictionary', 'Version';
%let col_Methods      = 'ID', 'Name', 'Type', 'Description', 'Expression Context', 'Expression Code', 'Document', 'Pages';
%let col_Comments     = 'ID', 'Description', 'Document', 'Pages';
%let col_Documents    = 'ID', 'Title', 'Href';

* "Convert" column-variables to a dataset ;
%p21spec_create_sheet_meta;

*******************************************************************************;
* Get data from the entry-file - store the individual sheets as defdata.[sheet];
*******************************************************************************;

* Copy entry-file to a temporary location to avoid "open by other user" issue ;
data _null_;
  infile %sysfunc(quote(copy &entryfile_path. &temp_entryfile_path.)) pipe;
  input;
  put _infile_;
run;

%p21spec_excel_import(sheet=define, ignore_empty_rows=N);
%p21spec_excel_import(sheet=datasets);
%p21spec_excel_import(sheet=variables);
%p21spec_excel_import(sheet=valueLevel);
%p21spec_excel_import(sheet=codelists);
%p21spec_excel_import(sheet=dictionaries);
%p21spec_excel_import(sheet=methods);
%p21spec_excel_import(sheet=comments);
%p21spec_excel_import(sheet=documents);

* Delete temporary entry-file;
data _null_;
  infile %sysfunc(quote(del &temp_entryfile_path.)) pipe;
  input;
  put _infile_;
run;

*******************************************************************************;
* All configuration/preparation done! ;
* In the following section, the "sheet-datasets" are modified to the structure ;
* and content that is eventually written to the p21upload-file. ;
* This section is mostly macro calls, but simpler oprations cna be done in ;
* in-line code ;
*******************************************************************************;

*------------------------------------------------------------------------------;
* Read "global information" from the define sheet and add "do not edit" notes ;
* to be included in the upload-file ;
*------------------------------------------------------------------------------;
%p21spec_define(
  inds_define = &_LASTDS_DEFINE.,
  outds_define = temp_define_updated
);

*------------------------------------------------------------------------------;
* Convert methods in the entry sheet (variables/valuelevel) to entries in the Method sheet;
* - if an entry-METHOD matches an exiting METHODS.ID no updates are done ;
*   (intended to be used for generic/standard methods so they only have to be ;
*   defined/maintained in a single place) ;
* - Otherwise, the values in the entry-METHOD_-columns are copied to the correspoinding ;
*   column in the METHODS-sheet, entry-METHOD is copied to METHODS.DESCRIPTION and ;
*   a autogenerated ID (catx('_', dataset, variable, [suffix])) is inserted in ;
*   entry-METHOD and METHODS.ID.
* - When a method is auto-generatd, the entry-METHOD_-columns are cleared.
*------------------------------------------------------------------------------;
%p21spec_automethods (
  inds_main= &_LASTDS_VARIABLES.,
  inds_methods=&_LASTDS_METHODS.,
  outds_main=temp_variables_automethods,
  outds_methods=temp_methods_automethods
);

%p21spec_automethods(
  inds_main = &_LASTDS_VALUELEVEL.,
  inds_methods = &_LASTDS_METHODS.,
  outds_main = temp_valuelevel_automethods,
  outds_methods = temp_methods_vl_automethods,
  id_suffix = vlautomet
);

*------------------------------------------------------------------------------;
* Convert comments in the entry sheet (variables/valuelevel) to entries in the Comment sheet;
* - if a entry-COMMENT matches an exiting COMMENTS.ID no updates are done ;
*   (intended to be used for generic/standard comments so they only have to be ;
*   defined/maintained in a single place) ;
* - Otherwise, the values in the entry-COMMENT_-columns are copied to the correspoinding ;
*   column in the COMMENTS-sheet, entry-COMMENT is copied to COMMENTS.DESCRIPTION and ;
*   a autogenerated ID (catx('_', dataset, variable, [suffix])) is inserted in ;
*   entry-COMMENT and COMMentsS.ID.
* - When a comment is auto-generatd, the entry-COMMENT_-columns are cleared.
*------------------------------------------------------------------------------;
%p21spec_autocomments(
  inds_main = &_LASTDS_VARIABLES.,
  inds_comments = &_LASTDS_COMMENTS.,
  outds_main = temp_variables_autocomments,
  outds_comments = temp_comments_autocomments
);

%p21spec_autocomments(
  inds_main = &_LASTDS_VALUELEVEL.,
  inds_comments = &_LASTDS_COMMENTS.,
  outds_main = temp_valuelevel_autocomments,
  outds_comments = temp_comments_vl_autocomments,
  id_suffix = vlautocom
);

*------------------------------------------------------------------------------;
* Add core-group variables from/to the variable sheet;
*------------------------------------------------------------------------------;
%p21spec_add_core(
  inds=&_LASTDS_VARIABLES.,
  domain_specific_variables = assigned_value codelist method comment,
  outds=temp_variables_coregroup,
  cleanup=N
);

*------------------------------------------------------------------------------;
* Add default dataset standards ;
*------------------------------------------------------------------------------;
data temp_datasets_standard;
  set &_LASTDS_DATASETS. (rename=(standard=_standard));
  standard = coalescec(strip(_standard),"&_default_datasets_standard.");
run;
%let _LASTDS_DATASETS = temp_datasets_standard;  

*------------------------------------------------------------------------------;
* Output final version of the sheets to the Defdata library;
*------------------------------------------------------------------------------;
%p21spec_finalize_data(inds = &_LASTDS_DEFINE.,        sheet = Define);
%p21spec_finalize_data(inds = &_LASTDS_DATASETS.,      sheet = Datasets,      order = _read_order);
%p21spec_finalize_data(inds = &_LASTDS_VARIABLES.,     sheet = Variables,     order = _dataset_order dataset order);
%p21spec_finalize_data(inds = &_LASTDS_VALUELEVEL.,    sheet = valueLevel,    order = dataset order);
%p21spec_finalize_data(inds = &_LASTDS_CODELISTS.,     sheet = codelists,     order = id order term );
%p21spec_finalize_data(inds = &_LASTDS_DICTIONARIES.,  sheet = dictionaries);
%p21spec_finalize_data(inds = &_LASTDS_METHODS.,       sheet = methods,       order = id);
%p21spec_finalize_data(inds = &_LASTDS_COMMENTS.,      sheet = comments);
%p21spec_finalize_data(inds = &_LASTDS_DOCUMENTS.,     sheet = documents);

*------------------------------------------------------------------------------;
* Create the P21 spec file ;
*------------------------------------------------------------------------------;
* Delte output file, to ensure the new file can be written without conflicts ;
* if existing file cannot be deleted, warn. and write the new file with a ;
* user/date/time prefix ;

filename p21out "&p21uplfile_path." recfm=n;
%let rc = %sysfunc(fdelete(p21out));
option linesize=120;
data _null_;
  exitstatus="%sysfunc(sysmsg())";
  if indexw(exitstatus,'The file is already locked by another') then do;
    prefix=compress("&sysuserid._" || put(date(),date9.) || 'T' || put(time(),tod5.),': ');
    newfile= "&PROGDOC.\&__scope.\_" || strip(prefix) || '_' || "&p21uploadfile.";
    putlog "%str(W)ARNING: Cannot write to the specified upload-file:";
    putlog "%str(W)ARNING:   &p21uplfile_path.";
    putlog "%str(W)ARNING: you (or someone else) might have it open. Your file will be saved with the prefix:";
    putlog "%str(W)ARNING:   " prefix;
    call symput('p21uplfile_path',newfile);
  end;
run;

ods _all_ close;
ods excel file = "&p21uplfile_path." options(flow='tables' formulas='off' autofilter='all' protect_worksheet='on');
  %p21spec_write_sheet(sheet = define);
  %p21spec_write_sheet(sheet = datasets);
  %p21spec_write_sheet(sheet = variables);
  %p21spec_write_sheet(sheet = valuelevel);
  %p21spec_write_sheet(sheet = codelists);
  %p21spec_write_sheet(sheet = dictionaries);
  %p21spec_write_sheet(sheet = methods);
  %p21spec_write_sheet(sheet = comments);
  %p21spec_write_sheet(sheet = documents);
ods excel close;
ods listing;

*------------------------------------------------------------------------------;
* Delete the lock-file ;
*------------------------------------------------------------------------------;
%let rc = %sysfunc(fdelete(_fn_lock));
