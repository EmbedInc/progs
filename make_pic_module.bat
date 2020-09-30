@echo off
rem
rem   MAKE_PIC_MODULE name [oname]
rem
rem   Create a new module for the current PIC project by copying and customizing
rem   the template.  If a specific template exists with the module name, then
rem   that is used.  Otherwise the generic template is used.
rem
rem   This script must be run in a source code repository.  The BUILD_VARS
rem   script in that repository will be run to get the particulars of the
rem   firmware the new module is for.
rem
rem   The optional ONAME parameter specifies the resulting module name.  The
rem   default is NAME.
rem
rem   This script can also get include files associated with the template
rem   module.
rem
setlocal
if exist build_vars.bat call build_vars

if "%srcdir%"=="" (
  echo SRCDIR not defined.
  exit /b 3
  )
if "%fwname%"=="" (
  echo FWMAME not defined.
  exit /b 3
  )
if "%~1"=="" (
  echo Module name missing on command line.
  exit /b 3
  )

set oname=%~1
if not "%~2"=="" set oname=%~2

set suff=.aspic
set libdir=pic
if "%picclass%"=="dsPIC" (
  set suff=.dspic
  set libdir=dspic
  )

rem ****************
rem
rem   Try various template algorithms implemented in PIC_MODULE_TEMPLATE.ESCR.
rem
set dest=%fwname%_%oname%%suff%
set name=%~1
call progout_var "pic_module_template" templ
if not "%templ%"=="" goto :have_templ

rem ****************
rem
rem   Try name without underscore in master library.
rem
call treename_var "(cog)source/%libdir%/qqq%~1%suff%" templ
set dest=%fwname%%oname%%suff%
if exist "%templ%" goto :have_templ

rem ****************
rem
rem   Default back to generic template module.
rem
call treename_var "(cog)source/%libdir%/qqq_xxxx%suff%" templ
set dest=%fwname%_%oname%%suff%

rem ****************
rem
rem   Copy and customize the module template.  The following variables are set:
rem
rem     TEMPL  -  Treename of the template file.
rem
rem     DEST  -  Destination file name.
rem
:have_templ
echo Creating %dest%
copya -in "%templ%" -out "%dest%" -repl qq1 %srcdir% -repl qq2 %fwname% -repl qq3 %oname% -repl qq4 %pictype%
aspic_fix "%dest%"

rem   Copy and customize the include file associated with the template module,
rem   if one exists.
rem
call treename_var "(cog)source/%libdir%/qqq_%1.ins%suff%" templ
if not exist "%templ%" goto :done_included
set dest=%fwname%_%oname%.ins%suff%
echo Creating %dest%
copya -in "%templ%" -out "%dest%" -repl qq1 %srcdir% -repl qq2 %fwname% -repl qq3 %oname% -repl qq4 %pictype%
aspic_fix "%dest%"
:done_included
