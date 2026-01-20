module billreport_show;
define show_hours;
%include 'billreport.ins.pas';
{
********************************************************************************
*
*   Subroutine SHOW_HOURS
*
*   For each customer, show hours spent each log entry and total hours.
}
procedure show_hours;                  {show hours by date per customer}
  val_param;

var
  cust_p: cust_p_t;                    {to current customer}
  ent_p: entry_p_t;                    {to current log entry within customer}
  tk: string_var32_t;                  {scratch token}
  ncust: sys_int_machine_t;            {number of customers listed}
  tzone: sys_tzone_k_t;                {time zone here}
  hours_west: real;                    {hours west for time zone here}
  daysave: sys_daysave_k_t;            {daylight savings time strategy here}
  date: sys_date_t;                    {expanded date/time}

begin
  tk.max := size_char(tk.str);         {init local var string}
  ncust := 0;                          {init number of customers reported on}
  sys_timezone_here (                  {get info for our time zone here}
    tzone, hours_west, daysave);

  cust_p := cust_first_p;              {init to first customer in the list}
  while cust_p <> nil do begin         {scan the customer list}
    ncust := ncust + 1;
    writeln;
    writeln (cust_p^.name_p^.str:cust_p^.name_p^.len); {show customer name}

    ent_p := cust_p^.first_p;          {to first log entry this customer}
    while ent_p <> nil do begin        {scan the log entries for this customer}
      sys_clock_to_date (              {make expanded date/time for this log entry}
        ent_p^.time,                   {time to expand}
        tzone, hours_west, daysave,    {target time zone}
        date);                         {returned expanded date/time}
      string_f_mon (tk, date.month+1); {get 3-letter month abbreviation}
      write ((date.day+1):4, ' ', tk.str:tk.len, ent_p^.hours:6:1, ' h');
      if ent_p^.desc_p <> nil then begin
        write ('  - ', ent_p^.desc_p^.str:ent_p^.desc_p^.len);
        end;
      writeln;
      ent_p := ent_p^.nextcust_p;      {to next log entry for this customer}
      end;

    writeln ('  Total ', cust_p^.hours:6:1, ' hours');
    cust_p := cust_p^.next_p;          {to next customer in customers list}
    end;

  writeln;
  writeln (ncust, ' customers found');
  end;
