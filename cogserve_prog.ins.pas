{   Private include file for the COGSERVE server routines.
}
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'cogserve.ins.pas';

var (csrv)
  debug: sys_int_machine_t;            {0-10 debug level}
{
*   Private routine declarations.
}
procedure csrv_client (                {service a newly-established client}
  in out  conn: file_conn_t);          {handle to client connection}
  extern;

procedure csrv_cmd_run (               {process client RUN command}
  in out  conn_client: file_conn_t;    {handle to client stream connection}
  in      opts: csrv_runopt_t;         {option flags from client}
  in      cmline: univ string_var_arg_t); {command line to execute}
  val_param; extern;

function csrv_version_sequence         {return server's private sequence number}
  :sys_int_conv32_t;
  extern;

procedure csrv_wait_client (           {wait for, then handle client connections}
  in      serv: file_inet_port_serv_t); {handle to server port}
  val_param; extern;
