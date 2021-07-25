{   Program DIRSIZE
*
*   Show the size of files and directories in the current directory.
}
program dirsize;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  entty_k_t = (                        {type of directory entry}
    entty_file_k,                      {data file}
    entty_dir_k);                      {subdirectory}

  ent_p_t = ^ent_t;
  ent_pp_t = ^ent_p_t;
  ent_t = record                       {info about one directory entry}
    next_p: ent_p_t;                   {pointer to next entry in list}
    name: string_leafname_t;           {file or directory name}
    size: double;                      {size in bytes}
    entty: entty_k_t;                  {type of this entry}
    end;

var
  mem_p: util_mem_context_p_t;         {pointer to our private mem context}
  ent_first_p: ent_p_t;                {pointer to first entry in list}
  ent_last_p: ent_p_t;                 {pointer to last entry in list}
  nent: sys_int_machine_t;             {total number of entries}
  tsize: double;                       {total size, bytes}

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
*   Local subroutine LIST_ENT_ADD (ENT)
*
*   Add the entry ENT to the end of the global directory entries list.
}
procedure list_ent_add (               {add entry to global dir entries list}
  in var  ent: ent_t);                 {the entry to add}
  val_param; internal;

begin
  if ent_last_p = nil
    then begin                         {this is first entry in list}
      ent_first_p := addr(ent);
      end
    else begin                         {adding to end of existing list}
      ent_last_p^.next_p := addr(ent);
      end
    ;
  ent_last_p := addr(ent);             {update pointer to last entry in list}

  nent := nent + 1;                    {count one more entry in the list}
  end;
{
********************************************************************************
*
*   Local function DIR_ENTS_SIZE (NAME, LEVEL)
*
*   Find the size of all files and subdirectories in the directory NAME.  This
*   routine calls itself recursively.  LEVEL is the recursion nesting level,
*   the the top being 0.  This is also the number of levels the directory NAME
*   is nested below the top level directory.
*
*   For the top level directory only (LEVEL = 0), each directory entry is added
*   to the global directory entries list.
}
function dir_ents_size (               {get size of all files/dirs in directory}
  in      name: string_treename_t;     {name of directory to scan}
  in      level: sys_int_machine_t)    {nexting level, 0 at top}
  :double;                             {size of all files/dirs in the directory}
  val_param; internal;

var
  conn: file_conn_t;                   {connection for reading the directory}
  finfo: file_info_t;                  {info about directory entry}
  ent: string_leafname_t;              {name of the current directory entry}
  sz: double;                          {size of current directory entry}
  sztot: double;                       {total size of directory contents}
  entty: entty_k_t;                    {type of this entry}
  subdir: string_treename_t;           {treename of any subdirectory}
  ent_p: ent_p_t;                      {pointer to list entry}
  stat: sys_err_t;                     {completion status}

begin
  ent.max := size_char(ent.str);       {init local var strings}
  subdir.max := size_char(subdir.str);

  file_open_read_dir (                 {open the current directory for reading}
    name,                              {name of directory to read}
    conn,                              {returned connection to the directory}
    stat);                             {completion status}
  sys_error_abort (stat, '', '', nil, 0);

  string_copy (conn.tnam, subdir);     {init name of any subdirectory}
  string_append1 (subdir, '/');
  sztot := 0.0;                        {init total size of directory entries}

  while true do begin                  {back here to read each new directory entry}
    file_read_dir (                    {read next directory entry}
      conn,                            {connection to the directory}
      [ file_iflag_len_k,              {requested info about this dir entry}
        file_iflag_type_k],
      ent,                             {returned name of this entry}
      finfo,                           {returned information about this entry}
      stat);
    if file_eof(stat) then exit;       {hit end of directory ?}
    sys_error_abort (stat, '', '', nil, 0);

    sz := finfo.len;                   {init size of this entry}

    case finfo.ftype of                {what kind of object is this ?}
file_type_dir_k: begin                 {this entry is a subdirectory ?}
        entty := entty_dir_k;          {remember that this entry is a subdirectory}
        subdir.len := conn.tnam.len + 1; {set to fixed prefix of subdir treename}
        string_append (subdir, ent);   {make full treename of the subdirectory}
        sz := sz + dir_ents_size (subdir, level+1); {process subdir recursively}
        end;
otherwise
      entty := entty_file_k;           {consider this entry an ordinary file}
      end;                             {end of entry type special handling cases}
    sztot := sztot + sz;               {add size of this entry to the total}

    if level = 0 then begin            {scanning top level directory ?}
      util_mem_grab (                  {allocate memory for this list entry}
        sizeof(ent_p^), mem_p^, false, ent_p);

      ent_p^.next_p := nil;            {fill in list entry}
      ent_p^.name.max := size_char(ent_p^.name.str);
      string_copy (ent, ent_p^.name);
      ent_p^.size := sz;
      ent_p^.entty := entty;

      list_ent_add (ent_p^);           {add this new entry to end of list}
      end;
    end;                               {back for next directory entry}

  file_close (conn);                   {close connection to the directory}
  dir_ents_size := sztot;              {return total size of this directory}
  end;
{
********************************************************************************
*
*   Local subroutine SIZE_STRING (SZ, STR)
*
*   Make the object size string in our standard format.
}
procedure size_string (                {make string from object size}
  in      sz: double;                  {size in bytes}
  in out  str: univ string_var_arg_t); {returned string}
  val_param; internal;

