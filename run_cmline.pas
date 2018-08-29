{   Program RUN_CMLINE command-line
*
*   This program is for running a command line program from a program that has
*   command line output, but where the user must be able to see the output.  If
*   a command line program is run directly from a GUI program, the command line
*   window pops away immediately when the program exist.  This program run the
*   target program, but then stays until the user dismisses it, thereby keeping
*   the window visible until the user is done with it.
}
program run_cmline;
%include 'base.ins.pas';

type
  exit_k_t = (                         {how this program should exit}
    exit_norm_k,                       {exit normally}
    exit_false_k,                      {exit indicating false condition, not a error}
    exit_err_k);                       {exit with error condition}

var
  parm:                                {one command line parameter}
    %include '(cog)lib/string8192.ins.pas';
  cmline:                              {command line to execute}
    %include '(cog)lib/string8192.ins.pas';
  tf: boolean;                         {true/false response from target program}
  exstat: sys_sys_exstat_t;            {target program exit status code}
  exmode: exit_k_t;                    {how this program is supposed to exit}
  stat: sys_err_t;                     {completion status}

label
  leave;

begin
  exmode := exit_err_k;                {init to exit this program with error status}

  string_cmline_init;                  {init for reading the command line}
  cmline.len := 0;                     {init target command line to empty}
  while true do begin                  {back here each new command line parameter}
    string_cmline_token (parm, stat);  {get this command line parameter}
    if string_eos(stat) then exit;     {exhausted the command line ?}
    if cmline.len = 0 then begin       {this token is executable pathname ?}
      string_copy (parm, cmline);
      string_treename (cmline, parm);  {expand to full pathname in system format}
      cmline.len := 0;
      end;
    string_append_token (cmline, parm); {add this parameter to end of command line}
    end;                               {back for next token from the command line}
  if cmline.len <= 0 then begin        {no target program specified ?}
    sys_message ('stuff', 'err_no_command');
    goto leave;
    end;

  sys_run_wait_stdsame (               {run the target program}
    cmline,                            {the command line to execute}
    tf, exstat,                        {returned true/false result and exit status}
    stat);
  if sys_error_check (stat, '', '', nil, 0) then goto leave;

  exmode := exit_norm_k;               {init to exit normally, no error}
  if not tf then exmode := exit_false_k; {exit indicating false, no error}
  if exstat > 1 then exmode := exit_err_k; {exit with error status}
  writeln;                             {leave blank line after target program output}

leave:                                 {common exit point}
  string_f_message (parm, 'stuff', 'wait_enter', nil, 0);
  string_append1 (parm, ' ');
  string_prompt (parm);
  string_readin (parm);                {wait for user to hit ENTER}

  case exmode of                       {how to exit this program ?}
exit_norm_k: sys_exit;
exit_false_k: sys_exit_false;
otherwise
    sys_exit_error;
    end;
  end.
