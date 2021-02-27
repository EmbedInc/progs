{   Program MPMEM options
*
*   Read a MPLINK map file and show the data memory usage.
}
program mpmem;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';
%include 'hier.ins.pas';
%include 'builddate.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  memreg_p_t = ^memreg_t;
  memreg_t = record                    {info about one memory region}
    next_p: memreg_p_t;                {pointer to region at next higher address}
    adr: sys_int_adr_t;                {start address}
    len: sys_int_adr_t;                {length in bytes}
    name: string_var32_t;              {section name}
    type: string_var32_t;              {from "Type" column in map file}
    end;

var
  fnam_in:                             {input file name}
    %include '(cog)lib/string_treename.ins.pas';
  rd: hier_read_t;                     {input file reading state}
  iname_set: boolean;                  {TRUE if the input file name already set}
  mem_p: util_mem_context_p_t;         {pointer to mem context for regions list}
  regfirst_p: memreg_p_t;              {pointer to first mem region in list}
  reglast_p: memreg_p_t;               {pointer to last mem region in list}
  regn: sys_int_machine_t;             {number of memory regions in the list}
  reg_p: memreg_p_t;                   {scratch pointer to me region list entry}
  name:                                {section name}
    %include '(cog)lib/string32.ins.pas';
  type:                                {name in Type column of map file}
    %include '(cog)lib/string32.ins.pas';
  adr: sys_int_adr_t;                  {mem region starting address}
  len: sys_int_adr_t;                  {mem region length in bytes}
  adrfirst: sys_int_adr_t;             {first address of first region}
  adrlast: sys_int_adr_t;              {end address of last region}
  nhex: sys_int_machine_t;             {number of HEX digits to use for addresses}
  ii: sys_int_machine_t;               {scratch integer and loop counter}

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
*   Subroutine NEW_REG (REG_P)
*
*   Allocate a new memory region descriptor, link it to the end of the list, and
*   return REG_P pointing to it.  The descriptor is initialized to default or
*   benign values to the extent possible.
}
procedure new_reg (                    {add new region to end of mem regions list}
  out     reg_p: memreg_p_t);          {returned pointing to the new descriptor}
  val_param; internal;

begin
  util_mem_grab (                      {allocate memory for the region}
    sizeof(reg_p^), mem_p^, false, reg_p);

  reg_p^.next_p := nil;                {this will be the last entry in the list}
  reg_p^.adr := 0;                     {init the data for this mem region}
  reg_p^.len := 0;
  reg_p^.name.max := size_char(reg_p^.name.str);
  reg_p^.name.len := 0;
  reg_p^.type.max := size_char(reg_p^.type.str);
  reg_p^.type.len := 0;

  if reglast_p = nil
    then begin                         {this is the first list entry}
      regfirst_p := reg_p;
      end
    else begin                         {adding to end of existing list}
      reglast_p^.next_p := reg_p;
      end
    ;
  reglast_p := reg_p;

  regn := regn + 1;                    {count one more entry in the list}
  end;
{
********************************************************************************
*
*   Subroutine ERR_BOMB_ATLINE (STAT)
*
*   Bomb the program if STAT indicates an error.  The current input line number
*   and file name will be included in the error message.
}
procedure err_bomb_atline (            {bomb program on err, show line number and file}
  in      stat: sys_err_t);            {error status, nothing done when no error}
  val_param; internal;

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;

begin
  if not sys_error(stat) then return;  {no error, nothing to do ?}

  sys_msg_parm_int (msg_parm[1], rd.conn.lnum); {line number message parameter}
  sys_msg_parm_vstr (msg_parm[2], rd.conn.tnam); {file name message parameter}
  sys_error_print (stat, 'progs', 'mpmem_err_atline', msg_parm, 2);
  sys_bomb;
  end;
{
********************************************************************************
*
*   Function RDLINE
*
*   Read the next line from the input file.  The function returns TRUE if a line
*   was read, and FALSE if the end of the file was encountered.  The program is
*   bombed on any error.
}
function rdline                        {read next input line}
  :boolean;                            {got line, not EOF}
  val_param; internal;

var
  stat: sys_err_t;

