{   Program DELT [options]
*
*   Delete an entire directory tree, or any other file system object.
*
*   <tree name>
*   -NAME <tree name>
*
*   -NSHOW
}
program delt;
%include '/cognivision_links/dsee_libs/sys/sys.ins.pas';
%include '/cognivision_links/dsee_libs/util/util.ins.pas';
%include '/cognivision_links/dsee_libs/string/string.ins.pas';
%include '/cognivision_links/dsee_libs/file/file.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  name:                                {name of object to delete}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  name_set: boolean;                   {TRUE if NAME already set}
  show: boolean;                       {TRUE if show progress to STDOUT}
  opts: file_del_t;                    {tree deletion options}

  opt:                                 {upcased command line option}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {error status code}

label
  next_opt, err_parm, parm_bad, done_opts;

begin
  string_cmline_init;                  {init for reading the command line}
{
*   Initialize our state before reading the command line options.
}
  name_set := false;                   {init to no name given yet}
  show := true;                        {init to show progress to standard output}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not name_set then begin         {name not set yet ?}
      string_copy (opt, name);         {set input file name}
      name_set := true;                {input file name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-NAME -NSHOW',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -NAME name
}
1: begin
  if name_set then begin               {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (name, stat);
  name_set := true;
  end;
{
*   -NSHOW
}
2: begin
  show := false;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   All done reading the command line.
}
  if not name_set then begin           {no input file name specified ?}
    sys_message_bomb ('file', 'no_name', nil, 0);
    end;

  opts := [file_del_errgo_k];          {continue on error}
  if show then begin                   {list activity to standard output ?}
    opts := opts + [file_del_list_k];
    end;

  file_delete_tree (name, opts, stat); {delete the object}
  sys_error_abort (stat, '', '', nil, 0);
  end.
