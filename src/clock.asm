; The clock has been centered by scrolling the screen both horizontally and vertically to make it
; fit on one name table page.

    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

digits             equ $00  ; digits of time (6 bytes)
hour_tens          equ $00
hour_ones          equ $01
minute_tens        equ $02
minute_ones        equ $03
second_tens        equ $04
second_ones        equ $05
frame              equ $06
mode               equ $07  ; 0 = set time, 1 = clock running
cursor_pos         equ $08  ; cursor position in "set time" mode
joypad_status      equ $09
prev_joypad_status equ $0a  ; previous joypad status
show_inactive      equ $0b  ; show inactive segments? (0 = no, 1 = yes)
timing             equ $0c  ; 0 = NTSC, 1 = PAL
temp               equ $0d

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_scroll equ $2005
ppu_addr   equ $2006
ppu_data   equ $2007
joypad1    equ $4016

; PPU memory space

vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

black  equ $0f
teal   equ $0c
yellow equ $28

digit_count equ 6

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:

    lda #%00000000
    sta ppu_ctrl
    sta ppu_mask

    bit ppu_status
-   lda ppu_status
    bpl -
-   lda ppu_status
    bpl -

    ; palette
    lda #>vram_palette
    sta ppu_addr
    lda #<vram_palette
    sta ppu_addr
    lda #black
    sta ppu_data
    sta ppu_data
    lda #yellow
    sta ppu_data

    ; copy CHR data to CHR RAM (3 * 256 bytes)
    ldx #$00
    stx ppu_addr
    stx ppu_addr
-   lda chr_data, x
    sta ppu_data
    inx
    bne -
-   lda chr_data + $100, x
    sta ppu_data
    inx
    bne -
-   lda chr_data + $200, x
    sta ppu_data
    inx
    bne -

    ; name table and attribute table (clear 4 * 256 bytes)
    lda #>vram_name_table0
    sta ppu_addr
    lda #$00
    sta ppu_addr
    tax
-   sta ppu_data
    sta ppu_data
    sta ppu_data
    sta ppu_data
    inx
    bne -

    ; colons (tiles $01 $02, $01 $02, $03 $04, $03 $04)
    ldx #0
-   lda #>(vram_name_table0 + 8 * 32)
    sta ppu_addr
    lda colon_addresses_low, x
    sta ppu_addr
    txa
    and #%00000010
    ora #%00000001
    tay
    sty ppu_data
    iny
    sty ppu_data
    inx
    cpx #4
    bne -

    ; clear zero page
    lda #$00
    tax
-   sta $00, x
    inx
    bne -

    ; enable square 1
    lda #%00000001
    sta $4015

    ldx #0
    jsr print_cursor
    jsr print_ntsc_pal_text
    jsr print_digits

    bit ppu_status
-   lda ppu_status
    bpl -

    ; enable NMI
    lda #%10000000
    sta ppu_ctrl

    ; show background
    lda #%00001010
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------
; Non-maskable interrupt routine

nmi:
    lda mode
    beq adjustment_mode
    jmp run_mode

adjustment_mode:
    ; joypad 1 status -> A, X (bits: A, B, select, start, up, down, left, right)
    ldx #1
    stx joypad1
    dex
    stx joypad1
    ldy #8
-   lda joypad1
    ror
    txa
    rol
    tax
    dey
    bne -
    sta joypad_status

    ; ignore buttons if something was pressed on last frame
    ldx prev_joypad_status
    beq +
    jmp button_read_done

    ; react to buttons
+   lsr
    bcs cursor_right
    lsr
    bcs cursor_left
    lsr
    bcs decrement_digit
    lsr
    bcs increment_digit
    lsr
    bcs start_clock
    lsr
    lsr
    bcc +
    jmp toggle_inactive_segment_color
+   lsr
    bcc +
    jmp toggle_ntsc_pal
+   jmp button_read_done

cursor_right:
    ldx cursor_pos
    jsr hide_cursor
    inx
    cpx #digit_count
    bne +
    ldx #0
+   stx cursor_pos
    jsr print_cursor
    jmp button_read_done

cursor_left:
    ldx cursor_pos
    jsr hide_cursor
    dex
    bpl +
    ldx #(digit_count - 1)
+   stx cursor_pos
    jsr print_cursor
    jmp button_read_done

decrement_digit:
    ldx cursor_pos
    lda digit_max_values_plus1, x
    sta temp
    ldy digits, x
    dey
    bpl +
    ldy temp
    dey
+   sty digits, x
    jmp button_read_done

increment_digit:
    ldx cursor_pos
    lda digit_max_values_plus1, x
    sta temp
    ldy digits, x
    iny
    cpy temp
    bne +
    ldy #0
+   sty digits, x
    jmp button_read_done

