; 1024 Byte Gradient Demo by Qalle (NES, ASM6). Seizure warning.

; --- Constants -----------------------------------------------------------------------------------

; RAM
; note: on the OAM page, attribute bytes of unused sprites ($x2/$x6/$xa/$xe) are used for other
; variables too
sprite_data     equ $00    ; OAM page ($100 bytes)
color_counter   equ $c2    ; color counter
text_counter    equ $c6    ; text counter
direction       equ $ca    ; direction of color animation: 0=inwards, 1=outwards
ppu_ctrl_copy   equ $ce    ; copy of ppu_ctrl
run_main_loop   equ $d2    ; is main loop allowed to run? (MSB: 0=no, 1=yes)
pal_src_index   equ $d6    ; start index in ROM palette (0-112 in steps of 16)
temp            equ $da
sine_table      equ $0200  ; $100 bytes

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
oam_addr        equ $2003
oam_dma         equ $4014
snd_chn         equ $4015
joypad2         equ $4017

; colors
colbg           equ $0f  ; background (black)
cl1             equ $12  ; animated color 1
cl2             equ $14  ; animated color 2
cl3             equ $16  ; animated color 3
cl4             equ $17  ; animated color 4
cl5             equ $18  ; animated color 5
cl6             equ $19  ; animated color 6
cl7             equ $1a  ; animated color 7
cl8             equ $1c  ; animated color 8
col_sprite      equ $0f  ; sprites (black)

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
                db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
                pad $0010, $00           ; unused

; --- Initialization ------------------------------------------------------------------------------

                base $c000              ; start of PRG ROM
                pad $fc00, $ff          ; last 1 KiB of CPU memory space

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
                stx snd_chn             ; disable sound channels

                jsr wait_vbl_start      ; wait for start of VBlank

                ldy #$ff                ; sprite page: set Y positions to $ff (to hide sprites)
                lda #$00                ; and attributes to $00 (also clears other variables)
                tax
-               sty sprite_data+0,x
                sta sprite_data+2,x
                inx
                inx
                inx
                inx
                bne -

                ldy #(spr_tiles_end-spr_tiles-1)
-               tya                     ; copy sprite tiles (Y/X = source/destination index;
                asl a                   ; 6502 has LDA absolute,y and STA zp,x but no STA zp,y)
                asl a
                tax
                lda spr_tiles,y
                sta sprite_data+1,x
                dey
                bpl -

                ; generate first 64 bytes (90 degrees) of sine table in RAM by extracting 16 bytes
                ; (64*2 bits) of delta-coded data
                lda #124                ; initial sine
                sta sine_table+$ff
                ldx #0                  ; X = source index / inner loop counter, Y = target index
                ldy #$ff
                ;
--              lda sine_deltas,x       ; byte with 4 deltas -> temp
                sta temp
                ;
                txa                     ; store source index
                pha
                ;
                ldx #4                  ; do 4 times: get bit pair with delta,
-               lda #0                  ; add to current sine to get next sine
                asl temp
                rol a
                asl temp
                rol a
                adc sine_table,y        ; carry is always clear
                iny
                sta sine_table,y
                dex
                bne -
                ;
                pla                     ; restore source index
                tax
                ;
                inx
                cpx #16
                bne --

                ldx #(64-1)             ; generate rest of 256-byte sine table using first 64
                ldy #0                  ; bytes; X = 63...0, Y = 0...63
                sec
                ;
-               lda sine_table,x
                sta sine_table+64,y     ; 2nd quarter (positive falling)
                ;
                lda #(2*124)            ; negate value (124 = zero level)
                sbc sine_table,x
                sta sine_table+128,x    ; 3rd quarter (negative falling)
                sta sine_table+192,y    ; 4th quarter (negative rising)
                ;
                iny
                dex
                bpl -

                jsr wait_vbl_start      ; wait for start of VBlank

                ldy #$3f                ; palette - sprite color
                lda #$11
                jsr set_ppu_addr
                lda #col_sprite
                sta ppu_data

                ldy #$00                ; prepare to write pattern table
                tya
                jsr set_ppu_addr

                ldx #0                  ; copy 2-bit tiles (X = source index)
-               lda pt_data_2bit,x
                jsr write2_pt_bytes     ; use nybbles as indexes to 2 bytes to write
                cpx #(pt_data_2bit_end-pt_data_2bit)
                bne -

                ldx #0                  ; copy 1-bit tiles (X = source index)
                ;
--              lda pt_data_1bit,x
                jsr write2_pt_bytes     ; use nybbles as indexes to 2 bytes to write
                ;
                txa                     ; if X % 4 = 0, write 2nd bitplane (8 zeros)
                and #%00000011
                bne +
                ldy #8
