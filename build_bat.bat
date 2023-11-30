@echo off
rem
rem   BUILD_BAT
rem
rem   Build the Windows BAT files from this source directory.
rem
setlocal
call build_vars

call src_bat dbg
call src_bat doc
call src_bat eagle_img
call src_bat eagle_pcb
call src_bat gitget_embed
call src_bat make_pic_module
call src_bat make_pic_project
call src_bat reformat
