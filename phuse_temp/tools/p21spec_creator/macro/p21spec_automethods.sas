/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_automethods.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Reads "method related columns" (from Variables or ValueLevel
                  sheets), "move" them to the Methods sheet and create referencs
                  (ID values to link Methods to the Variable/ValueLevel sheet).
Parameters:
  INDS_MAIN     : Name of the input dataset containing the inline methods data.
  INDS_METHODS  : Name of the input dataset containing the Methods sheet data.
  OUTDS_MAIN    : Name of the output 'main' dataset with the created method ID. 
  OUTDS_METHODS : Name of the Method sheet dataset updated with methods created
                    from the main datset inline methods.
  ID_SUFFIX     : Suffix to add to the auto-generated method-ID.
  NAME_PREFIX   : Prefix to add to the auto-generated method-Name.
  TYPE          : Default TYPE for the method - can be overruled by starting the
                  Methoc column in the 'main' sheet with either 'computation:' or
                  'imputation:' - TYPE will be set to the specified word.
*******************************************************************************/

%macro p21spec_automethods(
  inds_main=,
  inds_methods=,
  outds_main=,
  outds_methods=,
  id_suffix=automet,
  name_prefix=%str(Syntax for ),
  type =%str(Computation),
  cleanup=Y
);

%p21spec_cleanwork(mode = get);

* Add identifier to VARIABLES-sheet where METHOD is already defined in the METHODS-sheet ;
proc sql noprint;
  create table automethods_variables_prep as select 
    a.*,
    not missing(m.id) as __in_methods     
  from &inds_main. as a
  left join (select distinct id from &inds_methods.) as m
  on upcase(m.id) eq upcase(a.method);
quit;

* "move" specified VARIABLES.METHOD_-columns to a temporary dataset and ;
* generate other required METHODS-columns ;
data 
  &outds_main. (drop = __:)
  automethods_methods (
    where=(not missing(id))
    keep = __: drop = __in_methods 
    rename = (
      __read_order = _read_order
      __id = id
      __name = name
      __type = type
      __description = description
      __expression_context = expression_context
      __expression_code = expression_code
      __document = document
      __pages = pages
    )
  );
  set automethods_variables_prep;
  if (not missing(cats(method, method_expression_context, method_expression_code, method_document, method_pages)))
    and __in_methods ne 1 then do;
    * Create the columns for the method sheet;
    __id = upcase(catx('_', dataset, variable, "&id_suffix."));
    __name = "&name_prefix." || upcase(catx('.', dataset, variable));
    __expression_context = method_expression_context;
    __expression_code = method_expression_code;
    __document = method_document;
    __pages = method_pages;
    __read_order = _read_order;
    * If the 'inline method' begins wiht computation or imputation followed by a colon,;
    * set type to that word - otherwise falla back to the specifed type-parameter ;
    if upcase(strip(scan(method,1,':'))) in ('COMPUTATION', 'IMPUTATION') then do;
      __type =  propcase(strip(scan(method,1,':')));
      __description = substr(method,index(method,':')+1);
    end;
    else do;
      __type = "&type.";
      __description = method;
    end;
    * Replace VARIABLES.METHOD (now used as method description) with the generated id;
    * and clear the ohter VARIABLES.METHOD_-variables ; 
    method = __id;
    call missing(of method_:); 
  end;
run;


* Add the generated methods to the method sheet - making sure to use then longest length of each variable in the two sets;
proc sql noprint; 
  select distinct 
    strip(name) || ' $' || strip(put(max(length),best.)) into :_length_stmt separated by ' '
  from dictionary.columns
  where memname  eq "AUTOMETHODS_METHODS"
    or memname eq %upcase("&inds_methods.")
    or catx('.', libname, memname) eq %upcase("&inds_methods.")
  group by name
  ;
quit;

data &outds_methods.;
  length &_length_stmt.;
  set &inds_methods. automethods_methods;
run;

* Update Gloable DS-name variable;
%if %upcase( %scan(%str(&inds_main.), 1, %str(_), %str(b) )) eq %str(VARIABLES) %then %do;
  %let _LASTDS_VARIABLES = &outds_main.;
%end;
%else %if %upcase( %scan(%str(&inds_main.), 1, %str(_), %str(b) )) eq %str(VALUELEVEL) %then %do;
  %let _LASTDS_VALUELEVEL = &outds_main.;
%end;
%else %do;
  %put %str(E)RROR: Unexpected value of parameter INDS_MAIN ;
%end; 
%let _LASTDS_METHODS = &outds_methods.;

* Clean up work;
%p21spec_cleanwork(
  mode = clean,
  exception = &outds_main. &outds_methods.
);

%mend;
