{   Program WAV_COPY [options]
}
program wav_copy;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

const
  max_msg_args = 2;                    {max arguments we can pass to a message}

var
  fnam_in, fnam_out:                   {input and output file names}
    %include '(cog)lib/string_treename.ins.pas';
  wavin: wav_in_t;                     {state for reading the input WAV file}
  winfo: wav_info_t;                   {info about a WAV data set}
  wavot: wav_out_t;                    {state for writing the output WAV file}
  tbeg, tend: real;                    {start and end times within input stream}
  reqbits: sys_int_machine_t;          {requested bits per channel per sample}
  samp: wav_samp_t;                    {data for each channel of a sample}
  nosam: sys_int_conv32_t;             {number of output samples}
  losam: sys_int_conv32_t;             {last 0-N output sample number}
  gain: real;                          {input to output amplitude gain}
  speed: real;                         {relative input playback speed}
  s: sys_int_conv32_t;                 {scratch sample number}
  ch: sys_int_machine_t;               {scratch channel number}
  srate: real;                         {output sample rate when SRATE_SET is TRUE}
  filt: wav_filt_t;                    {state for getting filtered input data}
  odur: double;                        {output signal duration in seconds}
  aspeed: real;                        {absolute value of SPEED}

  iname_set: boolean;                  {input file name already set}
  oname_set: boolean;                  {output file name already set}
  bits_set: boolean;                   {-BITS command line option used}
  srate_set: boolean;                  {output sample rate explicitly set}
  autogain: boolean;                   {automatically use gain that maximizes outout}
  mono: boolean;                       {convert to monophonic (average all in chans)}

  opt:                                 {upcased command line option}
    %include '(cog)lib/string_treename.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string_treename.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  msg_parm:                            {references arguments passed to a message}
    array[1..max_msg_args] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_opt, done_opt, err_parm, parm_bad, done_opts;
{
****************************************************************************
*
*   Subroutine OUTSAMPLE (S, SAMP)
*
*   Get the values from the input signal for output sample S.  The first
*   output sample is 0, with successive samples increasing by 1.
}
procedure outsample (                  {get one output sample from the input signal}
  in      s: sys_int_conv32_t;         {0-N output sample number}
  out     samp: wav_samp_t);           {returned data for all the output channels}
  val_param;

var
  t: double;                           {input signal data time of the output sample}
  ch: sys_int_machine_t;               {input channel number}

