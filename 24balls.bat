@echo off
rem WARNING: this batch file DELETES files. Run at own risk.

cls
if exist 24balls.nes del 24balls.nes

echo === assemble.bat: assembling ===
asm6f 24balls.asm 24balls.nes
if errorlevel 1 goto error
echo.

echo === assemble.bat: comparing to original file ===
fc /b ..\..\nes\old-programs\24balls.nes 24balls.nes
if errorlevel 1 goto error

goto end

:error
echo === assemble.bat: error detected ===

:end
