{   Program RENAME_SYM fnam syold synew
*
*   Renames all occurances of the symbol SYOLD in file FNAM to SYNEW.  Pascal
*   rules for what is a symbol, what is in comments, etc, are used.
}
program rename_sym;
%include 'base.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  fnam:                                {name of file to edit}
    %include '(cog)lib/string_treename.ins.pas';
  syold, synew:                        {old and new symbol names}
    %include '(cog)lib/string32.ins.pas';
  conn: file_conn_t;                   {connection to the file being edited}
  lines: string_list_t;                {list of lines from the file}
  buf:                                 {one line buffer}
    %include '(cog)lib/string8192.ins.pas';
  excl: boolean;                       {in exclusion}
  exclend: char;                       {character to end the exclusion}

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
*   Subroutine TRANSLATE_SYMBOL (S1, S2)
*
*   Convert the original symbol name S1 to the new symbol name in S2.  If no
*   change is to be made, then just copy S1 to S2.
}
procedure translate_symbol (           {make new symbol name from old}
  in      s1: univ string_var_arg_t;   {original symbol name}
  in out  s2: univ string_var_arg_t);  {new resulting symbol name}
  val_param; internal;

begin
  if string_equal (s1, syold)
    then begin                         {this is the symbol to change}
      string_copy (synew, s2);         {return the replacement symbol name}
      end
    else begin                         {this is not the target symbol}
      string_copy (s1, s2);            {return the same symbol}
      end
    ;
  end;
{
********************************************************************************
*
*   Subroutine TRANSLATE_LINE (L1, L2)
*
*   Translate the file line L1 into L2.
}
procedure translate_line (             {make new file line from existing}
  in      l1: univ string_var_arg_t;   {original line}
  in out  l2: univ string_var_arg_t);  {result after editing}
  val_param; internal;

var
  p: string_index_t;                   {L1 parse index}
  c: char;                             {current L1 character being examined}
  sym: string_var80_t;                 {symbol name}
  synew: boolean;                      {a new symbol may start after prev char}
  systart: boolean;                    {valid character for starting a symbol}
  sycont: boolean;                     {valid character for continuing a symbol}
{
******************************
*
*   Local subroutine SYFINISH
*
*   The current symbol, if any, has finished.  If there is a current symbol,
*   write its translation to the output line and clear the symbol.
}
procedure syfinish;                    {finish current symbol, if any}
  val_param; internal;

var
  sym2: string_var80_t;                {translated symbol name}

begin
  sym2.max := size_char(sym2.str);     {init local var string}

  if sym.len = 0 then return;          {no symbol to finish, nothing to do ?}

  translate_symbol (sym, sym2);        {apply translation rules to this symbol}
  string_append (l2, sym2);            {add translated symbol to output line}
  sym.len := 0;                        {clear to not in a symbol}
  end;
{
******************************
*
*   Executable code for TRANSLATE_LINE.
}
begin
  sym.max := size_char(sym.str);       {init local var string}

  l2.len := 0;                         {init the translated result line to empty}
  sym.len := 0;                        {init to not in a symbol}
  synew := true;                       {symbol may start at start of line}

  for p := 1 to l1.len do begin        {scan the characters in the input string}
    c := l1.str[p];                    {fetch this input string character}

    if excl then begin                 {in a exclusion ?}
      string_append1 (l2, c);          {just copy character to output}
      excl := (c <> exclend);          {check for this char ends the exclusion}
      next;
      end;

    excl := true;                      {init to this char starts a new exclusion}
    case c of                          {check for start of new exclusion}
