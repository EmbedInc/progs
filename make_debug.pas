{   Program MAKE_DEBUG filename [name ... name]
*
*   Write scripts to set various debug switches according to the command line
*   and the DEBUG environment variable.
}
program make_debug;
%include 'base.ins.pas';

type
  fmt_k_t = (                          {output file format ID}
    fmt_bat_k,                         {Windows CMD batch script}
    fmt_prepic_k,                      {Embed PIC preprocessor}
    fmt_pas_k,                         {Pascal}
    fmt_c_k,                           {C language}
    fmt_escr_k,                        {Embed ESCR script}
    fmt_txt_k);                        {text file}

  dopt_p_t = ^dopt_t;
  dopt_t = record                      {info about one debug option}
    next_p: dopt_p_t;                  {points to next option in the list}
    uname: string_var32_t;             {constant name, upper case}
    lname: string_var32_t;             {constant name, lower case}
    enab: boolean;                     {this option is enabled}
    end;

var
  fnam:                                {output file name}
    %include '(cog)lib/string_treename.ins.pas';
  format: fmt_k_t;                     {output file format}
  opt:                                 {raw option name}
    %include '(cog)lib/string32.ins.pas';
  name:                                {full debug option constant name}
    %include '(cog)lib/string32.ins.pas';
  str:                                 {scratch string}
    %include '(cog)lib/string132.ins.pas';
  p: string_index_t;                   {parse index}
  mem_p: util_mem_context_p_t;         {points to our private mem context}
  opt_list_p: dopt_p_t;                {points to start of options list}
  opt_last_p: dopt_p_t;                {points to last option in list}
  opt_p: dopt_p_t;                     {points to current list entry}
  conn: file_conn_t;                   {connection to the output file}
  pick: sys_int_machine_t;             {number of option picked from list}
  obuf:                                {one line output buffer}
    %include '(cog)lib/string132.ins.pas';
  ndbg: sys_int_machine_t;             {number of options found in DEBUG var}
  dbg_off: boolean;                    {debugging is globally disabled}
  dbg_any: boolean;                    {at least one debug option is enabled}
  stat: sys_err_t;                     {completion status}
{
********************************************************************************
*
*   Function ENTRY_FIND (NAME)
*
*   Returns the pointer to the debug options list entry NAME.  NAME must be
*   upper case.  NIL is returned if no entry with name NAME exists.
}
function entry_find (                  {find debug options list entry}
  in      name: string_var32_t)        {name of entry to look for, upper case}
  :dopt_p_t;                           {pointer to the existing entry, NIL if none}

var
  opt_p: dopt_p_t;                     {pointer to current entry}

begin
  entry_find := nil;                   {init to no such list entry found}

  opt_p := opt_list_p;                 {init to first list entry}
  while opt_p <> nil do begin          {back here each new list entry}
    if string_equal(opt_p^.uname, name) then begin {found existing option ?}
      entry_find := opt_p;             {return pointer to the existing list entry}
      return;
      end;
    opt_p := opt_p^.next_p;            {advance to next option in the list}
    end;
  end;
{
********************************************************************************
*
*   Function ENTRY_NEW (NAME)
*
*   Create the new list entry with the name NAME, and return the pointer to it.
*   NAME is assumed to be upper case.
}
function entry_new (                   {create new debug options list entry}
  in      name: string_var32_t)        {name of entry to look for, upper case}
  :dopt_p_t;                           {pointer to the new list entry}

var
  opt_p: dopt_p_t;                     {pointer to current entry}

begin
  util_mem_grab (                      {allocate memory for new list entry}
    sizeof(opt_p^), mem_p^, false, opt_p);

  opt_p^.next_p := nil;                {fill in this new list entry}
  opt_p^.uname.max := size_char(opt_p^.uname.str); {upper case name}
  string_copy (name, opt_p^.uname);
  opt_p^.lname.max := size_char(opt_p^.lname.str); {lower case name}
  string_copy (name, opt_p^.lname);
  string_downcase (opt_p^.lname);

  opt_p^.enab := false;                {init this debug option to disabled}

  if opt_last_p = nil
    then begin                         {this is first list entry}
      opt_list_p := opt_p;
      end
    else begin                         {adding to end of existing list}
      opt_last_p^.next_p := opt_p;
      end
    ;
  opt_last_p := opt_p;                 {update pointer to last entry in list}

  entry_new := opt_p;                  {return pointer to the new list entry}
  end;
{
********************************************************************************
*
*   Function ENTRY (NAME)
*
*   Return the pointer to the debug options list entry with the name NAME.  If
*   the entry does not exist, then it is created and the enable state
*   initialized to FALSE.
}
function entry (                       {get pointer to debug options list entry}
  in      name: string_var32_t)        {name of entry to look for, upper case}
  :dopt_p_t;                           {pointer to the new list entry}

