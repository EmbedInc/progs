{   Program FIX_GLD_LINKS
*
*   Fix links to the Microchip 16 bit linker files.  These used to be in
*   source/dspic, now in extern/mplab.
}
program fix_gld_links;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  fix: boolean;                        {fix links, not just identify needed changes}
  lev: sys_int_machine_t;              {recursive nesting level, 0 at top level}
  dspicdir:
    %include '(cog)lib/string_treename.ins.pas';

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Subroutine PROCESS_DIR (DIR)
*
*   Process the links in the directory DIR.  Subdirectories are processed
*   recursively.
}
procedure process_dir (                {process directory, subdirs recursively}
  in      dir: univ string_var_arg_t); {name of directory to process}
  val_param; internal;

var
  conn: file_conn_t;                   {connection to the directory}
  ent: string_leafname_t;              {directory entry name}
  finfo: file_info_t;                  {info about current directory entry}
  tnam: string_treename_t;             {scratch full pathname}
  link: string_treename_t;             {link treename}
  dest: string_treename_t;             {link destination}
  lnam: string_leafname_t;             {scratch leafname}
  lfil: string_leafname_t;             {linker file leafname}
  ldir: string_leafname_t;             {linker file portable dir name}
  stat: sys_err_t;                     {completion status}

label
  done_ent;

begin
  ent.max := size_char(ent.str);       {init local var strings}
  tnam.max := size_char(tnam.str);
  link.max := size_char(link.str);
  dest.max := size_char(dest.str);
  lnam.max := size_char(lnam.str);
  lfil.max := size_char(lfil.str);
  ldir.max := size_char(ldir.str);

  file_open_read_dir (dir, conn, stat); {open the directory to read it}
  sys_error_abort (stat, '', '', nil, 0);
  lev := lev + 1;                      {indicate one level further down}

  while true do begin                  {back here each new directory entry}
    file_read_dir (                    {read next entry from directory}
      conn,                            {connection to the directory}
      [file_iflag_type_k],             {request file type}
      ent,                             {returned directory entry name}
      finfo,                           {info about the directory entry}
      stat);
    if file_eof(stat) then exit;       {exhausted the directory ?}
    sys_error_abort (stat, '', '', nil, 0);
    case finfo.ftype of                {what type of file is this ?}

file_type_dir_k: begin                 {subdirectory}
  if string_equal (ent, string_v('.git'(0)))
    then goto done_ent;
  string_pathname_join (               {make full pathname of this subdirectory}
    conn.tnam, ent, tnam);
  process_dir (tnam);                  {process this subdirectory recursively}
  end;

file_type_link_k: begin                {this directory entry is a symbolic link}
  string_pathname_join (               {make full pathname of this link in LINK}
    conn.tnam, ent, link);
  file_link_resolve (link, dest, stat); {get link expansion into DEST}
  sys_error_abort (stat, '', '', nil, 0);
  string_substr (                      {extract last 4 chars of link expansion}
    dest, dest.len-3, dest.len, lnam);
  string_upcase (lnam);
  if not string_equal (lnam, string_v('.GLD'(0))) {not to a linker file ?}
    then goto done_ent;

  string_pathname_split (              {split off linker file leafname into LFIL}
    dest, tnam, lfil);
  string_pathname_split (              {split off portable linker file dir into LDIR}
    tnam, dest, ldir);

  string_substr (                      {get 3 first chars of linker file directory}
    ldir, 1, 3, lnam);
  string_upcase (lnam);
  if not string_equal (lnam, string_v('GLD'(0))) {not to a linker directory ?}
    then goto done_ent;

  string_treename (dest, tnam);        {make abs pathname of start of link expansion}
  if not string_equal (tnam, dspicdir) {link doesn't point into DSPIC source dir ?}
    then goto done_ent;

  string_vstring (dest, '(cog)extern/mplab/'(0), -1); {build new link expansion}
  string_append (dest, ldir);
  string_append1 (dest, '/');
  string_append (dest, lfil);

  writeln (                            {show link and desired new expansion}
    link.str:link.len, ' --> ', dest.str:dest.len);
  if not fix then goto done_ent;       {don't try to fix the link ?}

  file_link_create (                   {update the link}
    link,                              {name of the link}
    dest,                              {new link expansion}
    [file_crea_overwrite_k],           {overwrite existing link}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  end;                                 {end of dir entry is a link case}

      end;                             {end of directory entry type cases}
done_ent:                              {done with the current directory entry}
    end;                               {back for next directory entry}

  file_close (conn);                   {close connection to the directory}
  lev := lev - 1;                      {indicate one level further up}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize before reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  fix := true;                         {init to fix links}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-SHOW',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -SHOW
}
1:  begin
      fix := false;
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

  string_treename (                    {save full pathname of the DSPIC source dir}
    string_v('(cog)source/dspic'(0)),  {portable pathname of DSPIC source dir}
    dspicdir);                         {returned absolute pathname}

  lev := 0;                            {init recursive nesting level}
  process_dir (string_v('.'(0)));      {recursively process the current directory tree}
  end.
