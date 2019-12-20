@echo off
cls

asm6f clock.asm clock.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\clock.nes clock.nes

:end
