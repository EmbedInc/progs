{   Program TODO_FILE filename
*
*   Show the scheduled tasks listed in the input file whos time has arrived.
}
program todo_file;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  fnam_in:                             {input file name}
    %include '(cog)lib/string_treename.ins.pas';
  now: sys_clock_t;                    {time used for this run of the program}
  time: sys_clock_t;                   {task due time}
  iname_set: boolean;                  {TRUE if the input file name already set}
  fnam_written: boolean;               {file name has already been shown}
  conn: file_conn_t;                   {connection to the input file}
  ibuf:                                {one line input buffer}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {IBUF parse index}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts, loop_line, eof;
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
  iname_set := false;                  {no input file name specified}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not iname_set then begin        {input file name not set yet ?}
      string_copy (opt, fnam_in);      {set input file name}
      iname_set := true;               {input file name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-IN',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -IN filename
}
1: begin
  if iname_set then begin              {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (fnam_in, stat);
  iname_set := true;
  end;
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

  if not iname_set then begin
    sys_message_bomb ('string', 'cmline_input_fnam_missing', nil, 0);
    end;

  file_open_read_text (fnam_in, '.info ""', conn, stat); {open the input file}
  sys_error_abort (stat, '', '', nil, 0);
  fnam_written := false;               {init to input file name not shown}
  now := sys_clock;                    {set the current time for this run}

loop_line:                             {back here each new input line}
  file_read_text (conn, ibuf, stat);   {read new input line into IBUF}
  if file_eof(stat) then goto eof;     {hit end of file ?}
  sys_error_abort (stat, '', '', nil, 0);
  string_unpad (ibuf);                 {delete trailing spaces}
  if ibuf.len <= 0 then goto loop_line; {ignore blank lines}
  if ibuf.str[1] <> ':' then goto loop_line; {this line not starting a new task ?}
  p := 2;                              {init IBUF parse index}
  string_token (ibuf, p, parm, stat);  {get task due time token}
  if sys_error(stat) then goto loop_line; {ignore if no token present or other error}

  string_t_time1 (parm, true, time, stat); {convert to time this task is due}
  if sys_error(stat) then goto loop_line; {not a valid time string, ignore ?}

  if sys_clock_compare (now, time) = sys_compare_lt_k {not time for this task yet ?}
    then goto loop_line;
{
*   The task defined on the current line has triggered.
}
  if not fnam_written then begin       {not shown tasks source filename yet ?}
    writeln;
    writeln (conn.tnam.str:conn.tnam.len, ':');
    fnam_written := true;              {source file name has now been shown}
    end;

  for p := 2 to ibuf.len do begin      {shift string left to delete leading colon}
    ibuf.str[p-1] := ibuf.str[p];
    end;
  ibuf.len := ibuf.len - 1;
  writeln ('  ', ibuf.str:ibuf.len);
  goto loop_line;                      {back to process next line from input file}

eof:                                   {end of input file encountered}
  file_close (conn);                   {close the input file}
  end.
