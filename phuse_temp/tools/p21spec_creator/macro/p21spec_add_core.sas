/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_add_core.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Replaces "core group" rows with the actual variable-rows
                  as define for the "core source"
                  - Set COMMON to 'Y' for core group variables from ADSL/ADSLPRE 
                    (both for the ADSLPRE/ADSL and the destination datasets)
                  - For core variables in the destination datasets; 
                      - Set ORIGIN to 'Predecessor' and PREDECESSOR to 
                        [name].[dataset] of the source dataset.
                      - Clear METHOD and COMMENT (this is explained for the 
                        predecessor variable)
                  - If the string '[DOMAIN]' exists in any of the variables specified
                    in DOMAIN_SPECIFIC_VARIABLES paramter, it will be replaced by the
                    value of the DATASET variable; 
                    (e.g., if PARAM and PARAMCD is part of a "BDS core group" their
                    codelists can be set to CL_[DOMAIN]_PARAM and CL_[DOMAIN]_PARMACD,
                    when to core goupr is expanded to e.g., ADLB and ADVS the codelists
                    will be CL_ADLB_PARAM/CL_ADLB_PARAMCD and CL_ADVS_PARAM/CL_ADVS_PARAMCD.
                    (assuming CODELIST is included in DOMAIN_SPECIFIC_VARIABLE).

Parameters:
  inds : (library.)name of the input dataset to be porcesed
  domain_specific_variables : Space separated list of variables where the value will
    have the keyword '[DOMAIN]' replace by the value of the DEMAIN_KEY_VARIABLE when
    expanded to core-groups.
    [Default=assigned_value codelist]
  outds : (library.)name of the output dataset to be created.
  cleanup : when set to Y, all datasets created in the work library by this macro
    (except for the OUTDS) will be deleted.
    [Default=Y]
  auto_order : specifies how to populate the 'order' variable in the output dataset
    'entry_dc' (entry order, dataset + core): for each dataset, the variables are
      ordered by the sequence in the entry-seet. Core-variabels placed in a single
      block, in the position of the CORE-placeholder variable. Internally core-variabels
      are ordered by their position in the core-defintion dataset
      (this is currently the only valid option)
    '[blank]' (missing or and unknown option): relies on the 'order' variable in the
      entry-sheet... might cause unexpecetd/unwanted result (especially when core
      groups are defined)
    [Default = entry_d]
*******************************************************************************/

%macro p21spec_add_core(
  inds=, 
  domain_specific_variables = assigned_value codelist,
  outds= ,
  common_src_domains = ADSLPRE ADSL,
  auto_order = entry_dc,
  cleanup = Y
);

* Declare "static variables" that are not supposed to be change (hence not in the macro ;
* definition) but kept as variables for potential furture use/expansion ;
%let group_key_variable=variable;
%let domain_key_variable=dataset;

%p21spec_cleanwork(mode = get);

* Extract subset of rows that referes a 'core group';
data core_group_references;
  length core_group $50;
  set &inds.;
  where scan(&group_key_variable.,1,'.') eq ':CORE';
  keep _read_order &domain_key_variable. core_group;
  rename _read_order = __core_group_order;
  core_group = scan(variable,2,'.');
run;

* Extract subset of rows that defines a 'core group';
data core_group_definitions;
  set &inds. (rename=core_group=__tmp_core_group);
  where not missing(__tmp_core_group);
  drop &domain_key_variable.;
  rename _read_order = __core_variable_order;
  length core_group $50;
  core_group = cats(dataset, __tmp_core_group);

  * Set COMMON to 'Y' for variables originating from ADSLPRE or ADSL;
  if upcase(dataset) in ('ADSLPRE', 'ADSL') then common = 'Y';
  
  * Set ORGIGIN to predecessor/value to the "core-sourece";
  * and clear method/comment;
  origin = 'Predecessor';
  predecessor = upcase(catx('.',dataset,variable));
  call missing(method, comment);

run;

* Join reference- and definiiton sets, creating a set wiht all 'core rows'  in the refered 'core group';
proc sql feedback;
  create table expanded_core_group_raw as select * 
  from core_group_definitions natural 
  full join core_group_references
  order by &domain_key_variable., __core_group_order, __core_variable_order;
quit;

* Stack the 'source set' (excluding rows that refers a core goup) and the expanded core-group set);
data expanded_core_group;
  length core_group __read_dc_order $50;
  set
    &inds. (where=(scan(&group_key_variable.,1,'.') ne ':CORE') in=a)
    expanded_core_group_raw(in=c)
  ;

  * Put a note on core variables propagated to other datasets;
  if not missing(core_group) then do;
    if a then _core_variable_note = catx(':','SOURCEDS', dataset, core_group);
    if c then _core_variable_note = catx(':','TARGET. FROM', core_group, predecessor);
  end;

  * Exclude observations with missing DOMAIN_KEY_VARIABLE (can occure if a core-group is ;
  * defined but not reffered);
  if missing(&domain_key_variable.) then delete;
 
  * Set COMMON to 'Y' for variables in ADSLPRE/ADSL that are part of a core gorup;
  if a and indexw(upcase("&common_src_domains."), upcase(dataset)) and not missing(core_group) then common = 'Y';

  * Create a "dataset+core read order variable" based on the actual order in the entry sheet, ;
  * CORE_GROUP_ORDER is the _READ_ORDER of the "core group reference row(s)" and CORE_VARIABLE_ORDER ;
  * is the _READ_ORDER of the core group variables.;
  if cmiss(__core_group_order, __core_variable_order) eq 0 then 
    __read_dc_order=catx('.', __core_group_order, __core_variable_order);
  else __read_dc_order = _read_order;

  * Loop over 'domain specific rows' pertainig to core-groups and replace the '[DOMAIN]' placehodler :
  * with the actual domain value;
  array replace_domain &domain_specific_variables.;
  if not missing(core_group) then do __i = 1 to dim(replace_domain);
    if indexw(replace_domain[__i],'[DOMAIN]') then replace_domain[__i] = tranwrd(replace_domain[__i],'[DOMAIN]',&domain_key_variable.);
  end;