var
  opt_p: dopt_p_t;                     {pointer to current entry}

begin
  opt_p := entry_find (name);          {get pointer to existing entry, if exists}
  if opt_p = nil then begin            {no entry of this name exists ?}
    opt_p := entry_new (name);         {create new entry, get pointer to it}
    end;

  entry := opt_p;                      {return pointer to the entry}
  end;
{
********************************************************************************
*
*   Subroutine WVSTR (VSTR)
*
*   Write the var-string VSTR to the current output line.
}
procedure wvstr (                      {write vstring to output}
  in      vstr: univ string_var_arg_t); {the string to write}
  val_param; internal;

begin
  string_append (obuf, vstr);
  end;
{
********************************************************************************
*
*   Subroutine WSTR (STR)
*
*   Write the Pascal string STR to the current output line.
}
procedure wstr (                       {write Pascal string to output}
  in      str: string);                {the string to write}
  val_param; internal;

begin
  string_appends (obuf, str);
  end;
{
********************************************************************************
*
*   Subroutine WLINE
*
*   End the current output line and write it to the file.  The output line
*   buffer is reset to empty.
}
procedure wline;                       {write current output line to output file}
  val_param; internal;

var
  stat: sys_err_t;                     {completion status}

begin
  file_write_text (obuf, conn, stat);  {do the write}
  sys_error_abort (stat, '', '', nil, 0);
  obuf.len := 0;                       {init the next output line to empty}
  end;
{
********************************************************************************
*
*   Subroutine WRITE_START
*
*   Write any special content before all the debug constants are defined.
}
procedure write_start;                 {write at start of output file}
  val_param; internal;

begin
  obuf.len := 0;                       {init the output buffer to empty}

  case format of                       {what is the output format}

fmt_pas_k: begin                       {Pascal}
      wstr ('const');
      end;

    end;

  if obuf.len > 0 then wline;          {write output, if any}
  end;
{
********************************************************************************
*
*   Subroutine WRITE_OPT (OPT)
*
*   Write the debug option OPT to the output file.
}
procedure write_opt (                  {write definition of one debug option}
  in      opt: dopt_t);                {the debug option to write}
  val_param; internal;

begin
  case format of                       {which output format to write in ?}

fmt_bat_k: begin                       {.BAT file}
      wstr ('set ');
      wvstr (opt.uname);
      wstr ('=');
      if opt.enab
        then wstr ('true')
        else wstr ('false');
      end;

fmt_prepic_k: begin                    {prepic source}
      wstr ('/const ');
      wvstr (opt.lname);
      wstr (' bool = ');
      if opt.enab
        then wstr ('True')
        else wstr ('False');
      end;

fmt_pas_k: begin                       {Pascal}
      wstr ('  ');
      wvstr (opt.lname);
      wstr (' = ');
      if opt.enab
        then wstr ('true')
        else wstr ('false');
      wstr (';');
      end;

fmt_c_k: begin                         {C}
      wstr ('#define ');
      wvstr (opt.lname);
      wstr (' (');
      if opt.enab
        then wstr ('1')
        else wstr ('0');
      wstr (')');
      end;

fmt_escr_k: begin                      {ESCR script}
      wstr ('const ');
      wvstr (opt.lname);
      wstr (' bool = ');
      if opt.enab
        then wstr ('True')
        else wstr ('False');
      end;

fmt_txt_k: begin                       {text file}
      wvstr (opt.lname);
      wstr (' ');
      if opt.enab
        then wstr ('TRUE')
        else wstr ('FALSE');
      end;

    end;                               {end of output format cases}
  wline;                               {write the accumulated output line to the file}
  end;
{
********************************************************************************
*
*   Subroutine WRITE_END
*
*   Write any special content after all the debug constants are defined.
}
procedure write_end;                   {write at end of output file}
  val_param; internal;

begin
  end;
{
********************************************************************************
*
*   Subroutine ERROR_FALSE
*
*   The special FALSE option was found in the DEBUG environment variable
*   together with other options.
}
procedure error_false;
  options (noreturn);