-               sta ppu_data
                dey
                bne -
                ;
+               cpx #(pt_data_1bit_end-pt_data_1bit)
                bne --

                ldy #$20                ; prepare to write two name and attribute tables
                lda #$00
                jsr set_ppu_addr

                ldy #30                 ; name table 0: vertical stripes, Y=row counter,
                ;                       ; every row is the same:
--              ldx #(256-16)           ; X & %11 for X = 240...255 and 15...0
-               txa
                and #%00000011
                sta ppu_data
                inx
                bne -
                ldx #(16-1)
-               txa
                and #%00000011
                sta ppu_data
                dex
                bpl -
                ;
                dey
                bne --

                ldy #8                  ; attribute table 0: vertical stripes, Y=row counter
--              ldx #(8-1)
-               lda attr_data,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

                ldy #0                  ; name table 1: horizontal stripes, Y=row counter,
-               jsr write_nt1_row       ; each row consists of one tile only:
                iny                     ; Y & %11 for Y = 0...15 and 15...2
                cpy #16
                bne -
                dey
-               jsr write_nt1_row
                dey
                cpy #1
                bne -

                ldy #(8-1)              ; attribute table 1: horizontal stripes, Y=row counter
--              lda attr_data,y
                ldx #8
-               sta ppu_data
                dex
                bne -
                dey
                bpl --

                jsr wait_vbl_start      ; wait for start of VBlank

                lda #%10000001          ; enable NMI, use name table 1
                sta ppu_ctrl_copy
                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                jmp main_loop

wait_vbl_start  bit ppu_status          ; wait for start of VBlank
-               bit ppu_status
                bpl -
                rts

sine_deltas     ; sine table: 64 values for angles < 90 degrees; each value is a 2-bit unsigned
                ; delta; Python 3:
                ;   import math
                ;   v = [round(128-4+math.sin(i*2*math.pi/256)*100) for i in range(64)]
                ;   d = [b-a for (a,b) in zip([v[0]]+v,v)]
                ;   bytes(d[i]*64+d[i+1]*16+d[i+2]*4+d[i+3] for i in range(0,len(d),4)).hex()
                hex 2e ee eb ae ba aa ea 6a 9a 66 59 55 55 45 10 40

write2_pt_bytes pha                     ; in: A = byte from pt_data_2bit/pt_data_1bit;
                inx                     ; write 2 pattern table bytes using nybbles of A as
                ;                       ; indexes to pt_data_bytes; also increment X
                ;
                lsr a                   ; get 1st actual byte by high nybble
                lsr a
                lsr a
                lsr a
                tay
                lda pt_data_bytes,y
                sta ppu_data
                ;
                pla                     ; get 2nd actual byte by low nybble
                and #%00001111
                tay
                lda pt_data_bytes,y
                sta ppu_data
                ;
                rts

                ; pattern table data (each nybble is an index to pt_data_bytes)
pt_data_2bit    ; 2-bit tiles (16 nybbles = 1 tile)
                hex 99999999 00000000  ; tile $00: solid    color 1
                hex 34343434 43434343  ; tile $01: dithered color 1/2
                hex 00000000 99999999  ; tile $02: solid    color 2
                hex 43434343 99999999  ; tile $03: dithered color 2/3
pt_data_2bit_end
pt_data_1bit    ; 1-bit tiles (8 nybbles = 1st bitplane of 1 tile; 2nd bitplane will be zeroed)
                hex 96696666  ; tile $04: "A"
                hex 55596699  ; tile $05: "B"
                hex 11196699  ; tile $06: "D"
                hex 95595599  ; tile $07: "E"
                hex 95566699  ; tile $08: "G"
                hex 22222222  ; tile $09: "I"/"1"
                hex 55555599  ; tile $0a: "L"
                hex 68976666  ; tile $0b: "M"
                hex 96666666  ; tile $0c: "N"
                hex 96666699  ; tile $0d: "O"/"0"
                hex 96691111  ; tile $0e: "Q"/"9"
                hex 95555555  ; tile $0f: "R"
                hex 92222222  ; tile $10: "T"
                hex 66699119  ; tile $11: "Y"
                hex 91195599  ; tile $12: "Z"/"2"
                hex 66691111  ; tile $13: "4"
pt_data_1bit_end

pt_data_bytes   ; actual pattern table data bytes (all tiles consist of these bytes only)
                db %00000000  ; index 0
                db %00000011  ; index 1
                db %00011000  ; index 2
                db %01010101  ; index 3
                db %10101010  ; index 4
                db %11000000  ; index 5
                db %11000011  ; index 6
                db %11011011  ; index 7
                db %11100111  ; index 8
                db %11111111  ; index 9