run;

* Append the read-order of the datasets from then input dataset ;
proc sql;
  create table expanded_core_group_dsord as select *
  from expanded_core_group
  natural left join (select distinct min(_read_order) as _dataset_order, dataset from &inds. group by dataset);
quit;

%if %upcase("&auto_order.") eq "ENTRY_DC" %then %do;
  * Sort by the dataset- and 'dataset+core read order' variables;
  proc sort data=expanded_core_group_dsord sortseq=linguistic(numeric_collation=on)
    out=expanded_core_group_rawsort;
    by _dataset_order __read_dc_order dataset;
  run;

  * Reset order to 1 for each new dataset and increas by 1 for each variable;
  data outds_prepsort;
    set expanded_core_group_rawsort;
    by _dataset_order __read_dc_order dataset;
 
    retain __neworder __core_group_dsorder 0;
    if dataset ne lag(dataset) then do;
      __neworder = 1;
      __core_group_dsorder = __core_group_dsorder+1;
    end;
    else __neworder=__neworder+1;

    order = put(__neworder,best.-l);
    * core_group_dsorder = put(__core_group_dsorder,best.-l);
  run;

  proc sort data=outds_prepsort(
      where=(not missing(dataset))
    )out=outds_sorted sortseq=linguistic(numeric_collation=on);
    by _dataset_order dataset order;
  run;
%end;
%else %do;
  proc sort data=expanded_core_group_dsord(
      where=(not missing(dataset))
    )out=outds_sorted sortseq=linguistic(numeric_collation=on);
    by _dataset_order &domain_key_variable. order;
  run;
%end;

* write the final work dataset;
data &outds.;
  set outds_sorted;
  drop core_group __:;
run;

* Update Gloable DS-name variable;
%let _LASTDS_VARIABLES = &outds.;

* Clean up work;
%p21spec_cleanwork(
  mode = clean,
  exception = &outds.
);

%mend;


