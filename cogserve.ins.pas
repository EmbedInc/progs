{   Include file to define client-visible data structures for communicating
*   with the COGSERVE server.
*
*   Multi-byte numeric fields are transmitted in the order specified by the
*   server, except as explicitly noted.  The server byte order must be
*   determined with the SVINFO command.  The client must adjust the byte order
*   accordingly.
*
*   Minor server versions within a major version are guaranteed to be backwards
*   compatible.  In other words, without needing to know about version
*   differences, a client can talk with any server that has the same major
*   version, AND that has the same or greater minor version as the client.
*   A client may talk to a server with a lesser major or minor version, but
*   must then be aware of, and adjust for, any version differences.  A client
*   must immediately break off communication with any server that reports a
*   higher major version number than the client is equipped to deal with.  It
*   is the client's job to determine compatibility, and to handle any
*   incompatibilities or to terminate the server connection.  Note that the
*   SVINFO command and response IDs must be the same for all versions.  The
*   value of zero was chosen because it is also independent of byte ordering.
*
*   Two and four byte numeric values are always naturally aligned
*   within their command or response data structures.  The command and response
*   data types are CSRV_CMD_xxx_T and CSRV_RSP_xxx_T, where XXX is the command
*   or response name.
}
const
  csrv_port_k = 631;                   {"well known port" of the server}
  csrv_id_k = 2;                       {ID of CSERVE server}
  csrv_ver_maj_k = 2;                  {major version number}
  csrv_ver_min_k = 0;                  {minor version number}
  csrv_maxchars_k = 8192;              {max chars in variable length string}
{
*   Status codes for the COGSERVE subsystem.
}
  csrv_subsys_k = -28;                 {ID for COGSERVE subsystem}

  csrv_stat_noserve_k = 1;             {unable to find correct server}
  csrv_stat_svers_bad_k = 2;           {server version is incompatible}
  csrv_stat_commerr_k = 3;             {error communicating with remote server}

