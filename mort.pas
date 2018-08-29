{   Program MORT <input file name>
*
*   Prints out info about a mortgage, given payment and interest history.
*   The input file name must end in .MORT, although this may be omitted on
*   the command line.
*
*   The input file contains a set of commands.  Commands start with a keyword
*   and may have parameters following them.  All keywords are case
*   insensitive.  These command names and parameters must be separated from
*   each other by one or more spaces.  Any character string parameters must be
*   enclosed in either quotes (""), or apostrophies ('') if they contain spaces
*   or the "/*" comment delimeter.  A command cannot span more than one line.
*
*   All blank lines are ignored.  End of line comments start with "/*".  In
*   other words, "/*" and all characters following on the same line are
*   ignored.
*
*   Valid input file commands are:
*
*     BORROW d
*
*       Indicate the number of dollars borrowed.  This sets the initial size
*       of the loan on the date specified by the DATE command if no PAY commands
*       have been given yet.  After the first PAY command, this indicates any
*       additional amount borrowed and will apply at the time of the previous
*       payment.
*
*     INT r
*
*       Indicate the current non-compounded annual interest rate in percent.
*       At least one of these command must precede the first PAY command.
*
*     DATE yyyy mm dd
*
*       Declares the date of the loan.  This is only used for reporting the
*       date of each transaction.  The year should be the full 4 digits, the
*       month should be 1-12, and DD is the day of the month.  The first
*       payment is assumed to be due one month after this date.
*       This command must precede any PAY and BORROW commands.
*
*     PAY d
*
*       Indicate the current monthly payment size in dollars.  By default,
*       this command also runs the calculation for one month of the mortgage.
*
*     RUN n
*
*       Explicitly set the number of months to run with the current conditions.
*       This command must appear after a PAY command on the same line.
*
*     PAY_INT d
*
*       Explicitly set the amount of the payment to be applied to the
*       outstanding accumulated interest instead of the principle.  By default,
*       as much as possible of the payment is applied to any outstanding
*       interest instead of principle.  It is an error to set this amount
*       greater than the total outstanding interest.  This command must appear
*       after a PAY command on the same line.
}
program mort;
%include 'base.ins.pas';

const
  max_msg_parms = 12;                  {max parameters we can pass to a message}

var
{
*   Variables used for I/O handling.
}
  ifnam:                               {input file name}
    %include '(cog)lib/string_treename.ins.pas';
  buf:                                 {one line input buffer}
    %include '(cog)lib/string132.ins.pas';
  iconn: file_conn_t;                  {input file connection handle}
{
*   Variables used for processing the command line and commands from the
*   input file.
}
  cmd:                                 {command name}
    %include '(cog)lib/string32.ins.pas';
  p_buf: string_index_t;               {parse index into input buffer}
  pick: sys_int_machine_t;             {number of token picked from list}
{
*   Current state of the mortgage.
}
  principle: double;                   {dollars currently outstanding}
  int_unpaid: double;                  {dollars interest currently unpaid}
  int_ytd: double;                     {year-to-date total interest paid}
  int_percent: double;                 {effective annual interest rate in percent}
  ifr_y, ifr_m: double;                {yearly and monthly interest fractions}
  pay_total: double;                   {total payment amount}
  pay_prin: double;                    {payment amount applied to priciple}
  pay_int: double;                     {payment amount applied to interest}
  r: double;                           {scratch floating point value}
  year, day, month: sys_int_machine_t; {date of next payment}
  n_year, n_month: sys_int_machine_t;  {number of years/months into mortgage}
  n_run: sys_int_machine_t;            {number of months to run}
  principle_set: boolean;              {TRUE if encountered BORROW command}
  ifr_set: boolean;                    {TRUE if encountered INT command}
  date_set: boolean;                   {TRUE if encountered DATE command}
  before_payments: boolean;            {TRUE if before first PAY command}
  pay_int_set: boolean;                {TRUE if PAY_INT command used}
  before_pay: boolean;                 {TRUE if before PAY command on line}
{
*   Temporary and scratch variables and constants.
}
  comment: string_var4_t               {end of line command start string}
    := [str := '/*', len := 2, max := sizeof(comment.str)];
  si: string_index_t;                  {scratch string index}
  i: sys_int_machine_t;                {loop counter}
  d, d2: double;                       {for intermediate calculations}
{
*   Variables used for handling errors.
}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_line, next_cmd, err_parm, err_after_pay, err_at_line, run_months, leave;
{
********************************
*
*   Local subroutine ROUND_CENTS (D)
*
*   Round the amount in dollars in D to the nearest cent.
}
procedure round_cents (
  in out  d: double);

