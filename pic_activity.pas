{   Program PIC_ACTIVITY
*
*   Make a list of recent PIC firmware development activity and hardware design
*   activity by quarter.
}
program pic_activity;
%include 'base.ins.pas';

const
  max_ver = 100;                       {max versions of a project per quarter}
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  ptype_k_t = (                        {project type, listed here in sort order}
    ptype_hw_k,                        {hardware project}
    ptype_fw_k);                       {firmware project}

  proj_p_t = ^proj_t;
  proj_t = record                      {info about one project within a quarter}
    next_p: proj_p_t;                  {next project in list for this quarter}
    ptype: ptype_k_t;                  {type of project (firmware, hardware, etc)}
    lib: string_var80_t;               {library name the project is within}
    name: string_var80_t;              {project name}
    nver: sys_int_machine_t;           {number of versions this quarter}
    ver: array[1 .. max_ver] of sys_int_machine_t; {version numbers activity this quarter}
    end;

  quart_p_t = ^quart_t;
  quart_t = record                     {activity info about one quarter year}
    next_p: quart_p_t;                 {to next quarter, NIL at end of list}
    start: sys_clock_t;                {start time of this quarter}
    end: sys_clock_t;                  {end time of this quarter}
    proj_p: proj_p_t;                  {points to list of projects this quarter}
    end;

var
  tzone: sys_tzone_k_t;                {our time zone}
  hours_west: real;                    {our time zone hours west of CUT}
  daysave: sys_daysave_k_t;            {our time zone daylight savings strategy}
  date: sys_date_t;                    {scratch date descriptor}
  date_end: sys_date_t;                {ignore activity after this date/time}
  time: sys_clock_t;                   {scratch time}
  qlist_p: quart_p_t;                  {to list of quarters, guaranteed not empty}
  qlist_last_p: quart_p_t;             {to last quarters list entry}
  quart_p: quart_p_t;                  {to list entry for current quarter}
  ii: sys_int_machine_t;               {scratch integers and loop counters}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  next_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Subroutine GET_VERSION (GNAM, NAME, VER)
*
*   Extract the name and version number from the generic file name GNAM.  GNAM
*   is just a string that may end in successive decimal digits.  If so, then
*   NAME is set to the part of GNAM without the digits and VER is returned the
*   integer value of the digits.  If GNAM does not end in digits, then NAME is
*   the whole GNAM string and VER is set to 0.  NAME is always returned upper
*   case regardless of the case in GNAM.
}
procedure get_version (                {extract name and version from combination}
  in      gnam: univ string_var_arg_t; {input string, may end in version number}
  in out  name: univ string_var_arg_t; {returned upper case name part of GNAM}
  out     ver: sys_int_machine_t);     {returned version number, 0 for none}
  val_param; internal;

var
  ii: sys_int_machine_t;               {index of last non-digit character}
  c: char;                             {current character being examined}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;                     {completion status}

begin
  tk.max := size_char(tk.str);         {init local var string}

  ii := gnam.len;                      {init to no trailing digits}
  while true do begin                  {scan backwards looking for last non-digit}
    c := gnam.str[ii];                 {get this combined name character}
    if (c < '0') or (c > '9') then exit; {this char is not a digit ?}
    ii := ii - 1;                      {go to previous character}
    if ii <= 0 then exit;              {no more chars ?}
    end;
{
*   II is the character index into GNAM of the last non-digit.
}
  if ii = gnam.len
    then begin                         {no version number}
      string_copy (gnam, name);        {name is whole input string}
      ver := 0;                        {as if version were 0}
      end
    else begin                         {file name contains version number}
      string_substr (gnam, 1, ii, name); {extract name part of input string}
      string_substr (gnam, ii+1, gnam.len, tk); {extract version number string}
      string_t_int (tk, ver, stat);    {make integer version number}
      if sys_error(stat) then ver := 0;
      end
    ;
  string_upcase (name);                {always return name part upper case}
  end;
{
********************************************************************************
*
*   Subroutine SORT_PROJ (PROJ)
*
*   Sort the version numbers of the project PROJ into ascending order.
}
procedure sort_proj (                  {sort version numbers into ascending order}
  in out  proj: proj_t);               {project to sort version numbers of}
  val_param; internal;

var
  i, j: sys_int_machine_t;             {loop indexes}
  temp: sys_int_machine_t;

