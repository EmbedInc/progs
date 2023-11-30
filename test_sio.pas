{   Program TEST_SIO [options]
}
program test_sio;
%include 'base.ins.pas';

const
  def_baud_k = file_baud_115200_k;     {default baud rate}
  tbreak = 0.5;                        {time for break in received stream, seconds}
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  sio: sys_int_machine_t;              {number of system serial line to use}
  baud: file_baud_k_t;                 {serial line baud rate ID}
  conn: file_conn_t;                   {connection to the system serial line}
  wrlock: sys_sys_threadlock_t;        {lock for writing to standard output}
  thid_brk: sys_sys_thread_id_t;       {ID of thread to show time breaks}
  thid_in: sys_sys_thread_id_t;        {ID of low level serial line input thread}
  thid_send: sys_sys_thread_id_t;      {ID of output buffer sending thread}
  conf: file_sio_config_t;             {serial line configuration options}
  ev_recv: sys_sys_event_id_t;         {signalled when byte received and shown}
  ev_send: sys_sys_event_id_t;         {signalled when sending thread exits}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  prompt:                              {prompt string for entering command}
    %include '(cog)lib/string4.ins.pas';
  buf:                                 {one line command buffer}
    %include '(cog)lib/string8192.ins.pas';
  obuf:                                {output bytes data buffer}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {BUF parse index}
  quit: boolean;                       {TRUE when trying to exit the program}
  newline: boolean;                    {STDOUT stream is at start of new line}
  usb: boolean;                        {connection is over USB, not serial line}
  usbname:                             {specific name of USB device}
    %include '(cog)lib/string80.ins.pas';
  i1: sys_int_machine_t;               {integer command parameters}
  repout: boolean;                     {repeat output until users stops}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  done_test_sio, next_opt, err_parm, parm_bad, done_opts,
  loop_iline, loop_hex, tkline, loop_tk,
  done_cmd, err_cmparm, err_extra, leave;
{
****************************************************************************
*
*   Subroutine LOCKOUT
*
*   Acquire exclusive lock for writing to standard output.
}
procedure lockout;

begin
  sys_thread_lock_enter (wrlock);
  if not newline then writeln;         {start on a new line}
  newline := true;                     {init to STDOUT will be at start of line}
  end;
{
****************************************************************************
*
*   Subroutine UNLOCKOUT
*
*   Release exclusive lock for writing to standard output.
}
procedure unlockout;

