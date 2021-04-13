@echo off
rem
rem   EAGLE_IMG
rem
rem   Make the PCB assembly drawing files from the raw images exported by FILE >
rem   EXPORT > IMAGE in the board editor.  The overall procedure for generating
rem   the drawing files is:
rem
rem     1 - On the final board but before adding the layer names outside the
rem         board area, run ULP GRID_BRD.
rem
rem     2 - Save the board as GRID.BRD.
rem
rem     3 - Run the script GRID_TOP.  This will display the drawing for the top
rem         side of the board.
rem
rem     4 - Select the menu entry FILE > EXPORT > IMAGE.  Set the image file
rem         name to \temp\top.tif, and the resolution to 600 DPI.
rem
rem     5 - Run the script GRID_BOT.  This will display the drawing for the
rem         bottom side of the board.
rem
rem     6 - Select the menu entry FILE > EXPORT > IMAGE.  Use the same settings
rem         as before, except the image file name must be \temp\bot.tif this
rem         time.
rem
rem     7 - Run this script in the directory for the board.  The directory name
rem         must be the same as the board name.
rem
rem   This procedure will create the BBB_TOP.GIF, BBB_BOT.GIF, and BBB_BOTF.GIF
rem   drawing files, where BBB is the board name.  These files are expected by
rem   the EAGLE_ASSY script, which is used to make the package of assembly
rem   files.
rem
rem   This script also creates the image files TOP.GIF, BOT.GIF, and BOTF.GIF.
rem   These are sized to view whole on a 1920 x 1200 screen, and are not
rem   included in the package of assembly files.
rem
setlocal
call treename_var . dir
call leafname_var %dir% brd
call treename_var /temp tdir

if not exist "%tdir%\top.tif" (
  echo TOP.TIF file not available.
  exit /b 3
  )
if not exist "%tdir%\bot.tif" (
  echo BOT.TIF file not available.
  exit /b 3
  )

if exist "%brd%_top.gif" del "%brd%_top.gif"
if exist "%brd%_bot.gif" del "%brd%_bot.gif"
if exist "%brd%_botf.gif" del "%brd%_botf.gif"
if exist "top.gif" del "top.gif"
if exist "bot.gif" del "bot.gif"
if exist "botf.gif" del "botf.gif"

echo %brd%_top.gif
image_copy "%tdir%\top.tif" %brd%_top.gif -form -gray

echo %brd%_bot.gif
image_copy "%tdir%\bot.tif" %brd%_bot.gif -form -gray

echo %brd%_botf.gif
image_flip "%tdir%\bot.tif" "%tdir%\botf.img" -fliplr
image_copy "%tdir%\botf.img" %brd%_botf.gif -form -gray

echo top.gif
image_resize %brd%_top.gif top.gif -fit 1920 1200 -form -gray
echo bot.gif
image_resize %brd%_bot.gif bot.gif -fit 1920 1200 -form -gray
echo botf.gif
image_resize %brd%_botf.gif botf.gif -fit 1920 1200 -form -gray

image_disp -dev screen top.gif bot.gif botf.gif
