    include "_common.asm"

    ; value to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; zero page
in_palette_editor  equ $00  ; flag; MSB: 0 = paint mode, 1 = palette edit mode
nmi_done           equ $01  ; flag; MSB: 0 = no, 1 = yes
do_paint           equ $02  ; flag; MSB: 0 = do nothing, 1 = write new_nt_byte to vram_address
joypad_status      equ $03
prev_joypad_status equ $04  ; previous joypad status
delay_left         equ $05  ; cursor move delay left
cursor_type        equ $06  ; 0 = small (arrow), 1 = big (square)
cursor_x           equ $07  ; cursor X position (in paint mode; 0-63)
cursor_y           equ $08  ; cursor Y position (in paint mode; 0-47)
color              equ $09  ; selected color (0-3)
palette_cursor     equ $0a  ; cursor position in palette edit mode (0-3)
user_palette       equ $0b  ; 4 bytes, each $00-$3f
paint_area_offset  equ $11  ; 2 bytes (low, high; 0-767)
temp               equ $13
pointer            equ $14  ; 2 bytes

; other RAM
sprite_data equ $0200  ; 256 bytes; first 9 paint mode sprites, then 13 palette editor sprites
nt_buffer   equ $0300  ; 768 bytes; copy of name table data of paint area

; colors
black  equ $0f
white  equ $30
red    equ $16
yellow equ $28
olive  equ $18
green  equ $1a
blue   equ $02
purple equ $04

; misc
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

; --- Interrupt vectors ----------------------------------------------------------------------------

    pad $fffa
    dw nmi, reset, $ffff

