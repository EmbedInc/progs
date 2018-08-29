{   Program FIND_STRING fnam string
*
*   Show each line of FNAM that contains the string STRING.
}
program find_string;
%include 'base.ins.pas';

const
  lnumn_k = 5;                         {min column width of line numbers}

var
  fnam:                                {file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {connection to the input file}
  patt:                                {string search pattern}
    %include '(cog)lib/string132.ins.pas';
  buf, ubuf:                           {one line input buffer, lower/upper case}
    %include '(cog)lib/string8192.ins.pas';
  tk:                                  {scratch token for number conversion}
    %include '(cog)lib/string32.ins.pas';
  fshown: boolean;                     {the input file name has already been shown}
  stat: sys_err_t;                     {completion status}

label
  loop_line, eof;
{
*******************************************************************************
*
*   Function FOUND_PATT (STR, SI, PATT, PI)
*
*   Return TRUE iff the string pattern in PATT starting at PI appears in the
*   string STR starting at SI.
}
function found_patt (                  {determine if pattern appears in string}
  in      str: univ string_var_arg_t;  {the string to search for the pattern in}
  in      si: string_index_t;          {starting index for STR}
  in      patt: univ string_var_arg_t; {the patter to search for}
  in      pi: string_index_t)          {starting index for PATT}
  :boolean;                            {TRUE if patter found in string}
  val_param; internal;

var
  ss: string_index_t;                  {start index into string}
  cs: string_index_t;                  {current temp index into string}
  cp: string_index_t;                  {current index into pattern}
  c: char;                             {scratch character}

label
  next_schar, match;

begin
  found_patt := false;                 {init to pattern not found in the string}
  if pi > patt.len then return;        {empty pattern never matches}

  for ss := si to str.len do begin     {once for each position in the string}
    cs := ss;                          {start at the current string position}
    cp := pi;                          {start at the beginning of the pattern}
    while cp <= patt.len do begin      {scan thru the pattern}
      if cs > str.len then return;     {exhausted string before the pattern ?}
      c := patt.str[cp];               {get next search pattern character}
      case c of                        {check for some special characters}

'^':    begin                          {escape, next char interpreted literally ?}
          cp := cp + 1;                {advance to the next pattern character}
          if cp > patt.len then return; {error, no character follows ?}
          c := patt.str[cp];           {get next literal pattern character}
          end;

'*':    begin                          {wildcard, matches any string up to following pattern}
          cp := cp + 1;                {make index of pattern following wildcard}
          if cp > patt.len then goto match; {wildcard at end of pattern (stupid but legal) ?}
          while cs <= str.len do begin {scan up to end of input string}
            if found_patt (str, cs, patt, cp) then goto match; {rest of pattern matched ?}
            cs := cs + 1;              {this string char matches wildcard, try next}
            end;
          return;                      {never found pattern following wildcard}
          end;

        end;                           {end of special character cases}
      {
      *   C is the literal pattern character to match.
      }
      cp := cp + 1;                    {to next pattern character for next time}
      if str.str[cs] <> c then goto next_schar; {no match at this string position}
      cs := cs + 1;                    {to next string char next patt char must match}
      end;                             {back to handle next pattern char}

match:                                 {pattern match found in the string}
    found_patt := true;                {indicate pattern match}
    return;

next_schar:                            {advance to next input string character}
    end;                               {back for pattern starting next string char}
  end;                                 {exhausted string, no pattern found}
{
*******************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam, stat);    {get the input file name}
  string_cmline_req_check (stat);
  string_cmline_token (patt, stat);    {get the string search pattern}
  string_cmline_req_check (stat);
  string_upcase (patt);                {make pattern upper case}
  string_cmline_end_abort;             {no additional command line options allowed}

  file_open_read_text (fnam, '', conn, stat); {open the input file}
  sys_error_abort (stat, '', '', nil, 0);
  fshown := false;                     {init to input file name not shown yet}

loop_line:                             {back here each new line from input file}
  file_read_text (conn, buf, stat);    {read new line from the input file}
  if file_eof(stat) then goto eof;     {hit end of input file}
  sys_error_abort (stat, '', '', nil, 0);
  string_copy (buf, ubuf);             {make upper case version of input line}
  string_upcase (ubuf);
  if found_patt (ubuf, 1, patt, 1) then begin {this line contains a matching string ?}
    if not fshown then begin           {file name not previously shown ?}
      writeln;                         {leave blank line before block for this file}
      writeln (conn.tnam.str:conn.tnam.len, ':'); {show file name for following matches}
      fshown := true;                  {indicate file name has now been shown}
      end;
    string_f_int (tk, conn.lnum);      {make line number string}
    if tk.len < lnumn_k then begin     {need blank padding before line number ?}
      write (' ':(lnumn_k - tk.len));  {write leading blanks to justify line number}
      end;
    writeln (tk.str:tk.len, ': ', buf.str:buf.len); {show line from file}
    end;
  goto loop_line;                      {back to do next input file line}

eof:                                   {hit end of input file}
  file_close (conn);                   {close the input file}
  end.
