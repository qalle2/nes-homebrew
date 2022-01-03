# Warning: this script deletes files. Run at your own risk.
rm -f video-chr.bin video-chr.bin.gz video.nes video.nes.gz
python3 video-generate-chr.py video-chr.bin
asm6 video.asm video.nes
gzip --best video-chr.bin
gzip -k --best video.nes
