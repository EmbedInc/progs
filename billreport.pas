{   Program BILLREPORT
*
*   Generate reports from the billing log file.
}
program billreport;
%include 'billreport.ins.pas';
define billcom;                        {define common block for global variables}

var
  stat: sys_err_t;                     {completion status}

begin
{
*   Initialize the global state.
}
  util_mem_context_get (               {create our private mem context}
    util_top_mem_context, mem_p);
  log_first_p := nil;                  {init to no log entries}
  log_last_p := nil;
  cust_first_p := nil;                 {init to no customer list entries}
  cust_last_p := nil;
{
*   Create the in-memory data structures from the log file.
}
  log_read (string_v(logfile), stat);  {read log file, create data structures}
  sys_error_abort (stat, '', '', nil, 0);

  hours_make;                          {compute hours for log entries and customers}
  show_hours;                          {show work hours by date per customer}
  end.
