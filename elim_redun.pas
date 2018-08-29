{   ELIM_REDUN <in fnam> <out fnam>
*
*   Eliminate all adjacent redundant lines in the input file by writing them only
*   once to the output file.
}
program elim_redun;
%include 'base.ins.pas';

var
  fnam_in, fnam_out:                   {input and output file names}
    %include '(cog)lib/string_treename.ins.pas';
  conn_in, conn_out: file_conn_t;      {input and output file I/O connections}
  buf:                                 {new and previous line input buffers}
    array[0..1] of string_var8192_t;
  this_buf: sys_int_machine_t;         {index for current line buffer}
  last_buf: sys_int_machine_t;         {index for previous line buffer}
  blklen: sys_int_machine_t;           {length of current repeat block}
  nblk: sys_int_machine_t;             {number of repeat blocks}
  ii: sys_int_machine_t;               {scratch integer}
  stat: sys_err_t;                     {completion status}

begin
  buf[0].max := size_char(buf[0].str); {init var strings}
  buf[1].max := size_char(buf[1].str);

  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (fnam_in, stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_token (fnam_out, stat);
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_end_abort;             {no more command line arguments allowed}

  file_open_read_text (fnam_in, '', conn_in, stat);
  sys_error_abort (stat, '', '', nil, 0);
  file_open_write_text (fnam_out, '', conn_out, stat);
  sys_error_abort (stat, '', '', nil, 0);

  this_buf := 0;                       {init curr and previous buf indicies}
  last_buf := 1;
  blklen := 0;                         {length of current repeat block}
  nblk := 0;                           {init number of repeat blocks}

  while true do begin                  {back here each new input file line}
    file_read_text (conn_in, buf[this_buf], stat);
    if file_eof(stat) then exit;
    sys_error_abort (stat, '', '', nil, 0);
    string_unpad (buf[this_buf]);      {delete trailing spaces}
    if                                 {write this line to output file ?}
        (conn_in.lnum = 1) or          {first line in file ?}
        (not string_equal(buf[this_buf], buf[last_buf])) {different from last line ?}
        then begin
      file_write_text (buf[this_buf], conn_out, stat); {write line to output file}
      sys_error_abort (stat, '', '', nil, 0);
      if blklen > 1 then begin         {just ended a repeat block ?}
        nblk := nblk + 1;              {count one more repeat block found}
        end;
      blklen := 0;                     {init size of this repeat block}
      end;
    blklen := blklen + 1;              {count one more line in this repeat block}
    ii := this_buf;                    {flip the buffers}
    this_buf := last_buf;
    last_buf := ii;
    end;                               {back to get next input file line}
  if blklen > 1 then begin             {ended in a repeat block ?}
    nblk := nblk + 1;
    end;

  writeln (conn_in.lnum, ' lines read, ',
    conn_in.lnum - conn_out.lnum, ' lines removed in ',
    nblk, ' repeat blocks, ',
    conn_out.lnum, ' lines written.');
  file_close (conn_in);
  file_close (conn_out);
  end.
