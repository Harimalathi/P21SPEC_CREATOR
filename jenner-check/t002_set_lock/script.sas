/*******************************************************************************
  Bundle: p21spec_set_lock

  Exercises the p21spec_creator concurrency guard %p21spec_set_lock. The macro
  writes a lock file (containing &sysuserid and the current date/time) when none
  exists, and creates the fileref _fn_lock the driver later uses to release it.
  This bundle runs the "acquire" path: with no lock present the macro writes the
  lock file, and we read it back to confirm the guard took effect.

  The macro body is copied verbatim from macro/p21spec_set_lock.sas; only the
  lockfile path is made relative (the driver passes an absolute Windows path
  built from its run folder).
*******************************************************************************/

/* --- Macro body, copied verbatim from macro/p21spec_set_lock.sas --- */
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

/* --- Acquire the lock (none exists yet) --- */
%p21spec_set_lock(lockfile=%str(./lock.p21spec_creator));

/* --- Confirm the guard wrote a lock file --- */
data _null_;
  infile "./lock.p21spec_creator" truncover;
  input line $char80.;
  put "LOCK ACQUIRED; contents: " line;
run;
