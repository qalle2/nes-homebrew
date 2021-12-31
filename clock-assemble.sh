# Warning: this script DELETES files. Run at your own risk.
rm -f clock-chr.bin clock-chr.bin.gz clock.nes clock.nes.gz
python3 ../nes-util/nes_chr_encode.py clock-chr.png clock-chr.bin
asm6 clock.asm clock.nes
gzip --best clock-chr.bin
gzip -k --best clock.nes
