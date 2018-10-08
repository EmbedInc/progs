@echo off
rem
rem   Set up for building a Pascal (.pas suffix) module.
rem
set srcdir=progs
set buildname=

call src_go "%srcdir%"
call src_getfrom sys base.ins.pas
call src_getfrom sys sys.ins.pas
call src_getfrom util util.ins.pas
call src_getfrom string string.ins.pas
call src_getfrom file file.ins.pas
call src_getfrom math math.ins.pas
call src_getfrom stuff stuff.ins.pas
call src_builddate "%srcdir%"