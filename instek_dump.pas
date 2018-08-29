{   Program INSTEK_DUMP [options]
*
*   Dump the data from a Instek GDS-800 series oscilloscope to a CSV file.
}
program instek_dump;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

const
  maxpoints = 1000;                    {max possible points per channel data}
  max_msg_args = 2;                    {max arguments we can pass to a message}

  lastpoint = maxpoints - 1;           {index of last channel data word}

type
  chan_t = array [0 .. lastpoint] of real; {captured data of one scope channel, volts}

  oform_k_t = (                        {output file format}
   oform_csv_k,                        {.CSV (comma separated values)}
   oform_sl_k);                        {.INS.SL file for SLIDE program}

var
  fnam_out:                            {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  sio: sys_int_machine_t;              {1-N number of serial line to use}
  conn: file_conn_t;                   {connection to scope}
  secsamp: real;                       {seconds per sample}
  sec0: real;                          {time at sample 0}
  timescale: real;                     {time multiplier for output file}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  u, v: real;                          {scratch floating point}
  oname_set: boolean;                  {TRUE if the output file name already set}
  nchan1, nchan2: sys_int_machine_t;   {number of data points in CHAN1 and CHAN2}
  nchan: sys_int_machine_t;            {number of data points per enabled channel}
  chan1: chan_t;                       {channel 1 data}
  chan2: chan_t;                       {channel 2 data}
  csv: csv_out_t;                      {CSV file writing state}
  chan: sys_int_machine_t;             {1-N channel to write to single channel output files}
  oform: oform_k_t;                    {output file format ID}
  cont: boolean;                       {output line has content}
  tk:                                  {scratch token}
    %include '(cog)lib/string32.ins.pas';

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
*   Subroutine SEND (VSTR)
*
*   Send the string in VSTR as one command line to the scope.  The end of line
*   terminator will be automatically added.
}
procedure send (                       {send command string to scope}
  in      vstr: univ string_var_arg_t); {the string to send, terminator will be added}
  val_param;

var
  stat: sys_err_t;                     {completion status}

begin
  file_write_sio_rec (vstr, conn, stat); {send the string plus end of line terminator}
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
********************************************************************************
*
*   Subroutine SENDSTR (STR)
*
*   Send the Pascal string STR followed by a line terminator to the scope.
*   Trailing blanks in STR are ignored.  All characters of STR starting with the
*   first 0 character, if any, are ignored.
}
procedure sendstr (                    {send string to scope}
  in      str: string);                {the string to send, terminator will be added}
  val_param;

var
  vstr: string_var132_t;               {var string copy of STR}

begin
  vstr.max := size_char(vstr.str);     {init local var string}

  string_vstring (vstr, str, size_char(str)); {make var string from the input string}
  send (vstr);                         {send the var string}
  end;
{
********************************************************************************
*
*   Function IBYTE
*
*   Returns the next input byte from the scope.  This routine waits indefinitely
*   for a input byte to be available.
}
function ibyte                         {return next input byte from scope}
  :sys_int_machine_t;                  {0-255 byte value}

var
  buf: string_var4_t;                  {input buffer}
  stat: sys_err_t;                     {completion status}

begin
  buf.max := 1;                        {indicate number of bytes to read}
  file_read_sio_rec (conn, buf, stat); {read the next byte}
  sys_error_abort (stat, '', '', nil, 0);
  ibyte := ord(buf.str[1]);            {return the byte}
  end;
{
********************************************************************************
*
*   Subroutine GETSTR (S)
*
*   Get the next terminated response line fromt the scope.
}
procedure getstr (                     {get terminated string from scope}
  in out  s: univ string_var_arg_t);   {returned string, not including EOL}
  val_param;

var
  b: sys_int_machine_t;                {input byte value}

begin
  s.len := 0;                          {init returned string to empty}

  while true do begin                  {loop until line terminator encountered}
    b := ibyte;                        {get the next input byte}
    if b = 10 then return;             {end of line terminator ?}
    string_append1 (s, chr(b));        {append this character to end of return string}
    end;
  end;
{
********************************************************************************
*
*   Subroutine READ_CHANNEL (CHAN, DAT, NDAT, RATE)
*
*   Read the captured data for channel CHAN from the scope into DAT.  DAT is
*   assumed to be able to hold MAXPOINTS points.  NDAT is returned the number of
*   points read into DAT.  RATE is the sample rate as reported by the scope.
}
procedure read_channel (               {read captured data for a channel from scope}
  in      chan: sys_int_machine_t;     {1-N number of scope channel to read}
  out     dat: chan_t;                 {returned captured channel data}
  out     ndat: sys_int_machine_t;     {returned number of points read into DAT}
  out     rate: real);                 {sample rate}
  val_param;