start_clock:
    ; start clock if hour is 23 or smaller
    lda hour_tens
    cmp #2
    bcc +
    lda hour_ones
    cmp #4
    bcc +
    ; error sound effect
    lda #%10011111
    sta $4000
    lda #%00001000
    sta $4001
    lda #%11111111
    sta $4002
    lda #%10111111
    sta $4003
    jmp button_read_done
+   ; hide NTSC/PAL text
    lda #>(vram_name_table0 + 10 * 32 + 6)
    sta ppu_addr
    lda #<(vram_name_table0 + 10 * 32 + 6)
    sta ppu_addr
    lda #$00
    ldx #4
-   sta ppu_data
    dex
    bne -
    ; hide cursor
    ldx cursor_pos
    jsr hide_cursor
    ; switch to "clock running" mode
    inc mode
    jmp button_read_done

toggle_inactive_segment_color:
    ; toggle color of inactive segments
    lda show_inactive
    eor #%00000001
    sta show_inactive
    tax
    lda #>(vram_palette + 1)
    sta ppu_addr
    lda #<(vram_palette + 1)
    sta ppu_addr
    lda inactive_segment_colors, x
    sta ppu_data
    jmp button_read_done

toggle_ntsc_pal:
    ; toggle between NTSC and PAL timing
    lda timing
    eor #%00000001
    sta timing
    jsr print_ntsc_pal_text

button_read_done:
    lda joypad_status
    sta prev_joypad_status
    jsr print_digits
    rti

run_mode:
    jsr print_digits

    ; length of second in frames -> temp

    db $ad  ; LDA absolute (forgot to use zero page addressing mode here)
    dw timing  ; 0 = NTSC, 1 = PAL
    bne pal_timing
    ; NTSC timing: 60 frames/s, except 61 frames every 10 seconds (= 60.1 frames/s)
    ; (should be 60.0988 frames/s according to NESDev wiki)
    lda #60
    sta temp
    lda second_ones
    bne +
    inc temp
    jmp +
pal_timing:
    ; PAL timing: 50 frames/s, except 51 frames every 120 seconds (= 50.0083 frames/s)
    ; (should be 50.007 frames/s according to NESDev wiki)
    lda #50
    sta temp
    lda minute_ones
    and #%00000001
    ora second_tens
    ora second_ones
    bne +
    inc temp
+

    ; increment digits

    inc frame
    lda frame
    cmp temp
    bne digit_increment_done

    lda #0
    sta frame

    ldx second_ones
    lda plus1_modulo10, x
    sta second_ones
    bne digit_increment_done

    ldx second_tens
    lda plus1_modulo6, x
    sta second_tens
    bne digit_increment_done

    ldx minute_ones
    lda plus1_modulo10, x
    sta minute_ones
    bne digit_increment_done

    ldx minute_tens
    lda plus1_modulo6, x
    sta minute_tens
    bne digit_increment_done

    ldx hour_ones
    lda hour_tens
    cmp #2
    beq +
    lda plus1_modulo10, x
    jmp ++
+   lda plus1_modulo4, x
++  sta hour_ones
    bne digit_increment_done

    ldx hour_tens
    lda plus1_modulo3, x
    sta hour_tens

digit_increment_done:
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

print_cursor:
    ; print cursor below digit specified by X (0-5)
    lda #>(vram_name_table0 + 16 * 32)
    sta ppu_addr
    lda cursor_addresses_low, x
    sta ppu_addr
    lda #$05      ; left half of cursor
    sta ppu_data
    lda #$06      ; right half of cursor
    sta ppu_data
    rts

hide_cursor:
    ; hide cursor from below digit specified by X (0-5)
    lda #>(vram_name_table0 + 16 * 32)
    sta ppu_addr
    lda cursor_addresses_low, x
    sta ppu_addr
    lda #$00
    sta ppu_data
    sta ppu_data
    rts

print_ntsc_pal_text:
    ; print "NTSC" or "PAL "
    lda timing
    asl
    asl
    tax
    lda #>(vram_name_table0 + 10 * 32 + 6)
    sta ppu_addr
    lda #<(vram_name_table0 + 10 * 32 + 6)
    sta ppu_addr
    ldy #4
-   lda ntsc_pal_text, x
    sta ppu_data
    inx
    dey
    bne -
    rts

print_digits:
    ; print the digit segments (2*1 tiles per round; each digit is 2*4 tiles)
    ldy #(digit_count * 4 - 1)  ; counts to 0
