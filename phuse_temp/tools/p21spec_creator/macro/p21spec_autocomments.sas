/*******************************************************************************
Project Name    : general (part of the p21spec_creator package)
Program Name    : p21spec_autocomments.sas
Program Author  : Thomas Gulholm-Hansen (TGUH)
Program Purpose : Reads "comment related columns" (from Variables or ValueLevel
                  sheets), "move" them to the Comments sheet and create referencs
                  (ID values to link Comments to the Variable/ValueLevel sheet).
Parameters:
  INDS_MAIN     : Name of the input dataset containing the inline comment data.
  INDS_COMMENTS : Name of the input dataset containing the Comments sheet data.
  OUTDS_MAIN    : Name of the output 'main' dataset with the created comment ID. 
  OUTDS_COMMENTS: Name of the Comments sheet dataset updated with comments created
                    from the main datset inline comments.
  ID_SUFFIX     : Suffix to add to the auto-generated comment-ID.
*******************************************************************************/

%macro p21spec_autocomments(
  inds_main=,
  inds_comments=,
  outds_main=,
  outds_comments=,
  id_suffix=autocom,
  cleanup=Y
);

%p21spec_cleanwork(mode = get);

* Add identifier to VARIABLES-sheet where COMMENT is already defined in the COMMENTS-sheet ;
proc sql noprint;
  create table autocomments_variables_prep as select 
    m.*,
    not missing(c.id) as __in_comments     
  from &inds_main. as m
  left join (select distinct id from &inds_comments.) as c
  on upcase(c.id) eq upcase(m.comment);
quit;

* "move" specified VARIABLES.COMMENT_-columns to a temporary comments-dataset;
* and use VARIABLES.COMMENT as 'Comment description' ;
data 
  &outds_main. (drop = __:)
  autocomments_comments (
    where=(not missing(id))
    keep = __: drop = __in_comments
    rename = (
      __read_order = _read_order
      __id = id
      __description = description
      __document = document
      __pages = pages
    )
  );
  set autocomments_variables_prep;
  if (not missing(cats(comment, comment_document, comment_pages)))
    and __in_comments ne 1 then do;
    * Create the columns for the comments sheet;
    __id = upcase(catx('_', dataset, variable, "&id_suffix."));
    __description = comment;
    __document = comment_document;
    __pages = comment_pages;
    __read_order = _read_order;
    * Replace VARIABLES.COMMENT (now used as comment description) with the generated id;
    * and clear the ohter VARIABLES.COMMENT_-variables ; 
    comment = __id;
    call missing(of comment_:); 
  end;
run;


* Add the generated comments to the comment sheet - making sure to use then longest length of each variable in the two sets;
proc sql noprint; 
  select distinct 
    strip(name) || ' $' || strip(put(max(length),best.)) into :_length_stmt separated by ' '
  from dictionary.columns
  where memname  eq "AUTOCOMMENTS_COMMENTS"
    or memname eq %upcase("&inds_comments.")
    or catx('.', libname, memname) eq %upcase("&inds_comments.")
  group by name
  ;
quit;

data &outds_comments.;
  length &_length_stmt.;
  set &inds_comments. autocomments_comments;
run;

* Update Gloable DS-name variable;
%if %index(%upcase(&inds_main.), %str(VARIABLES)) %then %do;
  %let _LASTDS_VARIABLES = &outds_main.;
%end;
%else %if %index(%upcase(&inds_main.), %str(VALUELEVEL)) %then %do;
  %let _LASTDS_VALUELEVEL = &outds_main.;
%end;
%else %do;
  %put %str(E)RROR: Unexpected value of parameter INDS_MAIN ;
%end; 
%let _LASTDS_COMMENTS = &outds_comments.;

* Clean up work;
%p21spec_cleanwork(
  mode = clean,
  exception = &outds_main. &outds_comments.
);


%mend;
