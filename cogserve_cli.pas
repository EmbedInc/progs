{   Module of COGSERVE server client-side utilities.
}
module csrv;
define csrv_connect;
define csrv_stat_get;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'cogserve.ins.pas';
{
**********************************************************
*
*   Subroutine CSRV_CONNECT (MACHINE, CONN, INFO, STAT)
*
*   Establish a connection to the COGSERVE server running on the indicated
*   machine.  This routine verifies the server and checks the server version.
*   If all verifies correctly, then INFO is returned with information
*   about this specific server.  INFO may be filled in even on some errors,
*   like version incompatibility.  CONN is only set if STAT indicates no errors.
*
*   By default, the standard COGSERVE port number is assumed.  This can be
*   overridden by an environment variable with the name COGSERVE_<machine>,
*   where <machine> is the upper case name of the remote machine as passed
*   in MACHINE.  The value of such an environment variable must be the
*   decimal integer string of the port number to use.
}
procedure csrv_connect (               {connect to a COGSERVE server}
  in      machine: univ string_var_arg_t; {machine name where server is running}
  out     conn: file_conn_t;           {handle to server stream connection}
  out     info: csrv_server_info_t;    {info about remote server}
  out     stat: sys_err_t);            {completion status code}
  val_param;

var
  cmd: csrv_cmd_t;                     {buffer for one command to server}
  rsp: csrv_rsp_t;                     {buffer for one response from server}
  node_adr: sys_inet_adr_node_t;       {internet address of remote machine}
  port: sys_inet_port_id_t;            {server internet port on remote machine}
  envvar: string_var132_t;             {environment variable name}
  s: string_var32_t;                   {scratch string}
  i: sys_int_machine_t;                {scratch integer}
  olen: sys_int_adr_t;                 {amount of data read}

label
  noserve, abort;

