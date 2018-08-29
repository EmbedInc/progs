{   Program HEX_DUMP hexfile
*
*   Dump the contents of the HEX file to standard output.
}
program hex_dump;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

var
  fnam:                                {HEX file name}
    %include '(cog)lib/string_treename.ins.pas';
  ihn: ihex_in_t;                      {HEX file reading state}
  sadr: int32u_t;                      {starting address of data chunk}
  ind: sys_int_machine_t;              {0-N index into data chunk}
  nd: sys_int_machine_t;               {number of data bytes}
  dat: ihex_dat_t;                     {chunk of data bytes from the HEX file}
  tk:                                  {scratch token}
    %include '(cog)lib/string32.ins.pas';
  buf:                                 {one line output buffer}
    %include '(cog)lib/string80.ins.pas';
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam, stat);    {get HEX input file name from command line}
  string_cmline_req_check (stat);      {HEX file name is required}
  string_cmline_end_abort;             {no additional command line arguments allowed}

  ihex_in_open_fnam (fnam, '.hex', ihn, stat); {open the HEX input file}
  sys_error_abort (stat, '', '', nil, 0);

  while true do begin                  {loop until HEX file exhausted}
    ihex_in_dat (ihn, sadr, nd, dat, stat); {get next chunk of data}
    if file_eof(stat) then exit;       {hit end of file ?}
    sys_error_abort (stat, '', '', nil, 0);
    string_f_int32h (buf, sadr);       {init to starting address of this chunk}
    string_append1 (buf, '-');
    string_f_int32h (tk, sadr + nd - 1); {make ending address string}
    string_append (buf, tk);
    string_appends (buf, ' ('(0));
    string_f_int (tk, nd);
    string_append (buf, tk);
    string_appends (buf, '):'(0));
    for ind := 0 to nd-1 do begin      {once for each data byte in this chunk}
      string_f_int_max_base (          {make 2 digit HEX string from this data byte}
        tk, dat[ind], 16, 2, [string_fi_leadz_k, string_fi_unsig_k], stat);
      if (buf.len + tk.len + 1) > buf.max then begin {no room on existing output line ?}
        writeln (buf.str:buf.len);     {write this output line}
        buf.len := 0;                  {reset output line to empty}
        string_append1 (buf, ' ');     {add indentation for continued lines}
        end;
      string_append1 (buf, ' ');       {separator before new byte value}
      string_append (buf, tk);         {this byte value in HEX}
      end;                             {back for next byte in this chunk}
    if buf.len > 0 then begin          {partial unwritten line ?}
      writeln (buf.str:buf.len);
      buf.len := 0;
      end;
    end;                               {back to get next data chunk from the HEX file}

  ihex_in_close (ihn, stat);           {close the HEX input file}
  sys_error_abort (stat, '', '', nil, 0);
  end.