write_nt1_row   tya                     ; write Y & %11 32 times to VRAM
                and #%00000011
                ldx #32
-               sta ppu_data
                dex
                bne -
                rts

attr_data       ; attribute table data (read backwards but it's the same both ways)
                hex 00 55 aa ff ff aa 55 00

; --- Main loop -----------------------------------------------------------------------------------

main_loop       bit run_main_loop       ; wait until NMI routine has set flag
                bpl main_loop
                lsr run_main_loop       ; clear flag

                lda direction           ; if direction=0, decr. color_counter (animate inwards)
                bne +                   ; if direction=1, incr. color_counter (animate outwards)
                dec color_counter       ; if color_counter ends up at zero, invert direction
                jmp ++
+               inc color_counter
++              bne +
                lda direction
                eor #%00000001
                sta direction

+               lda color_counter       ; from which index in ROM to copy palette to PPU
                asl a                   ; more "ASL A" instructions -> faster animation
                asl a
                and #%01110000
                sta pal_src_index

                lda color_counter       ; which name table to show:
                and #%10000000          ; (MSB of color_counter) XOR direction
                asl a
                rol a
                eor direction
                ora #%10000000
                sta ppu_ctrl_copy

                inc text_counter        ; move text

                ldy text_counter        ; set positions of letter sprites
                ldx #0                  ; X = letter index / destination index; Y = angle
                ;
-               txa                     ; letter index -> stack, destination index -> X
                pha
                asl a
                asl a
                tax
                lda sine_table,y        ; sine of angle -> sprite Y position
                sbc #(10-1-1)           ; carry is always clear
                sta sprite_data+0,x
                tya                     ; increase angle by 90 degrees (256/4)
                adc #(64-1)             ; carry is always set
                tay
                lda sine_table,y        ; sine of angle -> sprite X position
                sta sprite_data+3,x
                pla                     ; letter index -> X
                tax
                tya                     ; decrease angle for next letter (64 has been added to
                sec                     ; each value in table to undo the increment above)
                sbc angle_changes,x
                tay
                ;
                inx
                cpx #(spr_tiles_end-spr_tiles)
                bne -

                jmp main_loop           ; infinite loop

spr_tiles       ; tiles of sprites (note: spaces are defined in angle_changes)
                hex 09 0d 12 13              ; "IOZ4"
                hex 05 11 10 07              ; "BYTE"
                hex 08 0f 04 06 09 07 0c 10  ; "GRADIENT"
                hex 06 07 0b 0d              ; "DEMO"
                hex 05 11                    ; "BY"
                hex 0e 04 0a 0a 07           ; "QALLE"
spr_tiles_end

angle_changes   ; what to subtract from (angle+64) after each letter
                db 64+7, 64+7, 64+7, 64+12
                db 64+7, 64+7, 64+7, 64+12
                db 64+7, 64+7, 64+7, 64+7, 64+7, 64+7, 64+7, 64+12
                db 64+7, 64+7, 64+7, 64+12
                db 64+7, 64+12
                db 64+7, 64+7, 64+7, 64+7
                ;
                if $-angle_changes != spr_tiles_end-spr_tiles - 1
                    error "length of angle_changes must equal length of spr_tiles minus 1"
                endif

; --- Interrupt routines --------------------------------------------------------------------------

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; reset ppu_scroll/ppu_addr latch
                lda #$00                ; do OAM DMA
                sta oam_addr
                lda #>sprite_data
                sta oam_dma

                ldy #$3f                ; copy 16 colors from ROM to background palettes
                lda #$00
                jsr set_ppu_addr
                ldx pal_src_index
                ldy #16
-               lda palettes,x
                sta ppu_data
                inx
                dey
                bne -

                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                sec                     ; set flag to let main loop run once
                ror run_main_loop

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti                     ; note: IRQ unused

palettes        ; eight 16-color sets of background palettes
                db colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1
                db colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2
                db colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3
                db colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4
                db colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5
                db colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6
                db colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7
                db colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8

; --- Subs used in many places --------------------------------------------------------------------

set_ppu_addr    sty ppu_addr            ; set PPU address from Y & A
                sta ppu_addr
                rts

set_ppu_regs    lda #0
                sta ppu_scroll
                sta ppu_scroll
                lda ppu_ctrl_copy
                sta ppu_ctrl
                lda #%00011110          ; show background and sprites
                sta ppu_mask
                rts

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq  ; note: IRQ unused
