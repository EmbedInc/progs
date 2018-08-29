{   Program GET_NEWER pathname [options]
*
*   Copy the indicated file or tree into the current directory.  Only those
*   files that do not exist in the current directory, or are newer in the
*   source tree are copied.  PATHNAME can be a single file or a directory.
}
program get_newer;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  tsrc,                                {source tree pathname}
  tdst:                                {destination tree pathname}
    %include '(cog)lib/string_treename.ins.pas';
  dir:                                 {scratch directory name}
    %include '(cog)lib/string_treename.ins.pas';
  lnam:                                {scratch leafname}
    %include '(cog)lib/string_leafname.ins.pas';
  tnam:                                {scratch file or tree name}
    %include '(cog)lib/string_treename.ins.pas';
  tstat: string_tnstat_k_t;            {status of pathname translation}
  src_set: boolean;                    {source pathname has been set}
  dst_set: boolean;                    {destination pathname has been set}
  docopy: boolean;                     {actually copy files, not just list}
  nexist: boolean;                     {source allowed to not exist without error}
  ndlist: string_list_t;               {list of directories to not copy}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Subroutine GET_TREE (S, D, LEV)
*
*   Copy the tree S to D.  Only those files and directories that are newer in
*   S or do not exist in D are copied.  LEV is the recursive nesting level this
*   routine is being called with.  LEV of 1 indicates the original call from a
*   external routine.  LEV > 1 means this is a recursive call.
}
procedure get_tree (                   {get newer files in tree}
  in      s: string_treename_t;        {source pathname}
  in      d: string_treename_t;        {destination pathname}
  in      lev: sys_int_machine_t);     {call nesting level}
  val_param; internal;

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  src, dest: string_treename_t;        {full source and destination pathnames}
  sinfo: file_info_t;                  {info on source file or tree}
  dinfo: file_info_t;                  {info on destination file or tree}
  tnam, tnam2: string_treename_t;      {scratch full pathname}
  enam: string_leafname_t;             {directory entry name}
  conn: file_conn_t;                   {connection to directory for reading it}
  tstat: string_tnstat_k_t;            {status of pathname translation}
  exist: boolean;                      {destination exists}
  newer: boolean;                      {source is newer or dest doesn't exist}
  ind: boolean;                        {indent name of files actually copied}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  do_copy;
{
****************************************
*
*   Local subroutine SHOW_COPY
*
*   Show the user that the source object is being copied.
}
procedure show_copy;
  val_param; internal;

begin
  if sinfo.ftype = file_type_dir_k     {don't show "changed" directories}
    then return;

  if ind then begin                    {indent file name ?}
    write ('  ');
    end;
  writeln (dest.str:dest.len);         {show copied object}
  end;
{
****************************************
*
*   Start of GET_TREE.
}
begin
  src.max := size_char(src.str);       {init local var strings}
  dest.max := size_char(dest.str);
  tnam.max := size_char(tnam.str);
  tnam2.max := size_char(tnam2.str);
  enam.max := size_char(enam.str);

  newer := true;                       {init to source object is newer than dest}
{
*   Make the full source and destination pathnames without following links.
}
  string_treename_opts (               {resolve absolute pathame to target object}
    s,                                 {input pathname to resolve}
    [ string_tnamopt_remote_k,         {continue on remote system if needed}
      string_tnamopt_proc_k,           {relative to this process}
      string_tnamopt_native_k],        {translate to native OS format}
    src,                               {output full absolute pathname}
    tstat);                            {translation result status}

  string_treename_opts (               {resolve absolute pathame to target object}
    d,                                 {input pathname to resolve}
    [ string_tnamopt_remote_k,         {continue on remote system if needed}
      string_tnamopt_proc_k,           {relative to this process}
      string_tnamopt_native_k],        {translate to native OS format}
    dest,                              {output full absolute pathname}
    tstat);                            {translation result status}
{
*   Get info on the source.
}
  file_info (                          {get information on the source}
    src,                               {file to get info on}
    [ file_iflag_dtm_k,                {get date/time stamp}
      file_iflag_type_k],              {get file system object type}
    sinfo,                             {returned info}
    stat);
  sys_msg_parm_vstr (msg_parm[1], src);
  sys_error_abort (stat, 'file', 'info', msg_parm, 1);
{
*   Show the top level if a tree is being updated.
}
  ind := (lev > 1);                    {init to indent only if down in tree}

  if
      (sinfo.ftype = file_type_dir_k) and {source object is a directory ?}
      (lev = 1)                        {at the top of the tree ?}
      then begin
    ind := true;                       {indent files actually copied}
    sys_msg_parm_vstr (msg_parm[1], src);
    sys_msg_parm_vstr (msg_parm[2], dest);
    sys_message_parms ('progs', 'gnew_start', msg_parm, 2);
    end;
{
*   Get info on the destination.
}
  exist := false;                      {init to destination does not exist}
  file_info (                          {get information on the destination}
    dest,                              {file to get info on}
    [ file_iflag_dtm_k,                {get date/time stamp}
      file_iflag_type_k],              {get file system object type}
    dinfo,                             {returned info}
    stat);
  if file_not_found(stat) then goto do_copy;
  sys_msg_parm_vstr (msg_parm[1], src);
  sys_error_abort (stat, 'file', 'info', msg_parm, 1);
  exist := true;                       {destination does exist}
{
*   Do some special handling for links.
}
  if dinfo.ftype <> sinfo.ftype then begin {dest exists, but different type ?}
    if dinfo.ftype = file_type_link_k
      then begin                       {destination is a link}
        file_link_del (dest, stat);    {delete the link}
        sys_msg_parm_vstr (msg_parm[1], dest);
        sys_error_abort (stat, 'file', 'link_del', msg_parm, 1);
        end
      else begin                       {destination is not a link}
        file_delete_tree (dest, [file_del_errgo_k], stat); {delete the tree or file}
        sys_msg_parm_vstr (msg_parm[1], dest);
        sys_error_abort (stat, 'file', 'delete', msg_parm, 1);
        end
      ;
    exist := false;                    {dest has been deleted}
    goto do_copy;                      {do the copy}
    end;

  newer :=                             {indicate whether source object is newer than dest}
    sys_clock_compare (sinfo.modified, dinfo.modified)
    = sys_compare_gt_k;

do_copy:                               {copy source to destination}
  case sinfo.ftype of                  {what kind of object is being copied ?}
{
*   Copy a link.  The target is either a link or does not exist.
}
file_type_link_k: begin
  if not newer then return;            {source isn't newer, don't copy}
  file_link_resolve (src, tnam, stat); {get the link value into TNAM}
  sys_msg_parm_vstr (msg_parm[1], src);
  sys_error_abort (stat, 'file', 'link_resolve', msg_parm, 1);
  if exist then begin                  {the destination link already exists ?}
    file_link_resolve (dest, tnam2, stat); {get the destination link value}
    if                                 {links already the same ?}
        (not sys_error(stat)) and      {no error getting destination link value ?}
        string_equal(tnam2, tnam)      {dest already set to same as source ?}
        then begin
      return;                          {nothing more to do}
      end;
    end;
  if docopy then begin
    show_copy;
    file_link_create (dest, tnam, [file_crea_overwrite_k], stat); {create dest link}
    sys_msg_parm_vstr (msg_parm[1], dest);
    sys_error_abort (stat, 'file', 'link_create', msg_parm, 1);
    end;
  end;
{
*   Copy a directory.  The target is either a directory or does not exist.
}
file_type_dir_k: begin
  string_pathname_split (src, tnam, tnam2); {make dir leafname in TNAM2}
  string_list_pos_start (ndlist);      {to before start of no-copy dirs list}
  while true do begin                  {loop over each no-copy dir name}
    string_list_pos_rel (ndlist, 1);   {go to next list entry}
    if ndlist.str_p = nil then exit;   {hit end of list ?}
    if string_equal (tnam2, ndlist.str_p^) {this dir in no-copy list ?}
      then return
    end;                               {back to check next no-copy list entry}

  if docopy then begin
    file_create_dir (dest, [file_crea_keep_k], stat); {create dir if not already existing}
    sys_msg_parm_vstr (msg_parm[1], dest);
    sys_error_abort (stat, 'file', 'dir_create', msg_parm, 1);
    end;

  file_open_read_dir (src, conn, stat); {open the source directory for reading}
  sys_msg_parm_vstr (msg_parm[1], src);
  sys_error_abort (stat, 'file', 'open_dir', msg_parm, 1);
  while true do begin                  {loop thru each entry in source directory}
    file_read_dir (                    {get next directory entry}
      conn,                            {connection to the directory}
      [],                              {nothing requested beyond entry name}
      enam,                            {returned directory entry name}
      sinfo,                           {returned info about the directory entry}
      stat);
    if file_eof(stat) then exit;       {exhausted the directory ?}
    sys_error_abort (stat, 'file', 'read_dir', msg_parm, 1);
    string_copy (src, tnam);           {build source pathname in TNAM}
    string_append1 (tnam, '/');
    string_append (tnam, enam);
    string_copy (dest, tnam2);         {build destination pathname in TNAM2}
    string_append1 (tnam2, '/');
    string_append (tnam2, enam);
    get_tree (tnam, tnam2, lev + 1);   {copy this file or tree recursively}
    end;                               {back to do next directory entry}
  end;
{
*   No special handling required, copy as ordinary file.
}
otherwise
    if not newer then return;          {source isn't newer, don't copy}
    if docopy then begin
      show_copy;
      file_copy (src, dest, [file_copy_replace_k], stat); {copy the file}
      sys_error_abort (stat, '', '', nil, 0);
      sys_msg_parm_vstr (msg_parm[1], src);
      sys_msg_parm_vstr (msg_parm[2], dest);
      sys_error_abort (stat, 'file', 'copy_err', msg_parm, 2);
      end;
    end;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize before reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  src_set := false;                    {source pathname has not been set yet}
  dst_set := false;                    {destination pathname not explicitly set}
  docopy := true;                      {init to actually copy files, not just list}
  nexist := false;                     {init to source not exist is error}
  string_list_init (ndlist, util_top_mem_context); {init list of dirs to not copy}
  ndlist.deallocable := false;
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not src_set then begin          {source pathname not set yet ?}
      string_copy (opt, tsrc);         {set source pathname}
      src_set := true;                 {remember that source pathname has been set}
      goto next_opt;
      end;
    if not dst_set then begin          {destination pathname not set yet ?}
      string_copy (opt, tdst);         {set destination pathname}
      dst_set := true;                 {dest pathname has now been set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-FROM -TO -NCOPY -ND -NE',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -FROM source
}
1: begin
  if src_set then begin                {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (tsrc, stat);
  src_set := true;
  end;
{
*   -TO dest
}
2: begin
  if dst_set then begin                {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (tdst, stat);
  dst_set := true;
  end;
{
*   -NCOPY
}
3: begin
  docopy := false;
  end;
{
*   -ND name
}
4: begin
  string_cmline_token (parm, stat);
  if sys_error(stat) then goto err_parm;
  if parm.len <= 0 then goto parm_bad;

  ndlist.size := parm.len;
  string_list_line_add (ndlist);       {create new list entry}
  string_copy (parm, ndlist.str_p^);   {set the new list entry to NAME}
  end;
{
*   -NE
}
5: begin
  nexist := true;                      {source allowed to not exist}
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   Get the full absolute source pathname into TSRC.
}
  if not src_set then begin            {source tree not specified ?}
    sys_message_bomb ('progs', 'gnew_nsource', nil, 0);
    end;

  string_treename_opts (               {resolve absolute pathame to target object}
    tsrc,                              {input pathname to resolve}
    [ string_tnamopt_remote_k,         {continue on remote system if needed}
      string_tnamopt_proc_k,           {relative to this process}
      string_tnamopt_native_k],        {translate to native OS format}
    tnam,                              {output full absolute pathname}
    tstat);                            {translation result status}
  string_copy (tnam, tsrc);

  if not file_exists (tsrc) then begin {soruce does not exist ?}
    if nexist then return;             {source allowed to not exist ?}
    sys_msg_parm_vstr (msg_parm[1], tsrc);
    sys_message_bomb ('progs', 'gnew_snexist', msg_parm, 1);
    end;
{
*   Get the full absolute destination pathname into TDST.  It is set to the
*   default if not set at all.
}
  if not dst_set then begin            {destination not explicitly set ?}
    file_currdir_get (tdst, stat);     {init to current directory}
    sys_error_abort (stat, 'progs', 'gnew_currdir', nil, 0);
    string_pathname_split (tsrc, tnam, lnam); {get source object leafname}
    string_append1 (tdst, '/');        {source leafname within curr dir}
    string_append (tdst, lnam);
    end;

  string_treename_opts (               {make abs pathname, don't follow links}
    tdst,                              {input pathname to resolve}
    [ string_tnamopt_remote_k,         {continue on remote system if needed}
      string_tnamopt_proc_k,           {relative to this process}
      string_tnamopt_native_k],        {translate to native OS format}
    tnam,                              {output full absolute pathname}
    tstat);                            {translation result status}
  string_copy (tnam, tdst);
{
*   Check for the destination being within the source tree.
}
  string_copy (tdst, dir);             {init first directory to check}
  while true do begin                  {back here each new parent directory}
    if dir.len < tsrc.len then exit;   {DIR can't be within TSRC ?}
    if string_equal (dir, tsrc) then begin
      sys_message_bomb ('progs', 'gnew_circ', nil, 0);
      end;
    string_pathname_split (dir, tnam, lnam); {make parent directory in TNAM}
    if string_equal (tnam, dir) then exit; {already at top, nothing further to do ?}
    string_copy (tnam, dir);           {directory to check next iteration}
    end;                               {back to check DIR}
{
*   Do the copy.
}
  get_tree (tsrc, tdst, 1);            {copy from source to destination}
  end.
