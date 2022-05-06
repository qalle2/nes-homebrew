; Clock (NES, ASM6)
; TODO: make the cursor a sprite; move stuff from NMI routine to main loop.

; --- Constants -----------------------------------------------------------------------------------

; RAM
digits          equ $00  ; digits of time (6 bytes, from tens of hour to ones of minute)
frame_counter   equ $06  ; count frames in 1 second (0-60)
program_mode    equ $07  ; 0 = set time, 1 = clock running
cursor_pos      equ $08  ; cursor position in "set time" mode (0-5)
pad_status      equ $09  ; joypad status
prev_pad_status equ $0a  ; previous joypad status
run_main_loop   equ $0b  ; main loop allowed to run? (MSB: 0=no, 1=yes)
temp            equ $0c  ; temporary
segment_buffer  equ $80  ; segments to draw on next NMI (6*2*4 = 48 = $30 bytes)

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
color_dim       equ $0f  ; unlit         (black; $0c = dark teal)
color_medium    equ $18  ; medium bright (dark yellow)
color_bright    equ $28  ; bright        (yellow)

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
                db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
                pad $0010, $00           ; unused

; --- Initialization ------------------------------------------------------------------------------

                base $c000              ; start of PRG ROM
                pad $f800, $ff          ; last 2 KiB of CPU address space

reset           ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
                sei                     ; ignore IRQs
                cld                     ; disable decimal mode
                ldx #%01000000
                stx joypad2             ; disable APU frame IRQ
                ldx #$ff
                txs                     ; initialize stack pointer
                inx
                stx ppu_ctrl            ; disable NMI
                stx ppu_mask            ; disable rendering
                stx dmc_freq            ; disable DMC IRQs
                stx sound_ctrl          ; disable sound channels

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #$00                ; clear zero page
                tax