begin
  envvar.max := size_char(envvar.str); {init local var strings}
  s.max := size_char(s.str);

  file_inet_name_adr (                 {convert machine name to internet address}
    machine,                           {input machine name}
    node_adr,                          {returned internet address}
    stat);
  if sys_error(stat) then return;
{
*   Determine the internet port number of the server on the remote machine.
}
  port := csrv_port_k;                 {set server port to default value}

  string_vstring (envvar, 'COGSERVE_'(0), -1); {init environment variable name}
  string_append (envvar, machine);     {append remote machine name}
  string_upcase (envvar);              {envvars names are all upper case}
  sys_envvar_get (envvar, s, stat);    {try to get environment variable name}
  if not sys_error(stat) then begin    {found environment variable and got value ?}
    string_t_int (s, i, stat);         {try to convert envvar string to integer}
    if not sys_error(stat) then begin  {got an integer value ?}
      port := i;                       {set server port to number from envvar}
      end;                             {done with got integer envvar value}
    end;                               {done with got envvar value}
{
*   Establish internet stream to server.
}
  file_open_inetstr (                  {try to establish connection to server}
    node_adr,                          {internet address of remote machine}
    port,                              {server port on remote machine}
    conn,                              {returned connection handle}
    stat);
  if sys_error(stat) then return;
{
*   Send the SVINFO command to check out the server, verify version, and get info.
}
  cmd.cmd := csrv_cmd_svinfo_k;        {fill in SVINFO command buffer}
  cmd.svinfo.t1 := 29;
  cmd.svinfo.t2 := 113;
  cmd.svinfo.t3 := 241;
  cmd.svinfo.t4 := 83;

  file_write_inetstr (                 {send SVINFO command to server}
    cmd,                               {output buffer}
    conn,                              {server connection handle}
    offset(cmd.svinfo) + size_min(cmd.svinfo), {amount of data to send}
    stat);
  if sys_error(stat) then goto abort;

  file_read_inetstr (                  {read response opcode from server}
    conn,                              {server connection handle}
    sizeof(rsp.rsp),                   {amount of data to read}
    [],                                {wait for data to arrive}
    rsp,                               {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then goto abort;
  if rsp.rsp <> csrv_rsp_svinfo_k then goto noserve; {didn't get right response ?}

  file_read_inetstr (                  {read rest of SVINFO command}
    conn,                              {server connection handle}
    size_min(rsp.svinfo),              {amount of data to read}
    [],                                {wait for data to arrive}
    rsp.svinfo,                        {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then goto abort;

  if                                   {check for any illegal response from server}
      (rsp.svinfo.t1 <> cmd.svinfo.t1) or
      (rsp.svinfo.t2 <> cmd.svinfo.t2) or
      (rsp.svinfo.t3 <> cmd.svinfo.t3) or
      (rsp.svinfo.t4 <> cmd.svinfo.t4) or
      (rsp.svinfo.r1 <> xor(cmd.svinfo.t1, cmd.svinfo.t2, cmd.svinfo.t3,
        cmd.svinfo.t4, 5)) or
      (rsp.svinfo.r2 <> (xor(cmd.svinfo.t1 + cmd.svinfo.t2 + cmd.svinfo.t3 +
        cmd.svinfo.t4, 5) & 255)) or
      (rsp.svinfo.r3 <> (xor(rsp.svinfo.r1 + rsp.svinfo.r2, 5) & 255))
    then goto noserve;

  case rsp.svinfo.order of             {what is server byte order ?}
csrv_order_fwd_k: info.order := sys_byte_order_fwd_k;
csrv_order_bkw_k: info.order := sys_byte_order_bkw_k;
otherwise
    goto noserve;
    end;

  info.flip := info.order <> sys_byte_order_k; {set flag if byte order requires flip}
  if info.flip then begin              {we need to flip data to/from server ?}
    sys_order_flip (rsp.svinfo.id, sizeof(rsp.svinfo.id));
    sys_order_flip (rsp.svinfo.ver_maj, sizeof(rsp.svinfo.ver_maj));
    sys_order_flip (rsp.svinfo.ver_min, sizeof(rsp.svinfo.ver_min));
    sys_order_flip (rsp.svinfo.ver_seq, sizeof(rsp.svinfo.ver_seq));
    end;

  if rsp.svinfo.id <> csrv_id_k then goto noserve; {not the right server ID ?}

  info.ver_maj := rsp.svinfo.ver_maj;  {return server version info}
  info.ver_min := rsp.svinfo.ver_min;
  info.ver_seq := rsp.svinfo.ver_seq;
  return;                              {normal no-error return point}
{
*   Jump here to abort to caller indicating the correct server could not be
*   found.
}
noserve:
  sys_stat_set (csrv_subsys_k, csrv_stat_noserve_k, stat);
  goto abort;
{
*   Jump here on error after server connection open.  STAT must already be set.
}
abort:
  file_close (conn);                   {close connection to server}
  end;
{
**********************************************************
*
*   Subroutine CSRV_STAT_GET (CONN, FLIP, ERR, STAT)
*
*   Read the STAT response from the server and return the ERR status code.
}
procedure csrv_stat_get (              {read STAT response and return result}
  in out  conn: file_conn_t;           {server connection handle}
  in      flip: boolean;               {TRUE if need to flip to server byte order}
  out     err: csrv_err_t;             {error status flag from STAT response}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  rsp: csrv_rsp_t;                     {buffer for one response from COGSERVE server}
  olen: sys_int_adr_t;                 {unused subroutine argument}

begin
  file_read_inetstr (                  {read STAT response from server}
    conn,                              {handle to server connection}
    sizeof(rsp.rsp) + size_min(rsp.stat), {amount of data to read}
    [],                                {wait indefinately for the data}
    rsp,                               {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then return;

  if flip then begin                   {must flip to server byte order ?}
    sys_order_flip (rsp.rsp, sizeof(rsp.rsp));
    sys_order_flip (rsp.stat.err, sizeof(rsp.stat.err));
    end;

  if rsp.rsp <> csrv_rsp_stat_k then begin {not STAT response ?}
    sys_stat_set (csrv_subsys_k, csrv_stat_commerr_k, stat);
    return;
    end;

  err := rsp.stat.err;                 {extract error status code}
  end;
