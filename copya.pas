{   Program COPYA <input file name> [<options>]
*
*   Copy a text file to another file.  The destination file is created if not
*   already existing, and overwritten if previously existing.  Various command
*   line options control operation.  See the COPYA documentation file for
*   details.
}
program copya;
%include '(cog)lib/base.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}
  tabto_max = 256;                     {max column tabs can be more than one space}
  tab = chr(9);                        {tab character}

type
  repl_p_t = ^repl_t;
  repl_t = record                      {info about one input to output string substitution}
    next_p: repl_p_t;                  {pointer to next substitution in list}
    patti: string_var80_t;             {input pattern}
    pattiu: string_var80_t;            {upper case input pattern}
    patto: string_var80_t;             {output pattern}
    excase: boolean;                   {use exact case for input match and substitution}
    end;

  blankmode_k_t = (                    {blank line processing mode}
    blankmode_copy_k,                  {copy all blank lines as found}
    blankmode_1_k,                     {write out only a single consecutive blank line}
    blankmode_del_k);                  {delete all blank lines}

var
  in_fnam,                             {input file name}
  out_fnam:                            {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn_in, conn_out: file_conn_t;      {file connection handles}
  lnum_from, lnum_to: sys_int_machine_t; {first/last line number to copy}
  pattf_p: repl_p_t;                   {pointer to first string substitution pattern}
  pattl_p: repl_p_t;                   {pointet to last substitution pattern in the chain}
  patt_p: repl_p_t;                    {scratch susbstitution pattern pointer}
  i, j: sys_int_machine_t;             {scratch integers and loop counters}
  tab_prev, tab_new: sys_int_machine_t; {previous and new tab stop column numbers}
  blankmode: blankmode_k_t;            {blank line processing mode}
  lnum: sys_int_machine_t;             {1-N number of the current line}
  in_fnam_set: boolean;                {TRUE if input file name explicitly set}
  out_fnam_set: boolean;               {TRUE if output file name explicitly set}
  dotab: boolean;                      {TRUE if translating tabs into spaces}
  stdout: boolean;                     {TRUE if output to standard output}
  fileout: boolean;                    {TRUE if output to a file}
  filein: boolean;                     {TRUE if input from a file}
  instr: boolean;                      {-S used, string is in IBUF}
  append: boolean;                     {append source to end of output file}
  outbin: boolean;                     {using binary output file hack}
  wblank: boolean;                     {last line written was a blank}
  wlnum: boolean;                      {write line number in front of each line}
  tabto:                               {table of from-to tab columns}
    array[1..tabto_max]                {column number tab found at}
    of sys_int_machine_t;              {column number to skip to for next char}
  ibuf,                                {input line buffer used in some cases}
  buf:                                 {one line text buffer}
    %include '(cog)lib/string8192.ins.pas';
  in_p, out_p: string_var8192_p_t;     {point to current IN and OUT buffers, IBUF or BUF}
  opts:                                {command line options names, space separated}
    %include '(cog)lib/string256.ins.pas';

  opt:                                 {command line option name}
    %include '(cog)lib/string_treename.ins.pas';
  token:                               {scratch command line token}
    %include '(cog)lib/string8192.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, next_tab_opt, done_tab_opts, done_tabs_set, done_opt, parm_bad,
  done_opts, loop, done_line, done_copy;
{
********************************************************************************
*
*   Subroutine PATT_CHECK (SI, P, SO, PA)
*
*   Check for the pattern specified in PA matching the string SI starting at
*   position P.  If so, advance P over the pattern in the input string and
*   write the substitution to the output string.  If not, copy the character
*   at P to the output string and advance P by 1.
}
procedure patt_check (                 {check for pattern match}
  in      si: string_var8192_t;        {string to check for match in}
  in out  p: string_index_t;           {SI index to check for pattern match at}
  in out  so: string_var8192_t;        {output string}
  in      pa: repl_t);                 {string substitution descriptor}

var
  ii: string_index_t;                  {input string index}
  ip: string_index_t;                  {pattern string index}
  lasti: string_index_t;               {ending input string index of pattern if match}
  c: char;                             {scratch character}
  ucase: boolean;                      {at least one upper case char in input string}
  lcase: boolean;                      {at least one lower case char in input string}
  ucase1: boolean;                     {first input string char is upper case}

label
  no_match, done_repl;

begin
  lasti := p + pa.patti.len - 1;       {index of last SI char to match pattern}
  if lasti > si.len then goto no_match; {no room for the pattern here ?}

  ip := 1;                             {init pattern index}
  ucase := false;                      {init to not upper case char in input string}
  lcase := false;                      {init to no lower case char in input string}
  if pa.excase
    then begin                         {upper/lower case must match pattern exactly}
      for ii := p to lasti do begin    {scan input string region that could match pattern}
        c := si.str[ii];               {fetch this input string char}
        if c <> pa.patti.str[ip] then goto no_match; {input string not match pattern ?}
        ip := ip + 1;                  {advance to next pattern char}
        end;                           {back to do next input string char}
      end
    else begin                         {case-independent match}
      for ii := p to lasti do begin    {scan input string region that could match pattern}
        c := si.str[ii];               {fetch this input string char}
        ucase := ucase or ((c >= 'A') and (c <= 'Z')); {update upper case char found}
        lcase := lcase or ((c >= 'a') and (c <= 'z')); {update lower case char found}
        c := string_upcase_char(c);    {make upper case input string character}
        if c <> pa.pattiu.str[ip] then goto no_match; {input string not match pattern ?}
        ip := ip + 1;                  {advance to next pattern char}
        end;                           {back to do next input string char}
      end
    ;
{
*   The input string matches the pattern.
}
  if pa.patto.len <= 0 then goto done_repl; {no output pattern, done doing the replace ?}

  if pa.excase
    then begin                         {write pattern in its original case}
      for ii := 1 to pa.patto.len do begin {scan the replacement pattern}
        c := pa.patto.str[ii];         {fetch this replacement char}
        string_append1 (so, c);        {append this replacement char to output string}
        end;
      end
    else begin
      ucase := ucase and (not lcase);  {make body of replacement upper case ?}

      c := si.str[p];                  {get first input char}
      ucase1 := (c >= 'A') and (c <= 'Z'); {first input char is upper case ?}
      c := pa.patto.str[1];            {get first replacement pattern char}
      if ucase1 or ucase then c := string_upcase_char(c);
      string_append1 (so, c);          {write first replacement char to output string}

      for ii := 2 to pa.patto.len do begin {scan rest of replacement pattern}
        c := pa.patto.str[ii];         {fetch this replacement char}
        if ucase then c := string_upcase_char(c); {make upper case ?}
        string_append1 (so, c);        {append this replacement char to output string}
        end;
      end
    ;

done_repl:                             {done writing output pattern to output string}
  p := p + pa.patti.len;               {advance input index to after replaced pattern}
  return;

no_match:                              {input string does not match pattern}
  string_append1 (so, si.str[p]);      {copy this input char to output unaltered}
  p := p + 1;                          {advance to next input string char}
  end;
{
********************************************************************************
*
*   Subroutine DOPATT (SI, SO, PA)
*
*   Perform the string substition on the input line SI according to the pattern
*   PA and write the result to the output line SO.
}
procedure dopatt (                     {process line for one string substitution}
  in      si: string_var8192_t;        {input line}
  in out  so: string_var8192_t;        {output line}
  in      pa: repl_t);                 {string substitution descriptor}
  val_param; internal;

var
  p: string_index_t;                   {current input string character}

begin
  so.len := 0;                         {init output string to empty}
  p := 1;                              {init input string position}
  while p <= si.len do begin           {scan the whole input string}
    patt_check (si, p, so, pa);        {check for and handle pattern at this location}
    end;
  end;
{
********************************************************************************
*
*   Subroutine BUFS_FLIP
*
*   Flip the input and output buffers.  IN_P points to the input buffer and
*   OUT_P to the output.  This routine should be called after any processing
*   that applies a transformation to the current line string by copying and
*   modifying it from the input buffer to the output buffer.  When not in the
*   process of such a transformation, IN_P must point to the source string, and
*   OUT_P to a scratch buffer.
*
*   This routine simply flips IN_P and OUT_P to point to the other buffer.
}
procedure bufs_flip;                   {flip input and output buffers}
  val_param; internal;

var
  p: univ_ptr;

begin
  p := in_p;
  in_p := out_p;
  out_p := p;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for parsing command line}

  lnum_from := 1;                      {init first line number to copy}
  lnum_to := 0;                        {init to copy to end of file}
  for i := 1 to tabto_max do begin     {once for each TABTO table entry}
    tabto[i] := i + 1;                 {init to tabs are just like spaces}
    end;
  in_fnam_set := false;                {init to no input file name set}
  out_fnam_set := false;               {init to output file name not explicitly set}
  dotab := false;                      {init to not translating tabs}
  stdout := false;                     {init to not copy output to standard out}
  fileout := true;                     {init to write output to output file}
  instr := false;                      {init to source is not string from cmdline}
  ibuf.len := 0;                       {init accumulated -S string}
  append := false;                     {init to not append to end of output file}
  outbin := false;                     {init to not using binary output hack}
  patt_p := nil;                       {init to no string substitution patterns}
  pattl_p := nil;
  wlnum := false;                      {init to not write line numbers}
  blankmode := blankmode_copy_k;       {init to copy all blank lines to the output}
{
*   Process the command line options.  Come back here each new command line
*   option.
}
  string_appends (opts, '-FROM'(0));   {1}
  string_appends (opts, ' -TO'(0));    {2}
  string_appends (opts, ' -TABS'(0));  {3}
  string_appends (opts, ' -OUT'(0));   {4}
  string_appends (opts, ' -SHOW'(0));  {5}
  string_appends (opts, ' -NSHOW'(0)); {6}
  string_appends (opts, ' -WRITE'(0)); {7}
  string_appends (opts, ' -NWRITE'(0)); {8}
  string_appends (opts, ' -LIST'(0));  {9}
  string_appends (opts, ' -IN'(0));    {10}
  string_appends (opts, ' -S'(0));     {11}
  string_appends (opts, ' -APPEND'(0)); {12}
  string_appends (opts, ' -REPL'(0));  {13}
  string_appends (opts, ' -NOBLANK'(0)); {14}
  string_appends (opts, ' -1BLANK'(0)); {15}
  string_appends (opts, ' -REPLNC'(0)); {16}
  string_appends (opts, ' -LNUM'(0));  {17}

