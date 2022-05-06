; Clock (NES, ASM6)
; TODO:
; - allow stopping the clock
; - make each digit 3*5 tiles?

; --- Constants -----------------------------------------------------------------------------------

; RAM
digits          equ $00    ; digits of time (6 bytes, from tens of hour to ones of minute)
frame_counter   equ $06    ; count frames in 1 second (0-60)
program_mode    equ $07    ; 0 = set time, 1 = clock running
cursor_pos      equ $08    ; cursor position in "set time" mode (under which digit; 0-5)
pad_status      equ $09    ; joypad status
prev_pad_status equ $0a    ; previous joypad status
run_main_loop   equ $0b    ; main loop allowed to run? (MSB: 0=no, 1=yes)
fps             equ $0c    ; frames per second (60/61)
temp            equ $0d    ; temporary
segment_buffer  equ $80    ; segments to draw on next NMI (6*2*4 = 48 = $30 bytes)
sprite_data     equ $0200  ; OAM page ($100 bytes)

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
oam_addr        equ $2003
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
oam_dma         equ $4014
sound_ctrl      equ $4015
joypad1         equ $4016
joypad2         equ $4017

; colors
color_bg        equ $0f  ; background (black)
color_dim       equ $18  ; dim        (dark yellow)
color_bright    equ $28  ; bright     (yellow)
color_unused    equ $30  ; unused     (white)

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

                ldy #$00                ; fill zero page with $00 and sprite page with $ff
                lda #$ff                ; note: 6502 has no absolute indexed STX/STY
                ldx #0
-               sty $00,x
                sta sprite_data,x
                inx
                bne -

                ldx #0                  ; copy initial sprite data