begin
  sys_thread_lock_leave (wrlock);
  end;
{
****************************************************************************
*
*   Subroutine WHEX (B)
*
*   Write the byte value in the low 8 bits of B as two hexadecimal digits
*   to standard output.
}
procedure whex (                       {write hex byte to standard output}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  tk: string_var16_t;                  {hex string}
  stat: sys_err_t;

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_f_int_max_base (              {make the hex string}
    tk,                                {output string}
    b & 255,                           {input integer}
    16,                                {radix}
    2,                                 {field width}
    [ string_fi_leadz_k,               {pad field on left with leading zeros}
      string_fi_unsig_k],              {the input integer is unsigned}
    stat);
  write (tk.str:tk.len);               {write the string to standard output}
  end;
{
****************************************************************************
*
*   Subroutine WDEC (B)
*
*   Write the byte value in the low 8 bits of B as an unsigned decimal
*   integer to standard output.  Exactly 3 characters are written with
*   leading zeros as blanks.
}
procedure wdec (                       {write byte to standard output in decimal}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  tk: string_var16_t;                  {hex string}
  stat: sys_err_t;

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_f_int_max_base (              {make the hex string}
    tk,                                {output string}
    b & 255,                           {input integer}
    10,                                {radix}
    3,                                 {field width}
    [string_fi_unsig_k],               {the input integer is unsigned}
    stat);
  write (tk.str:tk.len);               {write the string to standard output}
  end;
{
****************************************************************************
*
*   Subroutine WPRT (B)
*
*   Show the byte value in the low 8 bits of B as a character, if it is
*   a valid character code.  If not, write a description of the code.
}
procedure wprt (                       {show printable character to standard output}
  in      b: sys_int_machine_t);       {byte value in low 8 bits}
  val_param; internal;

var
  c: sys_int_machine_t;                {character code}

begin
  c := b & 255;                        {extract the character code}

  case c of                            {check for a few special handling cases}
0: write ('NULL');
7: write ('^G bell');
10: write ('^J LF');
13: write ('^M CR');
17: write ('^Q Xon');
19: write ('^S Xoff');
27: write ('Esc');
32: write ('SP');
127: write ('DEL');
otherwise
    if c >= 33 then begin              {printable character ?}
      write (chr(c));                  {let system display the character directly}
      return;
      end;
    if (c >= 1) and (c <= 26) then begin {CTRL-letter ?}
      write ('^', chr(c+64));
      return;
      end;
    end;                               {end of special handling cases}
  end;
{
****************************************************************************
*
*   Subroutine THREAD_BREAK (ARG)
*
*   This routine is run in a separate thread.  It writes a single blank line
*   to the output whenever there is a break longer than TBREAK seconds in
*   the received byte stream.
*
*   When the receiving thread gets and shows a byte, it notifies the EV_RECV
*   event.  This thread waits on the EV_RECV event or a timeout.  If the
*   timeout is reached, then there was a break in the received byte stream.
}
procedure thread_break (               {write blanks at receive breaks}
  in      arg: sys_int_adr_t);         {unused argument}
  val_param; internal;

var
  recv: boolean;                       {a byte was received since last break}
  stat: sys_err_t;

begin
  recv := false;                       {init to no byte received since break}

  while true do begin                  {infinite loop}
    if sys_event_wait_tout (ev_recv, tbreak, stat)
      then begin                       {timeout, break detected}
        if recv then begin             {new stuff written since last break ?}
          lockout;
          writeln;                     {write a blank line to show the break}
          unlockout;
          recv := false;               {reset to no new byte since break}
          end;
        end
      else begin                       {no timeout, a byte was received}
        recv := true;                  {byte received since last break}
        end
      ;
    if quit then begin                 {trying to exit the program ?}
      sys_thread_exit;
      end;
    end;                               {loop back}

  end;
{
****************************************************************************
*
*   Subroutine THREAD_SEND (ARG)
*
*   Send the bytes in OBUF.  The sending is repeated as long as REPOUT is
*   TRUE.  The contents of OBUF is always sent at least once.  This thread
*   exits when done sending.
}
procedure thread_send (                {send bytes in OBUF, repeat on REPOUT}
  in      arg: sys_int_adr_t);         {unused argument}
  val_param; internal;

label
  loop;

begin
  if obuf.len <= 0 then return;        {buffer is empty, nothing to do ?}

loop:                                  {back here to repeat sending buffer}
  if usb
    then begin                         {connected via USB}
      file_write_embusb (              {write the bytes in OBUF}
        obuf.str,                      {the data bytes to write}
        conn,                          {connection to the device}
        obuf.len,                      {number of bytes to write}
        stat);
      end
    else begin                         {connected via serial line}
      file_write_sio_rec (obuf, conn, stat); {send the data bytes}
      end
    ;
  if sys_error(stat) then begin        {error on sending ?}
    lockout;
    sys_error_print (stat, '', '', nil, 0);
    unlockout;
    return;
    end;

  if repout then goto loop;            {keep repeating the output ?}
  end;
{
****************************************************************************
*
*   Subroutine THREAD_IN (ARG)
*
*   This routine is run in a separate thread.  It reads data bytes
*   from the serial port and writes information about the received
*   data to standard output.
}
procedure thread_in (                  {get data bytes from serial line}
  in      arg: sys_int_adr_t);         {unused argument}
  val_param; internal;

var
  b: sys_int_machine_t;                {data byte value}
  tk: string_var32_t;                  {scratch token}

label
  loop;
{
******************************
*
*   Local function IBYTE
*
*   Return the next byte from the serial line.
}
function ibyte                         {return next byte from remote system}
  :sys_int_machine_t;                  {0-255 byte value}

var
  buf: string_var4_t;                  {raw bytes input buffer}
  olen: sys_int_adr_t;                 {number of bytes actually received}
  stat: sys_err_t;                     {completion status}

begin
  buf.max := 1;                        {allow only single byte to be read at a time}

  if usb
    then begin                         {connected via USB}
      file_read_embusb (               {read next byte from USB device}
        conn,                          {connection to the device}
        buf.max,                       {maximum number of bytes to read}
        buf.str,                       {buffer to receive the byte into}
        olen,                          {number of bytes actually received}
        stat);
      end
    else begin                         {connected via serial line}
      file_read_sio_rec (conn, buf, stat); {read next byte from serial line}
      end
    ;
  if quit then begin                   {trying to exit the program ?}
    sys_thread_exit;
    end;
  sys_error_abort (stat, '', '', nil, 0);

  ibyte := ord(buf.str[1]);
  end;
{
******************************
*
*   Executable code for subroutine THREAD_IN.
}
begin
  tk.max := size_char(tk.str);         {init local var string}

loop:                                  {back here each new response opcode}
  b := ibyte;                          {get response opcode byte}
  sys_event_notify_bool (ev_recv);     {indicate a byte was received}

  lockout;                             {acquire exclusive lock on standard output}
  whex (b);                            {show byte value in HEX}
  write (' ');
  wdec (b);                            {show byte value in decimal}
  write (' ');
  wprt (b);                            {show printable character, if possible}
  writeln;
  unlockout;

  goto loop;                           {back to read next byte from serial line}
  end;
{
****************************************************************************
*
*   Subroutine CONNECT_SIO
*
*   Connect to the remote device over a serial line.
}
procedure connect_sio;
  val_param; internal;

begin
  file_open_sio (                      {open connection to the serial line}
    sio,                               {number of serial line to use}
    baud,                              {baud rate ID}
    conf,                              {additional configuration options}
    conn,                              {returned connection to the serial line}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  file_sio_set_eor_read (conn, '', 0); {no special input end of record sequence}
  file_sio_set_eor_write (conn, '', 0); {no special output end of record sequence}

  usb := false;                        {indicate not connected via USB}
  end;
{
****************************************************************************
*
*   Subroutine CONNECT_USB
*
*   Connect to the remote device via USB.
}
procedure connect_usb;
  val_param; internal;

var
  list: file_usbdev_list_t;            {list of Embed USB devices}
  dev_p: file_usbdev_p_t;              {pointer to current USB devices list entry}
  stat: sys_err_t;                     {completion status}

begin
  if usbname.len > 0                   {connect to a specific USB device ?}
{
*   Check for connecting to a specific USB device.  In this case, it can be
*   any Embed USB device.
}
    then begin
      file_embusb_list_get (           {get list of all Embed USB devices}
        0,                             {allow any VID/PID}
        util_top_mem_context,          {parent memory context to create list within}
        list,                          {the returned list}
        stat);
      sys_error_abort (stat, '', '', nil, 0);

      dev_p := list.list_p;            {point to first device in list}
      while true do begin              {look for the specific device in the list}
        if dev_p = nil then begin      {exhausted the list ?}
          writeln ('Embed USB device "', usbname.str:usbname.len, '" not found.');
          sys_bomb;
          end;
        if string_equal (dev_p^.name, usbname) then exit; {found matching device ?}
        dev_p := dev_p^.next_p;        {advance to next list entry}
        end;                           {back to check this new list entry}

      file_open_embusb (               {open connection to the USB device}
        dev_p^.vidpid,                 {VID/PID of the device}
        dev_p^.name,                   {Embed USB device name}
        conn,                          {returned connection to the device}
        stat);
      sys_error_abort (stat, '', '', nil, 0);

      file_usbdev_list_del (list);     {deallocate the USB devices list}
      end                              {end of specific name case}
{
*   No specific name was given.  Connect to any Embed 10 USB device.
}
    else begin
      file_open_embusb (               {open connection to the USB device}
        file_usbid (5824, 1489),       {VID/PID of Embed USB device 10}
        usbname,                       {name, is blank, allow any}
        conn,                          {returned connection to the device}
        stat);
      sys_error_abort (stat, '', '', nil, 0);
      end                              {end of no specific name case}
    ;

  usb := true;                         {indicate connected via USB}
  end;
{
****************************************************************************
*
*   Start of main routine.
}
begin
{
*   Initialize our state before reading the command line options.
}
  string_cmline_init;                  {init for reading the command line}
  baud := def_baud_k;                  {init to default baud rate}
  conf := [];                          {init configuration options to default}
  usb := false;                        {init to using serial line, not USB}
  sio := 1;                            {init to default serial line number}

  sys_envvar_get (string_v('SIO_DEFAULT'), parm, stat);
  if not sys_error(stat) then begin
    string_t_int (parm, ii, stat);
    if not sys_error(stat) then begin
      sio := ii;
      end;
    end;

  sys_envvar_get (string_v('TEST_SIO'), parm, stat);
  if sys_error(stat) then goto done_test_sio;
  string_t_int (parm, ii, stat);
  if not sys_error(stat) then begin
    sio := ii;
    goto done_test_sio;
    end;
  p := 1;                              {init parse index}
  string_token (parm, p, opt, stat);   {extract first token of TEST_SIO string}
  if sys_error(stat) then goto done_test_sio;
  string_upcase (opt);
  string_tkpick80 (opt, 'USB', pick);  {pick keyword from list}
  case pick of                         {which keyword is it ?}
1:  begin                              {USB [name]}
      string_token (parm, p, opt, stat); {try to get optional name string}
      if string_eos(stat) then opt.len := 0; {indicate no specific name given}
      if sys_error(stat) then goto done_test_sio; {abort on hard error}
      string_copy (opt, usbname);      {save name of USB device}
      string_token (parm, p, opt, stat); {try to get additional token ?}
      if not string_eos(stat) then begin {too many parameters}
        writeln ('Too many parameters to USB command in TEST_SIO env var.');
        sys_bomb;
        end;
      usb := true;                     {indicate to connect to USB device}
      end;                             {end of "USB [name]" case}
    end;                               {end of TEST_SIO keyword cases}
done_test_sio:
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-SIO -BAUD -XF -HWF -PARO -PARE -USB',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -SIO n
}
1: begin
  usb := false;
  string_cmline_token_int (sio, stat);
  end;
{
*   -BAUD baudrate
}
2: begin
  string_cmline_token_int (i1, stat);
  if sys_error(stat) then goto parm_bad;
  case i1 of
300: baud := file_baud_300_k;
1200: baud := file_baud_1200_k;
2400: baud := file_baud_2400_k;
4800: baud := file_baud_4800_k;
9600: baud := file_baud_9600_k;
19200: baud := file_baud_19200_k;
38400: baud := file_baud_38400_k;
57600: baud := file_baud_57600_k;
115200: baud := file_baud_115200_k;
153600: baud := file_baud_153600_k;
otherwise
    goto parm_bad;
    end;
  end;
{
*   -XF
*
*   Enable XON/XOFF flow control.
}
3: begin
  conf := conf + [file_sio_xonoff_send_k, file_sio_xonoff_obey_k];
  end;
{
*   -HWF
*
*   Enable hardware flow control.
}
4: begin
  conf := conf + [file_sio_rtscts_k];
  end;
{
*   -PARO
}
5: begin
  conf := conf - [file_sio_par_even_k];
  conf := conf + [file_sio_par_odd_k]
  end;
{
*   -PARE
}
6: begin
  conf := conf - [file_sio_par_odd_k];
  conf := conf + [file_sio_par_even_k]
  end;
{
*   -USB [name]
}
7: begin
  usb := true;                         {indicate to connect to USB device}
  string_cmline_token (opt, stat);     {get next command line token}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] = '-') then begin {next option, not name ?}
    string_cmline_reuse;               {put this command line option back}
    usbname.len := 0;                  {indicate no specific name given}
    goto next_opt;
    end;
  string_copy (opt, usbname);          {save specific name of USB device}
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
*
*   Open the connection to the device.
}
  if usb
    then begin
      connect_usb;
      end
    else begin
      connect_sio;
      end
    ;
{
*   Perform some system initialization.
}
  sys_thread_lock_create (wrlock, stat); {create interlock for writing to STDOUT}
  sys_error_abort (stat, '', '', nil, 0);

  quit := false;                       {init to not trying to exit the program}
  newline := true;                     {STDOUT is currently at start of new line}

  sys_event_create_bool (ev_recv);     {create event for byte received and shown}
  sys_thread_create (                  {start thread for handling gaps in received data}
    addr(thread_break),                {address of thread root routine}
    0,                                 {argument passed to thread (unused)}
    thid_brk,                          {returned thread ID}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  sys_thread_create (                  {start thread for reading serial line input}
    addr(thread_in),                   {address of thread root routine}
    0,                                 {argument passed to thread (unused)}
    thid_in,                           {returned thread ID}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
{
***************************************
*
*   Process user commands.
*
*   Initialize before command processing.
}
  string_vstring (prompt, ': '(0), -1); {set command prompt string}

loop_iline:                            {back here each new input line}
  sys_wait (0.100);
  lockout;
  string_prompt (prompt);              {prompt the user for a command}
  newline := false;                    {indicate STDOUT not at start of new line}
  unlockout;

  string_readin (buf);                 {get command from the user}
  newline := true;                     {STDOUT now at start of line}
  if buf.len <= 0 then goto loop_iline; {ignore blank lines}
  p := 1;                              {init BUF parse index}
  while buf.str[p] = ' ' do begin      {skip over spaces before new token}
    if p >= buf.len then goto loop_iline; {only blanks found, ignore line ?}
    p := p + 1;                        {skip over this blank}
    end;
  obuf.len := 0;                       {init to no bytes to send from this command}
  repout := false;                     {init to not repeat the output bytes}

  if (buf.str[p] = '''') or (buf.str[p] = '"') {quoted string ?}
    then goto tkline;                  {this line contains data tokens}

  string_token (buf, p, opt, stat);    {get command name token into OPT}
  if string_eos(stat) then goto loop_iline; {ignore line if no command found}
  if sys_error(stat) then goto err_cmparm;
  string_t_int (opt, i1, stat);        {try to convert integer}
  if not sys_error (stat) then goto tkline; {this line contains only data tokens ?}
  sys_error_none (stat);
  string_upcase (opt);
  string_tkpick80 (opt,                {pick command name from list}
    '? HELP Q S H SQ',
    pick);
  case pick of
{
*   HELP
}
1, 2: begin
  lockout;
  writeln;
  writeln ('? or HELP   - Show this list of commands');
  writeln ('Q           - Quit the program');
  writeln ('S chars     - Remaining characters sent as ASCII');
  writeln ('H hex ... hex - Data bytes, tokens interpreted in hexadecimal');
  writeln ('val ... val - Integer bytes or strings, strings must be quoted, "" or ''''');
  writeln ('SQ          - Emit square wave at 1/2 baud frequency');
  writeln ('Integer tokens have the format: [base#]value with decimal default.');
  unlockout;
  end;
{
*   Q
}
3: begin
  goto leave;
  end;
{
*   S chars
}
4: begin
  string_substr (buf, 3, buf.len, obuf);
  end;
{
*   H hexval ... hexval
}
5: begin
loop_hex:                              {back here each new hex value}
  string_token (buf, p, parm, stat);   {get the next token from the command line}
  if string_eos(stat) then goto done_cmd; {exhausted the command line ?}
  string_t_int32h (parm, i1, stat);    {convert this token to integer}
  if sys_error(stat) then goto err_cmparm;
  i1 := i1 & 255;                      {force into 8 bits}
  string_append1 (obuf, chr(i1));      {one more byte to send due to this command}
  goto loop_hex;                       {back to get next command line token}
  end;
{
*  SQ
}
6: begin
  string_token (buf, p, parm, stat);   {try to get a command parameter}
  if not string_eos(stat) then goto err_extra; {found parameter ?}

  string_append1 (obuf, chr(16#55));   {byte value to send}
  repout := true;                      {repeat the buffer contents until user stops}
  end;
{
*   Unrecognized command.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_parms ('string', 'err_command_bad', msg_parm, 1);
    goto loop_iline;
    end;
  goto done_cmd;                       {done handling this command}
{
*   The line contains data tokens.  Process each and add the resulting bytes to OBUF.
}
tkline:
  p := 1;                              {reset to parse position to start of line}

loop_tk:                               {back here to get each new data token}
  if p > buf.len then goto done_cmd;   {exhausted command line ?}
  while buf.str[p] = ' ' do begin      {skip over spaces before new token}
    if p >= buf.len then goto done_cmd; {nothing more left on this command line ?}
    p := p + 1;                        {skip over this blank}
    end;
  if (buf.str[p] = '"') or (buf.str[p] = '''') then begin {token is a quoted string ?}
    string_token (buf, p, parm, stat); {get resulting string into PARM}
    if sys_error(stat) then goto err_cmparm;
    string_append (obuf, buf);         {add string to bytes to send}
    goto loop_tk;                      {back to get next token}
    end;

  string_token (buf, p, parm, stat);   {get this token into PARM}
  if sys_error(stat) then goto err_cmparm;
  string_t_int (parm, i1, stat);       {convert token to integer}
  if sys_error(stat) then goto err_cmparm;
  i1 := i1 & 255;                      {keep only the low 8 bits}
  string_append1 (obuf, chr(i1));
  goto loop_tk;

done_cmd:                              {done processing the current command}
  if sys_error(stat) then goto err_cmparm; {handle error, if any}
  if obuf.len <= 0 then goto loop_iline; {nothing to send, back for next command ?}

  if repout then begin                 {repeat output until user stops ?}
    lockout;
    string_prompt (string_v('Press ENTER to stop output: '));
    newline := false;
    unlockout;
    end;
  sys_thread_create (                  {start thread to send OBUF contents}
    addr(thread_send),                 {address of thread root routine}
    0,                                 {argument passed to thread (unused)}
    thid_send,                         {returned thread ID}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  sys_thread_event_get (thid_send, ev_send, stat); {get thread exit event}
  sys_error_abort (stat, '', '', nil, 0);
  if repout then begin                 {repeating output until user stops ?}
    string_readin (parm);              {wait for user to hit ENTER}
    newline := true;
    repout := false;                   {stop the repeated sending}
    end;
  sys_event_wait (ev_send, stat);      {wait for sending thread to exit}
  sys_error_abort (stat, '', '', nil, 0);
  sys_event_del_bool (ev_send);        {delete the thread-exit event}

  goto loop_iline;                     {back to process next command input line}

err_cmparm:                            {parameter error, STAT set accordingly}
  lockout;
  sys_error_print (stat, '', '', nil, 0);
  unlockout;
  goto loop_iline;

err_extra:                             {extra command line parameter found}
  lockout;
  writeln ('Parameter "', parm.str:parm.len, '" is invalid or unrecognized.');
  unlockout;
  goto loop_iline;

leave:
  quit := true;                        {tell all threads to shut down}
  file_close (conn);                   {close connection to the serial line}
  end.