begin
  if proj.nver <= 1 then return;       {nothing to sort ?}

  for i := 1 to proj.nver-1 do begin   {outer sort loop}
    for j := i+1 to proj.nver do begin {inner sort loop}
      if proj.ver[j] >= proj.ver[i] then next; {already in order ?}
      temp := proj.ver[i];             {flip the order}
      proj.ver[i] := proj.ver[j];
      proj.ver[j] := temp;
      end;
    end;
  end;
{
********************************************************************************
*
*   Subroutine SORT_PROJS (LIST_P)
*
*   Sort the list of project descriptors pointed to by LIST_P by ascending
*   library name, then project name within each library.  LIST_P is updated to
*   point to the first entry in the re-ordered list.
}
procedure sort_projs (                 {list list of projects}
  in out  list_p: proj_p_t);           {pointer to first list entry}
  val_param; internal;

type
  parr_t = array[1 .. 1] of proj_p_t;  {array of pointers to list entries}
  parr_p_t = ^parr_t;

var
  parr_p: parr_p_t;                    {pointer to array of list entry pointers}
  np: sys_int_machine_t;               {number of projects to sort}
  proj_p: proj_p_t;                    {scratch project pointer}
  i, j: sys_int_machine_t;             {scratch integers and loop counters}
  comp: sys_int_machine_t;             {-1, 0, 1 compare result}

label
  flip;

begin
{
*   Build the array of pointers to the project list entries.
}
  np := 0;                             {init number of projects to sort}
  proj_p := list_p;                    {init to first project in list}
  while proj_p <> nil do begin         {scan the existing list}
    np := np + 1;                      {count one more project in the list}
    sort_proj (proj_p^);               {sort the version numbers in this project}
    proj_p := proj_p^.next_p;
    end;
  if np <= 1 then return;              {nothing to sort ?}

  sys_mem_alloc (sizeof(parr_p^[1]) * np, parr_p); {allocate array of pointers to each proj}
  i := 0;
  proj_p := list_p;                    {init to first project in list}
  while proj_p <> nil do begin         {init array of pointers to the projects}
    i := i + 1;                        {make index for this array entry}
    parr_p^[i] := proj_p;              {init this array entry}
    proj_p := proj_p^.next_p;
    end;
{
*   Sort the array.
}
  for i := 1 to np-1 do begin          {outer sort loop}
    for j := i+1 to np do begin        {inner sort loop}
      comp := string_compare (parr_p^[j]^.lib, parr_p^[i]^.lib); {compare library names}
      if comp > 0 then next;           {already in right order ?}
      if comp < 0 then goto flip;      {in wrong order ?}
      if ord(parr_p^[j]^.ptype) > ord(parr_p^[i]^.ptype) {in right order by type ?}
        then next;
      if ord(parr_p^[j]^.ptype) < ord(parr_p^[i]^.ptype) {in wrong order by type ?}
        then goto flip;
      comp := string_compare (parr_p^[j]^.name, parr_p^[i]^.name); {compare proj names}
      if comp >= 0 then next;          {already in right order ?}
flip:                                  {out of order, flip the order}
      proj_p := parr_p^[i];
      parr_p^[i] := parr_p^[j];
      parr_p^[j] := proj_p;
      end;                             {back next inner sort loop iteration}
    end;                               {back next outer sort loop iteration}
{
*   Re-link the list in sorted order.
}
  proj_p := parr_p^[np];               {init pointer to last array entry}
  proj_p^.next_p := nil;               {indicate no following entry in the list}
  for i := np-1 downto 1 do begin      {scan in backwards sorted order}
    parr_p^[i]^.next_p := proj_p;
    proj_p := parr_p^[i];
    end;
  list_p := proj_p;                    {update list pointer to new first entry}

  sys_mem_dealloc (parr_p);            {deallocate temporary pointers array}
  end;
{
********************************************************************************
*
*   Subroutine SORT_QUARTS
*
*   Sort the all the projects within each quarter in the quarters list.
}
procedure sort_quarts;
  val_param; internal;

var
  q_p: quart_p_t;                      {to current quarter in quarters list}

