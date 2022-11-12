# Warning: this script deletes files. Run at your own risk.

rm -f video-chr.bin
python3 video-generate-chr.py video-chr.bin
asm6 video.asm video.nes
gzip -9f video-chr.bin
gzip -9fk video-nt.bin video.nes
