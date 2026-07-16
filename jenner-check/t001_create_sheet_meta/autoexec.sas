/* cap input rows for the captured run */
options obs=100;

/* p21spec_creator sets these options in its driver; kept here so the bundle
   runs the macro in the same environment as the tool. */
options validvarname=upcase nomprint nosource mcompilenote=all;

/* The tool writes spec_sheet_meta to its 'defdata' library; for a self-contained
   run we point that at WORK. */
libname defdata (work);
