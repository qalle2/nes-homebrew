# nes-homebrew

Programs for the [Nintendo Entertainment System](http://en.wikipedia.org/wiki/Nintendo_Entertainment_System) (NES).
They can be assembled with [ASM6](https://www.romhacking.net/utilities/674/).

Files for each program:
* `FOO.nes.gz`: assembled iNES ROM
* `FOO.asm`: 6502/ASM6 source code
* `FOO-chr.bin.gz`: raw CHR ROM data (needed if you want to assemble the program yourself)
* `FOO-chr.png`: CHR ROM data as an image (can be encoded with `nes_chr_encode.py` in my [NES utilities](https://github.com/qalle2/nes-util))
* `FOO.png`: screenshot
* `FOO-assemble.sh`: a script intended for my personal use (warning: do not run it before reading it)

Thanks to [pdroms.de](https://pdroms.de) for archiving some of these programs.

## The programs

### Gradient Demo
Shows an animated gradient and moving text.
Warning: you may get a seizure.
The CHR ROM data is in `gradient-chr.bin.gz`.

![gradient.asm](gradient.png)

### Qalle's Brainfuck
A Brainfuck interpreter.
The programs can use 256 bytes of RAM.
Spaces are for readability only.
The CHR ROM data is in `brainfuck-chr.bin.gz`.

![brainfuck.asm](brainfuck.png)

See `brainfuck-examples.txt` for some programs.

References:
* [Wikipedia &ndash; Brainfuck](https://en.wikipedia.org/wiki/Brainfuck)
* [Esolang &ndash; Brainfuck](https://esolangs.org/wiki/Brainfuck)

### Clock
A 24-hour 7-segment clock. NTSC/PAL support.

![clock.asm](clock.png)

### Video
Plays a short video of Doom gameplay (NES, ASM6).

![video.asm](video.png)

### Hello World
Prints *Hello, World!*.

![hello.asm](hello.png)

### Transgender flag
Shows a flag.
Note: this program is heavily optimized for size; it does not represent good programming practice.
The actual size is 97 bytes (including interrupt vectors and CHR data).

![transflag.asm](transflag.png)
