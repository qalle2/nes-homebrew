; Clock (NES, ASM6)
; TODO: the code needs a lot of cleaning up.

; --- Constants -----------------------------------------------------------------------------------

; RAM
digits          equ $00  ; digits of time (6 bytes)
hour_tens       equ $00
hour_ones       equ $01
minute_tens     equ $02
minute_ones     equ $03
second_tens     equ $04
second_ones     equ $05
frame           equ $06
mode            equ $07  ; 0 = set time, 1 = clock running
cursor_pos      equ $08  ; cursor position in "set time" mode
joypad_stat     equ $09  ; joypad status
prevjoystat     equ $0a  ; previous joypad status
temp            equ $0b

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
sound_ctrl      equ $4015
joypad1         equ $4016
joypad2         equ $4017

; colors
color_bg        equ $0f  ; background    (black)
color_unlit     equ $0c  ; unlit segment (dark teal)
color_lit       equ $28  ; lit   segment (yellow)

digit_count     equ 6

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
                db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
                pad $0010, $00           ; unused

; --- Main program --------------------------------------------------------------------------------

                base $c000  ; last 16 KiB of CPU memory space

reset           ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
                sei             ; ignore IRQs
                cld             ; disable decimal mode
                ldx #%01000000
                stx joypad2     ; disable APU frame IRQ
                ldx #$ff
                txs             ; initialize stack pointer
                inx
                stx ppu_ctrl    ; disable NMI
                stx ppu_mask    ; disable rendering
                stx dmc_freq    ; disable DMC IRQs
                stx sound_ctrl  ; disable sound channels

                bit ppu_status  ; wait until next VBlank starts
-               lda ppu_status
                bpl -

                lda #$00        ; clear zero page
                tax
-               sta $00,x
                inx
                bne -

                lda #%00000001  ; enable pulse 1 channel
                sta sound_ctrl

                bit ppu_status  ; wait until next VBlank starts
-               lda ppu_status
                bpl -

                lda #$3f       ; set up palette (while we're still in VBlank;
                sta ppu_addr   ; copy the same 4 bytes to every subpalette)
                lda #$00
                sta ppu_addr
                ldy #8
--              ldx #0
-               lda palette,x
                sta ppu_data
                inx
                cpx #4
                bne -
                dey
                bne --

                ; clear name/attribute table 0 (4*256 bytes)
                lda #$20
                sta ppu_addr
                lda #$00
                sta ppu_addr
                ldy #4
--              tax
-               sta ppu_data
                inx
                bne -
                dey
                bne --

                ; colons (tiles $01 $02, $01 $02, $03 $04, $03 $04)
                ldx #0
-               lda #$21
                sta ppu_addr
                lda colonaddrlo,x
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

                ldx #0
                jsr print_cursor
                jsr print_digits

                bit ppu_status  ; wait until next VBlank starts
-               lda ppu_status
                bpl -

                lda #%10000000  ; enable NMI, show background
                sta ppu_ctrl
                lda #%00001010
                sta ppu_mask

-               jmp -

; --- NMI routine ---------------------------------------------------------------------------------

nmi             lda mode
                beq adjustment_mode
                jmp run_mode

adjustment_mode ; joypad 1 status -> A, X (bits: A, B, select, start, up, down, left, right)
                ldx #1
                stx joypad1
                dex
                stx joypad1
                ldy #8
-               lda joypad1
                ror
                txa
                rol
                tax
                dey
                bne -
                sta joypad_stat

                ; ignore buttons if something was pressed on last frame
                ldx prevjoystat
                beq +
                jmp button_read_done

                ; react to buttons
+               lsr
                bcs cursor_right
                lsr
                bcs cursor_left
                lsr
                bcs decrement_digit
                lsr
                bcs increment_digit
                lsr
                bcs start_clock
                jmp button_read_done

cursor_right    ldx cursor_pos
                jsr hide_cursor
                inx
                cpx #digit_count
                bne +
                ldx #0
+               stx cursor_pos
                jsr print_cursor
                jmp button_read_done

cursor_left     ldx cursor_pos
                jsr hide_cursor
                dex
                bpl +
                ldx #(digit_count-1)
+               stx cursor_pos
                jsr print_cursor
                jmp button_read_done

decrement_digit ldx cursor_pos
                lda max_digits,x  ; maximum values of digits, plus 1
                sta temp
                ldy digits,x
                dey
                bpl +
                ldy temp
                dey
+               sty digits,x
                jmp button_read_done

increment_digit ldx cursor_pos
                lda max_digits,x  ; maximum values of digits, plus 1
                sta temp
                ldy digits,x
                iny
                cpy temp
                bne +
                ldy #0
+               sty digits,x
                jmp button_read_done

start_clock     ; start clock if hour is 23 or smaller
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
+               ; hide cursor
                ldx cursor_pos
                jsr hide_cursor
                ; switch to "clock running" mode
                inc mode

button_read_done
                lda joypad_stat
                sta prevjoystat
                jsr print_digits
                rti

run_mode        jsr print_digits

                ; length of second in frames -> temp
                ; NTSC timing: 60 fps plus an extra frame every 10 seconds (60.1 fps);
                ; should be 60.0988 frames/s according to NESDev wiki
                lda #60
                sta temp
                lda second_ones
                bne +
                inc temp

