{   Module of system-independent routines of the COGSERVE server.
}
module cogserve;
define csrv_client;
define csrv_version_sequence;
%include 'cogserve2.ins.pas';

define csrv;                           {define the "common block"}
{
*****************************************************************************
*
*   Subroutine CSRV_CLIENT (CONN)
*
*   Handle one client connection.  The stream to the client has just been
*   established, and CONN is the handle to that stream.  No data has yet been
*   transferred on the stream.  This routine must always close the stream
*   connection before returning.
*
*   NOTE: This routine is usually run in a separate thread on systems that
*   support threads.  On such systems, the program's global variables will be
*   shared between the main thread and all other client threads.  On systems
*   that don't support threads, this routine may be running in a separate
*   process, and will have its own copy of the global data.  This routine
*   may also be run from the main thread, usually for debug purposes.  THIS
*   ROUTINE MUST BE WRITTEN TO WORK PROPERLY IN ALL THREE CASES.
*
*   This routine must never attempt to terminate its thread directly.  For
*   all exit conditions, normal or abnormal, it must first make sure the
*   client connection is closed, then simply return.
}
procedure csrv_client (                {service a newly-established client}
  in out  conn: file_conn_t);          {handle to client connection}

var
  cmd: csrv_cmd_t;                     {buffer for command from client}
  rsp: csrv_rsp_t;                     {buffer for response to client}
  olen: sys_int_adr_t;                 {amount of data actually transferred}
  path: string_var8192_t;              {raw pathname}
  tnam: string_var8192_t;              {translated treename}
  s: string_var8192_t;                 {scratch string}
  conn2: file_conn_t;                  {scratch file connection handle}
  tnamopt: string_tnamopt_t;           {treename translation flags}
  tstat: string_tnstat_k_t;            {treename translation status}
  conn2_open: boolean;                 {TRUE if CONN2 is open}
  stat: sys_err_t;