-               lda init_spr_data,x
                sta sprite_data,x
                inx
                cpx #(5*4)
                bne -

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$3f                ; set up palette (while still in VBlank; copy same
                lda #$00                ; 4 colors backwards to all subpalettes)
                jsr set_ppu_addr
                ldy #8
--              ldx #(4-1)
-               lda palette,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

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

                jsr wait_vbl_start      ; wait until next VBlank starts
                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask
                jmp main_loop

wait_vbl_start  bit ppu_status          ; wait until next VBlank starts
-               lda ppu_status
                bpl -
                rts

set_ppu_addr    sty ppu_addr            ; set PPU address from Y and A
                sta ppu_addr
                rts

init_spr_data   ; initial sprite data (Y, tile, attributes, X)
                db $66-1, $01, %00000000, $5c  ; #0: top    dot between hour   & minute
                db $74-1, $01, %00000000, $5c  ; #1: bottom dot between hour   & minute
                db $66-1, $01, %00000000, $94  ; #2: top    dot between minute & second
                db $74-1, $01, %00000000, $94  ; #3: bottom dot between minute & second
                db $88-1, $02, %00000000, $34  ; #4: cursor

palette         db color_unused, color_bright, color_dim, color_bg  ; backwards to all subpalettes

; --- Main loop - common --------------------------------------------------------------------------

main_loop       bit run_main_loop       ; wait until NMI routine has set flag
                bpl main_loop
                ;
                lsr run_main_loop       ; clear flag

                ; copy from segment_tiles to segment_buffer (2*1 tiles/round, 2*4 tiles/digit)
                ldy #(6*4-1)            ; Y = tile pair index
                ;
-               tya                     ; source index: A = ((digits[Y>>2] << 2) | (Y&3)) << 1
                lsr a
                lsr a
                tax
                lda digits,x
                asl a
                asl a
                sta temp
                tya
                and #%00000011
                ora temp
                asl a
                ;
                pha                     ; segment_buffer[Y*2] = segment_tiles[sourceIndex]
                tax
                clc
                jsr copy_seg_tile
                ;
                pla                     ; segment_buffer[Y*2+1] = segment_tiles[sourceIndex+1]
                tax
                inx
                sec
                jsr copy_seg_tile
                ;
                dey
                bpl -

                lda program_mode        ; run mode-specific code
                beq main_adj_mode
                jmp main_run_mode

copy_seg_tile   lda segment_tiles,x     ; segment_buffer[Y*2+C] = segment_tiles[X]
                pha
                tya
                rol a
                tax
                pla
                sta segment_buffer,x
                rts

segment_tiles   hex 06 09  0b 0d  15 17  1c 1f  ; "0"
                hex 00 07  00 0d  00 17  00 1d  ; "1"
                hex 04 09  0a 0f  16 18  1c 1e  ; "2"
                hex 04 09  0a 0f  14 19  1a 1f  ; "3"
                hex 05 07  0c 0f  14 19  00 1d  ; "4"
                hex 06 08  0c 0e  14 19  1a 1f  ; "5"
                hex 06 08  0c 0e  16 19  1c 1f  ; "6"
                hex 06 09  0b 0d  00 17  00 1d  ; "7"
                hex 06 09  0c 0f  16 19  1c 1f  ; "8"
                hex 06 09  0c 0f  14 19  1a 1f  ; "9"

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
                bne buttons_done

                ldx cursor_pos          ; react to buttons
                ldy digits,x
                lda pad_status
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
                bcc buttons_done        ; unconditional

cursor_left     dex
                bpl +
                ldx #(6-1)
                bpl +                   ; unconditional
cursor_right    inx
                cpx #6
                bne +
                ldx #0
+               stx cursor_pos
                jmp buttons_done

decrement_digit dey
                bpl ++
                lda max_digits,x
                tay
                bpl ++                  ; unconditional
increment_digit tya
                cmp max_digits,x
                bne +
                ldy #0
                beq ++                  ; unconditional
+               iny
++              sty digits,x
                bpl buttons_done        ; unconditional

start_clock     lda digits+0            ; start clock if hour <= 23
                cmp #2
                bcc +
                lda digits+1
                cmp #4
                bcs buttons_done
+               lda #$ff                ; hide cursor sprite
                sta sprite_data+4*4+0
                inc program_mode        ; switch to "clock running" mode

buttons_done    ldx cursor_pos          ; update cursor sprite X
                lda cursor_x,x
                sta sprite_data+4*4+3
                jmp main_loop           ; return to common main loop

max_digits      db 2, 9, 5, 9, 5, 9     ; maximum values of digits

cursor_x        hex 34 4c 6c 84 a4 bc   ; cursor sprite X positions

; --- Main loop - run mode ------------------------------------------------------------------------

main_run_mode   ; length of second in frames -> fps
                ; 60.1 on average (60 + an extra frame every 10 seconds)
                ; should be 60.0988 according to NESDev wiki
                lda #60
                sta fps
                lda digits+5
                bne +
                inc fps

+               ; increment digits

                inc frame_counter
                lda frame_counter
                cmp fps
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

digit_incr_done jmp main_loop           ; return to common main loop

plus1_mod3      db 1, 2, 0
plus1_mod4      db 1, 2, 3, 0
plus1_mod6      db 1, 2, 3, 4, 5, 0
plus1_mod10     db 1, 2, 3, 4, 5, 6, 7, 8, 9, 0

; --- NMI routine - common ------------------------------------------------------------------------

                align $100, $ff

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; reset ppu_scroll/ppu_addr latch
                lda #$00                ; do sprite DMA
                sta oam_addr
                lda #>sprite_data
                sta oam_dma

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

                sec                     ; set flag to let main loop run once
                ror run_main_loop

                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

                rti

segment_addr_lo ; low bytes of segment addresses
                ; notes:
                ; - digits are a half tile left of centerline (total width is odd)
                ; - digits are one    tile top  of centerline (to fit all on same VRAM page)
                db 4*32+ 6, 5*32+ 6, 6*32+ 6, 7*32+ 6  ; tens of hour
                db 4*32+ 9, 5*32+ 9, 6*32+ 9, 7*32+ 9  ; ones of hour
                db 4*32+13, 5*32+13, 6*32+13, 7*32+13  ; tens of minute
                db 4*32+16, 5*32+16, 6*32+16, 7*32+16  ; ones of minute
                db 4*32+20, 5*32+20, 6*32+20, 7*32+20  ; tens of second
                db 4*32+23, 5*32+23, 6*32+23, 7*32+23  ; ones of second

; --- Subs used in many places --------------------------------------------------------------------

set_ppu_regs    lda #$00                ; reset PPU scroll
                sta ppu_scroll
                sta ppu_scroll
                lda #%10000000          ; enable NMI
                sta ppu_ctrl
                lda #%00011110          ; show background and sprites
                sta ppu_mask
                rts

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, 0

; --- CHR ROM -------------------------------------------------------------------------------------

                ; tiles in pattern table 0:
                ; $00: blank
                ; $01: dot
                ; $02: cursor
                ; $04-$0f, $14-$1f: segments
                ; all other tiles are unused

                pad $10000, $ff
                incbin "clock-chr.bin"
                pad $12000, $ff
