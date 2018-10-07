{   Program MENU_ENTRY [options]
*
*   Create or delete system menu entries.  The exact operation of this program
*   is system-specific.
}
program menu_entry;
%include '(cog)lib/base.ins.pas';

const
  max_msg_args = 7;                    {max arguments we can pass to a message}

var
  prog,                                {program to create menu entry for}
  progt,                               {full treename of target program}
  path,                                {menu entry path within its root menu}
  name,                                {menu entry name}
  wdir,                                {working directory to run program in}
  icon:                                {icon .bmp file name}
    %include '(cog)lib/string_treename.ins.pas';
  args,                                {command line parameters of target program}
  desc:                                {menu entry description string}
    %include '(cog)lib/string8192.ins.pas';
  menuid: sys_menu_k_t;                {ID of root menu to add entry within}
  menuname:                            {name ID of root menu, for error messages}
    %include '(cog)lib/string32.ins.pas';
  gprog:                               {generic name of program}
    %include '(cog)lib/string_leafname.ins.pas';
  tk:                                  {scratch token}
    %include '(cog)lib/string8192.ins.pas';
  i: sys_int_machine_t;                {scratch integer}
  p: string_index_t;                   {scratch string parse index}
  delete: boolean;                     {delete menu entry, not create it}
  prog_set: boolean;                   {program name in PROG has been set}
  icon_set: boolean;                   {menu entry icon explicitly set}
  show: boolean;                       {show details of menu entry trying to create}
  ifex: boolean;                       {create entry only if target program exists}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string8192.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts, leave;

begin
{
*   Initialize our state before reading the command line options.
}
  string_cmline_init;                  {init for reading the command line}
  prog_set := false;                   {init to program for menu entry not set}
  icon_set := false;                   {init to icon not explicitly set}
  menuid := sys_menu_progs_all_k;      {init to default root menu}
  string_vstring (menuname, 'PROGS'(0), -1);
  delete := false;                     {init to create, not delete, menu entry}
  show := false;                       {init to not show info before create menu entry}
  ifex := false;                       {init to target prog must exist on create}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not prog_set then begin         {program name not already set ?}
      string_copy (opt, prog);         {set program name}
      prog_set := true;                {program name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-PROG -MENU -SUB -NAME -WDIR -DESC -ICON -DEL -SHOW -ARGS -CMD -IFEX',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -PROG program
*
*   Set the name of the program to run when the menu entry is selected.
}
1: begin
  string_cmline_token (prog, stat);
  prog_set := true;
  end;
{
*   -MENU menuroot
*
*   Identifies the root menu the entry is within.
}
2: begin
  string_cmline_token (parm, stat);    {get menu ID token}
  if sys_error(stat) then goto err_parm;
  string_upcase (parm);                {make upper case for keyword matching}
  string_tkpick80 (parm,               {pick keyword from list}
    'PROGS PROGSU DESK DESKU',
    pick);
  case pick of
1:  begin
      menuid := sys_menu_progs_all_k;
      string_vstring (menuname, 'PROGS'(0), -1)
      end;
2:  begin
      menuid := sys_menu_progs_user_k;
      string_vstring (menuname, 'PROGSU'(0), -1)
      end;
3:  begin
      menuid := sys_menu_desk_all_k;
      string_vstring (menuname, 'DESK'(0), -1)
      end;
4:  begin
      menuid := sys_menu_desk_user_k;
      string_vstring (menuname, 'DESKU'(0), -1)
      end;
