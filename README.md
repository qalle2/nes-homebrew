# nes-homebrew

Programs for the [Nintendo Entertainment System](http://en.wikipedia.org/wiki/Nintendo_Entertainment_System) (NES).
They can be assembled with [ASM6](https://www.romhacking.net/utilities/674/).
The assembled programs are in files with extension `.nes.gz`.

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

### Hello World
Prints *Hello, World!*.

![hello.asm](hello.png)

### Transgender flag
Shows a flag.
Note: this program is heavily optimized for size; it does not represent good programming practice.
The actual size is 97 bytes (including interrupt vectors and CHR data).

![transflag.asm](transflag.png)

### Clock
**This program does not assemble with ASM6 at the moment.**
A 24-hour 7-segment clock. NTSC/PAL support.

![clock.asm](clock.png)
