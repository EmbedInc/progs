{   Program AFONT_FONT <input file name> [<output file name>]
*
*   Create a binary .FONT file from and ASCII .AFONT file.
}
program afont_font;
%include 'base.ins.pas';

const
  max_font_size = 100000;              {max number of entries in font array}
  max_char_index = 127;                {largest number of valid character}
  max_msg_parms = 2;                   {max parameters we can pass to a message}

  max_font_index = max_font_size - 1;  {max allowable font array subscript}

var
  ar: array[0..max_font_index] of integer32; {font array}
  in_fnam,                             {input file name}
  out_fnam:                            {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {file connection}
  buf:                                 {one line input buffer}
    %include '(cog)lib/string80.ins.pas';
  token:                               {scratch token for parsing input buffer}
    %include '(cog)lib/string32.ins.pas';
  curr_char: sys_int_machine_t;        {current char ID being worked on}
  next_pos: sys_int_machine_t;         {AR index where to write next word}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  pick: sys_int_machine_t;             {number of token picked from list}
  p: string_index_t;                   {input buffer parse index}
  r32: real;                           {scratch real for string conversion}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {error completion code}

label
  in_loop, in_eof, no_room, err_at_line, abort;

begin
{
*   Read command line.
}
  string_cmline_init;                  {init for command line processing}

  string_cmline_token (in_fnam, stat); {get input file name}
  string_cmline_req_check (stat);

  string_cmline_token (out_fnam, stat); {get optional output file name}
  if string_eos(stat)
    then begin                         {output file name argument not present}
      string_generic_fnam (in_fnam, '.font', out_fnam); {use input file generic name}
      end
    else begin                         {not hit end of command line}
      sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
      end
    ;

  string_cmline_token (token, stat);   {try to get another command line argument}
  if not string_eos(stat) then begin   {not just hit end of command line ?}
    sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
    sys_msg_parm_vstr (msg_parm[1], token);
    sys_message_bomb ('string', 'cmline_extra_token', nil, 0);
    end;
{
*   Open input file and init before reading the file.
}
  file_open_read_text (in_fnam, '.afont', conn, stat); {open input file}
  sys_error_abort (stat, '', '', nil, 0);

  for curr_char := 0 to max_char_index do begin {once for each character}
    ar[curr_char] := 0;                {init to character not defined}
    end;

  curr_char := -1;                     {init to no char currently being built}
  next_pos := max_char_index + 1;      {init next place to put move/draw data}
{
*   Read the input file.
}
in_loop:                               {back here each new input file line}
  file_read_text (conn, buf, stat);    {read new input file line}
  if file_eof(stat) then goto in_eof;  {hit end of input file ?}
  sys_error_abort (stat, '', '', nil, 0);

  string_upcase (buf);                 {make input line all upper case}
  p := 1;                              {init input line parse pointer}
  string_token (buf, p, token, stat);  {get command name token}
  if sys_error_check (stat, '', '', nil, 0) then goto err_at_line;
  string_tkpick80 (token, 'CHAR MOVE DRAW', pick); {pick which command this is}
  case pick of                         {different code for each command}

1: begin                               {CHAR command}
  if curr_char <> -1 then begin        {current character to close out ?}
    ar[next_pos] := -1;                {indicate end of char definition}
    next_pos := next_pos + 1;          {advance write pointer}
    if next_pos > max_font_index then goto no_room; {hit end of font array ?}
    end;
  string_token_int (buf, p, curr_char, stat); {get new char number}
  if sys_error_check (stat, '', '', nil, 0) then begin
    goto err_at_line;
    end;
  if (curr_char < 0) or (curr_char > max_char_index) then begin
    writeln ('Character number out of range.');
    goto err_at_line;
    end;
  ar[curr_char] := next_pos;           {write start pointer for this char}
  end;

2: begin                               {MOVE command}
  string_token_fpm (buf, p, r32, stat); {get X coordinate value}
  if sys_error_check (stat, '', '', nil, 0) then begin
    goto err_at_line;
    end;
  ar[next_pos] := integer32(r32) & 16#0FFFFFFFE; {low bit =0 to indicate MOVE}
  next_pos := next_pos + 1;            {advance write pointer}
  if next_pos > max_font_index then goto no_room; {hit end of font array ?}

  string_token_fpm (buf, p, r32, stat); {get Y coordinate value}
  if sys_error_check (stat, '', '', nil, 0) then begin
    goto err_at_line;
    end;
  ar[next_pos] := integer32(r32);      {stuff Y coordinate into array}
  next_pos := next_pos + 1;            {advance write pointer}
  if next_pos > max_font_index then goto no_room; {hit end of font array ?}
  end;

3: begin                               {DRAW command}
  string_token_fpm (buf, p, r32, stat); {get X coordinate value}
  if sys_error_check (stat, '', '', nil, 0) then begin
    goto err_at_line;
    end;
  ar[next_pos] := integer32(r32) ! 1;  {low bit =1 to indicate MOVE}
  next_pos := next_pos + 1;            {advance write pointer}
  if next_pos > max_font_index then goto no_room; {hit end of font array ?}

  string_token_fpm (buf, p, r32, stat); {get Y coordinate value}
  if sys_error_check (stat, '', '', nil, 0) then begin
    goto err_at_line;
    end;
  ar[next_pos] := integer32(r32);      {stuff Y coordinate into array}
  next_pos := next_pos + 1;            {advance write pointer}
  if next_pos > max_font_index then goto no_room; {hit end of font array ?}
  end;

otherwise
    writeln ('Unrecognized command name.');
    goto err_at_line;
    end;
  goto in_loop;                        {back for next input file line}
{
*   End of input file was encountered.
}
in_eof:                                {end of file encountered on .AFONT input file}
  file_close (conn);                   {close input file}

  if curr_char <> -1 then begin        {need to terminate last character ?}
    ar[next_pos] := -1;                {indicate end of char definition}
    next_pos := next_pos + 1;          {advance write pointer}
    if next_pos > max_font_index then goto no_room; {hit end of font array ?}
    end;
{
*   Write the font data in the AR array to the output file.
}
  file_open_write_bin (out_fnam, '.font', conn, stat); {open output file}
  sys_error_abort (stat, '', '', nil, 0);

  if sys_byte_order_k <> sys_byte_order_fwd_k then begin {need to flip byte order ?}
    for i := 0 to next_pos-1 do begin  {once for each font array entry}
      sys_order_flip (ar[i], sizeof(ar[i]));
      end;
    end;

  file_write_bin (                     {write all the font data to output file}
    ar,                                {output buffer}
    conn,                              {connection to output file}
    next_pos * sizeof(ar[0]),          {amount of data to write}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  file_close (conn);                   {close output file}
  return;                              {normal return}
{
*   Error exits.
}
no_room:                               {not enough room in AR array error}
  writeln ('Not enough room in font array.  Adjust MAX_FONT_SIZE.');
  goto abort;

err_at_line:                           {error at specific input file line number}
  sys_msg_parm_int (msg_parm[1], conn.lnum);
  sys_msg_parm_vstr (msg_parm[2], conn.tnam);
  sys_message_parms ('file', 'error_fnam_lnum', msg_parm, 2);
  goto abort;

abort:                                 {abort while input file open}
  file_close (conn);                   {close the file}
  sys_bomb;
  end.
