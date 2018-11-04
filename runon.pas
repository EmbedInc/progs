{   Program RUNON <machine name> <remote prog name> <remote arg 1> ... <rem arg N>
*
*   Run a program on a remote machine.  The first command line argument to
*   RUNON is the name of the remote machine.  The remaining command line
*   arguments are used to make the command line to execute on the remote
*   machine.  The remote command line is formed by concatenating the second
*   thru last argument with one space between each argument.
*
*   The standard output and error output streams from RUNON will be the standard
*   and error output of the remote program.  The standard input to RUNON will
*   be delivered to the standard input of the remote program.  RUNON's exit
*   status code will be the exit status code from the remote program.  In other
*   words, the program will appear to the local command shell as if it were
*   being run locally.
*
*   RUNON requires a COGSERVE server to be running on the remote machine.
*
*   NOTE: This version is not fully implemented.  The standard input to
*     RUNON is not currently passed to the remote program.
}
program runon;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'cogserve.ins.pas';

const
  max_msg_parms = 3;                   {max parameters we can pass to a message}

var
  machine: string_var256_t;            {name of remote machine}
  token: string_var8192_t;             {scratch command line token}
  p: string_index_t;                   {TOKEN parse index}
  tk: string_var8192_t;                {scratch token}
  cmline: string_var8192_t;            {remote command line}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  olen: sys_int_adr_t;                 {amount of data actually read}
  info: csrv_server_info_t;            {info about remote COGSERVE server}
  conn: file_conn_t;                   {handle to COGSERVE server connection}
  conn_stdout, conn_stderr: file_conn_t; {connection handles to our std out streams}
  conn_p: file_conn_p_t;               {pointer to output handle to use}
  cmd: csrv_cmd_t;                     {one COGSERVE server command buffer}
  rsp: csrv_rsp_t;                     {one COGSERVE server response buffer}
  chars_p: csrv_maxchars_p_t;          {pointer to max size server char string}
  line: string_var8192_t;              {scratch one line buffer}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  next_token, done_tokens, loop_response;
{
**********************************************************************
*
*   Local subroutine PROCESS_EXIT (EXTSTAT)
*
*   Process the remote program's exit status code.
*
*   KLUDGE ALERT - This code should just be a CASE statement in the main
*     routine.  However, the IBM compiler couldn't compile the program, probably
*     because of the wide ordinal range of CASE choices.  This prevents use
*     of a single jump table, which apparently the IBM compiler is incapable
*     of dealing with.  We therefore write out the the IF - THEN - ELSE
*     code manually.
}
procedure process_exit (               {process remote program's exit status code}
  in      exstat: csrv_exstat_k_t);    {exit status code from remote program}
  val_param;

label
  done;

begin
%debug; write ('Remote program status: ');
if exstat = csrv_exstat_ok_k then begin
    %debug; writeln ('OK');
    sys_exit;
    end;
if exstat = csrv_exstat_true_k then begin
    %debug; writeln ('TRUE');
    sys_exit_true;
    end;
if exstat = csrv_exstat_false_k then begin
    %debug; writeln ('FALSE');
    sys_exit_false;
    end;
if exstat = csrv_exstat_warn_k then begin
    %debug; writeln ('WARNING');
    goto done;
    end;
if exstat = csrv_exstat_err_k then begin
    %debug; writeln ('ERROR');
    goto done;
    end;
if exstat = csrv_exstat_sverr_k then begin
    %debug; writeln ('SERVER ERROR');
    sys_message_parms ('file', 'cogserve_run_sverr', nil, 0);
    goto done;
    end;
if exstat = csrv_exstat_nogo_k then begin
    %debug; writeln ('NOT INVOKED');
    sys_msg_parm_vstr (msg_parm[1], cmline);
    sys_message_parms ('file', 'cogserve_run_nogo', msg_parm, 1);
    goto done;
    end;
if exstat = csrv_exstat_stop_k then begin
    %debug; writeln ('STOPPED BY CLIENT');
    goto done;
    end;
if exstat = csrv_exstat_svkill_k then begin
    %debug; writeln ('KILLED BY SERVER');
    sys_message_parms ('file', 'cogserve_run_svkill', nil, 0);
    goto done;
    end;
if exstat = csrv_exstat_abort_k then begin
    %debug; writeln ('ABORT ABNORMALLY');
    sys_message_parms ('file', 'cogserve_run_abort', nil, 0);
    goto done;
    end;
if exstat = csrv_exstat_unk_k then begin
    %debug; writeln ('UNKNOWN');
    sys_message_parms ('file', 'cogserve_run_stat_unknown', nil, 0);
    goto done;
    end;
if exstat = csrv_exstat_run_k then begin
    %debug; writeln ('STILL RUNNING');
    sys_message_parms ('file', 'cogserve_run_nostop', nil, 0);
    goto done;
    end;

  sys_msg_parm_int (msg_parm[1], ord(exstat));
  sys_message_bomb ('file', 'cogserve_run_stat_bad', msg_parm, 1);
done:                                  {all done with particular EXSTAT case}
  sys_exit_error;                      {exit with error by default}
  end;
{
**********************************************************************
*
*   Start of main routine.
}
begin
  machine.max := size_char(machine.str); {init local var strings}
  token.max := size_char(token.str);
  tk.max := size_char(tk.str);
  cmline.max := size_char(cmline.str);
  line.max := size_char(line.str);

  string_cmline_init;                  {init for reading the command line}

  string_cmline_token (machine, stat); {get remote machine name}
  string_cmline_req_check (stat);      {the machine name is mandatory}

  cmline.len := 0;                     {init accumulated command line to empty}
next_token:                            {back here each new remote command line token}
  string_cmline_token (token, stat);   {try to get another command line token}
  if string_eos(stat) then goto done_tokens; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  p := 1;                              {init TOKEN parse index}
  while p <= token.len do begin        {once for each sub-token parsed from TOKEN}
    string_token (token, p, tk, stat); {try to get next sub-token from TOKEN}
    if string_eos(stat) then exit;     {done with this command line token ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_append_token (cmline, tk);  {add this sub-token to end of command line}
    end;                               {back for next sub-token}
  goto next_token;                     {back for next command line argument}
done_tokens:                           {done reading all our command line arguments}

  if cmline.len <= 0 then begin        {no remote command to execute ?}
    sys_message_bomb ('file', 'runon_cmline_empty', nil, 0);
    end;
{
*   The remote machine name is in MACHINE, and the remote command line is
*   in CMLINE.  Now connect to the COGSERVE server on the remote machine.
}
  csrv_connect (                       {connect to server on remote machine}
    machine,                           {remote machine name}
    conn,                              {returned handle to server connection}
    info,                              {returned info about remote server}
    stat);
  sys_msg_parm_vstr (msg_parm[1], machine);
  sys_error_abort (stat, 'file', 'cogserve_connect', msg_parm, 1);

  if                                   {incompatible server version ?}
      (info.ver_maj <> csrv_ver_maj_k) or {not same major version number}
      (info.ver_min < csrv_ver_min_k)  {server has older minor version ?}
      then begin
    sys_msg_parm_vstr (msg_parm[1], machine);
    sys_msg_parm_int (msg_parm[2], info.ver_maj);
    sys_msg_parm_int (msg_parm[3], info.ver_min);
    sys_message_bomb ('file', 'cogserve_incompatible', msg_parm, 3);
    end;
{
*   Send the RUN command to the remote server.
}
  cmd.cmd := csrv_cmd_run_k;           {command opcode}
  cmd.run.len := cmline.len;           {number of command line characters}
  cmd.run.opts := [                    {standard out/err will be in text format}
    csrv_runopt_out_text_k, csrv_runopt_err_text_k];
  for i := 1 to cmline.len do begin    {copy the command line into the command buf}
    cmd.run.cmline[i] := cmline.str[i];
    end;
  if info.flip then begin              {flip to server byte order if needed}
    sys_order_flip (cmd.cmd, sizeof(cmd.cmd));
    sys_order_flip (cmd.run.len, sizeof(cmd.run.len));
    end;

  file_write_inetstr (                 {send RUN command to the server}
    cmd,                               {output buffer}
    conn,                              {handle to server connection}
    offset(cmd.run.cmline) +           {amount of data to send}
      sizeof(cmd.run.cmline[1])*cmline.len,
    stat);
  sys_msg_parm_vstr (msg_parm[1], cmline);
  sys_error_abort (stat, 'file', 'cogserve_run_cmline', msg_parm, 1);

  file_open_stream_text (              {create connection handle to STDOUT}
    sys_sys_iounit_stdout_k,           {ID of system stream to connect to}
    [file_rw_write_k],                 {read/write access we require}
    conn_stdout,                       {returned connection handle}
    stat);
  sys_error_abort (stat, 'file', 'open_stdout', nil, 0);

  file_open_stream_text (              {create connection handle to STDERR}
    sys_sys_iounit_errout_k,           {ID of system stream to connect to}
    [file_rw_write_k],                 {read/write access we require}
    conn_stderr,                       {returned connection handle}
    stat);
  sys_error_abort (stat, 'file', 'open_errout', msg_parm, 1);
{
*   Loop back here for each response from the server.
}
loop_response:
  file_read_inetstr (                  {read response opcode from server}
    conn,                              {handle to server connection}
    sizeof(rsp.rsp),                   {amount of data to read}
    [],                                {wait indefinately for data to arrive}
    rsp,                               {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);
  if info.flip then begin              {flip from server byte order if needed}
    sys_order_flip (rsp.rsp, sizeof(rsp.rsp));
    end;

  case rsp.rsp of                      {which server response is this ?}
{
*   The program emitted standard output or error output raw binary data.
}
csrv_rsp_stdout_data_k,
csrv_rsp_errout_data_k: begin
  file_read_inetstr (                  {read fixed length part of response}
    conn,                              {handle to server connection}
    offset(rsp.stdout_data.data) -     {amount of data to read}
      offset(rsp.stdout_data),
    [],                                {wait indefinately for data to arrive}
    rsp.stdout_data,                   {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);
  if info.flip then begin              {flip from server byte order if needed}
    sys_order_flip (rsp.stdout_data.len, sizeof(rsp.stdout_data.len));
    end;

  file_read_inetstr (                  {read the rest of the response packet}
    conn,                              {handle to server connection}
    rsp.stdout_data.len * sizeof(rsp.stdout_data.data[1]), {amount of data to read}
    [],                                {wait indefinately for data to arrive}
    rsp.stdout_data.data,              {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);

  chars_p := csrv_maxchars_p_t(addr(rsp.stdout_data.data));
  write (chars_p^:rsp.stdout_data.len); {send data to our standard output}
  end;
{
*   The program emitted one standard output or error output text line.
}
csrv_rsp_stdout_line_k,
csrv_rsp_errout_line_k: begin
  if rsp.rsp = csrv_rsp_stdout_line_k  {select which output stream to use}
    then conn_p := addr(conn_stdout)
    else conn_p := addr(conn_stderr);

  file_read_inetstr (                  {read fixed length part of response}
    conn,                              {handle to server connection}
    offset(rsp.stdout_line.line) -     {amount of data to read}
      offset(rsp.stdout_line),
    [],                                {wait indefinately for data to arrive}
    rsp.stdout_line,                   {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);
  if info.flip then begin              {flip from server byte order if needed}
    sys_order_flip (rsp.stdout_line.len, sizeof(rsp.stdout_line.len));
    end;

  file_read_inetstr (                  {read the rest of the response packet}
    conn,                              {handle to server connection}
    rsp.stdout_line.len * sizeof(rsp.stdout_line.line[1]), {amount of data to read}
    [],                                {wait indefinately for data to arrive}
    rsp.stdout_line.line,              {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);

  string_vstring (line, rsp.stdout_line.line, rsp.stdout_line.len);
  file_write_text (line, conn_p^, stat); {write this line to our output stream}
  if rsp.rsp = csrv_rsp_stdout_line_k  {select which output stream to use}
    then sys_error_abort (stat, 'file', 'write_stdout_text', nil, 0)
    else sys_error_abort (stat, 'file', 'write_errout_text', nil, 0);
  end;
{
*   Remote program terminated.
}
csrv_rsp_stop_k: begin
  file_close (conn_stdout);            {close our handles to our std out streams}
  file_close (conn_stderr);

  file_read_inetstr (                  {read response opcode from server}
    conn,                              {handle to server connection}
    size_min(rsp.stop),                {amount of data to read}
    [],                                {wait indefinately for data to arrive}
    rsp.stop,                          {input buffer}
    olen,                              {amount of data actually read}
    stat);
  sys_error_abort (stat, 'file', 'cogserve_readfrom', nil, 0);
  if info.flip then begin              {flip from server byte order if needed}
    sys_order_flip (rsp.stop.stat, sizeof(rsp.stop.stat));
    end;

  file_close (conn);                   {close connection to server}

  process_exit (rsp.stop.stat);        {process remote exit status code}
  end;
{
*   Unexpected server response.
}
otherwise
    sys_msg_parm_int (msg_parm[1], ord(rsp.rsp));
    sys_message_bomb ('file', 'cogserve_response_unexpected', msg_parm, 1);
    end;
  goto loop_response;                  {back for next response from server}
  end.
