@echo off
rem
rem   BUILD_ESCR
rem
rem   Build the embed ESCR scripts from this source directory.
rem
setlocal
call build_vars

call src_escr gitcheck