-   lda #>(vram_name_table0 + 8 * 32)
    sta ppu_addr
    lda segment_addresses_low, y
    sta ppu_addr
    ; which digit (0-5) -> X
    tya
    lsr
    lsr
    tax
    ; digit offset in segment data -> temp
    lda digits, x
    rept 3
        asl
    endr
    sta temp
    ; digit row offset in segment data -> X
    tya
    and #%00000011
    asl
    adc temp
    tax
    ; print digit row
    lda segment_tiles + 0, x
    sta ppu_data
    lda segment_tiles + 1, x
    sta ppu_data
    ; next digit row
    dey
    bpl -

    ; reset VRAM address
    lda #$00
    sta ppu_addr
    sta ppu_addr

    ; horizontal scroll
    lda #256-4
    sta ppu_scroll

    ; vertical scroll
    lda #256-8
    sta ppu_scroll
    rts

; --------------------------------------------------------------------------------------------------
; Tables

colon_addresses_low:
    db 5 * 32 + 11
    db 5 * 32 + 18
    db 6 * 32 + 11
    db 6 * 32 + 18
cursor_addresses_low:
    db 32 + 6
    db 32 + 9
    db 32 + 13
    db 32 + 16
    db 32 + 20
    db 32 + 23
ntsc_pal_text:
    hex 07 08 09 0a  ; "NTSC"
    hex 0b 0c 0d 00  ; "PAL "

digit_max_values_plus1:
    db 3, 10, 6, 10, 6, 10
plus1_modulo3:
    db 1, 2, 0
plus1_modulo4:
    db 1, 2, 3, 0
plus1_modulo6:
    db 1, 2, 3, 4, 5, 0
plus1_modulo10:
    db 1, 2, 3, 4, 5, 6, 7, 8, 9, 0

inactive_segment_colors:
    db black, teal

segment_addresses_low:
    ; tens of hour
    db 4 * 32 + 6
    db 5 * 32 + 6
    db 6 * 32 + 6
    db 7 * 32 + 6
    ; ones of hour
    db 4 * 32 + 9
    db 5 * 32 + 9
    db 6 * 32 + 9
    db 7 * 32 + 9
    ; tens of minute
    db 4 * 32 + 13
    db 5 * 32 + 13
    db 6 * 32 + 13
    db 7 * 32 + 13
    ; ones of minute
    db 4 * 32 + 16
    db 5 * 32 + 16
    db 6 * 32 + 16
    db 7 * 32 + 16
    ; tens of second
    db 4 * 32 + 20
    db 5 * 32 + 20
    db 6 * 32 + 20
    db 7 * 32 + 20
    ; ones of second
    db 4 * 32 + 23
    db 5 * 32 + 23
    db 6 * 32 + 23
    db 7 * 32 + 23

segment_tiles:
    hex 13 17  1a 1d  22 25  2b 2f  ; "0"
    hex 10 15  18 1d  20 25  28 2d  ; "1"
    hex 11 17  19 1f  23 26  2b 2e  ; "2"
    hex 11 17  19 1f  21 27  29 2f  ; "3"
    hex 12 15  1b 1f  21 27  28 2d  ; "4"
    hex 13 16  1b 1e  21 27  29 2f  ; "5"
    hex 13 16  1b 1e  23 27  2b 2f  ; "6"
    hex 13 17  1a 1d  20 25  28 2d  ; "7"
    hex 13 17  1b 1f  23 27  2b 2f  ; "8"
    hex 13 17  1b 1f  21 27  29 2f  ; "9"

