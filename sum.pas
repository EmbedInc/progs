{   Quick hack to add up all the command line arguments.
}
program sum;
%include 'base.ins.pas';

var
  parm:                                {last token parsed from command line}
    %include '(cog)lib/string80.ins.pas';
  iparm: sys_int_max_t;                {integer parameter value}
  fpparm: sys_fp_max_t;                {floating point parameter value}
  ival: sys_int_max_t;                 {current sum if value is integer}
  fval: sys_fp_max_t;                  {current sum if value is floating point}
  valfp: boolean;                      {sum is in floating point format}
  stat: sys_err_t;                     {completion status}

label
  loop_parm, parm_fp, done_parms;

begin
  ival := 0;                           {init sum}
  valfp := false;                      {sum starts out integer}
  string_cmline_init;                  {init for reading the command line}

loop_parm:                             {back here each new command line parameter}
  string_cmline_token (parm, stat);    {get next command line parameter into PARM}
  if string_eos(stat) then goto done_parms; {exhausted the command line ?}
  sys_error_abort (stat, '', '', nil, 0);
  if valfp then goto parm_fp;          {sum already floating point ?}
{
*   Try to interpret parameter as integer.
}
  string_t_int_max (parm, iparm, stat); {try to convert parameter string to integer}
  if sys_error(stat) then goto parm_fp; {integer didn't work, try floating point ?}
  ival := ival + iparm;                {update sum}
  goto loop_parm;                      {back for next command line parameter}
{
*   Interpret parameter as floating point.
}
parm_fp:
  string_t_fpmax (parm, fpparm, [], stat); {convert parameter string to floating point}
  sys_error_abort (stat, '', '', nil, 0);
  if not valfp then begin              {current sum is integer ?}
    fval := ival;                      {make FP sum}
    valfp := true;                     {indicate using floating point from now on}
    end;
  fval := fval + fpparm;               {update the sum}
  goto loop_parm;

done_parms:                            {done with all command line parameters}
  if valfp
    then begin                         {sum is floating point}
      string_f_fp_free (parm, fval, 8); {make FP value string}
      writeln (parm.str:parm.len);     {write it out}
      end
    else begin                         {sum is integer}
      writeln (ival);                  {write it out}
      end
    ;
  end.
