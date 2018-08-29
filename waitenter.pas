{   Program WAITENTER [-prompt string]
*
*   Wait for the user to hit ENTER.
}
program waitenter;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  prompt:                              {string to write to prompt user}
    %include '(cog)lib/string132.ins.pas';
  buf:                                 {string entered by the user}
    %include '(cog)lib/string8192.ins.pas';
  prompt_set: boolean;                 {explicit prompt string supplied}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize for reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  prompt_set := false;
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-PROMPT',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -PROMPT string
}
1: begin
  string_cmline_token (prompt, stat);
  prompt_set := true;
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
{
*   Done reading the command line.
}
  if not prompt_set then begin         {use default prompt ?}
    string_vstring (prompt, 'Hit ENTER to continue: '(0), -1);
    end;

  string_prompt (prompt);              {prompt user what to do}
  string_readin (buf);                 {get text entered by user}
  writeln (buf.str:buf.len);           {write user text to standard output}
  end.
