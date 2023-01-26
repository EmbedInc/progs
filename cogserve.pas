{   Program COGSERVE <options>
*
*   This program runs the COGSERVE server used for remote file system access
*   and other remote functions needed by the Cognivision interoperability
*   environment.
*
*   Command line options are:
*
*     -DEBUG level
*
*     Set the level of informational debug messages to be issued to standard
*     output.  A value of zero disables all debug messages.  A value of 10
*     results in the maximum debug information to be printed.  The default is
*     zero.
}
program cogserve;
%include 'cogserve_prog.ins.pas';

var
  serv: file_inet_port_serv_t;         {handle to our public server socket}

  opt:                                 {command line option name}
    %include '(cog)lib/string32.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  stat: sys_err_t;

label
  next_opt, done_opts;

begin
  string_cmline_init;                  {init for reading command line}

  debug := 0;                          {init before processing command line}
{
*   Process the command line options.  Come back here each new command line
*   option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (                    {pick option name from list}
    opt,                               {option name}
    '-DEBUG',
    pick);                             {number of picked option}
  case pick of                         {do routine for specific option}
{
*   -DEBUG level
}
1: begin
  string_cmline_token_int (debug, stat);
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}
done_opts:                             {done reading the command line}

  debug := max(0, min(10, debug));     {clip DEBUG to legal limits}
{
*   Set ourselves up as a server.
}
  file_create_inetstr_serv (           {create server socket waiting for clients}
    sys_sys_inetnode_any_k,            {respond to any addresses this node has}
    csrv_port_k,                       {our "well known" port number}
    serv,                              {returned handle to our server socket}
    stat);
  if sys_error(stat) then begin        {requesting fixed port number didn't work ?}
    file_create_inetstr_serv (         {create server socket waiting for clients}
      sys_sys_inetnode_any_k,          {respond to any addresses this node has}
      sys_sys_inetport_unspec_k,       {let system pick port number}
      serv,                            {returned handle to our server socket}
      stat);
    end;
  sys_error_abort (stat, 'file', 'create_server', nil, 0);
  writeln ('COGSERVE Server established at internet port ', serv.port, '.');

  csrv_wait_client (serv);             {wait for and process client requests}
  end.
