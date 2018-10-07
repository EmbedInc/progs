{   Program REBOOT
*
*   Reboot the machine.
}
program "gui" reboot;
%include 'sys.ins.pas';
%include 'util.ins.pas';
%include 'string.ins.pas';

var
  stat: sys_err_t;

begin
  sys_reboot (stat);
  sys_error_abort (stat, '', '', nil, 0);
  end.
