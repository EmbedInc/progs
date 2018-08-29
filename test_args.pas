{   Program TEST_ARGS arg ... arg
*
*   Shows each individual command line argument as a separate line to standard
*   output, and to the file /temp/test_args.txt.
}
program test_args;
%include 'base.ins.pas';

var
  args: string_list_t;                 {list of command line arguments}
  arg: %include '(cog)lib/string8192.ins.pas'; {one command line argument}
  conn: file_conn_t;                   {connection to output file}
  stat: sys_err_t;                     {completion status}
{
********************************************************************************
*
*   Subroutine MAKE_OUTLINE (S)
*
*   Create the formatted output line in S for the current list entry.  The list
*   is advanced to the next entry.
}
procedure make_outline (               {make output line from list entry}
  in out  s: univ string_var_arg_t);   {returned output string}
  val_param; internal;

begin
  s.len := 0;                          {init returned line to empty}
  if args.str_p = nil then return;     {no current list entry ?}

  string_f_int (s, args.curr);         {make 1-N number of this argument}
  string_appends (s, ': '(0));
  string_append (s, args.str_p^);

  string_list_pos_rel (args, 1);       {advance to next list entry}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  string_cmline_init;                  {init for reading the command line}
  string_list_init (args, util_top_mem_context); {init the arguments list}
  args.deallocable := false;           {won't individually delete list entries}
{
*   Get the command line arguments and save them in the ARGS list.
}
  while true do begin                  {back here each new command line argument}
    string_cmline_token (arg, stat);   {get this command line argument}
    if string_eos(stat) then exit;     {exhausted the command line ?}
    sys_error_abort (stat, '', '', nil, 0);
    args.size := arg.len;              {set size of list entry to create}
    string_list_line_add (args);       {create new list entry, make it current}
    string_copy (arg, args.str_p^);    {save this argument in the list}
    end;                               {back for next command line argument}
{
*   Write each argument as a new line to standard output.
}
  string_list_pos_abs (args, 1);       {go to first list entry}
  while args.str_p <> nil do begin     {once for each list entry}
    make_outline (arg);                {make this output line}
    writeln (arg.str:arg.len);
    end;
{
*   Write each argument as a new line to the log output file.  This is done
*   after writing to standard output in case there are errors opening the file.
}
  file_open_write_text (string_v('/temp/test_args.txt'(0)), '', conn, stat);
  sys_error_abort (stat, '', '', nil, 0);

  string_list_pos_abs (args, 1);       {go to first list entry}
  while args.str_p <> nil do begin     {once for each list entry}
    make_outline (arg);                {make this output line}
    file_write_text (arg, conn, stat);
    sys_error_abort (stat, '', '', nil, 0);
    end;
  file_close (conn);
  end.
