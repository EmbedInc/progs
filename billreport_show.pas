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
  currday: sys_date_t;                 {date of current day}
  dayh: real;                          {hours worked in curr day for curr cust}
  havecurr: boolean;                   {CURRDAY is valid}
  firstdent: boolean;                  {at first entry in current day}
{
********************************************************************************
*
*   Local subroutine NEW_DAY
*
*   Update the state to start a new day for the current customer.
}
procedure new_day;
  val_param; internal;

begin
  currday := date;                     {save date of this day}
  havecurr := true;                    {current date is set}
  dayh := 0.0;                         {init hours worked in this day}
  firstdent := true;                   {now at first entry in the current day}
  end;
{
********************************************************************************
*
*   Local subroutine SHOW_DAY
*
*   Show the total hours worked in the current day.  Nothing is done if there is
*   no current day.
}
procedure show_day;
  val_param; internal;

begin
  if not havecurr then return;         {there is no current day state ?}

  writeln ('        ', dayh:6:1, ' total');
  writeln;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  tk.max := size_char(tk.str);         {init local var string}
  ncust := 0;                          {init number of customers reported on}
  sys_timezone_here (                  {get info for our time zone here}
    tzone, hours_west, daysave);

  cust_p := cust_first_p;              {init to first customer in the list}
  while cust_p <> nil do begin         {scan the customer list}
    havecurr := false;                 {don't have current day for this cust yet}
    ncust := ncust + 1;
    writeln;
    writeln (cust_p^.name_p^.str:cust_p^.name_p^.len); {show customer name}

    ent_p := cust_p^.first_p;          {to first log entry this customer}
    while ent_p <> nil do begin        {scan the log entries for this customer}
      sys_clock_to_date (              {make expanded date/time for this log entry}
        ent_p^.time,                   {time to expand}
        tzone, hours_west, daysave,    {target time zone}
        date);                         {returned expanded date/time}

      if not havecurr then begin       {this is first day for this customer ?}
        new_day;                       {init current day to this day}
        end;
      if                               {starting a new day ?}
          (date.year <> currday.year) or
          (date.month <> currday.month) or
          (date.day <> currday.day)
          then begin
        show_day;                      {show total hours this day}
        new_day;                       {set up state for new day}
        end;
      dayh := dayh + ent_p^.hours;     {update hours in the current day}

      if firstdent
        then begin                     {this is first entry for this day}
          string_f_mon (tk, date.month+1); {get 3-letter month abbreviation}
          write ((date.day+1):4, ' ', tk.str:tk.len);
          end
        else begin                     {subsequent entry for current day}
          write ('        ');
          end
        ;
      write (ent_p^.hours:6:1, ' h');
      if ent_p^.desc_p <> nil then begin
        write ('  - ', ent_p^.desc_p^.str:ent_p^.desc_p^.len);
        end;
      if ent_p^.next_p = nil then begin {this entry not ended ?}
        write (' (ongoing)');
        end;
      writeln;
      ent_p := ent_p^.nextcust_p;      {to next log entry for this customer}
      firstdent := false;              {no longer at first entry for current day}
      end;
    show_day;                          {show hours for last day, if any}

    writeln ('  Total ', cust_p^.hours:6:1, ' hours');
    cust_p := cust_p^.next_p;          {to next customer in customers list}
    end;

  writeln;
  writeln (ncust, ' customers found');
  end;
