@echo off
rem This batch file DELETES files. Use at your own risk.

cls

rem Encode sprite data
if exist paint-sprites.chr del paint-sprites.chr
python ..\nes-util\nes_chr_encode.py paint-sprites.png paint-sprites.chr
if errorlevel 1 goto end

rem Assemble
asm6f paint.asm -L paint.nes

rem Delete encoded sprite data
del paint-sprites.chr

:end
