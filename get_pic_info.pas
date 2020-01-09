{   Program GET_PIC_INFO picname [options]
*
*   Write information about the indicated PIC to standard output.
}
program get_pic_info;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';
%include 'file.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

type
  show_k_t = (                         {IDs for what info to show}
    show_all_k,                        {show all pieces of info}
    show_fam_k,                        {show only bare family name}
    show_class_k,                      {show only bare class name}
    show_subclass_k);                  {show only bare subclass name}

var
  show: show_k_t;                      {ID for what to show}
  pic:                                 {full upper case PIC name, like "16F876" or "30F2010"}
    %include '(cog)lib/string32.ins.pas';
  p, p2: string_index_t;               {scratch string index}
  fam: sys_int_machine_t;              {initial PIC family number, like 12 16 33, etc}
  famstr:                              {PIC family type, like "12", "16", "16E", "33", etc}
    %include '(cog)lib/string32.ins.pas';
  ptype:                               {PIC memory type designator like "F", "C", "J"}
    %include '(cog)lib/string32.ins.pas';
  pnum:                                {full name within family, like "876A"}
    %include '(cog)lib/string32.ins.pas';
  picnum: sys_int_machine_t;           {bare number of PIC within family}
  class:                               {PIC class, like "PIC" or "dsPIC"}
    %include '(cog)lib/string32.ins.pas';
  subclass:                            {subclass, usually first letter of PTYPE, like C, F, or H}
    %include '(cog)lib/string32.ins.pas';
  famenh: boolean;                     {"enhanced" version of the current family}
  lcase: boolean;                      {make output lower case}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, done_opt, err_parm, parm_bad, done_opts,
  invalid, fndfam;

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (pic, stat);     {get PIC name}
  string_cmline_req_check (stat);      {this command line token is required}
  string_upcase (pic);                 {save PIC name in upper case}

  show := show_all_k;                  {init to show all pieces of information}
  lcase := false;                      {init output to upper case}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-FAM -CLASS -SCLASS -L',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -FAM
}
1: begin
  show := show_fam_k;
  end;
{
*   -CLASS
}
2: begin
  show := show_class_k;
  end;
{
*   -SUBCLASS
}
3: begin
  show := show_subclass_k;
  end;
{
*   -L
}
4: begin
  lcase := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

done_opt:                              {done handling this command line option}

err_parm:                              {jump here on error with parameter}
  string_cmline_parm_check (stat, opt); {check for bad command line option parameter}
  goto next_opt;                       {back for next command line option}

parm_bad:                              {jump here on got illegal parameter}
  string_cmline_reuse;                 {re-read last command line token next time}
  string_cmline_token (parm, stat);    {re-read the token for the bad parameter}
  sys_msg_parm_vstr (msg_parm[1], parm);
  sys_msg_parm_vstr (msg_parm[2], opt);
  sys_message_bomb ('string', 'cmline_parm_bad', msg_parm, 2);

done_opts:                             {done with all the command line options}
{
*   All done reading the command line.
}
  if pic.len < 3 then begin            {PIC name too small to be valid ?}
invalid:                               {complain about invalid PIC name and bomb}
    writeln ('The PIC name "', pic.str:pic.len, '" is not valid.');
    sys_bomb;
    end;
{
*   Extract leading PIC family number into FAM.
}
  famenh := false;                     {init to this is not extended version of family}

  for p := 1 to pic.len do begin
    if (pic.str[p] < '0') or (pic.str[p] > '9') {this char not a digit ?}
      then goto fndfam;
    end;
  goto invalid;                        {all digits is not valid PIC name}
fndfam:                                {P is index of first non-digit char}
  if p = 1 then goto invalid;          {no leading family number ?}
  string_substr (pic, 1, p-1, opt);    {extract family number string into OPT}
  string_t_int (opt, fam, stat);       {convert to integer prefix number}
  if sys_error(stat) then goto invalid;
{
*   P is the index of the first char in PIC past the leading family number.
*
*   Get the PIC memory type designator into PTYPE.  This is the "F" in 16F876
*   for example.
}
  ptype.len := 0;
  while (pic.str[p] < '0') or (pic.str[p] > '9') {scan forward until first digit}
      do begin
    string_append1 (ptype, pic.str[p]); {add this char to mem type designator string}
    p := p + 1;                        {advance to next character}
    if p > pic.len then goto invalid;  {no number in rest of string ?}
    end;

  string_substr (ptype, 1, 1, subclass); {extract subclass name}
{
*   P is the index of the first char in PIC past the memory type designator
*   string.  The character at P is guaranteed to be a digit, and P is guaranteed
*   to be within the string.
*
*   Extract the model number string within the family, and the integer model
*   number with any suffix removed.
}
  string_substr (pic, p, pic.len, pnum); {extract full model number within family string}

  p2 := p;                             {save start index of number}
  while                                {scan forwards to end of string or first non-digit}
      (p <= pic.len) and               {still within the string ?}
      ((pic.str[p] >= '0') and (pic.str[p] <= '9')) {this char is a digit ?}
      do begin
    p := p + 1;
    end;
  string_substr (pic, p2, p - 1, opt); {extract just the number string}
  string_t_int (opt, picnum, stat);    {convert to integer number in PICNUM}
  if sys_error(stat) then goto invalid;
{
*   Adjust the family number so that 12 means the 12 bit core and 16 means the
*   14 bit core.
}
  if fam = 12 then begin               {original family number is 12 ?}
    case picnum of                     {check for special cases}
629, 635, 675, 683: fam := 16;         {these are really 14 bit core}
      end;
    end;

  if fam = 10 then fam := 12;          {PIC10 uses the 12 bit core}

  if fam = 16 then begin
    case picnum of
54, 55, 56, 57, 58, 59, 505, 506, 540: fam := 12; {really 12 bit core}
      end;
    end;

  famenh :=                            {special "enhanced" PIC 16 ?}
    (fam = 16) and (pnum.str[1] = '1');

 string_f_int (famstr, fam);           {init family string}
 if famenh then begin                  {"enhanced" version of this family ?}
   string_append1 (famstr, 'E');
   end;
{
*   Determine the PIC class.
}
  case fam of
24, 30, 33: string_vstring (class, 'dsPIC'(0), -1);
otherwise
    string_vstring (class, 'PIC'(0), -1);
    end;
{
*   Convert all results to lower case if so directed on the command line.  This
*   is indicated by LCASE being TRUE.
}
  if lcase then begin                  {make all results lower case ?}
    string_downcase (pic);
    string_downcase (famstr);
    string_downcase (ptype);
    string_downcase (pnum);
    string_downcase (class);
    string_downcase (subclass);
    end;
{
*   Show the results.
}
  case show of

show_all_k: begin
      writeln ('PIC ', pic.str:pic.len, ':');
      writeln ('  Family   ', famstr.str:famstr.len);
      writeln ('  Memory   ', ptype.str:ptype.len);
      writeln ('  Number   ', picnum, ', subname ', pnum.str:pnum.len);
      writeln ('  Class    ', class.str:class.len);
      writeln ('  Subclass ', subclass.str:subclass.len);
      end;

show_fam_k: begin
      writeln (famstr.str:famstr.len);
      end;

show_class_k: begin
      writeln (class.str:class.len);
      end;

show_subclass_k: begin
      writeln (subclass.str:subclass.len);
      end;

    end;
  end.
