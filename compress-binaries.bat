@echo off
rem WARNING: this batch file DELETES files. Run at own risk.
if exist binaries.zip del binaries.zip
7z a -mx9 -bd -bso0 binaries.zip *.nes
