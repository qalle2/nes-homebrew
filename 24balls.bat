@echo off
cls

asm6f 24balls.asm 24balls.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\24balls.nes 24balls.nes

:end
