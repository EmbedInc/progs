{   Program CARCOST
*
*   Calculate the present cost of a car including its purchase prices and cost
*   of fuel over its lifetime.
}
program carcost;
%include 'base.ins.pas';

const
  max_miles = 200000;                  {miles limit to calculate to}
  max_years = 15;                      {years limit to calculate to}

var
{
*   Input parameters.
}
  doll_purch: real;                    {initial purchase price}
  mpg_city: real;                      {miles/gallon, city driving}
  mpg_hwy: real;                       {miles/gallon, highway driving}
  frac_city: real;                     {0-1 fraction of total driving in city}
  miles_month: sys_int_machine_t;      {miles driven per month}
  doll_gal: real;                      {dollars/gallon of gasoline}
  eay: real;                           {money effective annual yield, mult factor}
{
*   Calculated values.
}
  gal_month: real;                     {gallons fuel used per month}
  doll_month: real;                    {dollars/month for fuel}
  emy: double;                         {effective monthly money yeild, mult factor}
{
*   Running values.
}
  years: sys_int_machine_t;            {years since purchase}
  miles: sys_int_machine_t;            {accumulated miles}
  doll_yield: double;                  {accumulated money yield, mult factor}
  costy: double;                       {additional present cost in current year}
  cost: double;                        {total accumulated cost}
  m: sys_int_machine_t;                {month loop counter}

  r: real;                             {scratch floating point}
  buf:                                 {one line input buffer}
    %include '(cog)lib/string256.ins.pas';
  stat: sys_err_t;                     {completion status}
{
********************************************************************************
*
*   Local subroutine SHOW_STATE
*
*   Show the current running computed state.  This writes one line to the
*   output.
}
procedure show_state;                  {show current state on one line}
  internal; val_param;

var
  buf: string_var132_t;                {output buffer}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;                     {completion status}

begin
  buf.max := size_char(buf.str);       {init local var strings}
  tk.max := size_char(tk.str);

  buf.len := 0;                        {init output line to empty}

  string_appends (buf, '  '(0));
  string_f_intrj (tk, years, 5, stat); {make years string}
  sys_error_abort (stat, '', '', nil, 0);
  string_append (buf, tk);

  string_appends (buf, '  '(0));
  string_f_fp (                        {make miles string}
    tk,                                {output string}
    miles,                             {input value}
    7,                                 {field width}
    0,                                 {free form exponent field, not used}
    0,                                 {minimum significant digits required}
    6,                                 {max digits allowed left of point}
    0, 0,                              {min/max digits right of point}
    [ string_ffp_exp_no_k,             {exponential notation not allowed}
      string_ffp_group_k],             {write digits group character}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_append (buf, tk);

  string_appends (buf, '  '(0));
  string_f_fp (                        {make dollars this year string}
    tk,                                {output string}
    costy,                             {input value}
    14,                                {field width}
    0,                                 {free form exponent field, not used}
    0,                                 {minimum significant digits required}
    11,                                {max digits allowed left of point}
    0, 0,                              {min/max digits right of point}
    [ string_ffp_exp_no_k,             {exponential notation not allowed}
      string_ffp_group_k],             {write digits group character}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_append (buf, tk);

  string_appends (buf, '  '(0));
  string_f_fp (                        {make accumulated dollars string}
    tk,                                {output string}
    cost,                              {input value}
    9,                                 {field width}
    0,                                 {free form exponent field, not used}
    0,                                 {minimum significant digits required}
    7,                                 {max digits allowed left of point}
    0, 0,                              {min/max digits right of point}
    [ string_ffp_exp_no_k,             {exponential notation not allowed}
      string_ffp_group_k],             {write digits group character}
    stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_append (buf, tk);

  writeln (buf.str:buf.len);
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
{
*   Get the input information from the user.
}
  string_prompt (string_v('Purchase price ($): '(0)));
  string_readin (buf);
  string_t_fpm (buf, doll_purch, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_prompt (string_v('Miles/gallon in city: '(0)));
  string_readin (buf);
  string_t_fpm (buf, mpg_city, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_prompt (string_v('Miles/gallon on highway: '(0)));
  string_readin (buf);
  string_t_fpm (buf, mpg_hwy, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_prompt (string_v('Percent of driving in city: '(0)));
  string_readin (buf);
  string_t_fpm (buf, r, stat);
  sys_error_abort (stat, '', '', nil, 0);
  frac_city := r / 100.0;

  string_prompt (string_v('Miles/month: '(0)));
  string_readin (buf);
  string_t_int (buf, miles_month, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_prompt (string_v('$/gallon for fuel: '(0)));
  string_readin (buf);
  string_t_fpm (buf, doll_gal, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_prompt (string_v('Effective annual yield above inflation (percent): '(0)));
  string_readin (buf);
  string_t_fpm (buf, r, stat);
  sys_error_abort (stat, '', '', nil, 0);
  eay := 1.0 + (r / 100.0);
{
*   Compute static derived values.
}
  r := miles_month * frac_city;        {city miles/month}
  gal_month := r / mpg_city;           {gallons/month from city driving}
  r := miles_month - r;                {highway miles/month}
  gal_month := gal_month + (r / mpg_hwy); {add in gallons/month from highway driving}

  doll_month := gal_month * doll_gal;  {dollars/month for fuel}

  emy := eay ** (1.0 / 12.0);          {effective monthly yield, mult factor}
{
*   Write header for running output values.
}
  writeln;
  writeln ('  Years    Miles  Present $/year  Present $');
  writeln ('  -----  -------  --------------  ---------');
{
*   Loop per month until either the maximum miles or years limit.
}
  miles := 0;                          {init accumulated miles}
  doll_yield := sqrt(emy);             {init dollar yield to half way into first month}
  costy := 0.0;                        {init running costs this year}
  cost := doll_purch;                  {init accumulated cost to purchase price}
  years := 0;                          {init years from purchase}
  show_state;                          {show starting state}

  for years := 1 to max_years do begin {up to maximum allowed years}
    costy := 0.0;                      {init accumulated costs this year}
    for m := 1 to 12 do begin          {once for each month in this year}
      miles := miles + miles_month;    {update total miles to include this month}
      costy := costy + (doll_month / doll_yield); {add present value cost for this month}
      doll_yield := doll_yield * emy;  {update discount rate for next month}
      end;                             {back to do next month this year}
    cost := cost + costy;              {update total cost to include this year}
    show_state;                        {show the results after this year}
    if miles >= max_miles then exit;   {quit if reached miles limit}
    end;                               {back to do next year}
  end.
