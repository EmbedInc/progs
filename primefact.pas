{   Program PRIMEFACT integer
*
*   Show all the prime factor of the integer on the command line.
}
program primefact;
%include 'base.ins.pas';

const
  maxf = 46340;                        {max possible factor (sqrt of largest int)}

var
  ii: sys_int_machine_t;               {the integer to find factors of}
  pr: sys_int_machine_t;               {prime number}
  npf: sys_int_machine_t;              {number of different primes factors found}
  stat: sys_err_t;
{
********************************************************************************
*
*   Subroutine DOPRIME
*
*   Check the number in II against the possible prime factor PR.  Results are
*   reported on standard output.
}
procedure doprime;                     {check II against prime factor PR}
  val_param; internal;

var
  nf: sys_int_machine_t;               {number of times PR is a factor of II}
  qu: sys_int_machine_t;               {quotient of II div PR}

begin
  nf := 0;                             {init to PR is not a factor of II}

  while true do begin                  {back here each factor of PR}
    qu := ii div pr;                   {try to find factor of PR}
    if (qu * pr) <> ii then exit;      {PR is not a factor of II ?}
    nf := nf + 1;                      {count one more time PR was a factor}
    ii := qu;                          {update number with this factor removed}
    end;

  if nf > 0 then begin                 {PR was a factor at all ?}
    if npf = 0
      then write (' =')
      else write (' *');
    npf := npf + 1;                    {count one more prime factor}
    write (' ', pr);
    if nf > 1 then begin
      write ('^', nf);
      end;
    end;
  end;
{
********************************************************************************
*
*   Function ISPRIME (PR)
*
*   Returns TRUE iff PR is prime.  PR must be odd.
}
function isprime (                     {check whether number is prime}
  in      pr: sys_int_machine_t)       {the number to check}
  :boolean;                            {the number is prime}
  val_param; internal;

var
  fc: sys_int_machine_t;               {candidate factor}

label
  prime;

begin
  isprime := false;                    {init to number is not prime}
  if sqr(3) > pr then goto prime; if ((pr div 3) * 3) = pr then return;
  if sqr(5) > pr then goto prime; if ((pr div 5) * 5) = pr then return;
  if sqr(7) > pr then goto prime; if ((pr div 7) * 7) = pr then return;
  if sqr(11) > pr then goto prime; if ((pr div 11) * 11) = pr then return;
  if sqr(13) > pr then goto prime; if ((pr div 13) * 13) = pr then return;
  if sqr(17) > pr then goto prime; if ((pr div 17) * 17) = pr then return;
  if sqr(19) > pr then goto prime; if ((pr div 19) * 19) = pr then return;
  if sqr(23) > pr then goto prime; if ((pr div 23) * 23) = pr then return;
  if sqr(29) > pr then goto prime; if ((pr div 29) * 29) = pr then return;
  if sqr(31) > pr then goto prime; if ((pr div 31) * 31) = pr then return;
  if sqr(37) > pr then goto prime; if ((pr div 37) * 37) = pr then return;
  if sqr(41) > pr then goto prime; if ((pr div 41) * 41) = pr then return;
  if sqr(43) > pr then goto prime; if ((pr div 43) * 43) = pr then return;
  if sqr(47) > pr then goto prime; if ((pr div 47) * 47) = pr then return;
  if sqr(53) > pr then goto prime; if ((pr div 53) * 53) = pr then return;
  if sqr(59) > pr then goto prime; if ((pr div 59) * 59) = pr then return;
  if sqr(61) > pr then goto prime; if ((pr div 61) * 61) = pr then return;
  if sqr(67) > pr then goto prime; if ((pr div 67) * 67) = pr then return;
  if sqr(71) > pr then goto prime; if ((pr div 71) * 71) = pr then return;
  if sqr(73) > pr then goto prime; if ((pr div 73) * 73) = pr then return;
  if sqr(79) > pr then goto prime; if ((pr div 79) * 79) = pr then return;
  if sqr(83) > pr then goto prime; if ((pr div 83) * 83) = pr then return;
  if sqr(89) > pr then goto prime; if ((pr div 89) * 89) = pr then return;
  if sqr(97) > pr then goto prime; if ((pr div 97) * 97) = pr then return;

  fc := 101;                           {init next factor to try}
  while sqr(fc) <= pr do begin         {past square root, all factors tried ?}
    if ((pr div fc) * fc) = pr then return;
    fc := fc + 2;
    end;

prime:
  isprime := true;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token_int (ii, stat);  {get the integer to find factors of}
  string_cmline_req_check (stat);      {the command line parameter is required}
  string_cmline_end_abort;             {no more command line parameters allowed}

  if ii < 2 then begin
    writeln ('Value is not 2 or more');
    sys_bomb;
    end;

  write (ii);                          {show the number to be factored}
  npf := 0;                            {init to no prime factors found}

  pr := 2;                             {init to first prime to check against}
  doprime;                             {check against this prime}

  pr := 3;                             {init candidate prime}
  while sqr(pr) <= ii do begin         {exhausted all prime factors except itself ?}
    if pr > maxf then exit;            {past largest possible factor ?}
    if isprime (pr) then begin         {this is a prime number ?}
      doprime;                         {check for factors of this prime}
      end;
    pr := pr +2;                       {make next candidate prime}
    end;                               {back to try with this new candidate prime}

  if ii > 1 then begin                 {II is the last prime ?}
    if npf = 0
      then begin                       {no factors found, the original II is prime}
        writeln (' is prime');
        end
      else begin                       {the original number was not prime}
        pr := ii;
        doprime;
        writeln;
        end;
      ;
    end;
  end;
