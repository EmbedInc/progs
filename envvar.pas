{   Program ENVVAR <environment variable name> [-LC] [<option>]
*
*   Manipulate a environment variable.
}
program envvar;
%include 'base.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  lc: string_var4_t :=                 {name of -LC command line option}
    [str := '-LC', len := 3, max := sizeof(lc.str)];
  noerr_str: string_var16_t :=         {name of NOERR command line parameter}
    [str := 'NOERR', len := 5, max := sizeof(noerr_str.str)];
  pick: sys_int_machine_t;             {number of token picked from list}
  defval: boolean;                     {TRUE when default value supplied}
  noerr: boolean;                      {TRUE when error reporting suppressed}
  changed: boolean;                    {value was changed}
  flags: sys_envvar_t;                 {flags about system startup values}
  name,                                {environment variable name}
  opt:                                 {command line option name}
    %include '(cog)lib/string80.ins.pas';
  token,                               {scratch token string}
  val:                                 {environment variable value}
    %include '(cog)lib/string8192.ins.pas';
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  lc_no, lc_yes, next_token, done_tokens, sysset;

begin
  string_cmline_init;                  {init for command line processing}
{
*   Get environment variable name.
}
  string_cmline_token (name, stat);    {get env var name from command line}
  string_cmline_req_check (stat);      {env var name is required on command line}
{
*   Check for optional -LC flag.
}
  string_cmline_token (opt, stat);     {get -LC option, if present}
  if string_eos(stat) then goto lc_no; {no command line token left at all ?}
  sys_error_abort (stat, '', '', nil, 0);
  string_upcase (opt);                 {make upper case for comparison}
  if string_equal(opt, lc) then goto lc_yes; {this really is the -LC option}
  string_cmline_reuse;                 {isn't -LC, put command line option back}
lc_no:                                 {-LC command line option is not present}
  string_upcase (name);                {convert variable name to all upper case}
lc_yes:                                {jump here if -LC command line option found}
{
*   Processes the operation option.
}
  string_cmline_token (opt, stat);     {get operation option}
  if string_eos(stat) then begin       {no token present, replace with default}
    string_vstring (opt, '-GET', 4);
    end;
  sys_error_abort (stat, '', '', nil, 0);
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,
    '-GET -SET -DEL -SGET -SSET -SSETS -SSETE -SDEL',
    pick);
  case pick of
{
*   -GET [<default value>]
}
1: begin
  string_cmline_token (token, stat);   {get default value if present}
  defval := not string_eos(stat);      {TRUE if default value present}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no more tokens allowed on command line}
  sys_envvar_get (name, val, stat);    {try to get variable's value}
  if sys_stat_match (sys_subsys_k, sys_stat_envvar_noexist_k, stat) then begin
    if defval
      then begin                       {variable didn't exist, use default value}
        string_copy (token, val);
        end
      else begin                       {variable didn't exist, report as error}
        sys_stat_set (sys_subsys_k, sys_stat_envvar_noexist_k, stat);
        sys_stat_parm_vstr (name, stat);
        sys_error_print (stat, '', '', nil, 0);
        sys_exit_error;
        end
      ;
    end;                               {done handling variable not found}
  sys_error_abort (stat, '', '', nil, 0);
  writeln (val.str:val.len);           {write value to standard output}
  end;
{
*   -SET [<value token 1> ... <value token N>]
}
2: begin
  string_cmline_token (val, stat);     {init total value string to first token}
  if string_eos(stat) then goto done_tokens; {no more value string tokens ?}
  sys_error_abort (stat, '', '', nil, 0);
next_token:                            {back here to read each new cmline token}
  string_cmline_token (token, stat);   {get next value string token}
  if string_eos(stat) then goto done_tokens; {no more value string tokens ?}
  sys_error_abort (stat, '', '', nil, 0);
  string_append1 (val, ' ');           {add separator between tokens}
  string_append (val, token);          {add this token to end of string}
  goto next_token;                     {back to get next command line token}
done_tokens:                           {all done getting command line tokens}
  sys_envvar_set (name, val, stat);    {set environment variable to new value}
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
*   -DEL [NOERR]
}
3: begin
  noerr := false;                      {init to errors should be reported}
  string_cmline_token (token, stat);   {get NOERR token, if present}
  if not string_eos(stat) then begin   {there was something on command line ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_upcase (token);             {make upper case for keyword matching}
    if not string_equal (token, noerr_str) then begin {not NOERR keyword ?}
      sys_msg_parm_vstr (msg_parm[1], token);
      sys_msg_parm_vstr (msg_parm[2], opt);
      sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);
      end;
    noerr := true;                     {inhibit error reporting}
    string_cmline_end_abort;           {no more tokens allowed on command line}
    end;                               {NOERR flag all set}
  sys_envvar_del (name, stat);         {try to delete environment variable}
  if noerr then sys_error_none (stat); {inhibit error reporting ?}
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
*   -SGET
*
*   Get the system startup value for this variable.
}
4: begin
  sys_envvar_startup_get (
    name,                              {variable name}
    val,                               {returned value}
    flags,                             {returned indicator flags}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  writeln (val.str:val.len);           {write variable value}
  if flags <> [] then begin
    write ('  Flags:');
    if sys_envvar_noexp_k in flags then begin
      write (' NOEXP');
      end;
    if sys_envvar_expvar_k in flags then begin
      write (' EXPVAR');
      end;
    writeln;
    end;
  end;
{
*   -SSET val
}
5: begin
  flags := [];

sysset:                                {common code to set system startup value}
  string_cmline_token (val, stat);
  sys_error_abort (stat, '', '', nil, 0);
  changed := sys_envvar_startup_set (  {set system startup value for this variable}
    name,                              {variable name}
    val,                               {value to set it to}
    flags,                             {option flags}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  if changed
    then writeln ('Changed')
    else writeln ('No change');
  end;
{
*   -SSETS
}
6: begin
  flags := [sys_envvar_noexp_k];       {specify no variable expansion}
  goto sysset;
  end;
{
*   -SSETE
}
7: begin
  flags := [sys_envvar_expvar_k];      {specify variable expansion}
  goto sysset;
  end;
{
*   -SDEL
}
8: begin
  sys_envvar_startup_del (name, stat);
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
*   Unrecognized command line option.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_bad', msg_parm, 1);
    end;
  end.
