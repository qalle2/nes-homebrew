# Encode CHR ROM data for gradient.asm. Warning: deletes files. Run at your own risk.
rm -f gradient-chr.bin gradient-chr.bin.gz
python3 ../nes-util/nes_chr_encode.py gradient-chr.png gradient-chr.bin
gzip -k --best gradient-chr.bin
