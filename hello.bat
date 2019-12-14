@echo off
cls

echo === assemble.bat: assembling ===
rem see https://github.com/freem/asm6f
rem and http://qallee.net/misc/asm6f-win64.zip
asm6f hello.asm hello.nes
if errorlevel 1 goto error

goto end

:error
echo === assemble.bat: an error was detected ===

:end
