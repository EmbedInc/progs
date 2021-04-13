@echo off
rem
rem   EAGLE_PCB
rem
rem   Create a ZIP file containing the generic package of files for
rem   having a PCB fabricated.  This script must be run in the Eagle
rem   project directory for the board after all the manufacturing
rem   files are created.  The board name is assumed to be the same
rem   as the leafname of the directory this script is run in.
rem
rem   The following files are required to exist before this script
rem   is run, and are always included in the package:
rem
rem     .plc  -  component side silk screen
rem     .stc  -  component side solder mask
rem     .cmp  -  component side copper
rem     .sol  -  solder side copper
rem     .drl  -  list of drill sizes and tool numbers
rem     .drd  -  drill data
rem
rem   The following files are included in the package if they are
rem   present:
rem
rem     .sts  -  solder side solder mask
rem     .pls  -  solder side silk screen
rem     .ly2 ... .ly15  -  top to bottom inner copper layers
rem     .out  -  board outline only
rem     .dri  -  human readable drill information
rem     .gpi  -  human readable photoplotter information
rem
rem   In addition a README_FAB.TXT file is always created and added to
rem   the package.  It contains a one-line description of each of the
rem   other files in the package.  If the files NOTES_FAB.TXT exists,
rem   then its contents will be appended to the README_FAB.TXT file.
rem
rem   The steps in creating the right files in Eagle from a completed
rem   board layout are:
rem
rem   1  -  Make sure there are fiducials in two opposite corners.
rem
rem   2  -  Add the layer name to each layer outside the board area.
rem
rem   3  -  Run DRILLCFG.ULP from the board editor.  Specify inches.
rem         Go back and fix hole sizes that aren't in the ~/eagle/holes.txt
rem         list.
rem
rem   4  -  Run the EXCELLON.CAM CAM processor job to create the
rem         drill data (.DRD) file.
rem
rem   5  -  Run the Generic2L (2 layer boards) or Generic4L
rem         (4 layer boards) CAM processor jobs.  This will produce the
rem         gerber files for each photo-plotted layer.
rem
rem         NOTE 1: Delete the solder paste mask output file(s) if package
rem           is for PCB only, not full board manufacturing.
rem
rem   8  -  Run this script to create the ZIP file with all the needed
rem         files.
rem
rem   7  -  Visually verify the Gerber files with a Gerber file viewer.
rem
setlocal
call treename_var . tnam
call leafname_var "%tnam%" brd

rem
rem   Write one line to the README_FAB.TXT file giving a quick exlpanation of each
rem   file in the package.
rem
copya -s "File names:" -out readme_fab.txt
copya -s "  .plc  -  Top silk screen" -out readme_fab.txt -append
copya -s "  .stc  -  Top solder mask" -out readme_fab.txt -append
copya -s "  .cmp  -  Top copper" -out readme_fab.txt -append
if exist %brd%.ly2 copya -s "  .ly2 to .lyN  -  Inner layers from top to bottom" -out readme_fab.txt -append
copya -s "  .sol  -  Bottom copper" -out readme_fab.txt -append
if exist %brd%.sts copya -s "  .sts  -  Bottom solder mask" -out readme_fab.txt -append
if exist %brd%.pls copya -s "  .pls  -  Bottom silk screen" -out readme_fab.txt -append
copya -s "  .drl  -  Drill sizes" -out readme_fab.txt -append
copya -s "  .drd  -  Drill data" -out readme_fab.txt -append
if exist %brd%.out copya -s "  .out  -  Board outline" -out readme_fab.txt -append
if exist %brd%.dri copya -s "  .dri  -  Human readable drill information" -out readme_fab.txt -append
if exist %brd%.gpi copya -s "  .gpi  -  Human readable photoplotter information" -out readme_fab.txt -append
rem
rem   Add special notes for this board.
rem
if exist notes_fab.txt copya notes_fab.txt -append readme_fab.txt
rem
rem   Build the ZIP package.
rem
if exist %brd%_fab.zip del %brd%_fab.zip
"c:\program files\WinZip\wzzip" -ex %brd%_fab.zip readme_fab.txt %brd%.plc %brd%.stc %brd%.cmp %brd%.ly* %brd%.sol %brd%.sts %brd%.drl %brd%.drd %brd%.dri %brd%.gpi %brd%.pls* %brd%.out*

"c:\program files\WinZip\wzunzip" -vbf %brd%_fab.zip
copya -list -s ""
copya -list readme_fab.txt
