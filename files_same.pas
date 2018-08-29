{   Program FILES_SAME
*
*   Compare two text files and return exit status of 0 if they are the
*   same.  If both files exist but differences were found then exit status
*   1 is returned.  If one or both files were not found then a higher exit
*   status is returned.  If an error other than not found is encountered
*   on attempt to open either file, the an error message is written and an
*   exit status greater than 1 is returned.
}
program files_same;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

var
  fnam1, fnam2:                        {input file names}
    %include '(cog)lib/string_treename.ins.pas';
  conn1, conn2: file_conn_t;           {connections to the input files}
  buf1, buf2:                          {one line input buffers for each file}
    %include '(cog)lib/string8192.ins.pas';
  stat, stat2: sys_err_t;              {completion status}

label
  loop, different, eof;

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam1, stat);   {get first input file name}
  string_cmline_req_check (stat);
  string_cmline_token (fnam2, stat);   {get second input file name}
  string_cmline_req_check (stat);
  string_cmline_end_abort;             {nothing more allowed on command line}

  file_open_read_text (fnam1, '', conn1, stat); {try to open first input file}
  if file_not_found(stat) then sys_exit_error;
  sys_error_abort (stat, '', '', nil, 0);

  file_open_read_text (fnam2, '', conn2, stat); {try to open second input file}
  if file_not_found(stat) then sys_exit_error;
  sys_error_abort (stat, '', '', nil, 0);

loop:                                  {back here each new line from the files}
  file_read_text (conn1, buf1, stat);  {read line from first input file}
  file_read_text (conn2, buf2, stat2); {read line from second input file}
  if file_eof(stat) then begin         {hit end of first file ?}
    if file_eof(stat2) then goto eof;  {also hit end of second file ?}
    sys_error_abort (stat2, '', '', nil, 0);
    goto different;                    {file 2 is longer than file 1}
    end;
  sys_error_abort (stat, '', '', nil, 0);
  if file_eof(stat2) then goto different; {file 2 is shorter than file 1 ?}
  sys_error_abort (stat2, '', '', nil, 0);
  if string_equal(buf1, buf2) then goto loop; {these lines match, on to next ?}

different:                             {difference found, no error}
  file_close (conn1);
  file_close (conn2);
  sys_exit_false;                      {indicate files different}

eof:                                   {hit end of both files, no differences found}
  file_close (conn1);
  file_close (conn2);
  sys_exit_true;                       {indicate the files are the same}
  end.