begin
  t := s / wavot.info.srate;           {make output data time of this sample}
  t := (tbeg + t) * speed;             {make input data time of this sample}

  if mono then begin                   {average all input chans to make out chans ?}
    samp[0] := wav_filt_samp_chan (filt, t, -1); {get the averaged channels at T}
    return;
    end;

  for ch := 0 to wavin.chlast do begin {once for each input channel}
    samp[ch] := wav_filt_samp_chan (filt, t, ch); {get the value of this channel}
    end;
  end;
{
****************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
{
*   Initialize our state before reading the command line options.
}
  iname_set := false;                  {no input file name specified}
  oname_set := false;                  {no output file name specified}
  tbeg := 0.0;                         {init where to start within input stream}
  tend := 1.0E35;                      {init where to end within input stream}
  bits_set := false;                   {init to no specific bits requested}
  reqbits := 8;
  srate_set := false;                  {init to use default output sampling rate}
  gain := 1.0;                         {init to default amplitude gain}
  autogain := false;
  speed := 1.0;                        {init to default relative playback speed}
  mono := false;                       {init to not convert to monophonic}
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
    '-IN -OUT -FROM -TO -BITS -GAIN -SRATE -SPEED -MONO',
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
*   -FROM s
}
3: begin
  string_cmline_token_fpm (tbeg, stat);
  end;
{
*   -TO s
}
4: begin
  string_cmline_token_fpm (tend, stat);
  end;
{
*   -BITS s
}
5: begin
  string_cmline_token_int (reqbits, stat);
  bits_set := true;
  end;
{
*   -GAIN g
*   -GAIN *
}
6: begin
  string_cmline_token (parm, stat);    {get the parameter string}
  if (parm.len = 1) and (parm.str[1] = '*') then begin {autogain ?}
    autogain := true;
    goto done_opt;                     {done with this command line option}
    end;
  string_t_fpm (parm, gain, stat);
  autogain := false;
  end;
{
*   -SRATE Hz
}
7: begin
  string_cmline_token_fpm (srate, stat);
  srate_set := true;
  end;
{
*   -SPEED s
}
8: begin
  string_cmline_token_fpm (speed, stat);
  end;
{
*   -MONO
}
9: begin
  mono := true;
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
  if not iname_set then begin          {no input file name specified ?}
    sys_message_bomb ('img', 'input_fnam_missing', nil, 0);
    end;
{
*   Open the WAV input file and set parameters from its info.
}
  wav_in_open_fnam (wavin, fnam_in, stat); {open WAV input file}
  sys_error_abort (stat, '', '', nil, 0);

  writeln ('Input file: ', wavin.conn.tnam.str:wavin.conn.tnam.len);
  writeln ('  Channels       ', wavin.info.nchan:9);
  writeln ('  Bits/channel   ', wavin.info.cbits:9);
  writeln ('  Samples        ', wavin.nsamp:9);
  writeln ('  Samp rate (Hz) ', wavin.info.srate:9:0);
  writeln ('  Duration (Sec) ', wavin.tsec:13:3);

  winfo := wavin.info;                 {init output format from input format}
  winfo.enc := wav_enc_samp_k;         {set output to samples at regular intervals}
  if bits_set then begin               {explicit output bits/chan requested ?}
    winfo.cbits := reqbits;            {set to requested value}
    end;
  if srate_set then begin              {output sample rate explicitly set ?}
    winfo.srate := srate;
    end;
  if mono then begin                   {convert to monophonic output ?}
    winfo.nchan := 1;
    end;
{
*   Open the WAV output file and adapt to the configuration actually received.
}
  if not oname_set then begin          {output filename not explicitly set ?}
    string_copy (wavin.conn.gnam, fnam_out); {default to input file leafname}
    end;

  wav_out_open_fnam (wavot, fnam_out, winfo, stat); {open the WAV output file}
  sys_error_abort (stat, '', '', nil, 0);

  tbeg := max(0.0, min(wavin.tsec, tbeg)); {clip start time to valid range}
  tend := max(0.0, min(wavin.tsec, tend)); {clip end time to valid range}
  if tend < tbeg then speed := -speed; {range flipped backwards ?}
  aspeed := abs(speed);                {make positive input speedup multiplier}
  odur := abs((tend - tbeg) / speed);  {make duration of output signal}
  nosam := max(1, round(odur * wavot.info.srate)); {number of output samples}
  losam := nosam - 1;                  {number of the last output sample}

  wav_filt_aa (                        {set up input filter}
    wavin,                             {state for getting input signal}
    wavot.info.srate * 0.5 / aspeed,   {anti-aliasing filter frequency pass limit}
    1000.0,                            {min require attenuation at pass freq limit}
    filt);                             {returned filter for resampling}

  writeln ('Output file: ', wavot.conn.tnam.str:wavin.conn.tnam.len);
  writeln ('  Channels       ', wavot.info.nchan:9);
  writeln ('  Bits/channel   ', wavot.info.cbits:9);
  writeln ('  Samples        ', nosam:9);
  writeln ('  Samp rate (Hz) ', wavot.info.srate:9:0);
  writeln ('  Duration (Sec) ', (nosam/wavot.info.srate):13:3);
{
*   Determine the gain setting automatically if this is enabled.  The gain
*   will be set to maximize the output signal without clipping it.
}
  if autogain then begin               {determine gain automatically ?}
    gain := 0.0;                       {init to max signal magnitude found}
    for s := 0 to losam do begin       {once for each output sample}
      outsample (s, samp);             {get the input signal at this output sample}
      for ch := 0 to wavot.chlast do begin {once for each channel in this sample}
        gain := max(gain, abs(samp[ch])); {update max signal level found so far}
        end;                           {back for next channel in this sample}
      end;                             {back for next sample in the interval}
    if gain >= 15.0E-6
      then begin                       {max magnitude is large enough to invert}
        gain := 1.0 / gain;            {set gain so max magnitude scales to 1}
        end
      else begin                       {max magnitude is essentially zero}
        gain := 1.0;                   {set gain for no amplitude adjustment}
        end
      ;
    end;                               {done finding automatic gain setting}

  writeln ('Gain =', gain:10:3);
{
*   Copy the input stream to the output stream.
}
  for s := 0 to losam do begin         {once for each output sample}
    outsample (s, samp);               {get the input signal at this output sample}
    for ch := 0 to wavot.chlast do begin {once for each channel in this sample}
      samp[ch] := samp[ch] * gain;     {perform the amplitude gain adjustment}
      end;                             {back for next channel in this sample}
    wav_out_samp (wavot, samp, wavot.info.nchan, stat); {write it to the output}
    sys_error_abort (stat, '', '', nil, 0);
    end;                               {back for next input sample}
{
*   Clean up and leave.
}
  wav_out_close (wavot, stat);         {close the output WAV file}
  sys_error_abort (stat, '', '', nil, 0);
  wav_in_close (wavin, stat);          {close the input WAV file}
  sys_error_abort (stat, '', '', nil, 0);
  end.
