# Warning: this script DELETES files. Run at your own risk.
rm -f *.gz
gzip -k --best *.nes
