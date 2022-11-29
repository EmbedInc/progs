@echo off
rem
rem   GITGET_EMBED [path1 ... pathN name]
rem
rem   Create or update a single or all Embed GIT repositories on this machine.
rem   The existing git repository directories, if any, will be completely
rem   deleted, then the latest version downloaded from the official server.
rem
rem   With no command line arguments, all public Embed GIT repositories are
rem   created or updated on the local machine.  When NAME is supplied, then only
rem   the public Embed GIT repository of that name will be created or updated.
rem
rem   The PATHn arguments followed by NAME specify the path of the GIT
rem   repository within the Embed SOURCE directory.  For example, the USBProg
rem   firmware source code is at SOURCE > PICPRG > EUSB.  The command line
rem   arguments for just that GIT repository should be "picprg eusb".  In
rem   contrast, the SYS library is at SOURCE > SYS, so the command line
rem   arguments for that should be just "sys".
rem
rem   ANY LOCAL CHANGES SINCE THE LAST OFFICIAL VERSION WILL BE LOST.
rem
rem   This script also guarantees that the minimum Embed source code and build
rem   directories structure exists.
rem
setlocal

rem   Make sure that Embed software is installed on this machine, then go to the
rem   installation directory.
rem
call treename_var (cog)env/global.env tnam
if not exist "%tnam%" goto :no_embed
call treename_var (cog)doc/environment_files.txt tnam
if not exist "%tnam%" goto :no_embed
call treename_var (cog)com/copya.exe tnam
if not exist "%tnam%" goto :no_embed
goto :is_embed
:no_embed
echo No Embed software installation directory found
exit /b 3
:is_embed
call godir (cog)
echo Embed software installation directory is at %CD%

rem   Make sure the SOURCE and SRC directories exist.
rem
call treename_var (cog)source tnam
if not exist %tnam% mkdir source
call treename_var (cog)src tnam
if not exist %tnam% mkdir src

rem   If NAME was supplied on the command line, get that single repository.
rem
if not "%1"=="" (
  call :gitget %1 %2 %3 %4 %5 %6 %7 %8 %9
  exit /b 0
  )

rem   Get all the Embed public respositories.
rem
call :gitget buildscr
call :gitget can
call :gitget chess
call :gitget code
call :gitget csvana
call :gitget displ
call :gitget dspic
call :gitget email
call :gitget escr
call :gitget file
call :gitget fline
call :gitget gui
call :gitget hier
call :gitget img
call :gitget imgdisp
call :gitget imgedit
call :gitget imgprogs
call :gitget ioext ioext
call :gitget ioext usbcan
call :gitget math
call :gitget mdev
call :gitget menu
call :gitget mlang
call :gitget pbp
call :gitget phot
call :gitget pic
call :gitget picprg eusb
call :gitget picprg lprg
call :gitget picprg picprg
call :gitget picprg pprghost
call :gitget picprg pprog
call :gitget picprg pptst
call :gitget pntcalc
call :gitget progs
call :gitget qprot u1ex
call :gitget ray
call :gitget rend core
call :gitget rend test
call :gitget rend win
call :gitget sst
call :gitget strflex
call :gitget string
call :gitget stuff
call :gitget syn
call :gitget syo
call :gitget sys
call :gitget usb usbser
call :gitget utest
call :gitget util
call :gitget vect

exit /b 0

rem ****************************************************************************
rem
rem   Subroutine GITGET [path1 ... pathN] repo
rem
rem   Get the GIT repository REPO in the Embed SOURCE directory.
rem
:gitget
set repo=%~1
set path1=
set path2=
set path3=
set path4=
set path5=
set path6=
set path7=
set path8=
set path9=
if not "%2"=="" (
  set path1=%~1
  set repo=%~2
  )
if not "%3"=="" (
  set path2=%~2
  set repo=%~3
  )
if not "%4"=="" (
  set path3=%~3
  set repo=%~4
  )
if not "%5"=="" (
  set path4=%~4
  set repo=%~5
  )
if not "%6"=="" (
  set path5=%~5
  set repo=%~6
  )
if not "%7"=="" (
  set path6=%~6
  set repo=%~7
  )
if not "%8"=="" (
  set path7=%~7
  set repo=%~8
  )
if not "%9"=="" (
  set path8=%~8
  set repo=%~9
  )

rem   Determine the remote repository name in RREPO.  This is sometimes
rem   different from the local repository name.
rem
set rrepo=%repo%
if "%path1%"=="rend" (
  if "%repo%"=="core" set rrepo=RendCore
  if "%repo%"=="test" set rrepo=rend_test
  if "%repo%"=="win" set rrepo=RendWin
  )
if "%path1%"=="qprot" (
  if "%repo%"=="u1ex" set rrepo=QprotU1ex
  )

rem   Make sure the directory in SRC exists.
rem
call godir (cog)src
if not exist "%~1" mkdir "%~1"

rem   Make sure the directory tree in SOURCE exists.
rem
call godir (cog)source
if not "%path1%"=="" (
  if not exist "%path1%" mkdir "%path1%"
  cd "%path1%"
  )
if not "%path2%"=="" (
  if not exist "%path2%" mkdir "%path2%"
  cd "%path2%"
  )
if not "%path3%"=="" (
  if not exist "%path3%" mkdir "%path3%"
  cd "%path3%"
  )
if not "%path4%"=="" (
  if not exist "%path4%" mkdir "%path4%"
  cd "%path4%"
  )
if not "%path5%"=="" (
  if not exist "%path5%" mkdir "%path5%"
  cd "%path5%"
  )
if not "%path6%"=="" (
  if not exist "%path6%" mkdir "%path6%"
  cd "%path6%"
  )
if not "%path7%"=="" (
  if not exist "%path7%" mkdir "%path7%"
  cd "%path7%"
  )
if not "%path8%"=="" (
  if not exist "%path8%" mkdir "%path8%"
  cd "%path8%"
  )

rem   Create/update the repository.
rem
if exist "%repo%" (
  attrib "%repo%\*" -h -r /s
  delt "%repo%"
  )
git clone "https://github.com/EmbedInc/%rrepo%" "%repo%"
goto :eof
