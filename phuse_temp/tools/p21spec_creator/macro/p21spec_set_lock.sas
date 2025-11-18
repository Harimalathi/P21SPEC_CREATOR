/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_set_lock.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Write a 'lock file' (specified as paramter) containg the 
                  sysuserid and current date/time. If the file already
                  exists, an error is thrown, displaying the user and date/time
                  from the existing lock file, the further execution is aborted.
  
                  The macro creates a filename '_fn_lock' that can later be 
                  used in a fdelete statement to remove the lock.
Parameters:
  lockfile      : Full path and name of the lockfile
*******************************************************************************/

%macro p21spec_set_lock(lockfile=);

filename _fn_lock "&lockfile.";

%if %sysfunc(fileexist("&lockfile.")) %then %do;
  option linesize = 120;
  data _null_;
    length lockline $50 user $10 started $50;
    infile "&lockfile." truncover;
    input lockline $char50.;
    user = scan(lockline,1,';');
    started = '(started: ' || strip(scan(lockline,2,';')) || ')';

    put "%str(E)RROR: This user is already running p21spec_creator in this folder: " user started;
    put "%str(E)RROR: If you are positive the other user is actually NOT runnig p21spec_creator (i.e., confirmation";
    put "%str(E)RROR: from the user, or it was started LOOONG tim ago) you can delete the lockfile and re-run the program.";
    put "%STR(E)RROR:   &lockfile.";
    put "%str(E)RROR: This instance is terminating.";
  run; 
  %abort cancel;
%end;
%else %do;
  data _null_;
    file _fn_lock;
    lockline = "&sysuserid.;" || put(date(),date9.) || ' at ' || put(time(),tod5.);
    put lockline;
  run;
%end;
%mend;

