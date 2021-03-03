@echo off
rem
rem   DOC <topic>
rem
rem   This command brings up a documentation file for reading.
rem
setlocal

call :trypath "~/com/%~1.escr"
if not errorlevel 1 exit /b 0

call :trypath "~/com/%~1.bat"
if not errorlevel 1 exit /b 0

call :trypath "(cog)doc/%~1.pdf"
if not errorlevel 1 exit /b 0

call :trypath "(cog)doc/%~1.htm"
if not errorlevel 1 exit /b 0

call :trypath "(cog)doc/%~1/index.htm"
if not errorlevel 1 exit /b 0

call :trypath "(cog)doc/%~1.txt"
if not errorlevel 1 exit /b 0

call :trypath "(cog)bat/%~1.escr"
if not errorlevel 1 exit /b 0

call :trypath "(cog)bat/%~1.bat"
if not errorlevel 1 exit /b 0

call :trypath "(cog)com/%~1.escr"
if not errorlevel 1 exit /b 0

call :trypath "(cog)com/%~1.bat"
if not errorlevel 1 exit /b 0

call :trypath "(cog)lib/%~1"
if not errorlevel 1 exit /b 0

call :trypath "(cog)lib/%~1.ins.pas"
if not errorlevel 1 exit /b 0

call :trypath "(cog)node/env/%1"
if not errorlevel 1 exit /b 0

call :trypath "(cog)site/env/%1"
if not errorlevel 1 exit /b 0

call :trypath "(cog)env/%1"
if not errorlevel 1 exit /b 0

echo No such documentation file found.
exit /b 3

rem ****************************************************************************
rem
rem   Subroutine TRYPATH path
rem
rem   Try to display the indicated documentation file.  If the file exists, then
rem   the file is displayed and this routine returns with 0 exit status.  If the
rem   file does not exist, then this routine returns with a exit status of 1.
rem
rem   PATH is a Embed portable pathname.
rem
:trypath
setlocal
call treename_var "%~1" tnam
if not exist "%tnam%" exit /b 1

rem   This doc file exists.
rem
call leafname_var "%tnam%" lnam

rem   Check for file name suffixes that indicate the file can be displayed by
rem   running it.
rem
call leafname_var "%lnam%" gnam .htm .html .pdf
if not "%gnam%"=="%lnam%" (
  server cmd /c "%tnam%"
  exit /b 0
  )

rem   Make a copy of the file in the temp directory, then display that.
rem
copya "%tnam%" "%temp%/view_doc.txt"
server -in "%temp%" -run notepad view_doc.txt
exit /b 0
