module billreport_log_read;
define log_read;
%include 'billreport.ins.pas';
{
********************************************************************************
*
*   Subroutine LOG_READ (FNAM, STAT)
*
*   Read the billing log file FNAM and add its contents to the in-memory
*   structures.  Specifically, the log entry list and customer list are updated.
}
procedure log_read (                   {read log file, build in-memory data}
  in      fnam: univ string_treename_t; {log file name, .TXT suffix implied}
  out     stat: sys_err_t);            {completion status}
  val_param;

var
  conn: file_conn_t;                   {connection to log file}
  iline: string_var8192_t;             {current input line from log file}
  tk: string_var32_t;                  {token parsed from input line}
  p: string_index_t;                   {input line parse index}
  date: sys_date_t;                    {date on current input line}
  time: sys_clock_t;                   {time of current log entry}
  cust: string_var80_t;                {customer name, case-sensitive}
  desc: string_var8192_t;              {description string}
  cust_p: cust_p_t;                    {to customer list entry}
  ent_p: entry_p_t;                    {to log list entry}

label
  nextline, done_cust, err_atline, abort1, done_logfile;

begin
  iline.max := size_char(iline.str);   {init local var strings}
  tk.max := size_char(tk.str);
  cust.max := size_char(cust.str);
  desc.max := size_char(desc.str);

  file_open_read_text (                {open connection to the log file}
    fnam, '.txt',                      {file name and required suffix}
    conn,                              {returned connection to the file}
    stat);
  if sys_error(stat) then return;

nextline:                              {read and process the next log file line}
  file_read_text (conn, iline, stat);  {read this next log file entry}
  if file_eof(stat) then goto done_logfile; {end of log file ?}
  if sys_error(stat) then goto abort1;
  string_unpad (iline);                {truncate trailing blanks}
  if iline.len <= 0 then goto nextline; {ignore blank or empty lines}

  p := 1;                              {init parse index into this line}
  while (iline.str[p] = ' ') do begin  {scan forwards for the first non-blank}
    if p > iline.len then exit;        {reached end of input line ?}
    p := p + 1;                        {to next input line character}
    end;
  if iline.str[p] = '*' then goto nextline; {comment line, ignore ?}
{
*   This is not a comment line.  P is the index of the first non-blank input
*   line character.
*
*   Get the date/time string and set TIME accordingly.
}
  string_token (iline, p, tk, stat);   {get time string}
  if sys_error(stat) then goto err_atline;
  string_t_date1 (tk, true, date, stat); {interpret the date/time string}
  if sys_error(stat) then goto err_atline;
  time := sys_clock_from_date (date);  {make time descriptor from date/time}
{
*   Get the customer name into CUST.
}
  string_token (iline, p, cust, stat); {get customer name string}
  if string_eos(stat) then begin
    cust.len := 0;
    end;
{
*   Get description string into DESC.
}
  string_token (iline, p, desc, stat); {get description string}
  if string_eos(stat) then begin
    desc.len := 0;
    end;

  string_token (iline, p, tk, stat);   {try to get another token}
  if not string_eos(stat) then begin   {didn't hit end of line as expected ?}
    goto err_atline;
    end;
{
*   Done reading the log file line.  TIME is the time of this log entry, CUST
*   the customer name, and DESC the description.  Both CUST and DESC may be
*   empty.
*
*   Find or create a customer list entry for the specified customer.  Either
*   way, CUST_P is set pointing to the entry.  CUST_P will be NIL when no
*   customer was specified.
}
  if cust.len <= 0 then begin          {no customer specified ?}
    cust_p := nil;
    goto done_cust;
    end;

  cust_p := cust_first_p;              {init to first customer list entry}
  while cust_p <> nil do begin         {scan the existing list entries}
    if string_equal(cust_p^.name_p^, cust) {existing entry for this customer ?}
      then goto done_cust;
    cust_p := cust_p^.next_p;          {to next customer list entry}
    end;

  util_mem_grab (                      {allocate memory for new customer list entry}
    sizeof(cust_p^), mem_p^, false, cust_p);
  cust_p^.next_p := nil;               {will be last entry in customer list}
  string_duplicate (cust, mem_p^, false, cust_p^.name_p); {save customer name string}
  cust_p^.first_p := nil;              {no log entries for this customer yet}
  cust_p^.last_p := nil;
  cust_p^.hours := 0.0;

  if cust_last_p = nil
    then begin                         {this will be first customer list entry}
      cust_first_p := cust_p;
      end
    else begin                         {adding to end of existing customer list}
      cust_last_p^.next_p := cust_p;
      end
    ;
  cust_last_p := cust_p;               {update pointer to last customer list entry}

done_cust:                             {CUST_P points to customer list ent, or NIL}
{
*   Create the new log list entry.
}
  util_mem_grab (                      {allocate memory for new log entry}
    sizeof(ent_p^), mem_p^, false, ent_p);
  ent_p^.next_p := nil;                {will be last log entry}
  ent_p^.time := time;                 {save time of this log entry}
  ent_p^.hours := 0.0;
  ent_p^.cust_p := cust_p;             {to customer name, if any}
  if desc.len <= 0
    then begin                         {no description string}
      ent_p^.desc_p := nil;
      end
    else begin                         {this log entry has a description}
      string_duplicate (               {save description string}
        desc, mem_p^, false, ent_p^.desc_p);
      end
    ;
  ent_p^.nextcust_p := nil;            {init to last entry for this customer}

  if log_last_p = nil
    then begin                         {this will be first log entry}
      log_first_p := ent_p;
      end
    else begin                         {adding to end of existing log entries list}
      log_last_p^.next_p := ent_p;
      end
    ;
  log_last_p := ent_p;                 {update pointer to last log entry}
{
*   Add this entry to the list for the customer, if a customer was specified.
}
  if cust_p <> nil then begin          {this log entry specifies a customer ?}
    if cust_p^.last_p = nil
      then begin                       {will be first log entry for this customer}
        cust_p^.first_p := ent_p;
        end
      else begin                       {add to end of log entries for this custome}
        cust_p^.last_p^.nextcust_p := ent_p;
        end
      ;
    cust_p^.last_p := ent_p;           {update last log entry for this customer}
    end;

  goto nextline;                       {back to process next log file line}

err_atline:                            {error on current log file line}
  if sys_error(stat)
    then begin                         {STAT already indicates an error}
      writeln ('Error on line ', conn.lnum, ' of "', conn.tnam.str:conn.tnam.len, ':');
      end
    else begin                         {STAT not set yet}
      sys_stat_set (string_subsys_k, string_stat_err_on_line_k, stat);
      sys_stat_parm_int (conn.lnum, stat);
      sys_stat_parm_vstr (conn.tnam, stat);
      end
    ;

abort1:                                {skip to here on error with log file open}
done_logfile:                          {done reading the log file}
  file_close (conn);
  if sys_error(stat) then return;
  end;
