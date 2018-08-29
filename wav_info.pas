program wav_info;
%include 'base.ins.pas';
%include 'stuff.ins.pas';

var
  fnam: string_treename_t;
  conn: file_conn_t;
  stat: sys_err_t;
{
***************************************************************************
*
*   Local subroutine CHUNK (POS, LEN, LEVEL)
*
*   Read the list of chunks starting at file position POS up to a length of LEN.
*   LEVEL is the recursion level.  LEVEL is set to 0 when this routine is called
*   the first time for the top RIFF chunk at the beginning of the file.
}
procedure chunk (
  in      pos: sys_int_adr_t;          {file position to start reading at}
  in      len: sys_int_adr_t;          {max length to read}
  in      level: sys_int_machine_t);   {current recursion level, 0 = top}
  val_param; internal;

type
  fmt_t = record                       {info stored in one "fmt " chunk}
    size: int32u_t;                    {size of remainder of the chunk}
    dtype: integer16;                  {data type, 1 = uncompressed}
    n_chan: int16u_t;                  {number of audio channels}
    samp_sec: int32u_t;                {number of samples per second}
    bytes_sec: int32u_t;               {number of bytes per second}
    bytes_samp: int16u_t;              {bytes per sample}
    bits_samp: int16u_t;               {bits per sample}
    end;

var
  chunk_name: array[1..4] of char;     {name of this chunk}
  chunk_len: int32u_t;                 {generic chunk length}
  fmt: fmt_t;                          {FMT chunk data}
  ofs: sys_int_adr_t;                  {offset from start of caller's region}
  olen: sys_int_adr_t;                 {number of bytes actually read}
  name: string_var4_t;                 {chunk name}
  i: sys_int_machine_t;                {scratch integer and loop counter}

label
  loop_chunk;

begin
  name.max := size_char(name.str);     {init local var string}

  ofs := 0;                            {init offset into caller's region}

loop_chunk:                            {back here each new chunk in this region}
  if (ofs + sizeof(chunk_name)) > len then return; {exhausted region ?}
  file_pos_ofs (conn, pos+ofs, stat);  {go to start of new chunk}
  sys_error_abort (stat, '', '', nil, 0);
  file_read_bin (conn, sizeof(chunk_name), chunk_name, olen, stat);
  if file_eof(stat) then return;       {pop back a level on end of file}
  sys_error_abort (stat, '', '', nil, 0);
  ofs := ofs + sizeof(chunk_name);

  string_vstring (name, chunk_name, size_char(chunk_name)); {make var string chunk name ID}
  if
      (level = 0) and                  {at start of file ?}
      (not string_equal (name, string_v('RIFF'))) {top chunk is not RIFF ?}
      then begin
    writeln ('Not a RIFF file.');
    sys_bomb;
    end;

  for i := 1 to level do write ('  '); {indent for this nesting level}

  string_tkpick80 (name,               {look up this chunk name in list of known names}
    'RIFF LIST WAVE fmt data',
    i);
  case i of                            {which known chunk type is it ?}

1, 2: begin                            {chunk types that contain sub-chunks}
      file_read_bin (conn, sizeof(chunk_len), chunk_len, olen, stat);
      sys_error_abort (stat, '', '', nil, 0);
      ofs := ofs + sizeof(chunk_len);
      writeln (name.str:name.len, ', length = ', chunk_len); {show info for this chunk}
      if chunk_len > (len - pos) then begin
        writeln ('Chunk extends past end of parent chunk.');
        sys_bomb;
        end;
      chunk (pos+ofs, chunk_len, level+1); {process sub chunks recursively}
      end;

3:  begin                              {WAVE chunk}
      chunk_len := len - ofs;          {length is rest of parent chunk}
      writeln (name.str:name.len, ', length = ', chunk_len); {show info for this chunk}
      chunk (pos+ofs, chunk_len, level+1); {process sub chunks recursively}
      end;

4:  begin                              {FMT subchunk within WAVE}
      file_read_bin (conn, sizeof(fmt), fmt, olen , stat); {read FMT chunk data}
      sys_error_abort (stat, '', '', nil, 0);
      ofs := ofs + sizeof(fmt.size);   {account for chunk length field}
      chunk_len := fmt.size;           {get size of this chunk}
      writeln (name.str:name.len, ', length = ', chunk_len); {show info for this chunk}
      for i := 1 to level do write ('  '); writeln ('  Data type ', fmt.dtype);
      for i := 1 to level do write ('  '); writeln ('  Channels ', fmt.n_chan);
      for i := 1 to level do write ('  '); writeln ('  Samp/sec ', fmt.samp_sec);
      for i := 1 to level do write ('  '); writeln ('  Bytes/sec ', fmt.bytes_sec);
      for i := 1 to level do write ('  '); writeln ('  Bytes/samp ', fmt.bytes_samp);
      for i := 1 to level do write ('  '); writeln ('  Bits/samp ', fmt.bits_samp);
      end;                             {end of FMT chunk case}

5:  begin                              {DATA subchunk within WAVE}
      file_read_bin (conn, sizeof(chunk_len), chunk_len, olen, stat);
      sys_error_abort (stat, '', '', nil, 0);
      ofs := ofs + sizeof(chunk_len);
      writeln (name.str:name.len, ', length = ', chunk_len); {show info for this chunk}
      if chunk_len > (len - pos) then begin
        writeln ('Chunk extends past end of parent chunk.');
        sys_bomb;
        end;
      for i := 1 to level do write ('  '); writeln ('  Seconds ',
        ((chunk_len div fmt.bytes_samp) - 1) / fmt.samp_sec);
      end;

otherwise                              {unrecognized chunk type}
    file_read_bin (conn, sizeof(chunk_len), chunk_len, olen, stat);
    sys_error_abort (stat, '', '', nil, 0);
    ofs := ofs + sizeof(chunk_len);
    writeln (name.str:name.len, ', length = ', chunk_len); {show info for this chunk}
    if chunk_len > (len - pos) then begin
      writeln ('Chunk extends past end of parent chunk.');
      sys_bomb;
      end;
    end;

  if odd(chunk_len) then begin         {chunk length is odd number of bytes ?}
    chunk_len := chunk_len + 1;        {account for implicit padding byte}
    end;

  ofs := ofs + chunk_len;              {update offset to after this chunk}
  goto loop_chunk;                     {back to do next chunk in this region}
  end;
{
***************************************************************************
*
*   Start of main routine.
}
begin
  fnam.max := size_char(fnam.str);

  string_cmline_init;
  string_cmline_token (fnam, stat);
  string_cmline_req_check (stat);
  string_cmline_end_abort;

  file_open_read_bin (fnam, '.wav', conn, stat);
  sys_error_abort (stat, '', '', nil, 0);
  chunk (0, 16#7FFFFFFF, 0);           {process the chunks tree recursively}
  end.
