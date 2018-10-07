{   Program NODE_INFO <options>
*
*   Print out some information about the node running this process.
*   The default is to print all available information with text that
*   identifies it.  Command line options are:
*
*   -NAME
*
*     Only the network name of the machine is written without any surrounding
*     characters.
*
*   -ID
*
*     Only the unique ID for this machine is written without any surrounding
*     characters.
}
program node_info;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

type
  which_t = (                          {identifies which info to write}
    which_name_k,                      {just the node name}
    which_id_k,                        {just the node ID}
    which_all_k);                      {everything with explanatory text}

var
  which: which_t;                      {identifies what info to write}
  s1, s2:                              {scratch strings}
    %include '(cog)lib/string80.ins.pas';

  opt:                                 {name of last command line option}
    %include '(cog)lib/string16.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {error status code}

label
  next_opt, done_opts;

begin
  string_cmline_init;                  {init for command line processing}
  which := which_all_k;                {init to default values}

next_opt:                              {back here each new command line option}
  string_cmline_token (opt, stat);     {read next command line option}
  if string_eos(stat) then goto done_opts; {exhausted the command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,                {pick matching command line option from list}
    '-NAME -ID',
    pick);                             {returned number of token picked from list}
  case pick of
{
*   -NAME
}
1: begin
  if which <> which_all_k then begin
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  which := which_name_k;
  end;
{
*   -ID
}
2: begin
  if which <> which_all_k then begin
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  which := which_id_k;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;
    end;
  goto next_opt;
done_opts:                             {all done processing command line}
{
*   All done processing the command line.  WHICH is set to indicate which
*   piece(s) of information are to be written.
}
  case which of
{
*   Write just the node name.
}
which_name_k: begin
      sys_node_name (s1);              {get node name}
      string_write (s1);
      end;
{
*   Write just the node ID.
}
which_id_k: begin
      sys_node_id (s1);                {get node ID}
      string_write (s1);
      end;
{
*   Write all the info with explanatory text.
}
which_all_k: begin
      sys_node_name (s1);              {get node name}
      sys_node_id (s2);                {get node ID}
      sys_msg_parm_vstr (msg_parm[1], s1);
      sys_msg_parm_vstr (msg_parm[2], s2);
      sys_message_parms ('sys', 'node_info', msg_parm, 2);
      end;
    end;                               {end of which info to write cases}
  end.
