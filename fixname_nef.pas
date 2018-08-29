{   Program FIXNAME_NEF
*
*   Fix all the raw camera NEF file names in the current directory.  These are
*   named DSC_xxxx.NEF in the camera, where XXXX is a 4 digit number.  This
*   program renames any such file to xxxx.nef.  Note that the resulting name
*   will be lower case.  The case of the original file name is irrelevant.
}
program fixname_nef;
%include 'base.ins.pas';

var
  conn: file_conn_t;                   {connection to the directory}
  finfo: file_info_t;                  {extra information about directory entry}
  nren: sys_int_machine_t;             {number of files renamed}
  name:                                {name of current directory entry}
    %include '(cog)lib/string_treename.ins.pas';
  lname:                               {lower case NAME}
    %include '(cog)lib/string_treename.ins.pas';
  newname:                             {name current entry is changed to}
    %include '(cog)lib/string_treename.ins.pas';
  stat: sys_err_t;                     {completion status code}
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_end_abort;             {abort on any command line arguments}

  file_open_read_dir (                 {open current directory for reading}
    string_v('.'(0)),                  {name of directory to open}
    conn,                              {returned connection to the directory}
    stat);                             {completion status}
  sys_error_abort (stat, '', '', nil, 0);

  nren := 0;                           {init number of files renamed}
  while true do begin                  {back here each new directory entry}
    file_read_dir (                    {get next directory entry}
      conn,                            {connection to the directory}
      [],                              {no special info being requested}
      name,                            {returned directory entry name}
      finfo,                           {info about this directory entry}
      stat);                           {completion status}
    if file_eof(stat) then exit;       {exhausted the directory ?}
    sys_error_abort (stat, '', '', nil, 0);

    if name.len < 9 then next;         {too short for DSC_x.NEF ?}
    string_copy (name, lname);         {make lower case version of original name}
    string_downcase (lname);
    if lname.str[1] <> 'd' then next;  {not start with DSC_ ?}
    if lname.str[2] <> 's' then next;
    if lname.str[3] <> 'c' then next;
    if lname.str[4] <> '_' then next;
    if lname.str[lname.len-3] <> '.' then next; {not end with .NEF ?}
    if lname.str[lname.len-2] <> 'n' then next;
    if lname.str[lname.len-1] <> 'e' then next;
    if lname.str[lname.len-0] <> 'f' then next;

    string_substr (                    {extract part of name after DSC_}
      lname, 5, lname.len, newname);
    writeln (name.str:name.len, ' --> ', newname.str:newname.len);
    file_rename (name, newname, stat); {rename the file}
    sys_error_abort (stat, '', '', nil, 0);
    nren := nren + 1;                  {count one more file renamed}
    end;                               {back to do next file}

  file_close (conn);                   {close connection to the directory}
  writeln (nren, ' files renamed');
  end.
