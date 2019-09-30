{   Program SEQN3 fnam
*
*   Return the value in the sequence file FNAM, then increment the value by one.
*   The returned number is always at least 3 digits wide, padded with leading
*   zeros as necessary.
}
program seqn3;
%include 'base.ins.pas';

var
  fnam:                                {sequence number file name}
    %include '(cog)lib/string_treename.ins.pas';
  seq: sys_int_machine_t;              {sequence number}
  npad: sys_int_machine_t;             {number of leading zeros to add}
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam, stat);    {get sequence number file name}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;

  seq := string_seq_get (              {get the sequence number}
    fnam,                              {sequence number file name}
    1,                                 {increment}
    1,                                 {initial value on no file}
    [],                                {get the number before the increment}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_f_int (fnam, seq);            {make seq string without leading zeros}

  npad := 3 - fnam.len;                {number of leading zeros padding to add}
  while npad > 0 do begin              {write the leading zeros}
    write ('0');
    npad := npad - 1;
    end;
  writeln (fnam.str:fnam.len);         {write the number}
  end.