begin
  q_p := qlist_p;                      {init to first quarter in the list}
  while q_p <> nil do begin            {once for each quarters list entry}
    sort_projs (q_p^.proj_p);          {sort the projects within this quarter}
    q_p := q_p^.next_p;                {to next quarter in the list}
    end;                               {back to process this next quarter}
  end;
{
********************************************************************************
*
*   Subroutine ADD_ACT (LIB, PROJ, PTYPE, VER, TIME)
*
*   Add a specific item of activity to the collected data if appropriate.  LIB
*   is the upper case source library name (customer designator).  PROJ is the
*   upper case project name.  PTYPE is the project type, which indicates whether
*   this is a firmware or hardware project.  VER is the version number of this
*   activity within the customer designator name, project name, and project
*   type.  TIME is the time when the activity was completed.
}
procedure add_act (                    {add activity to the collected list}
  in      lib: univ string_var_arg_t;  {source library name, upper case}
  in      proj: univ string_var_arg_t; {project name, upper case}
  in      ptype: ptype_k_t;            {type of activity (hardware/firmware)}
  in      ver: sys_int_machine_t;      {version number}
  in      time: sys_clock_t);          {time this firmware version was created}
  val_param; internal;

var
  q_p: quart_p_t;                      {to current quarter in quarters list}
  comp: sys_compare_k_t;               {result of time comparison}
  proj_p: proj_p_t;                    {points to project within current quarter}

label
  next_proj, next_quarter;

