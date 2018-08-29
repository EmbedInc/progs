{   Program BOM_LABELS
}
program bom_labels;
%include 'base.ins.pas';

const
  max_lab_len = 40;                    {max characters per label output line}
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  part_p_t = ^part_t;
  part_t = record                      {info about one part type in the BOM}
    next_p: part_p_t;                  {points to next part in list}
    qty: sys_int_machine_t;            {total quantity used}
    desig: string_list_t;              {designator for each use of this part}
    desc: string_var80_t;              {part description}
    value: string_var80_t;             {part value}
    pack: string_var80_t;              {package name}
    manuf: string_var80_t;             {manufacturer name}
    partnum: string_var80_t;           {manufacturer's part number}
    end;

var
  fnam_in:                             {CSV input file name}
    %include '(cog)lib/string_treename.ins.pas';
  iname_set: boolean;                  {input name set from command line}
  parts_p: part_p_t;                   {points to start of parts list}
  part_last_p: part_p_t;               {points to last parts list entry}
  nparts: sys_int_machine_t;           {number of parts in parts list}
  nunits: sys_int_machine_t;           {number of units to be built}
  board:                               {name of board this kit is for, upper case}
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
  next_opt, done_opt, err_parm, parm_bad, done_opts;
{
********************************************************************************
*
*   Subroutine READ_CSV (FNAM)
*
*   Read the comma-separated values input file and build the parts list.
*
*   The first line of the file must contain text headers for the columns with
*   subsequent lines containing the raw data as specified by the headers.  The
*   column heading names are examined to determine which column contains which
*   information.
}
procedure read_csv (                   {read CSV input file and build parts list}
  in      fnam: univ string_var_arg_t); {file name}
  val_param; internal;

const
  maxcol_k = 20;                       {maximum columns supported}
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  colty_k_t = (                        {ID for each of the recognized column types}
    colty_ignore_k,                    {ignore this column}
    colty_qty_k,                       {quantity}
    colty_desig_k,                     {designators list}
    colty_desc_k,                      {text description}
    colty_value_k,                     {part value}
    colty_pack_k,                      {package name}
    colty_manuf_k,                     {manufacturer}
    colty_partnum_k);                  {part number}
  colty_t = set of colty_k_t;          {flags for all column types in one word}

var
  conn: file_conn_t;                   {connection to CSV input file}
  colty: array[1 .. maxcol_k] of colty_k_t; {type ID for each column}
  col: sys_int_machine_t;              {1-N current column number}
  cols: colty_t;                       {set of all column types found so far}
  tcol: colty_k_t;                     {type of this column}
  mi: string_index_t;                  {substring start index}
  p: string_index_t;                   {BUF parse index}
  part_p: part_p_t;                    {pointer to new parts list entry}
  buf: string_var8192_t;               {one line input buffer}
  tk: string_var8192_t;                {token parsed from input line}
  i: sys_int_machine_t;                {scratch integer}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status}
{
****************************************
*
*   Local subroutine READ_DESIGNATORS (S, PART)
*
*   Read the list of part designators from the string S and add them to the
*   DESIG string list of PART.  The designators in S are separated by blanks.
}
procedure read_designators (           {read designators string, add to DESIG list}
  in      s: univ string_var_arg_t;    {designators string, blank separated}
  in out  part: part_t);               {add the designators to DESIG string list}
  val_param; internal;

var
  p: string_index_t;                   {S parse index}
  tk: string_var32_t;                  {token parsed from S}
  stat: sys_err_t;                     {completion status}

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_list_pos_last (part.desig);   {go to end of existing designators list, if any}
  p := 1;                              {init parse index to beginning of input string}

  while true do begin                  {once for each designator in the input string}
    string_token (s, p, tk, stat);     {get next designator into TK}
    if string_eos(stat) then exit;     {end of string, all done ?}
    sys_error_abort (stat, '', '', nil, 0);
    part.desig.size := tk.len;         {set size of new string list entry to create}
    string_list_line_add (part.desig); {create the entry}
    string_copy (tk, part.desig.str_p^) {write this designator to new list entry}
    end;                               {back to get next designator from input string}
  end;
{
****************************************
*
*   Start of executable code for subroutine READ_CSV.
}
label
  nextline, err_atline, leave;

