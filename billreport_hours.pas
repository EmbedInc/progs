module billreport_hours;
define hours_make;
%include 'billreport.ins.pas';
{
********************************************************************************
*
*   Subroutine HOURS_MAKE
*
*   Compute the hours for each log entry, and the total for each customer.
}
procedure hours_make;                  {compute hours, log entries and customers}
  val_param;

var
  ent_p: entry_p_t;                    {to current log entry}
  endt: sys_clock_t;                   {work period ending time}
  dt: double;                          {seconds of work time}
  cust_p: cust_p_t;                    {to current customer list entry}

label
  next_ent;

begin
{
*   Compute the hours for each individual log entry.  A log entry only has hours
*   when it is for a specific customer.
}
  ent_p := log_first_p;                {init to first log entry}
  while ent_p <> nil do begin          {scan the list of log entries}
    if ent_p^.cust_p = nil then begin  {this entry is for ending a work period ?}
      ent_p^.hours := 0.0;
      goto next_ent;
      end;

    if ent_p^.next_p = nil
      then begin                       {at last entry in list}
        endt := sys_clock;             {assume work still ongoing until now}
        end
      else begin                       {there is a next entry}
        endt := ent_p^.next_p^.time;   {get time work for this entry stopped}
        end
      ;

    dt := sys_clock_to_fp2 (           {make seconds of work time this entry}
      sys_clock_sub (endt, ent_p^.time) );
    ent_p^.hours := dt / 3600.0;       {save hours work time this log entry}

next_ent:
    ent_p := ent_p^.next_p;            {to next entry in log}
    end;                               {back to process this next log entry}
{
*   Update the accumulated hours for each customer.
}
  cust_p := cust_first_p;              {init to first customer list entry}
  while cust_p <> nil do begin         {scan the customer list entries}
    cust_p^.hours := 0.0;              {init accumulated hours}
    ent_p := cust_p^.first_p;          {to first log entry for this customer}
    while ent_p <> nil do begin        {scan the log entries for this customer}
      cust_p^.hours := cust_p^.hours + ent_p^.hours; {add hours from this entry}
      ent_p := ent_p^.nextcust_p;      {to next log entry for this customer}
      end;
    cust_p := cust_p^.next_p;          {to next customer in list}
    end;

  end;
