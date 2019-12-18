@echo off
cls

asm6f paint.asm paint.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\paint.nes paint.nes

:end
