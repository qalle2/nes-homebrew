; Gradient demo (NES, ASM6). Seizure warning.
; TODO: reduce size of cosine table?

; --- Constants -----------------------------------------------------------------------------------

; RAM
; note: on the OAM page, attribute bytes of unused sprites ($x2/$x6/$xa/$xe) are used for other
; variables too
sprite_data     equ $00  ; OAM page ($100 bytes)
color_counter   equ $c2  ; color counter
text_counter    equ $c6  ; text counter
direction       equ $ca  ; direction of color animation: 0=inwards, 1=outwards
ppu_ctrl_copy   equ $ce  ; copy of ppu_ctrl
run_main_loop   equ $d2  ; is main loop allowed to run? (MSB: 0=no, 1=yes)
pal_src_index   equ $d6  ; start index in ROM palette (0-112 in steps of 16)
temp            equ $da  ; temporary

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
colbg           equ $0f
cl1             equ $12
cl2             equ $14
cl3             equ $16
cl4             equ $17
cl5             equ $18
cl6             equ $19
cl7             equ $1a
cl8             equ $1c

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
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

                jsr wait_vbl_start      ; wait for start of VBlank

                ldy #$3f                ; palette (black -> 2nd color of 1st sprite subpalette)
                lda #$11
                jsr set_ppu_addr
                lda #$0f
                sta ppu_data

                ldy #$20                ; prepare to write name and attribute tables
                lda #$00
                jsr set_ppu_addr

                ldy #30                 ; name table 0 (vertical stripes; Y = row counter)
                ;
--              ldx #(256-16)           ; tiles: 4 * (00 01 02 03)
-               txa
                and #%00000011
                sta ppu_data
                inx
                bne -
                ;
                ldx #(16-1)             ; tiles: 4 * (03 02 01 00)
-               txa
                and #%00000011
                sta ppu_data
                dex
                bpl -
                ;
                dey
                bne --

                ldy #8                  ; attribute table 0 (vertical stripes; Y = row counter)
--              ldx #(8-1)
-               lda attr_data,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

                ldy #0                  ; name table 1 (horizontal stripes)
--              tya                     ; 16 rows; each one consists of one tile only
                and #%00000011          ; (00, 01, 02, 03, 00, ...)
                ldx #32
-               sta ppu_data
                dex
                bne -
                iny
                cpy #16
                bne --
                ;
                dey                     ; Y = 15
--              tya                     ; 14 rows; each one consists of one tile only
                and #%00000011          ; (03, 02, 01, 00, ...)
                ldx #32
-               sta ppu_data
                dex
                bne -
                dey
                cpy #1
                bne --

                ldy #(8-1)              ; write attribute table 1 (horiz. stripes; Y=row counter)
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

attr_data       ; attribute table data (read backwards but it's the same both ways)
                db %00000000, %01010101, %10101010, %11111111
                db %11111111, %10101010, %01010101, %00000000

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
-               txa                     ; letter index -> A, stack
                pha
                ;
                asl a                   ; destination index -> X
                asl a
                tax
                ;
                tya                     ; cosine of A -> A
                jsr get_cosine
                sbc #(10-1-1)           ; carry is always clear
                sta sprite_data+0,x     ; set sprite Y position
                ;
                tya                     ; increase angle by 90 degrees (256/4)
                clc
                adc #64
                ;
                jsr get_cosine          ; cosine of A -> A
                sta sprite_data+3,x     ; set sprite X position
                ;
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

get_cosine      bmi +                   ; in: A = angle (0-255); N flag must be set according to A
                tay                     ; out: A = cosine of A, Y = original A
                lda cosine_table,y
                rts
+               sta temp                ; angle >= 128; temporarily invert index
                eor #%11111111
                tay
                lda cosine_table,y
                ldy temp
                rts

cosine_table    ; 128 values for angles < 180 degrees (to get values for angles >= 180 degrees,
                ; use 360 degrees minus angle as index)
                ; Python 3:
                ; ",".join(format(128-4+math.cos(i*2*math.pi/256)*100,"3.0f") for i in range(128))
                ;
                db 224,224,224,224,224,223,223,223,222,222,221,220,220,219,218,217
                db 216,215,214,213,212,211,210,208,207,206,204,203,201,200,198,196
                db 195,193,191,189,187,186,184,182,180,177,175,173,171,169,167,165
                db 162,160,158,155,153,151,148,146,144,141,139,136,134,131,129,126
                db 124,122,119,117,114,112,109,107,104,102,100, 97, 95, 93, 90, 88
                db  86, 83, 81, 79, 77, 75, 73, 71, 68, 66, 64, 62, 61, 59, 57, 55
                db  53, 52, 50, 48, 47, 45, 44, 42, 41, 40, 38, 37, 36, 35, 34, 33
                db  32, 31, 30, 29, 28, 28, 27, 26, 26, 25, 25, 25, 24, 24, 24, 24

spr_tiles       ; tiles of sprites (note: spaces are defined in angle_changes)
                hex 04 05 06 07 08 09 0a 0b  ; "GRADIENT"
                hex 07 09 0c 0d              ; "DEMO"
                hex 0e 0f                    ; "BY"
                hex 10 06 11 11 09           ; "KALLE"
spr_tiles_end

angle_changes   ; what to subtract from (angle+64) after each letter
                db 64+8, 64+8, 64+8, 64+8, 64+8, 64+8, 64+8, 64+12
                db 64+8, 64+8, 64+8, 64+12
                db 64+8, 64+12
                db 64+8, 64+8, 64+8, 64+8
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

; --- CHR ROM -------------------------------------------------------------------------------------

                pad $10000, $ff
                incbin "gradient-chr.bin"
                pad $12000, $ff
