{   Program L [<directory name>]
*
*   List contents of directory.
}
program l;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

const
  separate = 2;                        {min chars between columns}
  max_msg_parms = 1;                   {max parameters we can pass to a message}

type
  namtyp_k_t = (                       {file system object naming types}
    namtyp_leaf_k,                     {leafname}
    namtyp_rel_k,                      {relative to top listing directory}
    namtyp_tree_k);                    {full treename}

var
  width_out: sys_int_machine_t;        {max width of output lists, if possible}
  dnam:                                {directory name from command line}
    %include '(cog)lib/string_treename.ins.pas';
  topdir:                              {treename of top directory to list}
    %include '(cog)lib/string_treename.ins.pas';
  i: sys_int_machine_t;                {scratch integer and loop counter}
  c: char;                             {scratch character}
  dnam_set: boolean;                   {TRUE if DNAM set on command line}
  enab_file: boolean;                  {enable listing or ordinary files}
  enab_dir: boolean;                   {enable listing of directory names}
  enab_link: boolean;                  {enable listing of symbolic links}
  namtyp: namtyp_k_t;                  {what part of name to show for each object}
  tree: boolean;                       {show whole tree at listing directory}
  sline: boolean;                      {show each obj on single line, no headers}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  next_opt, err_parm, parm_bad, done_opts;
{
***********************************************
*
*   Local subroutine STRING_WRITE_CHARS (S)
*
*   Write string contents to standard output.  Nothing other than the string
*   contents (like CRLF) is written.
}
procedure string_write_chars (         {write string chars only, no CRLF}
  in    s: univ string_var_arg_t);     {string to write to standard output}
  val_param; internal;

type
  long_str_t = array[1..30000] of char;

var
  long_p: ^long_str_t;

begin
  long_p := univ_ptr(addr(s.str));
  write (long_p^:s.len);
  end;
{
***********************************************
*
*   Local subroutine WRITE_LIST (LIST, PATH, MAX_LEN)
*
*   Write the contents of the strings list LIST.  MAX_LEN is the length
*   of the longest entry in the list.  It is used to determine column width.
*   Only one column is written when MAX_LEN is zero.
}
procedure write_list (
  in out  list: string_list_t;         {handle to the list}
  in      path: string_treename_t;     {path to show before each list entry}
  in      max_len: sys_int_machine_t); {length of longest entry in the list}
  val_param; internal;

var
  columns: sys_int_machine_t;          {number of columns to format output into}
  col: sys_int_machine_t;              {current column number}
  len: sys_int_machine_t;              {length of last name written}
  mxlen: sys_int_machine_t;            {max length with PATH}
  addlen: sys_int_machine_t;           {length added to each entry to show}
  pnam: string_treename_t;             {full pathname to show}