begin
  rdline := hier_read_line_nh (rd, stat); {get the new line}
  err_bomb_atline (stat);              {abort the program on hard error}
  end;
{
********************************************************************************
*
*   Subroutine RDLINE_NOEOF
*
*   Read the next line from the input file.  A line is required.  End of file is
*   an error.  The program is bombed on any error.
}
procedure rdline_noeof;                {read next line, EOF not allowed}

const
  max_msg_args = 1;                    {max arguments we can pass to a message}

var
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;

begin
  if not rdline then begin             {hit end of file ?}
    sys_msg_parm_vstr (msg_parm[1], rd.conn.tnam); {file name message parameter}
    sys_message_bomb ('progs', 'mpmem_eof', msg_parm, 1);
    end;
  end;
{
********************************************************************************
*
*   Function IFTKSTR (S)
*
*   Get the next token and return it in S.  The function returns TRUE when a
*   token was found, and FALSE if the end of line was encountered.
*
*   The program is bombed on error.
}
function iftkstr (                     {get next token}
  in out  s: univ string_var_arg_t)    {the returned token string}
  :boolean;                            {got a token, not EOL}
  val_param; internal;

begin
  iftkstr := hier_read_tk (rd, s);
  end;
{
********************************************************************************
*
*   Subroutine TKSTR (S)
*
*   Get the next input token and return it in S.
*
*   The program is bombed on error.
}
procedure tkstr (                      {get next token, which is required}
  in out  s: univ string_var_arg_t);   {the returned token string}
  val_param; internal;

var
  stat: sys_err_t;                     {completion status}

begin
  if not hier_read_tk_req (rd, s, stat) then begin {get the token}
    err_bomb_atline (stat);            {abort program on error}
    end;
  end;
{
********************************************************************************
*
*   Function IFKEYW (KW)
*
*   Read the next token as a keyword and return it in KW.  KW is returned upper
*   case for case-insensitive keyword matching.  The function returns TRUE if
*   a token was found, and FALSE if the end of line was encountered instead.
*
*   The program is bombed on error.
}
function ifkeyw (                      {read next token as keyword, required}
  in out  kw: univ string_var_arg_t)   {returned keyword, upper case}
  :boolean;                            {got a token, not EOL}
  val_param; internal;

begin
  ifkeyw := iftkstr (kw);              {get the token}
  string_upcase (kw);                  {make all upper case}
  end;
{
********************************************************************************
*
*   Subroutine RDKEYW (KW)
*
*   Read the next token as a keyword and return it in KW.  KW is returned upper
*   case for case-insensitive keyword matching.
*
*   The program is bombed on error.
}
procedure rdkeyw (                     {read next token as keyword, required}
  in out  kw: univ string_var_arg_t);  {returned keyword, upper case}
  val_param; internal;

begin
  tkstr (kw);                          {get the raw token}
  string_upcase (kw);                  {make all upper case}
  end;
{
********************************************************************************
*
*   Function IFINT (IVAL)
*
*   Get the next input line token and interpret it as an integer value according
*   to the MPLINK map file convention.  The integer value is returned in IVAL.
*
*   MPLINK map file integers are either decimal or hexadecimal.  If the token
*   starts with "0x", then the remainder is a hexadecimal number.  Otherwise,
*   the token is a decimal integer and may only contain the digits 0-9.
*
*   The function returns TRUE when returning with an integer value, and FALSE
*   when the end of line was encountered.
*
*   The program is bombed on error.
}
function ifint (                       {get next token, must be integer}
  out     ival: sys_int_adr_t)         {returned integer value}
  :boolean;                            {got an integer, not EOL}
  val_param; internal;

const
  max_msg_args = 3;                    {max arguments we can pass to a message}

var
  ii: sys_int_machine_t;               {scratch integer value}
  tk: string_var32_t;                  {the token parsed from the input line}
  tk2: string_var32_t;                 {edited token}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}

label
  err_int;

