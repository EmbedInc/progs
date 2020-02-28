{   Program XCOPYRIGHT fnam
*
*   Quick hack to remove silly copyright notice from files that have them.
*   These copyright notices always seem to be on comment lines starting with
*   "*", then one or more blanks, then "::" with possibly other stuff following.
*
*   If a "*" only line preceeds the copyright block, then it is delete too.
*
*   If the copyright block is its own comment block with the open-curly line
*   immediately preceeding and the close-curly line immediately following, then
*   the whole comment block is deleted.
}
program xcopyright;
%include '(cog)lib/base.ins.pas';

var
  fnam:                                {file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {connection to the file}
  lines: string_list_t;                {list of file text lines}
  buf:                                 {one line input buffer}
    %include '(cog)lib/string8192.ins.pas';
  delprev: boolean;                    {previous line was deleted}
  del: boolean;                        {just deleted one or more lines}
  mod: boolean;                        {modifications made to lines list}
  p: string_index_t;                   {current line parse index}
  pchar: char;                         {single character one previous line}
  stat: sys_err_t;

label
  dodel, nodel, nxline;

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam, stat);    {get file name}
  string_cmline_req_check (stat);      {file name is required}
  string_cmline_end_abort;             {no more command line parameters allowed}
{
*   Read the file contents into the list LINES.
}
  file_open_read_text (fnam, '.pas', conn, stat); {open the file to read it}
  sys_error_abort (stat, '', '', nil, 0);

  string_list_init (lines, util_top_mem_context); {init text lines list}
  lines.deallocable := true;           {lines may be deleted individually}

  while true do begin                  {read the file lines into the list}
    file_read_text (conn, buf, stat);  {read line from file}
    if file_eof(stat) then exit;       {end of file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf);                {delete any trailing blanks}
    string_list_str_add (lines, buf);  {add this line to strings list}
    end;
  file_close (conn);                   {close the file}
{
*   Look for copyright lines and delete them.  All the copyright lines start
*   with "*", then blanks, then "::".
}
  del := false;                        {init to not just deleted lines}
  string_list_pos_abs (lines, 1);      {go to first line}
  while lines.str_p <> nil do begin    {loop over the lines}
    delprev := del;                    {save deletion status of previous line}
    del := false;                      {init to this line not deleted}
    if lines.str_p^.len < 3 then goto nodel; {too short to be copyright line ?}
    if lines.str_p^.str[1] <> '*' then goto nodel; {doesn't start with "*" ?}
    p := 2;                            {init parse index}
    while                              {skip over blanks}
      lines.str_p^.str[p] = ' '
      do p := p + 1;
    if (lines.str_p^.len - p) < 1 then goto nodel; {no room for "::" ?}
    if lines.str_p^.str[p] <> ':' then goto nodel; {first char not ":" ?}
    if lines.str_p^.str[p+1] <> ':' then goto nodel; {second char not ":" ?}
    {
    *   Found copyright line.  Delete it.
    }
dodel:
    string_list_line_del (lines, true); {delete this line, move to next}
    del := true;                       {indicate this line was deleted}
    mod := true;                       {indicate modification was made}
    next;
    {
    *   This line doesn't match, don't delete it.
    }
nodel:
    if delprev then begin              {just ended a block of deleted lines ?}
      string_list_pos_rel (lines, -1); {go to line just before deleted block}
      if lines.str_p^.len <> 1 then goto nxline; {not just a single character ?}
      pchar := lines.str_p^.str[1];    {save the single character}
      if pchar = '*' then begin        {just a blank comment line ?}
        string_list_line_del (lines, true); {delete the preceeding blank comment line}
        goto nxline;
        end;
      string_list_pos_rel (lines, 1);  {back to first line after deleted block}
      if pchar <> '{' then goto nxline; {previous line wasn't blank comment start ?}
      if lines.str_p^.len <> 1 then goto nxline; {this line not blank comment end ?}
      if lines.str_p^.str[1] <> '}' then goto nxline;
      string_list_line_del (lines, false); {delete the comment end line}
      string_list_line_del (lines, true); {delete the comment start line}
      next;
      end;                             {done with after deleted block handling}

nxline:                                {advance to next line}
    string_list_pos_rel (lines, 1);    {to next line}
    end;                               {back to do next line in list}
{
*   Write the edited lines list to the file if modifications were made.
}
  if mod then begin                    {modified ?}
    writeln (fnam.str:fnam.len);
    file_open_write_text (fnam, '.pas', conn, stat);
    sys_error_abort (stat, '', '', nil, 0);

    string_list_pos_start (lines);     {go to before first list line}
    while true do begin                {loop over the lines}
      string_list_pos_rel (lines, 1);  {to next line}
      if lines.str_p = nil then exit;  {hit end of list ?}
      file_write_text (lines.str_p^, conn, stat); {write this line to file}
      sys_error_abort (stat, '', '', nil, 0);
      end;                             {back to do next line in list}

    file_close (conn);
    end;                               {end of content was modified}
  end.
