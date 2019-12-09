@echo off
rem
rem   BUILD_BAT
rem
rem   Build the Windows BAT files from this source directory.
rem
setlocal
call build_vars

call src_bat gitget_embed