begin
  writeln ('FALSE in DEBUG environment variable conflicts with other options.');
  sys_bomb;
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  dbg_off := false;                    {init to debugging not globally disabled}
  dbg_any := false;                    {init to no debug option is enabled}
{
*   Get the output file name from the command line and determine the output
*   format based on the file name suffix.  The suffix is the part of the file
*   name from the last dot (.) to the end.
}
  string_cmline_token (fnam, stat);    {get FILENAME into FNAM}
  string_cmline_req_check (stat);      {FILENAME is required}

  name.len := 0;                       {init suffix to the empty string}
  p := fnam.len;                       {init index to last character of file name}
  while (p >= 1) and (fnam.str[p] <> '.') do begin {scan backward looking for "."}
    p := p - 1;
    end;
  if p >= 1 then begin                 {found a period ?}
    string_substr (fnam, p, fnam.len, name); {extract suffix from the file name}
    end;

  string_tkpick80 (                    {pick the file name suffix from list}
    name,                              {the suffix of the output file name}
    '.bat .aspic .dspic .pas .h .es .escr', {list of recognized suffixes}
    pick);                             {1-N number matching list entry, 0 = none}

  case pick of                         {which file name suffix is it ?}
1:  format := fmt_bat_k;               {.BAT}
2, 3: format := fmt_prepic_k;          {.ASPIC, .DSPIC}
4:  format := fmt_pas_k;               {.PAS}
5:  format := fmt_c_k;                 {.H}
6, 7: format := fmt_escr_k;            {.ES, .ESCR}
otherwise
    format := fmt_txt_k;               {unrecognized suffix}
    end;
{
*   Read all the NAME command line parameters.  Create a debug options list
*   entry for each new one.
}
  util_mem_context_get (               {create our private memory context}
    util_top_mem_context, mem_p);

  opt_list_p := nil;                   {init the list of debug options to empty}
  opt_last_p := nil;

  while true do begin                  {back here each new NAME command line parameter}
    string_cmline_token (opt, stat);   {try to get next NAME parameter}
    if string_eos(stat) then exit;     {exhausted the command line ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_upcase (opt);               {case-insensitive, make upper case}
    string_vstring (name, 'DEBUG_'(0), -1); {make the full constant name}
    string_append (name, opt);
    discard( entry(name) );            {make sure entry exists for this name}
    end;                               {back for next command line parameter}
{
*   Process all the names listed in the DEBUG environment variable.  For each
*   one, make sure a list entry exists for that name, and set it to TRUE.
}
  sys_envvar_get (string_v('DEBUG'), str, stat); {get DEBUG envvar contents}
  if sys_error(stat) then begin
    str.len := 0;                      {any error is as if DEBUG is empty string}
    sys_error_none (stat);             {clear the error condition}
    end;

  string_upcase (str);                 {case-insensitive, make upper case}
  p := 1;                              {init debug options string parse index}
  ndbg := 0;                           {init number of options found in DEBUG var}

  while true do begin                  {back here each new debug option}
    string_token (str, p, opt, stat);  {get the next option name}
    if string_eos(stat) then exit;     {exhausted the list of option names ?}
    sys_error_abort (stat, '', '', nil, 0);

    if string_equal (opt, string_v('FALSE')) then begin {special case of FALSE keyword ?}
      if ndbg > 0 then error_false;    {FALSE must be only contents of DEBUG var}
      dbg_off := true;                 {indicate debugging is globally disabled}
      next;                            {back for next option}
      end;

    ndbg := ndbg + 1;                  {count one more real debug option}
    if dbg_off and (ndbg > 0) then begin {FALSE keyword previously used ?}
      error_false;                     {fatal error, bomb the program}
      end;

    string_vstring (name, 'DEBUG_'(0), -1); {make the full constant name}
    string_append (name, opt);
    opt_p := entry (name);             {get pointer to the entry with this name}
    opt_p^.enab := true;               {mark this debug option as enabled}
    dbg_any := true;                   {at least one debug option is enabled}

    if string_equal (opt, string_v('TRUE')) then begin {special case of TRUE option ?}
      string_vstring (name, 'DEBUG_ICD'(0), -1); {TRUE implies ICD}
      opt_p := entry (name);
      opt_p^.enab := true;
      string_vstring (name, 'DEBUG_VS'(0), -1); {TRUE implies VS}
      opt_p := entry (name);
      opt_p^.enab := true;
      end;
    end;                               {back to get next debug option name}
{
*  Create DEBUGGING.
}
  string_vstring (name, 'DEBUGGING'(0), -1);
  opt_p := entry (name);               {get pointer to DEBUGGING list entry}
  opt_p^.enab := dbg_any;              {TRUE if any debug option is enabled}
{
*   Write the output file.
}
  file_open_write_text (fnam, '', conn, stat); {open the output file}
  sys_error_abort (stat, '', '', nil, 0);

  write_start;                         {do one-time start of file write}

  opt_p := opt_list_p;                 {init pointer to start of list}
  while opt_p <> nil do begin          {back here each new list entry}
    write_opt (opt_p^);                {write this debug constant to output file}
    opt_p := opt_p^.next_p;            {advance to next list entry}
    end;                               {back to do this new list entry}

  write_end;                           {do one-time end of file write}
  file_close (conn);                   {close the output file}
  end.
