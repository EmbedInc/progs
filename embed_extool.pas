{   Program EMBED_EXTOOL
*
*   Set up environment variables, links, and other system state required for the
*   Embed Inc software to work with external tools.
}
program embed_extool;
%include 'base.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}
  tree_lev_show = 3;                   {levels into tree to show search dirs}

type
  objtype_k_t = (                      {list of search modifier flags}
    objtype_file_k,                    {search target can be a file}
    objtype_dir_k);                    {search target can be a directory}
  objtype_t = set of objtype_k_t;

var
  reboot: boolean;                     {state was changed that requires reboot}
  clist: string_list_t;                {list of candidate directory treenames}
  clist_open: boolean;                 {string list CLIST has been initialized}
  tnam, tnam2:                         {scratch pathnames}
    %include '(cog)lib/string_treename.ins.pas';
  swinst:                              {installation directory of the ext software}
    %include '(cog)lib/string_treename.ins.pas';
  ii: sys_int_machine_t;               {scratch integer}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';
  mplab_installed: boolean;

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  retry_mplab, done_mplab;
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
*   Subroutine SEARCH_FOR_OBJ (TREE, NAME, LIST, OBJTYPE, STAT)
*
*   Search for file system objects of a particular name within a directory tree.
*   TREE is the root of the directory tree to search within.
*
*   NAME is the name of the object to search for.  NAME is a Pascal string.
*
*   The treenames of objects matching the criteria are added to the end of the
*   strings list LIST.  LIST must be previously initialized.
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
}
procedure search_for_obj (             {search for file system objects of a name}
  in      tree: string_treename_t;     {root directory of tree to search in}
  in      name: string;                {name that objects must match}
  in out  list: string_list_t;         {results will be added to this list}
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
  tnam: string_treename_t;             {treename of current directory entry}
  finfo: file_info_t;                  {info about current directory entry}

begin
  fnam.max := size_char(fnam.str);     {init local var strings}
  tnam.max := size_char(tnam.str);

  file_open_read_dir (dir, conn, stat); {open the root directory}
  if sys_error(stat) then return;

  while true do begin                  {loop over the entries of this directory}
    tnam.len := 0;                     {init to dir entry pathname not set}
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
            (objtype_file_k in objtype) and then {searching for a file ?}
            string_equal(fnam, snam)   {matches the search name ?}
            then begin
          list.size := conn.tnam.len;
          string_list_line_add (list); {create new list entry}
          string_copy (conn.tnam, list.str_p^); {fill in new list entry}
          end;
        end;

file_type_dir_k: begin                 {subdirectory}
        string_pathname_join (conn.tnam, fnam, tnam); {make treename of subdirectory}
        if
            (objtype_dir_k in objtype) and then {searching for a directory ?}
            string_equal(fnam, snam)   {matches the search name ?}
            then begin
          list.size := tnam.len;
          string_list_line_add (list); {create new list entry}
          string_copy (tnam, list.str_p^); {fill in new list entry}
          end;
        if lev <= tree_lev_show then begin {show this directory as search activity ?}
          writeln ('':(lev*2), fnam.str:fnam.len);
          end;
        process_dir (tnam, lev+1, stat); {process subdirectory recursively}
        end;

      end;                             {end of object type cases}
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

  string_treename (tree, tnam);        {make full treename of directory to search}
  string_vstring (snam, name, size_char(name)); {save var string name to look for}

  writeln ('Searching ', tnam.str:tnam.len);

  string_list_pos_last (list);         {to end of list, new entries added here}
  process_dir (tnam, 1, stat);         {process the top directory and everything below it}
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
  string_append1 (tnam, '/');          {make full link value}
  string_appends (tnam, swintarg);
  string_treename (tnam, targ);        {make absolute link value}

  file_link_create (                   {create the link}
    name, targ, [file_crea_overwrite_k], stat);
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
  mplab_installed := false;            {init to MPLAB hooks not installed}

{*******************************************************************************
*
*   Set up hooks for MPLAB 8 bit tools.
}
retry_mplab:
  writeln;
  sys_message ('stuff', 'inst_ask_mplab');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_mplab_fail');
    goto done_mplab;
    end;

  clist_init;                          {init search results list}

  search_for_obj (                     {search for dir holding the tools}
    tnam,                              {top of tree to search in}
    'mpasmx',                          {name to search for}
    clist,                             {list to add results to}
    [objtype_dir_k],                   {search target it directory}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_mplab;                  {back and ask the user again}
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

  if clist.n = 0 then begin            {no matching directories found ?}
    sys_message ('stuff', 'inst_nodirs'); {complain about it}
    goto retry_mplab;                  {go back and ask again}
    end;
{
*   Check for more than one suitable directory was found.  Make the user pick
*   the right one.
}
  ii := 1;                             {init to list entry number to use}

  if clist.n > 1 then begin            {multiple matches found ?}
    writeln;
    sys_message ('stuff', 'inst_dirs_mult');

    while true do begin                {keep asking user until get resolution}
      writeln;
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
      if ii = 0 then goto retry_mplab; {back for another search ?}
      if (ii >= 1) and (ii <= clist.n) {got a valid answer ?}
        then exit;
      end;
    end;

  string_list_pos_abs (clist, ii);     {go to the selected list entry}
  string_pathname_split (              {save software installation dir in SWINST}
    clist.str_p^, swinst, tnam);
  string_list_kill (clist);            {delete the candidate directories list}
  clist_open := false;

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_mplab_found', msg_parm, 1);
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

done_mplab:

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
