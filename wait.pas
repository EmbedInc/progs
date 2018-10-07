{   Program WAIT <seconds>
*
*   Suspend the process for the indicated number of seconds.
}
program wait;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';

var
  seconds: real;                       {number of seconds to wait}
  r: sys_fp1_t;                        {for getting command line values}
  opt_first: boolean;                  {TRUE for first command line option}
  opt:                                 {command line option name}
    %include '(cog)lib/string32.ins.pas';
  pick: sys_int_machine_t;             {number of option name in list}
  stat: sys_err_t;

label
  next_parm, opt_err, parm_err, done_parms;

begin
  string_cmline_init;                  {init for command line parsing}
  seconds := 0.0;                      {init total seconds to wait}
  opt_first := true;                   {next command line token is the first}

next_parm:                             {back here for each new command line parameter}
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_parms; {exhausted command line ?}
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,
    '-S -M -H',
    pick);
  case pick of
{
*   -S sec
}
1: begin
  string_cmline_token_fp1 (r, stat);
  seconds := seconds + r;
  end;
{
*   -M min
}
2: begin
  string_cmline_token_fp1 (r, stat);
  seconds := seconds + (60.0 * r);
  end;
{
*   -H hours
}
3: begin
  string_cmline_token_fp1 (r, stat);
  seconds := seconds + (3600.0 * r);
  end;
{
*   Unrecognized command line option name.
}
otherwise
    if not opt_first then goto opt_err; {not the first token on command line ?}
    string_t_fp1 (opt, r, stat);       {is unexpected token an FP number ?}
    if sys_error(stat) then goto opt_err; {token is not a floating point number ?}
    string_cmline_end_abort;           {no more tokens allowed after this one}
    seconds := r;                      {this special token was seconds value}
    goto done_parms;                   {no more command line parameters left}
opt_err:                               {jump here on bad command line option token}
    string_cmline_opt_bad;
    end;                               {end of option name cases}
parm_err:                              {jump here if parameter error}
  string_cmline_parm_check (stat, opt); {check for parameter error}
  opt_first := false;                  {next option no longer the first}
  goto next_parm;
done_parms:                            {jump here when all done with comline parms}

  sys_wait (seconds);
  end.