chr_data:
    ; characters $00-$0d
    hex 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ; $00: blank
    hex 00 00 00 00 00 00 00 00  00 03 03 03 03 00 00 00  ; $01: part of colon
    hex 00 00 00 00 00 00 00 00  00 c0 c0 c0 c0 00 00 00  ; $02: part of colon
    hex 00 00 00 00 00 00 00 00  00 00 00 03 03 03 03 00  ; $03: part of colon
    hex 00 00 00 00 00 00 00 00  00 00 00 c0 c0 c0 c0 00  ; $04: part of colon
    hex 00 00 00 00 00 00 00 00  01 03 07 0d 01 01 01 01  ; $05: left  half of up arrow
    hex 00 00 00 00 00 00 00 00  80 c0 e0 b0 80 80 80 80  ; $06: right half of up arrow
    hex 00 00 00 00 00 00 00 00  c6 e6 f6 de ce c6 c6 00  ; $07: "N"
    hex 00 00 00 00 00 00 00 00  7e 18 18 18 18 18 18 00  ; $08: "T"
    hex 00 00 00 00 00 00 00 00  7c c6 c0 7c 06 c6 7c 00  ; $09: "S"
    hex 00 00 00 00 00 00 00 00  7c c6 c0 c0 c0 c6 7c 00  ; $0a: "C"
    hex 00 00 00 00 00 00 00 00  fc c6 c6 fc c0 c0 c0 00  ; $0b: "P"
    hex 00 00 00 00 00 00 00 00  7c c6 c6 fe c6 c6 c6 00  ; $0c: "A"
    hex 00 00 00 00 00 00 00 00  c0 c0 c0 c0 c0 c0 fe 00  ; $0d: "L"

    ; characters $10-$3f: segments
    pad chr_data + $10 * 16, $00
    ; top row of digit - left
    hex 0f 1f 1f 6f f0 f0 f0 f0  00 00 00 00 00 00 00 00  ; $10: down off, right off
    hex 00 00 00 60 f0 f0 f0 f0  0f 1f 1f 0f 00 00 00 00  ; $11: down off, right on
    hex 0f 1f 1f 0f 00 00 00 00  00 00 00 60 f0 f0 f0 f0  ; $12: down on,  right off
    hex 00 00 00 00 00 00 00 00  0f 1f 1f 6f f0 f0 f0 f0  ; $13: down on,  right on
    ; top row of digit - right
    hex f0 f8 f8 f6 0f 0f 0f 0f  00 00 00 00 00 00 00 00  ; $14: left off, down off
    hex f0 f8 f8 f0 00 00 00 00  00 00 00 06 0f 0f 0f 0f  ; $15: left off, down on
    hex 00 00 00 06 0f 0f 0f 0f  f0 f8 f8 f0 00 00 00 00  ; $16: left on,  down off
    hex 00 00 00 00 00 00 00 00  f0 f8 f8 f6 0f 0f 0f 0f  ; $17: left on,  down on
    ; second row of digit - left
    hex f0 f0 f0 f0 f0 f0 6f 1f  00 00 00 00 00 00 00 00  ; $18: up off, right off
    hex f0 f0 f0 f0 f0 f0 60 00  00 00 00 00 00 00 0f 1f  ; $19: up off, right on
    hex 00 00 00 00 00 00 0f 1f  f0 f0 f0 f0 f0 f0 60 00  ; $1a: up on,  right off
    hex 00 00 00 00 00 00 00 00  f0 f0 f0 f0 f0 f0 6f 1f  ; $1b: up on,  right on
    ; second row of digit - right
    hex 0f 0f 0f 0f 0f 0f f6 f8  00 00 00 00 00 00 00 00  ; $1c: left off, up off
    hex 00 00 00 00 00 00 f0 f8  0f 0f 0f 0f 0f 0f 06 00  ; $1d: left off, up on
    hex 0f 0f 0f 0f 0f 0f 06 00  00 00 00 00 00 00 f0 f8  ; $1e: left on,  up off
    hex 00 00 00 00 00 00 00 00  0f 0f 0f 0f 0f 0f f6 f8  ; $1f: left on,  up on
    ; third row of digit - left
    hex 1f 6f f0 f0 f0 f0 f0 f0  00 00 00 00 00 00 00 00  ; $20: down off, right off
    hex 00 60 f0 f0 f0 f0 f0 f0  1f 0f 00 00 00 00 00 00  ; $21: down off, right on
    hex 1f 0f 00 00 00 00 00 00  00 60 f0 f0 f0 f0 f0 f0  ; $22: down on,  right off
    hex 00 00 00 00 00 00 00 00  1f 6f f0 f0 f0 f0 f0 f0  ; $23: down on,  right on
    ; third row of digit - right
    hex f8 f6 0f 0f 0f 0f 0f 0f  00 00 00 00 00 00 00 00  ; $24: left off, down off
    hex f8 f0 00 00 00 00 00 00  00 06 0f 0f 0f 0f 0f 0f  ; $25: left off, down on
    hex 00 06 0f 0f 0f 0f 0f 0f  f8 f0 00 00 00 00 00 00  ; $26: left on,  down off
    hex 00 00 00 00 00 00 00 00  f8 f6 0f 0f 0f 0f 0f 0f  ; $27: left on,  down on
    ; bottom row of digit - left
    hex f0 f0 f0 f0 6f 1f 1f 0f  00 00 00 00 00 00 00 00  ; $28: up off, right off
    hex f0 f0 f0 f0 60 00 00 00  00 00 00 00 0f 1f 1f 0f  ; $29: up off, right on
    hex 00 00 00 00 0f 1f 1f 0f  f0 f0 f0 f0 60 00 00 00  ; $2a: up on,  right off
    hex 00 00 00 00 00 00 00 00  f0 f0 f0 f0 6f 1f 1f 0f  ; $2b: up on,  right on
    ; bottom row of digit - right
    hex 0f 0f 0f 0f f6 f8 f8 f0  00 00 00 00 00 00 00 00  ; $2c: left off, up off
    hex 00 00 00 00 f0 f8 f8 f0  0f 0f 0f 0f 06 00 00 00  ; $2d: left off, up on
    hex 0f 0f 0f 0f 06 00 00 00  00 00 00 00 f0 f8 f8 f0  ; $2e: left on,  up off
    hex 00 00 00 00 00 00 00 00  0f 0f 0f 0f f6 f8 f8 f0  ; $2f: left on,  up on

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    org $fffa
    dw nmi, reset, 0
