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
call src_getfrom math math.ins.pas

rem   Programs with Pascal source modules.
rem
call src_prog %srcdir% afont_font %1
call src_prog %srcdir% align_comments %1
call src_prog %srcdir% bom_labels %1
call src_prog %srcdir% c-f %1
call src_prog %srcdir% carcost %1
call src_prog %srcdir% csv_addval %1
call src_prog %srcdir% elim_redun %1
call src_prog %srcdir% embed_extool %1
call src_prog %srcdir% f-c %1
call src_prog %srcdir% files_same %1
call src_prog %srcdir% find_string %1
call src_prog %srcdir% fixname_nef %1
call src_prog %srcdir% flines %1
call src_prog %srcdir% font_afont %1
call src_prog %srcdir% get_newer %1
call src_prog %srcdir% get_pic_info %1
call src_prog %srcdir% hex_dump %1
call src_prog %srcdir% instek_dump %1
call src_prog %srcdir% macadr %1
call src_prog %srcdir% mort %1
call src_prog %srcdir% pic_activity %1
call src_prog %srcdir% primefact %1
call src_prog %srcdir% quad %1
call src_prog %srcdir% rename_raw %1
call src_prog %srcdir% rename_sym %1
call src_prog %srcdir% run_cmline %1
call src_prog %srcdir% sum %1
call src_prog %srcdir% test_args %1
call src_prog %srcdir% test_partref %1
call src_prog %srcdir% test_sio %1
call src_prog %srcdir% test_usb %1
call src_prog %srcdir% text_htm %1
call src_prog %srcdir% waitenter %1
call src_prog %srcdir% wav_copy %1
call src_prog %srcdir% wav_csv %1
call src_prog %srcdir% wav_info %1

rem   Programs with C source modules.
rem
call src_cprg %srcdir% driver_install %1
