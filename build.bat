@echo off
rem
rem   Build everything from this source directory.
rem
setlocal
call godir "(cog)source/progs"

call build_progs
call build_doc
