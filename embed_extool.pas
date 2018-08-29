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
  srch_k_t = (                         {list of search modifier flags}
    srch_parent_k);                    {save parent dir name, not search target}
  srch_t = set of srch_k_t;

var
  reboot: boolean;                     {state was changed that requires reboot}
  clist: string_list_t;                {list of candidate directory treenames}
  clist_open: boolean;                 {string list CLIST has been initialized}
  tnam, tnam2, tnam3:                  {scratch pathnames}
    %include '(cog)lib/string_treename.ins.pas';
  swinst:                              {installation directory of the ext software}
    %include '(cog)lib/string_treename.ins.pas';
  envvar:                              {environment variable name}
    %include '(cog)lib/string80.ins.pas';
  envval:                              {environment variable value}
    %include '(cog)lib/string8192.ins.pas';
  envflg: sys_envvar_t;                {set of flags about environment variables}
  ii: sys_int_machine_t;               {scratch integer}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';
  mplab_installed: boolean;

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  retry_mplab, done_mplab, retry_c30, c30_deldir, done_c30,
  retry_msvc, retry_vstudio, try_vstudio, done_vstudio, done_msvc;
{
********************************************************************************
*
*   Subroutine EXEC_PATH (EXDIR)
*
*   Ensure that EXDIR is in the command search path.  REBOOT is set to TRUE if
*   any system changes were made that require a reboot to take effect.  If the
*   path is already in the search list, then nothing is done.  If it is not,
*   then it is added at the end.
}
procedure exec_path (                  {add dir to command search path}
  in      exdir: string_treename_t);   {directory to add}
  val_param; internal;

var
  list: string_list_t;                 {search directories list}
  path: string_var8192_t;              {command search path string}
  envvar: string_var32_t;              {environment variable name}
  dir: string_treename_t;              {individual directory from search path}
  p: string_index_t;                   {PATH parse index}
  ii: sys_int_machine_t;               {scratch integer}
  eflg: sys_envvar_t;                  {flags about environment variable}
  tnam: string_treename_t;             {full treename of directory to add to list}
  tnam2: string_treename_t;            {scratch pathname}
  stat: sys_err_t;                     {completion status}

label
  leave;

