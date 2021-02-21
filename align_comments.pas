{   Program ALIGN_COMMENTS <source file name> [options]
*
*   Copy a text file to another file.  The destination file is created if not
*   already existing, and overwritten if previously existing.  The command
*   line options are:
*
*     -OUT filename
*
*       Explicitly set output file name.  The default output file name is the
*       leafname of the input file.
*
*     -EXCL <character range spec>
*
*       Define an exclusion within which characters will be copied verbatim.
*
*     -COMM <character range spec>
*
*       Define one comment type.
*
*     -COMTAB n
*
*       Set tab column for comment starts.  Only comments following non-blank
*       characters on the same line will be adjusted.
*
*   The <character range spec> syntax referred to above describes how a range
*   of characters (like an inline comment or a quoted string) are delimeted.
*   A range spec must always contain at least two tokens.  These are the
*   start and end of range recognition strings.  Additional keywords are
*   allowed after that.  These keywords are:
*
*     -BOL
*
*       The range always starts at the beginning of a line.  This means
*       that the range start string is only valid if found in column 1.
*
*     -EOL
*
*       End of line terminates the range.  The end of range string becomes
*       irrelevant if this keyword is present.
*
*     -LINE
*
*       The range is contrained to start and end on the same line.  It is
*       an error if the end of line is encountered within such a range.
}
program align_comments;
%include 'base.ins.pas';

const
  max_excl_k = 4;                      {max separate exclusion types we understand}
  max_comm_k = 4;                      {max separate comment types we understand}
  max_msg_parms = 4;                   {max parameters we can pass to a message}

type
  parse_k_t = (                        {input line parsing state}
    parse_normal_k,                    {normal character}
    parse_excl_k,                      {within an exclusion}
    parse_comm_k);                     {within end of line comment}

  crange_t = record                    {data about one character range}
    strs: string_var4_t;               {string that starts the range}
    stre: string_var4_t;               {string that ends the range}
    bols: boolean;                     {STRS only valid at the beginning of line}
    eole: boolean;                     {range ends at the end of line}
    slin: boolean;                     {TRUE if range start/end always on same line}
    nfnd: sys_int_conv4_t;             {number of chars currently into STRS/STRE}
    end;

var
  fnam:                                {scratch file name}
    %include '(cog)lib/string_treename.ins.pas';
  conn_in, conn_out: file_conn_t;      {handles to input and output file connections}
  buf,                                 {input line buffer}
  buf2:                                {output line buffer}
    %include '(cog)lib/string8192.ins.pas';
  opt:                                 {current command line option}
    %include '(cog)lib/string16.ins.pas';
  parm:                                {command line option parameter}
    %include '(cog)lib/string80.ins.pas';
  pick: sys_int_machine_t;             {number of keyword picked from list}

  comtab: sys_int_machine_t;           {end of line comment tab position}
  comtab_set: boolean;                 {TRUE if -COMTAB command line option used}
  excl:                                {all the exclusions we know about}
    array[1..max_excl_k] of crange_t;
  nexcl: sys_int_machine_t;            {number of defined exclusions}
  comm:                                {all the comment types we know about}
    array[1..max_comm_k] of crange_t;
  ncomm: sys_int_machine_t;            {number of defined comment types}

  i, j: sys_int_machine_t;             {scratch loop counters and integers}
  ind: sys_int_machine_t;              {input line character read index}
  cind: sys_int_machine_t;             {index of curr exclusion or comment}
  n_blank: sys_int_machine_t;          {out char index of last non-blank character}
  last_copied: sys_int_machine_t;      {input line index of last char copied}
  matching: sys_int_machine_t;         {number of chars currently matching}
  parse: parse_k_t;                    {current input line parsing state}
  c: char;                             {current input line char being parsed}

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  next_opt, done_opts, cmline_err, loop_line, next_char, eof;
{
*****************************************************************
*
*   Local subroutine DO_RANGE_SPEC (CRANGE, SPEC)
*
*   Fill in the character range descriptor CRANGE from the range specifier
*   string SPEC.
*
*   A range specifier string must contain at least two tokens.  These
*   are the leading and trailing strings that identify the start and end
*   of the range.  The keywords below may optionally follow the first
*   two mandatory tokens:
*
*   -BOL
*
*     The start of range is only valid at the beginning of a line.
*
*   -EOL
*
*     The end of range is the end of line.  The end of range string
*     token is ignored if this token is present.
*
*   -LINE
*
*     The range start and end is always on the same line.  It is an error
*     if a range start is found on a line without a matching range end on
*     the same line.
}
procedure do_range_spec (
  out     crange: crange_t;            {character range descriptor to fill in}
  in      spec: univ string_var_arg_t); {character range specifier string}
  val_param;

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  token: string_var16_t;               {token parsed from SPEC}
  p: string_index_t;                   {SPEC parse index}
  pick: sys_int_machine_t;             {number of token parsed from list}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  tknext;

