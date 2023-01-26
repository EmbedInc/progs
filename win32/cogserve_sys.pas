{   Module of system-dependent routines of the COGSERVE server.
*
*   This version is for the Microsoft Win32 API.
}
module cogserve_sys;
define csrv_cmd_run;
define csrv_wait_client;
%include 'cogserve_prog.ins.pas';
%include 'sys_sys2.ins.pas';
{
*****************************************************************************
*
*   Subroutine CSRV_CMD_RUN (CONN_CLIENT, OPTS, CMLINE)
*
*   Process the client RUN command.  CONN_CLIENT is the connection handle to
*   the client stream.  CMLINE is the command line to execute.  OPTS is
*   a set of option flags.  These flags can be:
*
*     CSRV_RUNOPT_OUT_TEXT_K  -  The programs standard output should be interpreted
*       in text format and sent to the client as lines of text.  By default,
*       the program's standard output is assumed to be raw binary and is not
*       interpreted in any way.
*
*     CSRV_RUNOPT_ERR_TEXT_K  -  The programs error output should be interpreted
*       in text format and sent to the client as lines of text.  By default,
*       the program's error output is assumed to be raw binary and is not
*       interpreted in any way.
}
procedure csrv_cmd_run (               {process client RUN command}
  in out  conn_client: file_conn_t;    {handle to client stream connection}
  in      opts: csrv_runopt_t;         {option flags from client}
  in      cmline: univ string_var_arg_t); {command line to execute}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