begin
  tk.max := size_char(tk.str);         {init local var strings}
  tk2.max := size_char(tk2.str);
  ifint := false;                      {init to not returning with an integer}

  if not ifkeyw(tk) then begin         {hit end of line ?}
    return;
    end;
  ifint := true;                       {will return with value, or bomb the program}

  string_t_int (tk, ii, stat);         {try to interpret as decimal integer}
  if not sys_error(stat) then begin    {that worked ?}
    ival := ii;                        {pass back the value}
    return;
    end;

  if tk.len < 3 then goto err_int;     {not long enough for 0xN ?}
  if                                   {doesn't start with "0x" ?}
      (tk.str[1] <> '0') or
      (tk.str[2] <> 'X')
    then goto err_int;

  string_substr (tk, 3, tk.len, tk2);  {extract just the HEX digits into TK2}

  string_t_int32h (tk2, ii, stat);     {interpret the remainder as HEX integer}
  if sys_error(stat) then goto err_int; {not a valid HEX string ?}
  ival := ii;                          {pass back the integer result}
  return;

err_int:                               {token is not a valid integer}
  sys_msg_parm_vstr (msg_parm[1], tk);
  sys_msg_parm_int (msg_parm[2], rd.conn.lnum);
  sys_msg_parm_vstr (msg_parm[3], rd.conn.tnam);
  sys_error_print (stat, 'progs', 'mpmem_tkint_err', msg_parm, 3);
  sys_bomb;
  return;                              {keep compiler from complaining}
  end;
{
********************************************************************************
*
*   Subroutine TKINT (IVAL)
*
*   Get the next input line token and interpret it as an integer value according
*   to the MPLINK map file convention.  The integer value is returned in IVAL.
*
*   MPLINK map file integers are either decimal or hexadecimal.  If the token
*   starts with "0x", then the remainder is a hexadecimal number.  Otherwise,
*   the token is a decimal integer and may only contain the digits 0-9.
*
*   The program is bombed on error.
}
procedure tkint (                      {get next token, must be integer}
  out     ival: sys_int_adr_t);        {returned integer value}
  val_param; internal;

const
  max_msg_args = 3;                    {max arguments we can pass to a message}

var
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;

begin
  if not ifint(ival) then begin        {hit end of line, didn't get integer ?}
    sys_msg_parm_int (msg_parm[1], rd.conn.lnum);
    sys_msg_parm_vstr (msg_parm[2], rd.conn.tnam);
    sys_message_bomb ('progs', 'mpmem_tk_eol', msg_parm, 2);
    end;
  end;
{
********************************************************************************
*
*   Subroutine HEXADR (ADR, TK)
*
*   Make the hexadecimal string for the address ADR.  NHEX number of HEX digits
*   will be used to express the address.  The HEX string is returned in TK.
}
procedure hexadr (                     {make hex address string}
  in      adr: sys_int_adr_t;          {the address}
  in out  tk: univ string_var_arg_t);  {the returned HEX string}
  val_param; internal;

var
  stat: sys_err_t;

begin
  string_f_int_max_base (              {convert integer to string}
    tk,                                {output string}
    adr,                               {input integer}
    16,                                {number base (radix)}
    nhex,                              {fixed field width}
    [ string_fi_leadz_k,               {fill field with leading zeros}
      string_fi_unsig_k],              {the input integer is unsigned}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  writeln ('Program MPMEM built on ', build_dtm_str:size_char(build_dtm_str));
{
*   Initialize before reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  iname_set := false;                  {no input file name specified}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not iname_set then begin        {input file name not set yet ?}
      string_treename(opt, fnam_in);   {set input file name}
      iname_set := true;               {input file name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-MAP',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -MAP filename
}
1: begin
  if iname_set then begin              {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (opt, stat);
  string_treename (opt, fnam_in);
  iname_set := true;
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
  if not iname_set then begin
    sys_message_bomb ('string', 'cmline_input_fnam_missing', nil, 0);
    end;
{
********************
*
*   Read all the data memory regions from the input file.
}
  hier_read_open (                     {open the input file}
    fnam_in, '.map',                   {file name and mandatory suffix}
    rd,                                {returned file reading state}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  writeln ('Reading MPLINK map file "',
    rd.conn.tnam.str:rd.conn.tnam.len, '"');
{
*   The file opened successfully.  Now initialize before reading the file.
}
  util_mem_context_get (               {create our private memory context}
    util_top_mem_context, mem_p);

  regfirst_p := nil;                   {init the memory regions list to empty}
  reglast_p := nil;
  regn := 0;
{
*   Read the MAP file lines looking for "Section Info" table.
}
  while true do begin                  {back here each new map file line}
    rdline_noeof;                      {get the next input file line}

    if not ifkeyw(parm) then next;
    if not string_equal(parm, string_v('SECTION'(0)))
      then next;

    if not ifkeyw(parm) then next;
    if not string_equal(parm, string_v('INFO'(0)))
      then next;

    if not hier_read_eol (rd, stat) then begin {not at end of line ?}
      err_bomb_atline (stat);
      end;
    exit;                              {found the "Section Info" line}
    end;                               {back to try next input file line}

  for ii := 1 to 2 do begin            {skip the next two lines}
    rdline_noeof;
    end;
{
*   The next line should be the first data line of the Section Info table.  A
*   blank line ends the table.
}
  while true do begin                  {back here each new map file line}
    if not rdline then exit;           {get next line, exit on EOF}
    if rd.buf.len = 0 then exit;       {blank line ends the table}

    tkstr (name);                      {get section name}
    rdkeyw (type);                     {get section type name}
    tkint (adr);                       {get section starting address}
    rdkeyw (parm);                     {get program/data qualifier}
    tkint (len);                       {get section length in bytes}

    if not string_equal(parm, string_v('DATA'(0)))
      then next;                       {not a data memory section ?}

    new_reg (reg_p);                   {add new mem regions entry to end of list}
    reg_p^.adr := adr;                 {fill in the data for this mem region}
    reg_p^.len := len;
    string_copy (name, reg_p^.name);
    string_copy (type, reg_p^.type);
    end;                               {back to get next Section Info table entry}

  hier_read_close (rd, stat);          {close the input file}
  sys_error_abort (stat, '', '', nil, 0);
{
********************
*
*   Show the mem regions data on standard output.
}
  write (regn, ' data memory regions found');
  if regn = 0
    then begin                         {no data memory regions were found}
      write ('.');
      writeln;
      end
    else begin                         {there is at least one memory region}
      adrfirst := regfirst_p^.adr;     {first address of all regions}
      adrlast := reglast_p^.adr + reglast_p^.len - 1; {last address of all regions}
      nhex := 3;                       {init HEX digits to use for addresses}
      if adrlast > 16#FFF then nhex := nhex + 1; {use more digits for larger addresses}
      hexadr (adrfirst, parm);
      write (' from ', parm.str:parm.len);
      hexadr (adrlast, parm);
      write (' to ', parm.str:parm.len, ':');
      writeln;
      writeln;
      end
    ;

  reg_p := regfirst_p;                 {init to first memory region in the list}
  while reg_p <> nil do begin          {back here each new list entry}
    {
    *   Show this memory region.
    }
    adrfirst := reg_p^.adr;            {get addresses and length of this region}
    len := reg_p^.len;
    adrlast := adrfirst + len - 1;

    hexadr (adrfirst, parm);
    write (' ':(25-reg_p^.name.len), reg_p^.name.str:reg_p^.name.len,
      ': ', parm.str:parm.len);
    hexadr (adrlast, parm);
    write ('-', parm.str:parm.len, ', length ', len:5,
      ', type ', reg_p^.type.str:reg_p^.type.len);
    writeln;
    {
    *   Show gap between this region and the next, if any.
    }
    adrfirst := reg_p^.adr + reg_p^.len; {gap starting address}
    if reg_p^.next_p = nil
      then begin                       {this is last region in the list}
        adrlast :=                     {to end of this bank}
          ((adrfirst + 16#FF) & 16#FFFFFF00) - 1;
        end
      else begin                       {there is another region following this one}
        adrlast := reg_p^.next_p^.adr - 1; {gap ending address}
        end
      ;
    if adrlast > adrfirst then begin   {there actually is a gap ?}
      len := adrlast - adrfirst + 1;   {size of this gap}
      hexadr (adrfirst, parm);
      write ('                           ', parm.str:parm.len);
      hexadr (adrlast, parm);
      write ('-', parm.str:parm.len, ', length ', len:5);
      writeln;
      end;
    {
    *   Write a blank line between banks of 256 bytes.
    }
    if
        (reg_p^.next_p <> nil) and then {there is a following region ?}
        (reg_p^.next_p^.adr & 16#FFFFFF00) {next region in different bank ?}
          <> (adrlast & 16#FFFFFF00)
        then begin
      writeln;
      end;

    reg_p := reg_p^.next_p;            {to next memory region in the list}
    end;                               {back to process this new list entry}

  end.
