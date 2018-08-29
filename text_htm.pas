{   Program TEXT_HTM <in fnam> [<out fnam>]
*
*   Create HTML file from text file so that the text is displayed verbatim
*   in the browswer.
}
program text_htm;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

const
  backg_red = 240;                     {HTML document background color, 0-255}
  backg_grn = 240;
  backg_blu = 240;

var
  fnam_in, fnam_out:                   {input and output file names}
    %include '(cog)lib/string_treename.ins.pas';
  conn_in: file_conn_t;                {connection to text input file}
  hout: htm_out_t;                     {connection to HTML output file}
  backg:                               {background color in HTML HEX string format}
    %include '(cog)lib/string32.ins.pas';
  buf:                                 {one line buffer and scratch string}
    %include '(cog)lib/string8192.ins.pas';
  stat: sys_err_t;                     {completion status}

label
  loop_line, done_lines;

begin
{
*   Get the command line parameters.
}
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam_in, stat); {get the input file name}
  string_cmline_req_check (stat);      {input file name is required}
  string_cmline_token (fnam_out, stat); {try to get output file name}
  if string_eos(stat) then begin       {no output file name supplied ?}
    fnam_out.len := 0;                 {indicate no output file name set}
    end;
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no more command line parameters allowed}
{
*   Make the 6 digit hexadecimal background color string in BACKG from the
*   0-255 RGB constants BACKG_RED, BACKG_GRN, and BACKG_BLU.
}
  string_f_int8h (backg, backg_red);
  string_f_int8h (buf, backg_grn);
  string_append (backg, buf);
  string_f_int8h (buf, backg_blu);
  string_append (backg, buf);
{
*   Open the input and output files.
}
  file_open_read_text (fnam_in, '', conn_in, stat); {try to open input file}
  sys_error_abort (stat, '', '', nil, 0);

  if fnam_out.len <= 0 then begin      {no output file specified, use default ?}
    string_pathname_split (            {init output file name to input file leafname}
      conn_in.fnam, buf, fnam_out);
    end;
  htm_open_write_name (hout, fnam_out, stat); {open HTML output file}
  sys_error_abort (stat, '', '', nil, 0);
{
*   Write the HTML header and set up for preformatted text.
}
  htm_write_str (hout, '<html>'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_newline (hout, stat);
  sys_error_abort (stat, '', '', nil, 0);

  htm_write_str (hout, '<head><title>'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_nopad (hout);
  string_copy (conn_in.fnam, buf);     {make upper case input file leafname}
  string_upcase (buf);
  htm_write_vstr (hout, buf, stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_nopad (hout);
  htm_write_str (hout, '</title></head>'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_newline (hout, stat);
  sys_error_abort (stat, '', '', nil, 0);

  htm_write_str (hout, '<body bgcolor=#'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_nopad (hout);
  htm_write_vstr (hout, backg, stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_nopad (hout);
  htm_write_str (hout, '><font color=#000000>'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_newline (hout, stat);
  sys_error_abort (stat, '', '', nil, 0);

  htm_write_pre_start (hout, stat);    {init for writing pre-formatted text}
  sys_error_abort (stat, '', '', nil, 0);
{
*   The HTML output file has been set up for writing preformatted text.  Now
*   write all the input file lines to the HTML output file as preformatted text.
}
loop_line:                             {back here each new input file line}
  file_read_text (conn_in, buf, stat); {read this input file line}
  if file_eof(stat) then goto done_lines; {end of input file ?}
  sys_error_abort (stat, '', '', nil, 0);
  htm_write_pre_line (hout, buf, stat); {write preformatted line to HTML output file}
  sys_error_abort (stat, '', '', nil, 0);
  goto loop_line;                      {back to do next line}

done_lines:                            {input file has been exhausted}
  file_close (conn_in);                {close the input file}

  htm_write_pre_end (hout, stat);      {done writing preformatted lines to HTML file}
  sys_error_abort (stat, '', '', nil, 0);

  htm_write_str (hout, '</font></body></html>'(0), stat);
  sys_error_abort (stat, '', '', nil, 0);
  htm_close_write (hout, stat);        {close the HTML output file}
  sys_error_abort (stat, '', '', nil, 0);
  end.