begin
  path.max := size_char(path.str);     {init local var strings}
  envvar.max := size_char(envvar.str);
  dir.max := size_char(dir.str);
  tnam.max := sizeof(tnam.str);
  tnam2.max := sizeof(tnam2.str);

  string_vstring (envvar, 'PATH'(0), -1); {set environment variable name}
  sys_envvar_startup_get (             {get startup value for PATH environment var}
    envvar,                            {environment variable name}
    path,                              {returned value of the variable}
    eflg,                              {returned flags about the variable}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_list_init (list, util_top_mem_context); {init directories list structure}
  list.deallocable := false;           {we won't individually deallocate strings}
{
*   Parse PATH to build the list of directories in the executables search path.
}
  p := 1;                              {init PATH parse index}
  while true do begin                  {back here each new dir to parse from PATH}
    string_token_anyd (                {parse the next directory name from PATH}
      path,                            {input string}
      p,                               {parse index}
      ';', 1,                          {list of delimiters}
      0,                               {first N delimiters that may be repeated}
      [],                              {option flags}
      dir,                             {token parsed from PATH}
      ii,                              {number of defining delimiter (unused)}
      stat);
    if string_eos(stat) then exit;     {exhausted path string ?}
    sys_error_abort (stat, '', '', nil, 0);
    list.size := dir.len;              {set size needed for new list entry}
    string_list_line_add (list);       {make new list entry}
    string_copy (dir, list.str_p^);    {save this directory name in the list}
    end;                               {back to get next path entry}
{
*   Check the list for EXDIR already in it.
}
  string_treename (exdir, tnam);       {make full treename of desired directory}
  writeln ('Adding to path: ', tnam.str:tnam.len);

  string_list_pos_abs (list, 1);       {init to first list entry}
  while list.str_p <> nil do begin     {back here each new list entry}
    string_treename (list.str_p^, tnam2);
    if string_compare_opts (tnam2, tnam, [string_comp_ncase_k]) = 0 {already in path ?}
        then begin
      writeln ('  Already in path, not changed.');
      goto leave;
      end;
    string_list_pos_rel (list, 1);     {advance to next list entry}
    end;
{
*   The desired directory is not already in the commands search path.  Add it to
*   the end of the list.
}
  string_list_pos_last (list);         {go to last entry in the list}
  list.size := tnam.len;               {create new list entry}
  string_list_line_add (list);
  string_copy (tnam, list.str_p^);     {write desired dir into the new entry}
{
*   Create the PATH string from the new list and update the environment variable
*   with it.
}
  path.len := 0;                       {init path string to empty}
  string_list_pos_abs (list, 1);       {init to first list entry}
  while list.str_p <> nil do begin     {back here each new list entry}
    if path.len > 0 then begin
      string_append1 (path, ';');
      end;
    string_append (path, list.str_p^); {add this entry to end of path string}
    string_list_pos_rel (list, 1);     {advance to next list entry}
    end;

  reboot := reboot or sys_envvar_startup_set ( {update the PATH env variable}
    envvar,                            {environment variable name}
    path,                              {value to set it to}
    eflg,                              {preserve original flags}
    stat);

leave:                                 {common exit point}
  writeln ('Executable commands search path:');
  string_list_pos_abs (list, 1);       {init to first list entry}
  while list.str_p <> nil do begin     {back here each new list entry}
    writeln ('  ', list.str_p^.str:list.str_p^.len);
    string_list_pos_rel (list, 1);     {advance to next list entry}
    end;

  string_list_kill (list);             {deallocate list resources}
  end;
{
********************************************************************************
*
*   Subroutine ENV_SET (NAME, VAL)
*
*   Make sure the environment variable NAME is set to VAL.  REBOOT is set to
*   TRUE if any system state that requires a reboot to take effect is changed.
}
procedure env_set (                    {make sure environment variable set}
  in      name: univ string_var_arg_t; {environment variable name}
  in      val: univ string_var_arg_t); {value the variable must have}
  val_param; internal;

var
  old: string_var8192_t;               {old value, if any}
  eflg: sys_envvar_t;                  {env var modifier flags}
  ch: boolean;                         {startup setting was changed}
  stat: sys_err_t;

begin
  old.max := size_char(old.str);       {init local var string}

  writeln ('Environment variable: ', name.str:name.len);
  ch := false;                         {init to no startup state changed}

  sys_envvar_startup_get (name, old, eflg, stat);
  if file_not_found(stat)
    then begin                         {var does not already exist}
      writeln ('  Creating = "', val.str:val.len, '"');
      ch := sys_envvar_startup_set (   {create this variable}
        name,                          {variable name}
        val,                           {value}
        [sys_envvar_noexp_k],          {don't expand var references when used}
        stat);
      sys_error_abort (stat, '', '', nil, 0);
      end
    else begin                         {already exists or hard error}
      sys_error_abort (stat, '', '', nil, 0);
      if string_equal(old, val)
        then begin                     {already set to desired value}
          writeln ('  Already = "', old.str:old.len, '"');
          end
        else begin                     {exists, but not right value}
          writeln ('  Was = "', old.str:old.len, '"');
          writeln ('  Now = "', val.str:val.len, '"');
          ch := sys_envvar_startup_set ( {set to the new value}
            name,                      {environment variable name}
            val,                       {new value}
            [sys_envvar_noexp_k],      {don't expand var references when used}
            stat);
          sys_error_abort (stat, '', '', nil, 0);
          end
        ;
      end
    ;
  reboot := reboot or ch;              {reboot required on startup state change}
  end;
{
********************************************************************************
*
*   Subroutine SEARCH_FOR_DIR (TREE, NAME, FLAGS, LIST, STAT)
*
*   Search for subdirectories of a particular name within a directory tree.
*   TREE is the root of the directory tree to search within.  NAME is the name
*   of the subdirectory being searched for.  FLAGS is a set of flags that can
*   modify the search process and how the results are reported.  The treename of
*   each directory that matches the criteria is added to the string list LIST
*   in no particular order.  LIST must have been previously initialized.
*
*   The supported modifier flags are:
*
*     SRCH_PARENT_K  -  Save the name of the parent directory of subdirectories
*       matching the criteria.  The default is to save the subdirectory names.
}
procedure search_for_dir (             {search for subdirectories of a name}
  in      tree: string_treename_t;     {root directory of tree to search in}
  in      name: univ string_var_arg_t; {name that subdirectories must match}
  in      flags: srch_t;               {optional modifier flags}
  in out  list: string_list_t;         {results will be added to this list}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  tnam: string_treename_t;             {full pathname of root directory}
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
  sdir: string_treename_t;             {treename of current directory entry}
  finfo: file_info_t;                  {info about current directory entry}

begin
  fnam.max := size_char(fnam.str);     {init local var strings}
  sdir.max := size_char(sdir.str);

  file_open_read_dir (dir, conn, stat); {open the root directory}
  if sys_error(stat) then return;

  while true do begin                  {loop over the entries of this directory}
    sdir.len := 0;                     {init to dir entry pathname not set}
    file_read_dir (                    {get next entry in this directory}
      conn,                            {connection to the directory}
      [file_iflag_type_k],             {we need to know type of this entry}
      fnam,                            {returned entry name}
      finfo,                           {additional information about the entry}
      stat);
    if file_eof(stat) then exit;       {exhausted the directory ?}
    if sys_error(stat) then next;      {skip this entry on error}
    {
    *   The leafname of this directory entry is in FNAM.
    }
    if string_equal (fnam, name) then begin {this file matches target name ?}
      if srch_parent_k in flags
        then begin                     {save parent directory in list}
          list.size := conn.tnam.len;
          string_list_line_add (list); {create new list entry}
          string_copy (conn.tnam, list.str_p^); {fill in new list entry}
          end
        else begin                     {save the subdirectory name in list}
          string_pathname_join (conn.tnam, fnam, sdir); {make full pathname}
          list.size := sdir.len;
          string_list_line_add (list); {create new list entry}
          string_copy (sdir, list.str_p^); {add this subdirectory to the list}
          end
        ;
      end;
    if finfo.ftype <> file_type_dir_k then next; {skip if not subdirectory}
    {
    *   The current entry is a subdirectory.
    }
    if lev <= tree_lev_show then begin {show this directory as search activity ?}
      writeln ('':(lev*2), fnam.str:fnam.len);
      end;
    if sdir.len = 0 then begin         {full pathname not set yet ?}
      string_pathname_join (conn.tnam, fnam, sdir); {make full pathname}
      end;
    process_dir (sdir, lev+1, stat);   {process subdirectory recursively}
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

  string_treename (tree, tnam);        {make full treename of directory to search}
  writeln ('Searching ', tnam.str:tnam.len);

  string_list_pos_last (list);         {to end of list, new entries added here}
  process_dir (tnam, 1, stat);         {process the top directory and everything below it}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  reboot := false;                     {init to reboot not required}
  clist_open := false;                 {list of candidate directories is not open}
  mplab_installed := false;            {init to MPLAB hooks not installed}

{*******************************************************************************
*
*   Set up hooks for MPLAB.
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

  if clist_open then begin             {candidate list already exists ?}
    string_list_kill (clist);          {not anymore}
    end;
  string_list_init (clist, util_top_mem_context); {create candidate dirs list}
  clist_open := true;                  {list now exists}

  search_for_dir (                     {search for particular subdirectories}
    tnam,                              {top of tree to search in}
    string_v('MPASM Suite'),           {directory name to search for}
    [srch_parent_k],                   {save parent names of search targets}
    clist,                             {list to add results to}
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
    string_copy (clist.str_p^, tnam);  {build name of required subdirectory}
    string_append1 (tnam, '/');
    string_appends (tnam, 'MPLAB IDE'(0));
    if file_exists(tnam)
      then begin                       {required subdirectory exists}
        string_list_pos_rel (clist, 1);
        end
      else begin                       {subdirectory missing, not MPLAB dir}
        string_list_line_del (clist, true); {delete this line, advance to next}
        end
      ;
    end;

  if clist.n = 0 then begin            {not matching directories found ?}
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
  string_copy (clist.str_p^, swinst);  {save MPLAB installation directory name}
  string_list_kill (clist);            {delete the candidate directories list}
  clist_open := false;

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_mplab_found', msg_parm, 1);
{
*   The MPLAB installation directory name is in SWINST.  Now install the hooks.
*
*   Set up ASMPIC_SERV environment variable.  When this variable is "true", the
*   MPASM build script runs MPASMWIN in a background process via COGSERVE.  We
*   don't know whether the user always has COGSERVE running, so we only set this
*   variable to "false" if it doesn't already exist.  This documents the choice.
}
  string_vstring (envvar, 'asmpic_serv'(0), -1); {set environment variable name}
  writeln ('Environment variable: ', envvar.str:envvar.len);

  sys_envvar_startup_get (envvar, envval, envflg, stat); {get env var startup value}
  if file_not_found(stat)
    then begin                         {env var doesn't already exist}
      string_vstring (envval, 'false'(0), -1); {default value}
      writeln ('  Creating, set to "', envval.str:envval.len, '"');
      reboot := reboot or sys_envvar_startup_set ( {create the environment variable}
        envvar, envval, [sys_envvar_noexp_k], stat);
      sys_error_abort (stat, '', '', nil, 0);
      end
    else begin
      sys_error_abort (stat, '', '', nil, 0);
      writeln ('  Already = "', envval.str:envval.len, '"');
      end
    ;
{
*   Set up dsPICDir environment variable.
}
  string_vstring (envvar, 'dsPICDir'(0), -1); {set environment variable name}

  string_copy (swinst, tnam);          {make treename of dsPIC directory}
  string_appends (tnam, '/MPLAB ASM30 Suite'(0));
  string_treename (tnam, envval);
  env_set (envvar, envval);
{
*   Set up MPLABDir environment variable.
}
  string_vstring (envvar, 'MPLABDir'(0), -1); {set environment variable name}

  string_copy (swinst, tnam);          {make treename of dsPIC directory}
  string_appends (tnam, '/MPASM Suite'(0));
  string_treename (tnam, envval);
  env_set (envvar, envval);
{
*   Create the symbolic links to the linker file directories in SOURCE/DSPIC.
}
  string_vstring (tnam3, '(cog)source/dspic/'(0), -1); {directory to contain link}
  string_treename (tnam3, tnam);
  string_appends (tnam, '\gld24f'(0)); {add link leafname}

  string_copy (swinst, tnam3);         {make link target}
  string_appends (tnam3, '/MPLAB ASM30 Suite/support/pic24f/gld'(0));
  string_treename (tnam3, tnam2);

  writeln ('Creating link: ', tnam.str:tnam.len);
  writeln ('  --> ', tnam2.str:tnam2.len);
  file_link_create (                   {create symbolic link}
    tnam,                              {link pathname}
    tnam2,                             {link value}
    [file_crea_overwrite_k],           {overwrite if previously existing}
    stat);
  sys_error_abort (stat, '', '', nil, 0);


  string_vstring (tnam3, '(cog)source/dspic/'(0), -1); {directory to contain link}
  string_treename (tnam3, tnam);
  string_appends (tnam, '\gld24h'(0)); {add link leafname}

  string_copy (swinst, tnam3);         {make link target}
  string_appends (tnam3, '/MPLAB ASM30 Suite/support/pic24h/gld'(0));
  string_treename (tnam3, tnam2);

  writeln ('Creating link: ', tnam.str:tnam.len);
  writeln ('  --> ', tnam2.str:tnam2.len);
  file_link_create (                   {create symbolic link}
    tnam,                              {link pathname}
    tnam2,                             {link value}
    [file_crea_overwrite_k],           {overwrite if previously existing}
    stat);
  sys_error_abort (stat, '', '', nil, 0);


  string_vstring (tnam3, '(cog)source/dspic/'(0), -1); {directory to contain link}
  string_treename (tnam3, tnam);
  string_appends (tnam, '\gld30f'(0)); {add link leafname}

  string_copy (swinst, tnam3);         {make link target}
  string_appends (tnam3, '/MPLAB ASM30 Suite/support/dspic30f/gld'(0));
  string_treename (tnam3, tnam2);

  writeln ('Creating link: ', tnam.str:tnam.len);
  writeln ('  --> ', tnam2.str:tnam2.len);
  file_link_create (                   {create symbolic link}
    tnam,                              {link pathname}
    tnam2,                             {link value}
    [file_crea_overwrite_k],           {overwrite if previously existing}
    stat);
  sys_error_abort (stat, '', '', nil, 0);


  string_vstring (tnam3, '(cog)source/dspic/'(0), -1); {directory to contain link}
  string_treename (tnam3, tnam);
  string_appends (tnam, '\gld33f'(0)); {add link leafname}

  string_copy (swinst, tnam3);         {make link target}
  string_appends (tnam3, '/MPLAB ASM30 Suite/support/dspic33f/gld'(0));
  string_treename (tnam3, tnam2);

  writeln ('Creating link: ', tnam.str:tnam.len);
  writeln ('  --> ', tnam2.str:tnam2.len);
  file_link_create (                   {create symbolic link}
    tnam,                              {link pathname}
    tnam2,                             {link value}
    [file_crea_overwrite_k],           {overwrite if previously existing}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  mplab_installed := true;
done_mplab:                            {done installing hooks for MPLAB}

{*******************************************************************************
*
*   Set up hooks for the Microchip C30 compiler.  This can be installed in a
*   separate place from MPLAB.  This section is skipped if MPLAB (above) was
*   skipped.
}
  if not mplab_installed then goto done_c30; {no MPLAB, so skip C30 ?}

retry_c30:
  writeln;
  sys_message ('stuff', 'inst_ask_c30');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_c30_fail');
    goto done_c30;
    end;

  if clist_open then begin             {candidate list already exists ?}
    string_list_kill (clist);          {not anymore}
    end;
  string_list_init (clist, util_top_mem_context); {create candidate dirs list}
  clist_open := true;                  {list now exists}

  search_for_dir (                     {search for particular subdirectories}
    tnam,                              {top of tree to search in}
    string_v('bin'),                   {directory name to search for}
    [srch_parent_k],                   {save parent names of search targets}
    clist,                             {list to add results to}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_c30;                    {back and ask the user again}
    end;
{
*   This list of candidate directories matching the search name is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}

    string_pathname_split (clist.str_p^, tnam, tnam2); {last dir name must be "bin"}
    string_upcase (tnam2);
    if not string_equal (tnam2, string_v('BIN'))
      then goto c30_deldir;

    string_copy (clist.str_p^, tnam);  {check for ./pic30-gcc.exe}
    string_append1 (tnam, '/');
    string_appends (tnam, 'pic30-gcc.exe'(0));
    if not file_exists(tnam) then goto c30_deldir;

    string_list_pos_rel (clist, 1);    {leave this dir in list, advance to next}
    next;

c30_deldir:                            {delete the current list entry}
    string_list_line_del (clist, true); {delete this line, advance to next}
    end;

  if clist.n = 0 then begin            {not matching directories found ?}
    sys_message ('stuff', 'inst_nodirs'); {complain about it}
    goto retry_c30;                    {go back and ask again}
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
      if ii = 0 then goto retry_c30;   {back for another search ?}
      if (ii >= 1) and (ii <= clist.n) {got a valid answer ?}
        then exit;
      end;
    end;

  string_list_pos_abs (clist, ii);     {go to the selected list entry}
  string_pathname_split (              {save installation directory in SWINST}
    clist.str_p^, swinst, tnam);
  string_list_kill (clist);            {delete the candidate directories list}
  clist_open := false;

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_c30_found', msg_parm, 1);
{
*   The C30 installation directory name is in SWINST.  Now install the hooks.
*
*   Set up C30Dir environment variable.
}
  string_vstring (envvar, 'C30Dir'(0), -1); {set environment variable name}
  env_set (envvar, swinst);            {set the environment variable}

done_c30:                              {done installing hooks for the C30 compiler}

{*******************************************************************************
*
*   Set up hooks for Microsoft Visual C++ compiler.  This assumes version 6.0,
*   which is the last version released under subscription before the
*   subscription program was terminated in the mid 1990s.
}
retry_msvc:
  writeln;
  sys_message ('stuff', 'inst_ask_msvc');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_msvc_fail');
    goto done_msvc;
    end;

  if clist_open then begin             {candidate list already exists ?}
    string_list_kill (clist);          {not anymore}
    end;
  string_list_init (clist, util_top_mem_context); {create candidate dirs list}
  clist_open := true;                  {list now exists}

  search_for_dir (                     {search for particular subdirectories}
    tnam,                              {top of tree to search in}
    string_v('C1XX.DLL'),              {file name to search for}
    [srch_parent_k],                   {save parent names of search targets}
    clist,                             {list to add results to}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_msvc;                   {back and ask the user again}
    end;
{
*   This list of candidate directories containing the search name is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}
    {
    *   Must also contain CL.EXE.
    }
    string_copy (clist.str_p^, tnam);
    string_append1 (tnam, '/');
    string_appends (tnam, 'CL.EXE'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;
    {
    *   Must also contain LINK.EXE.
    }
    string_copy (clist.str_p^, tnam);
    string_append1 (tnam, '/');
    string_appends (tnam, 'LINK.EXE'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;
    {
    *   Switch to the parent directory.  The removed directory must be named
    *   BIN.
    }
    string_pathname_split (clist.str_p^, tnam, tnam2); {switch to parent dir}
    string_copy (tnam, clist.str_p^);
    string_upcase (tnam2);
    if not string_equal (tnam2, string_v('BIN')) then begin {subdir not BIN ?}
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;
    {
    *   Must also contain Include.
    }
    string_copy (clist.str_p^, tnam);
    string_append1 (tnam, '/');
    string_appends (tnam, 'Include'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;
    {
    *   Must also contain Lib.
    }
    string_copy (clist.str_p^, tnam);
    string_append1 (tnam, '/');
    string_appends (tnam, 'Lib'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;

    string_list_pos_rel (clist, 1);    {advance to next list entry}
    end;

  if clist.n = 0 then begin            {not matching directories found ?}
    sys_message ('stuff', 'inst_nodirs'); {complain about it}
    goto retry_mplab;                  {go back and ask again}
    end;
{
*   Check for more than one suitable directory was found.  Make the user pick
*   the right one if so.
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
      if ii = 0 then goto retry_msvc;  {back for another search ?}
      if (ii >= 1) and (ii <= clist.n) {got a valid answer ?}
        then exit;
      end;
    end;

  string_list_pos_abs (clist, ii);     {go to the selected list entry}
  string_copy (clist.str_p^, swinst);  {save MSVC installation directory name}
  string_list_kill (clist);            {delete the candidate directories list}
  clist_open := false;

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_msvc_found', msg_parm, 1);
{
*   The MSVC installation directory name is in SWINST.  Now install the hooks.
*
*   Set up MSVCDir environment variable.
}
  string_vstring (envvar, 'MSVCDir'(0), -1); {set environment variable name}
  string_treename (swinst, envval);
  env_set (envvar, envval);
{
*   Set up INCLUDE environment variable.
}
  string_vstring (envvar, 'include'(0), -1); {set environment variable name}

  string_copy (swinst, tnam);          {make treename of dsPIC directory}
  string_appends (tnam, '/Include'(0));
  string_treename (tnam, envval);
  env_set (envvar, envval);
{
*   Set up LIB_SYS environment variable.
}
  string_vstring (envvar, 'lib_sys'(0), -1); {set environment variable name}

  string_copy (swinst, tnam);          {make treename of dsPIC directory}
  string_appends (tnam, '/lib'(0));
  string_treename (tnam, envval);
  env_set (envvar, envval);
{
*   Find the Visual Studio part of the MSVC installation that is apparently
*   always put where it feels like regarless of what you enter.  We need to add
*   the MSDev98/bin directory in there to the command search path.
}
  string_vstring (tnam,                {tree to search in}
    '/Program Files/Microsoft Visual Studio'(0), -1);
  goto try_vstudio;                    {skip asking the user the first time}

retry_vstudio:                         {try looking for Visual Studio, path in TNAM}
  writeln;
  sys_message ('stuff', 'inst_ask_vstudio');
  string_prompt (string_v('>> '));
  string_readin (tnam);
  string_unpad (tnam);                 {remove trailing spaces}
  if tnam.len = 0 then begin           {entered blank ?}
    sys_message ('stuff', 'inst_vstudio_fail');
    goto done_vstudio;
    end;

try_vstudio:                           {TNAM contains name of tree to search}
  writeln;
  string_vstring (tnam2,               {target to search for}
    'MSDev98'(0), -1);

  if clist_open then begin             {candidate list already exists ?}
    string_list_kill (clist);          {not anymore}
    end;
  string_list_init (clist, util_top_mem_context); {create candidate dirs list}
  clist_open := true;                  {list now exists}

  search_for_dir (                     {search for particular subdirectories}
    tnam,                              {top of tree to search in}
    tnam2,                             {file name to search for}
    [],                                {save actual names of search targets}
    clist,                             {list to add results to}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then begin {couldn't open dir ?}
    goto retry_vstudio;                {back and ask the user again}
    end;
{
*   This list of candidate directories containing the search name is in CLIST.
*   Now apply additional criteria to possibly narrow the list.
}
  string_list_pos_abs (clist, 1);      {go to first list entry}
  while clist.str_p <> nil do begin    {scan all the list entries}
    {
    *   Must contain Bin.
    }
    string_copy (clist.str_p^, tnam);
    string_append1 (tnam, '/');
    string_appends (tnam, 'Bin'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;
    {
    *   Must contain Bin/MSDEV.EXE.
    }
    string_copy (clist.str_p^, tnam);
    string_appends (tnam, '/Bin/MSDEV.EXE'(0));
    if not file_exists(tnam) then begin
      string_list_line_del (clist, true); {delete this entry, advance to next}
      next;
      end;

    string_list_pos_rel (clist, 1);    {advance to next list entry}
    end;

  if clist.n = 0 then begin            {not matching directories found ?}
    sys_message ('stuff', 'inst_nodirs'); {complain about it}
    goto retry_vstudio;                {go back and ask again}
    end;
{
*   Check for more than one Visual Studio directory was found.  Make the user
*   pick the right one if so.
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
      if ii = 0 then goto retry_vstudio; {back for another search ?}
      if (ii >= 1) and (ii <= clist.n) {got a valid answer ?}
        then exit;
      end;
    end;

  string_list_pos_abs (clist, ii);     {go to the selected list entry}
  string_copy (clist.str_p^, swinst);  {save MSVC installation directory name}
  string_list_kill (clist);            {delete the candidate directories list}
  clist_open := false;

  writeln;
  sys_msg_parm_vstr (msg_parm[1], swinst);
  sys_message_parms ('stuff', 'inst_vstudio_found', msg_parm, 1);
{
*   Vistual Studio 98 is apparently installed to the directory named in SWINST.
*   Now install the hooks.
*
*   Add the Bin subdirectory to the command search path.
}
  string_copy (swinst, tnam);
  string_appends (tnam, '/Bin');       {make dir to add to command search path}
  exec_path (tnam);                    {go add it}

done_vstudio:                          {done installing hooks to Visual Studio 98}

done_msvc:                             {done installing hooks to MSVC}

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
