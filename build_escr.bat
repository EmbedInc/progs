@echo off
rem
rem   BUILD_ESCR
rem
rem   Build the embed ESCR scripts from this source directory.
rem
setlocal
call build_vars

call src_escr gitcheck
call src_escr make_build
call src_escr make_pic_project
call src_escr pic_module_template
call src_escr unseq

call src_escr repo.ins
call src_escr util.ins
