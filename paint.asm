    include "_common.asm"

; --------------------------------------------------------------------------------------------------
; Constants

; RAM

mode               equ $00  ; MSB: 0 = paint mode, 1 = palette edit mode
joypad_status      equ $01
prev_joypad_status equ $02  ; previous joypad status
delay_left         equ $03  ; cursor move delay left
cursor_type        equ $04  ; 0 = small (arrow), 1 = big (square)
cursor_x           equ $05  ; cursor X position (in paint mode; 0-63)
cursor_y           equ $06  ; cursor Y position (in paint mode; 0-47)
color              equ $07  ; selected color (0-3)
user_palette       equ $08  ; 4 bytes, each $00-$3f
palette_cursor     equ $0c  ; cursor position in palette edit mode (0-3)
vram_address       equ $0d  ; 2 bytes
pointer            equ $0f  ; 2 bytes
temp               equ $10
nmi_done           equ $11  ; MSB: 0 = no, 1 = yes

sprite_data equ $0200  ; 256 bytes

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

cursor_move_delay           equ 10
paint_mode_sprite_count     equ 9
palette_editor_sprite_count equ 13

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
