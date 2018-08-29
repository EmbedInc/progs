{   Program CSV_ADDVAL csv csv2 name [name1]
*
*   Adds the values for the column NAME from CSV file 2 to the first CSV file.
*   If the first CSV file does not exist, then it is created.
*
*   If the first CSV file already exists, then the value from the second CSV
*   file is interpolated to the independent variable values in the first CSV
*   file.  The first column in each CSV file is assumed to be the independent
*   variable.
}
program csv_addval;
%include 'base.ins.pas';
%include 'math.ins.pas';

var
  csv1:                                {name of CSV file to add variable to}
    %include '(cog)lib/string_treename.ins.pas';
  csv2:                                {name of CSV file to get the variable from}
    %include '(cog)lib/string_treename.ins.pas';
  name:                                {variable name (column header), upper case}
    %include '(cog)lib/string80.ins.pas';
  oname:                               {variable name in output file}
    %include '(cog)lib/string80.ins.pas';
  conn: file_conn_t;                   {connection to the current input or output file}
  buf:                                 {one line input or output buffer}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {BUF parse index}
  vcol: sys_int_machine_t;             {1-N column number of variable in source file}
  col: sys_int_machine_t;              {column number}
  tk:                                  {scratch token}
    %include '(cog)lib/string80.ins.pas';
  indname:                             {name of independent variable in CSV file 2}
    %include '(cog)lib/string80.ins.pas';
  x, y: real;                          {independent and dependent variable values}
  add: real;                           {amount to add to input value}
  funlen: sys_int_machine_t;
  funar_p: ^math_funar_arg_t;          {input value function array}
  funn: sys_int_machine_t;             {1-N function array index}
  lines: string_list_t;                {list of original lines of CSV file 1}
  stat: sys_err_t;                     {completion status}

label
  done_cmline, make_new, leave;

begin
  string_cmline_init;                  {init for reading the command line}
  add := 0.0;                          {init to not alter the input value}

  string_cmline_token (csv1, stat);    {get name of CSV file to edit}
  string_cmline_req_check (stat);

  string_cmline_token (csv2, stat);    {get name of CSV file to get new data from}
  string_cmline_req_check (stat);

  string_cmline_token (name, stat);    {get name of variable to add}
  string_cmline_req_check (stat);

  string_cmline_token (oname, stat);   {try to get variable output name}
  if string_eos(stat) then begin
    string_copy (name, oname);
    goto done_cmline;
    end;
  sys_error_abort (stat, '', '', nil, 0);

  string_cmline_token_fpm (add, stat); {get optional amount to add to input value}
  if string_eos(stat) then begin
    add := 0.0;
    goto done_cmline;
    end;
  sys_error_abort (stat, '', '', nil, 0);

  string_cmline_end_abort;             {no more command line tokens allowed}

