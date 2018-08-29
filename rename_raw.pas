{   Template for a program to rename files in a directory.  The logic of what
*   files to rename and what to rename them to is in subroutine NEW_NAME.
*
*   This source module is intended to be renamed and subroutine NEW_NAME
*   modified to make one-off renaming programs with complex rules.
}
program rename_raw;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  conn: file_conn_t;                   {connection for reading directory}
  finfo: file_info_t;                  {info about directory entry}
  nrename: sys_int_machine_t;          {number of files renamed}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Function STRING_START (STR, PT)
*
*   Returns TRUE iff the string STR starts with the string PT.  This can only
*   be true when the length of STR is at least the length of PT.
}
function string_start (                {check if string starts with a pattern}
  in      str: univ string_var_arg_t;  {the string to check}
  in      pt: string)                  {the pattern to check for}
  :boolean;                            {TRUE iff STR starts with PT}
  val_param; internal;

var
  patt: string_var80_t;                {pattern as var string}
  ii: sys_int_machine_t;               {scratch integer}

begin
  patt.max := size_char(patt.str);     {init local var string}

  string_start := false;               {init to pattern not matched}
  string_vstring (patt, pt, size_char(pt)); {make var string pattern}
  if patt.len < 1 then return;         {no pattern ?}
  if patt.len > str.len then return;   {string too short to hold pattern ?}

  for ii := 1 to patt.len do begin     {scan the pattern characters}
    if str.str[ii] <> patt.str[ii] then return; {found mismatch ?}
    end;

  string_start := true;                {whole pattern was found}
  end;
{
********************************************************************************
*
*   Function STRING_END (STR, PT)
*
*   Returns TRUE iff the string STR ends with the string PT.  This can only
*   be true when the length of STR is at least the length of PT.
}
function string_end (                  {check if string ends with a pattern}
  in      str: univ string_var_arg_t;  {the string to check}
  in      pt: string)                  {the pattern to check for}
  :boolean;                            {TRUE iff STR starts with PT}
  val_param; internal;

var
  patt: string_var80_t;                {pattern as var string}
  ii: sys_int_machine_t;               {scratch integer}
  ofs: sys_int_machine_t;              {offset from pattern to string char index}

begin
  patt.max := size_char(patt.str);     {init local var string}

  string_end := false;                 {init to pattern not matched}
  string_vstring (patt, pt, size_char(pt)); {make var string pattern}
  if patt.len < 1 then return;         {no pattern ?}
  if patt.len > str.len then return;   {string too short to hold pattern ?}

  ofs := str.len - patt.len;           {make offset from PATT to STR index}
  for ii := 1 to patt.len do begin     {scan the pattern characters}
    if str.str[ii+ofs] <> patt.str[ii] then return; {found mismatch ?}
    end;

  string_end := true;                  {whole pattern was found}
  end;
{
********************************************************************************
*
*   Function NEW_NAME (OLD, NEW)
*
*   Determine whether the file name in OLD should be changed.  If so, the
*   function returns TRUE and the new name is returned in NEW.  If not, the
*   function returns FALSE and the contents of NEW is undefined.
}
function new_name (                    {find new name for file}
  in      old: univ string_var_arg_t;  {existing file name}
  in out  new: univ string_var_arg_t)  {name should be changed to}
  :boolean;                            {file name should change, NEW is valid}
  val_param; internal;

begin
  new_name := true;                    {init to name should change}

  if
      string_start (old, 'DSC_') and
      string_end (old, '.NEF')
      then begin
    string_substr (old, 5, old.len, new); {make new file name}
    string_downcase (new);
    return;
    end;

  new_name := false;                   {indicate to leave name as is}
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
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
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

  file_open_read_dir (string_v('.'), conn, stat); {open current directory for reading}
  sys_error_abort (stat, '', '', nil, 0);
  nrename := 0;                        {init number of files renamed}

  while true do begin                  {back here each new directory entry}
    file_read_dir (                    {read next directory entry}
      conn,                            {connection to the directory to read}
      [file_iflag_type_k],             {request syste file type}
      opt,                             {directory entry name}
      finfo,                           {extra info about directory entry}
      stat);
    if file_eof(stat) then exit;       {exhausted the directory entries ?}
    sys_error_abort (stat, '', '', nil, 0);
    if finfo.ftype <> file_type_data_k then next; {not a ordinary data file ?}
    if new_name (opt, parm) then begin {need to rename this file ?}
      writeln (opt.str:opt.len, ' --> ', parm.str:parm.len); {show rename}
      file_rename (opt, parm, stat);   {rename the file}
      sys_error_abort (stat, '', '', nil, 0);
      nrename := nrename + 1;          {count one more file that was renamed}
      end;
    end;                               {back to get next directory entry}
  file_close (conn);                   {close connection to the directory}

  writeln (nrename, ' files renamed');
  end.
