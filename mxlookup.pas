{   Program MXLOOKUP domain
*
*   Show the MX (mail exchange) servers for a particular domain.
}
program mxlookup;
%include 'base.ins.pas';

var
  domain:                              {domain name to look up MX hosts for}
    %include '(cog)lib/string256.ins.pas';
  mx_p: sys_mxdom_p_t;                 {pointer to MX info for the domain}
  host_p: sys_mxrec_p_t;               {pointer to info about one MX host}
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_token (domain, stat);  {get domain name from command line}
  sys_error_abort (stat, '', '', nil, 0);
  string_cmline_req_check (stat);      {domain name is required on command line}
  string_cmline_end_abort;             {nothing more allowed on the command line}

  sys_mx_lookup (                      {look up MX hosts for the domain}
    util_top_mem_context,              {parent memory context}
    domain,                            {domain name}
    mx_p,                              {returned pointer to MX info}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  writeln (mx_p^.n, ' MX hosts found');

  host_p := mx_p^.list_p;              {point to first host in list}
  while host_p <> nil do begin         {loop thru the list}
    writeln (
      'Pref ', host_p^.pref:5,
      ', TTL ', host_p^.ttl:6,
      ', "', host_p^.name_p^.str:host_p^.name_p^.len, '"');
    host_p := host_p^.next_p;          {advance to next list entry}
    end;                               {back to process this new list entry}

  sys_mx_dealloc (mx_p);               {deallocate the MX records}
  end.
