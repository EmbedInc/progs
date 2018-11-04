{   Program COPYT [options]
*
*   Copy a whole file system object from one place to another.  If the object
*   is a directory, then the entire directory tree is copied.
*
*   The command line options are:
*
*   <source object name>
*
*   -FROM <source object name>
*
*   <destination object name>
*
*   -TO <destination object name>
*
*   -NSHOW
*
*   -NREPL
}
program copyt;
%include '/cognivision_links/dsee_libs/sys/sys.ins.pas';
%include '/cognivision_links/dsee_libs/util/util.ins.pas';
%include '/cognivision_links/dsee_libs/string/string.ins.pas';
%include '/cognivision_links/dsee_libs/file/file.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  name_src, name_dst:                  {source and destination object names}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  sname_set: boolean;                  {TRUE if source name already set}
  dname_set: boolean;                  {TRUE if destination name already set}
  opts: file_copy_t;                   {option flags for FILE_COPY_TREE}
  show: boolean;                       {TRUE if show progress to STDOUT}
  repl: boolean;                       {OK for dest to replace existing object}

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
  sname_set := false;                  {source name not already set}
  dname_set := false;                  {destination name not already set}
  show := true;                        {init to show progress to standard output}
  repl := true;                        {init to OK for dest to replace existing obj}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not sname_set then begin        {source name not set yet ?}
      string_copy (opt, name_src);     {set source name}
      sname_set := true;               {source name is now set}
      goto next_opt;
      end;
    if not dname_set then begin        {dest name not set yet ?}
      string_copy (opt, name_dst);     {set dest name}
      dname_set := true;               {dest name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-FROM -TO -NSHOW -NREPL',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -FROM <source name>
}
1: begin
  if sname_set then begin              {source name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (name_src, stat);
  sname_set := true;
  end;
{
*   -TO <destination name>
}
2: begin
  if dname_set then begin              {dest name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (name_dst, stat);
  dname_set := true;
  end;
{
*   -NSHOW
}
3: begin
  show := false;
  end;
{
*   -NREPL
}
4: begin
  repl := false;
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
  if not sname_set then begin          {no source name specified ?}
    sys_message_bomb ('img', 'input_fnam_missing', nil, 0);
    end;

  if not dname_set then begin          {use default dest name ?}
    string_generic_fnam (name_src, '', name_dst);
    end;

  opts := [];                          {init file copy option flags}
  if repl then begin                   {OK to replace existing object ?}
    opts := opts + [file_copy_replace_k];
    end;
  if show then begin                   {show progress to standard output ?}
    opts := opts + [file_copy_list_k];
    end;

  file_copy_tree (name_src, name_dst, opts, stat);
  sys_error_abort (stat, '', '', nil, 0);
  end.
