{   F-C degF
*
*   Converts degrees Farenheit to degrees Celsius.
}
program f_to_c;
%include 'base.ins.pas';

var
  degf: real;                          {degrees Farenheit}
  degc: real;                          {degrees Celsius}
  tk:
    %include '(cog)lib/string32.ins.pas';
  stat: sys_err_t;

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token_fpm (degf, stat); {get the command line argument}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no more command line arguments allowed}
  degc := (degf - 32.0) * 5.0 / 9.0;
  string_f_fp_fixed (tk, degc, 2);
  writeln (tk.str:tk.len);
  end.
