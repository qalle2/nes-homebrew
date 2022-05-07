; Clock (NES, NTSC, ASM6)
; TODO:
; - store & write segments vertically instead of horizontally to save VBlank time?
; - make each digit 3*5 tiles?

; --- Constants -----------------------------------------------------------------------------------

; note: "segment tile pair buffer" = which segment pairs to draw on next VBlank

; RAM
seg_buf_left    equ $00    ; segment tile pair buffer - left  tiles (6*4 = 24 = $18 bytes)
seg_buf_right   equ $18    ; segment tile pair buffer - right tiles (6*4 = 24 = $18 bytes)
digits          equ $30    ; digits of time (6 bytes, from tens of hour to ones of minute)
clock_running   equ $36    ; is clock running? (MSB: 0=no, 1=yes)
run_main_loop   equ $37    ; is main loop allowed to run? (MSB: 0=no, 1=yes)
pad_status      equ $38    ; joypad status
prev_pad_status equ $39    ; previous joypad status
cursor_pos      equ $3a    ; cursor position (0-5)
frame_counter   equ $3b    ; frames left in current second (0-61)
temp            equ $3c    ; temporary
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

tile_dot        equ $01  ; dot (in colons)
tile_cursor     equ $02  ; cursor (up arrow)

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
                db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
                pad $0010, $00           ; unused

; --- Initialization ------------------------------------------------------------------------------

                base $c000              ; start of PRG ROM
                pad $fc00, $ff          ; last 1 KiB of CPU address space

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

init_spr_data   ; initial sprite data (Y, tile, attributes, X)
                db $66-1, tile_dot,    %00000000, $5c  ; #0: top    dot between hour   & minute
                db $73-1, tile_dot,    %00000000, $5c  ; #1: bottom dot between hour   & minute
                db $66-1, tile_dot,    %00000000, $94  ; #2: top    dot between minute & second
                db $73-1, tile_dot,    %00000000, $94  ; #3: bottom dot between minute & second
                db $88-1, tile_cursor, %00000000, $34  ; #4: cursor

palette         db color_unused, color_bright, color_dim, color_bg  ; backwards to all subpalettes

; --- Main loop - common --------------------------------------------------------------------------

main_loop       bit run_main_loop       ; wait until NMI routine has set flag
                bpl main_loop
                ;
                lsr run_main_loop       ; clear flag

                lda pad_status          ; store previous joypad status
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

                ; copy from segment_tiles to segment buffers (2*1 tiles/round, 2*4 tiles/digit)
                ; note: 6502 has LDA/STA zp,x but no LDA/STA zp,y; using X as destination index
                ; and Y as temporary variable instead of vice versa saves 1 byte
                ;
                ldx #(6*4-1)            ; X = tile pair index
                ;
-               txa                     ; source index: Y = ((digits[Y>>2] << 2) | (Y&3)) << 1
                lsr a
                lsr a
                tay
                lda digits,y
                asl a
                asl a
                sta temp
                txa
                and #%00000011
                ora temp
                asl a
                tay
                ;
                lda segment_tiles+0,y
                sta seg_buf_left,x
                lda segment_tiles+1,y
                sta seg_buf_right,x
                ;
                dex
                bpl -

                bit clock_running       ; run mode-specific code
                bpl main_adj_mode
                jmp main_run_mode

segment_tiles   ; In each digit, segments (A-G) correspond to tile slots (grid, 0-7) like this:
                ;   +-----+-----+
                ;   |  AAA|AAA  |
                ; 0 |  AAA|AAA  | 1
                ;   |BB   |   CC|
                ;   +-----+-----+
                ;   |BB   |   CC|
                ; 2 |BB   |   CC| 3
                ;   |  DDD|DDD  |
                ;   +-----+-----+
                ;   |  DDD|DDD  |
                ; 4 |EE   |   FF| 5
                ;   |EE   |   FF|
                ;   +-----+-----+
                ;   |EE   |   FF|
                ; 6 |  GGG|GGG  | 7
                ;   |  GGG|GGG  |
                ;   +-----+-----+
                ;
                ; Tiles allowed in each tile slot (in addition to 00 or blank tile):
                ;     0: 04-06; 1: 07-09; 2: 0a-0c; 3: 0d-0f
                ;     4: 14-16; 5: 17-19; 6: 1a-1c; 7: 1d-1f
                ;
                ;    0  1  2  3  4  5  6  7  <- tile slot
                ;   -- -- -- -- -- -- -- --
                hex 06 09 0b 0d 15 17 1c 1f  ; "0"
                hex 00 07 00 0d 00 17 00 1d  ; "1"
                hex 04 09 0a 0f 16 18 1c 1e  ; "2"
                hex 04 09 0a 0f 14 19 1a 1f  ; "3"
                hex 05 07 0c 0f 14 19 00 1d  ; "4"
                hex 06 08 0c 0e 14 19 1a 1f  ; "5"
                hex 06 08 0c 0e 16 19 1c 1f  ; "6"
                hex 06 09 0b 0d 00 17 00 1d  ; "7"
                hex 06 09 0c 0f 16 19 1c 1f  ; "8"
                hex 06 09 0c 0f 14 19 1a 1f  ; "9"