+               ; increment digits

                inc frame
                lda frame
                cmp temp
                bne digit_increment_done

                lda #0
                sta frame

                ldx second_ones
                lda plus1mod10,x
                sta second_ones
                bne digit_increment_done

                ldx second_tens
                lda plus1mod6,x
                sta second_tens
                bne digit_increment_done

                ldx minute_ones
                lda plus1mod10,x
                sta minute_ones
                bne digit_increment_done

                ldx minute_tens
                lda plus1mod6,x
                sta minute_tens
                bne digit_increment_done

                ldx hour_ones
                lda hour_tens
                cmp #2
                beq +
                lda plus1mod10,x
                jmp ++
+               lda plus1mod4,x
++              sta hour_ones
                bne digit_increment_done

                ldx hour_tens
                lda plus1mod3,x
                sta hour_tens

digit_increment_done
                rti

; --- Subs ----------------------------------------------------------------------------------------

print_cursor    ; print cursor below digit specified by X (0-5)
                lda #>($2000+16*32)
                sta ppu_addr
                lda cursoradrlo,x
                sta ppu_addr
                lda #$05      ; left half of cursor
                sta ppu_data
                lda #$06      ; right half of cursor
                sta ppu_data
                rts

hide_cursor     ; hide cursor from below digit specified by X (0-5)
                lda #>($2000+16*32)
                sta ppu_addr
                lda cursoradrlo,x
                sta ppu_addr
                lda #$00
                sta ppu_data
                sta ppu_data
                rts

print_digits    ; print the digit segments (2*1 tiles per round; each digit is 2*4 tiles)
                ldy #(digit_count*4-1)  ; counts to 0
-               lda #>($2000+8*32)
                sta ppu_addr
                lda segment_addresses_low,y
                sta ppu_addr
                ; which digit (0-5) -> X
                tya
                lsr
                lsr
                tax
                ; digit offset in segment data -> temp
                lda digits,x
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
                lda segment_tiles+0,x
                sta ppu_data
                lda segment_tiles+1,x
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

; --- Arrays --------------------------------------------------------------------------------------

                ; initial palette (for all subpalettes)
                ; note: to hide unlit segments, replace "color_unlit" with "color_bg"
palette         db color_bg, color_unlit, color_lit, color_bg

colonaddrlo     db 5*32+11  ; low bytes of colon addresses
                db 5*32+18
                db 6*32+11
                db 6*32+18

cursoradrlo     db 32+6     ; low bytes of cursor addresses
                db 32+9
                db 32+13
                db 32+16
                db 32+20
                db 32+23

max_digits      db 2+1, 9+1, 5+1, 9+1, 5+1, 9+1  ; maximum values of digits, plus 1
plus1mod3       db 1, 2, 0
plus1mod4       db 1, 2, 3, 0
plus1mod6       db 1, 2, 3, 4, 5, 0
plus1mod10      db 1, 2, 3, 4, 5, 6, 7, 8, 9, 0

segment_addresses_low
                ; tens of hour
                db 4*32+6
                db 5*32+6
                db 6*32+6
                db 7*32+6
                ; ones of hour
                db 4*32+9
                db 5*32+9
                db 6*32+9
                db 7*32+9
                ; tens of minute
                db 4*32+13
                db 5*32+13
                db 6*32+13
                db 7*32+13
                ; ones of minute
                db 4*32+16
                db 5*32+16
                db 6*32+16
                db 7*32+16
                ; tens of second
                db 4*32+20
                db 5*32+20
                db 6*32+20
                db 7*32+20
                ; ones of second
                db 4*32+23
                db 5*32+23
                db 6*32+23
                db 7*32+23

segment_tiles
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

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, 0

; --- CHR ROM -------------------------------------------------------------------------------------

; Tiles:
;
; misc:
;   00: blank
;   01: colon - top    left
;   02: colon - top    right
;   03: colon - bottom left
;   04: colon - bottom right
;   05: up arrow - left
;   06: up arrow - right
;   07: "N"
;   08: "T"
;   09: "S"
;   0a: "C"
;   0b: "P"
;   0c: "A"
;   0d: "L"
; 1st row of digit - left:
;   10: down off, right off
;   11: down off, right on
;   12: down on,  right off
;   13: down on,  right on
; 1st row of digit - right:
;   14: left off, down off
;   15: left off, down on
;   16: left on,  down off
;   17: left on,  down on
; 2nd row of digit - left:
;   18: up off, right off
;   19: up off, right on
;   1a: up on,  right off
;   1b: up on,  right on
; 2nd row of digit - right:
;   1c: left off, up off
;   1d: left off, up on
;   1e: left on,  up off
;   1f: left on,  up on
; 3rd row of digit - left:
;   20: down off, right off
;   21: down off, right on
;   22: down on,  right off
;   23: down on,  right on
; 3rd row of digit - right:
;   24: left off, down off
;   25: left off, down on
;   26: left on,  down off
;   27: left on,  down on
; 4th row of digit - left:
;   28: up off, right off
;   29: up off, right on
;   2a: up on,  right off
;   2b: up on,  right on
; 4th row of digit - right:
;   2c: left off, up off
;   2d: left off, up on
;   2e: left on,  up off
;   2f: left on,  up on

                pad $10000, $ff
                incbin "clock-chr.bin"
                pad $12000, $ff
