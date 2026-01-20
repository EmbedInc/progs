{   Private include file for the BILLREPORT program.
}
%include 'base.ins.pas';

const
  logfile = '~/business/bill/log.txt'; {name of default log file}

type
  entry_p_t = ^entry_t;
  cust_p_t = ^cust_t;

  entry_t = record                     {data from one billing log file entry}
    next_p: entry_p_t;                 {to next entry, NIL at last}
    time: sys_clock_t;                 {start time for entry activity}
    hours: real;                       {hours worked, 0 when not applicable}
    cust_p: cust_p_t;                  {to customer, NIL if none}
    desc_p: string_var_p_t;            {to optional description}
    nextcust_p: entry_p_t;             {to next entry for this customer}
    end;

  cust_t = record                      {info about one customer}
    next_p: cust_p_t;                  {to next customer in list}
    name_p: string_var_p_t;            {to customer name string}
    first_p: entry_p_t;                {to first entry for this customer}
    last_p: entry_p_t;                 {to last entry for this customer}
    hours: real;                       {accumulated hours for this customer}
    end;

var (billcom)
  mem_p: util_mem_context_p_t;         {to our private memory context}
  log_first_p: entry_p_t;              {to log entries list}
  log_last_p: entry_p_t;               {to last log entry in list}
  cust_first_p: cust_p_t;              {to customer list}
  cust_last_p: cust_p_t;               {to last customer in list}
{
*   Subroutines and functions.
}
procedure hours_make;                  {compute hours, log entries and customers}
  val_param; extern;

procedure log_read (                   {read log file, build in-memory data}
  in      fnam: univ string_treename_t; {log file name, .TXT suffix implied}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure show_hours;                  {show hours by date per customer}
  val_param; extern;
