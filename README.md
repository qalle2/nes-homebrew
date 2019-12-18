# nes-homebrew

My 6502 assembly programs for the [Nintendo Entertainment System](http://en.wikipedia.org/wiki/Nintendo_Entertainment_System) (NES).

Thanks to [pdroms.de](https://pdroms.de) for archiving some of these programs.

## How to assemble
* Install **asm6f**:
  * [GitHub page](https://github.com/freem/asm6f)
  * [64-bit Windows binary](http://qallee.net/misc/asm6f-win64.zip) (compiled by me)
* Either run the program's batch file (only works on Windows) or assemble manually: `asm6f file.asm file.nes`

## The programs
Assembled programs are in `binaries.zip`.

### 24balls.asm
Shows 24 bouncing balls.

![24balls.asm](24balls.png)

### brainfuck.asm
KHS-NES-Brainfuck, a Brainfuck interpreter. The programs can use 256 bytes of RAM. Spaces are for readability only.

![brainfuck.asm](brainfuck.png)

### colorsquares.asm
Prints colored squares. On each frame, two adjacent squares trade places.

![colorsquares.asm](colorsquares.png)

### gradient.asm
Prints an animated gradient and moving text. Warning: you may get a seizure.

![gradient.asm](gradient.png)

### hello.asm
Prints *Hello, World!*. Only tested on [FCEUX](http://www.fceux.com).

![hello.asm](hello.png)

## References
* [NESDev Wiki &ndash; init code](http://wiki.nesdev.com/w/index.php/Init_code)
* [NESDev Wiki &ndash; PPU registers](http://wiki.nesdev.com/w/index.php/PPU_registers)
* [Wikipedia &ndash; Brainfuck](https://en.wikipedia.org/wiki/Brainfuck)
* [Esolang &ndash; Brainfuck](https://esolangs.org/wiki/Brainfuck)
