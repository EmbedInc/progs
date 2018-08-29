{   Program WAV_CSV [options]
*
*   Write the contents of a WAV file to a CSV file.
}
program wav_csv;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  fnam_in, fnam_out:                   {input and output file names}
    %include '(cog)lib/string_treename.ins.pas';
  wavin: wav_in_t;                     {state for reading the input WAV file}
  conn: file_conn_t;                   {connection to CSV output file}
  i, j: sys_int_machine_t;             {scratch integers and loop counters}
  r: real;                             {scratch floating point value}
  iname_set: boolean;                  {TRUE if the input file name already set}
  oname_set: boolean;                  {TRUE if the output file name already set}
  buf:                                 {one line output buffer}
    %include '(cog)lib/string8192.ins.pas';

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, err_parm, parm_bad, done_opts;

begin
  string_cmline_init;                  {init for reading the command line}
{
*   Initialize our state before reading the command line options.
}
  iname_set := false;                  {no input file name specified}
  oname_set := false;                  {no output file name specified}
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {implicit pathname token ?}
    if not iname_set then begin        {input file name not set yet ?}
      string_copy (opt, fnam_in);      {set input file name}
      iname_set := true;               {input file name is now set}
      goto next_opt;
      end;
    if not oname_set then begin        {output file name not set yet ?}
      string_copy (opt, fnam_out);     {set output file name}
      oname_set := true;               {output file name is now set}
      goto next_opt;
      end;
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (opt,                {pick command line option name from list}
    '-IN -OUT',
    pick);                             {number of keyword picked from list}
  case pick of                         {do routine for specific option}
{
*   -IN filename
}
1: begin
  if iname_set then begin              {input file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (fnam_in, stat);
  iname_set := true;
  end;
{
*   -OUT filename
}
2: begin
  if oname_set then begin              {output file name already set ?}
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
    end;
  string_cmline_token (fnam_out, stat);
  oname_set := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {unrecognized command line option}
    end;                               {end of command line option case statement}

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
  if not iname_set then begin          {no input file name specified ?}
    sys_message_bomb ('img', 'input_fnam_missing', nil, 0);
    end;
{
*   Open the WAV input file.
}
  wav_in_open_fnam (wavin, fnam_in, stat); {open WAV input file}
  sys_error_abort (stat, '', '', nil, 0);

  writeln ('Number of channels = ', wavin.info.nchan);
  writeln ('Sample rate =', wavin.info.srate:6:0, ' Hz');
  writeln ('Bits per channel = ', wavin.info.cbits);
  writeln ('Bytes per channel = ', wavin.info.cbytes);
  writeln ('Bytes per sample = ', wavin.info.sbytes);
  writeln ('Seconds = ', wavin.tsec:8:3);
  writeln ('Number of samples = ', wavin.nsamp);
{
*   Open the CSV output file and write its header line.
}
  if not oname_set then begin          {make default output file name ?}
    string_copy (wavin.conn.gnam, fnam_out); {use generic name of input file}
    end;

  file_open_write_text (fnam_out, '.csv', conn, stat); {open the output file}
  sys_error_abort (stat, '', '', nil, 0);

  string_vstring (buf, 'Seconds'(0), -1); {init CSV file header line}
  for i := 1 to wavin.info.nchan do begin {make label for each channel value}
    string_vstring (parm, 'Chan '(0), -1); {init start of name for this column}
    string_f_int (opt, i);             {make string channel number}
    string_append (parm, opt);         {make full column name in PARM}
    string_append1 (buf, ',');         {add separating comma after previous label}
    string_append_token (buf, parm);   {add label for this channel}
    end;
  file_write_text (buf, conn, stat);   {write the header line to the CSV output file}
{
*   Write all the input samples to the CSV output file.
}
  for i := 1 to wavin.nsamp do begin   {once for each input sample}
    r := (i - 1) / wavin.info.srate;   {make data time in seconds}
    string_f_fp_fixed (buf, r, 5);     {init output line with data time}
    for j := 1 to wavin.info.nchan do begin {once for each channel in this sample}
      r := wav_in_samp_chan (wavin, i-1, j-1); {get the value of this channel}
      string_f_fp_fixed (parm, r, 4);  {convert to floating point string}
      string_append1 (buf, ',');       {add separating comma after column}
      string_append_token (buf, parm); {write the value for this channel}
      end;                             {back for next channel in this sample}
    file_write_text (buf, conn, stat); {write the output line for this sample}
    end;                               {back for next sample in the input file}

  file_close (conn);                   {close the CSV output file}
  wav_in_close (wavin, stat);          {close the WAV input file}
  sys_error_abort (stat, '', '', nil, 0);
  end.