var
  i: sys_int_max_t;

begin
  i := round(d * 100.0);
  d := i / 100.0;
  end;
{
********************************
*
*   Local subroutine YEARLY_SUMMARY
*
*   Write the year-end summary.
}
procedure yearly_summary;

begin
  sys_msg_parm_int (msg_parm[1], year);
  sys_msg_parm_fp2 (msg_parm[2], int_ytd);
  sys_message_parms ('mort_prog', 'yearly_summary', msg_parm, 2);
  end;
{
********************************
*
*   Start of main program.
}
begin
  string_cmline_init;                  {initialize command line for extracting tokens}

  string_cmline_token (ifnam, stat);   {get input file name from command line}
  string_cmline_req_check (stat);      {this command line argument is required}
  string_cmline_end_abort;             {there should be no more tokens on com line}
{
*   Now initialize for processing the commands from the input file.
}
  file_open_read_text (ifnam, '.mort', iconn, stat); {open input file for read}
  sys_msg_parm_vstr (msg_parm[1], ifnam);
  sys_error_abort (stat, 'file', 'open_input_read_text', msg_parm, 1);

  principle := 0.0;
  int_unpaid := 0.0;
  int_ytd := 0.0;
  int_percent := 0.0;
  ifr_m := 0.0;
  pay_total := 0.0;
  pay_int := 0.0;
  year := 0;
  day := 0;
  month := 0;
  n_year := 0;
  n_month := 0;
  principle_set := false;
  ifr_set := false;
  date_set := false;
  before_payments := true;
  pay_int_set := false;
{
*   Back here for each new command from the input file.
}
next_line:
  file_read_text (iconn, buf, stat);   {read next line from input file}
  if file_eof(stat) then goto leave;   {hit end of input file ?}
  sys_error_abort (stat, 'file', 'read_input_text', nil, 0);
  string_find (comment, buf, si);      {find comment start if there is one}
  if si > 0 then begin                 {SI is first character of comment ?}
    buf.len := si - 1;                 {truncate input line before comment}
    end;
  string_unpad (buf);                  {remove trailing blanks from input line}
  if buf.len <= 0 then goto next_line; {line line is empty ?}
  string_upcase (buf);                 {make all upper case for token matching}
  p_buf := 1;                          {init buffer parse index}
  n_run := 0;                          {reset number of months to run}
  before_pay := false;                 {reset to no PAY command yet this line}

