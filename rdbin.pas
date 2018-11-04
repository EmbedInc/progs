{   Program RDBIN <file name> [<options>]
*
*   Read the bytes in the binary file and print them in various formats.
*
*   Command line options are:
*
*     -ORDER order
*
*       Explicitly set the byte order for interpreting multi-byte fields.
*       The keywords are:
*
*         FWD  -  Forwards.  High byte stored first like Motorola 680x0.
*         BKW  -  Backwards.  Low byte stored first like Intel 80x86.
*
*     -SHOW fmt
*
*       Explicitly indicate which data interpretation formats to show.
*       Choices are:
*
*         HEX  -  Two hexadecimal characters per byte.
*         ASC  -  ASCII characters.
*         I8   -  8 bit integers, signed.
*         I8u  -  8 bit integers, unsigned.
*         I16  -  16 bit integers, signed.
*         I16u -  16 bit integers, unsigned.
*         I32  -  32 bit integers, signed.
*         I32u -  32 bit integers, unsigned.
*         FP32 -  32 bit floating point.
*         FP64 -  64 bit floating point.
*
*       Each format is shown accross the output line in the order given
*       for each block of 8 input bytes.  Only the chosen formats are shown.
*       The default is HEX ASC.  The list of formats is initialized to empty
*       when the first -SHOW command is encountered.
*
*   ***  NOTE  ***
*   The -SHOW and -ORDER command line options have not been implemented yet.
*   The old -R command line option is still active.
}
program rdbin;
%include '/cognivision_links/dsee_libs/sys/sys.ins.pas';
%include '/cognivision_links/dsee_libs/util/util.ins.pas';
%include '/cognivision_links/dsee_libs/string/string.ins.pas';
%include '/cognivision_links/dsee_libs/file/file.ins.pas';

const
  linsize = 8;                         {number of bytes per output line}
  group_size = 4;                      {number of bytes in horizontal group}
  max_msg_parms = 2;                   {max parameters we can pass to messages}

type
  ibuf_t =                             {template for input buffer}
    array[1..linsize] of char;

  ibuf_p_t =                           {pointer to input buffer}
    ^ibuf_t;

  c_p_t = ^char;

