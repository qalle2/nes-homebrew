@echo off
cls

asm6f gradient.asm gradient.nes
if errorlevel 1 goto end

echo.
fc /b ..\..\nes\old-programs\gradient.nes gradient.nes

:end