var
  s: string_var80_t;                   {scratch string}
  tk: string_var32_t;                  {scratch token}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  n: sys_int_machine_t;                {scratch integer}
  j: integer16;                        {16 bit signed data value}
  i32: sys_int_conv32_t;               {32 bit integer for floating point conversion}
  r: real;                             {scratch floating point}
  vunit: real;                         {volts/unit of raw data value}
  stat: sys_err_t;                     {completion status}

begin
  tk.max := size_char(tk.str);         {init local var strings}
  s.max := size_char(s.str);
{
*   Find the horizontal scale.  We get 25 samples per division.
}
  s.len := 0;                          {send :CHANx:SCAL? command}
  string_appends (s, ':CHAN'(0));
  string_f_int (tk, chan);
  string_append (s, tk);
  string_appends (s, ':SCAL?'(0));
  send (s);

  getstr (s);                          {get text vols/division}
  string_t_fpm (s, r, stat);           {convert to floating point in R}
  sys_error_abort (stat, '', '', nil, 0);
  vunit := r / 25.0;                   {volts per unit data value}
{
*   Send the command to request the channel data.
}
  s.len := 0;                          {build command string}
  string_appends (s, ':ACQ'(0));
  string_f_int (tk, chan);
  string_append (s, tk);
  string_appends (s, ':POIN'(0));
  send (s);                            {send the command}
{
*   Read channel data indicator.
}
  if ibyte <> ord('#') then begin
    writeln ('Channel data not started with "#" as expected.');
    sys_bomb;
    end;
{
*   Read digit that indicates how many data length digits follow.
}
  tk.str[1] := chr(ibyte);             {get data length size digit}
  tk.len := 1;
  string_t_int (tk, n, stat);          {convert to integer}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Read the data length digits.
}
  tk.len := 0;
  for i := 1 to n do begin             {once for each data length digit}
    string_append1 (tk, chr(ibyte));
    end;
  string_t_int (tk, n, stat);          {convert data size to integer in N}
  sys_error_abort (stat, '', '', nil, 0);

  n := n - 8;                          {make number of data bytes to read}
  n := n div 2;                        {make number of data words to read}
  if n > maxpoints then begin
    writeln ('More data points per channel than array is configured for.');
    writeln (n, ' data points, but array only configured for ', maxpoints, '.');
    sys_bomb;
    end;
{
*   Read sample rate.  This is a 32 bit floating point value in IEEE format
*   sent in most to least significant byte order.  Despite what the
*   documentation says, this is not the sample rate but the
*   seconds/division.
}
  i32 := lshft(ibyte, 24);             {assemble the 32 bit value in I32}
  i32 := i32 ! lshft(ibyte, 16);
  i32 := i32 ! lshft(ibyte, 8);
  i32 := i32 ! ibyte;
  rate := real(i32);                   {copy into floating point variable}
{
*   Read channel number byte.
}
  i := ibyte;
  if i <> chan then begin              {not the expected channel ?}
    writeln ('Received data for channel ', i, ', expected channel ', chan, '.');
    sys_bomb;
    end;
{
*   Read the number of data bytes that follow.  This is a 24 bit binary value
*   sent in most to least significant byte order.
}
  i32 := lshft(ibyte, 16);             {assemble the 24 bit value in I32}
  i32 := i32 ! lshft(ibyte, 8);
  i32 := i32 ! ibyte;

  i32 := i32 div 2;                    {make number of 16 bit data words}
  if i32 <> n then begin
    writeln ('Data size indicates ', n, ' words, but waveform data size ', i32, '.');
    sys_bomb;
    end;
{
*   Read the waveform data.  Each data point is sent as 16 bit binary, high byte
*   first.
}
  ndat := n;                           {pass back number of data points}
  n := n - 1;                          {make index of last data point}
  for i := 0 to n do begin             {once for each data point}
    j := lshft(ibyte, 8);              {assemble this data value}
    j := j ! ibyte;

    dat[i] := j * vunit;               {write this data point to returned array}
    end;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize our state before reading the command line options.
}
  string_cmline_init;                  {init for reading the command line}
  sio := 1;                            {default serial line number}
  oname_set := false;                  {init to output file name not set}
  oform := oform_csv_k;                {default to .CSV output file type}
  chan := 0;                           {default to first channel for 1-chan output files}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not oname_set then begin        {output file name not set yet ?}
      string_copy (opt, fnam_out);     {set output file name}
      oname_set := true;               {output file name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-OUT -SIO -SL -CHAN',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -OUT filename
}
1: begin
  if oname_set then begin              {output file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (fnam_out, stat);
  oname_set := true;
  end;
{
*   -SIO n
}
2: begin
  string_cmline_token_int (sio, stat);
  end;
{
*   -SL
}
3: begin
  oform := oform_sl_k;
  end;
{
*   -CHAN n
}
4: begin
  string_cmline_token_int (chan, stat);
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
*   Done reading the command line options.
}
  file_open_sio (                      {open connection to the scope via serial line}
    sio,                               {number of the serial line to use}
    file_baud_38400_k,                 {baud rate}
    [],                                {no flow control, no parity}
    conn,                              {returned I/O connection}
    stat);
  file_sio_set_eor_write (conn, ''(10), 1); {send LF at end of lines}
  file_sio_set_eor_read (conn, '', 0); {no special EOL interpretation on reading}

  nchan1 := 0;                         {init to no channel data read}
  nchan2 := 0;
{
*   Read channel 1 if enabled.
}
  sendstr (':CHAN1:DISP?');
  getstr (parm);
  string_t_int (parm, i, stat);
  sys_error_abort (stat, '', '', nil, 0);
  if i <> 0 then begin
    read_channel (1, chan1, nchan1, u);
    end;
{
*   Read channel 2 if enabled.
}
  sendstr (':CHAN2:DISP?');
  getstr (parm);
  string_t_int (parm, i, stat);
  sys_error_abort (stat, '', '', nil, 0);
  if i <> 0 then begin
    read_channel (2, chan2, nchan2, v);
    if nchan1 <> 0 then begin          {read data from both channels ?}
      if nchan1 <> nchan2 then begin
        writeln ('Not same number of data points for each channel.');
        sys_bomb;
        end;
      if u <> v then begin
        writeln ('Not same time scale for each channel.');
        sys_bomb;
        end;
      end;
    end;
  nchan := max(nchan1, nchan2);

  if nchan <= 0 then begin
    writeln ('No channel enabled.');
    sys_bomb;
    end;
{
*   Find the time scale.  It has already been checked that both channels have
*   the same time scale and number of samples.
}
  sendstr (':TIM:SCAL?');
  getstr (parm);                       {get seconds/division}
  string_t_fpm (parm, secsamp, stat);  {convert to floating point in SECSAMP}
  sys_error_abort (stat, '', '', nil, 0);
  secsamp := secsamp / 25.0;           {make seconds/sample}

  sendstr (':TIM:DEL?');
  getstr (parm);                       {get trigger time relative to screen center}
  string_t_fpm (parm, sec0, stat);     {convert to floating point in SEC0}
  sys_error_abort (stat, '', '', nil, 0);
  sec0 := sec0 - (secsamp * 250.0);    {make time at sample 0}

  file_close (conn);                   {close connection to the scope}
{
*   Write the output file.
}
  if not oname_set then begin          {output file name not specified on command line ?}
    string_vstring (fnam_out, 'scope'(0), -1); {set to default}
    end;

  case oform of                        {what is the output file format ?}
