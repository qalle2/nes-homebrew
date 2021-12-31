# Warning: this script DELETES files. Run at your own risk.
rm -f transflag.nes transflag.nes.gz
asm6 transflag.asm transflag.nes
gzip -k --best transflag.nes