var
  stat: sys_err_t;

begin
  string_f_fp (                        {make size string}
    str,                               {output string}
    sz,                                {input floating point value}
    15,                                {fixed field width}
    0,                                 {exponent field width}
    0,                                 {min required total significant digits}
    12,                                {max allowed digits left of point}
    0,                                 {min required digits right of point}
    0,                                 {max allowed digits right of point}
    [string_ffp_group_k],              {write digits in groups, separator between}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
********************************************************************************
*
*   Local subroutine ENTS_SORT
*
*   Sort the entries list by ascending entry size.
}
procedure ents_sort;                   {sort list by ascending entry size}
  val_param; internal;

var
  unsort_p: ent_p_t;                   {start of remaining unsorted list}
  best_p: ent_p_t;                     {best entry so far in unsorted list}
  best_prevp: ent_pp_t;                {pointer to forward link to best entry}
  best_sz: double;                     {size of best entry so far}
  prev_pp: ent_pp_t;                   {pointer to forward link to current entry}
  ent_p: ent_p_t;                      {current entry in unsorted list}


begin
  unsort_p := ent_first_p;             {save pointer to the existing list}

  ent_first_p := nil;                  {reset official list to empty}
  ent_last_p := nil;
  nent := 0;

  while unsort_p <> nil do begin       {loop until all entries moved to official list}
    prev_pp := addr(unsort_p);         {init pointer to forward link to current entry}
    ent_p := prev_pp^;                 {init current entry to first in unsorted list}
    best_p := ent_p;                   {init best entry so far to the first}
    best_prevp := addr(unsort_p);
    best_sz := ent_p^.size;

    while true do begin                {loop over remaining entries}
      prev_pp := addr(ent_p^.next_p);  {advance to next entry}
      ent_p := ent_p^.next_p;
      if ent_p = nil then exit;        {hit end of list ?}
      if ent_p^.size > best_sz then next; {this entry isn't smaller ?}
      if                               {check for special case of equal sizes}
          (ent_p^.size = best_sz) and then
          (string_compare(ent_p^.name, best_p^.name) >= 0) {use names to sort}
        then next;
      best_p := ent_p;                 {switch to this entry as best so far}
      best_prevp := prev_pp;
      best_sz := ent_p^.size;
      end;                             {back to check next entry in unsorted list}

    best_prevp^ := best_p^.next_p;     {unlink best entry from unsorted list}
    list_ent_add (best_p^);            {add it to the end of the official list}
    end;                               {back to get next entry from unsorted list}
  end;
{
********************************************************************************
*
*   Subroutine ENTS_WRITE
*
*   Write the directory entries list to standard output.
}
procedure ents_write;                  {write list to STDOUT}
  val_param; internal;

var
  ent_p: ent_p_t;                      {pointer to current list entry}
  str: string_var1024_t;               {one output line}

begin
  str.max := size_char(str.str);

  ent_p := ent_first_p;
  while ent_p <> nil do begin          {loop over the list entries}
    size_string (ent_p^.size, str);    {init output line with entry size}
    string_append1 (str, ' ');         {separator after size}
    case ent_p^.entty of
entty_dir_k: string_append1 (str, 'D');
otherwise
      string_append1 (str, 'F');
      end;
    string_append1 (str, ' ');
    string_append (str, ent_p^.name);
    writeln (str.str:str.len);         {write this output line}
    ent_p := ent_p^.next_p;            {advance to next list entry}
    end;                               {back to process this new list entry}

  writeln;
  size_string (tsize, str);            {init summary line with total size}
  string_appends (str, ' total size of '(0));
  string_append_intu (str, nent, 0);   {number of entries}
  string_appends (str, ' directory entries'(0));
  writeln (str.str:str.len);           {write the summary line}
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
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
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
*   Done reading and processing the command line options.
}
  util_mem_context_get (util_top_mem_context, mem_p); {make our private mem context}
  ent_first_p := nil;                  {init list of directory entries to empty}
  ent_last_p := nil;
  nent := 0;
  tsize := 0.0;                        {init size of all directory entries}

  string_vstring (parm, '.'(0), -1);   {name of top level directory to read}
  tsize := dir_ents_size (parm, 0);    {scan the top level directory}

  ents_sort;                           {sort list by ascending entry size}
  ents_write;                          {show list on standard output}
  end.