next_cmd:                              {back here each new command on line}
  string_token (buf, p_buf, cmd, stat); {get next token from this input line}
  if string_eos(stat) then goto run_months; {read all commands on this line ?}
  if sys_error(stat) then begin
    sys_msg_parm_int (msg_parm[1], iconn.lnum);
    sys_msg_parm_vstr (msg_parm[2], iconn.tnam);
    sys_error_abort (stat, 'mort_prog', 'err_read', msg_parm, 2);
    end;

  string_tkpick80 (cmd,                {pick command name from list}
    'BORROW INT DATE PAY RUN PAY_INT',
    pick);
  case pick of
{
*   BORROW d
}
1: begin
  if not date_set then begin
    sys_message ('mort_prog', 'date_not_set');
    goto err_at_line;
    end;
  string_token_fp2 (buf, p_buf, r, stat); {grab the value into R}
  if sys_error(stat) then goto err_parm;
  round_cents (r);                     {round to the nearest cent}
  principle := principle + r;          {increase principle to include new amount borrowed}
  principle_set := true;

  pay_total := -r;
  pay_prin := -r;
  pay_int := 0.0;
  d := principle + int_unpaid;         {unpaid total}

  sys_msg_parm_int (msg_parm[1], n_year);
  sys_msg_parm_int (msg_parm[2], n_month);
  sys_msg_parm_fp2 (msg_parm[3], pay_total);
  sys_msg_parm_fp2 (msg_parm[4], pay_prin);
  sys_msg_parm_fp2 (msg_parm[5], pay_int);
  sys_msg_parm_fp2 (msg_parm[6], principle);
  sys_msg_parm_fp2 (msg_parm[7], int_unpaid);
  sys_msg_parm_fp2 (msg_parm[8], d);
  sys_msg_parm_fp2 (msg_parm[9], int_percent);
  sys_msg_parm_int (msg_parm[10], year);
  sys_msg_parm_int (msg_parm[11], month);
  sys_msg_parm_int (msg_parm[12], day);
  sys_message_parms ('mort_prog', 'borrow_data', msg_parm, 12);
  end;
{
*   INT r
}
2: begin
  string_token_fp2 (buf, p_buf, int_percent, stat);
  if sys_error(stat) then goto err_parm;
  ifr_y := int_percent / 100.0;        {convert from percent}
  ifr_m := ((1.0 + ifr_y) ** (1.0 / 12.0)) - 1.0;
  ifr_set := true;
  end;
{
*   DATE yyy mm dd
}
3: begin
  if date_set then begin
    sys_message ('mort_prog', 'date_date');
    goto err_at_line;
    end;
  if not before_payments then goto err_after_pay;
  string_token_int (buf, p_buf, year, stat);
  if sys_error(stat) then goto err_parm;
  string_token_int (buf, p_buf, month, stat);
  if sys_error(stat) then goto err_parm;
  string_token_int (buf, p_buf, day, stat);
  if
      (month < 1) or (month > 12) or
      (day < 1) or (day > 31)
    then goto err_parm;
  date_set := true;

  writeln;                             {write the initial columns header}
  sys_message ('mort_prog', 'header_year');
  end;
{
*   PAY d
}
4: begin
  if not principle_set then begin
    sys_message ('mort_prog', 'principle_not_set');
    goto err_at_line;
    end;
  if not ifr_set then begin
    sys_message ('mort_prog', 'interest_not_set');
    goto err_at_line;
    end;
  if not date_set then begin
    sys_message ('mort_prog', 'date_not_set');
    goto err_at_line;
    end;
  before_payments := false;
  string_token_fp2 (buf, p_buf, pay_total, stat);
  if sys_error(stat) then goto err_parm;
  round_cents (pay_total);
  pay_int_set := false;                {reset to no PAY_INT command given}
  n_run := 1;                          {set default number of months to run}
  before_pay := false;
  end;
{
*   RUN n
}
5: begin
  if before_pay then begin
    sys_message ('mort_prog', 'run_before_pay');
    goto err_at_line;
    end;
  string_token_int (buf, p_buf, n_run, stat);
  end;
{
*   PAY_INT d
}
6: begin
  string_token_fp2 (buf, p_buf, pay_int, stat);
  if sys_error(stat) then goto err_parm;
  round_cents (pay_int);
  pay_int_set := true;
  end;
{
*   Illegal command.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], cmd);
    sys_message_parms ('mort_prog', 'command_bad', msg_parm, 1);
    goto err_at_line;
    end;                               {end of command name cases}

  if not sys_error(stat) then goto next_cmd; {no errors with this command ?}

err_parm:
  sys_msg_parm_vstr (msg_parm[1], cmd);
  sys_message_parms ('mort_prog', 'parm_bad', msg_parm, 1);
  goto err_at_line;

