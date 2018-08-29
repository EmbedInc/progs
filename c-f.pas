{   C-F degC
*
*   Converts degrees Celsius to degrees Farenheit.
}
program c_to_f;
%include 'base.ins.pas';

var
  degf: real;                          {degrees Farenheit}
  degc: real;                          {degrees Celsius}
  tk:
    %include '(cog)lib/string32.ins.pas';
  stat: sys_err_t;

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token_fpm (degc, stat); {get the command line argument}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no more command line arguments allowed}
  degf := (degc * 9.0 / 5.0) + 32.0;
  string_f_fp_fixed (tk, degf, 2);
  writeln (tk.str:tk.len);
  end.
