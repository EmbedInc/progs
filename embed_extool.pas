{   Program EMBED_EXTOOL
*
*   Set up environment variables, links, and other system state required for the
*   Embed Inc software to work with external tools.
}
program embed_extool;
%include 'base.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}
  tree_lev_show = 2;                   {levels into tree to show search dirs}

type
  objtype_k_t = (                      {list of search modifier flags}
    objtype_file_k,                    {search target can be a file}
    objtype_dir_k);                    {search target can be a directory}
  objtype_t = set of objtype_k_t;

  evar_p_t = ^evar_t;
  evar_t = record                      {data for one environment variable}
    next_p: evar_p_t;                  {points to next variable in the list}
    name_p: string_var_p_t;            {points to variable name string}
    val_p: string_var_p_t;             {points to variable value string}
    end;

  varset_t = record                    {values for a set of environment variables}
    mem_p: util_mem_context_p_t;       {points to private mem context for this list}
    n: sys_int_machine_t;              {number of variables in the list}
    first_p: evar_p_t;                 {points to first list entry}
    last_p: evar_p_t;                  {points to last list entry}
    end;

var
  reboot: boolean;                     {state was changed that requires reboot}
  clist: string_list_t;                {list of candidate directory treenames}
  clist_open: boolean;                 {list CLIST has been initialized}
  notdir: string_list_t;               {list of disallowed subdirectories}
  notdir_open: boolean;                {list NOTDIR has been initialized}
  show_search: boolean;                {enabled showing search progress to user}
  tnam, tnam2:                         {scratch pathnames}
    %include '(cog)lib/string_treename.ins.pas';
  lnam:                                {scratch leafname}
    %include '(cog)lib/string_leafname.ins.pas';
  swinst:                              {installation directory of the ext software}
    %include '(cog)lib/string_treename.ins.pas';
  buf:                                 {one line buffer, command line, etc}
    %include '(cog)lib/string8192.ins.pas';
  ii: sys_int_machine_t;               {scratch integer}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';
  finfo: file_info_t;                  {information about a file}
  time: sys_clock_t;                   {scratch time value}
  tf: boolean;                         {True/False returned by subordinate program}
  exstat: sys_sys_exstat_t;            {subordinate program's exit status code}
  vars_bef: varset_t;                  {variables state "before"}
  vars_aft: varset_t;                  {variables state "after"}
  evar_p: evar_p_t;                    {pointer to current variable definition}
  ev_p: evar_p_t;                      {scratch pointer to a variable definition}
  conn: file_conn_t;                   {scratch connection to a file}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  retry_mplab8, done_mplab8, retry_mplab16, done_mplab16,
  retry_msvc, msvc_dir_ok1, msvc_dir_keep, msvc_dir_del,
  done_msvcdbg, msvc_next_var, done_msvc;
{
********************************************************************************
*
*   Subroutine CLIST_INIT
*
*   Create and initialize the global strings list CLIST.  If CLIST already
*   exists, then it is first deleted before being re-created.
}
procedure clist_init;                  {create and init CLIST}
  val_param; internal;

begin
  if clist_open then begin             {the list already exists ?}
    string_list_kill (clist);          {not anymore}
    end;

  string_list_init (clist, util_top_mem_context); {create the list}
  clist_open := true;                  {list now exists}
  end;
{
********************************************************************************
*
*   Subroutine NOTDIR_INIT
*
*   Create and initialize the global strings list NOTDIR.  If NOTDIR already
*   exists, then it is first deleted before being re-created.
}
procedure notdir_init;                 {create and init NOTDIR}
  val_param; internal;

begin
  if notdir_open then begin            {the list already exists ?}
    string_list_kill (notdir);         {not anymore}
    end;

  string_list_init (notdir, util_top_mem_context); {create the list}
  notdir_open := true;                 {list now exists}
  end;
{
********************************************************************************
*
*   Subroutine NOTDIR_NONE
*
*   Make sure the list of disallowed subdirectories does not exist.  If the list
*   exists, it is deleted.
}
procedure notdir_none;                 {make sure NOTDIR does not exist}
  val_param; internal;

begin
  if notdir_open then begin            {the list exists ?}
    string_list_kill (notdir);         {delete it}
    notdir_open := false;
    end;
  end;
{
********************************************************************************
*
*   Subroutine SEARCH_FOR_OBJ (TREE, NAME, OBJTYPE, STAT)
*
*   Search for file system objects of a particular name within a directory tree.
*   TREE is the root of the directory tree to search within.
*
*   NAME is the name of the object to search for.  NAME is a Pascal string.  The
*   search is performed case-independently.
*
*   The treenames of objects matching the criteria are written to the strings
*   list CLIST.  CLIST will be initialized, then any search results added.  The
*   previous state of CLIST is irrelevant (as long as it is correctly indicated
*   by CLIST_OPEN).
*
*   OBJTYPE is a set of flags that indicate the matching file system object
*   types:
*
*     OBJTYPE_FILE_K
*
*       The file system object being searched for may be a file.  In that case,
*       the resulting LIST entry will be the treename of the parent directory
*       containing the file.
*
*     OBJTYPE_DIR_K
*
*       The file system object being searched for may be a directory.  In that
*       case, the resulting LIST entry will be the complete treename of the
*       directory.
*
*   If the list NOTDIR exists, as indicated by NOTDIR_OPEN, then it is taken as
*   a list of directories that are not allowed.  When a subdirectory is found
*   that matches at least one of the NOTDIR entries, that subdirectory is
*   ignored.
*
*   If the global switch SHOW_SEARCH is set to TRUE, then search progress is
*   shown to the user.  This is the default.  If SHOW_SEARCH is FALSE, then the
*   search is performed silently this time, but SHOW_SEARCH is reset to TRUE.
}
procedure search_for_obj (             {search for file system objects of a name}
  in      tree: string_treename_t;     {root directory of tree to search in}
  in      name: string;                {name that objects must match}
  in      objtype: objtype_t;          {types of matching file system objs}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  tnam: string_treename_t;             {full pathname of root directory}
  snam: string_leafname_t;             {name of object to search for}
{
******************************
*
*   Subroutine PROCESS_DIR (DIR, LEV, STAT)
*   This routine is local to SEARCH_FOR_DIR.
*
*   Process a directory tree recursively.  DIR is the top name of the directory
*   tree to process.  LEV is the current nesting level.  The original call to
*   this routine is passed 1 in LEV, which is incremented by one each additional
*   recursion level.
}
procedure process_dir (                {process a directory tree}
  in      dir: string_treename_t;      {root directory of the tree to process}
  in      lev: sys_int_machine_t;      {nesting level, top call is passed 1}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  conn: file_conn_t;                   {connection to the directory}
  fnam: string_leafname_t;             {name of this directory entry}
  fnamu: string_leafname_t;            {upper case directory entry name}
  tnam: string_treename_t;             {treename of current directory entry}
  finfo: file_info_t;                  {info about current directory entry}
  added_dir: boolean;                  {already added this directory as result}

label
  next_ent;

begin
  fnam.max := size_char(fnam.str);     {init local var strings}
  fnamu.max := size_char(fnamu.str);
  tnam.max := size_char(tnam.str);
  added_dir := false;                  {init to this directory not a search result}

  file_open_read_dir (dir, conn, stat); {open the root directory}
  if sys_error(stat) then return;

  while true do begin                  {loop over the entries of this directory}
    file_read_dir (                    {get next entry in this directory}
      conn,                            {connection to the directory}
      [file_iflag_type_k],             {we need to know type of this entry}
      fnam,                            {returned entry name}
      finfo,                           {additional information about the entry}
      stat);
    if file_eof(stat) then exit;       {exhausted the directory ?}
    if sys_error(stat) then next;      {skip this entry on error}
    case finfo.ftype of                {what kind of file system object is this ?}

file_type_data_k: begin                {ordinary file}
        if
            (not added_dir) and        {didn't already add this directory ?}
            (objtype_file_k in objtype) {searching for a file ?}
            then begin
          string_upcase (fnam);        {upper case for case-insensitive matching}
          if string_equal(fnam, snam) then begin
            string_list_str_add (clist, conn.tnam); {add dir to results list}
            added_dir := true;         {this directory has been added as search result}
            end;                       {end of name matches search pattern}

          end;
        end;                           {end of this object is a file case}

file_type_dir_k: begin                 {subdirectory}
        string_copy (fnam, fnamu);     {make upper case version of entry name}
        string_upcase (fnamu);
        string_pathname_join (conn.tnam, fnam, tnam); {make treename of subdirectory}

        if
            (objtype_dir_k in objtype) and then {searching for a directory ?}
            string_equal(fnamu, snam)  {matches the search name ?}
            then begin
          string_list_str_add (clist, tnam); {add this dir to results list}
          end;

        if                             {show this directory as search activity ?}
            show_search and
            (lev <= tree_lev_show)
            then begin
          writeln ('':(lev*2), fnam.str:fnam.len);
          end;
        {
        *   Ignore this entry if it matches a disallowed subdirectory name.
        }
        if notdir_open then begin      {there is a list of disallowed dirs ?}
          string_list_pos_abs (notdir, 1); {go to first list entry}
          while notdir.str_p <> nil do begin {scan list of disallowed dirs}
            if string_equal (fnamu, notdir.str_p^) {matches disallowed ?}
              then goto next_ent;      {ignore this directory entry}
            string_list_pos_rel (notdir, 1); {to next disallowed name}
            end;
          end;

        process_dir (tnam, lev+1, stat); {process subdirectory recursively}
        end;

      end;                             {end of object type cases}
next_ent:                              {done with this directory entry, advance to next}
    end;                               {back to do next directory entry}

  file_close (conn);                   {close the directory}
  end;
{
******************************
*
*   Start of executable code of SEARCH_FOR_DIR.
}
begin
  tnam.max := size_char(tnam.str);     {init local var string}
  snam.max := size_char(snam.str);

  clist_init;                          {init search results list}

  string_treename (tree, tnam);        {make full treename of directory to search}
  string_vstring (snam, name, size_char(name)); {save var string name to look for}
  string_upcase (snam);                {upper case for case-independent matching}

  if show_search then begin
    writeln;
    writeln ('Searching ', tnam.str:tnam.len);
    end;

  process_dir (tnam, 1, stat);         {process the top directory and everything below it}
  show_search := true;                 {restore to default}

  if show_search then begin
    writeln;
    end;
  end;
{
********************************************************************************
*
*   Function REQUIRED_FILE (NAME)
*
*   Check that the file NAME exists in the directory named by the current entry
*   of the list CLIST.  NAME is a Pascal string, not a var string.
*
*   If the file exists, then the function returns TRUE and does nothing else.
*
*   If the file does not exist, the function returns FALSE.  The current CLIST
*   entry is deleted, and the position advanced to the next sequential entry.
}
function required_file (               {check for file in dir of CLIST curr entry}
  in      name: string)                {name of file within the directory}
  :boolean;                            {file exists, CLIST entry not deleted}
  val_param; internal;

var
  tnam: string_treename_t;             {full pathname of the file}

begin
  tnam.max := size_char(tnam.str);     {init local var string}

  string_copy (clist.str_p^, tnam);    {init pathname with directory name}
  string_append1 (tnam, '/');
  string_appends (tnam, name);         {add leafname to make full pathname}

  if file_exists (tnam) then begin     {the file exists ?}
    required_file := true;             {indicate the file exists}
    return;
    end;

  required_file := false;              {indicate the file does not exist}
  string_list_line_del (clist, true);  {delete this entry, advance to next}
  end;
{
********************************************************************************
*
*   Subroutine ENSURE_DIR (DIR, STAT)
*
*   Ensure that the directory DIR exists.  DIR is a Pascal string.  All
*   directories in the path will be created if they do not already exist.  DIR
*   is first translated according to the Embed portable pathname rules before
*   the directory path is determined.
}
procedure ensure_dir (                 {ensure a directory exists}
  in      dir: string;                 {directory name, Embed rules}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  tdir: string_treename_t;             {full absolute treename of the directory}
  tnam: string_treename_t;             {scratch treename}
  lnam: string_leafname_t;             {one entry in directory path}
  finfo: file_info_t;                  {info about a file, used for file type}
  path: string_list_t;                 {list of names in directory path}

label
  abort;

begin
  tdir.max := size_char(tdir.str);     {init local var strings}
  tnam.max := size_char(tnam.str);
  lnam.max := size_char(lnam.str);
  sys_error_none (stat);

  string_vstring (tnam, dir, size_char(dir)); {make var string DIR}
  string_treename (tnam, tdir);        {make full absolute pathname in TDIR}
{
*   The full target directory name is in TDIR.
}
  if file_exists (tdir) then begin     {target already exists ?}
    file_info (                        {get information about the target object}
      tdir,                            {name of object to get info about}
      [file_iflag_type_k],             {requesting file type}
      finfo,                           {returned info about the ojbect}
      stat);
    if sys_error(stat) then return;
    if finfo.ftype = file_type_dir_k   {is a directory ?}
      then return;                     {yes, nothing to do here}
    {
    *   The target object exists, but is not a directory.  Delete it, then
    *   proceed as if the target object does not yet exist.
    }
    file_delete_tree (tdir, [], stat); {delete the object}
    if sys_error(stat) then return;
    end;
{
*   The target directory does not exist.
}
  string_list_init (path, util_top_mem_context); {init non-existing path list}

  repeat                               {scan backwards until last existing dir}
    string_pathname_split (tdir, tnam, lnam); {separate leaf dir into LNAM}
    string_copy (tnam, tdir);          {update path with leaf dir removed}
    string_list_str_add (path, lnam);  {add leaf dir to list of dirs to create}
    until file_exists (tdir);          {back if the remaining path still doesn't exist}
{
*   TDIR contains the initial part of the path that does exist.  The remaining
*   pathname components are in the list PATH in local to global order.
*
*   Now walk backwards thru PATH and create each directory in the list.
}
  string_list_pos_last (path);         {to first pathname component}
  while path.str_p <> nil do begin     {loop over the non-existing components}
    string_pathname_join (tdir, path.str_p^, tnam); {make treename of this component}
    file_create_dir (                  {create this next directory in the path}
      tnam, [file_crea_overwrite_k], stat);
    if sys_error(stat) then goto abort;
    string_copy (tnam, tdir);          {update path that exists so far}
    string_list_pos_rel (path, -1);    {go to next component to create}
    end;                               {back to do this new component}

abort:                                 {PATH exists, STAT all set}
  string_list_kill (path);             {delete the PATH list}
  end;
{
********************************************************************************
*
*   Subroutine EXTERN_LINK (EXTNAME, SWINTARG, STAT)
*
*   Create a symbolic link somewhere in the Embed EXTERN directory tree.
*   EXTNAME is the name of the link within (cog)extern.  SWINTARG is the target
*   of the link within the directory named in SWINST.
}
procedure extern_link (                {create link in Embed EXTERN tree}
  in      extname: string;             {name of link within (cog)extern}
  in      swintarg: string;            {link target within SWINST dir}
  out     stat: sys_err_t);            {completion status}

var
  name: string_treename_t;             {link name}
  targ: string_treename_t;             {link target}
  tnam: string_treename_t;             {scratch pathname}

begin
  name.max := size_char(name.str);     {init local var strings}
  targ.max := size_char(targ.str);
  tnam.max := size_char(tnam.str);

  string_vstring (name, '(cog)extern/'(0), -1); {init fixed part of link name}
  string_appends (name, extname);      {make full link name}

  string_copy (swinst, tnam);          {init fixed part of link value}
  string_vstring (targ, swintarg, size_char(swintarg)); {make var string arg}
  if targ.len > 0 then begin           {SWINTARG not the empty string ?}
    string_append1 (tnam, '/');        {make full link value}
    string_append (tnam, targ);
    end;
  string_treename (tnam, targ);        {make absolute link value}

  writeln ('Linking ', name.str:name.len, ' --> ', targ.str:targ.len);
  file_link_create (                   {create the link}
    name, targ, [file_crea_overwrite_k], stat);
  end;
{
********************************************************************************
*
*   Function PICK_RESULT
*
*   Pick the appropriate entry from the search results list, CLIST.
*
*   If there are 0 entries in the list, then the MSG_NONE message is emitted and
*   the function returns FALSE.
*
*   If there is exactly 1 entry in the CLIST is set to that entry and the
*   function returns TRUE.
*
*   If there are multiple entries in the list, then the user is asked to pick
*   one.  If this is successful, CLIST is returned set to the selected entry,
*   and the function returns TRUE.  If the user wants to retry the whole
*   search, the function returns FALSE.  This last case can be distinguished
*   from the 0 search results case by looking at the number of list entries,
*   CLIST.N.
}
function pick_result
  :boolean;                            {success, CLIST set to selected entry}
  val_param; internal;

var
  ii: sys_int_machine_t;               {entry number}

begin
  pick_result := false;                {init to not returning with result}

  if clist.n = 0 then begin            {search results list is empty ?}
    sys_message ('stuff', 'inst_nodirs');
    writeln;
    return;
    end;

  ii := 1;                             {init to list entry number to use}

  if clist.n > 1 then begin            {multiple matches found ?}
    sys_message ('stuff', 'inst_dirs_mult');
    writeln;
    while true do begin                {keep asking user until get resolution}
      string_list_pos_abs (clist, 1);  {go to first list entry}
      while clist.str_p <> nil do begin {once for each list entry}
        writeln (clist.curr, ': ', clist.str_p^.str:clist.str_p^.len);
        string_list_pos_rel (clist, 1); {advance to next list entry}
        end;
      writeln;
      sys_message ('stuff', 'inst_dirs_pick'); {tell user to pick a directory}
      string_prompt (string_v('>> '));
      string_readin (tk);              {get the user's response into TK}
      if tk.len <= 0 then next;        {no answer, ask again ?}
      string_t_int (tk, ii, stat);     {try to interpret response as integer}
      if sys_error(stat) then next;    {invalid response, ask again ?}
      if ii = 0 then return;           {back for another search ?}
      if (ii >= 1) and (ii <= clist.n) {got a valid answer ?}
        then exit;
      end;
    end;

  string_list_pos_abs (clist, ii);     {go to the selected list entry}
  pick_result := true;                 {indicate returning with selection}
  end;
{
********************************************************************************
*
*   Subroutine SHOW_LIST (LIST, COMMENT)
*
*   This routine is for debugging only.  The contents of the strings list LIST
*   will be shown to standard output, after the short comment COMMENT and the
*   number of list entries.
}
(*
procedure show_list (                  {show list contents, for debugging}
  in out  list: string_list_t;         {the list to show contents of}
  in      comment: string);            {comment to show above list of entries}
  val_param; internal;

var
  tk: string_var80_t;                  {scratch token}

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_vstring (tk, comment, size_char(comment)); {make var string comment}

  writeln;
  write (tk.str:tk.len, '  ', list.n, ' entries');
  if list.n = 0
    then write ('.')
    else write (':');
  writeln;

  string_list_pos_abs (list, 1);
  while list.str_p <> nil do begin
    writeln ('  ', list.str_p^.str:list.str_p^.len);
    string_list_pos_rel (list, 1);
    end;

  writeln;
  end;
*)
{
********************************************************************************
*
*   Subroutine PATH_CLIST (STR)
*
*   Parse the directories path string STR into its separate components, and
*   write them to the strings list CLIST.  CLIST will be initialized as needed.
*   Its previous state is irrelevant.
*
*   STR is assumed to be separate entries separated by semicolons (;).
}
(*
procedure path_clist (                 {parse path string into CLIST}
  in      str: univ string_var_arg_t); {the path string to parse}
  val_param; internal;

var
  p: string_index_t;                   {input string parse index}
  tnam: string_treename_t;             {one path component parsed from input string}
  delim: sys_int_machine_t;            {number of delimiter used to find token}
  stat: sys_err_t;

begin
  tnam.max := size_char(tnam.str);     {init local var string}
  clist_init;                          {make sure CLIST exist, init to empty}

  p := 1;                              {init the parse index}
  while true do begin                  {back here each new path component}
    string_token_anyd (                {parse next component from input string}
      str,                             {input string}
      p,                               {parse index}
      ';',                             {list of token delimiters}
      1,                               {number of delimiters in the list}
      0,                               {first N delimiters that can repeat}
      [string_tkopt_padsp_k],          {strip leading and trailing blanks from token}
      tnam,                            {token parsed from input string}
      delim,                           {1-N number of delimiter actually used}
      stat);
    if string_eos(stat) then exit;     {hit end of input string ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_list_str_add (clist, tnam); {add this component to the list}
    end;                               {back to get next component}
  end;
*)
{
********************************************************************************
*
*   Subroutine VARSET_DEL (VARS)
*
*   Delete the set of environment variable definitions, VARS.  This deallocates
*   any system resources used by VARS.  This routine must only be called if
*   VARS has been created.
}
procedure varset_del (                 {delete environment variables definitions}
  in out  vars: varset_t);             {definitions to deallocate resources of}
  val_param; internal;

begin
  util_mem_context_del (vars.mem_p);   {deallocate all dynamic memory of VARS}
  end;
{
********************************************************************************
*
*   Subroutine VARSET_READ (FNAM, VARS, MEM, STAT)
*
*   Reads the environment variable settings from the file FNAM, and creates the
*   set of variable definitions VARS from them.  MEM is the parent memory
*   context.  A subordinate memory context will be created, and all dynamic
*   memory for the VARS allocated under it.
*
*   Each line of the input file has the format:
*
*     <varname>=<value>
*
*   This is the result, for example, of capturing the standard output of the SET
*   command in the CMD command shell to a file.
*
*   When the routine returns without error, VARS is always created, even if
*   empty.  When the routine returns with error, VARS is uninitialized, meaning
*   it has no memory context allocated to it.
}
procedure varset_read (                {create env varset from file}
  in      fnam: string_treename_t;     {input file with env var definitions}
  out     vars: varset_t;              {resulting env var set}
  in out  mem: util_mem_context_t;     {parent memory context, will make sub}
  out     stat: sys_err_t);            {completion status}

var
  conn: file_conn_t;                   {connection to the input file}
  in_open: boolean;                    {the input file is open}
  vars_crea: boolean;                  {VARS created}
  buf: string_var8192_t;               {one line input buffer}
  p: string_index_t;                   {input line parse index}
  name: string_var132_t;               {variable name}
  vval: string_var8192_t;              {variable value}
  pick: sys_int_machine_t;             {number of delimiter picked from list}
  evar_p: evar_p_t;                    {points to current variable definition}

label
  abort;

begin
  buf.max := size_char(buf.str);       {init local var strings}
  name.max := size_char(name.str);
  vval.max := size_char(vval.str);
  in_open := false;                    {init to input file not open}
  vars_crea := false;                  {init to VARS not created}

  file_open_read_text (fnam, '', conn, stat); {open the input file}
  if sys_error(stat) then goto abort;
  in_open := true;                     {indicate the input file is now open}

  util_mem_context_get (mem, vars.mem_p); {init VARS}
  vars_crea := true;                   {indicate VARS has mem context}
  vars.n := 0;                         {init VARS}
  vars.first_p := nil;
  vars.last_p := nil;

  while true do begin                  {back here each new input file line}
    file_read_text (conn, buf, stat);  {read next line from the input file}
    if file_eof(stat) then exit;       {hit end of the file ?}
    if sys_error(stat) then goto abort; {hard error ?}
    string_unpad (buf);                {delete trailing spaces from input line}
    if buf.len = 0 then next;          {ignore blank lines}
    if buf.str[1] = '*' then next;     {ignore comment lines}
    p := 1;                            {init input line parse index}

    string_token_anyd (                {get the variable name token}
      buf, p,                          {input string and parse index}
      '=', 1,                          {delimiters}
      0,                               {first N delimiters that can repeat}
      [string_tkopt_padsp_k],          {strip leading and trailing spaces from token}
      name,                            {returned token}
      pick,                            {num of delim picked from list (unused)}
      stat);
    if sys_error(stat) then goto abort;

    string_substr (                    {get rest of input line as variable value}
      buf, p, buf.len, vval);
    if vval.len = 0 then next;         {this variable doesn't really exist ?}

    util_mem_grab (                    {allocate mem for descriptor of this new var}
      sizeof(evar_p^), vars.mem_p^, false, evar_p);

    string_alloc (                     {allocate and link var name string}
      name.len, vars.mem_p^, false, evar_p^.name_p);
    string_copy (name, evar_p^.name_p^); {save variable name}

    string_alloc (                     {allocate and link var value string}
      vval.len, vars.mem_p^, false, evar_p^.val_p);
    string_copy (vval, evar_p^.val_p^); {save variable value}

    evar_p^.next_p := nil;             {link this variable def to end of list}
    if vars.last_p = nil
      then begin                       {this is first list entry}
        vars.first_p := evar_p;
        end
      else begin                       {adding to end of existing list}
        vars.last_p^.next_p := evar_p;
        end
      ;
    vars.last_p := evar_p;             {update pointer to last list entry}
    vars.n := vars.n + 1;              {count one more variable in the list}
    end;                               {back for next input file line}

  file_close (conn);                   {close the input file}
  return;                              {normal return point}

abort:                                 {abort with error, STAT already set}
  if in_open then begin                {input file is open ?}
    file_close (conn);                 {close it}
    end;
  if vars_crea then begin              {VARS has been created}
    varset_del (vars);                 {delete it}
    end;
  end;
{
********************************************************************************
*
*   Function VAR_FIND (VARS, NAME, EVAR_P)
*
*   Find the variable names NAME in the variables set VARS.  If the variable is
*   found, then the function returns TRUE and EVAR_P points to the descriptor
*   for that variable.  If the variable is not found, then the function returns
*   FALSE and EVAR_P is set to NIL.
*
*   Variable names are compared in a case-insenstive manner.
}
function var_find (                    {find particular variable in var set}
  in      vars: varset_t;              {the var set to look in}
  in      name: univ string_var_arg_t; {name of variable to look for}
  out     evar_p: evar_p_t)            {pointer to var if found, else NIL}
  :boolean;                            {variable was found}
  val_param; internal;

var
  uname: string_var132_t;              {upper case search name}
  vu: string_var132_t;                 {upper case name of candicate var}

begin
  uname.max := size_char(uname.str);   {init local var strings}
  vu.max := size_char(vu.str);
  var_find := true;                    {init to variable was found}

  string_copy (name, uname);           {make upper case for case-independent match}
  string_upcase (uname);

  evar_p := vars.first_p;              {init pointer to first variable in the list}
  while evar_p <> nil do begin         {scan the variables in the list}
    string_copy (evar_p^.name_p^, vu); {make upper case for case-independent match}
    string_upcase (vu);
    if string_equal (vu, uname) then return; {found the target variable ?}
    evar_p := evar_p^.next_p;          {no, advance to next list entry}
    end;                               {back to check this new list entry}

  var_find := false;                   {indicate that the variable was not found}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_end_abort;             {no command line args allowed}

  reboot := false;                     {init to reboot not required}
  clist_open := false;                 {list of candidate directories is not open}
  notdir_open := false;                {init to no list of disallowed directories}
  show_search := true;                 {init to show any search progress}

{*******************************************************************************
*
*   Set up hooks for MPLAB and the 8 bit tools.
}
retry_mplab8:
  writeln;
  writeln;
  sys_message ('stuff', 'inst_mplab_ask');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_mplab_fail');
    goto done_mplab8;
    end;

  notdir_init;                         {create list of disallowed directories}
  string_list_str_add (notdir,
    string_v('ROLLBACKBACKUPDIRECTORY'(0))
    );
  search_for_obj (                     {search for dir holding the tools}
    tnam,                              {top of tree to search in}
    'mpasmx',                          {name to search for}
    [objtype_dir_k],                   {search target is a file}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_mplab8;                 {back and ask the user again}
    end;
{
*   This list of candidate directories matching the search name is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}
    if not required_file ('mpasmx.exe') then next;
    if not required_file ('mplib.exe') then next;
    if not required_file ('mplink.exe') then next;
    string_list_pos_rel (clist, 1);    {this dir checks out, advance to next}
    end;

  if not pick_result then goto retry_mplab8; {didn't get a suitable directory}

  string_pathname_split (              {up to top MPLAB installation dir}
    clist.str_p^, swinst, tnam);

  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_mplab_found', msg_parm, 1);
  writeln;
{
*   The MPLAB installation directory name is in SWINST.  Now install the hooks.
}
  ensure_dir ('(cog)extern/mplab', stat); {make sure this EXTERN subdir exists}
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/ide.exe', 'mplab_platform/bin/mplab_ide.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/mpasm.exe', 'mpasmx/mpasmx.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/mplib.exe', 'mpasmx/mplib.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/mplink.exe', 'mpasmx/mplink.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

done_mplab8:

{*******************************************************************************
*
*   Set up hooks for MPLAB 16 bit tools.
}
retry_mplab16:
  writeln;
  writeln;
  sys_message ('stuff', 'inst_mplab16_ask');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_mplab_fail');
    goto done_mplab16;
    end;

  notdir_init;                         {create list of disallowed directories}
  string_list_str_add (notdir,
    string_v('ROLLBACKBACKUPDIRECTORY'(0))
    );
  search_for_obj (                     {search for dir holding the tools}
    tnam,                              {top of tree to search in}
    'xc16-gcc.exe',                    {name to search for}
    [objtype_file_k],                  {search target is a file}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_mplab16;                {back and ask the user again}
    end;
{
*   The list of directories containing the named file is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}
    if not required_file ('xc16-as.exe') then next;
    if not required_file ('xc16-ar.exe') then next;
    if not required_file ('xc16-ranlib.exe') then next;
    if not required_file ('xc16-ld.exe') then next;
    if not required_file ('xc16-bin2hex.exe') then next;
    string_list_pos_rel (clist, 1);    {this dir checks out, advance to next}
    end;

  if clist.n > 1 then begin            {found more than one directory ?}
    string_list_pos_abs (clist, 1);    {go to first list entry}
    string_copy (clist.str_p^, tnam);  {build pathname of the C compiler}
    string_appends (tnam, '/xc16-gcc.exe'(0));
    file_info (tnam, [file_iflag_dtm_k], finfo, stat); {get compiler date}
    sys_error_abort (stat, '', '', nil, 0);
    time := finfo.modified;            {init time of newest file so far}
    while true do begin                {scan the remaining list entries}
      string_list_pos_rel (clist, 1);  {advance to next list entry}
      if clist.str_p = nil then exit;  {hit end of list ?}
      string_copy (clist.str_p^, tnam); {build pathname of the C compiler}
      string_appends (tnam, '/xc16-gcc.exe'(0));
      file_info (tnam, [file_iflag_dtm_k], finfo, stat); {get compiler date}
      sys_error_abort (stat, '', '', nil, 0);
      if sys_clock_compare(finfo.modified, time) {newer ?}
          = sys_compare_gt_k then begin
        time := finfo.modified;        {update newest file found so far}
        end;
      end;                             {back to check next list entry}
    {
    *   The time of the newest C compiler executable file is in TIME.  Now
    *   delete all list entries that do not match this time.
    }
    string_list_pos_abs (clist, 1);    {go to first list entry}
    while clist.str_p <> nil do begin  {scan all the list entries}
      string_copy (clist.str_p^, tnam); {build pathname of the C compiler}
      string_appends (tnam, '/xc16-gcc.exe'(0));
      file_info (tnam, [file_iflag_dtm_k], finfo, stat); {get compiler date}
      sys_error_abort (stat, '', '', nil, 0);
      if sys_clock_compare(finfo.modified, time)
          = sys_compare_eq_k
        then begin                     {latest time, keep this entry}
          string_list_pos_rel (clist, 1); {advance to next entry}
          end
        else begin                     {different time, delete this entry}
          string_list_line_del (clist, true); {delete this, advance to next}
          end
        ;
      end;                             {back to process this new entry}
    end;

  if not pick_result then goto retry_mplab16; {didn't get a suitable directory ?}

  string_copy (clist.str_p^, swinst);  {save directory the target got installed in}

  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_mplab16_found', msg_parm, 1);
  writeln;
{
*   The MPLAB 16 bit tool executables are in SWINST.
}
  ensure_dir ('(cog)extern/mplab', stat); {make sure this EXTERN subdir exists}
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/asm16.exe', 'xc16-as.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/lib16.exe', 'xc16-ar.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/index16.exe', 'xc16-ranlib.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/link16.exe', 'xc16-ld.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/bin_hex16.exe', 'xc16-bin2hex.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/ccomp16.exe', 'xc16-gcc.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);
{
*   Add links for targets above the BIN directory.  SWINST currently contains
*   the pathname of the BIN directory.
}
  string_pathname_split (swinst, tnam, tnam2); {switch to parent of current dir}
  string_treename (tnam, swinst);

  extern_link ('mplab/support16', 'support', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/lib16', 'lib', stat);
  sys_error_abort (stat, '', '', nil, 0);
{
*   Install links to the linker file directories.  These are in SUPPORT/name.
}
  string_copy (swinst, tnam);          {go down into the SUPPORT directory}
  string_appends (tnam, '/support'(0));
  string_treename (tnam, swinst);

  extern_link ('mplab/gld24e', 'PIC24E/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/gld24f', 'PIC24F/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/gld24h', 'PIC24H/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/gld30f', 'dsPIC30F/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/gld33e', 'dsPIC33E/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('mplab/gld33f', 'dsPIC33F/gld', stat);
  sys_error_abort (stat, '', '', nil, 0);

done_mplab16:

{*******************************************************************************
*
*   Set up hooks for Microsoft Visual Studio C compiler and related.
}
retry_msvc:
  writeln;
  writeln;
  sys_message ('stuff', 'inst_msvc_ask');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_msvc_fail');
    goto done_msvc;
    end;

  notdir_none;                         {no list of disallowed directories}
  search_for_obj (                     {search for dir holding the tools}
    tnam,                              {top of tree to search in}
    'cl.exe',                          {name to search for}
    [objtype_file_k],                  {search target is a file, not directory}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_msvc;                   {back and ask the user again}
    end;
{
*   This list of candidate directories matching the search name is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}
    if not required_file ('lib.exe') then next;
    if not required_file ('link.exe') then next;
    {
    *   The executable tools seem to be stored in different flavors of what
    *   machines they run on, and what machines they produce code for.  We want
    *   the Win32 executables that produce Win32 executables.
    *
    *   In old versions of VC the Win32-->Win32 executables were stored in a
    *   directory just called "bin", with the other flavors in subdirectories
    *   with names indicating the flavor, like "amd64_arm", "x86_amd64", etc.
    *
    *   Newer versions of VC seem to use separate directories for the host
    *   architecture, then subdirectories in those for the target architectures.
    *   Examples are "Hostx64/x64", "Hostx86/x64", etc.
    *
    *   Therefore, we accept any directory path ending in "bin", or those ending
    *   in two directories with names that both end in "x86".
    }
    string_pathname_split (clist.str_p^, tnam, lnam); {split off lowest dir}
    string_upcase (lnam);
    if string_equal (lnam, string_v('BIN'(0))) {matches old style ?}
      then goto msvc_dir_ok1;

    string_substr (lnam, lnam.len-2, lnam.len, tk); {get last 3 chars of dir}
    if not string_equal (tk, string_v('X86'(0))) {not the right target machine ?}
      then goto msvc_dir_del;

    string_pathname_split (tnam, tnam2, lnam); {get next higher dir name}
    string_substr (lnam, lnam.len-2, lnam.len, tk); {get last 3 chars of dir}
    string_upcase (tk);
    if not string_equal (tk, string_v('X86'(0))) {not the right host machine ?}
      then goto msvc_dir_del;
msvc_dir_ok1:                          {passed host and target machine tests}

msvc_dir_keep:                         {this dir checks out}
    string_list_pos_rel (clist, 1);    {advance to next list entry}
    next;                              {back to process this new list entry}

msvc_dir_del:                          {delete this directory from the list}
    ii := clist.curr;                  {save number of entry being deleted}
    string_list_line_del (clist, true); {delete this results list entry}
    if ii > clist.curr then exit;      {just deleted last list entry ?}
    end;                               {back to process next list entry}

  if not pick_result then goto retry_msvc; {didn't get a suitable directory ?}

  string_copy (clist.str_p^, swinst);  {save software installation dir in SWINST}
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_msvc_found_exe', msg_parm, 1);
  writeln;
{
*   The MSVC installation directory name is in SWINST.  Now install the hooks.
}
  ensure_dir ('(cog)extern/msvc', stat); {make sure this EXTERN subdir exists}
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('msvc/cl.exe', 'cl.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('msvc/lib.exe', 'lib.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

  extern_link ('msvc/link.exe', 'link.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);
{
****************************************
*
*   Go up the tree to the VC directory, then look there for the VCVARSALL.BAT
*   script.
}
  while true do begin                  {keep going up until get to the VC directory}
    string_pathname_split (swinst, tnam, lnam); {split off the lowest directory}
    string_upcase (lnam);
    if string_equal (lnam, string_v('VC'(0))) {the SWINST dir is the VC directory ?}
      then exit;
    string_copy (tnam, swinst);        {up one level for next iteration}
    end;                               {back to check this new level}
  string_copy (swinst, tnam);          {save top level VC directory}

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_msvc_found', msg_parm, 1);

  show_search := false;                {don't show this search to the user}
  search_for_obj (                     {search for the VCVARSALL script}
    swinst,                            {tree to seach in}
    'vcvarsall.bat',                   {file to search for}
    [objtype_file_k],                  {target is a file, not directory}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  if clist.n = 0 then begin            {file not found ?}
    sys_message ('stuff', 'inst_msvc_n_vcvars');
    goto done_msvc;
    end;

  string_list_pos_abs (clist, 1);      {go to the first results list entry}
  string_copy (clist.str_p^, swinst);

  extern_link ('msvc/vcvarsall.bat', 'vcvarsall.bat', stat);
  sys_error_abort (stat, '', '', nil, 0);
{
****************************************
*
*   Go up one more level, then look for the debugger, DEVENV.EXE.  The top level
*   VC directory is in TNAM.
}
  string_pathname_split (tnam, tnam2, lnam); {go up one directory level}

  show_search := false;                {do this search silently}
  search_for_obj (                     {search for debugger executable}
    tnam2,                             {top of tree to search in}
    'devenv.exe',                      {name to search for}
    [objtype_file_k],                  {search target is a file, not directory}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  if clist.n < 1 then begin
    sys_message ('stuff', 'inst_msvc_debug0');
    goto done_msvcdbg;
    end;
  if clist.n > 1 then begin
    sys_message ('stuff', 'inst_msvc_debugn');
    goto done_msvcdbg;
    end;

  string_list_pos_abs (clist, 1);      {make the single list entry current}
  string_copy (clist.str_p^, swinst);  {save software installation dir in SWINST}

  extern_link ('msvc/debugger.exe', 'devenv.exe', stat);
  sys_error_abort (stat, '', '', nil, 0);

done_msvcdbg:
{
****************************************
*
*   Run the MSVC_INIT script that is private to this program.  The script does
*   some more setup.
*
*   MSVC_INIT also writes out all the environment variables before and after
*   calling the MSVC VCVARSALL script to files VARS_BEF and VARS_AFT.  The
*   two set of environment variable settings are compared, and the difference
*   is written to the SET_VARS.BAT file.  SET_VARS.BAT then effectively does
*   what VCVARSALL.BAT does, but specific to this system and this setup.  This
*   can be significantly faster, especially with newer versions of MSVC that
*   do a lot of looking around and checking in VCVARSALL.BAT.
}
  string_vstring (buf, 'cmd.exe /c'(0), -1); {init command line to run}
  string_vstring (                     {Embed pathname of script to run}
    tnam, '(cog)progs/embed_extool/msvc/msvc_init.bat'(0), -1);
  string_treename (tnam, tnam2);       {make absolute pathname}
  string_append_token (buf, tnam2);    {add path as single token to command line}

  writeln;
  writeln ('Running VCVARSALL.BAT');
  sys_run_wait_stdsame (               {run the command, use our std I/O}
    buf,                               {the command to run}
    tf,                                {True/False returned by program}
    exstat,                            {exit status code of the program}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  writeln;
  writeln ('Creating SET_VARS.BAT');
{
*   Read the VARS_BEF and VARS_AFT files written by the MSVC_INIT script.
}
  string_vstring (tnam, '(cog)progs/embed_extool/msvc/vars_bef'(0), -1);
  varset_read (                        {get state of variables before VCVARSALL}
    tnam,                              {file to read from}
    vars_bef,                          {var set to create}
    util_top_mem_context,              {parent mem context}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  writeln ('  ', vars_bef.n, ' vars before');

  string_vstring (tnam, '(cog)progs/embed_extool/msvc/vars_aft'(0), -1);
  varset_read (                        {get state of variables after VCVARSALL}
    tnam,                              {file to read from}
    vars_aft,                          {var set to create}
    util_top_mem_context,              {parent mem context}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  writeln ('  ', vars_aft.n, ' vars after');
{
*   Write the SET_VARS.BAT script.  This sets all the variable as left by
*   VCVARSALL, but does so directly and efficiently.  It also sets a few
*   variables used by the Embed build environment.
}
  string_vstring (tnam,                {name of file to write}
    '(cog)extern/msvc/set_vars.bat'(0), -1);
  file_open_write_text (               {open the file}
    tnam, '.bat',                      {file name and suffix}
    conn,                              {returned connection to the file}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  {
  *   Write the variables used by the Embed build environment.  These are:
  *
  *     compiler  -  Pathname of the MSVC compiler executable.
  *     librarian  -  Pathname of the MSVC librarian executable.
  *     linker  -  Pathname of the MSVC linker executable.
  }
  string_vstring (buf, 'set compiler='(0), -1); {define COMPILER}
  string_vstring (tnam, '(cog)extern/msvc/cl.exe'(0), -1);
  string_treename (tnam, tnam2);
  string_append (buf, tnam2);
  file_write_text (buf, conn, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_vstring (buf, 'set librarian='(0), -1); {define LIBRARIAN}
  string_vstring (tnam, '(cog)extern/msvc/lib.exe'(0), -1);
  string_treename (tnam, tnam2);
  string_append (buf, tnam2);
  file_write_text (buf, conn, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_vstring (buf, 'set linker='(0), -1); {define LINKER}
  string_vstring (tnam, '(cog)extern/msvc/link.exe'(0), -1);
  string_treename (tnam, tnam2);
  string_append (buf, tnam2);
  file_write_text (buf, conn, stat);
  sys_error_abort (stat, '', '', nil, 0);
  {
  *   Compare the AFT list of variables to the BEF list of variables.  Write any
  *   variable to the SET_VARS.BAT file if they were created or changed.
  }
  evar_p := vars_aft.first_p;          {init to first AFTER variable}
  while evar_p <> nil do begin         {scan all the AFTER variables}
    if var_find (vars_bef, evar_p^.name_p^, ev_p) then begin {BEFORE var exists ?}
      if string_equal(ev_p^.val_p^, evar_p^.val_p^) {var not changed ?}
        then goto msvc_next_var;
      end;
    {
    *   The current variable was created or altered from before.  Write the new
    *   definition to the output file.
    }
    string_vstring (buf, 'set '(0), -1); {init this output line}
    string_append (buf, evar_p^.name_p^); {variable name}
    string_append1 (buf, '=');
    string_append (buf, evar_p^.val_p^); {variable value}
    file_write_text (buf, conn, stat);
    sys_error_abort (stat, '', '', nil, 0);

msvc_next_var:                         {advance to next variable in AFTER list}
    evar_p := evar_p^.next_p;
    end;                               {back to check this new variable}

  file_close (conn);                   {done writing the SET_VARS.BAT file}

  varset_del (vars_bef);               {delete the variables states}
  varset_del (vars_aft);

done_msvc:

{*******************************************************************************
*
*   Make sure that /TEMP exists.  If not create a directory of that name.
}
  string_vstring (tnam, '/temp'(0), -1); {make expansion of /TEMP}
  string_treename (tnam, tnam2);
  if not file_exists(tnam2) then begin {/TEMP does not exist ?}
    writeln;
    writeln ('Creating /temp directory');
    file_create_dir (tnam, [file_crea_keep_k], stat);
    sys_error_abort (stat, 'stuff', 'inst_temp_create', nil, 0);
    end;

{*******************************************************************************
*
*   Common exit point.  Reboot if any system startup state was changed.
}
  if reboot then begin                 {changes made that require reboot ?}
    writeln;
    sys_message ('stuff', 'inst_reboot');
    string_readin (tnam);              {wait for user to hit ENTER}
    string_upcase (tnam);
    if not string_equal(tnam, string_v('NO')) then begin
      sys_reboot (stat);
      sys_error_abort (stat, '', '', nil, 0);
      end;
    end;
  end.