type
  waitid_k_t = (                       {ID's for each event we can wait on}
    waitid_stdout_k,                   {standard output thread completed}
    waitid_stderr_k,                   {standard error thread completed}
    waitid_stdin_k);                   {standard input thread completed}

  kill_k_t = (                         {ID's for why to kill program}
    kill_no_k,                         {don't kill program}
    kill_client_k,                     {explicit kill request from client}
    kill_err_k);                       {we encountered some kind of error}

  copyout_info_t = record              {info for copying an out stream from prog}
    h: win_handle_t;                   {handle to our end of pipe for this stream}
    conn_p: file_conn_p_t;             {pointer to client stream connection handle}
    crsect_p: sys_sys_threadlock_p_t;  {pointer to client send interlock}
    rsp: csrv_rsp_k_t;                 {ID of response to use}
    end;

  copyin_info_t = record               {info for handling commands from client}
    conn_p: file_conn_p_t;             {pointer to client stream connection handle}
    stdin_h: win_handle_t;             {handle to our end of program's STDIN pipe}
    stop_h: win_handle_t;              {stop thread when this handle signalled}
    kill: kill_k_t;                    {info about whether/why to kill program}
    end;

var
  procid: sys_sys_proc_id_t;           {ID of program's process}
  stdin_h, stdout_h, stderr_h:         {handles to our end of prog's STDIO pipes}
    sys_sys_iounit_t;
  copy_stdout: copyout_info_t;         {thread info for copying standard output}
  copy_stderr: copyout_info_t;         {thread info for copying standard error}
  copy_stdin: copyin_info_t;           {thread info for handling client commands}
  thread_stdout_h: win_handle_t;       {handle to thread copying standard output}
  thread_stderr_h: win_handle_t;       {handle to thread copying standard error}
  thread_stdin_h: win_handle_t;        {handle to thread copying standard input}
  thread_id: win_dword_t;              {scratch thread ID (not handle)}
  active_stdout: boolean;              {TRUE if stdout thread is active}
  active_stderr: boolean;              {TRUE if stderr thread is active}
  active_stdin: boolean;               {TRUE if stdin thread is active}
  rsp: csrv_rsp_t;                     {buffer for one response to client}
  crsect: sys_sys_threadlock_t;        {descriptor for thread mutual exclusion lock}
  p: univ_ptr;                         {scratch pointer}
  waitlist: array[0..2] of win_handle_t; {list of handles to wait on}
  waitid:                              {event ID's for each WAITLIST entry}
    array[0..2] of waitid_k_t;
  nwait: sys_int_machine_t;            {number of entries in WAITLIST and WAITID}
  donewait: donewait_k_t;              {reason WaitFor... returned}
  i: sys_int_machine_t;                {scratch integer}

  exstat_sys: sys_sys_exstat_t;        {subordinate program's exit status code}
  stopstat: csrv_exstat_k_t;           {status to send in STOP response}
  ok: win_bool_t;                      {WIN_BOOL_FALSE_K on system call failure}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {Cognivision completion status code}

label
  loop_threads, done_threads, leave;
{
**************************
*
*   Local Function COPY_OUT_BIN (INFO)
*   This subroutine is local to CSRV_CMD_RUN.
*
*   This is the main routine for the threads that copy the standard output and
*   the error output from the program to the client in binary (uninterpreted)
*   mode.  The return value of this function is not used, and should always be
*   zero.
}
function copy_out_bin (                {copy an output stream from prog to client}
  in      info: copyout_info_t)        {info about the stream connection}
  :sys_int_adr_t;                      {unused, always set to zero}

var
  rsp: csrv_rsp_t;                     {buffer for one response packet to client}
  ok: win_bool_t;                      {WIN_BOOL_FALSE_K on system call failure}
  nread: win_dword_t;                  {amount of data actually read}
  stat: sys_err_t;                     {Cognivision completion status code}

label
  loop, leave;

begin
  rsp.rsp := info.rsp;                 {set response packet ID}

loop:                                  {back here to transfer each new chunk}
  ok := ReadFile (                     {try to read next chunk from program}
    info.h,                            {handle to pipe from program}
    rsp.stdout_data.data,              {input buffer}
    csrv_maxchars_k,                   {max bytes allowed to}
    nread,                             {amount of data actually read}
    nil);                              {no overlap info supplied}
  if ok = win_bool_false_k then goto leave; {ReadFile failed ?}
  if debug >= 10 then begin
    writeln ('Recived ', nread, ' binary bytes from program.');
    end;
  if nread <= 0 then goto loop;        {nothing actually read ?}

  rsp.stdout_data.len := nread;        {indicate amount of data in this packet}

  EnterCriticalSection (info.crsect_p^); {ensure we are only ones sending to client}
  file_write_inetstr (                 {send packet to client}
    rsp,                               {output buffer}
    info.conn_p^,                      {handle to client connection}
    offset(rsp.stdout_data.data) +     {amount of data to send}
      nread*sizeof(rsp.stdout_data.data[1]),
    stat);
  LeaveCriticalSection (info.crsect_p^); {release our lock on sending to client}
  if sys_error(stat) then goto leave;  {error on send packet to client ?}
  goto loop;                           {back to transfer next packet}

leave:                                 {common exit point}
  copy_out_bin := 0;                   {set function return value}
  end;
{
**************************
*
*   Local Function COPY_OUT_TEXT (INFO)
*   This subroutine is local to CSRV_CMD_RUN.
*
*   This is the main routine for the threads that copy the standard output and
*   the error output from the program to the client in text mode.
*   The return value of this function is not used, and should always be zero.
}
function copy_out_text (               {copy an output stream from prog to client}
  in      info: copyout_info_t)        {info about the stream connection}
  :sys_int_adr_t;                      {unused, always set to zero}

const
  buflen_k = 8192;                     {size of raw data input buffer}

var
  rsp: csrv_rsp_t;                     {buffer for one response packet to client}
  bnext: sys_int_machine_t;            {index for reading next character from BUF}
  nbuf: sys_int_machine_t;             {total number of characters in BUF}
  buf: array[0..buflen_k-1] of char;   {raw input buffer from program's stream}
  c: char;                             {scratch character}
  got_any: boolean;                    {TRUE if we got any chars for curr line}
  eof: boolean;                        {end of input stream encountered}
  stat: sys_err_t;                     {Cognivision completion status code}

label
  loop, send, leave;
{
**********
*
*   Local function NEXT_CHAR (C)
*   This routine is local to COPY_OUT_TEXT.
*
*   Return the next raw character from the input stream in C.  The function
*   value will be FALSE when no additional character was available.  This
*   routine must not be called after it has returned FALSE.
*
*   Characters are returned from BUF, as available.  A new buffer full is read
*   into BUF automatically when needed.  The variables BNEXT and NBUF must
*   both be initialized to zero before the first call to NEXT_CHAR.
}
function next_char (                   {get next character from the program's stream}
  out     c: char)                     {returned character, invalid on return FALSE}
  :boolean;                            {TRUE if did return character}

var
  ok: win_bool_t;                      {WIN_BOOL_FALSE_K on system call failure}
  nread: win_dword_t;                  {amount of data actually read}

label
  retry, eof;

begin
  next_char := true;                   {init to we will return a valid character}

retry:                                 {back here to retry with new buffer full}
  if bnext < nbuf then begin           {next char is already available in BUF ?}
    c := buf[bnext];                   {fetch the character from the buffer}
    bnext := bnext + 1;                {update buffer read index}
    return;
    end;

  ok := ReadFile (                     {read another chunk from the program's stream}
    info.h,                            {handle to pipe to program's output stream}
    buf,                               {input buffer}
    buflen_k,                          {max number of bytes to read}
    nread,                             {number of bytes actually read}
    nil);                              {no overlap info supplied}
  if ok = win_bool_false_k then goto eof; {assume stream end on any error}
  if debug >= 10 then begin
    writeln ('Recived ', nread, ' text bytes from program.');
    end;
  nbuf := nread;                       {set number of chars now in our buffer}
  bnext := 0;                          {reset buffer read index}
  goto retry;                          {try again with this new buffer}

eof:                                   {we hit the end of the input stream}
  next_char := false;                  {signal stream end to caller}
  end;
{
**********
*
*   Start of COPY_OUT_TEXT.
}
begin
  rsp.rsp := info.rsp;                 {set response packet ID}
  nbuf := 0;                           {init our input buffer to empty}
  bnext := 0;                          {init buffer read index}
  rsp.stdout_line.len := 0;            {init length of accumulated string}
  eof := false;                        {init to not hit end of imput stream yet}
  got_any := false;                    {init to no partial output line pending}

loop:                                  {back here to process each new input char}
  if not next_char(c) then begin       {no additional character available ?}
    eof := true;                       {remember to quit after this chunk}
    goto send;                         {send current chunk, if any, then exit}
    end;
  got_any := true;                     {a partial output line is now pending}

  case ord(c) of                       {which character is this ?}
10: begin                              {line feed, signals end of line}
      goto send;                       {send current chunk as one text line}
      end;
13: ;                                  {carriage return, ignored}
otherwise                              {a regular character}
    if rsp.stdout_line.len < csrv_maxchars_k then begin {is room for this char ?}
      rsp.stdout_line.len := rsp.stdout_line.len + 1; {count one more char in chunk}
      rsp.stdout_line.line[rsp.stdout_line.len] := c; {put this char at end of chunk}
      end;
    end;                               {end of character cases}
  goto loop;                           {back to handle next input character}

send:                                  {send current packet as one text line}
  if got_any then begin                {there is something to send ?}
    EnterCriticalSection (info.crsect_p^); {ensure we are only ones sending to client}
    file_write_inetstr (               {send packet to client}
      rsp,                             {output buffer}
      info.conn_p^,                    {handle to client connection}
      offset(rsp.stdout_line.line) +   {amount of data to send}
        rsp.stdout_line.len*sizeof(rsp.stdout_line.line[1]),
      stat);
    LeaveCriticalSection (info.crsect_p^); {release our lock on sending to client}
    end;
  if sys_error(stat) then goto leave;  {error on send packet to client ?}
  got_any := false;                    {reset to nothing pending in output buffer}
  rsp.stdout_line.len := 0;            {reset output buffer to empty}
  if not eof then goto loop;           {back for next char if not hit end of stream}

leave:                                 {common exit point}
  copy_out_text := 0;                  {set function return value}
  end;
{
**************************
*
*   Local function COPY_IN (INFO)
*   This routine is local to CSRV_CMD_RUN.
*
*   This routine is run as a separate thread.  It's job is to respond to
*   client commands.  The only valid client commands are STDIN_DATA,
*   STDIN_LINE, and STOP.  The function return value is not used, and
*   should always be zero.
}
function copy_in (                     {handle client commands while prog running}
  in out  info: copyin_info_t)         {info about client, program, etc.}
  :sys_int_adr_t;                      {unused, always set to zero}

const
  wait_io_k = 0;                       {wait ID for I/O complete}
  wait_exit_k = 1;                     {wait reason for explicit exit request}
  nwait_k = 2;                         {total number of wait reasons}

type
  buf_t = record                       {used for reading from client}
    cmd: csrv_cmd_t;                   {raw client command input buffer}
    pad: array[1..2] of char;          {ensure room for CR LF at end of input data}
    end;

var
  buf: buf_t;                          {buffer for reading from client}
  ovl: overlap_t;                      {overlapped I/O control structure}
  event_io_h: win_handle_t;            {handle gets signalled on overlapped I/O done}
  waitlist: array[0..nwait_k-1] of win_handle_t; {list of handles to wait on}
  donewait: donewait_k_t;              {reason wait completed}
  nread: win_dword_t;                  {amount of data actually read}
  olen: sys_int_adr_t;                 {amount of data actually read}
  nwrite: win_dword_t;                 {amount of data actually written}
  ok: win_bool_t;                      {WIN_BOOL_FALSE_K on system call failure}
  stat: sys_err_t;

label
  loop_cmd, got_cmdid, leave1, leave0;

begin
  event_io_h := CreateEventA (         {create event handle for our overlapped I/O}
    nil,                               {no security attributes supplied}
    win_bool_false_k,                  {system resets on on successful wait}
    win_bool_false_k,                  {initial state is not signalled}
    nil);                              {this event will have no name}
  if event_io_h = handle_none_k        {didn't create event handle for some reason ?}
    then goto leave0;

  waitlist[wait_io_k] := event_io_h;   {handle to wait on for overlapped I/O done}
  waitlist[wait_exit_k] := info.stop_h; {gets signalled when we're supposed to stop}

  ovl.internal := 0;                   {init overlapped I/O control structure}
  ovl.internal_high := 0;
  ovl.event_h := event_io_h;           {indicate handle to signal on completion}

loop_cmd:                              {back here to read each new client command}
  sys_error_none (stat);               {init STAT to indicate no error}
  ovl.offset := 0;                     {offset is not used for stream I/O}
  ovl.offset_high := 0;
  ok := ReadFile (                     {try to read command ID from client}
    info.conn_p^.sys,                  {I/O handle}
    buf.cmd,                           {input buffer}
    sizeof(buf.cmd.cmd),               {amount of data to read}
    nread,                             {number of bytes actually read}
    addr(ovl));                        {pointer to overlap control structure}
  if ok <> win_bool_false_k then goto got_cmdid; {got a client command ID ?}
  stat.sys := GetLastError;            {get ID of error from ReadFile}
  if stat.sys <> err_io_pending_k then begin {not just indicating ovl I/O started ?}
    sys_error_print (stat, '', '', nil, 0);
    info.kill := kill_err_k;           {assume client went away, kill program}
    goto leave1;                       {abort thread on a real error}
    end;
{
*   The I/O operation has been initiated to read the next command ID from the
*   client.
}
  donewait := WaitForMultipleObjects ( {wait for next event we need to attend to}
    nwait_k,                           {number of possible events to wait on}
    waitlist,                          {list of handles to wait on}
    win_bool_false_k,                  {return as soon as anything happens}
    timeout_infinite_k);               {wait indefinately for next event to occur}

  case ord(donewait) of                {what caused us to stop waiting ?}
wait_exit_k: begin                     {we've been signalled to terminate thread}
      goto leave1;                     {clean up and leave}
      end;
wait_io_k: begin                       {read of command ID completed}
      ok := GetOverlappedResult (      {get status of I/O completion}
        info.conn_p^.sys,              {handle I/O operation was performed on}
        ovl,                           {pointer to overlapped I/O control structure}
        nread,                         {number of bytes actually read}
        win_bool_true_k);              {wait for I/O operation to complete}
      if ok = win_bool_false_k then begin {error occurred ?}
        stat.sys := GetLastError;      {get error ID}
        sys_error_print (stat, '', '', nil, 0);
        info.kill := kill_err_k;       {assume client went away, kill program}
        goto leave1;                   {abort thread}
        end;
      end;
otherwise                              {unexpected reason for WAIT to terminate}
    stat.sys := GetLastError;
    sys_error_print (stat, '', '', nil, 0);
    goto leave1;
    end;                               {end of wait done reason cases}

got_cmdid:                             {we have the command ID from the client}
  case buf.cmd.cmd of                  {which command is client sending ?}
{
*   The client is sending raw binary data for the program's standard input.
}
csrv_cmd_stdin_data_k: begin
  file_read_inetstr (                  {read data length word}
    info.conn_p^,                      {client stream connection handle}
    size_min(buf.cmd.stdin_data.len),  {amount of data to read}
    [],                                {wait for data to arrive}
    buf.cmd.stdin_data.len,            {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then begin        {something went wrong ?}
    sys_error_print (stat, '', '', nil, 0);
    info.kill := kill_err_k;           {assume client went away, kill program}
    goto leave1;                       {abort thread}
    end;

  if buf.cmd.stdin_data.len = 0 then goto loop_cmd; {no data to send to program ?}

  file_read_inetstr (                  {read the actual data}
    info.conn_p^,                      {client stream connection handle}
    buf.cmd.stdin_data.len,            {amount of data to read}
    [],                                {wait for data to arrive}
    buf.cmd.stdin_data.data,           {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then begin        {something went wrong ?}
    sys_error_print (stat, '', '', nil, 0);
    info.kill := kill_err_k;           {assume client went away, kill program}
    goto leave1;                       {abort thread}
    end;

  ok := WriteFile (                    {send the data to the program}
    info.stdin_h,                      {I/O handle}
    buf.cmd.stdin_data.data,           {output buffer}
    buf.cmd.stdin_data.len,            {amount of data to write}
    nwrite,                            {amount of data actually written}
    nil);                              {no overlap info supplied}
  if ok = win_bool_false_k then begin  {error writing to program ?}
    goto leave1;
    end;
  end;
{
*   The client is sending one line of text for the program's standard input.
}
csrv_cmd_stdin_line_k: begin
  file_read_inetstr (                  {read data length word}
    info.conn_p^,                      {client stream connection handle}
    size_min(buf.cmd.stdin_line.len),  {amount of data to read}
    [],                                {wait for data to arrive}
    buf.cmd.stdin_line.len,            {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then begin        {something went wrong ?}
    sys_error_print (stat, '', '', nil, 0);
    info.kill := kill_err_k;           {assume client went away, kill program}
    goto leave1;                       {abort thread}
    end;

  if buf.cmd.stdin_line.len > 0 then begin {there are characters on this line ?}
    file_read_inetstr (                {read the actual data}
      info.conn_p^,                    {client stream connection handle}
      buf.cmd.stdin_line.len,          {amount of data to read}
      [],                              {wait for data to arrive}
      buf.cmd.stdin_line.line,         {input buffer}
      olen,                            {amount of data actually read}
      stat);
    if sys_error(stat) then begin      {something went wrong ?}
      sys_error_print (stat, '', '', nil, 0);
      info.kill := kill_err_k;         {assume client went away, kill program}
      goto leave1;                     {abort thread}
      end;
    end;

  buf.cmd.stdin_line.len :=            {add CR to end of buffer}
    buf.cmd.stdin_line.len + 1;
  buf.cmd.stdin_line.line[buf.cmd.stdin_line.len] := chr(13);
  buf.cmd.stdin_line.len :=            {add LF to end of buffer}
    buf.cmd.stdin_line.len + 1;
  buf.cmd.stdin_line.line[buf.cmd.stdin_line.len] := chr(10);

  ok := WriteFile (                    {send the text line to the program}
    info.stdin_h,                      {I/O handle}
    buf.cmd.stdin_line.line,           {output buffer}
    buf.cmd.stdin_line.len,            {amount of data to write}
    nwrite,                            {amount of data actually written}
    nil);                              {no overlap info supplied}
  if ok = win_bool_false_k then begin  {error writing to program ?}
    goto leave1;
    end;
  end;
{
*   The client wants to stop the program.
}
csrv_cmd_stop_k: begin
  info.kill := kill_client_k;          {indicate to kill the program when we exit}
  goto leave1;                         {exit this thread}
  end;
{
*   Unexpected command received from the client.
}
otherwise
    end;                               {end of client command cases}

  goto loop_cmd;                       {back to process next client command}

leave1:                                {exit, ovl I/O event handle still exists}
  discard( CloseHandle(event_io_h) );  {try to close overlapped I/O event handle}

leave0:                                {common exit point}
  copy_in := 0;                        {set function return value (unused)}
  end;
{
**************************
*
*   Start of main routine.
}
begin
  sys_run (                            {try to run program as requested by client}
    cmline,                            {command line to execute}
    sys_procio_talk_k,                 {set up pipes for talking to prog STDIO}
    stdin_h, stdout_h, stderr_h,       {returned handles to our ends of STDIO pipes}
    procid,                            {returned handle to new process}
    stat);
  sys_msg_parm_vstr (msg_parm[1], cmline);
  if                                   {unable to get program launched ?}
      sys_error_check (stat, 'sys', 'run', msg_parm, 1) then begin
    stopstat := csrv_exstat_nogo_k;    {indicate program never started}
    goto leave;
    end;

  InitializeCriticalSection (crsect);  {init interlock for sending to client}
{
*   The subordinate program has been successfully launched.
*   Now create thread for copying the program's standard output to the client.
}
  copy_stdout.h := stdout_h;           {handle to copy from}
  copy_stdout.conn_p := addr(conn_client); {pointer to client connection handle}
  copy_stdout.crsect_p := addr(crsect); {pointer to client send interlock}
  if csrv_runopt_out_text_k in opts
    then begin                         {standard output form is TEXT}
      copy_stdout.rsp := csrv_rsp_stdout_line_k; {responses will be lines of text}
      p := addr(copy_out_text);        {get pointer to thread routine}
      end
    else begin                         {standard output format is BINARY}
      copy_stdout.rsp := csrv_rsp_stdout_data_k; {responses will be raw bytes}
      p := addr(copy_out_bin);         {get pointer to thread routine}
      end
    ;
  thread_stdout_h := CreateThread (    {start thread to copy standard output}
    nil,                               {no security attributes supplied}
    0,                                 {use default initial stack size}
    p,                                 {pointer to thread routine}
    addr(copy_stdout),                 {thread routine argument}
    [],                                {additional thread creation flags}
    thread_id);                        {ID of the new thread}
  active_stdout := thread_stdout_h <> handle_none_k; {TRUE if thread created}
{
*   Create thread for copying program's standard error output to the client.
}
  copy_stderr.h := stderr_h;           {handle to copy from}
  copy_stderr.conn_p := addr(conn_client); {pointer to client connection handle}
  copy_stderr.crsect_p := addr(crsect); {pointer to client send interlock}
  if csrv_runopt_err_text_k in opts
    then begin                         {standard output form is TEXT}
      copy_stderr.rsp := csrv_rsp_errout_line_k; {responses will be lines of text}
      p := addr(copy_out_text);        {get pointer to thread routine}
      end
    else begin                         {standard output format is BINARY}
      copy_stderr.rsp := csrv_rsp_errout_data_k; {responses will be raw bytes}
      p := addr(copy_out_bin);         {get pointer to thread routine}
      end
    ;
  thread_stderr_h := CreateThread (    {start thread to copy standard output}
    nil,                               {no security attributes supplied}
    0,                                 {use default initial stack size}
    p,                                 {pointer to thread routine}
    addr(copy_stderr),                 {thread routine argument}
    [],                                {additional thread creation flags}
    thread_id);                        {ID of the new thread}
  active_stderr := thread_stderr_h <> handle_none_k; {TRUE if thread created}
{
*   Create the thread that will process client commands.
}
  copy_stdin.conn_p := addr(conn_client); {address of handle to client connection}
  copy_stdin.stdin_h := stdin_h;       {handle to program's standard input pipe}
  copy_stdin.kill := kill_no_k;        {init to not kill program on thread exit}
  copy_stdin.stop_h := CreateEventA (  {create event for stopping COPY_IN thread}
    nil,                               {no security attributes specified}
    win_bool_true_k,                   {event only reset manually}
    win_bool_false_k,                  {event is initially not signalled}
    nil);                              {this event will have no name}

  thread_stdin_h := CreateThread (     {start thread to handle standard input}
    nil,                               {no security attributes supplied}
    0,                                 {use default initial stack size}
    addr(copy_in),                     {pointer to thread routine}
    addr(copy_stdin),                  {thread routine argument}
    [],                                {additional thread creation flags}
    thread_id);                        {ID of the new thread}
  active_stdin := thread_stdin_h <> handle_none_k; {TRUE if thread created}
{
*   All three threads that handle the three standard I/O connections of the
*   program have been launched.
}
loop_threads:                          {back here to wait for the next event}
  nwait := 0;                          {init number of things to wait on}

  if active_stdout then begin          {STDOUT thread is still active ?}
    waitlist[nwait] := thread_stdout_h;
    waitid[nwait] := waitid_stdout_k;
    nwait := nwait + 1;
    end;
  if active_stderr then begin          {STDERR thread is still active ?}
    waitlist[nwait] := thread_stderr_h;
    waitid[nwait] := waitid_stderr_k;
    nwait := nwait + 1;
    end;
  if active_stdin then begin           {STDIN thread is still active ?}
    waitlist[nwait] := thread_stdin_h;
    waitid[nwait] := waitid_stdin_k;
    nwait := nwait + 1;
    end;
  if nwait = 0 then goto done_threads; {nothing more left to wait on ?}

  sys_error_none (stat);
  donewait := WaitForMultipleObjects ( {wait for next event}
    nwait,                             {number of handles to wait on}
    waitlist,                          {list of handles to wait on}
    win_bool_false_k,                  {wait for any event, not all together}
    timeout_infinite_k);               {wait indefinitely for event to occur}
  if                                   {something went wrong ?}
      (ord(donewait) < 0) or
      (ord(donewait) >= nwait)
      then begin
    stat.sys := GetLastError;          {get reason for wait failure}
    sys_error_abort (stat, '', '', nil, 0); {this is really serious}
    end;

  case waitid[ord(donewait)] of        {which event occurred ?}
waitid_stdout_k: begin                 {standard output copy thread completed}
      active_stdout := false;          {indicate thread is no longer active}
      discard( CloseHandle(thread_stdout_h) ); {close handle to the thread}
      discard( CloseHandle(stdout_h) ); {close handle to I/O connection}
      end;
waitid_stderr_k: begin                 {standard error copy thread completed}
      active_stderr := false;          {indicate thread is no longer active}
      discard( CloseHandle(thread_stderr_h) ); {close handle to the thread}
      discard( CloseHandle(stderr_h) ); {close handle to I/O connection}
      end;
waitid_stdin_k: begin                  {standard input copy thread completed}
      active_stdin := false;           {indicate thread is no longer active}
      discard( CloseHandle(thread_stdin_h) ); {close handle to the thread}
      discard( CloseHandle(stdin_h) ); {close handle to I/O connection}
      discard( CloseHandle(copy_stdin.stop_h) ); {close thread stop event handle}
      if copy_stdin.kill <> kill_no_k then begin {we need to kill the program ?}
        case copy_stdin.kill of        {why are we killing the program ?}
kill_client_k: exstat_sys := sys_sys_exstat_wekill_k;
otherwise                              {assume an error occurred}
          exstat_sys := sys_sys_exstat_wekill_k - 1;
          end;                         {end of kill reason cases}
        discard( TerminateProcess (    {try to kill the program}
          procid,                      {handle to program's process}
          exstat_sys) );               {set exit status of process}
        end;                           {end of we try to kill program}
      end;                             {end of STDIN thread completed case}
    end;                               {end of event type cases}

  i := 0;                              {make 0-7 indicating active threads}
  if active_stdout
    then i := i ! 1;
  if active_stderr
    then i := i ! 2;
  if active_stdin
    then i := i ! 4;
  case i of                            {what combination of threads are active}
0:  begin                              {all thread have stopped}
      goto done_threads;
      end;
4:  begin                              {out threads ended, input thread still active}
      discard( SetEvent(copy_stdin.stop_h) ); {signal input thread to stop}
      end;
    end;                               {end of active thread combination cases}
  goto loop_threads;                   {back and wait for next event}
{
*   All the threads have stopped.
}
done_threads:
  DeleteCriticalSection (crsect);      {done with thread interlock for client send}

  discard( WaitForSingleObject (       {wait a little while to let program stop}
    procid,                            {handle to process to wait on}
    2000) );                           {milliseconds before we give up waiting}

  sys_error_none (stat);
  ok := GetExitCodeProcess (           {try to get the program's exit status code}
    procid,                            {handle to program's process}
    exstat_sys);                       {returned process' exit status code}
  if ok = win_bool_false_k
    then begin                         {didn't get process exit status code}
      stat.sys := GetLastError;
      sys_error_print (stat, '', '', nil, 0);
      stopstat := csrv_exstat_unk_k;   {indicate exit status is unknown}
      end
    else begin                         {we have process exit status code}
      case exstat_sys of               {why did program terminate ?}
sys_sys_exstat_ok_k: stopstat := csrv_exstat_ok_k;
sys_sys_exstat_false_k: stopstat := csrv_exstat_false_k;
sys_sys_exstat_warn_k: stopstat := csrv_exstat_warn_k;
sys_sys_exstat_abort_k: stopstat := csrv_exstat_abort_k;
sys_sys_exstat_running_k: stopstat := csrv_exstat_run_k;
sys_sys_exstat_wekill_k: stopstat := csrv_exstat_stop_k;
sys_sys_exstat_wekill_k-1: stopstat := csrv_exstat_svkill_k;
otherwise
        stopstat := csrv_exstat_err_k; {indicate general program failure}
        end;                           {end of process exit status code cases}
      end                              {end of case where we have exit status code}
    ;                                  {STOPSTAT all set}

  discard( CloseHandle(procid) );      {release our handle to the program}
{
*   Common exit point.  STOPSTAT must be set to the program exit status to
*   report to the client.
}
leave:
  rsp.rsp := csrv_rsp_stop_k;          {set response ID}
  rsp.stop.stat := stopstat;           {indicate program's status}

  file_write_inetstr (                 {send response packet back to client}
    rsp,                               {data to send}
    conn_client,                       {client stream connection handle}
    offset(rsp.stop) + size_min(rsp.stop), {amount of data to send}
    stat);
  sys_error_print (stat, 'file', 'write_inetstr_server', nil, 0);
  end;
{
*****************************************************************************
*
*   Subroutine CSRV_WAIT_CLIENT (SERV)
*
*   This routine is the main loop of the COGSERVE server.  It waits for new
*   client connections, and handles them.  This routine is an infinite loop.
*
*   SERV is the handle to the previously established server port.
}
procedure csrv_wait_client (           {wait for, then handle client connections}
  in      serv: file_inet_port_serv_t); {handle to server port}
  val_param;

var
  conn: file_conn_t;                   {connection handle to client stream}
  rem_adr: sys_inet_adr_node_t;        {internet address of client node}
  rem_port: sys_inet_port_id_t;        {port number of client on remote node}
  s: string_var32_t;                   {scratch string}
  stat: sys_err_t;                     {error status code}

label
  next_client, done_show_client;

begin
  s.max := size_char(s.str);           {init local var string}
{
*   Main loop.  Back here to wait for each new client connection request.
}
next_client:
  if debug >= 1 then begin
    writeln;
    writeln ('Waiting for client to request connection.');
    end;

  file_open_inetstr_accept (serv, conn, stat); {wait for client connection request}
  if sys_error_check (stat, 'file', 'inetstr_accept', nil, 0) then begin
    goto next_client;                  {back and try again with next client}
    end;

  if debug >= 1 then begin
    file_inetstr_info_remote (         {get info about client end of connection}
      conn,                            {handle to internet stream connection}
      rem_adr,                         {returned address of client node}
      rem_port,                        {returned client port number on remote node}
      stat);
    if sys_error_check(stat, 'file', 'inet_info_remote', nil, 0) {error getting info ?}
      then goto done_show_client;
    string_f_inetadr (s, rem_adr);
    writeln ('Connected to client ', s.str:s.len, ' at port ', rem_port, '.');
done_show_client:                      {done showing info about client}
    end;

  csrv_client (conn);                  {handle this client}
  goto next_client;                    {back to wait for next client connect request}
  end;
