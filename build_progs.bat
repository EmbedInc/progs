@echo off
rem
rem   BUILD_PROGS
rem
rem   Build the executable programs from this source directory.
rem
setlocal
call build_pasinit

rem   Programs with Pascal source modules.
rem
call src_prog %srcdir% afont_font
call src_prog %srcdir% align_comments
call src_prog %srcdir% bom_labels
call src_prog %srcdir% c-f
call src_prog %srcdir% cogserve cogserve_util cogserve_sys
call src_prog %srcdir% copya
call src_prog %srcdir% copyt
call src_prog %srcdir% carcost
call src_prog %srcdir% csv_addval
call src_prog %srcdir% delt
call src_prog %srcdir% downcase_dir
call src_prog %srcdir% elim_redun
call src_prog %srcdir% embed_extool
call src_prog %srcdir% f-c
call src_prog %srcdir% files_same
call src_prog %srcdir% find_string
call src_prog %srcdir% fixname_nef
call src_prog %srcdir% flines
call src_prog %srcdir% font_afont
call src_prog %srcdir% get_newer
call src_prog %srcdir% get_pic_info
call src_prog %srcdir% hex_dump
call src_prog %srcdir% instek_dump
call src_prog %srcdir% l
call src_prog %srcdir% macadr
call src_prog %srcdir% make_debug
call src_prog %srcdir% menu_entry
call src_prog %srcdir% mort
call src_prog %srcdir% mxlookup
call src_prog %srcdir% pic_activity
call src_prog %srcdir% plotfilt
call src_prog %srcdir% primefact
call src_prog %srcdir% quad
call src_prog %srcdir% rdbin
call src_prog %srcdir% rename_raw
call src_prog %srcdir% rename_sym
call src_prog %srcdir% run_cmline
call src_prog %srcdir% runon
call src_prog %srcdir% seqn3
call src_prog %srcdir% slink
call src_prog %srcdir% sum
call src_prog %srcdir% test_args
call src_prog %srcdir% test_sio
call src_prog %srcdir% test_usb
call src_prog %srcdir% text_htm
call src_prog %srcdir% todo_file
call src_prog %srcdir% touch
call src_prog %srcdir% treename
call src_prog %srcdir% waitenter
call src_prog %srcdir% wav_copy
call src_prog %srcdir% wav_csv
call src_prog %srcdir% wav_info
call src_prog %srcdir% xcopyright

rem   Programs with C source modules.
rem
call src_cprg %srcdir% driver_install
