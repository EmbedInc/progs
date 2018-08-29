{   Program QUAD a b c
*
*   Solves a quadratic equation.  Specifically, the equation is:
*
*     A x^2 + B x + C = 0
*
*   The coefficients A, B, and C are entered on the command line.  The program
*   solves for X and displays the result.
}
program quad;
%include 'base.ins.pas';

var
  a, b, c: double;                     {quadratic coefficients}
  r: double;                           {scratch for intermediate calculations}
  s1, s2: double;                      {the solutions}
  tk:                                  {scratch strings for formatting answer}
    %include '(cog)lib/string32.ins.pas';
  stat: sys_err_t;

begin
  string_cmline_init;
  string_cmline_token_fp2 (a, stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_token_fp2 (b, stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_token_fp2 (c, stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;

  r := sqr(b) - 4.0 * a * c;           {value to take square root of}
  if r < 0.0 then begin
    writeln ('No solution');
    return;
    end;
  r := sqrt(r);

  s1 := (-b + r) / (2.0 * a);          {solution 1}
  s2 := (-b - r) / (2.0 * a);          {solution 2}

  string_f_fp (                        {make solution 1 string}
    tk,                                {output string}
    s1,                                {input value}
    0, 0,                              {free form, no fixed field width}
    5,                                 {minimum significant digits to show}
    6,                                 {max allowed digits left of point}
    0,                                 {min required digits right of point}
    5,                                 {max allowed digits right of point}
    [string_ffp_exp_eng_k],            {engineering notation when exp used}
    stat);
  write ('Solutions: ', tk.str:tk.len);

  string_f_fp (                        {make solution 2 string}
    tk,                                {output string}
    s2,                                {input value}
    0, 0,                              {free form, no fixed field width}
    5,                                 {minimum significant digits to show}
    6,                                 {max allowed digits left of point}
    0,                                 {min required digits right of point}
    5,                                 {max allowed digits right of point}
    [string_ffp_exp_eng_k],            {engineering notation when exp used}
    stat);
  writeln (', ', tk.str:tk.len);
  end.