begin
  pnam.max := size_char(pnam.str);     {init local var string}

  if list.n <= 0 then return;          {this list is empty ?}
  string_list_pos_abs (list, 1);       {position to the start of the list}
  if not sline then writeln;           {leave blank line before list}

  addlen := 0;                         {init nothing added to each raw entry}
  if                                   {need to add size of PATH ?}
      (max_len > 0) and                {MAX_LEN is valid ?}
      (path.len > 0)                   {PATH is not empty ?}
      then begin
    string_pathname_join (path, list.str_p^, pnam); {make trial pathname}
    addlen := pnam.len - list.str_p^.len; {find num chars added to make pathname}
    end;
  mxlen := max_len + addlen;           {max length of any entry to list}
  columns := max(1,                    {columns for output formatting}
    (width_out + separate) div (mxlen + separate));
  if                                   {force single column ?}
      (max_len <= 0) or                {single column requested by caller ?}
      sline                            {in single object per line raw mode ?}
      then begin
    columns := 1;                      {make just one column of names}
    end;
  col := 1;                            {init number of next column to use}

  while list.str_p <> nil do begin     {once for each entry in list}
    len := list.str_p^.len + addlen;   {save length entry as will be listed}
    if path.len <= 0
      then begin                       {show raw list entry}
        string_write_chars (list.str_p^); {write this list entry}
        end
      else begin                       {show list entry with preceeding path}
        string_pathname_join (path, list.str_p^, pnam);
        string_write_chars (pnam);
        end
      ;
    string_list_pos_rel (list, 1);     {advance to next entry in this list}
    col := col + 1;                    {make number of next column}
    if col <= columns
      then begin                       {there is room for more on this line}
        if list.str_p <> nil then begin {there is another entry to write ?}
          write (' ':(mxlen + separate - len)); {skip to start of next column}
          end;
        end
      else begin                       {we just wrote into the last column this line}
        writeln;                       {close this line, advance to next line}
        col := 1;                      {next entry goes into first column}
        end
      ;
    end;                               {back for next list entry}
  if col > 1 then writeln;             {close partial line, if any}
  end;
{
***********************************************
*
*   Subroutine MAKE_PRINTABLE (S)
*
*   Insure that all characters in the string S are printable.  Any non-printable
*   characters will be substituted with NONT_PRINT_CHAR (defined below).
}
procedure make_printable (
  in out  s: univ string_var_arg_t);
  val_param; internal;

const
  non_print_char = '*';                {character to substitute for control chars}

var
  i: sys_int_machine_t;                {loop counter}

begin
  for i := 1 to s.len do begin         {once for each character in the string}
    if (s.str[i] < ' ') or (s.str[i] > '~') then begin {non printable character ?}
      s.str[i] := non_print_char;      {substitute the special character}
      end
    end;                               {back to process next character in string}
  end;
{
***********************************************
*
*   Subroutine LISTDIR (DIR, STAT)
*
*   List the contents of the directory DIR according to the current settings.
*   This routine will call itself recursively to list subordinate directories.
}
procedure listdir (                    {list directory according to curr settings}
  in      dir: univ string_var_arg_t;  {the directory to list}
  out     stat: sys_err_t);            {completion status code}
  val_param; internal;

var
  max_file, max_dir:                   {max width for names in each list except link}
    sys_int_machine_t;
  list_file, list_dir, list_link:      {handles to each of the lists}
    string_list_t;
  info: file_info_t;                   {additional info about directory entry}
  conn: file_conn_t;                   {connection handle to directory}
  tnam: string_treename_t;             {scratch treename}
  fnam: string_treename_t;             {scratch pathname}
  lexp: string_treename_t;             {link expansion name}
  lnam: string_leafname_t;             {scratch leafname}

label
  loop_in, done_in;

