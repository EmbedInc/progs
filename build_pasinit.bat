@echo off
rem
rem   Set up for building a Pascal module.
rem
call build_vars

call treename_var (cog)src/%srcdir% tnam
cd /d "%tnam%"

call src_getbase
call src_getfrom sys sys_sys2.ins.pas
call src_getfrom file cogserve.ins.pas
call src_getfrom math math.ins.pas
call src_getfrom stuff stuff.ins.pas
call src_getfrom hier hier.ins.pas

call src_builddate "%srcdir%"
