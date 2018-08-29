{   Program PIC_ACTIVITY
*
*   Make a list of recent PIC firmware development activity and hardware design
*   activity by quarter.
}
program pic_activity;
%include 'base.ins.pas';

const
  max_ver = 100;                       {max versions of a project per quarter}
  nquart = 5;                          {N quarters to build info for starting with curr}

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

  quart_t = record                     {activity info about one quarter year}
    start: sys_clock_t;                {start time of this quarter}
    proj_p: proj_p_t;                  {points to list of projects this quarter}
    end;

var
  q: array[1 .. nquart] of quart_t;    {info on quarters from current back}
  tzone: sys_tzone_k_t;                {our time zone}
  hours_west: real;                    {our time zone hours west of CUT}
  daysave: sys_daysave_k_t;            {our time zone daylight savings strategy}
  date: sys_date_t;                    {scratch date descriptor}
  ii, jj: sys_int_machine_t;           {scratch integers and loop counters}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';
  proj_p: proj_p_t;                    {pointer to current project in list}
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
  qn: sys_int_machine_t;               {index for current quarter}
  comp: sys_compare_k_t;               {result of time comparison}
  proj_p: proj_p_t;                    {points to project in list of curr quarter}

label
  next_proj;

begin
  for qn := 1 to nquart do begin       {scan thru the quarters backwards in time}
    comp := sys_clock_compare (time, q[qn].start); {compare FW time to start of this quarter}
    if comp = sys_compare_lt_k then next; {created before this quarter ?}

    proj_p := q[qn].proj_p;            {init pointer to first project this quarter}
    while proj_p <> nil do begin       {scan the list of existing projects}
      if not string_equal(proj_p^.lib, lib) {source library names don't match ?}
        then goto next_proj;
      if not string_equal(proj_p^.name, proj) {project names don't match ?}
        then goto next_proj;
      if proj_p^.ptype <> ptype        {project type doesn't match ?}
        then goto next_proj;
      exit;                            {found existing entry for this firmware}
next_proj:                             {curr project doesn't match, on to next}
      proj_p := proj_p^.next_p;
      end;

    if proj_p = nil then begin         {no existing entry for this project ?}
      sys_mem_alloc (sizeof(proj_p^), proj_p); {create new project descriptor}
      proj_p^.next_p := q[qn].proj_p;  {link at start of list for this quarter}
      q[qn].proj_p := proj_p;
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
    exit;                              {no need to go back to previous quarters}
    end;                               {back to check the previous quarter}
  end;
{
********************************************************************************
*
*   Subroutine SCAN_TREE_SRC (SRCPATH)
*
*   Scan the directory tree starting at SRCPATH within the (cog)src directory.
*   Information about any HEX files with modified dates within the quarters of
*   interest will be added to the collected data.
*
*   This routine calls itself recursively to process subordinate directories.
}
procedure scan_tree_src (              {scan directory tree within SRC directory}
  in      srcpath: univ string_var_arg_t); {path within SRC directory of the tree}
  val_param; internal;

var
  conn: file_conn_t;                   {connection to the top directory of the tree}
  dir: string_treename_t;              {scratch pathname}
  lib: string_treename_t;              {current source library name}
  ent: string_leafname_t;              {directory entry name}
  finfo: file_info_t;                  {extra info about current directory entry}
  tk: string_leafname_t;               {scratch token}
  i: sys_int_machine_t;                {scratch integer}
  c: char;                             {scratch character}
  ver: sys_int_machine_t;              {firmware version number}
  stat: sys_err_t;                     {completion status}

label
  done_ent;

begin
  dir.max := size_char(dir.str);       {init local var strings}
  lib.max := size_char(lib.str);
  ent.max := size_char(ent.str);
  tk.max := size_char(tk.str);

  string_copy (srcpath, lib);          {save source library name for this subdir}
  string_upcase (lib);

  string_vstring (dir, '(cog)src'(0), -1); {init directory to SRC root}
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
  scan_tree_src (dir);                 {handle this subdirectory recursively}
  end;
{
*   Directory entry is a ordinary file.
}
file_type_data_k: begin
  if lib.len <= 0 then goto done_ent;  {ignore files in top level (shouldn't be there)}
  if ent.len < 5 then goto done_ent;   {name too short to be HEX file}
  string_upcase (ent);                 {make file name upper case}
  string_substr (ent, ent.len - 3, ent.len, tk); {get last 4 file name chars}
  if not string_equal (tk, string_v('.HEX')) then goto done_ent; {not a HEX file ?}
  ent.len := ent.len - 4;              {truncate ".HEX" part of file name}
  i := ent.len;                        {init index of last non-digit char}
  while true do begin                  {scan backwards looking for last non-digit}
    c := ent.str[i];                   {get this file name character}
    if (c < '0') or (c > '9') then exit; {this char is not a digit ?}
    i := i - 1;                        {go to previous character}
    if i <= 0 then exit;               {no more chars ?}
    end;
  if i = ent.len then goto done_ent;   {no version number ?}
  if i <= 0 then goto done_ent;        {all digits, no project name ?}
  string_substr (ent, i+1, ent.len, tk); {get version number part of file name}
  ent.len := i;                        {truncate firmware version number from file name}
  string_t_int (tk, ver, stat);        {make integer version number}
  if sys_error_check (stat, '', '', nil, 0) then goto done_ent;
  {
  *   A new HEX file was found for a released version of firmware.  ENT contains
  *   the upper case project name from the HEX file, and VER is the version
  *   number.
  }
  add_act (                            {collect this firmware version info if appropriate}
    lib,                               {source library, upper case}
    ent,                               {project name, upper case}
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
*   Start of main routine.
}
begin
{
*   Make the date for the start of the current quarter.
}
  sys_timezone_here (tzone, hours_west, daysave); {get info about our timezone}
  sys_clock_to_date (                  {make expanded date from current time}
    sys_clock,                         {current time}
    tzone, hours_west, daysave,        {timezone info}
    date);                             {returned date}
  date.day := 0;                       {back to start of current month}
  date.hour := 0;
  date.minute := 0;
  date.second := 0;
  date.sec_frac := 0.0;
  date.month := (date.month div 3) * 3; {back to start of current quarter}
{
*   Init the data for each quarter.
}
  for ii := 1 to nquart do begin       {once for each quarter to gather info for}
    q[ii].start := sys_clock_from_date(date); {set start time of this quarter}
    q[ii].proj_p := nil;               {init to no projects this quarter}
    if date.month < 3
      then begin                       {back to last quarter of previous year}
        date.year := date.year - 1;
        date.month := 9;
        end
      else begin                       {back to previous quarter in same year}
        date.month := date.month - 3;
        end
      ;
    end;                               {back to init data for previous quarter}
{
*   Gather the data.
}
  tk.len := 0;
  scan_tree_src (tk);                  {look in SRC directory for firmware activity}
  scan_tree_hw (tk);                   {look for hardware design activity}
{
*   Show the results.
}
  for ii := nquart downto 1 do begin   {scan forwards thru the quarters}
    sys_clock_to_date (q[ii].start, tzone, hours_west, daysave, date); {make Q start date}
    writeln;
    writeln (date.year:4, ' Q', ((date.month div 3) + 1));
    sort_projs (q[ii].proj_p);         {sort the projects of this quarter}
    proj_p := q[ii].proj_p;            {init to first project in list for this quarter}
    while proj_p <> nil do begin       {scan the projects list for this quarter}
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
      if                               {write list of versions ?}
          (proj_p^.nver <> 1) or       {not just one version ?}
          (proj_p^.ver[1] <> 0) or     {that version is not 0 ?}
          (proj_p^.ptype <> ptype_hw_k) {this is not a hardware project ?}
          then begin
        for jj := 1 to proj_p^.nver do begin
          write (' ', proj_p^.ver[jj]);
          end;
        end;
      writeln;
      proj_p := proj_p^.next_p;        {advance to next project this quarter}
      end;
    end;                               {back to do next quarter}
  end.
