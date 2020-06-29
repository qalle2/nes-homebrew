    ; TODO: use a 768-byte RAM buffer to avoid reading VRAM

    include "_common.asm"

    ; value to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; RAM

in_palette_editor  equ $00  ; flag; MSB: 0 = paint mode, 1 = palette edit mode
nmi_done           equ $01  ; flag; MSB: 0 = no, 1 = yes
joypad_status      equ $02
prev_joypad_status equ $03  ; previous joypad status
delay_left         equ $04  ; cursor move delay left
cursor_type        equ $05  ; 0 = small (arrow), 1 = big (square)
cursor_x           equ $06  ; cursor X position (in paint mode; 0-63)
cursor_y           equ $07  ; cursor Y position (in paint mode; 0-47)
color              equ $08  ; selected color (0-3)
palette_cursor     equ $09  ; cursor position in palette edit mode (0-3)
temp               equ $0a
user_palette       equ $10  ; 4 bytes, each $00-$3f
vram_address       equ $14  ; 2 bytes (high, low)
pointer            equ $16  ; 2 bytes
do_paint           equ $18  ; flag

sprite_data        equ $0200  ; 256 bytes; first 9 paint mode sprites, then 13 palette editor sprites
vram_buffer        equ $0300  ; 256 bytes (for main loop -> NMI communication; TODO: implement)

; non-address constants

button_a      = 1 << 7
button_b      = 1 << 6
button_select = 1 << 5
button_start  = 1 << 4
button_up     = 1 << 3
button_down   = 1 << 2
button_left   = 1 << 1
button_right  = 1 << 0

black  equ $0f
white  equ $30
red    equ $16
yellow equ $28
olive  equ $18
green  equ $1a
blue   equ $02
purple equ $04

cursor_move_delay equ 10

; --- iNES header ----------------------------------------------------------------------------------

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --- Main parts -----------------------------------------------------------------------------------

    org $c000
    include "paint-init.asm"
    include "paint-mainloop.asm"
    include "paint-nmi.asm"

; --- Subs used by many parts ----------------------------------------------------------------------

set_vram_address:
    ; A = high byte, X = low byte
    bit ppu_status  ; reset latch
    sta ppu_addr
    stx ppu_addr
    rts

; --- Interrupt vectors ----------------------------------------------------------------------------

    pad $fffa
    dw nmi, reset, 0