label
  next_cmd, loop_txwrite, done_cmd, client_end;
{
***************************************
*
*   Local subroutine RSP_STAT (ERR, STAT)
*   This subroutine is local to CSRV_CLIENT.
*
*   Send a STAT response to the client.  STAT is the status code ID to send.
}
procedure rsp_stat (                   {send STAT response to client}
  in      err: csrv_err_t;             {status code to send}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  rsp: csrv_rsp_t;                     {response buffer}

begin
  rsp.rsp := csrv_rsp_stat_k;          {set response opcode}
  rsp.stat.err := err;                 {set error code}

  file_write_inetstr (                 {send response packet back to client}
    rsp,                               {data to send}
    conn,                              {client stream connection handle}
    size_min(rsp.rsp) + size_min(rsp.stat), {amount of data to send}
    stat);
  end;
{
***************************************
*
*   Local subroutine READ_OPCODE (STAT)
*   This subroutine is local to CSRV_CLIENT.
*
*   Read the command ID from the client.  The command ID is placed in CMD.CMD.
}
procedure read_opcode (                {read opcode of next client command}
  out     stat: sys_err_t);            {returned completion status code}

var
  olen: sys_int_adr_t;                 {unused argument}

begin
  file_read_inetstr (                  {read command ID from client}
    conn,                              {client stream connection handle}
    sizeof(cmd.cmd),                   {amount of data to read}
    [],                                {no modifier flags specified}
    cmd,                               {data input buffer}
    olen,                              {returned amount of data actually transferred}
    stat);
  if file_eof(stat) then begin         {client closed connection ?}
    if debug >= 1 then begin
      writeln ('Connection closed by client.');
      end;
    sys_stat_set (file_subsys_k, file_stat_eof_k, stat); {restore error status}
    return;
    end;
  sys_error_print (stat, 'file', 'read_inetstr_server', nil, 0);
  end;
{
***************************************
*
*   Start of CSRV_CLIENT.
}
begin
  path.max := size_char(path.str);     {init local var strings}
  tnam.max := size_char(tnam.str);
  s.max := size_char(s.str);

  conn2_open := false;                 {init to CONN2 not in use}
{
*   Main loop.  We come back here to get each new command from the client.
}
next_cmd:                              {back here each new command from client}
  read_opcode (stat);                  {read command opcode into CMD.CMD}
  if sys_error(stat) then goto client_end;
  case cmd.cmd of                      {which command is this ?}
{
*****************
*
*   Command SVINFO.
}
csrv_cmd_svinfo_k: begin
  if debug >= 5 then begin
    writeln ('Received command SVINFO.');
    end;

  file_read_inetstr (                  {read data for this command}
    conn,                              {client stream connection handle}
    size_min(cmd.svinfo),              {amount of remaining data in this command}
    [],
    cmd.svinfo,                        {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;

  rsp.rsp := csrv_rsp_svinfo_k;        {fill in response packet}
  rsp.svinfo.t1 := cmd.svinfo.t1;
  rsp.svinfo.t2 := cmd.svinfo.t2;
  rsp.svinfo.t3 := cmd.svinfo.t3;
  rsp.svinfo.t4 := cmd.svinfo.t4;
  rsp.svinfo.r1 :=
    xor(cmd.svinfo.t1, cmd.svinfo.t2, cmd.svinfo.t3, cmd.svinfo.t4, 5);
  rsp.svinfo.r2 :=
    xor(cmd.svinfo.t1 + cmd.svinfo.t2 + cmd.svinfo.t3 + cmd.svinfo.t4, 5);
  rsp.svinfo.r3 :=
    xor(rsp.svinfo.r1 + rsp.svinfo.r2, 5);
  case sys_byte_order_k of
sys_byte_order_fwd_k: rsp.svinfo.order := csrv_order_fwd_k;
sys_byte_order_bkw_k: rsp.svinfo.order := csrv_order_bkw_k;
    end;
  rsp.svinfo.id := csrv_id_k;
  rsp.svinfo.ver_maj := csrv_ver_maj_k;
  rsp.svinfo.ver_min := csrv_ver_min_k;
  rsp.svinfo.ver_seq := csrv_version_sequence;

  file_write_inetstr (                 {send response packet back to client}
    rsp,                               {data to send}
    conn,                              {client stream connection handle}
    size_min(rsp.rsp) + size_min(rsp.svinfo), {amount of data to send}
    stat);
  if sys_error_check (stat, 'file', 'write_inetstr_server', nil, 0)
    then goto client_end;
  end;                                 {end of SVINFO command case}
{
*****************
*
*   Command PING.
}
csrv_cmd_ping_k: begin
  if debug >= 5 then begin
    writeln ('Received command PING.');
    end;

  rsp.rsp := csrv_rsp_ping_k;          {set response ID}

  file_write_inetstr (                 {send response packet back to client}
    rsp,                               {data to send}
    conn,                              {client stream connection handle}
    size_min(rsp.rsp),                 {amount of data to send}
    stat);
  if sys_error_check (stat, 'file', 'write_inetstr_server', nil, 0)
    then goto client_end;
  end;                                 {end of SVINFO command case}
{
*****************
*
*   Command TNAM.
}
csrv_cmd_tnam_k: begin
  if debug >= 5 then begin
    writeln ('Received command TNAM.');
    end;

  file_read_inetstr (                  {read the fixed length command data}
    conn,                              {client stream connection handle}
    offset(cmd.tnam.path) - offset(cmd.tnam), {amount of data to read}
    [],
    cmd.tnam,                          {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;

  if cmd.tnam.len > 0 then begin       {there are pathname bytes to read ?}
    file_read_inetstr (                {read the variable length pathname string}
      conn,                            {client stream connection handle}
      min(size_min(cmd.tnam.path), cmd.tnam.len), {amount of data to read}
      [],
      cmd.tnam.path,                   {input buffer}
      olen,
      stat);
    if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
      then goto client_end;
    end;
{
*   The command has been fully read in.
}
  string_vstring (path, cmd.tnam.path, cmd.tnam.len); {make var string pathname}
  if debug >= 10 then begin
    writeln ('  In: ', path.str:path.len);
    end;

  tnamopt := [];                       {set treename translation flags}
  if csrv_tnamopt_flink_k in cmd.tnam.opts
    then tnamopt := tnamopt + [string_tnamopt_flink_k];
  if csrv_tnamopt_native_k in cmd.tnam.opts
    then tnamopt := tnamopt + [string_tnamopt_native_k];

  string_treename_opts (               {try to translate the pathname}
    path,                              {pathname to translate}
    tnamopt,                           {set of translation option flags}
    tnam,                              {returned treename}
    tstat);                            {returned TNAM translation status}

  rsp.rsp := csrv_rsp_tnam_k;          {set response packet ID}
  rsp.tnam.len := min(size_char(rsp.tnam.tnam), tnam.len); {returned string length}
  case tstat of                        {what is treename translation status ?}
string_tnstat_native_k: rsp.tnam.tstat := csrv_tnstat_native_k;
string_tnstat_cog_k:    rsp.tnam.tstat := csrv_tnstat_cog_k;
string_tnstat_remote_k: rsp.tnam.tstat := csrv_tnstat_remote_k;
string_tnstat_proc_k:   rsp.tnam.tstat := csrv_tnstat_proc_k;
otherwise
    writeln ('Unexpected TSTAT value ', ord(tstat),
      ' returned by STRING_TREENAME_OPTS.');
    goto client_end;
    end;

  if debug >= 10 then begin
    write ('  Out: ', tnam.str:tnam.len, ' ');
    case tstat of                      {what is treename translation status ?}
string_tnstat_native_k: write ('(native)');
string_tnstat_cog_k:    write ('(cog)');
string_tnstat_remote_k: write ('(remote)');
string_tnstat_proc_k:   write ('(proc)');
      end;
    writeln;
    end;

  file_write_inetstr (                 {send fixed length part of response}
    rsp,                               {data to send}
    conn,                              {client stream connection handle}
    offset(rsp.tnam.tnam),             {amount of data to send}
    stat);
  if sys_error_check (stat, 'file', 'write_inetstr_server', nil, 0)
    then goto client_end;

  if rsp.tnam.len > 0 then begin       {we have string bytes to send ?}
    file_write_inetstr (               {send fixed length part of response}
      tnam.str,                        {data to send}
      conn,                            {client stream connection handle}
      rsp.tnam.len,                    {amount of data to send}
      stat);
    if sys_error_check (stat, 'file', 'write_inetstr_server', nil, 0)
      then goto client_end;
    end;
  end;
{
*****************
*
*   Command RUN.
}
csrv_cmd_run_k: begin
  if debug >= 5 then begin
    writeln ('Received command RUN.');
    end;

  file_read_inetstr (                  {read the fixed length command data}
    conn,                              {client stream connection handle}
    offset(cmd.run.cmline) - offset(cmd.run), {amount of data to read}
    [],
    cmd.run,                           {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;

  if cmd.run.len > 0 then begin        {there is additional data to read ?}
    file_read_inetstr (                {read the variable length data}
      conn,                            {client stream connection handle}
      min(size_min(cmd.run.cmline),    {amount of data to read}
        sizeof(cmd.run.cmline[1])*cmd.run.len),
      [],
      cmd.run.cmline,                  {input buffer}
      olen,
      stat);
    if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
      then goto client_end;
    end;

  string_vstring (s, cmd.run.cmline, cmd.run.len); {extract command line into S}
  if debug >= 6 then begin
    writeln ('  Command: "', s.str:s.len, '"');
    end;

  csrv_cmd_run (conn, cmd.run.opts, s); {process the RUN command}
  end;
{
*****************
*
*   Command STDIN.
*
*   This command is meant to supply standard input data to a running program.
*   If we get it as a top level command, then we have already sent the STOP
*   response, but the client sent this command before the STOP response was
*   received.  We therefore read all the data, but otherwise ignore the
*   command.
}
csrv_cmd_stdin_data_k: begin
  if debug >= 5 then begin
    writeln ('Received command STDIN_DATA - ignored.');
    end;

  file_read_inetstr (                  {read the fixed length command data}
    conn,                              {client stream connection handle}
    offset(cmd.stdin_data.data) - offset(cmd.stdin_data), {amount of data to read}
    [],
    cmd.stdin_data,                    {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;

  if cmd.stdin_data.len > 0 then begin {there is additional data to read ?}
    file_read_inetstr (                {read the variable length data}
      conn,                            {client stream connection handle}
      min(size_min(cmd.stdin_data.data), cmd.stdin_data.len), {N bytes to read}
      [],
      cmd.stdin_data.data,             {input buffer}
      olen,
      stat);
    if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
      then goto client_end;
    end;
  end;
{
*****************
*
*   Command STOP.
*
*   This command is meant to stop a program envoked with the RUN command.
*   If we get it as a top level command, then we have already sent the STOP
*   response, but the client sent this command before the STOP response was
*   received.  We therefore read all the data, but otherwise ignore the
*   command.  Since this command has no additional data, there is nothing
*   left to do.
}
csrv_cmd_stop_k: begin
  if debug >= 5 then begin
    writeln ('Received command STOP - ignored.');
    end;
  end;
{
*****************
*
*   Command TXWRITE.
*
*   This command opens a text file for write, then waits in a loop for
*   TXW_DATA and TXW_END commands.
}
csrv_cmd_txwrite_k: begin
  if debug >= 5 then begin
    writeln ('Received command TXWRITE.');
    end;
{
*   Read rest of command.
}
  file_read_inetstr (                  {read the fixed length command data}
    conn,                              {client stream connection handle}
    offset(cmd.txwrite.name) - offset(cmd.txwrite), {amount of data to read}
    [],
    cmd.txwrite,                       {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;

  if cmd.txwrite.len > 0 then begin    {there is additional data to read ?}
    file_read_inetstr (                {read the variable length data}
      conn,                            {client stream connection handle}
      min(size_min(cmd.txwrite.name),  {amount of data to read}
        sizeof(cmd.txwrite.name[1])*cmd.txwrite.len),
      [],
      cmd.txwrite.name,                {input buffer}
      olen,
      stat);
    if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
      then goto client_end;
    end;
{
*   Try to open the text file and send the STAT response.
}
  string_vstring (s, cmd.txwrite.name, cmd.txwrite.len); {make var string file name}
  file_open_write_text (s, '', conn2, stat); {try to open the text output file}
  if sys_error(stat) then begin        {couldn't open the file ?}
    rsp_stat (csrv_err_fail_k, stat);  {send error response to client}
    if sys_error(stat) then goto client_end;
    goto done_cmd;
    end;
  conn2_open := true;                  {indicate that CONN2 is now in use}

  rsp_stat (csrv_err_none_k, stat);    {tell client all is well}
  if sys_error(stat) then goto client_end;
{
*   Loop back here each new command from the client.  We abort if the client
*   does anything illegal.
}
loop_txwrite:                          {back here for each new command from client}
  read_opcode (stat);                  {read opcode of next command into CMD.CMD}
  if sys_error(stat) then goto client_end;
  case cmd.cmd of                      {which command is it ?}
{
*   Client sent command TXW_DATA.
}
csrv_cmd_txw_data_k: begin
  file_read_inetstr (                  {read the fixed length command data}
    conn,                              {client stream connection handle}
    offset(cmd.txw_data.line) - offset(cmd.txw_data), {amount of data to read}
    [],
    cmd.txw_data,                      {input buffer}
    olen,
    stat);
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto client_end;
  if cmd.txw_data.len > 0 then begin   {there is additional data to read ?}
    file_read_inetstr (                {read the variable length data}
      conn,                            {client stream connection handle}
      min(size_min(cmd.txw_data.line), {amount of data to read}
        sizeof(cmd.txw_data.line[1])*cmd.txw_data.len),
      [],
      cmd.txw_data.line,               {input buffer}
      olen,
      stat);
    if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
      then goto client_end;
    end;

  string_vstring (s, cmd.txw_data.line, cmd.txw_data.len); {make vstring text line}

  file_write_text (s, conn2, stat);    {try to write line to text output file}
  if sys_error(stat) then begin        {error occurred ?}
    rsp_stat (csrv_err_fail_k, stat);  {send error response to client}
    file_close (conn2);                {close text output file}
    conn2_open := false;               {CONN2 is no longer in use}
    file_delete_name (conn2.tnam, stat); {try to delete the output file}
    goto done_cmd;                     {abort TXWRITE command}
    end;
  end;
{
*   Client sent command TXW_END.
}
csrv_cmd_txw_end_k: begin
  file_close (conn2);                  {close the text file}
  conn2_open := false;                 {CONN2 is no longer in use}
  rsp_stat (csrv_err_none_k, stat);    {tell client everything went OK}
  goto done_cmd;                       {all done with TXWRITE command}
  end;
{
*   Unexpected command from client.
}
otherwise
    if debug >= 1 then begin
      writeln ('Recieved illegal command from client while within TXWRITE.');
      writeln ('Illegal command ID was ', ord(cmd.cmd), '.');
      end;
    goto client_end;
    end;                               {end of client command cases}
  goto loop_txwrite;                   {back for next command within TXWRITE}
  end;                                 {end of top level TXWRITE command case}
{
*****************
*
*   Unsupported command ID encountered.
}
otherwise
    writeln ('Received unrecognized command ', ord(cmd.cmd), ' from client.');
    goto client_end;
    end;                               {end of client command type cases}
  done_cmd:                            {all done with current command}
  goto next_cmd;                       {back for next command from this client}
{
*   Jump here to close client connection and return to caller.
}
client_end:                            {one way or another done with this client}
  if debug >= 1 then begin
    writeln ('Closing connection to client.');
    end;
  file_close (conn);                   {close connection to client}
  if conn2_open then begin             {CONN2 is still open ?}
    file_close (conn2);
    end;
  end;
{
*****************************************************************************
*
*   Function CSRV_VERSION_SEQUENCE
*
*   Returns the sequence number of this build.
}
function csrv_version_sequence         {return server's private sequence number}
  :sys_int_conv32_t;

begin
  csrv_version_sequence := 1;
  end;
