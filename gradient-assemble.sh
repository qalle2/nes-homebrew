# Warning: this script DELETES files. Run at your own risk.
rm -f gradient-chr.bin gradient-chr.bin.gz gradient.nes gradient.nes.gz
python3 ../nes-util/nes_chr_encode.py gradient-chr.png gradient-chr.bin
asm6 gradient.asm gradient.nes
gzip --best gradient-chr.bin
gzip -k --best gradient.nes