err_after_pay:
  sys_msg_parm_vstr (msg_parm[1], cmd);
  sys_message_parms ('mort_prog', 'err_after_pay', msg_parm, 1);
  goto err_at_line;

err_at_line:
  sys_msg_parm_int (msg_parm[1], iconn.lnum);
  sys_msg_parm_vstr (msg_parm[2], iconn.tnam);
  sys_message_bomb ('mort_prog', 'err_at_line', msg_parm, 2);
{
*   All done reading the commands from one line.  Now run the mortgage for
*   N_RUN months.
}
run_months:
  for i := 1 to n_run do begin         {once for each month to run}
    if (principle + int_unpaid) < 0.005 then goto leave; {mortgage all paid off ?}

    n_month := n_month + 1;            {one more month into mortgage}
    if n_month >= 12 then begin        {another whole year ?}
      n_month := n_month - 12;
      n_year := n_year + 1;
      end;

    month := month + 1;                {update current month}
    if month > 12 then begin           {just went from December to January ?}
      month := month - 12;
      year := year + 1;
      int_ytd := 0.0;                  {reset year-to-date interest paid}
      end;

    d := principle * ifr_m;            {interest from principle}
    round_cents (d);
    d2 := int_unpaid * ifr_m;          {interest from unpaid interest}
    round_cents (d2);
    int_unpaid := int_unpaid + d + d2;
    round_cents (int_unpaid);

    if pay_int_set
      then begin                       {amount of interest payment explicitly set}
        if                             {check amount for validity}
            (pay_int > int_unpaid) or
            (pay_int < 0.0) or
            (pay_int > pay_total)
            then begin
          sys_message ('mort_prog', 'pay_int_out_of_range');
          goto err_at_line;
          end;
        end
      else begin                       {pick interest amount automatically}
        pay_int := min(pay_total, int_unpaid);
        end
      ;

    round_cents (pay_int);
    pay_prin := min(principle, pay_total - pay_int); {payment towards principle}
    round_cents (pay_prin);
    pay_total := pay_prin + pay_int;   {recalculate total payment}
{
*   Everything is up to date for this month.  Now do the payment.
}
    int_unpaid := int_unpaid - pay_int; {pay off the interest}
    round_cents (int_unpaid);
    principle := principle - pay_prin; {pay off the principle}
    round_cents (principle);
    int_ytd := int_ytd + pay_int;      {keep track of year-to-date interest paid}

    if month = 1 then begin            {write new columns header ?}
      writeln;
      sys_message ('mort_prog', 'header_year');
      end;

    d := principle + int_unpaid;       {unpaid total}

    sys_msg_parm_int (msg_parm[1], n_year);
    sys_msg_parm_int (msg_parm[2], n_month);
    sys_msg_parm_fp2 (msg_parm[3], pay_total);
    sys_msg_parm_fp2 (msg_parm[4], pay_prin);
    sys_msg_parm_fp2 (msg_parm[5], pay_int);
    sys_msg_parm_fp2 (msg_parm[6], principle);
    sys_msg_parm_fp2 (msg_parm[7], int_unpaid);
    sys_msg_parm_fp2 (msg_parm[8], d);
    sys_msg_parm_fp2 (msg_parm[9], int_percent);
    sys_msg_parm_int (msg_parm[10], year);
    sys_msg_parm_int (msg_parm[11], month);
    sys_msg_parm_int (msg_parm[12], day);
    sys_message_parms ('mort_prog', 'month_data', msg_parm, 12);

    if month = 12 then begin           {write summary at end of year}
      yearly_summary;
      end;
    end;                               {back to process next month}
  goto next_line;                      {back for line from input file}
{
*   Common non-error exit point.  We either hit end of input file or paid
*   off the mortgage.
}
leave:
  file_close (iconn);                  {close input file}
  if                                   {write a summary statement for partial year ?}
      (month <> 12) and                {not already write summary ?}
      ((n_year <> 0) or (n_month <> 0)) {actually did something to summarize ?}
      then begin
    yearly_summary;
    end;
  end.