begin
  token.max := sizeof(token.str);      {init local var string}

  crange.strs.max := sizeof(crange.strs.str); {init var strings in range descriptor}
  crange.stre.max := sizeof(crange.stre.str);

  crange.bols := false;                {init to start only valid at line start}
  crange.eole := false;                {init to EOL is not range end}
  crange.slin := false;                {init to range may span multiple lines}
  crange.nfnd := 0;                    {init number of matched start/end so far}

  p := 1;                              {init SPEC parse index}
  sys_msg_parm_vstr (msg_parm[1], spec);

  string_token (spec, p, crange.strs, stat); {get range start string}
  sys_error_abort (stat, 'stuff', 'alcomm_crspec_start_bad', msg_parm, 1);

  string_token (spec, p, crange.stre, stat); {get range end string}
  sys_error_abort (stat, 'stuff', 'alcomm_crspec_end_bad', msg_parm, 1);

tknext:                                {back here each new token parsed from SPEC}
  string_token (spec, p, token, stat); {get next token from SPEC}
  if string_eos(stat) then return;     {exhausted specifier string ?}
  sys_error_abort (stat, 'stuff', 'alcomm_crspec_next_err', msg_parm, 1);
  string_upcase (token);               {make upper case for keyword matching}
  string_tkpick80 (token,              {pick parsed keyword from list}
    '-BOL -EOL -LINE',
    pick);                             {number of token parsed from list}
  case pick of
{
*   -BOL
}
1: begin
  crange.bols := true;
  end;
{
*   -EOL
}
2: begin
  crange.eole := true;
  crange.stre.len := 0;
  end;
{
*   -LINE
}
3: begin
  crange.slin := true;
  end;
{
*   Unrecognized keywords parsed from SPEC.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], token);
    sys_message_bomb ('stuff', 'alcomm_crspec_token_bad', msg_parm, 1);
    end;
  goto tknext;                         {back for next token from SPEC}
  end;
{
*****************************************************************
*
*   Local subroutine PUT_CHAR (C)
*
*   Put the character C to the output line buffer.
}
procedure put_char (
  in      c: char);
  val_param;

begin
  string_append1 (buf2, c);            {append character to output buffer}
  if c <> ' ' then begin               {character is non-blank ?}
    n_blank := buf2.len;               {save index of last non-blank character}
    end;
  end;
{
*****************************************************************
*
*   Local subroutine RESET_MATCHES
*
*   Reset the character match counters in all the char ranges to zero.
}
procedure reset_matches;

var
  i: sys_int_machine_t;