-               sta $00,x
                inx
                bne -

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$3f                ; set up palette (while we're still in VBlank)
                lda #$00
                jsr set_ppu_addr
                tax
-               lda palette,x
                sta ppu_data
                inx
                cpx #4
                bne -

                ldy #$20                ; clear name/attribute table 0 (4*256 bytes)
                lda #$00
                jsr set_ppu_addr
                ldy #4
--              tax
-               sta ppu_data
                inx
                bne -
                dey
                bne --

                ldx #0                  ; colons (tiles $01 $02, $01 $02, $03 $04, $03 $04)
-               ldy #$21
                lda colon_addr_lo,x
                jsr set_ppu_addr
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

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #%10000000          ; enable NMI, show background
                sta ppu_ctrl
                lda #%00001010
                sta ppu_mask

                jmp main_loop

wait_vbl_start  bit ppu_status          ; wait until next VBlank starts
-               lda ppu_status
                bpl -
                rts

palette         db color_bg, color_dim, color_medium, color_bright

colon_addr_lo   db 5*32+11              ; low bytes of colon addresses
                db 5*32+18
                db 6*32+11
                db 6*32+18

; --- Main loop - common --------------------------------------------------------------------------

main_loop       bit run_main_loop       ; wait until NMI routine has set flag
                bpl main_loop
                ;
                lsr run_main_loop       ; clear flag

                ; set up segment buffer (2*1 tiles per round; each digit is 2*4 tiles)
                ldy #(6*4-1)            ; counts to 0
                ;
-               tya                     ; which digit (0-5) -> X
                lsr a
                lsr a
                tax
                ;
                lda digits,x            ; start of digit's segment data -> temp
                asl a
                asl a
                asl a
                sta temp
                ;
                tya                     ; start of tile pair's segment data -> A, stack
                and #%00000011
                asl a
                adc temp
                pha
                ;
                tax                     ; 1st tile of pair -> stack -> buffer
                lda segment_tiles+0,x
                pha
                tya
                asl a
                tax
                pla
                sta segment_buffer+0,x
                ;
                pla                     ; start of tile pair's segment data
                ;
                tax                     ; 2nd tile of pair -> stack -> buffer
                lda segment_tiles+1,x
                pha
                tya
                asl a
                tax
                pla
                sta segment_buffer+1,x
                ;
                dey                     ; next tile pair
                bpl -

                lda program_mode        ; run mode-specific code
                beq main_adj_mode
                jmp main_run_mode

; --- Main loop - adjustment mode -----------------------------------------------------------------

main_adj_mode   lda pad_status          ; store previous joypad status
                sta prev_pad_status
                ;
                lda #1                  ; read joypad
                sta joypad1             ; (bits: A, B, select, start, up, down, left, right)
                sta pad_status
                lsr a
                sta joypad1
-               lda joypad1
                lsr a
                rol pad_status
                bcc -

                lda prev_pad_status     ; ignore buttons if something was pressed on last frame
                beq +
                jmp buttons_done

+               lda pad_status          ; react to buttons
                lsr a
                bcs cursor_right
                lsr a
                bcs cursor_left
                lsr a
                bcs decrement_digit
                lsr a
                bcs increment_digit
                lsr a
                bcs start_clock
                jmp buttons_done

cursor_right    ldx cursor_pos
                inx
                cpx #6
                bne +
                ldx #0
+               stx cursor_pos
                jmp buttons_done

cursor_left     ldx cursor_pos
                dex
                bpl +
                ldx #(6-1)
+               stx cursor_pos
                jmp buttons_done

decrement_digit ldx cursor_pos
                lda maxdigits_plus1,x
                sta temp
                ldy digits,x
                dey
                bpl +
                ldy temp
                dey
+               sty digits,x
                jmp buttons_done

increment_digit ldx cursor_pos
                lda maxdigits_plus1,x
                sta temp
                ldy digits,x
                iny
                cpy temp
                bne +
                ldy #0
+               sty digits,x
                jmp buttons_done

maxdigits_plus1 db 2+1, 9+1, 5+1, 9+1, 5+1, 9+1  ; maximum values of digits, plus 1

start_clock     lda digits+0            ; start clock if hour <= 23
                cmp #2
                bcc +
                lda digits+1
                cmp #4
                bcs buttons_done
+               inc program_mode        ; switch to "clock running" mode

buttons_done    jmp main_loop           ; return to common main loop

; --- Main loop - run mode ------------------------------------------------------------------------

main_run_mode   jmp main_loop           ; return to common main loop

; --- NMI routine - common ------------------------------------------------------------------------

                align $100, $ff

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; reset ppu_scroll/ppu_addr latch

                ; print digit segments from segment buffer
                ; (2*1 tiles per round; each digit is 2*4 tiles)
                ldy #(6*4-1)            ; counts to 0 in steps of -1
                ldx #((6*4-1)*2)        ; counts to 0 in steps of -2
                ;
-               lda #$21
                sta ppu_addr
                lda segment_addr_lo,y
                sta ppu_addr
                dey
                ;
                lda segment_buffer+0,x  ; print tile pair
                sta ppu_data
                lda segment_buffer+1,x
                sta ppu_data
                dex
                dex
                ;
                bpl -

                ldy #$00                ; hide all possible cursors
                ldx #(6-1)              ; (Y = byte to write, X = loop counter)
-               lda #$22
                sta ppu_addr
                lda cursor_addr_lo,x
                sta ppu_addr
                sty ppu_data
                sty ppu_data
                dex
                bpl -

                lda program_mode        ; run mode-specific code
                bne +
                jmp nmi_adj_mode
+               jmp nmi_run_mode

nmi_end         sec                     ; set flag to let main loop run once
                ror run_main_loop

                lda #256-4              ; horizontal scroll
                sta ppu_scroll
                lda #256-8              ; vertical scroll
                sta ppu_scroll
                lda #%10000000          ; same value as in initialization
                sta ppu_ctrl

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

                rti

segment_addr_lo ; low bytes of segment addresses
                db 4*32+ 6, 5*32+ 6, 6*32+ 6, 7*32+ 6  ; tens of hour
                db 4*32+ 9, 5*32+ 9, 6*32+ 9, 7*32+ 9  ; ones of hour
                db 4*32+13, 5*32+13, 6*32+13, 7*32+13  ; tens of minute
                db 4*32+16, 5*32+16, 6*32+16, 7*32+16  ; ones of minute
                db 4*32+20, 5*32+20, 6*32+20, 7*32+20  ; tens of second
                db 4*32+23, 5*32+23, 6*32+23, 7*32+23  ; ones of second

segment_tiles   hex 13 17  1a 1d  22 25  2b 2f  ; "0"
                hex 10 15  18 1d  20 25  28 2d  ; "1"
                hex 11 17  19 1f  23 26  2b 2e  ; "2"
                hex 11 17  19 1f  21 27  29 2f  ; "3"
                hex 12 15  1b 1f  21 27  28 2d  ; "4"
                hex 13 16  1b 1e  21 27  29 2f  ; "5"
                hex 13 16  1b 1e  23 27  2b 2f  ; "6"
                hex 13 17  1a 1d  20 25  28 2d  ; "7"
                hex 13 17  1b 1f  23 27  2b 2f  ; "8"
                hex 13 17  1b 1f  21 27  29 2f  ; "9"

; --- NMI routine - adjustment mode ---------------------------------------------------------------

                align $100, $ff

nmi_adj_mode    ldy #>($2000+16*32)     ; show cursor
                ldx cursor_pos
                lda cursor_addr_lo,x
                jsr set_ppu_addr
                lda #$05                ; left half
                sta ppu_data
                lda #$06                ; right half
                sta ppu_data

                jmp nmi_end             ; return to common NMI routine

; --- NMI routine - run mode ----------------------------------------------------------------------

                align $100, $ff

nmi_run_mode    ; length of second in frames -> temp
                ; NTSC timing: 60 fps plus an extra frame every 10 seconds (60.1 fps);
                ; should be 60.0988 frames/s according to NESDev wiki
                lda #60
                sta temp
                lda digits+5
                bne +
                inc temp

+               ; increment digits

                inc frame_counter
                lda frame_counter
                cmp temp
                bne digit_incr_done

                lda #0
                sta frame_counter

                ldx digits+5            ; ones of second
                lda plus1_mod10,x
                sta digits+5
                bne digit_incr_done

                ldx digits+4            ; tens of second
                lda plus1_mod6,x
                sta digits+4
                bne digit_incr_done

                ldx digits+3            ; ones of minute
                lda plus1_mod10,x
                sta digits+3
                bne digit_incr_done

                ldx digits+2            ; tens of minute
                lda plus1_mod6,x
                sta digits+2
                bne digit_incr_done

                ldx digits+1            ; ones of hour
                lda digits+0
                cmp #2
                beq +
                lda plus1_mod10,x
                jmp ++
+               lda plus1_mod4,x
++              sta digits+1
                bne digit_incr_done

                ldx digits+0            ; tens of hour
                lda plus1_mod3,x
                sta digits+0

digit_incr_done jmp nmi_end             ; return to common NMI routine

plus1_mod3      db 1, 2, 0
plus1_mod4      db 1, 2, 3, 0
plus1_mod6      db 1, 2, 3, 4, 5, 0
plus1_mod10     db 1, 2, 3, 4, 5, 6, 7, 8, 9, 0

; --- Misc subs & arrays --------------------------------------------------------------------------

set_ppu_addr    sty ppu_addr            ; set PPU address from Y and A
                sta ppu_addr
                rts

cursor_addr_lo  db 32+ 6,  32+9         ; low bytes of cursor addresses
                db 32+13, 32+16
                db 32+20, 32+23

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
