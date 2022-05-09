# Warning: this script DELETES files. Run at your own risk.
rm -f gradient.nes gradient.nes.gz
asm6 gradient.asm gradient.nes
gzip -k --best gradient.nes
