{   DOWNCASE_DIR [<directory>]
*
*   Make sure all the entry names in the directory are lower case.
*   Subdirectories will be processed recursively.  The current directory
*   is the default directory.
}
program downcase_dir;
%include '/cognivision_links/dsee_libs/sys/sys.ins.pas';
%include '/cognivision_links/dsee_libs/util/util.ins.pas';
%include '/cognivision_links/dsee_libs/string/string.ins.pas';
%include '/cognivision_links/dsee_libs/file/file.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  dir:                                 {directory name from command line}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  dir_set: boolean;                    {TRUE if directory name already set}
  change: boolean;                     {TRUE if make changes}

  opt,                                 {upcased command line option}
  parm:                                {command line option parameter}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  next_opt, err_parm, parm_bad, done_opts;
{
******************************************************************************
*
*   Subroutine DOFILE (FNAM)
*
*   Make sure the leafname of the file in FNAM is lower case.  FNAM will be
*   updated if changed.
}
procedure dofile (                     {process one source file}
  in out  fnam: string_treename_t);    {full treename of file to process}
  val_param;

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  dir: string_treename_t;              {name of directory containing FNAM}
  lnam: string_leafname_t;             {FNAM leafname}
  newname: string_treename_t;          {new lower case file name}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

begin
  dir.max := sizeof(dir.str);          {init local var strings}
  lnam.max := sizeof(lnam.str);
  newname.max := sizeof(newname.str);

  string_pathname_split (fnam, dir, lnam); {make directory and leaf names}
  string_downcase (lnam);              {make sure leaf name is lower case}
  string_pathname_join (dir, lnam, newname); {reassemble full pathname}
  if string_equal (newname, fnam) then return; {nothing to change ?}

  string_write (fnam);

  if not change then return;           {actually making changes is inhibited ?}
  file_rename (fnam, newname, stat);   {rename the file}
  if sys_error(stat) then begin        {rename failed ?}
    sys_msg_parm_vstr (msg_parm[1], fnam);
    sys_msg_parm_vstr (msg_parm[2], newname);
    sys_error_print (stat, 'file', 'rename', msg_parm, 2);
    end;
  end;
{
******************************************************************************
*
*   Subroutine DODIR (DIR)
*
*   Do the files in the indicated directory.  Subordinate directories are
*   handled recursively.
}
procedure dodir (                      {done files in directory, dirs recursive}
  in      dir: string_treename_t);     {full treename of directory to process}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  conn: file_conn_t;                   {connection handle to directory}
  fnam: string_leafname_t;             {directory entry name}
  tnam: string_treename_t;             {directory entry full treename}
  finfo: file_info_t;                  {info about a file}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  loop;

begin
  fnam.max := sizeof(fnam.str);        {init local var strings}
  tnam.max := sizeof(tnam.str);

  file_open_read_dir (dir, conn, stat); {open directory for reading}
  sys_msg_parm_vstr (msg_parm[1], dir);
  sys_error_abort (stat, 'file', 'open_dir', msg_parm, 1);

loop:                                  {back here to read each new directory entry}
  file_read_dir (                      {get next directory entry}
    conn,                              {connection handle to directory}
    [file_iflag_type_k],               {we need to get file type of this entry}
    fnam,                              {directory entry name}
    finfo,                             {returned additional info about this file}
    stat);
  if file_eof(stat) then begin         {hit end of directory ?}
    file_close (conn);                 {close the directory}
    return;                            {all done}
    end;
  sys_error_abort (stat, 'file', 'read_dir', nil, 0);

  string_pathname_join (dir, fnam, tnam); {make full file treename in TNAM}

  dofile (tnam);                       {make sure this directory entry is lower case}

  case finfo.ftype of                  {what type of file is this ?}
{
*   Subordinate directory.
}
file_type_dir_k: begin
      dodir (tnam);                    {process as directory recursively}
      end;
    end;

  goto loop;                           {back to do next directory entry}
  end;
{
******************************************************************************
*
*   Start of main program.
}
begin
  string_cmline_init;                  {init for reading the command line}
{
*   Initialize our state before reading the command line options.
}
  dir_set := false;                    {directory name not set yet}
  change := true;                      {init to actually make any changes found}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not dir_set then begin          {directory name not set yet ?}
      string_copy (opt, dir);          {set directory name}
      dir_set := true;                 {directory name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-IN -CHECK',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -IN <directory name>
}
1: begin
  if dir_set then begin                {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (dir, stat);
  dir_set := true;
  end;
{
*   -CHECK
}
2: begin
  change := false;                     {inhibit making any changes}
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
*   Done reading the command line.
}
  if not dir_set then begin            {target directory not explicitly set ?}
    string_vstring (dir, '.', 1);      {default to current directory}
    end;

  string_treename (dir, parm);         {make full starting directory name}
  dodir (parm);                        {process the directory indicated by the user}
  end.
