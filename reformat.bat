@echo off
rem
rem   REFORMAT [fnam]
rem
rem   Adjust the formatting of all files with names that match the FNAM
rem   pattern and have a known suffix.  The adjustments applied depend
rem   on the file name suffix.  The following suffixes are supported:
rem
rem     .pas, .cog  -  Pascal source
rem
rem       Tabs converted to hard spaces, with tab stops every two columns.
rem       End of line comments aligned to start in column 40.
rem
rem     .ftn, .f77  -  FORTRAN source
rem
rem       Tabs converted to hard spaces, with tab stops in column 7 and
rem       every second column after that.  End of line comments will start
rem       in column 40.  End of line comments start with "{".
rem
rem     .c, .h, .c18, .h18. .c30, .h30, .xc16  -  C source
rem
rem       Tabs converted to hard spaces, with tab stops every two columns.
rem       End of line comments aligned to start in column 40.  End of line
rem       comments either start with "//", or "/*".
rem
rem     .aspic, .dspic  -  PIC assembler source
rem
rem       Tabs converted to single spaces.  Labels aligned in column 1,
rem       opcodes in column 10, operands in column 18, and end of line
rem       comments in column 30.
rem
rem     .escr, .es  -  Embed scripts
rem
rem       Tabs converted to single spaces.  End of line comments aligned in
rem       column 30.
rem
setlocal
set patt=%~1
if "%patt%"=="" set patt=*
for %%a in (%patt%) do (

  for /f "delims=" %%b in ('leafname "%%~a" .pas .cog') do (
    if not "%%~b"=="%%~a" (
      echo %%~a
      copya -in "%%~a" -out temp.reformat.pas -tabs 3 5 7 9 11 40
      align_comments temp.reformat.pas -out "%%~a"
      del temp.reformat.pas
      )
    )

  for /f "delims=" %%b in ('leafname "%%~a" .ftn .f77') do (
    if not "%%~b"=="%%~a" (
      echo %%~a
      copya -in "%%~a" -out temp.reformat.ftn -tabs 7 9
      align_comments temp.reformat.ftn -out "%%~a"
      del temp.reformat.ftn
      )
    )

  for /f "delims=" %%b in ('leafname "%%~a" .c .h .c18 .h18 .c30 .h30 .xc16') do (
    if not "%%~b"=="%%~a" (
      echo %%~a
      copya -in "%%~a" -out temp.reformat.c -tabs 3 5 7 9 11 40
      align_comments temp.reformat.c -out "%%~a"
      del temp.reformat.c
      )
    )

  for /f "delims=" %%b in ('leafname "%%~a" .aspic .dspic') do (
    if not "%%~b"=="%%~a" (
      echo %%~a
      aspic_fix "%%~a"
      )
    )

  for /f "delims=" %%b in ('leafname "%%~a" .escr .es') do (
    if not "%%~b"=="%%~a" (
      echo %%~a
      copya -in "%%~a" -out temp.reformat.escr -tabs 3 5 7 9 11 30
      align_comments temp.reformat.escr -out "%%~a"
      del temp.reformat.escr
      )
    )
  )
