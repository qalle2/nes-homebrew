# Encode CHR ROM data for brainfuck.asm. Warning: deletes files. Run at your own risk.
rm -f brainfuck-chr.bin brainfuck-chr.bin.gz
python3 ../nes-util/nes_chr_encode.py --palette 000000 ff00ff 00ffff ffffff brainfuck-chr.png brainfuck-chr.bin
gzip -k --best brainfuck-chr.bin
