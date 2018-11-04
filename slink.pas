{   Program SLINK [<options>]
*
*   Manipulate a symbolic file system link.  The command line options are:
*
*   <pathname>
*
*     Symbolic link name or link text.  The first argument not starting with
*     "-" is assumed to be the name of a symbolic link.  The second pathname
*     argument, if present, is assumed to be the text for the symbolic link.
*     A link name is always required, although it can be supplied using the
*     -NAME option, below.  The link text may also be supplied using the
*     -VAL option, below.
*
*   -NAME pathname
*
*     Explicitly give the link name.  This method is required if the link
*     name starts with "-".
*
*   -VAL text
*
*     Explicitly give the link text.  This method is required if the link
*     text starts with "-".
*
*   -REPL
*
*     Replace existing file or link with the same name as the link, if
*     neccessary.  This is the default.
*
*   -NREPL
*
*     It is an error to attempt to create a link with the same name as a
*     previously existing file or link.  The default is -REPL.
*
*   -DEL
*
*     Delete the link.
*
*   If only a link name is supplied, LINK will return TRUE status if the
*   link exists and is a link, otherwise it will return FALSE status.
*
*   If a link name and text is supplied, a new link will be created, subject
*   to the other command line arguments.
*
*   -DEL may only be used with link name (no link text).
}
program slink;
%include '/cognivision_links/dsee_libs/sys/sys.ins.pas';
%include '/cognivision_links/dsee_libs/util/util.ins.pas';
%include '/cognivision_links/dsee_libs/string/string.ins.pas';
%include '/cognivision_links/dsee_libs/file/file.ins.pas';

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  pick: sys_int_machine_t;             {number of token picked from list}
  create_flags: file_crea_t;           {creation behavior flags}
  name_set: boolean;                   {link name was supplied}
  text_set: boolean;                   {link text was supplied}
  repl: boolean;                       {OK to overwrite existing file}
  del: boolean;                        {delete link}
  name,                                {link name}
  text,                                {link text}
  opt:                                 {command line option}
    %include '/cognivision_links/dsee_libs/string/string_treename.ins.pas';

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;

label
  next_opt, done_opts;

begin
  string_cmline_init;                  {init for parsing command line}
{
*   Init choices before processing command line arguments.
}
  name_set := false;
  text_set := false;
  repl := true;
  del := false;
{
*   Back here each new command line option.
}
next_opt:
  string_cmline_token (opt, stat);     {get next command line option name}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  if (opt.len >= 1) and (opt.str[1] <> '-') then begin {link name or text token ?}
    if not name_set then begin         {assume this is link name ?}
      string_copy (opt, name);
      name_set := true;
      goto next_opt;
      end;
    if text_set then begin             {already got link text ?}
      sys_msg_parm_vstr (msg_parm[1], opt);
      sys_message_bomb ('string', 'cmline_opt_conflict', msg_parm, 1);
      end;
    string_copy (opt, text);           {set link text}
    text_set := true;
    goto next_opt;
    end;
  string_upcase (opt);                 {make upper case for matching list}
  string_tkpick80 (                    {pick option name from list}
    opt,                               {option name}
    '-NAME -VAL -REPL -NREPL -DEL',
    pick);                             {number of picked option}
  case pick of                         {do routine for specific option}
{
*   -NAME linkname
}
1: begin
  string_cmline_token (name, stat);
  name_set := true;
  end;
{
*   -VAL text
}
2: begin
  string_cmline_token (text, stat);
  text_set := true;
  end;
{
*   -REPL
}
3: begin
  repl := true;
  end;
{
*   -NREPL
}
4: begin
  repl := false;
  end;
{
*   -DEL
}
5: begin
  del := true;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;             {complain about unrecognized option and bomb}
    end;                               {end of command line option cases}

  string_cmline_parm_check (stat, opt); {check for bad parameter to command line opt}
  goto next_opt;                       {back for next command line option}
done_opts:                             {all done reading command line}

  if not name_set then begin           {no link name supplied ?}
    sys_message_bomb ('file', 'link_no_name', nil, 0);
    end;

  if del and text_set then begin
    sys_message_bomb ('file', 'link_del_incompatible', nil, 0);
    end;
{
*   Do command if deleting link.
}
  if del then begin                    {deleting link ?}
    file_link_del (name, stat);        {try to delete the link}
    sys_error_abort (stat, '', '', nil, 0);
    return;
    end;
{
*   Do command if inquiring whether link exists.
}
  if not text_set then begin           {just inquiring link exist ?}
    file_link_resolve (name, text, stat); {try to read link}
    if sys_error(stat)
      then begin                       {error reading link}
        sys_exit_false;
        end
      else begin                       {reading link was successful}
        sys_exit_true;
        end
      ;
    end;
{
*   Create a new link.
}
  if repl
    then create_flags := [file_crea_overwrite_k]
    else create_flags := [];
  file_link_create (name, text, create_flags, stat);
  sys_error_abort (stat, '', '', nil, 0);
  end.
