# Warning: this script DELETES files. Run at your own risk.
rm -f brainfuck.nes brainfuck.nes.gz
asm6 brainfuck.asm brainfuck.nes
gzip -k --best brainfuck.nes
