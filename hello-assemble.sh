# Warning: this script DELETES files. Run at your own risk.
rm -f hello.nes hello.nes.gz
asm6 hello.asm hello.nes
gzip -k --best hello.nes
