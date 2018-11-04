{   Program TOUCH filename
*
*   Lets the system think the file has been modified, although no contents
*   is actually changed.  This causes the last modified date/time to be
*   set to the current date time.  It may also effect modified or backup
*   flags depending on operating system.
}
program touch;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

var
  fnam:                                {file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {connection to the file}
  buf: sys_int_machine_t;              {read buffer, not actually written to}
  olen: sys_int_adr_t;                 {actual size of read}
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam, stat);    {get file name parameter}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no additional command line parameters allowed}

  file_open_bin (fnam, '', [file_rw_read_k, file_rw_write_k], conn, stat); {open file}
  sys_error_abort (stat, '', '', nil, 0);

  file_pos_end (conn, stat);           {position to end of file}
  sys_error_abort (stat, '', '', nil, 0);

  file_read_bin (conn, 1, buf, olen, stat); {read to read, should get end of file}
  discard( file_eof(stat) );           {end of file is not an error}
  sys_error_abort (stat, '', '', nil, 0);

  file_close (conn);                   {close the file}
  end.