otherwise
    goto parm_bad;
    end;
  end;
{
*   -SUB path
*
*   Set the path of the menu entry within the root menu.
}
3: begin
  string_cmline_token (path, stat);
  end;
{
*   -NAME name
*
*   Explicitly set the menu entry name as it is appears in the menu.
}
4: begin
  string_cmline_token (name, stat);
  end;
{
*   -WDIR dir
*
*   Set the working directory the program is to be run in when the menu entry is
*   activated.
}
5: begin
  string_cmline_token (wdir, stat);
  end;
{
*   -DESC string
*
*   Set the menu entry description string.
}
6: begin
  string_cmline_token (desc, stat);
  end;
{
*   -ICON fnam
*
*   Set the icon to display for the menu entry.  FNAM is the name of a suitable
*   image file.
}
7: begin
  string_cmline_token (icon, stat);
  icon_set := true;
  end;
{
*   -DEL
*
*   Delete the menu entry instead of creating it.
}
8: begin
  delete := true;
  end;
{
*   -SHOW
*
*   Cause info to be shown about menu entry trying to create.
}
9: begin
  show := true;
  end;
{
*   -ARGS "arg ... arg"
*
*   Specifies the command line arguments to be passed to the target program.
*   The parameters to -ARGS is a single token containing all the command line
*   parameters.
}
10: begin
  string_cmline_token (args, stat);
  end;
{
*   -CMD command-line
*
*   Specifies the full command line to invoke the target program.  The first
*   token of COMMAND-LINE will be interpreted as the executable, and the
*   remaining tokens as the command line parameters.  If the executable name
*   does not contain any dot (.), then the ".exe" suffix is assumed.  Otherwise
*   the full executable file name must be specified.  COMMAND-LINE is a single
*   token containing the executable name and all parameters.  Tokens within
*   COMMAND-LINE must be separated by one or more spaces.
}
11: begin
  string_cmline_token (parm, stat);
  if sys_error(stat) then goto err_parm;

  prog_set := false;                   {reset to no program name known}
  args.len := 0;                       {reset to no command line parameters}
  p := 1;                              {init input string parse index}

  string_token (parm, p, prog, stat);  {get executable name into PROG}
  if sys_error(stat) then goto err_parm;
  i := 1;
  while i <= prog.len do begin         {scan for "." in executable name}
    if prog.str[i] = '.' then exit;
    i := i + 1;
    end;
  if i > prog.len then begin           {no "." in executable name ?}
    string_appends (prog, '.exe'(0));  {add assumed file name suffix}
    end;

  while true do begin                  {back here each new parameter}
    string_token (parm, p, tk, stat);  {get this parameter into TK}
    if string_eos(stat) then exit;
    if sys_error(stat) then goto err_parm;
    string_append_token (args, tk);    {add parameter to parameters list}
    end;                               {back to get next parameter}

  prog_set := true;                    {indicate target program name has been set}
  end;
{
*   -IFEX
*
*   Only create the menu entry if the target program exists.  The program exits
*   normally without error and creates no menu entry if the target program does
*   not exist.  The default is that the target program is required to exist.
}
12: begin
  ifex := true;
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
  if prog.len > 0 then begin
    string_treename (prog, progt);     {make full treename of target program}
    end;
  string_generic_fnam (                {make generic program name}
    progt, '.exe .bat .htm .pdf .txt'(0), gprog);

  if name.len = 0 then begin           {default menu entry name ?}
    string_copy (gprog, name);
    end;
  if name.len = 0 then begin
    sys_message_bomb ('sys', 'menu_no_name', nil, 0);
    end;

  if delete then begin                 {supposed to delete the menu entry ?}
    sys_menu_entry_del (menuid, path, name, stat); {delete the menu entry}
    discard( file_not_found(stat) );   {OK if not previously existed}
    sys_msg_parm_vstr (msg_parm[1], name);
    sys_msg_parm_vstr (msg_parm[2], path);
    sys_msg_parm_vstr (msg_parm[3], menuname);
    sys_error_abort (stat, 'sys', 'menu_delete_err', msg_parm, 3);
    goto leave;
    end;

  if progt.len = 0 then begin
    sys_message_bomb ('sys', 'menu_no_prog', nil, 0);
    end;
  if not file_exists(progt) then begin {target program doesn't exist ?}
    if ifex then goto leave;           {not exists is OK, just do nothing ?}
    sys_msg_parm_vstr (msg_parm[1], progt);
    sys_message_bomb ('sys', 'menu_prog_nexist', msg_parm, 1);
    end;

  if wdir.len = 0 then begin           {default working directory for running program ?}
    string_vstring (parm, '(cog)progs/'(0), -1); {make PROGS dir name for this program}
    string_append (parm, gprog);
    string_treename (parm, opt);
    if file_exists (opt)
      then begin                       {this program has Embed PROGS directory}
        string_copy (opt, wdir);
        end
      else begin                       {no PROGS directory, use hard default}
        string_vstring (wdir, '/'(0), -1);
        end
      ;
    end;

  if not icon_set then begin           {no icon explicitly supplied ?}
    string_vstring (parm, '(cog)progs/'(0), -1); {make default icon pathname for this prog}
    string_append (parm, gprog);
    string_appends (parm, '/icon.bmp'(0));
    string_treename (parm, opt);
    if file_exists (opt) then begin    {this program has a default icon ?}
      string_copy (opt, icon);         {use it}
      end;
    end;

  if show then begin                   {show info before trying to create menu entry ?}
    sys_msg_parm_vstr (msg_parm[1], name);
    sys_msg_parm_vstr (msg_parm[2], menuname);
    sys_msg_parm_vstr (msg_parm[3], path);
    sys_msg_parm_vstr (msg_parm[4], prog);
    sys_msg_parm_vstr (msg_parm[5], args);
    sys_msg_parm_vstr (msg_parm[6], wdir);
    sys_msg_parm_vstr (msg_parm[7], icon);
    sys_msg_parm_vstr (msg_parm[8], desc);
    sys_message_parms ('sys', 'menu_info', msg_parm, 8);
    end;

  sys_menu_entry_set (                 {create the menu entry}
    menuid,                            {ID of the root menu to create entry in}
    path,                              {path within the root menu}
    name,                              {menu entry name}
    prog,                              {program to run when menu entry activated}
    args,                              {command line parameters to the target program}
    wdir,                              {directory to run the program in}
    desc,                              {description string}
    icon,                              {menu entry icon}
    stat);
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], name);
    sys_msg_parm_vstr (msg_parm[2], menuname);
    sys_msg_parm_vstr (msg_parm[3], path);
    sys_msg_parm_vstr (msg_parm[4], prog);
    sys_msg_parm_vstr (msg_parm[5], args);
    sys_msg_parm_vstr (msg_parm[6], wdir);
    sys_msg_parm_vstr (msg_parm[7], icon);
    sys_msg_parm_vstr (msg_parm[8], desc);
    sys_error_abort (stat, 'sys', 'menu_set_err', msg_parm, 8);
    end;

leave:
  end.
