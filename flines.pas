{   Program FLINES fnam
*
*   Write the number of lines in the text file FNAM.
}
program flines;
%include 'base.ins.pas';

var
  fnam:                                {input file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {connection to the input file}
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for processing the command line}
  string_cmline_token (fnam, stat);    {get the input file name}
  string_cmline_req_check (stat);      {input file name is required}
  string_cmline_end_abort;             {no more command line options allowed}

  file_open_read_text (fnam, '', conn, stat); {open the input file}
  sys_error_abort (stat, '', '', nil, 0);

  while true do begin                  {back here each new line from input file}
    file_read_text (conn, fnam, stat); {try to read another line}
    if file_eof(stat) then exit;       {hit end of file ?}
    sys_error_abort (stat, '', '', nil, 0);
    end;

  file_close (conn);                   {close connection to the input file}
  writeln (conn.lnum);                 {write out number of lines found}
  end.