'"', '''': exclend := c;
'{':  exclend := '}';
otherwise
      excl := false;                   {not in a new exclusion}
      end;
    if excl then begin                 {just started a new exclusion ?}
      syfinish;                        {finish any symbol in progress}
      synew := true;                   {new symbol can start after the exclusion}
      string_append1 (l2, c);          {copy this char to output line}
      next;
      end;

    systart :=                         {this character could start a symbol ?}
      ((c >= 'a') and (c <= 'z')) or
      ((c >= 'A') and (c <= 'Z')) or
      (c = '_');
    sycont :=                          {this character could continue a symbol ?}
      systart or
      ((c >= '0') and (c <= '9')) or
      (c = '$');

    if sym.len = 0
      then begin                       {not currently in a symbol}
        if synew and systart
          then begin                   {this character starts a new symbol}
            string_append1 (sym, c);   {start the new symbol}
            end
          else begin                   {not start of new symbol}
            string_append1 (l2, c);    {just copy character to output line}
            end
          ;
        end
      else begin                       {already accumulating a symbol?}
        if sycont
          then begin                   {continue this symbol}
            string_append1 (sym, c);   {add this char to end of symbol}
            end
          else begin                   {this char is not part of symbol}
            syfinish;                  {finish the symbol}
            string_append1 (l2, c);    {copy this character to output line}
            end
          ;
        end
      ;

    synew := true;                     {init to next char could be start of new symbol}
    synew := synew and (not sycont);   {not after valid symbol character}
    synew := synew and (c <> '.');     {not after record field delimiter}
    end;                               {back to do next input line character}

  syfinish;                            {finish any symbol that may be in progress}
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
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit argument ?}
    if fnam.len <= 0 then begin        {file name not set yet ?}
      string_treename (opt, fnam);     {set file name}
      goto next_opt;
      end;
    if syold.len <= 0 then begin       {old symbol name not set ?}
      string_copy (opt, syold);
      goto next_opt;
      end;
    if synew.len <= 0 then begin       {new symbol name not set ?}
      string_copy (opt, synew);
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-F -OLD -NEW',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -F filename
}
1: begin
  string_cmline_token (opt, stat);
  string_treename (opt, fnam);
  end;
{
*   -OLD symbol
}
2: begin
  string_cmline_token (syold, stat);
  end;
{
*   -NEW symbol
}
3: begin
  string_cmline_token (synew, stat);
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

  if fnam.len <= 0 then begin
    sys_message_bomb ('string', 'cmline_input_fnam_missing', nil, 0);
    end;
  if syold.len <= 0 then begin
    writeln ('Old symbol name not set');
    sys_bomb;
    end;
  if synew.len <= 0 then begin
    writeln ('New symbol name not set');
    sys_bomb;
    end;
{
*   Read the file into the internal strings list.
}
  file_open_read_text (fnam, '', conn, stat); {open the file for reading}
  sys_error_abort (stat, '', '', nil, 0);
  string_copy (conn.tnam, fnam);       {save complete pathname of the file}

  string_list_init (lines, util_top_mem_context); {init list of lines from the file}
  lines.deallocable := true;           {individually deallocate lines when deleted}

  while true do begin                  {back here each new line from the file}
    file_read_text (conn, buf, stat);  {read new line into BUF}
    if file_eof(stat) then exit;       {hit end of file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf);                {delete any trailing blanks}

    lines.size := buf.len + 10;        {leave a little room to edit line in place}
    string_list_line_add (lines);      {create the new line in the list}
    string_copy (buf, lines.str_p^);   {save this file line in list}
    end;                               {back to do next file line}

  file_close (conn);                   {close the file}
{
*   Scan the list of file lines and edit them as appropriate.
}
  excl := false;                       {init to not in a exclusion}

  string_list_pos_start (lines);       {go to before first file line in list}
  while true do begin                  {loop over the list of lines}
    string_list_pos_rel (lines, 1);    {advance to next line}
    if lines.str_p = nil then exit;    {hit end of list ?}
    translate_line (lines.str_p^, buf); {make edited version of this line in BUF}
    if buf.len > lines.str_p^.max then begin {new line is too long for existing string ?}
      string_list_line_del (lines, false); {delete the old line}
      lines.size := buf.len;           {set length for new line}
      string_list_line_add (lines);    {create new larger line}
      end;
    string_copy (buf, lines.str_p^);   {overwrite with edited version}
    end;
{
*   Write the updated lines to the file.  These will completely overwrite the
*   existing file contents.
}
  file_open_write_text (fnam, '', conn, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_list_pos_start (lines);       {go to before first file line in list}
  while true do begin                  {loop over the list of lines}
    string_list_pos_rel (lines, 1);    {advance to next line}
    if lines.str_p = nil then exit;    {hit end of list ?}
    file_write_text (lines.str_p^, conn, stat); {write this line to file}
    sys_error_abort (stat, '', '', nil, 0);
    end;

  file_close (conn);                   {close file, truncate at this position}
  end.