begin
  buf.max := size_char(buf.str);       {init local var strings}
  tk.max := size_char(tk.str);
  part_p := nil;                       {indicate part descriptor not allocated}

  file_open_read_text (fnam, '_bom.csv .csv', conn, stat); {open the input file}
  sys_error_abort (stat, '', '', nil, 0);
  writeln ('Reading file "', conn.tnam.str:conn.tnam.len, '"');
  string_copy (conn.gnam, board);      {save build name}
  string_upcase (board);

  for col := 1 to maxcol_k do begin    {init all columns to be ignored}
    colty[col] := colty_ignore_k;
    end;
  cols := [];                          {init list of all special column types found}

  file_read_text (conn, buf, stat);    {read the headers line into BUF}
  if file_eof(stat) then goto leave;   {end of file ?}
  sys_error_abort (stat, '', '', nil, 0);
  p := 1;                              {init BUF parse index}
  string_upcase (buf);                 {make upper case for case-insensitivity}
{
*   Parse the header line and set COLTY to indicate the column number of each
*   special column type, and COLS to the total set of special columns found.
}
  for col := 1 to maxcol_k do begin    {once for each possible supported column}
    string_token_comma (buf, p, tk, stat); {get header string for this col into TK}
    if string_eos(stat) then exit;     {end of line ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (tk);                 {delete trailing blanks}
    if tk.len = 0 then next;           {ignore blank or empty column names}
    tcol := colty_ignore_k;            {init to this column not special type}

    string_t_int (tk, i, stat);        {try to interpret column name as integer value}
    if sys_error(stat)
      then begin                       {column name isn't a integer}
        sys_error_none (stat);         {reset to no error occurred}
        end
      else begin                       {column heading is a integer}
        tcol := colty_qty_k;           {indicate this is the quantity column}
        nunits := i;                   {save number of units this kit is for}
        end
      ;

    string_find (string_v('DESIG'(0)), tk, mi);
    if mi <> 0 then tcol := colty_desig_k;

    string_find (string_v('DESC'(0)), tk, mi);
    if mi <> 0 then tcol := colty_desc_k;

    string_find (string_v('VALUE'(0)), tk, mi);
    if mi <> 0 then tcol := colty_value_k;

    string_find (string_v('PACK'(0)), tk, mi);
    if mi <> 0 then tcol := colty_pack_k;

    string_find (string_v('MANUF'(0)), tk, mi);
    if mi <> 0 then tcol := colty_manuf_k;

    string_find (string_v('MANUF PART'(0)), tk, mi);
    if mi <> 0 then tcol := colty_partnum_k;

    colty[col] := tcol;                {set type of this column}
    cols := cols + [tcol];             {include this type in found types list}
    end;                               {back to do next column header field}
{
*   Check for required columns.
}
  if not (colty_qty_k in cols) then begin
    writeln ('  Quantity column is missing.');
    sys_bomb;
    end;

  if not (colty_desig_k in cols) then begin
    writeln ('  Designators column is missing.');
    sys_bomb;
    end;

  if not (colty_desc_k in cols) then begin
    writeln ('  Description column is missing.');
    sys_bomb;
    end;
{
*   The header line has been read and the special columns identified.  COL
*   contains the ID for each column.
*
*   Now read each line and process the info on that line.
}
nextline:                              {back here to read each new input line}
  file_read_text (conn, buf, stat);    {read this data line into BUF}
  if file_eof(stat) then goto leave;   {end of file ?}
  if sys_error(stat) then goto err_atline;
  p := 1;                              {init BUF parse index}

  if part_p = nil then begin           {no previous parts descriptor to reuse ?}
    sys_mem_alloc (sizeof(part_p^), part_p); {allocate descriptor for this part}
    end;
  part_p^.next_p := nil;               {init all fields to default}
  part_p^.qty := 0;
  string_list_init (part_p^.desig, util_top_mem_context);
  part_p^.desig.deallocable := false;
  part_p^.desc.max := size_char(part_p^.desc.str);
  part_p^.desc.len := 0;
  part_p^.value.max := size_char(part_p^.value.str);
  part_p^.value.len := 0;
  part_p^.pack.max := size_char(part_p^.pack.str);
  part_p^.pack.len := 0;
  part_p^.manuf.max := size_char(part_p^.manuf.str);
  part_p^.manuf.len := 0;
  part_p^.partnum.max := size_char(part_p^.partnum.str);
  part_p^.partnum.len := 0;

  for col := 1 to maxcol_k do begin    {once for each possible supported column}
    string_token_comma (buf, p, tk, stat); {get field for this column into TK}
    if string_eos(stat) then exit;     {end of line ?}
    if sys_error(stat) then goto err_atline;

    case colty[col] of                 {what type of data is this ?}

colty_qty_k: begin                     {number of parts used of this type}
        if tk.len > 0 then begin       {not empty field ?}
          string_t_int (tk, part_p^.qty, stat);
          end;
        end;

colty_desig_k: begin                   {list of designators, blank separated}
        read_designators (tk, part_p^); {add designators to DESIG string list}
        end;

colty_desc_k: begin                    {part description string}
        string_copy (tk, part_p^.desc);
        end;

colty_value_k: begin
        string_copy (tk, part_p^.value);
        end;

colty_pack_k: begin
        string_copy (tk, part_p^.pack);
        end;

colty_manuf_k: begin
        string_copy (tk, part_p^.manuf);
        end;

colty_partnum_k: begin
        string_copy (tk, part_p^.partnum);
        end;

      end;                             {end of column type cases}
    if sys_error(stat) then goto err_atline; {abort on error}
    end;                               {back to process next column this line}
{
*   This line has ended one way or another, and all the relevant data has been
*   gathered into PART_P^.
*
*   Now add this part to the end of the parts list if it contains the minimum
*   required information.
}
  if part_p^.qty = 0 then goto nextline; {no quatity supplied or none used ?}
  if part_p^.desig.n = 0 then goto nextline; {no designators ?}
  if                                   {must have at least one of descr, value, or manuf partnum}
      (part_p^.desc.len = 0) and
      (part_p^.value.len = 0) and
      ((part_p^.manuf.len = 0) or (part_p^.partnum.len = 0))
    then goto nextline;

  if part_last_p = nil
    then begin                         {list is empty ?}
      parts_p := part_p;               {set start of list pointer}
      end
    else begin                         {adding after existing entry}
      part_last_p^.next_p := part_p;
      end
    ;
  part_last_p := part_p;               {update pointer to last list entry}
  part_p := nil;                       {need to allocate a new descriptor next time}
  nparts := nparts + 1;                {count one more part in parts list}
  goto nextline;                       {back to read next input file line}

err_atline:                            {error on current line, STAT already set}
  sys_error_print (stat, '', '', nil, 0);
  sys_msg_parm_int (msg_parm[1], conn.lnum);
  sys_msg_parm_vstr (msg_parm[2], conn.tnam);
  sys_message_bomb ('string', 'err_at_line', msg_parm, 2);

leave:                                 {common exit point with file open}
  file_close (conn);                   {close the file}
  end;
{
********************************************************************************
*
*   Subroutine WRITE_PARTS
*
*   Write the parts info to the LABE_BOM.INS.SL output file.
}
procedure write_parts;                 {write list of parts to output file}
  val_param; internal;

var
  part_p: part_p_t;                    {points to current parts list entry}
  conn: file_conn_t;                   {connection to the output file}
  buf: string_var1024_t;               {one line output buffer}
  tk, tk2: string_var1024_t;           {scratch tokens}
  ndesig: sys_int_machine_t;           {1-N number of designators line}
  stat: sys_err_t;                     {completion status}
{
****************************************
*
*   Local subroutine WBUF
*
*   Write the contents of BUF to the output file, then reset BUF to empty.
}
procedure wbuf;
  internal;

var
  stat: sys_err_t;

begin
  file_write_text (buf, conn, stat);   {write the line to the output file}
  sys_error_abort (stat, '', '', nil, 0);
  buf.len := 0;                        {reset BUF to empty}
  end;
{
****************************************
*
*   Subroutine LSTRING (S)
*
*   Add the literal string in SLIDE format to BUF.  A leading space is written
*   before the literal string if BUF is not empty.
}
procedure lstring (                    {add literal string in SLIDE format to BUF}
  in      s: univ string_var_arg_t);   {string to add}
  val_param; internal;

var
  ind: string_index_t;                 {index into input string}

begin
  if buf.len > 0 then begin            {there is some previous text on line ?}
    string_append1 (buf, ' ');         {add separator after previous text}
    end;

  string_append1 (buf, '"');           {leading quote to start literal string}
  for ind := 1 to s.len do begin       {once for each character in literal string}
    string_append1 (buf, s.str[ind]);  {add this character}
    if s.str[ind] = '"' then begin     {quote character special case ?}
      string_append1 (buf, '"');       {write double quote}
      end;
    end;
  string_append1 (buf, '"');           {literal string closing quote}
  end;
{
****************************************
*
*   Local subroutine WRITE_DESIG_LINE (LN)
*
*   Write the definition for a new designators line to the output file.  LN
*   is the line of designators to write.  NDESIG is the 1-N number of the
*   LAB_DESIGn line to define.  It will be updated to the next label to define.
*   BUF will be used.  It is assumed to be empty on entry and will be left empty
*   on exit.
}
procedure write_desig_line (           {write definition for one line of designators}
  in      ln: univ string_var_arg_t);  {line of designators to write}
  val_param; internal;

var
  tk: string_var32_t;                  {scratch token}

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_appends (buf, 'set lab_desig');
  string_f_int (tk, ndesig);
  string_append (buf, tk);
  lstring (ln);
  wbuf;

  ndesig := ndesig + 1;
  end;
{
****************************************
*
*   Executable code for subroutine WRITE_PARTS.
}
begin
  buf.max := size_char(buf.str);       {init local var strings}
  buf.len := 0;
  tk.max := size_char(tk.str);
  tk2.max := size_char(tk2.str);

  file_open_write_text (
    string_v('~/eagle/sl/label_bom.ins.sl'), '', {file name and suffix}
    conn,                              {returned connection to the output file}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
{
*   Write output file header.
}
  string_appends (buf, '*   Labels for kit '(0));
  string_append (buf, board);
  string_appends (buf, ', '(0));
  string_f_int (tk, nunits);
  string_append (buf, tk);
  string_appends (buf, ' units.'(0));
  wbuf;
  string_appends (buf, '*'(0));
  wbuf;

  string_appends (buf, 'set lab_ix 1');
  wbuf;

  string_appends (buf, 'set lab_iy 1');
  wbuf;

  string_appends (buf, 'set lab_start 1');
  wbuf;

  string_appends (buf, 'set lab_last '(0));
  string_f_int (tk, nparts);
  string_append (buf, tk);
  wbuf;

  string_appends (buf, 'set lab_dir 0');
  wbuf;

  string_appends (buf, 'set nunits '(0));
  string_f_int (tk, nunits);
  string_append (buf, tk);
  wbuf;

  string_appends (buf, 'set buildname');
  lstring (board);
  wbuf;
{
*   Write the information for each separate label.
}
  part_p := parts_p;                   {init to start of parts list}
  while part_p <> nil do begin         {once for each parts list entry}
    {
    *   Write info about this part to standard output.
    }
    string_f_int (tk, part_p^.qty);
    string_append (buf, tk);
    string_appends (buf, ': '(0));
    string_append (buf, part_p^.desc);
    string_appends (buf, ', '(0));
    string_append (buf, part_p^.value);
    string_appends (buf, ', '(0));
    string_append (buf, part_p^.pack);
    string_appends (buf, ', '(0));
    string_append (buf, part_p^.manuf);
    string_appends (buf, ', '(0));
    string_append (buf, part_p^.partnum);
    writeln (buf.str:buf.len);
    buf.len := 0;

    wbuf;                              {blank line separator before this label}
    {
    *   Define quantity string.
    }
    string_appends (buf, 'set lab_qty');
    string_f_int (tk, part_p^.qty);
    lstring (tk);
    wbuf;
    {
    *   Define description string.
    }
    string_appends (buf, 'set lab_desc');
    tk.len := 0;                       {init description string}
    if part_p^.desc.len > 0 then begin
      if tk.len > 0 then string_appends (tk, ', '(0));
      string_append (tk, part_p^.desc);
      end;
    if part_p^.value.len > 0 then begin
      if tk.len > 0 then string_appends (tk, ', '(0));
      string_append (tk, part_p^.value);
      end;
    if part_p^.pack.len > 0 then begin
      if tk.len > 0 then string_appends (tk, ', '(0));
      string_append (tk, part_p^.pack);
      end;
    if (part_p^.manuf.len > 0) and (part_p^.partnum.len > 0) then begin
      if tk.len > 0 then string_appends (tk, ', '(0));
      string_append (tk, part_p^.manuf);
      string_append1 (tk, ' ');
      string_append (tk, part_p^.partnum);
      end;
    lstring (tk);
    wbuf;
    {
    *   Define the designator strings.
    }
    ndesig := 1;                       {init number of current designator string}
    tk.len := 0;                       {init current designator line to empty}
    string_list_pos_abs (part_p^.desig, 1); {go to first designator in list}
    repeat                             {once for each designator in list}
      if (tk.len + 1 + part_p^.desig.str_p^.len) > max_lab_len then begin {need new line ?}
        write_desig_line (tk);
        tk.len := 0;                   {init new designators line to empty}
        end;
      if tk.len > 0 then begin         {not first designator on line ?}
        string_append1 (tk, ' ');
        end;
      string_append (tk, part_p^.desig.str_p^);
      string_list_pos_rel (part_p^.desig, 1); {advance to next designator in list}
      until part_p^.desig.str_p = nil;
    if tk.len > 0 then write_desig_line (tk); {write any partial remaining line}
    {
    *   Write line to draw the label.
    }
    string_appends (buf, 'call draw_label');
    wbuf;

    part_p := part_p^.next_p;          {advance to next part in parts list}
    end;

  file_close (conn);                   {close connection to the output file}
  end;
{
********************************************************************************
*
*   Start of main program.
}
begin
{
*   Initialize state before reading the command line.
}
  string_cmline_init;                  {init for reading the command line}
  parts_p := nil;                      {init parts list to empty}
  part_last_p := nil;
  nparts := 0;
  nunits := 0;
  iname_set := false;                  {init to file name not set yet}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit input file name ?}
    if not iname_set then begin        {input name not set yet ?}
      string_copy (opt, fnam_in);      {set input name}
      iname_set := true;               {input name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-IN',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -IN buildname
}
1: begin
  if iname_set then begin              {input name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (fnam_in, stat);
  iname_set := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

done_opt:                              {done processing the current command line option}

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
}
  if not iname_set then begin          {input name specified ?}
    writeln ('No input file specified.');
    sys_bomb;
    end;

  read_csv (fnam_in);                  {read CSV input file and build in-memory list}
  if parts_p = nil then begin          {no parts ?}
    writeln ('No parts found.');
    sys_exit;
    end;
  writeln (nparts, ' unique parts found.');

  write_parts;                         {write the parts list to the output file}
  end.
