{   Program TREENAME path
*
*   Expand PATH to the full absolute pathname, and write it to standard output.
*   Embed portable pathname rules are used to interpret PATH.  The result is in
*   the format used by the local system (can be passed directly to native system
*   commands, for example).
*
*   If there is no command line argument, then the current directory is
*   returned.  This is the same as if PATH was ".".
}
program treename;
%include 'base.ins.pas';

var
  path,                                {input pathname}
  tnam:                                {resulting absolute treename}
    %include '(cog)lib/string_treename.ins.pas';
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (path, stat);    {get PATH}
  if string_eos(stat) then begin       {no command line argument}
    path.len := 0;                     {default to expand empty string}
    end;
  sys_error_abort (stat, '', '', nil, 0); {hard error getting input pathname }
  string_cmline_end_abort;             {no more command line arguments allowed}

  string_treename (path, tnam);        {expand PATH into TNAM}
  writeln (tnam.str:tnam.len);         {write result to standard output}
  end.
