{   Program FONT_AFONT <.font input file name> [<.afont output file name>]
*
*   Convert a binary .font file to an ASCII .afont file.
}
program font_afont;
%include 'base.ins.pas';

const
  max_font_size = 100000;              {max number of entries in font array}
  max_char_index = 127;                {largest number of valid character}
  max_msg_parms = 1;                   {max parameters we can pass to a message}

  max_font_index = max_font_size;      {max allowable font array subscript}

var
  ar: array[0..max_font_index + 1] of integer32; {font array}
  in_fnam,                             {input file name}
  out_fnam:                            {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn: file_conn_t;                   {file connection descriptor}
  tlen: sys_int_adr_t;                 {amount of data actually read}
  buf:                                 {one line output buffer}
    %include '(cog)lib/string80.ins.pas';
  token:                               {scratch token for string conversion}
    %include '(cog)lib/string32.ins.pas';
  curr_char: sys_int_machine_t;        {current char ID being worked on}
  i: sys_int_machine_t;                {font array index}
  max_i: sys_int_machine_t;            {maximum font array index}
  x, y: real;                          {coordinate from font file}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {error completion code}

begin
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
*   Read input file into AR array.
}
  file_open_read_bin (in_fnam, '.font', conn, stat); {open input file}
  sys_error_abort (stat, '', '', nil, 0);

  file_read_bin (                      {try to fill entire font array}
    conn,                              {connection to file}
    sizeof(ar[0]) * (max_font_size + 1), {max size of data to read}
    ar,                                {input buffer}
    tlen,                              {amount of data actually transferred}
    stat);
  discard (file_eof_partial(stat));    {we expect end of file before filling array}
  sys_error_abort (stat, '', '', nil, 0);
  if tlen > (sizeof(ar[0]) * max_font_size) then begin
    writeln ('Font file too large for this program.');
    sys_bomb;
    end;

  file_close (conn);                   {close input file}

  max_i := (tlen div sizeof(ar[0])) - 1; {make max AR index}
{
*   Flip the byte order if this machine uses backwards byte ordering.
}
  if sys_byte_order_k <> sys_byte_order_fwd_k then begin {need to flip font words ?}
    for i := 0 to max_i do begin       {once for each font array entry}
      sys_order_flip (ar[i], sizeof(ar[i]));
      end;
    end;
{
*   Init before looping thru characters.
}
  file_open_write_text (out_fnam, '.afont', conn, stat); {open output file}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Main loop.  Come back here for each possible character in the .font file.
}
  for curr_char := 0 to max_char_index do begin {once for each possible char}
    i := ar[curr_char];                {AR index of data for this character}
    if i = 0 then next;                {this character doesn't exist ?}

    buf.len := 0;                      {write CHAR command}
    string_appends (buf, 'CHAR');
    string_append1 (buf, ' ');
    string_f_int (token, curr_char);
    string_append (buf, token);
    file_write_text (buf, conn, stat);
    sys_error_abort (stat, '', '', nil, 0);

    while                              {keep looping until end of this character}
        (i <= max_i) and then          {not past end of font data ?}
        (ar[i] <> -1)                  {not character termination flag ?}
        do begin
      buf.len := 0;
      if (ar[i] & 1) = 0               {check MOVE/DRAW flag}
        then string_appendn (buf, 'MOVE ', 5)
        else string_appendn (buf, 'DRAW ', 5);
      x := real(ar[i] & (~1));         {get X with MOVE/DRAW bit set to zero}
      i := i + 1;                      {advance index to Y value}
      y := real(ar[i]);                {get Y value}
      i := i + 1;                      {advance to start of next coordinate}

      string_f_fp_free (token, x, 6);
      string_append (buf, token);      {add on X string}
      string_append1 (buf, ' ');
      string_f_fp_free (token, y, 6);
      string_append (buf, token);      {add on Y string}

      file_write_text (buf, conn, stat);
      sys_error_abort (stat, '', '', nil, 0);
      end;                             {back and process next coordinate}
    end;                               {back and process next character}

  file_close (conn);                   {close output file}
  end.
