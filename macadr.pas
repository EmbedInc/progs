{   Program MACADR
*
*   Allocates a new permanent Embed Inc MAC address and writes this new address
*   to standard output.
}
program macadr;
%include 'base.ins.pas';

const
  oui5 = 16#80;                        {fixed OUI high bytes of MAC address}
  oui4 = 16#D0;
  oui3 = 16#19;
  seq_fnam = '(cog)progs/macadr/macadr.seq'; {sequence number file name}

var
  fnam:                                {sequence number file name}
    %include '(cog)lib/string_treename.ins.pas';
  ii: sys_int_machine_t;
  mac: sys_macadr_t;                   {new MAC address}
  stat: sys_err_t;                     {completion status}

begin
  string_cmline_init;                  {init for reading the command line}
  string_cmline_end_abort;             {abort on unread command line tokens}

  string_vstring (fnam, seq_fnam, size_char(seq_fnam)); {make seq number file name}
  if not file_exists (fnam) then begin {no MAC addresses sequence number file ?}
    sys_message_bomb ('stuff', 'err_no_macadr_seq', nil, 0);
    end;

  ii := string_seq_get (               {get next unassigned adr low bytes}
    fnam,                              {sequence number file name}
    1,                                 {amount to increment seq number}
    16#0100,                           {initial value on no file (unused)}
    [],
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  mac[0] := ii & 16#FF;                {assemble the complete MAC address}
  mac[1] := rshft(ii, 8) & 16#FF;
  mac[2] := rshft(ii, 16) & 16#FF;
  mac[3] := oui3;
  mac[4] := oui4;
  mac[5] := oui5;

  string_f_macadr (fnam, mac);         {make string representation of MAC adr}
  writeln (fnam.str:fnam.len);         {write it to standard output}
  end.