begin
  for i := 1 to nexcl do begin         {once for each exclusion}
    excl[i].nfnd := 0;
    end;
  for i := 1 to ncomm do begin         {once for each comment}
    comm[i].nfnd := 0;
    end;
  end;
{
*****************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}

  string_cmline_token (fnam, stat);    {get input file name from command line}
  string_cmline_req_check (stat);      {input file name argument is required}

  file_open_read_text (                {open input file, determine suffix}
    fnam,
    '.pas .cog .ftn .c .h .sml .asm .ain .aspic .c18 .c30 .escr .es ""',
    conn_in, stat);
  sys_error_abort (stat, '', '', nil, 0);
{
*   Init before processing command line options.
}
  comtab := 40;                        {default aligned end of line comment position}
  comtab_set := false;
  nexcl := 0;                          {init number of exclusions}
  ncomm := 0;                          {init number of defined comments}
  string_copy (conn_out.fnam, fnam);   {init output file to input file leafname}
{
*****************
*
*   Back here to read each new command line argument.
}
next_opt:
  string_cmline_token (opt, stat);     {read next command line option}
  if string_eos(stat) then goto done_opts; {hit end of command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,
    '-OUT -EXCL -COMM -COMTAB',
    pick);                             {number of keyword picked from list}
  case pick of                         {which command line option was picked ?}
{
*   -OUT filename
}
1: begin
  string_cmline_token (fnam, stat);
  end;
{
*   -EXCL <character range spec>
}
2: begin
  if nexcl >= max_excl_k then begin    {EXCL array overflow ?}
    sys_message_bomb ('stuff', 'alcomm_excl_too_many', nil, 0);
    end;
  nexcl := nexcl + 1;                  {indicate one more exclusion}
  string_cmline_token (parm, stat);    {get character range spec string}
  if sys_error(stat) then goto cmline_err;
  do_range_spec (excl[nexcl], parm);   {fill in data for this exclusion}
  end;
{
*   -COMM <character range spec>
}
3: begin
  if ncomm >= max_comm_k then begin    {COMM array overflow ?}
    sys_message_bomb ('stuff', 'alcomm_comm_too_many', nil, 0);
    end;
  ncomm := ncomm + 1;                  {indicate one more comment type}
  string_cmline_token (parm, stat);    {get character range spec string}
  if sys_error(stat) then goto cmline_err;
  do_range_spec (comm[ncomm], parm);   {fill in data for this comment type}
  end;
{
*   -COMTAB <comment align column>
}
4: begin
  string_cmline_token_int (comtab, stat);
  comtab_set := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    sys_msg_parm_vstr (msg_parm[1], opt);
    sys_message_bomb ('string', 'cmline_opt_bad', msg_parm, 1);
    end;
{
*   Done reading the current command line option.  Back for next option
*   if there are no errors.
}
cmline_err:                            {jump here on error with current OPT}
  sys_msg_parm_vstr (msg_parm[1], opt);
  sys_error_abort (stat, 'string', 'cmline_opt_problem', msg_parm, 1);
  goto next_opt;

done_opts:                             {all done reading command line options}
{
*   If no exclusions or comments were specified, then set defaults
*   based on the file suffix.
}
  if (nexcl = 0) and (ncomm = 0) then begin {no exclusions or comments declared ?}
    case conn_in.ext_num of            {what suffix did the input file have ?}

1, 2: begin                            {.PAS or .COG}
        do_range_spec (excl[1], string_v('"''" "''"'(0)));
        nexcl := 1;
        do_range_spec (comm[1], string_v('{ }'(0)));
        ncomm := 1;
(*
        do_range_spec (comm[2], string_v('''"'' ''"'''(0)));
        ncomm := 2;
*)
        end;

3:    begin                            {.FTN}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        nexcl := 1;
        do_range_spec (comm[1], string_v('C "" -bol -eol'(0)));
        do_range_spec (comm[2], string_v('{ "" -eol'(0)));
        ncomm := 2;
        end;