next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit file name token ?}
    if not (in_fnam_set or instr) then begin {input file name ?}
      string_copy (opt, in_fnam);      {save input file name}
      in_fnam_set := true;
      goto next_opt;
      end;
    if not out_fnam_set then begin     {output file name ?}
      string_copy (opt, out_fnam);     {save output file name}
      out_fnam_set := true;            {output file name now definately set}
      goto next_opt;                   {done processing this command line option}
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick (opt, opts, pick);     {pick option name from the list}
  case pick of                         {do routine for specific option}
{
*   -FROM n
}
1: begin
  string_cmline_token_int (lnum_from, stat);
  lnum_from := max(lnum_from, 1);
  end;
{
*   -TO n
}
2: begin
  string_cmline_token_int (lnum_to, stat);
  lnum_to := max(lnum_to, 1);
  end;
{
*   -TABS t1 t2 . . . tN
}
3: begin
  tab_prev := 1;                       {init previous tab stop column}
  tab_new := 2;                        {init new tab stop column}

next_tab_opt:                          {back here for next tab stop number}
  string_cmline_token (token, stat);   {try to get next command line token}
  if string_eos(stat) then goto done_tab_opts; {hit end of command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', msg_parm, 2);
  string_t_int (token, tab_new, stat); {interpret token as next tab column}
  if sys_error(stat) then begin        {integer conversion error, assume not tab col}
    sys_error_none (stat);             {clear error condition}
    string_cmline_reuse;               {allow failed tab column token to be re-read}
    goto done_tab_opts;                {done reading tab columns}
    end;
  if tab_new < 2 then begin
    sys_msg_parm_int (msg_parm[1], tab_new);
    sys_message_bomb ('file', 'copya_tab_out_range', msg_parm, 1);
    end;
  if tab_new <= tab_prev then begin
    sys_msg_parm_int (msg_parm[1], tab_new);
    sys_msg_parm_int (msg_parm[2], tab_prev);
    sys_message_bomb ('file', 'copya_tabs_not_ascending', msg_parm, 2);
    end;
  for i := tab_prev to tab_new-1 do begin {once for each TABTO array entry to set}
    if (i >= 1) and (i <= tabto_max) then begin {tab stop within range ?}
      tabto[i] := tab_new;             {indicate where to go if tab found at I}
      end;
    end;
  i := tab_new - tab_prev;             {save size of last tab interval}
  tab_prev := tab_new;                 {update previous tab column for next time}
  tab_new := tab_prev + i;             {init next tab stop from last interval}
  goto next_tab_opt;                   {back for next tab stop}

done_tab_opts:                         {done reading tab stop columns}
  for i := tab_prev to tab_new-1 do begin {once for each TABTO entry this interval}
    if i > tabto_max then goto done_tabs_set; {all done setting tab stops ?}
    if i >= 1 then begin               {tab stop within range ?}
      tabto[i] := tab_new;             {indicate where to go if tab found at I}
      end;
    end;
  i := tab_new - tab_prev;             {save size of tab interval}
  tab_prev := tab_new;                 {set tab interval for next iteration}
  tab_new := tab_prev + i;
  goto done_tab_opts;                  {back for next tab interval iteration}
done_tabs_set:                         {all done setting tab stops}
  dotab := true;                       {enable tab interpretation}
  end;                                 {end of -TABS command line option case}
{
*   -OUT filename
}
4: begin
  if out_fnam_set then begin           {already set once before ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (out_fnam, stat); {get output file name}
  out_fnam_set := true;                {flag output file name as explicitly set}
  end;
{
*   -SHOW
}
5: begin
  stdout := true;
  end;
{
*   -NSHOW
}
6: begin
  stdout := false;
  end;
{
*   -WRITE
}
7: begin
  fileout := true;
  end;
{
*   -NWRITE
}
8: begin
  fileout := false;
  end;
{
*   -LIST
}
9: begin
  stdout := true;
  fileout := false;
  end;
{
*   -IN filename
}
10: begin
  if in_fnam_set or instr then begin   {input file or string already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (in_fnam, stat); {get input file name}
  in_fnam_set := true;                 {flag input file name as explicitly set}
  end;
{
*   -S string
}
11: begin
  if in_fnam_set then begin            {source is input file ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (buf, stat);     {get string parameter in BUF}
  string_append (ibuf, buf);           {add to end of existing input string}
  instr := true;                       {input data is IBUF string}
  end;
{
*   -APPEND
}
12: begin
  append := true;
  end;
{
*   -REPL patti patto
}
13: begin
  string_cmline_token (token, stat);   {get input pattern into TOKEN}
  if sys_error(stat) then goto parm_bad;
  string_cmline_token (buf, stat);     {get replacement pattern into BUF}
  if sys_error(stat) then goto parm_bad;
  if token.len = 0 then goto done_opt; {ignore on NULL input pattern}

  sys_mem_alloc (sizeof(patt_p^), patt_p); {allocate new string replacement descriptor}
  patt_p^.next_p := nil;               {init new descriptor}
  patt_p^.patti.max := size_char(patt_p^.patti.str);
  patt_p^.pattiu.max := size_char(patt_p^.pattiu.str);
  patt_p^.patto.max := size_char(patt_p^.patto.str);
  string_copy (token, patt_p^.patti);
  string_copy (patt_p^.patti, patt_p^.pattiu);
  string_upcase (patt_p^.pattiu);
  string_copy (buf, patt_p^.patto);
  patt_p^.excase := false;

  if pattl_p = nil
    then begin                         {this is first pattern in list}
      pattf_p := patt_p;
      end
    else begin                         {link to end of existing chain}
      pattl_p^.next_p := patt_p;
      end
    ;
  pattl_p := patt_p;                   {update pointer to last chain entry}
  end;
{
*   -NOBLANK
}
14: begin
  blankmode := blankmode_del_k;
  end;
{
*   -1BLANK
}
15: begin
  blankmode := blankmode_1_k;
  end;
{
*   -REPLNC patti patto
}
16: begin
  string_cmline_token (token, stat);   {get input pattern into TOKEN}
  if sys_error(stat) then goto parm_bad;
  string_cmline_token (buf, stat);     {get replacement pattern into BUF}
  if sys_error(stat) then goto parm_bad;
  if token.len = 0 then goto done_opt; {ignore on NULL input pattern}

  sys_mem_alloc (sizeof(patt_p^), patt_p); {allocate new string replacement descriptor}
  patt_p^.next_p := nil;               {init new descriptor}
  patt_p^.patti.max := size_char(patt_p^.patti.str);
  patt_p^.pattiu.max := size_char(patt_p^.pattiu.str);
  patt_p^.patto.max := size_char(patt_p^.patto.str);
  string_copy (token, patt_p^.patti);
  string_copy (patt_p^.patti, patt_p^.pattiu);
  string_upcase (patt_p^.pattiu);
  string_copy (buf, patt_p^.patto);
  patt_p^.excase := true;

  if pattl_p = nil
    then begin                         {this is first pattern in list}
      pattf_p := patt_p;
      end
    else begin                         {link to end of existing chain}
      pattl_p^.next_p := patt_p;
      end
    ;
  pattl_p := patt_p;                   {update pointer to last chain entry}
  end;
{
*   -LNUM
}
17: begin
  wlnum := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

done_opt:                              {done handling this command line option}

parm_bad:                              {jump here on parm error, STAT indicates err}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}
done_opts:                             {done with all the command line options}

  filein := not instr;                 {TRUE if there is an input file}

  if not (in_fnam_set or instr) then begin {no input file name given ?}
    sys_message_bomb ('file', 'no_input_filename', nil, 0);
    end;
{
*   Done reading command line.
*
*   Now open the input and output files.
}
  if filein then begin                 {input is coming from a file ?}
    file_open_read_text (in_fnam, '', conn_in, stat);
    sys_msg_parm_vstr (msg_parm[1], in_fnam);
    sys_error_abort (stat, 'file', 'open_input_read_text', msg_parm, 1);
    end;

  if fileout then begin                {supposed to write to output file ?}
    if not out_fnam_set then begin     {no output name explicitly given ?}
      if not filein then begin         {no input file name available ?}
        sys_message_bomb ('file', 'copya_no_outfile', nil, 0);
        end;
      string_generic_fnam (in_fnam, '', out_fnam); {use input file generic name}
      end;
    if append
      then begin                       {append to end of existing file, if present}
        file_open_bin (                {open output file for raw binary I/O}
          out_fnam, '',                {file name and suffixes}
          [file_rw_read_k, file_rw_write_k], {we need both read and write access}
          conn_out,                    {returned connection handle}
          stat);
        sys_msg_parm_vstr (msg_parm[1], out_fnam);
        sys_error_abort (stat, 'file', 'open_output_write_text', msg_parm, 1);
        file_pos_end (conn_out, stat); {move to the end of the file}
        sys_error_abort (stat, 'file', 'pos_eof', nil, 0);
        outbin := true;                {indicate we are using binary output hack}
        end
      else begin                       {overwrite existing file, if present}
        file_open_write_text (out_fnam, '', conn_out, stat);
        sys_msg_parm_vstr (msg_parm[1], out_fnam);
        sys_error_abort (stat, 'file', 'open_output_write_text', msg_parm, 1);
        end
      ;
    end;
{
*   Position the input file to the starting line number.
}
  lnum := 1;                           {init current line number}

  if (lnum_from > 1) and filein then begin {skip over some input file lines ?}
    file_skip_text (conn_in, lnum_from-1, stat); {skip up to first line to copy}
    sys_error_abort (stat, 'file', 'skip_input_text', nil, 0);
    end;
{
*   Main loop.  Come back here for each new line to copy.
}
  wblank := false;                     {init to not just written blank line}
loop:                                  {back here each new input file text line}
  if                                   {past where to stop copying from ?}
      filein and                       {source is a file ?}
      (lnum_to > 0) and                {ending input line was specified ?}
      (conn_in.lnum >= lnum_to)        {ending input line has been reached ?}
    then goto done_copy;

  if filein then begin                 {read next input file line ?}
    file_read_text (conn_in, ibuf, stat); {read next line from input file}
    if file_eof(stat) then goto done_copy; {reached end of input file ?}
    sys_error_abort (stat, 'file', 'read_input_text', nil, 0);
    lnum := conn_in.lnum;              {1-N number of this line}
    end;
  string_unpad (ibuf);                 {truncate trailing input line blanks}
  in_p := addr(ibuf);                  {init pointer to current input and output buffers}
  out_p := addr(buf);

  if dotab then begin                  {tab interpretation is enabled ?}
    buf.len := 0;                      {init translated line to empty}
    for i := 1 to ibuf.len do begin    {once for each input line char to process}
      if ibuf.str[i] = tab
        then begin                     {this input line character is a tab}
          j := tabto[buf.len + 1] - 1; {last BUF column to fill with spaces}
          while buf.len < j do begin   {still more padding needed ?}
            string_append1 (buf, ' ');
            end;
          end
        else begin                     {this is a regular input line character}
          string_append1 (buf, ibuf.str[i]);
          end
        ;
      end;                             {back to process next input line character}
    string_unpad (buf);                {make sure there are no trailing spaces}
    bufs_flip;                         {flip input and output buffers}
    end;
{
*   The current processed input line is IN_P^, and OUT_P^ is available as a scratch
*   buffer for the next processed version of the line.  TAB interpretation, if any,
*   has already been performed.
*
*   Now perform any string substitutions.
}
  patt_p := pattf_p;                   {init to first substitution pattern in the list}
  while patt_p <> nil do begin         {once for each pattern}
    dopatt (in_p^, out_p^, patt_p^);   {perform the substitution}
    bufs_flip;                         {flip the input and output buffers}
    patt_p := patt_p^.next_p;          {advance to next substitution in the chain}
    end;                               {back to do next substitution pattern}
{
*   Apply special handling to blank lines.
}
  if in_p^.len = 0
    then begin                         {this is a blank line}
      case blankmode of                {how to handle blank lines ?}
blankmode_1_k: begin                   {write only single consecutive blank line}
          if wblank then goto done_line; {already written a blank line ?}
          end;
blankmode_del_k: begin                 {don't write any blank lines}
          goto done_line;
          end;
        end;
      wblank := true;                  {will now write a blank line}
      end
    else begin                         {this is not a blank line}
      wblank := false;
      end;
    ;
{
*   Add the line number to the start of the line if this is enabled.
}
  if wlnum then begin                  {write line numbers ?}
    if lnum < 100000
      then begin                       {needs 5 digits or less}
        string_f_int_max_base (        {make line number string}
          out_p^,                      {output string}
          lnum,                        {input integer}
          10,                          {number base (radix)}
          5,                           {field width}
          [string_fi_unsig_k],         {consider the input integer unsigned}
          stat);
        end
      else begin                       {would overflow our normal 5 char field}
        string_f_int_max_base (        {make line number string}
          out_p^,                      {output string}
          lnum,                        {input integer}
          10,                          {number base (radix)}
          0,                           {field width, use whatever it takes}
          [string_fi_unsig_k],         {consider the input integer unsigned}
          stat);
        end
      ;
    string_appendn (out_p^, ': ', 2);  {add delimiter after line number}
    string_append (out_p^, in_p^);     {add the contents of the line}
    bufs_flip;                         {flip the input and output buffers}
    end;
{
*   The final processed line is in IN_P^.
}
  if fileout then begin                {writing to output file enabled ?}
    if outbin
      then begin                       {we are using binary output hack}
        case sys_os_k of               {what operating system are we running on ?}
sys_os_win16_k,                        {these systems use CRLF to end lines}
sys_os_win32_k,
sys_os_os2_k: begin
            in_p^.len := min(in_p^.len, in_p^.max - 2); {ensure room for EOL}
            string_appendn (in_p^, ''(13)(10), 2); {append EOL}
            end;
otherwise                              {assume use just LF to end lines}
          in_p^.len := min(in_p^.len, in_p^.max - 1); {ensure room for EOL}
          string_append1 (in_p^, chr(10)); {append EOL}
          end;
        file_write_bin (in_p^.str, conn_out, in_p^.len, stat); {write out line as bin}
        end
      else begin                       {normal text output file}
        file_write_text (in_p^, conn_out, stat); {write output line as text}
        end
      ;
    sys_error_abort (stat, 'file', 'write_output_text', nil, 0);
    end;

  if stdout then begin                 {writing to standard output enabled ?}
    writeln (in_p^.str:in_p^.len);
    end;

done_line:                             {done writing out this line}
  if instr then goto done_copy;        {we only have one input line ?}
  goto loop;                           {back to copy next line}

done_copy:
  if filein then begin                 {input file exists ?}
    file_close (conn_in);              {close input file}
    end;
  if fileout then begin                {output file exists ?}
    file_close (conn_out);             {close output file}
    end;
  end.
