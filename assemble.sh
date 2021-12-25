# Warning: this script DELETES files. Run at your own risk.
if (($# != 1)); then echo "Argument: file to assemble (without extension)"; exit; fi
rm -f $1.nes
asm6 $1.asm $1.nes