4, 5, 10, 11: begin                    {.C, .H, .C18, .C30}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        do_range_spec (excl[2], string_v('''"'' ''"'' -line'(0)));
        nexcl := 2;
        do_range_spec (comm[1], string_v('/* */'(0)));
        do_range_spec (comm[2], string_v('// "" -eol'(0)));
        ncomm := 2;
        end;

6:    begin                            {.SML}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        do_range_spec (excl[2], string_v('''"'' ''"'' -line'(0)));
        nexcl := 2;
        do_range_spec (comm[1], string_v('{ }'(0)));
        ncomm := 1;
        end;

7, 8: begin                            {.ASM or .AIN}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        nexcl := 1;
        do_range_spec (comm[1], string_v('; "" -eol'(0)));
        ncomm := 1;
        end;

9:    begin                            {.ASPIC}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        do_range_spec (excl[2], string_v('''"'' ''"'' -line'(0)));
        nexcl := 2;
        do_range_spec (comm[1], string_v('; "" -eol'(0)));
        ncomm := 1;
        end;

12, 13: begin                          {.ESCR, .ES}
        do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
        do_range_spec (excl[2], string_v('''"'' ''"'' -line'(0)));
        nexcl := 2;
        do_range_spec (comm[1], string_v('// "" -eol'(0)));
        ncomm := 1;
        end;

otherwise                              {generic defaults}
      do_range_spec (excl[1], string_v('"''" "''" -line'(0)));
      do_range_spec (excl[2], string_v('''"'' ''"'' -line'(0)));
      nexcl := 2;
      do_range_spec (comm[1], string_v('/* "" -eol'(0)));
      ncomm := 1;
      end;                             {end of input file suffix cases}
    end;                               {done setting default exclusions and comments}
{
*   Set the default comments tab column unless it was explicitly set by the
*   user.
}
  if not comtab_set then begin         {user didn't explicitly set tab column ?}
    case conn_in.ext_num of            {what suffix did the input file have ?}
7, 8, 9, 12, 13: begin                 {.ASM, .AIN, .ASPIC, .ESCR, .ES}
        comtab := 30;
        end;
      end;                             {end of input file suffix cases}
    end;                               {end of setting default comments tab column}
{
*   Done processing command line options.
*
*****************
}
  file_open_write_text (fnam, '', conn_out, stat); {open output file}
  sys_error_abort (stat, '', '', nil, 0);
  parse := parse_normal_k;             {init input file parse state}

loop_line:                             {back here each new input file text line}
  file_read_text (conn_in, buf, stat); {read next line from input file}
  if file_eof(stat) then goto eof;     {hit end of input file ?}
  sys_error_abort (stat, '', '', nil, 0);
  string_unpad (buf);                  {strip off trailing blanks}
  buf2.len := 0;                       {init this output line to empty}
{
*   Process this line.  The input file line is in BUF.
}
  n_blank := 0;                        {init to all blank line so far}
  last_copied := 0;                    {init to no chars copied from input line yet}
  reset_matches;                       {reset to no current matches in any range}

  for ind := 1 to buf.len do begin     {scan forwards thru input string}
    c := buf.str[ind];                 {fetch current input line character}
    case parse of                      {what is current parsing state ?}
{
*   Normal parsing state.  Look for start of an exclusion or comment.
}
parse_normal_k: begin
  for i := 1 to nexcl do begin         {once for each possible exclusion}
    with excl[i]: cr do begin          {CR is crange for this exclusion}
      if                               {new character matches this range ?}
          (cr.strs.str[cr.nfnd + 1] = c) and {new character matches next range char ?}
          ( (not cr.bols) or           {range start not only at line start ?}
            (ind = 1) or               {at line start anyway ?}
            (cr.nfnd > 0)              {not first character in range ?}
            )
        then begin                     {one more character matches this range}
          cr.nfnd := cr.nfnd + 1;      {log one more character matched}
          if cr.nfnd >= cr.strs.len then begin {matched whole char range ?}
            cr.nfnd := 0;              {reset number of chars matched this range}
            cind := i;                 {save index for exclusion now within}
            for j := last_copied + 1 to ind do begin {once for each uncopied char}
              put_char (buf.str[j]);
              end;
            last_copied := ind;        {all copied up to current input char}
            parse := parse_excl_k;     {now within an exclusion}
            goto next_char;            {go process next input line character}
            end;
          end
        else begin                     {no match with this range}
          cr.nfnd := 0;                {reset this range to no match in progress}
          end
        ;
      end;                             {done with CR abbreviation}
    end;                               {back for next exclusion}

  matching := 0;                       {init number of chars currently matching}
  for i := 1 to ncomm do begin         {once for each possible comment}
    with comm[i]: cr do begin          {CR is crange for this comment}
      if                               {new character matches this range ?}
          (cr.strs.str[cr.nfnd + 1] = c) and {new character matches next range char ?}
          ( (not cr.bols) or           {range start not only at line start ?}
            (ind = 1) or               {at line start anyway ?}
            (cr.nfnd > 0)              {not first character in range ?}
            )
        then begin                     {one more character matches this range}
          cr.nfnd := cr.nfnd + 1;      {log one more character matched}
          if cr.nfnd >= cr.strs.len then begin {matched whole char range ?}
            cr.nfnd := 0;              {reset number of chars matched this range}
            cind := i;                 {save index for comment now within}
            if n_blank > 0 then begin  {previous non-blank exists on this line ?}
              if buf2.len <= n_blank then begin {last out char is non-blank ?}
                string_append1 (buf2, ' '); {always at least one blank before comment}
                end;
              buf2.len :=              {strip off extra trailing blanks, if needed}
                min(buf2.len, max(n_blank + 1, comtab - 1));
              while buf2.len < comtab-1 do begin {pad to start comment at COMTAB}
                string_append1 (buf2, ' ');
                end;
              end;
            string_append (buf2, cr.strs); {transfer comment start to output line}
            last_copied := ind;        {all copied up to current input char}
            parse := parse_comm_k;     {now within a comment}
            goto next_char;            {go process next input line character}
            end;
          end
        else begin                     {no match with this range}
          cr.nfnd := 0;                {reset this range to no match in progress}
          end
        ;
      matching := max(matching, cr.nfnd); {update number of chars matching comments}
      end;                             {done with CR abbreviation}
    end;                               {back for next comment descriptor}

  for j := last_copied + 1 to ind - matching do begin {copy new unmatched chars}
    put_char (buf.str[j]);
    if buf.str[j] = ',' then begin     {found a significant comma ?}
      if (buf.len > j) and (buf.str[j+1] <> ' ') then begin {followed by non-blank ?}
        string_append1 (buf2, ' ');    {insert space after comma}
        end;                           {done with comma followed by non-blank}
      end;                             {done with significant comma}
    end;                               {back to copy next unmatched char}
  last_copied := ind - matching;       {update index of last input char copied}
  end;                                 {done handling char in NORMAL parse mode}
{
*   This character is within an exclusion.  CIND is the exclusion index.
}
parse_excl_k: begin
  string_append1 (buf2, c);            {copy this character to output buffer}
  last_copied := ind;                  {all characters copied so far}
  with excl[cind]: cr do begin         {CR is crange for this exclusion}
    if                                 {new character matches this range ?}
        (cr.stre.str[cr.nfnd + 1] = c) and {new character matches next range char ?}
        (not cr.eole)                  {crange end not just EOL ?}
      then begin                       {one more character matches this range}
        cr.nfnd := cr.nfnd + 1;        {log one more character matched}
        if cr.nfnd >= cr.stre.len then begin {matched whole char range ?}
          reset_matches;               {reset match counters in all char ranges}
          n_blank := buf2.len;         {flag last char as non-blank}
          parse := parse_normal_k;     {back to normal parsing mode}
          end;
        end
      else begin                       {no match with this range}
        cr.nfnd := 0;                  {reset this range to no match in progress}
        end
      ;
    end;                               {done with CR abbreviation}
  end;                                 {end of EXCL parse mode case}
{
*   This character is within a comment.  CIND is the comment index.
}
parse_comm_k: begin
  string_append1 (buf2, c);            {copy this character to output buffer}
  last_copied := ind;                  {all characters copied so far}
  with comm[cind]: cr do begin         {CR is crange for this comment}
    if                                 {new character matches this range ?}
        (cr.stre.str[cr.nfnd + 1] = c) and {new character matches next range char ?}
        (not cr.eole)                  {crange end not just EOL ?}
      then begin                       {one more character matches this range}
        cr.nfnd := cr.nfnd + 1;        {log one more character matched}
        if cr.nfnd >= cr.stre.len then begin {matched whole char range ?}
          reset_matches;               {reset match counters in all char ranges}
          n_blank := buf2.len;         {flag last char as non-blank}
          parse := parse_normal_k;     {back to normal parsing mode}
          end;
        end
      else begin                       {no match with this range}
        cr.nfnd := 0;                  {reset this range to no match in progress}
        end
      ;
    end;                               {done with CR abbreviation}
  end;                                 {end of COMM parse mode case}

      end;                             {end of parse mode cases}
next_char:                             {jump here to advance to next input char}
    end;                               {back for next input line character}
{
*   All done parsing the current input line.
}
  case parse of                        {what is parsing mode at end of line ?}
{
*   Hit end of line while within an exclusion.
}
parse_excl_k: begin
  with excl[cind]: cr do begin         {CR is crange for this exclusion}
    if cr.eole
      then begin                       {range ends at end of line}
        reset_matches;                 {reset match counters in all char ranges}
        parse := parse_normal_k;       {back to normal parsing mode}
        end
      else begin                       {range doesn't end here}
        if cr.slin then begin          {range supposed to have ended by now ?}
          sys_msg_parm_int (msg_parm[1], conn_in.lnum);
          sys_msg_parm_vstr (msg_parm[2], conn_in.tnam);
          sys_msg_parm_vstr (msg_parm[3], cr.strs);
          sys_msg_parm_vstr (msg_parm[4], cr.stre);
          sys_message_bomb ('stuff', 'alcomm_excl_eol', msg_parm, 4);
          end;
        end
      ;
    end;                               {done with CR abbreviation}
  end;                                 {end of EXCL end of line parse mode case}
{
*   Hit end of line while within a comment.
}
parse_comm_k: begin
  with comm[cind]: cr do begin         {CR is crange for this comment}
    if cr.eole
      then begin                       {range ends at end of line}
        reset_matches;                 {reset match counters in all char ranges}
        parse := parse_normal_k;       {back to normal parsing mode}
        end
      else begin                       {range doesn't end here}
        if cr.slin then begin          {range supposed to have ended by now ?}
          sys_msg_parm_int (msg_parm[1], conn_in.lnum);
          sys_msg_parm_vstr (msg_parm[2], conn_in.tnam);
          sys_msg_parm_vstr (msg_parm[3], cr.strs);
          sys_msg_parm_vstr (msg_parm[4], cr.stre);
          sys_message_bomb ('stuff', 'alcomm_comm_eol', msg_parm, 4);
          end;
        end
      ;
    end;                               {done with CR abbreviation}
  end;                                 {end of COMM end of line parse mode case}
    end;                               {end of EOL parse mode cases}

  string_appendn (                     {copy all remaining uncopied characters}
    buf2, buf.str[last_copied + 1], buf.len - last_copied);
  string_unpad (buf2);                 {strip trailing spaces from output line}
  file_write_text (buf2, conn_out, stat); {write line to output file}
  sys_error_abort (stat, '', '', nil, 0);
  goto loop_line;                      {back and do next text line}

eof:                                   {end of input file encountered}
  case parse of                        {what is parsing mode at end of file ?}
{
*   Hit end of file while within an exclusion.
}
parse_excl_k: begin
  with excl[cind]: cr do begin         {CR is crange for this exclusion}
    sys_msg_parm_vstr (msg_parm[1], conn_in.tnam);
    sys_msg_parm_vstr (msg_parm[2], cr.strs);
    sys_msg_parm_vstr (msg_parm[3], cr.stre);
    sys_message_bomb ('stuff', 'alcomm_excl_eof', msg_parm, 3);
    end;                               {done with CR abbreviation}
  end;                                 {end of EXCL end of file parse mode case}
{
*   Hit end of file while within a comment.
}
parse_comm_k: begin
  with comm[cind]: cr do begin         {CR is crange for this comment}
    sys_msg_parm_vstr (msg_parm[1], conn_in.tnam);
    sys_msg_parm_vstr (msg_parm[2], cr.strs);
    sys_msg_parm_vstr (msg_parm[3], cr.stre);
    sys_message_bomb ('stuff', 'alcomm_comm_eof', msg_parm, 3);
    end;                               {done with CR abbreviation}
  end;                                 {end of COMM end of file parse mode case}
    end;                               {end of EOF parse mode cases}

  file_close (conn_in);                {close input file}
  file_close (conn_out);               {close output file}
  end.
