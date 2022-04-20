# nes-homebrew

Programs for the [Nintendo Entertainment System](http://en.wikipedia.org/wiki/Nintendo_Entertainment_System) (NES).
They can be assembled with [ASM6](https://www.romhacking.net/utilities/674/).
Thanks to [pdroms.de](https://pdroms.de) for archiving some of these programs.

## Files for each program

* `FOO.nes.gz`: assembled iNES ROM
* `FOO.asm`: 6502/ASM6 source code
* `FOO-chr.bin.gz`: raw CHR ROM data (needed if you want to assemble the program yourself)
* `FOO-chr.png`: CHR ROM data as an image (can be encoded with `nes_chr_encode.py` in my [NES utilities](https://github.com/qalle2/nes-util))
* `FOO.png`: screenshot
* `FOO-assemble.sh`: a script that assembles the program (warning: do not run it before reading it)

## The programs

### Gradient Demo
Shows an animated gradient and moving text.
Warning: you may get a seizure.

![gradient.asm](gradient.png)

### Qalle's Brainfuck
A Brainfuck interpreter.
The programs can use 256 bytes of RAM.
Spaces are for readability only.

![brainfuck.asm](brainfuck.png)

See `brainfuck-examples.txt` for some programs.

References:
* [Wikipedia &ndash; Brainfuck](https://en.wikipedia.org/wiki/Brainfuck)
* [Esolang &ndash; Brainfuck](https://esolangs.org/wiki/Brainfuck)

### Clock
A 24-hour 7-segment clock. NTSC/PAL support.

![clock.asm](clock.png)

### Video
Plays a short video of Doom gameplay.

![video.asm](video.png)

### Hello World
Prints *Hello, World!*.

![hello.asm](hello.png)

### Transgender flag
Shows the transgender flag.
Note: this program is heavily optimized for size; it does not represent good programming practice.
The actual size is 95 bytes (including interrupt vectors and CHR data).

![transflag.asm](transflag.png)

The program in hexadecimal:
```
a2038e00202c022010fbcad0f88a20f1
ffa002a2188d0720cad0faa9ff88d0f3
a93f20f1ffa003b9f8ff8d07208810f7
a92020f1ffa005b9ebffa2c08d0720ca
d0fa8810f2a90a8d0120000102000201
8d06208e06206025210030a1ffebff
```