oform_csv_k: begin                     {CSV output file}
      csv_out_open (fnam_out, csv, stat); {open the CSV output file}
      sys_error_abort (stat, '', '', nil, 0);
      end;
oform_sl_k: begin                      {include file for slide making program}
      file_open_write_text (fnam_out, '.ins.sl', conn, stat);
      sys_error_abort (stat, '', '', nil, 0);
      end;
otherwise
    writeln ('INTERNAL ERROR: Unexpected value of OFORM on open output file.');
    sys_bomb;
    end;

  timescale := 1.0;                    {init time scale to units of seconds}
  string_vstring (parm, 'Seconds'(0), -1);

  u := sec0 * timescale;               {scaled starting time}
  v := (sec0 + (nchan - 1) * secsamp) * timescale; {scaled ending time}
  if (abs(u) < 1.0) and (abs(v) < 1.0) then begin
    timescale := timescale * 1000.0;
    string_vstring (parm, 'Milliseconds'(0), -1);
    end;

  u := sec0 * timescale;               {scaled starting time}
  v := (sec0 + (nchan - 1) * secsamp) * timescale; {scaled ending time}
  if (abs(u) < 1.0) and (abs(v) < 1.0) then begin
    timescale := timescale * 1000.0;
    string_vstring (parm, 'Microseconds'(0), -1);
    end;

  u := sec0 * timescale;               {scaled starting time}
  v := (sec0 + (nchan - 1) * secsamp) * timescale; {scaled ending time}
  if (abs(u) < 1.0) and (abs(v) < 1.0) then begin
    timescale := timescale * 1000.0;
    string_vstring (parm, 'Nanoseconds'(0), -1);
    end;
{
*   Write output file header as apporpriate for the output file format.
*   U and V are the starting and ending times and PARM is the text lable for
*   the time scale.
}
  if chan = 0 then begin               {specific channel not chosen yet ?}
    if nchan2 > 0 then chan := 2;
    if nchan1 > 0 then chan := 1;
    end;

  case oform of

