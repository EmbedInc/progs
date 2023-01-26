@echo off
rem
rem   BUILD_PROGS
rem
rem   Build the executable programs from this source directory.
rem
setlocal
call build_pasinit

rem   Install the environment files that are private to this directory.
rem
call src_env %srcdir% progs.msg

rem   Programs with Pascal source modules.
rem
src_progl afont_font
src_progl align_comments
src_progl bom_labels
src_progl c-f
src_progl cogserve
src_progl copya
src_progl copyt
src_progl carcost
src_progl csv_addval
src_progl delt
src_progl dirsize
src_progl downcase_dir
src_progl elim_redun
src_progl embed_extool
src_progl f-c
src_progl files_same
src_progl find_string
src_progl fixname_nef
src_progl flines
src_progl font_afont
src_progl get_newer
src_progl get_pic_info
src_progl hex_dump
src_progl instek_dump
src_progl l
src_progl macadr
src_progl make_debug
src_progl menu_entry
src_progl mort
src_progl mpmem
src_progl mxlookup
src_progl pic_activity
src_progl plotfilt
src_progl primefact
src_progl quad
src_progl rdbin
src_progl rename_raw
src_progl rename_sym
src_progl run_cmline
src_progl runon
src_progl seqn3
src_progl server
src_progl slink
src_progl sum
src_progl test_args
src_progl test_sio
src_progl test_usb
src_progl text_htm
src_progl todo_file
src_progl touch
src_progl treename
src_progl waitenter
src_progl wav_copy
src_progl wav_csv
src_progl wav_info
src_progl xcopyright

rem   Programs with C source modules.
rem
call src_cprg %srcdir% driver_install