type
  csrv_server_info_t = record          {server info returned by CSRV_CONNECT}
    ver_maj: sys_int_machine_t;        {server major version number}
    ver_min: sys_int_machine_t;        {server minor version number}
    ver_seq: sys_int_machine_t;        {server build sequence number}
    order: sys_byte_order_k_t;         {server byte order}
    flip: boolean;                     {TRUE if server byte order flipped from ours}
    end;

  csrv_err_t = int32u_t (              {error codes from various responses}
    csrv_err_none_k,                   {no error, operation completed successfully}
    csrv_err_fail_k);                  {operation failed, no further info}

  csrv_cmd_k_t = int32u_t (            {IDs for all commands (client to server)}
    csrv_cmd_svinfo_k = 0,             {inquire general server information}
    csrv_cmd_ping_k,                   {generate PING response}
    csrv_cmd_tnam_k,                   {pathname to treename expansion}
    csrv_cmd_run_k,                    {run program on server's machine}
    csrv_cmd_stdin_data_k,             {pass standard input data to running prog}
    csrv_cmd_stdin_line_k,             {pass one line of stdout text to running prog}
    csrv_cmd_stop_k,                   {stop the running program}
    csrv_cmd_txwrite_k,                {start writing a text file}
    csrv_cmd_txw_data_k,               {data for text file being written}
    csrv_cmd_txw_end_k);               {close text file being written}

  csrv_rsp_k_t = int32u_t (            {IDs for all responses (server to client)}
    csrv_rsp_svinfo_k = 0,             {response to SVINFO command}
    csrv_rsp_ping_k,                   {response to PING command}
    csrv_rsp_tnam_k,                   {response to TNAM command}
    csrv_rsp_stdout_data_k,            {data from running program's standard output}
    csrv_rsp_stdout_line_k,            {one text line from program's standard out}
    csrv_rsp_errout_data_k,            {data from running program's error output}
    csrv_rsp_errout_line_k,            {one text line from program's error out}
    csrv_rsp_stop_k,                   {running program stopped}
    csrv_rsp_stat_k);                  {returns error (or OK) status}

  csrv_maxchars_t =                    {max size server character string}
    array[1..csrv_maxchars_k] of char;
  csrv_maxchars_p_t = ^csrv_maxchars_t;
{
*   General STAT response.  This is the response to several commands, and is
*   used to indicate whether the requested operation succeeded or failed, and
*   to maybe give more details on why it failed.
}
  csrv_rsp_stat_t = record
    err: csrv_err_t;                   {error (or OK) status code}
    end;
{
**********************************************************
*
*   SVINFO command and response.
*
*   The SVINFO command is used to verify that you're talking to the right server,
*   and to get the server byte order and version information.  The client should
*   only assume that it is talking to a CSERVE server if all of the following are
*   true:
*
*     1 - The T1-T4 test bytes are returned permuted as indicated.
*
*     2 - The R1-R3 bytes contain the proper values given the original
*         test bytes.
*
*     3 - The ORDER field is one of the allowable values.
*
*     4 - The returned ID matches CSRV_ID_K.  Note that this field may need to
*         be byte reversed, depending on ORDER and the client machine's byte
*         ordering scheme.
*
*   Additionally, a client should immediately close the connection to the server
*   if the server reports a major version number greater than any the client
*   knows how to handle.  No compatibility should be assumed between servers with
*   different major version numbers.
*
*   The client may send any values for the T1 - T4 test bytes.  The SVINFO command
*   may be used more than once within a session.  This command may be sent without
*   knowing the server version or byte ordering.
*
*   SVINFO is the only possible response to the SVINFO command.
}
  csrv_order_k_t = int8u_t (           {machine byte order flag}
    csrv_order_fwd_k,                  {forwards, most significant byte is first}
    csrv_order_bkw_k);                 {backwards, least significant byte is first}

  csrv_cmd_svinfo_t = record           {data for SVINFO command}
    t1, t2, t3, t4: int8u_t;           {test bytes to confirm right kind of server}
    end;

  csrv_rsp_svinfo_t = record           {data for SVINFO response}
    t3, t2, t4, t1: int8u_t;           {test bytes returned in different order}
    r1: int8u_t;                       {T1 xor T2 xor T3 xor T4 xor 5}
    r2: int8u_t;                       {(T1 + T2 + T3 + T4) xor 5}
    r3: int8u_t;                       {(R1 + R2) xor 5}
    order: csrv_order_k_t;             {server byte order}
    id: int32u_t;                      {ID of this server}
    ver_maj: int16u_t;                 {server major version number}
    ver_min: int16u_t;                 {server minor version number}
    ver_seq: int16u_t;                 {server private build sequence number}
    end;
{
**********************************************************
*
*   PING command and response.
*
*   This command only generates the PING response.  It may be useful for measuring
*   round trip response time, verifying the server is still up, etc.  It also resets
*   appropriate server inactivity timeouts, if any.
*
*   PING is the only possible response to the PING command.
}

{
**********************************************************
*
*   TNAM command and response.
*
*   The TNAM command expands an arbitrary file system pathname to the true
*   absolute pathname.  Details of this operation can be modified by flags in
*   the OPTS byte.  The status of the resulting translation is returned in
*   the TSTAT byte.
*
*   The TNAM is the only possible response to the TNAM command.
}
  csrv_tnamopt_k_t = (                 {options flags for TNAM command}
    csrv_tnamopt_flink_k,              {follow symbolic links}
    csrv_tnamopt_native_k);            {use target sys native OS file naming rules}
  csrv_tnamopt_t = set of bitsize 8 eletype csrv_tnamopt_k_t;

  csrv_tnstat_k_t = int8u_t (          {status of TNAM command result}
    csrv_tnstat_native_k,              {done as requested, name in native OS format}
    csrv_tnstat_cog_k,                 {done as requested, name in Cognivison format}
    csrv_tnstat_remote_k,              {resolved to pathname on another machine}
    csrv_tnstat_proc_k);               {further translation required by owning proc}

  csrv_cmd_tnam_t = record             {data for TNAM command}
    len: int16u_t;                     {number of characters in PATH}
    opts: csrv_tnamopt_t;              {set of option flags}
    path: csrv_maxchars_t;             {name to translate, must only send LEN chars}
    end;

  csrv_rsp_tnam_t = record             {data for TNAM response}
    len: int16u_t;                     {number of characters in TNAM}
    tstat: csrv_tnstat_k_t;            {translation status of name in TNAM}
    tnam: csrv_maxchars_t;             {translated pathname, only LEN chars are sent}
    end;
{
**********************************************************
*
*   RUN command and responses.
*
*   The RUN command causes the server to run a program on its machine.  The
*   server will then monitor the program's standard output and error output.
*   The client can send data to the programs standard input, and explicitly
*   cause it to be stopped.
*
*   Once the RUN command is issued, the server will produce any number
*   of STDOUT_DATA, STDOUT_LINE, ERROUT_DATA, and ERROUT_LINE responses,
*   followed by exactly one STOP response.  No other responses are allowed.
*   After the RUN command is sent, the client may send any number of STDIN_DATA
*   commands, followed by zero or one STOP command.
*
*   The server will always send exactly one STOP response for every RUN
*   command.  After the STOP response is sent, the RUN command is over from
*   the server's point of view.  Note that due to round trip delays, the
*   client may send any number of STDIN_DATA possibly followed by a STOP
*   command after the server has already issued the STOP response.  These
*   STDIN_DATA and STOP commands are interpreted as top level commands, and
*   are ignored, generating no additional responses.
*
*   The STOP command has no additional data values, and therefore doesn't
*   have any associated data structure.
}
  csrv_exstat_k_t = int32u_t (         {exit status information from remote program}
    csrv_exstat_ok_k = 0,              {program executed normally, no errors}
    csrv_exstat_true_k = 1,            {prog was true/false test, result was TRUE}
    csrv_exstat_false_k = 2,           {prog was true/false test, result was FALSE}
    csrv_exstat_warn_k = 3,            {prog completed, something unexpected found}
    csrv_exstat_err_k = 4,             {program failed in some way}
    csrv_exstat_sverr_k =  16#7FFFFFFF, {server error, program never envoked}
    csrv_exstat_nogo_k =   16#7FFFFFFE, {program invocation failed}
    csrv_exstat_stop_k =   16#7FFFFFFD, {program was stopped by client}
    csrv_exstat_svkill_k = 16#7FFFFFFC, {program killed due to server error}
    csrv_exstat_abort_k =  16#7FFFFFFB, {prog aborted not due to anything we did}
    csrv_exstat_unk_k =    16#7FFFFFFA, {exit status unknown due to error}
    csrv_exstat_run_k =    16#7FFFFFF9); {program still running, unable to stop it}

  csrv_runopt_k_t = (                  {individual option flags for running programs}
    csrv_runopt_out_text_k,            {standard output is text, not binary}
    csrv_runopt_err_text_k);           {standard error is text, not binary}
  csrv_runopt_t = set of bitsize 8 eletype csrv_runopt_k_t; {all flags in one byte}

  csrv_cmd_run_t = record              {data for RUN command}
    len: int16u_t;                     {number of chars in CMLINE}
    opts: csrv_runopt_t;               {additional option flags, unused bits = 0}
    cmline: csrv_maxchars_t;           {command line to execute on server's machine}
    end;

  csrv_cmd_stdin_data_t = record       {standard input data for running program}
    len: int16u_t;                     {number of bytes in DATA}
    data:                              {standard input data bytes for running prog}
      array [1..csrv_maxchars_k] of int8u_t; {max allowed size}
    end;

  csrv_cmd_stdin_line_t = record       {one text line of standard input for program}
    len: int16u_t;                     {number of characters in LINE}
    line: csrv_maxchars_t;             {text chars, no EOL, only LEN chars sent}
    end;

  csrv_rsp_stdout_data_t = record      {standard output data from running program}
    len: int16u_t;                     {number of bytes in DATA}
    data:                              {data from program}
      array [1..csrv_maxchars_k] of int8u_t; {max allowed size}
    end;

  csrv_rsp_stdout_line_t = record      {one STDOUT text line from running program}
    len: int16u_t;                     {number of characters in LINE}
    line: csrv_maxchars_t;             {text chars, no EOL, only LEN chars sent}
    end;

  csrv_rsp_errout_data_t = record      {error output data from running program}
    len: int16u_t;                     {number of bytes in DATA}
    data:                              {data from program}
      array [1..csrv_maxchars_k] of int8u_t; {max allowed size}
    end;

  csrv_rsp_errout_line_t = record      {one ERROUT text line from running program}
    len: int16u_t;                     {number of characters in LINE}
    line: csrv_maxchars_t;             {text chars, no EOL, only LEN chars sent}
    end;

  csrv_rsp_stop_t = record             {program envoked with RUN command has stopped}
    stat: csrv_exstat_k_t;             {program's exit status condition}
    end;
{
**********************************************************
*
*   TXWRITE command and associated commands and responses.
*
*   The TXWRITE command causes the server to open a text file for write.
*   Individual text lines are sent to the server with the TXW_DATA command.
*   The TXW_END command signifies the end of data for the text file, and causes
*   the file to be closed.
*
*   Only TXW_DATA commands are allowed after the TXWRITE command and before the
*   TXW_END command.  The TXWRITE command always generates one STAT response.
*   If a TXW_DATA commands is successful, no response is sent.  On TXW_DATA
*   error, a STAT response is sent indicating the error, and the TXWRITE command
*   is terminated.  Exactly one STAT response is sent for all the TXW_DATA
*   and the TXW_END commands.  TXW_DATA and TXW_END commands are ignored
*   at the top level.
*
*   The TXW_END command has no parameters, and therefore does not have an
*   associated data structure.
}
  csrv_cmd_txwrite_t = record          {open text file for write}
    len: int16u_t;                     {number of characters in NAME}
    name: csrv_maxchars_t;             {file name, must be local to server machine}
    end;

  csrv_cmd_txw_data_t = record         {send one line of text to write to file}
    len: int16u_t;                     {number of characters in LINE}
    line: csrv_maxchars_t;             {file name, must be local to server machine}
    end;
{
*   End of data structures for specific commands and responses.
*
**********************************************************
*
*   Combined data structures for the commands and responses.
}
  csrv_cmd_t = record                  {overlay of all the commands}
    cmd: csrv_cmd_k_t;                 {command ID}
    case csrv_cmd_k_t of
csrv_cmd_svinfo_k: (svinfo: csrv_cmd_svinfo_t);
csrv_cmd_ping_k: ();
csrv_cmd_tnam_k: (tnam: csrv_cmd_tnam_t);
csrv_cmd_run_k: (run: csrv_cmd_run_t);
csrv_cmd_stdin_data_k: (stdin_data: csrv_cmd_stdin_data_t);
csrv_cmd_stdin_line_k: (stdin_line: csrv_cmd_stdin_line_t);
csrv_cmd_stop_k: ();
csrv_cmd_txwrite_k: (txwrite: csrv_cmd_txwrite_t);
csrv_cmd_txw_data_k: (txw_data: csrv_cmd_txw_data_t);
csrv_cmd_txw_end_k: ();
    end;
  csrv_cmd_p_t = ^csrv_cmd_t;

  csrv_rsp_t = record                  {overlay of all the responses}
    rsp: csrv_rsp_k_t;                 {response ID}
    case csrv_rsp_k_t of
csrv_rsp_svinfo_k: (svinfo: csrv_rsp_svinfo_t);
csrv_rsp_ping_k: ();
csrv_rsp_tnam_k: (tnam: csrv_rsp_tnam_t);
csrv_rsp_stdout_data_k: (stdout_data: csrv_rsp_stdout_data_t);
csrv_rsp_stdout_line_k: (stdout_line: csrv_rsp_stdout_line_t);
csrv_rsp_errout_data_k: (errout_data: csrv_rsp_errout_data_t);
csrv_rsp_errout_line_k: (errout_line: csrv_rsp_errout_line_t);
csrv_rsp_stop_k: (stop: csrv_rsp_stop_t);
csrv_rsp_stat_k: (stat: csrv_rsp_stat_t);
    end;
  csrv_rsp_p_t = ^csrv_rsp_t;
{
*   Routine declarations.
}
procedure csrv_connect (               {connect to a COGSERVE server}
  in      machine: univ string_var_arg_t; {machine name}
  out     conn: file_conn_t;           {handle to server stream connection}
  out     info: csrv_server_info_t;    {info about remote server}
  out     stat: sys_err_t);            {completion status code}
  val_param; extern;

procedure csrv_stat_get (              {read STAT response and return result}
  in out  conn: file_conn_t;           {server connection handle}
  in      flip: boolean;               {TRUE if need to flip to server byte order}
  out     err: csrv_err_t;             {error status flag from STAT response}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;
