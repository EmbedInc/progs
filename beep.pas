{   Program BEEP [<option1> <option2> . . .]
*
*   Produce a sequence of tones or beeps.  The exact nature of the tones
*   is system-dependent.  Command line options are:
*
*   -DUR s
*
*     Set beep duration in seconds.  The default is 0.5 seconds.
*
*   -WAIT s
*
*     Set the wait interval between beeps in seconds.  The default is 0.5
*     seconds.
*
*   -REP n
*
*     Explicitly specify the number of beeps to produce.  A wait will be
*     inserted between beeps.  The default is 1.
*
*   -REP *
*
*     Repeat the beep/wait sequence indefinately.  The default is to produce
*     only one beep.
}
program beep;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';

var
  dur: real;                           {beep duration seconds}
  wait: real;                          {wait duration seconds}
  rep: sys_int_machine_t;              {repeat count}

  opt,                                 {command line option name}
  parm:                                {parameter to command line option}
    %include '(cog)lib/string32.ins.pas';
  pick: sys_int_machine_t;             {number of option name in list}
  stat: sys_err_t;                     {error status code}

label
  next_parm, parm_err, done_parms;

begin
  string_cmline_init;                  {init reading our command line}
  dur := 0.5;                          {init to default values}
  wait := 0.5;
  rep := 1;

next_parm:                             {back here for each new command line parameter}
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_parms; {exhausted command line ?}
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,
    '-DUR -WAIT -REP',
    pick);
  case pick of
{
*   -DUR s
}
1: begin
  string_cmline_token_fpm (dur, stat);
  end;
{
*  -WAIT s
}
2: begin
  string_cmline_token_fpm (wait, stat);
  end;
{
*   -REP n or *
}
3: begin
  string_cmline_token (parm, stat);
  if sys_error(stat) then goto parm_err;
  if (parm.len = 1) and (parm.str[1] = '*')
    then begin                         {parameter is "*"}
      rep := sys_beep_forever;
      end
    else begin                         {parameter is not "*"}
      string_t_int (parm, rep, stat);  {interpret as an integer number}
      end
    ;
  end;
{
*   Unrecognized command line option name.
}
otherwise
    string_cmline_opt_bad;
    end;                               {end of option name cases}
parm_err:                              {jump here if parameter error}
  string_cmline_parm_check (stat, opt); {check for parameter error}
  goto next_parm;
done_parms:                            {jump here when all done with comline parms}

  sys_beep (dur, wait, rep);           {do all the beeping}
  end.
