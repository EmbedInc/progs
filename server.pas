{   Program SERVER [options]
*
*   Run program in a separate process in the background as a server.
}
program server;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

type
  out_t = record                       {info for copying a standard output stream}
    in: sys_sys_iounit_t;              {raw system handle to stream from process}
    out: sys_sys_iounit_t;             {our standard stream ID to write to}
    done: boolean;                     {TRUE if done copying all data (hit EOF)}
    end;
  out_p_t = ^out_t;

var
  proc: sys_sys_proc_id_t;             {ID of new process}
  wait: real;                          {seconds to wait for process to get started}
  dir: string_treename_t;              {name of directory to run process in}
  cmline: string_var_max_t;            {command line of new process}
  stdout: out_t;                       {info for copying STDOUT stream}
  stderr: out_t;                       {info for copying STDERR stream}
  sin, sout, serr: sys_sys_iounit_t;   {handles to process' I/O streams}
  thread_out: sys_sys_thread_id_t;     {ID of thread copying STDOUT stream}
  thread_err: sys_sys_thread_id_t;     {ID of thread copying STDERR stream}
  clock_done: sys_clock_t;             {time when done waiting on child process}
  exstat: sys_sys_exstat_t;            {exit status of child process}

  pick: sys_int_machine_t;             {number of token picked from list}
  opt: string_var_max_t;               {current command line option name}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  loop_cmopt, loop_runtk, have_runtk, done_cmopts, loop_wait, release;
{
********************************************************************************
*
*   Subroutine COPYOUT (OUT_P)
*
*   This routine is run in a separate thread.  It runs as an infinite loop
*   copying data from the child process to one of our standard output streams.
}
procedure copyout (                    {copy data from IN to OUT I/O connection}
  in      out_p: out_p_t);             {pointer in/out streams to copy from/to}
  val_param;

var
  conn_in, conn_out: file_conn_t;      {connections to IN and OUT streams}
  ilen: sys_int_adr_t;                 {amount of data actually read in}
  buf: array[1..1024] of int8u_t;      {I/O buffer}
  stat: sys_err_t;

label
  loop, leave;

begin
  file_open_stream_bin (               {open connection to input stream}
    sys_sys_iounit_stdin_k,            {pretend we are connecting to our STDIN}
    [file_rw_read_k],                  {we will be reading from this stream}
    conn_in,                           {returned connection}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then goto leave;
  conn_in.sys := out_p^.in;            {set raw system stream to read from}

  file_open_stream_bin (               {open connection to our standard out stream}
    out_p^.out,                        {system stream ID to connect to}
    [file_rw_write_k],                 {we will be writing to this stream}
    conn_out,                          {returned connection}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then goto leave;

loop:                                  {inifinite loop to copy the data}
  file_read_bin (                      {read next chunk from input stream}
    conn_in,                           {stream connection}
    sizeof(buf),                       {max amount of data to read}
    buf,                               {the returned data}
    ilen,                              {amount of data actually read}
    stat);
  if file_eof(stat) then goto leave;   {exit normally on end of file}
  discard( file_eof_partial(stat) );   {partial buffer full is not an error}
  if sys_error_check (stat, '', '', nil, 0) then goto leave;

  file_write_bin (                     {copy the chunk to the output stream}
    buf,                               {the data to write}
    conn_out,                          {stream connection}
    ilen,                              {amount of data to write}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then goto leave;
  goto loop;                           {back to copy the next chunk of data}

leave:                                 {common exit point}
  out_p^.done := true;                 {indicate this thread is all done}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  dir.max := size_char(dir.str);       {init local var strings}
  cmline.max := size_char(cmline.str);
  opt.max := size_char(opt.str);
{
*   Initialize before processing the command line.
}
  string_cmline_init;                  {init for reading the command line}
  cmline.len := 0;                     {init process command line to empty}
  wait := 0.0;                         {init to release process immediately}
  dir.len := 0;                        {init to run process in current directory}

loop_cmopt:                            {back here each new command line option}
  string_cmline_token (opt, stat);     {get next command line token}
  if string_eos(stat) then goto done_cmopts; {exhausted the command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implied -RUN ?}
    goto have_runtk;                   {go process -RUN tokens}
    end;
  string_upcase (opt);                 {make upper case for keyword matching}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-IN -WAIT -RUN',
    pick);                             {number of the keyword picked from the list}
  case pick of                         {do routine for specific option}
{
*   -IN dir
}
1: begin
  string_cmline_token (dir, stat);
  end;
{
*   -WAIT sec
}
2: begin
  string_cmline_token_fpm (wait, stat);
  string_cmline_parm_check (stat, opt);
  wait := max(wait, 0.0);              {clip at zero}
  end;
{
*   -RUN <command line>
}
3: begin
loop_runtk:                            {back here each new -RUN token}
  string_cmline_token (opt, stat);     {get next command line token}
  if string_eos(stat) then goto done_cmopts; {exhausted the command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
have_runtk:                            {enter loop here if OPT already first token}
  string_append_token (cmline, opt);   {append token to end of process command line}
  goto loop_runtk;                     {back for next -RUN token}
  end;
{
*   Unrecognized command line option.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_bad', msg_parm, 1);
    end;

  string_cmline_parm_check (stat, opt); {check for parameter error}
  goto loop_cmopt;                     {back to get next command line option}
done_cmopts:                           {all done reading the command line}
{
*   Done reading the SERVER command line.  The process command line is in
*   CMLINE.
}
  if cmline.len <= 0 then begin        {no process command line supplied ?}
    sys_message_bomb ('sys', 'server_nocmline', nil, 0);
    end;

  if dir.len > 0 then begin            {specific directory for new process ?}
    file_currdir_set (dir, stat);      {go to the current directory for the process}
    sys_msg_parm_vstr (msg_parm[1], dir);
    sys_error_abort (stat, 'file', 'curr_dir_set', msg_parm, 1);
    end;
{
*   Handle the case where the process is to be released immediately with
*   no I/O connection to the parent.
}
  if wait <= 0.0 then begin            {release process immediately ?}
    sys_run (                          {start the new process}
      cmline,                          {command line for the new process}
      sys_procio_none_k,               {no standard I/O connection to parent process}
      sin, sout, serr,                 {handles to standard I/O, unused}
      proc,                            {ID of new process}
      stat);
    sys_msg_parm_vstr (msg_parm[1], cmline);
    sys_error_abort (stat, 'sys', 'proc_start_err', msg_parm, 1);
    goto release;                      {go release the child process}
    end;
{
*   We are to wait a while to see what the process does.  During that time,
*   the process standard I/O will be connected to our standard I/O.
}
  sys_run (                            {start the new process}
    cmline,                            {command line for the new process}
    sys_procio_talk_k,                 {make connections to child's STDIO streams}
    sin, sout, serr,                   {connections to the child's STDIO streams}
    proc,                              {ID of new process}
    stat);
  sys_msg_parm_vstr (msg_parm[1], cmline);
  sys_error_abort (stat, 'sys', 'proc_start_err', msg_parm, 1);

  clock_done := sys_clock_add (        {make time when to release process}
    sys_clock,                         {time now}
    sys_clock_from_fp_rel(wait));      {add on time to wait}

  stdout.in := sout;                   {set raw system ID to child process STDOUT}
  stdout.out := sys_sys_iounit_stdout_k; {unit of our std stream to write to}
  stdout.done := false;                {init to not done copying the stream yet}
  sys_thread_create (                  {start up thread to copy STDOUT}
    univ_ptr(addr(copyout)),           {pointer to root thread routine}
    sys_int_adr_t(addr(stdout)),       {argument passed to thread}
    thread_out,                        {returned ID of new thread}
    stat);
  sys_error_abort (stat, 'sys', 'thread_start', nil, 0);

  stderr.in := serr;                   {set raw system ID to child process STDERR}
  stderr.out := sys_sys_iounit_errout_k; {unit of our std stream to write to}
  stderr.done := false;                {init to not done copying the stream yet}
  sys_thread_create (                  {start up thread to copy STDERR}
    univ_ptr(addr(copyout)),           {pointer to root thread routine}
    sys_int_adr_t(addr(stderr)),       {argument passed to thread}
    thread_err,                        {returned ID of new thread}
    stat);
  sys_error_abort (stat, 'sys', 'thread_start', nil, 0);

loop_wait:                             {back here to check on process again}
  if
      stdout.done and                  {done copying all STDOUT from process ?}
      stderr.done and then             {done copying all STDERR from process ?}
      sys_proc_status (                {get status of the process}
        proc,                          {ID of the process inquiring about}
        false,                         {don't wait for process to terminate}
        exstat,                        {exit status of child process}
        stat)
      then begin                       {child process has stopped}
    if exstat = sys_sys_exstat_ok_k then sys_exit;
    if exstat = sys_sys_exstat_true_k then sys_exit_true;
    if exstat = sys_sys_exstat_false_k then sys_exit_false;
    sys_exit_error;
    end;

  sys_wait (0.2);                      {wait a short time}
  if sys_clock_compare(sys_clock, clock_done) = sys_compare_lt_k then begin
    goto loop_wait;                    {not yet time to release process}
    end;

release:                               {common code to release the child process}
  sys_proc_release (                   {let process run on its own}
    proc,                              {ID of the process to release}
    stat);
  sys_error_abort (stat, 'sys', 'proc_release', nil, 0);
  end.