done_cmline:                           {done with the command line}
  string_upcase (name);
{
*   Open CSV file 2 and find the indicated variable.
}
  file_open_read_text (csv2, '.csv', conn, stat); {open the input CSV file}
  sys_error_abort (stat, '', '', nil, 0);

  file_read_text (conn, buf, stat);    {read the header line}
  sys_error_abort (stat, '', '', nil, 0);
  p := 1;                              {init parse index}
  vcol := 0;                           {init number of last column parsed}
  while true do begin                  {loop until find header for the selected variable}
    string_token_comma (buf, p, tk, stat); {get name of this column}
    if string_eos(stat) then begin     {end of header, didn't find variable ?}
      writeln ('Variable not found in second CSV file.');
      sys_bomb;
      end;
    vcol := vcol + 1;                  {make 1-N number of column just parsed}
    if vcol = 1 then begin             {this is the independent variable ?}
      string_copy (tk, indname);       {save name of the independent variable}
      end;
    string_upcase (tk);                {make upper case for name matching}
    if string_equal (tk, name) then exit; {found the variable name ?}
    end;                               {no, go back and check next column name}
  if vcol = 1 then begin               {name was for the independent variable ?}
    writeln ('Can''t add the independent variable.');
    sys_bomb;
    end;
{
*   VCOL is the 1-N column number of the variable to add, and is guaranteed to
*   be at least 2 (is not the independent variable).  The name of the
*   independent variable has been saved in INDNAME.
*
*   Now set FUNLEN to the number of values of this variable.
}
  funlen := 0;                         {init number of values found so far}
  while true do begin                  {back here to read each new line from the file}
    file_read_text (conn, buf, stat);  {read this new line}
    if file_eof(stat) then exit;       {hit end file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf);                {delete trailing spaces}
    if buf.len <= 0 then next;         {ignore blank lines}
    p := 1;                            {init parse index for this line}
    string_token_comma (buf, p, tk, stat); {get the independent variable value string}
    if sys_error(stat) then next;      {ignore line if can't read ind variable}
    string_t_fpm (tk, x, stat);        {get independent variable value}
    if sys_error(stat) then next;      {ingore line if can't interpret ind variable}
    col := 1;                          {init number of last column read}
    while true do begin                {back here to read each new field on this line}
      string_token_comma (buf, p, tk, stat); {get string for this new field}
      if sys_error(stat) then exit;
      col := col + 1;                  {make number of this column}
      if col < vcol then next;         {not at the target column yet ?}
      string_t_fpm (tk, y, stat);      {try to get the value of this column}
      if sys_error(stat) then exit;    {ignore line if can't interpret variable}
      funlen := funlen + 1;            {count one more value found for the variable}
      exit;
      end;
    end;                               {back to read next line from the file}

  if funlen < 2 then begin
    writeln ('Not enough values found, need at least 2.');
    sys_bomb;
    end;
{
*   Now that we know the number of values, allocate and fill in the input values
*   array.
}
  sys_mem_alloc (sizeof(funar_p^[1]) * funlen, funar_p); {allocate function array}
  funn := 0;                           {init number of function array entries written}

  file_pos_start (conn, stat);         {reset back to start of the file}
  file_read_text (conn, buf, stat);    {skip over the header line}
  sys_error_abort (stat, '', '', nil, 0);

  while funn < funlen do begin         {back here to read each new line from the file}
    file_read_text (conn, buf, stat);  {read this new line}
    if file_eof(stat) then exit;       {hit end file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf);                {delete trailing spaces}
    if buf.len <= 0 then next;         {ignore blank lines}
    p := 1;                            {init parse index for this line}
    string_token_comma (buf, p, tk, stat); {get the independent variable value string}
    if sys_error(stat) then next;      {ignore line if can't read ind variable}
    string_t_fpm (tk, x, stat);        {get independent variable value}
    if sys_error(stat) then next;      {ingore line if can't interpret ind variable}
    col := 1;                          {init number of last column read}
    while true do begin                {back here to read each new field on this line}
      string_token_comma (buf, p, tk, stat); {get string for this new field}
      if sys_error(stat) then exit;
      col := col + 1;                  {make number of this column}
      if col < vcol then next;         {not at the target column yet ?}
      string_t_fpm (tk, y, stat);      {try to get the value of this column}
      if sys_error(stat) then exit;    {ignore line if can't interpret variable}
      funn := funn + 1;                {make function array index for this value}
      funar_p^[funn].x := x;           {save the data from this line}
      funar_p^[funn].y := y + add;
      exit;
      end;
    end;                               {back to read next line from the file}
  funlen := funn;                      {save actual number of function points stored}

  file_close (conn);                   {close the input CSV file}
{
*   Read the first CSV file and save its lines in the string list LINES.
}
  string_list_init (lines, util_top_mem_context); {init list of CSV file lines}
  lines.deallocable := false;          {won't individually deallocate list entries}

  file_open_read_text (csv1, '.csv', conn, stat); {open the CSV file that will be edited}
  if file_not_found(stat) then goto make_new; {doesn't exist, write new CSV file ?}
  sys_error_abort (stat, '', '', nil, 0);

  while true do begin                  {once for each line of the CSV file}
    file_read_text (conn, buf, stat);  {read this new line}
    if file_eof(stat) then exit;       {hit end of file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf);                {delete trailing blanks}
    lines.size := buf.len;             {set size of new line to add to list}
    string_list_line_add (lines);      {add new line and make it current}
    string_copy (buf, lines.str_p^);   {save this line in lines list}
    end;                               {back to save next line}
  file_close (conn);                   {done reading CSV file 1}

  string_list_pos_abs (lines, 1);      {go to the stored header line}
  if lines.str_p = nil then goto make_new; {no header line ?}
  if lines.str_p^.len <= 0 then goto make_new; {header line is empty ?}
{
*   Write the stored lines back to CSV file 1, but add the value of the new
*   variable at the end of every line where the independent variable value is
*   readable.  The lines position is set to the header line.
}
  file_open_write_text (csv1, '.csv', conn, stat); {open CSV file 1 for writing}
  sys_error_abort (stat, '', '', nil, 0);

  string_copy (lines.str_p^, buf);     {get the original header line}
  string_append1 (buf, ',');
  string_append_token (buf, oname);    {add name of the new variable}

  while true do begin                  {once for each data line to write}
    file_write_text (buf, conn, stat); {write previous modified line to the file}
    sys_error_abort (stat, '', '', nil, 0);
    string_list_pos_rel (lines, 1);    {go to next stored original line}
    if lines.str_p = nil then exit;    {hit end of lines list ?}
    string_copy (lines.str_p^, buf);   {init updated line to write}
    p := 1;                            {init parse index}
    string_token_comma (buf, p, tk, stat); {get independent variable}
    if sys_error(stat) then next;      {can't get ind var, leave line alone ?}
    string_t_fpm (tk, x, stat);        {try to get the ind var value}
    if sys_error(stat) then next;      {can't get ind var, leave line alone ?}
    y := math_ipolate(funar_p^, funlen, x); {interpolate to this independent var value}
    string_append1 (buf, ',');         {add separator at end before new field}
    string_f_fp_free (tk, y, 6);       {make new value string}
    string_append (buf, tk);           {add it to the end of the line}
    end;                               {back to write this line and do next}
  goto leave;                          {done writing all the update CSV file lines}
{
*   The first CSV file does not exist, is empty, or otherwise unusable.  Create
*   it entirely from the data saved from the second CSV file.
}
make_new:
  file_open_write_text (csv1, '.csv', conn, stat); {open CSV file 1 for writing}
  sys_error_abort (stat, '', '', nil, 0);

  string_copy (indname, buf);          {init header line with independent variable name}
  string_append1 (buf, ',');
  string_append_token (buf, oname);    {add the dependent variable name}

  funn := 0;                           {init current number of function array entry}
  while true do begin                  {once for each line to write}
    file_write_text (buf, conn, stat); {write the last generated line to the file}
    sys_error_abort (stat, '', '', nil, 0);
    funn := funn + 1;                  {make number of this function array entry}
    if funn > funlen then exit;        {done with all function entries ?}
    string_f_fp_free (buf, funar_p^[funn].x, 6); {init line with independent var value}
    string_append1 (buf, ',');
    string_f_fp_free (tk, funar_p^[funn].y, 6); {make dependent value string}
    string_append_token (buf, tk);
    end;                               {back to write this line and do next}

leave:                                 {common non-error exit point}
  file_close (conn);                   {close the modified or created CSV file}
  end.
