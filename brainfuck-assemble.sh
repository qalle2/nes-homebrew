# Warning: this script DELETES files. Run at your own risk.
rm -f brainfuck-chr.bin brainfuck-chr.bin.gz brainfuck.nes brainfuck.nes.gz
python3 ../nes-util/nes_chr_encode.py --palette 000000 ff00ff 00ffff ffffff brainfuck-chr.png brainfuck-chr.bin
asm6 brainfuck.asm brainfuck.nes
gzip --best brainfuck-chr.bin
gzip -k --best brainfuck.nes