; --- Main loop - adjust mode ---------------------------------------------------------------------

main_adj_mode   lda prev_pad_status     ; ignore buttons if something was pressed on last frame
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
                lda #60                 ; restart current second
                sta frame_counter
                sec                     ; set flag
                ror clock_running

buttons_done    ldx cursor_pos          ; update cursor sprite X
                lda cursor_x,x
                sta sprite_data+4*4+3
                jmp main_loop           ; return to common main loop

cursor_x        hex 34 4c 6c 84 a4 bc   ; cursor sprite X positions

; --- Main loop - run mode ------------------------------------------------------------------------

main_run_mode   dec frame_counter       ; count down; if zero, a second has elapsed
                bne digit_incr_done

                lda #60                 ; reinitialize frame counter
                sta frame_counter       ; 60.1 on average (60 + an extra frame every 10 seconds)
                lda digits+5            ; should be 60.0988 according to NESDev wiki
                bne +
                inc frame_counter

+               ldx #5                  ; increment digits (X = which digit)
-               cpx #1                  ; special logic: reset ones of hour if hour = 23
                bne +
                lda digits+0
                cmp #2
                bne +
                lda digits+1
                cmp #3
                beq ++
+               inc digits,x            ; the usual logic: increment digit; if too large, zero it
                lda max_digits,x        ; and continue to next digit, otherwise exit
                cmp digits,x
                bcs digit_incr_done
++              lda #0
                sta digits,x
                dex
                bpl -

digit_incr_done lda prev_pad_status     ; if nothing pressed on previous frame
                bne +
                lda pad_status          ; and start pressed on this frame
                and #%00010000
                beq +
                lda init_spr_data+4*4   ; then show cursor
                sta sprite_data+4*4+0
                lsr clock_running       ; and clear flag

+               jmp main_loop           ; return to common main loop

; --- Interrupt routines --------------------------------------------------------------------------

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

                ; print digit segments from buffer (2*1 tiles/round, 2*4 tiles/digit)
                ldy #$21                ; VRAM address high
                ldx #(6*4-1)
-               lda segment_addr_lo,x   ; set VRAM address
                jsr set_ppu_addr
                lda seg_buf_left,x      ; print tile pair
                sta ppu_data
                lda seg_buf_right,x
                sta ppu_data
                dex
                bpl -

                sec                     ; set flag to let main loop run once
                ror run_main_loop

                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti                     ; note: IRQ unused

segment_addr_lo ; low bytes of VRAM addresses of first bytes of segment tile pairs
                ; notes:
                ; - digits are a half tile left of centerline (total width is odd)
                ; - digits are one    tile top  of centerline (to fit all on same VRAM page)
                db 4*32+ 6, 5*32+ 6, 6*32+ 6, 7*32+ 6  ; tens of hour
                db 4*32+ 9, 5*32+ 9, 6*32+ 9, 7*32+ 9  ; ones of hour
                db 4*32+13, 5*32+13, 6*32+13, 7*32+13  ; tens of minute
                db 4*32+16, 5*32+16, 6*32+16, 7*32+16  ; ones of minute
                db 4*32+20, 5*32+20, 6*32+20, 7*32+20  ; tens of second
                db 4*32+23, 5*32+23, 6*32+23, 7*32+23  ; ones of second

; --- Subs & arrays used in many places -----------------------------------------------------------

set_ppu_addr    sty ppu_addr            ; set PPU address from Y and A
                sta ppu_addr
                rts

set_ppu_regs    lda #$00                ; reset PPU scroll
                sta ppu_scroll
                sta ppu_scroll
                lda #%10000000          ; enable NMI
                sta ppu_ctrl
                lda #%00011110          ; show background and sprites
                sta ppu_mask
                rts

max_digits      db 2, 9, 5, 9, 5, 9     ; maximum values of digits

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; note: IRQ unused

; --- CHR ROM -------------------------------------------------------------------------------------

                base $0000
                incbin "clock-chr.bin"
                pad $0200, $ff          ; 512 bytes should be enough for anybody
                pad $2000, $ff
