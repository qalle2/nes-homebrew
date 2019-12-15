@echo off
cls

asm6f colorsquares.asm colorsquares.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\colorsquares.nes colorsquares.nes

:end