var
  ibuf_p: ibuf_p_t;                    {points to input data buffer}
  ibuf: ibuf_t;                        {input file buffer}
  fnam:                                {input file name}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';
  obuf:                                {one line output buffer}
    %include '/cognivision_links/dsee_libs/string/string132.ins.pas';
  s:                                   {scratch string}
    %include '/cognivision_links/dsee_libs/string/string32.ins.pas';
  i: sys_int_adr_t;                    {loop counter}
  im: sys_int_machine_t;               {scratch machine integer}
  i32: integer32;                      {32 bit integer for interpreting file}
  i16: integer16;                      {16 bit integer for interpreting file}
  r32: real;                           {32 bit floating point for interpreting file}
  print_cnt: sys_int_machine_t;        {bytes left before print data}
  print_cnt_reset: sys_int_machine_t;  {value to reset PRINT_CNT to}
  retlen: sys_int_adr_t;               {number of bytes actually read}
  conn: file_conn_t;                   {connection handle to input file}
  c_p: c_p_t;                          {for filling in larger data types}
  start_p: c_p_t;                      {starting fill pointer}
  high_first: boolean;                 {TRUE if load high byte first}
  dp: sys_int_adr_t;                   {C_P increment}
  c: char;                             {scratch character}

  opt:                                 {command line option name}
    %include '/cognivision_links/dsee_libs/string/string32.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}

  stat: sys_err_t;                     {completion status code}
  msg_parm:                            {parameters to messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

label
  next_opt, done_opts, lop1, eof;

begin
  string_cmline_init;                  {init for parsing command line}
  string_cmline_token (fnam, stat);    {get input file name}
  string_cmline_req_check (stat);      {fine name argument is required}

  file_open_read_bin (fnam, '', conn, stat); {try to open binary input file for read}
  sys_msg_parm_vstr (msg_parm[1], fnam);
  sys_error_abort (stat, 'file', 'open_input_read_bin', msg_parm, 1);

  dp := 1;                             {init to high byte first}
  high_first := true;
{
*   Process the command line options.  Come back here each new command line
*   option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (                    {pick option name from list}
    opt,                               {option name}
    '-R',
    pick);                             {number of picked option}
  case pick of                         {do routine for specific option}
{
*   -R
}
1: begin
  high_first := false;
  dp := -1;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}
  goto next_opt;                       {back for next command line option}
done_opts:                             {done with all the command line options}
{
*   Main loop.  Come back here each new input buffer full to read.  One input
*   buffer full produces one output line.
}
lop1:
  file_read_bin (                      {get next block from input file}
    conn,                              {connection handle to input file}
    sizeof(ibuf),                      {max amount of data to read}
    ibuf,                              {buffer where to put the data}
    retlen,                            {amount of data actually read}
    stat);                             {completion status code}
  discard( file_eof_partial(stat) );   {OK to read partial record before end of file}
  if file_eof(stat) then goto eof;     {hit end of input file ?}
  sys_error_abort (stat, 'file', 'read_input_bin', nil, 0);
  ibuf_p := addr(ibuf);                {reset pointer to start of new data buffer}
{
*   Loop once thru all the characters in the input buffer and write their
*   octal representation to the output line buffer.
}
  obuf.len := 0;                       {init output line length}

  for i := 1 to sizeof(ibuf_p^) do begin {once for each possible character}
    if (i <> 1) and (i mod group_size = 1) then begin {start of a new group ?}
      string_append1 (obuf, ' ');      {extra space separator between groups}
      end;
    if i > retlen then begin           {past what we really read in ?}
      string_appendn (obuf, '   ', 3); {write blanks instead of hex number}
      next;
      end;
    string_f_int_max_base (            {make 2 digit hex number in S}
      s,                               {string to put number in}
      ord(ibuf_p^[i]),                 {input value}
      16,                              {number base}
      2,                               {we always want 2 characters}
      [string_fi_leadz_k, string_fi_unsig_k], {make leading 0, number is unsigned}
      stat);
    sys_error_abort (stat, '', '', nil, 0);
    string_append (obuf, s);           {add hex number to output line}
    string_append1 (obuf, ' ');        {add in separating space}
    end;                               {back and do next input byte}
{
*   Write out data as 4 16 bit integers.
}
  if high_first
    then begin                         {fill from high to low byte}
      start_p := univ_ptr(addr(i16));
      end
    else begin                         {fill from low to high byte}
      start_p := univ_ptr(sys_int_adr_t(addr(i16)) + 1);
      end
    ;
  c_p := start_p;                      {init where to put first byte}
  print_cnt_reset := 2;
  print_cnt := print_cnt_reset;        {number of bytes to go before print next}
  for i := 1 to sizeof(ibuf_p^) do begin {once for each posible character}
    if i <= retlen then begin          {this input byte exists ?}
      c_p^ := ibuf_p^[i];
      c_p := univ_ptr(sys_int_adr_t(c_p) + dp); {advance placement pointer}
      end;
    print_cnt := print_cnt - 1;        {one less input byte before print}
    if print_cnt <= 0 then begin       {time to print data ?}
      if i > retlen
        then begin                     {data didn't exist for this value}
          string_appendn (obuf, '      ', 6);
          end
        else begin                     {data did exist for this value}
          im := i16;                   {into format for number conversion}
          string_f_intrj (s, im, 6, stat);
          sys_error_abort (stat, '', '', nil, 0);
          string_append (obuf, s);
          c_p := start_p;
          print_cnt := print_cnt_reset;
          end
        ;
      end;                             {done printing data value}
    end;                               {back for next input character}
{
*   Write out data as 2 32 bit integers.
}
  string_appendn (obuf, ' ', 1);       {separator from previous data type}
  if high_first
    then begin                         {fill from high to low byte}
      start_p := univ_ptr(addr(i32));
      end
    else begin                         {fill from low to high byte}
      start_p := univ_ptr(sys_int_adr_t(addr(i32)) + 3);
      end
    ;
  c_p := start_p;                      {init where to put first byte}
  print_cnt_reset := 4;
  print_cnt := print_cnt_reset;        {number of bytes to go before print next}
  for i := 1 to sizeof(ibuf_p^) do begin {once for each posible character}
    if i <= retlen then begin          {this input byte exists ?}
      c_p^ := ibuf_p^[i];
      c_p := univ_ptr(sys_int_adr_t(c_p) + dp); {advance placement pointer}
      end;
    print_cnt := print_cnt - 1;        {one less input byte before print}
    if print_cnt <= 0 then begin       {time to print data ?}
      if i > retlen
        then begin                     {data didn't exist for this value}
          string_appendn (obuf, '           ', 11);
          end
        else begin                     {data did exist for this value}
          im := i32;                   {into format for number conversion}
          string_f_intrj (s, im, 11, stat);
          sys_error_abort (stat, '', '', nil, 0);
          string_append (obuf, s);
          c_p := start_p;
          print_cnt := print_cnt_reset;
          end
        ;
      end;                             {done printing data value}
    end;                               {back for next input character}
{
*   Write out data as 2 32 bit floating point numbers.
}
  string_appendn (obuf, ' ', 1);       {separator from previous data type}
  if high_first
    then begin                         {fill from high to low byte}
      start_p := univ_ptr(addr(r32));
      end
    else begin                         {fill from low to high byte}
      start_p := univ_ptr(sys_int_adr_t(addr(r32)) + 3);
      end
    ;
  c_p := start_p;                      {init where to put first byte}
  print_cnt_reset := 4;
  print_cnt := print_cnt_reset;        {number of bytes to go before print next}
  for i := 1 to sizeof(ibuf_p^) do begin {once for each posible character}
    if i <= retlen then begin          {this input byte exists ?}
      c_p^ := ibuf_p^[i];
      c_p := univ_ptr(sys_int_adr_t(c_p) + dp); {advance placement pointer}
      end;
    print_cnt := print_cnt - 1;        {one less input byte before print}
    if print_cnt <= 0 then begin       {time to print data ?}
      if i > retlen
        then begin                     {data didn't exist for this value}
          string_appendn (obuf, '           ', 11);
          end
        else begin                     {data did exist for this value}
          string_f_fp (                {try fixed point first}
            s,                         {output string}
            r32,                       {input floating point number}
            10,                        {total field width}
            0,                         {free format exponent, not used}
            0,                         {min required significant digits}
            10,                        {max allowed digits left of point}
            4,                         {min required digits right of point}
            10,                        {max allowed digits right of point}
            [string_ffp_exp_no_k],     {exponential notation not allowed}
            stat);
          if sys_error(stat) then begin {fixed point didn't work, try exp notation}
            string_f_fp (
              s,                       {output string}
              r32,                     {input floating point number}
              10,                      {total field width}
              0,                       {free format exponent}
              5,                       {min required significant digits}
              0,                       {max allowed digits left of point, unused}
              0,                       {min required digits right of point, unused}
              0,                       {max allowed digits right of point, unused}
              [ string_ffp_exp_k,      {force use of exponential notation}
                string_ffp_exp_eng_k], {use engineering notation}
              stat);
            sys_error_abort (stat, '', '', nil, 0);
            end;
          string_append (obuf, s);
          string_append1 (obuf, ' ');
          c_p := start_p;
          print_cnt := print_cnt_reset;
          end
        ;
      end;                             {done printing data value}
    end;                               {back for next input character}
{
*   Loop thru all the input bytes again and this time try to write out
*   the most reasonable ASCII representation.  Everything will guarantee
*   to cause a printable character or characters.
}
  string_appendn (obuf, ' ', 1);       {separator from previous data type}
  for i := 1 to retlen do begin        {thru all the bytes actually read in}
    c := chr(ord(ibuf_p^[i]) & 8#177); {make copy of byte with parity bit off}
    if (c >= ' ') and (c <= '~')
      then begin                       {this is a printable character}
        s.str[1] := c;
        s.len := 1;
        end
      else begin                       {non-printable character}
        s.str := '--';                 {init what we will print}
        s.len := 2;
        if ord(c) = 8#012 then s.str:='LF'; {line feed ?}
        if ord(c) = 8#014 then s.str:='FF'; {form feed ?}
        if ord(c) = 8#015 then s.str:='CR'; {carriage return ?}
        end
      ;
    string_appendn (obuf, '   ', 3-s.len); {leading blanks}
    string_append (obuf, s);           {add character name to output buffer}
    end;                               {back and do next input byte}

  writeln (obuf.str:obuf.len);         {write output line}
  goto lop1;                           {back for next input buffer full}
{
*   End of input file encountered.
}
eof:
  writeln ('End of file.');
  file_close (conn);                   {close input file}
  end.