oform_csv_k: begin                     {CSV output file}
      csv_out_vstr (csv, parm, stat);  {write CSV header line}
      sys_error_abort (stat, '', '', nil, 0);
      if nchan1 > 0 then begin
        csv_out_str (csv, 'Chan 1 volts', stat);
        sys_error_abort (stat, '', '', nil, 0);
        end;
      if nchan2 > 0 then begin
        csv_out_str (csv, 'Chan 2 volts', stat);
        sys_error_abort (stat, '', '', nil, 0);
        end;
      csv_out_line (csv, stat);
      sys_error_abort (stat, '', '', nil, 0);
      end;

oform_sl_k: begin                      {SLIDE program include file}
      string_vstring (opt, '*   X: '(0), -1);
      string_f_fp_free (tk, u, 3);
      string_append (opt, tk);
      string_appends (opt, ' to '(0));
      string_f_fp_free (tk, v, 3);
      string_append (opt, tk);
      string_appends (opt, ' range '(0));
      string_f_fp_free (tk, v - u, 3);
      string_append (opt, tk);
      string_append1 (opt, ' ');
      string_append (opt, parm);
      file_write_text (opt, conn, stat);
      sys_error_abort (stat, '', '', nil, 0);

      string_vstring (opt, '*'(0), -1);
      file_write_text (opt, conn, stat);
      sys_error_abort (stat, '', '', nil, 0);
      end;

    end;                               {end of output format cases}

  for i := 0 to nchan-1 do begin       {once for each data point}
    u := ((i * secsamp) + sec0) * timescale;
    case oform of

oform_csv_k: begin                     {CSV output file}
  csv_out_fp_free (csv, u, 6, stat);
  sys_error_abort (stat, '', '', nil, 0);
  if nchan1 > 0 then begin
    v := chan1[i];
    csv_out_fp_free (csv, v, 6, stat);
    sys_error_abort (stat, '', '', nil, 0);
    end;
  if nchan2 > 0 then begin
    v := chan2[i];
    csv_out_fp_free (csv, v, 6, stat);
    sys_error_abort (stat, '', '', nil, 0);
    end;
  csv_out_line (csv, stat);
  sys_error_abort (stat, '', '', nil, 0);
  end;                                 {end of CSV output type case}

oform_sl_k: begin                      {.INS.SL output file type}
  if i = 0
    then string_vstring (parm, 'move '(0), -1)
    else string_vstring (parm, 'draw '(0), -1);
  string_f_fp_free (opt, u, 6);
  string_append (parm, opt);
  cont := false;                       {init to no content this output line}
  case chan of
1:  begin
      v := chan1[i];
      cont := true;
      end;
2:  begin
      v := chan2[i];
      cont := true;
      end;
    end;
  if cont then begin
    string_append1 (parm, ' ');
    string_f_fp_free (opt, v, 6);
    string_append (parm, opt);
    file_write_text (parm, conn, stat);
    sys_error_abort (stat, '', '', nil, 0);
    end;
  end;                                 {end of .INS.SL output file type}

      end;                             {end of output file type cases}
    end;                               {back to next data point}

  case oform of
oform_csv_k: begin
      csv_out_close (csv, stat);
      csv_out_line (csv, stat);
      end;
oform_sl_k: begin
      file_close (conn);
      end;
    end;
  end.