begin
  q_p := qlist_p;                      {to first quarter in list}
  while q_p <> nil do begin            {scan forwards thru the quarters}
    comp := sys_clock_compare (time, q_p^.start); {compare time to start of this quarter}
    if comp = sys_compare_lt_k then exit; {activity is before this quarter ?}
    comp := sys_clock_compare (time, q_p^.end); {compare time to after of this quarter}
    if comp <> sys_compare_lt_k        {activity is after this quarter ?}
      then goto next_quarter;
    {
    *   The activity is within the current quarter.
    }
    proj_p := q_p^.proj_p;             {init pointer to first project this quarter}
    while proj_p <> nil do begin       {scan the list of existing projects}
      if not string_equal(proj_p^.lib, lib) {source library names don't match ?}
        then goto next_proj;
      if not string_equal(proj_p^.name, proj) {project names don't match ?}
        then goto next_proj;
      if proj_p^.ptype <> ptype        {project type doesn't match ?}
        then goto next_proj;
      exit;                            {found existing entry for this activity}
next_proj:                             {curr project doesn't match, on to next}
      proj_p := proj_p^.next_p;
      end;
    {
    *   PROJ_P points to the existing project this new activity is for, or is
    *   NIL to indicate that there is no existing project for this activity.
    }
    if proj_p = nil then begin         {no existing entry for this project ?}
      sys_mem_alloc (sizeof(proj_p^), proj_p); {create new project descriptor}
      proj_p^.next_p := q_p^.proj_p;   {link at start of list for this quarter}
      q_p^.proj_p := proj_p;
      proj_p^.ptype := ptype;          {set project type}
      proj_p^.name.max := size_char(proj_p^.name.str); {set project name}
      string_copy (proj, proj_p^.name);
      proj_p^.lib.max := size_char(proj_p^.lib.str); {set source library name}
      string_copy (lib, proj_p^.lib);
      proj_p^.nver := 0;               {init number of firmware versions in list}
      end;

    if proj_p^.nver < max_ver then begin {room left for another version ?}
      proj_p^.nver := proj_p^.nver + 1; {count one more version in this list}
      proj_p^.ver[proj_p^.nver] := ver; {add this version number to the list}
      end;

next_quarter:                          {skip here to advance to the next quarter}
    q_p := q_p^.next_p;                {to next quarter}
    end;                               {back to check the next quarter}
  end;
{
********************************************************************************
*
*   Subroutine SCAN_TREE_FW (SRCPATH)
*
*   Scan the directory tree (cog)source looking for HEX files.  Except for some
*   old projects, the released firmware version HEX files are within the HEX
*   subdirectory within the source code repository.
*
*   HEX files with modified dates within any of the quarters within the quarters
*   will be added to the activity data.
*
*   This routine calls itself recursively to process subordinate directories.
}
procedure scan_tree_fw (               {scan looking for firmware projects}
  in      srcpath: univ string_var_arg_t); {path within SRC directory of the tree}
  val_param; internal;

var
  lib: string_treename_t;              {current source library name}
  ent: string_leafname_t;              {directory entry name}
  conn: file_conn_t;                   {connection to the top directory of the tree}
  finfo: file_info_t;                  {extra info about current directory entry}
  finfo2: file_info_t;                 {scratch extra info about a file}
  dir: string_treename_t;              {scratch pathname}
  tk: string_treename_t;               {scratch token}
  lnam: string_leafname_t;             {last entry of pathname}
  name: string_var80_t;                {firmware name}
  ver: sys_int_machine_t;              {firmware version number}
  stat: sys_err_t;                     {completion status}

label
  done_ent;

begin
  dir.max := size_char(dir.str);       {init local var strings}
  lib.max := size_char(lib.str);
  ent.max := size_char(ent.str);
  tk.max := size_char(tk.str);
  lnam.max := size_char(lnam.str);
  name.max := size_char(name.str);

  string_copy (srcpath, lib);          {save source library name for this subdir}
  string_upcase (lib);

  string_vstring (dir, '(cog)source'(0), -1); {init directory to SOURCE root}
  if srcpath.len > 0 then begin        {add subdirectory path}
    string_append1 (dir, '/');
    string_append (dir, srcpath);
    end;
  file_open_read_dir (dir, conn, stat); {open directory for reading}
  if sys_error_check (stat, '', '', nil, 0) then return;

  while true do begin                  {scan this directory}
    file_read_dir (                    {read the next directory entry}
      conn,                            {connection to the directory}
      [ file_iflag_dtm_k,              {request last modified time}
        file_iflag_type_k],            {request file type}
      ent,                             {name of this directory entry}
      finfo,                           {info about this directory entry}
      stat);
    if file_eof(stat) then exit;       {done reading the directory ?}
    if sys_error_check (stat, '', '', nil, 0) then begin {hard error ?}
      file_close (conn);
      return;
      end;
    case finfo.ftype of                {what kind of file system object is this ?}
{
*   Directory entry is a subdirectory.
}
file_type_dir_k: begin
  string_copy (srcpath, dir);          {init subdirectory to current directory}
  if dir.len > 0 then begin
    string_append1 (dir, '/');
    end;
  string_append (dir, ent);            {add subdirectory name}
  scan_tree_fw (dir);                  {handle this subdirectory recursively}
  end;
{
*   Directory entry is an ordinary file.
}
file_type_data_k: begin
  if lib.len <= 0 then goto done_ent;  {ignore files in top level (shouldn't be there)}
  if ent.len < 6 then goto done_ent;   {name too short to be xn.HEX file}
  string_upcase (ent);                 {make file name upper case}
  string_substr (ent, ent.len - 3, ent.len, tk); {get last 4 file name chars}
  if not string_equal (tk, string_v('.HEX')) then goto done_ent; {not a HEX file ?}
  ent.len := ent.len - 4;              {truncate ".HEX" part of file name}
  get_version (ent, name, ver);        {extract firmware name and version number}
  if ver = 0 then goto done_ent;       {not version number ?}
  if name.len <= 0 then goto done_ent; {no firmware name ?}
  {
  *   A new HEX file was found for a released version of firmware.  NAME
  *   contains the upper case project name from the HEX file, and VER is the
  *   version number.
  }
  string_copy (lib, dir);              {init source library name to use}
  string_pathname_split (dir, tk, lnam); {strip off leaf directory name into LNAM}
  if string_equal (lnam, string_v('HEX'(0))) then begin {in HEX subdirectory ?}
    string_copy (tk, dir);             {use source lib name with HEX stripped off}
    end;
  string_pathname_split (dir, tk, lnam); {strip off new leaf directory name into LNAM}
  if string_equal (lnam, name) then begin {dir name matches HEX file firware name ?}
    string_copy (tk, dir);             {use lib name with firmware name stripped off}
    end;
  {
  *   DIR is set to the top level customer directory name within SOURCE.  Now
  *   whether the same HEX file exists in the SRC/<dir> directory.  If so, the
  *   oldest of the two modified times is used.
  }
  string_vstring (tk, '(cog)source/'(0), -1); {init to fixed part of pathname}
  string_append (tk, dir);             {into customer directory}
  string_append1 (tk, '/');
  string_append (tk, ent);             {HEX file name}
  file_info (                          {try to get info about HEX file in SOURCE dir}
    tk,                                {file name}
    [file_iflag_dtm_k],                {request last modified time}
    finfo2,                            {return info, if available}
    stat);
  if not sys_error(stat) then begin    {found the file, got the info ?}
    if sys_clock_compare (finfo2.modified, finfo.modified) = sys_compare_lt_k then begin
      finfo.modified := finfo2.modified; {use the earlier timestamp}
      end;
    end;

  add_act (                            {collect this firmware version info if appropriate}
    dir,                               {source library, upper case}
    name,                              {project name, upper case}
    ptype_fw_k,                        {this is a firmware project}
    ver,                               {firmware version number}
    finfo.modified);                   {creation time}
  end;                                 {end of ordinary file directory entry type case}

      end;                             {end of directory entry type cases}
done_ent:                              {done processing this directory entry}
    end;                               {back to process next directory entry}
  end;
{
********************************************************************************
*
*   Subroutine SCAN_TREE_HW (SUBPATH)
*
*   Scan the directory tree starting at SUBPATH within the ~/eagle/proj
*   directory.  Hardware projects will be added to the list according to the
*   last modified date/time of the board file if one is present, otherwise the
*   date/time of the schematic file.
*
*   This routine calls itself recursively to process subordinate directories.
}
procedure scan_tree_hw (               {scan directory tree within SRC directory}
  in      subpath: univ string_var_arg_t); {path within SRC directory of the tree}
  val_param; internal;

var
  conn: file_conn_t;                   {connection to the top directory of the tree}
  dir: string_treename_t;              {scratch pathname}
  lib: string_treename_t;              {current customer designator name, upper case}
  ent: string_leafname_t;              {directory entry name}
  proj: string_leafname_t;             {project name prefix from directory structure}
  pname: string_leafname_t;            {project name with any version number removed}
  pver: sys_int_machine_t;             {version number suffix in PROJ, 0 for none}
  finfo: file_info_t;                  {extra info about current directory entry}
  tk: string_leafname_t;               {scratch token}
  i: sys_int_machine_t;                {scratch integer}
  p: string_index_t;                   {string parse index}
  ver: sys_int_machine_t;              {version number}
  stat: sys_err_t;                     {completion status}

label
  done_ent;

begin
  dir.max := size_char(dir.str);       {init local var strings}
  lib.max := size_char(lib.str);
  ent.max := size_char(ent.str);
  proj.max := size_char(proj.str);
  pname.max := size_char(pname.str);
  tk.max := size_char(tk.str);

  lib.len := 0;                        {init to no customer name and project from SUBPATH}
  proj.len := 0;
  if subpath.len > 0 then begin        {there is path to extract names from ?}
    p := 1;                            {init parse index into SUBPATH}
    string_token_anyd (                {extract first directory name from SUBPATH}
      subpath,                         {input string}
      p,                               {parse index, will be updated}
      '/', 1,                          {list of token delimiters}
      0,                               {no repeatable delimiters}
      [],                              {no additional options}
      lib,                             {first token parsed is customer name}
      i,                               {list index of the defining delimiter}
      stat);
    if p <= subpath.len then begin     {path contains additional levels ?}
      string_substr (                  {remainder of path is proj name prefix}
        subpath, p, subpath.len, proj);
      end;
    end;
  string_upcase (lib);
  string_upcase (proj);
  get_version (proj, pname, pver);     {extract generic name and version from project}

  string_vstring (dir, '~/eagle/proj'(0), -1); {init this directory to search root}
  if subpath.len > 0 then begin        {add subdirectory path}
    string_append1 (dir, '/');
    string_append (dir, subpath);
    end;
  file_open_read_dir (dir, conn, stat); {open directory for reading}
  if sys_error_check (stat, '', '', nil, 0) then return;

  while true do begin                  {scan this directory}
    file_read_dir (                    {read the next directory entry}
      conn,                            {connection to the directory}
      [ file_iflag_dtm_k,              {request last modified time}
        file_iflag_type_k],            {request file type}
      ent,                             {name of this directory entry}
      finfo,                           {info about this directory entry}
      stat);
    if file_eof(stat) then exit;       {done reading the directory ?}
    if sys_error_check (stat, '', '', nil, 0) then begin {hard error ?}
      file_close (conn);
      return;
      end;
    case finfo.ftype of                {what kind of file system object is this ?}
{
*   Directory entry is a subdirectory.
}
file_type_dir_k: begin
  string_copy (subpath, dir);          {init subdirectory to current directory}
  if dir.len > 0 then begin
    string_append1 (dir, '/');
    end;
  string_append (dir, ent);            {add subdirectory name}
  scan_tree_hw (dir);                  {handle this subdirectory recursively}
  end;
{
*   Directory entry is a ordinary file.
}
file_type_data_k: begin
  if lib.len <= 0 then goto done_ent;  {ignore files in top level (shouldn't be there)}
  if ent.len < 5 then goto done_ent;   {name too short to be SCH file}
  string_upcase (ent);                 {make file name upper case}
  string_substr (ent, ent.len - 3, ent.len, tk); {get last 4 file name chars}
  if not string_equal (tk, string_v('.SCH')) then goto done_ent; {not a SCH file ?}
  ent.len := ent.len - 4;              {truncate ".SCH" part of file name}
  get_version (ent, tk, ver);          {extract generic name and version number}
  string_copy (tk, ent);               {ENT is upper case name with version removed}
  {
  *   A new SCH file was found.  ENT contains the upper case generic SCH file
  *   name with any version number removed.  VER is the integer version number.
  }
  if                                   {temporary saved copy of the schematic ?}
      (ver = 0) and                    {these temporary files are not numbered}
      string_equal (ent, string_v('SAVE'))
    then goto done_ent;                {ignore SAVE.SCH files}

  string_copy (proj, tk);              {init project name from directory path}
  if                                   {directory is redundant project name ?}
      string_equal (ent, pname) and    {generic names match ?}
      (ver = pver)                     {version numbers match ?}
      then begin
    tk.len := 0;                       {remove the redundant name}
    end;
  if tk.len > 0 then begin             {there is project name start to add to ?}
    string_append1 (tk, '/');          {add separator before file name}
    end;
  string_append (tk, ent);             {make final project name}

  add_act (                            {collect this firmware version info if appropriate}
    lib,                               {source library, upper case}
    tk,                                {project name, upper case}
    ptype_hw_k,                        {this is a firmware project}
    ver,                               {firmware version number}
    finfo.modified);                   {creation time}
  end;                                 {end of ordinary file directory entry type case}

      end;                             {end of directory entry type cases}
done_ent:                              {done processing this directory entry}
    end;                               {back to process next directory entry}
  end;
{
********************************************************************************
*
*   Subroutine SHOW_VERSIONS (PROJ)
*
*   Write the version numbers of the project PROJ.  Three or more successive
*   versions is shown as a range, not enumerated version numbers.
}
procedure show_versions (              {show list of versions}
  in      proj: proj_t);               {project to show list of versions of}
  val_param; internal;

var
  ind: sys_int_machine_t;              {version list index}
  ver: sys_int_machine_t;              {current version}
  range: boolean;                      {within a sequential range}
  rstart, rend: sys_int_machine_t;     {start and end of the current range}
{
******************************
*
*   Subroutine SHOW_RANGE
*   This subroutine is private to SHOW_VERSIONS
*
*   Show the current range of versions, if any.  The will be no range in
*   progress when this routine returns.
}
procedure show_range;
  val_param; internal;

begin
  if not range then return;            {no range, nothing to do ?}
  range := false;                      {the active range will be ended}

  write (' ', rstart);                 {show start of range number}
  if rend = rstart then return;        {range was for single number ?}

  if rend = (rstart + 1) then begin    {range is for two consective numbers ?}
    write (' ', rend);                 {show the second number}
    return;
    end;

  write ('-', rend);                   {show range to ending value}
  end;
{
******************************
*
*   Start of main code for SHOW_VERSIONS.
}
begin
  range := false;                      {init to not within a range}

  for ind := 1 to proj.nver do begin   {once for each version}
    ver := proj.ver[ind];              {get this version into VER}
    if range then begin                {there is an existing range ?}
      if ver = (rend + 1) then begin   {this version extends the range ?}
        rend := ver;
        next;
        end;
      show_range;                      {show and end the existing range}
      end;
    range := true;                     {start new range with this version}
    rstart := ver;
    rend := ver;
    end;

  show_range;                          {show any unfinished range}
  end;
{
********************************************************************************
*
*   Subroutine SHOW_QUARTER (Q)
*
*   Show the activity for the quarter described by Q.
}
procedure show_quarter (               {show activity for a quarter}
  in      q: quart_t);                 {quarter to show activity for}
  val_param; internal;

var
  date: sys_date_t;                    {scratch date descriptor}
  proj_p: proj_p_t;                    {to current project}

begin
  sys_clock_to_date (                  {make start date of this quarter}
    q.start, tzone, hours_west, daysave, date);
  writeln;
  writeln (date.year:4, ' Q', ((date.month div 3) + 1));

  proj_p := q.proj_p;                  {init to first project in list for this quarter}
  while proj_p <> nil do begin         {scan the projects list for this quarter}
    write ('  ', proj_p^.lib.str:proj_p^.lib.len);
    case proj_p^.ptype of
ptype_fw_k: begin                      {firmware}
        write (' Firmware');
        end;
ptype_hw_k: begin                      {hardware}
        write (' Hardware');
        end;
otherwise
      writeln;
      writeln ('INTERNAL ERROR: Unexpected project type ID of ', ord(proj_p^.ptype), ' found.');
      sys_bomb;
      end;

    write (' ', proj_p^.name.str:proj_p^.name.len);
    if                                 {write list of versions ?}
        (proj_p^.nver <> 1) or         {not just one version ?}
        (proj_p^.ver[1] <> 0) or       {that version is not 0 ?}
        (proj_p^.ptype <> ptype_hw_k)  {this is not a hardware project ?}
        then begin
      show_versions (proj_p^);         {show the list of versions of this project}
      end;
    writeln;
    proj_p := proj_p^.next_p;          {advance to next project this quarter}
    end;
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
  {
  *   Initialize time to start of the previous year.
  }
  sys_timezone_here (tzone, hours_west, daysave); {get info about our timezone}
  sys_clock_to_date (                  {make expanded date from current time}
    sys_clock,                         {current time}
    tzone, hours_west, daysave,        {timezone info}
    date_end);                         {returned date}

  date := date_end;                    {make default activity starting date/time}
  date.year := date.year - 1;          {go back to start of previous year}
  date.month := 0;
  date.day := 0;
  date.hour := 0;
  date.minute := 0;
  date.second := 0;
  date.sec_frac := 0.0;
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-Y',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -Y year
}
1: begin
  string_cmline_token_int (ii, stat);  {get year into II}
  if sys_error(stat) then goto err_parm;
  date.year := ii;                     {set starting year}
  date_end.year := date.year + 1;      {set ending date/time}
  date_end.month := 0;
  date_end.day := 0;
  date_end.hour := 0;
  date_end.minute := 0;
  date_end.second := 0;
  date_end.sec_frac := 0.0;
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
*   Create the quarters list.  The activity for each quarter is initialized to
*   empty.  At least one list entry is always created.  Put another way, the
*   quarters list is guaranteed not to be empty for the rest of the code after
*   this section.
}
  qlist_p := nil;                      {init the quarters list to empty}
  qlist_last_p := nil;

  time := sys_clock_from_date(date);   {init current start of quarter time}
  while true do begin                  {advance thru quarters until DATE_END}
    sys_mem_alloc (sizeof(quart_p^), quart_p); {create descriptor for this quarter}
    quart_p^.next_p := nil;            {init to no following list entries}
    quart_p^.start := time;            {set start time for this quarter}
    date.month := date.month + 3;      {advance to start of next quarter}
    if date.month > 11 then begin      {past end of year}
      date.month := date.month - 12;   {to next year}
      date.year := date.year + 1;
      end;
    time := sys_clock_from_date(date); {make start time of next quarter}
    quart_p^.end := time;              {save ending time for this quarter}
    quart_p^.proj_p := nil;            {init to no projects in this quarter}

    if qlist_last_p = nil              {link this quarter to end of quarters list}
      then begin
        qlist_p := quart_p;
        end
      else begin
        qlist_last_p^.next_p := quart_p;
        end
      ;
    qlist_last_p := quart_p;

    if                                 {reached end date ?}
        (date.year >= date_end.year) and
        (date.month >= date_end.month)
      then exit;
    end;                               {back to create list entry for next quarter}
{
*   Gather the data.
}
  tk.len := 0;
  scan_tree_fw (tk);                   {look for new firmware versions}
  scan_tree_hw (tk);                   {look for hardware design activity}

  sort_quarts;                         {sort the activity for each quarter}
{
*   Show the results.
}
  quart_p := qlist_p;                  {init to first quarter in list}
  while quart_p <> nil do begin        {scan forwards thru the quarters}
    show_quarter (quart_p^);           {show the activity this quarter}
    quart_p := quart_p^.next_p;        {to next quarter in the list}
    end;                               {back to do next quarter}
  end.
