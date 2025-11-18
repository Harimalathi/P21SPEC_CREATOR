/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_write_sheet.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Write the specified dataset as a sheet to an existing ODS EXCEL
                  destination. 

Parameters:
  SHEET         : Name of the sheet to write - used to lookup meteada in the 
                  SHEET_METADATA.
  INDS          : Name of the input dataset to write 
					default: defdata.p21spec_&sheet.
  SHEET_METADATA: name of the sheet-metadata dataset.
                    default: defdata.spec_sheet_meta
*******************************************************************************/

%macro p21spec_write_sheet(
  sheet = ,
  inds = defdata.p21spec_&sheet.,
  sheet_metadata=defdata.spec_sheet_meta
);

* Create macro variables with propper-cased sheet name, list of column names ;
* and 'proc report define statements' based on values from the shee-metadata set;
proc sql noprint;
  select
    order,
    sheet,
    name,
    catx(' ', 'define', name, '/ display', quote(strip(label)))
  into
    : _nowhere_,
    : _sheetname,
    : _namelist separated by ' ',
    : _definestmt separated by ';'
  from &sheet_metadata.
  where upcase(sheet) eq upcase("&sheet.") and write_ignore ne 1
  order by order;
quit;

* Initiate the sheet;
ods excel style = analysis options(
  frozen_headers = 'yes'
  sheet_name = "&_sheetname."
  embedded_titles = 'off'
);

* 'report' the dataset. Setting backgroud of the header row to darkblue, to ;
* clearly differentiate it from the entry-file. Also put usage notes in the ;
* Define-sheet (instructing not to update this file) in bold red text ;
proc report data=&inds. style(header)=[textalign=left verticalalign=top backgroundcolor=darkblue color=white];
  column &_namelist.;
  &_definestmt.;
  %if %upcase(&sheet.) eq %str(DEFINE) %then %do;
    compute attribute;
      if upcase(ATTRIBUTE) eq "USAGENOTE" then
        call define(_row_,"style","style={color=red fontweight=bold}");
    endcomp;
  %end;
  run;
%mend;
