@echo off
rem
rem   BUILD [-dbg]
rem
rem   Build everything from this library.
rem
setlocal
set srcdir=progs
set buildname=

call src_go %srcdir%
call src_getfrom stuff stuff.ins.pas

call src_prog %srcdir% afont_font %1