begin
  tnam.max := size_char(tnam.str);     {init local var strings}
  fnam.max := size_char(fnam.str);
  lexp.max := size_char(lexp.str);
  lnam.max := size_char(lnam.str);

  file_open_read_dir (dir, conn, stat); {open the directory for read}
  if sys_error(stat) then return;
  if topdir.len = 0 then begin         {top directory name not set yet ?}
    string_copy (conn.tnam, topdir);   {save full treename of top directory}
    end;

  if not sline then begin
    writeln ('Directory ', conn.tnam.str:conn.tnam.len); {show directory name}
    end;

  string_list_init (list_file, util_top_mem_context); {init list of file names}
  string_list_init (list_dir, util_top_mem_context); {init list of directory names}
  string_list_init (list_link, util_top_mem_context); {init list of link names}
  list_file.deallocable := false;      {won't need to delete any list entries}
  list_dir.deallocable := false;
  list_link.deallocable := false;
  max_file := 0;                       {init max width of names in each list}
  max_dir := 0;

loop_in:                               {back here for each directory entry}
  file_read_dir (                      {get next directory entry}
    conn,                              {handle to directory connection}
    [file_iflag_type_k],               {we need to know what type of file it is}
    tnam,                              {returned directory entry name}
    info,                              {additional info about dir entry}
    stat);
  if file_eof(stat) then goto done_in; {exhausted directory ?}
  discard( sys_stat_match (file_subsys_k, file_stat_info_partial_k, stat) );
  sys_error_abort (stat, 'file', 'read_dir', nil, 0);

  if not (file_iflag_type_k in info.flags) then begin {didn't get file type ?}
    info.ftype := file_type_data_k;    {assume normal data file}
    end;
  case info.ftype of                   {what kind of file system object is this ?}
{
*   This directory entry is a directory.
}
file_type_dir_k: begin
      list_dir.size := tnam.len;       {set length for new list entry}
      max_dir := max(max_dir, list_dir.size); {update length of longest name}
      string_list_line_add (list_dir); {create new list entry for this name}
      string_copy (tnam, list_dir.str_p^); {save this name in directories list}
      make_printable (list_dir.str_p^); {convert to all printable characters}
      end;
{
*   This directory entry is a symbolic link.
}
file_type_link_k: begin
      if sline
        then begin                     {show only link name}
          list_link.size := tnam.len;
          end
        else begin                     {show link name and link target}
          string_pathname_join (conn.tnam, tnam, fnam); {make complete link treename}
          file_link_resolve (fnam, lexp, stat); {get link text}
          sys_error_abort (stat, '', '', nil, 0);
          list_link.size := tnam.len + lexp.len + 4; {set length for new list entry}
          end
        ;
      string_list_line_add (list_link); {create new list entry for this name}
      string_copy (tnam, list_link.str_p^); {start with link leafname}
      if not sline then begin          {also show link target ?}
        string_appendn (list_link.str_p^, ' -> ', 4);
        string_append (list_link.str_p^, lexp); {show link expansion}
        end;
      make_printable (list_link.str_p^); {convert to all printable characters}
      end;
{
*   All other directory entry types are treated like normal files.
}
otherwise
    list_file.size := tnam.len;        {set length for new list entry}
    max_file := max(max_file, list_file.size); {update length of longest name}
    string_list_line_add (list_file);  {create new list entry for this name}
    string_copy (tnam, list_file.str_p^); {save this name in directories list}
    make_printable (list_file.str_p^); {convert to all printable characters}
    end;                               {end of directory entry type cases}

  goto loop_in;                        {back to read next directory entry}
{
*   Done reading all the directory entries.  The name from each entry has been
*   added to one of the lists.  Now write the contents of the lists.
}
done_in:                               {all done processing input lines}
  tnam.len := 0;                       {init to show nothing before leafname}
  case namtyp of                       {how should names be shown ?}
namtyp_rel_k: begin                    {show pathname relative to top list directory}
      string_copy (conn.tnam, fnam);   {init source to whole treename}
      while fnam.len > topdir.len do begin {FNAM still contains part of rel name ?}
        string_pathname_split (fnam, lexp, lnam); {get last leafname into LNAM}
        string_copy (lexp, fnam);      {update part of pathname not in TNAM}
        string_pathname_join (lnam, tnam, lexp); {make new directory rel name}
        string_copy (lexp, tnam);      {update new directory relative name}
        end;
      end;
namtyp_tree_k: begin                   {show full treename}
      string_copy (conn.tnam, tnam);
      end;
    end;                               {TNAM is path to show before each leafname}

  file_close (conn);                   {close directory}

  if enab_file then begin
    string_list_sort (                 {sort the file names alphabetically}
      list_file, [string_comp_ncase_k, string_comp_num_k]);
    write_list (list_file, tnam, max_file); {write list of files}
    end;

  if enab_dir or tree then begin       {need sorted directories list ?}
    string_list_sort (                 {sort the directory names alphabetically}
      list_dir, [string_comp_ncase_k, string_comp_num_k]);
    end;
  if enab_dir then begin
    write_list (list_dir, tnam, max_dir); {write list of directories}
    end;

  if enab_link then begin
    string_list_sort (                 {sort the link names alphabetically}
      list_link, [string_comp_ncase_k, string_comp_num_k]);
    write_list (list_link, tnam, 0);   {write list of links}
    end;
{
*   List all subdirectories if enabled.
}
  if tree then begin                   {listing whole tree ?}
    string_list_pos_abs (list_dir, 1); {position to first entry in subdir list}
    while list_dir.str_p <> nil do begin {once for each subdirectory}
      if not sline then writeln;       {leave blank line before new directory}
      string_pathname_join (conn.tnam, list_dir.str_p^, tnam); {make subdir treename}
      listdir (tnam, stat);            {list this subtree}
      if sys_error(stat) then return;
      string_list_pos_rel (list_dir, 1); {advance to next list entry}
      end;                             {back to process this new list entry}
    end;
{
*   All the information has been written.  Now clean up and leave.
}
  string_list_kill (list_file);        {deallocate the lists}
  string_list_kill (list_dir);
  string_list_kill (list_link);
  end.
{
***********************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
{
*   Initialize our state before reading the command line options.
}
  dnam_set := false;                   {init to directory name not specified}
  enab_file := true;                   {enable listing of ordinary files}
  enab_dir := true;                    {enable listing or directories}
  enab_link := true;                   {enable listing of symbolic links}
  namtyp := namtyp_leaf_k;             {show leaf name of each object listed}
  tree := false;                       {show only listing directory, not whole tree}
  sline := false;                      {show multiple objects on a line as fit}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit directory name ?}
    if not dnam_set then begin         {directory name not set yet ?}
      string_copy (opt, dnam);         {set directory name}
      dnam_set := true;                {directory name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-DIR -TREE -RNAM -TNAM -R -NF -ND -NL -LF -LD -LL -LO',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -DIR dir
}
1: begin
  if dnam_set then begin               {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (dnam, stat);
  dnam_set := true;
  end;
{
*   -TREE
}
2: begin
  tree := true;
  end;
{
*   -RNAM
}
3: begin
  namtyp := namtyp_rel_k;
  end;
{
*   -TNAM
}
4: begin
  namtyp := namtyp_tree_k;
  end;
{
*   -R
}
5: begin
  sline := true;
  end;
{
*   -NF
}
6: begin
  enab_file := false;
  end;
{
*   -ND
}
7: begin
  enab_dir := false;
  end;
{
*   -NL
}
8: begin
  enab_link := false;
  end;
{
*   -LF
}
9: begin
  enab_file := true;
  end;
{
*   -LD
}
10: begin
  enab_dir := true;
  end;
{
*   -LL
}
11: begin
  enab_link := true;
  end;
{
*   -LO flags
}
12: begin
  string_cmline_token (parm, stat);
  if sys_error(stat) then goto err_parm;
  enab_file := false;                  {reset to not list any object types}
  enab_dir := false;
  enab_link := false;

  for i := 1 to parm.len do begin      {once for each flag character}
    c := string_upcase_char (parm.str[i]); {get upper case flag character into C}
    case c of                          {which flag is it ?}
'A':  begin                            {all object types}
        enab_file := true;
        enab_dir := true;
        enab_link := true;
        end;
'D':  begin                            {directories}
        enab_dir := true;
        end;
'F':  begin                            {files}
        enab_file := true;
        end;
'L':  begin                            {symbolic links}
        enab_link := true;
        end;
otherwise
      topdir.str[1] := c;
      topdir.len := 1;
      sys_msg_parm_vstr (msg_parm[1], topdir);
      sys_message_bomb ('file', 'l_lo_badflag', msg_parm, 1);
      end;
    end;                               {back to process next flag letter}
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
  if not dnam_set then begin           {directory to list not explicitly set ?}
    string_vstring (dnam, '.', 1);     {default to current directory}
    end;

  width_out := sys_width_stdout;       {get available output width in characters}

  listdir (dnam, stat);                {list the contents of the indicated directory}
  sys_error_abort (stat, '', '', nil, 0);
  end.
