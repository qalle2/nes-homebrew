; 24 Balls (NES, ASM6f)

    ; value to fill unused areas with
    fillvalue $ff

    include "_common.asm"

; --- Constants -----------------------------------------------------------------------------------

; RAM
sprite_page        equ $0000  ; see "zero page layout" below
timer              equ $0200
nmi_done           equ $0201  ; flag (only MSB is important)
loop_counter       equ $0202
sprite_palette_ram equ $0203  ; 16 bytes; backwards

; Zero page layout:
;   $00-$bf: visible sprites:
;       192 bytes = 24 balls * 2 sprites/ball * 4 bytes/sprite
;   $c0-$ff: hidden sprites:
;       Y positions ($c0, $c4, $c8, ...): always $ff
;       other bytes: directions of balls (negative = up/left, positive = down/right):
;           horizontal: $c1, $c2, $c3; $c5, $c6, $c7; ...; $dd, $de, $df
;           vertical:   $e1, $e2, $e3; $e5, $e6, $e7; ...; $fd, $fe, $ff

; non-address constants
ball_count equ 24

; --- iNES header ---------------------------------------------------------------------------------

    inesprg 1  ; PRG ROM: 16 KiB
    ineschr 1  ; CHR ROM:  8 KiB
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------

    org $c000                       ; last 16 KiB of PRG ROM
    pad $f800                       ; last  2 KiB of PRG ROM
    include "24balls-init.asm"
    include "24balls-mainloop.asm"
    include "24balls-nmi.asm"
    include "24balls-common.asm"

; --- Interrupt vectors ---------------------------------------------------------------------------

    pad $fffa
    dw nmi, reset, $ffff

; --- CHR ROM -------------------------------------------------------------------------------------

    pad $10000
    incbin "24balls-chr.bin"
    pad $12000

