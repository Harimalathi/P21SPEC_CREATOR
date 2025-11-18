/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_cleanwork.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Keep the work library clean by recording exisitng datasets in
                  work in the beginning of a module and delete all new dataset
                  (except for specified exceptions) at the end of the module; 
Parameters      :
  ACTIVATE      : Must be set/resolve to Y for the macoro to actually run.
                  Default value is &cleanup., wihic is expecte to be a paramter
                  (which defaults to Y) in the module calling this macro. 
                  The intention is to make it easy to disable the celanup from
                  the driver program.
  MODE          : Set to GET when calling the macro in the beginning of a module
                  (to record datasets currently i WORK). Set to CLEAN when
                  calling the macro in the end of a module, to remove datasets
                  created by the module (except for the exceptions).
  EXCEPTION     : Space-separated list of datasets crated in work, that should
                  not be deleted (typicalliy this should be set to the [output
                  dataset] of the module.
  CONTENT_DS    : Not intended to be set by the user. Name of the datset used
                  to store the name of existing datasets.
*******************************************************************************/

%macro p21spec_cleanwork(
  activate = &cleanup.,
  mode = ,
  exception = ,
  content_ds = __preexec_workdata,
);

* Only run the macro if parameter ACTIVATE is set to 'Y' ;
* allowing easy diabling for debugging ;
%if %upcase(&activate.) eq %str(Y) %then %do;

  %if %upcase(&mode.) eq %str(GET) %then %do;
    * Get list of datasets currently in the work library ;
    proc sql noprint; 
      create table &content_ds. as
      select distinct memname
      from dictionary.tables
      where libname eq 'WORK'
      ;
    quit;
  %end;
  %else %if %upcase(&&mode.) eq %str(CLEAN) %then %do;
    * Crate a list if datsets added to the work-library since the 'content_ds' was created ;
    * and are not specified in the exception paramtere ;
    proc sql noprint;
      select distinct memname into :_kill_temp_list separated by %str(' ')
      from dictionary.tables
      where (
        (libname eq 'WORK')
        and (memname not in (select distinct memname from &content_ds.))
        and (not indexw(%upcase("&exception."), memname))
      );
    quit;

    * do the kill;
    %if %symexist(_kill_temp_list) %then %do;
      proc datasets lib=work nolist;
        delete &_kill_temp_list.;
      quit;
    %end;
  %end;
  %else %do;
    * Alert if unknown mode is specifed;
    %put %str(E)RROR: Invalid MODE is specified for macro P21SPEC_CLEANWORK, valid opitions are GET or CLEAN;
  %end;

%end;

%mend;
