@echo off
cls

asm6f brainfuck.asm brainfuck.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\brainfuck.nes brainfuck.nes

:end
