; Gradient demo (NES, ASM6). Seizure warning.
; Style:
; - indentation of instructions: 12 spaces
; - maximum length of identifiers: 11 characters
; TODO:
; - move stuff from NMI routine to main loop
; - reduce size of sine table

; --- Constants -----------------------------------------------------------------------------------

; memory-mapped registers
ppu_ctrl    equ $2000
ppu_mask    equ $2001
ppu_status  equ $2002
ppu_addr    equ $2006
ppu_data    equ $2007
dmc_freq    equ $4010
oam_addr    equ $2003
oam_dma     equ $4014
sound_ctrl  equ $4015
joypad2     equ $4017

; RAM
sprite_data equ $00
color_cntr  equ $0200  ; color counter
text_cntr   equ $0201  ; text counter
direction   equ $0202  ; 0 = animate colors inwards, 1 = animate colors outwards
temp        equ $0203  ; temporary

; colors
colbg       equ $0f
cl1         equ $12
cl2         equ $14
cl3         equ $16
cl4         equ $17
cl5         equ $18
cl6         equ $19
cl7         equ $1a
cl8         equ $1c

letter_cnt  equ 19  ; number of letters in text

; --- iNES header ---------------------------------------------------------------------------------

            ; see https://wiki.nesdev.org/w/index.php/INES
            base $0000
            db "NES", $1a            ; file id
            db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
            db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
            pad $0010, $00           ; unused

; --- Initialization ------------------------------------------------------------------------------

            base $c000             ; last 16 KiB of CPU memory space

reset       ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
            sei                    ; ignore IRQs
            cld                    ; disable decimal mode
            ldx #%01000000
            stx joypad2            ; disable APU frame IRQ
            ldx #$ff
            txs                    ; initialize stack pointer
            inx
            stx ppu_ctrl           ; disable NMI
            stx ppu_mask           ; disable rendering
            stx dmc_freq           ; disable DMC IRQs
            stx sound_ctrl         ; disable sound channels

            bit ppu_status         ; wait for start of VBlank
-           bit ppu_status
            bpl -

            lda #0                 ; start animating colors inwards
            sta direction

            lda #$ff               ; fill sprite data with $ff to hide unused sprites
            ldx #0
-           sta sprite_data,x
            inx
            bne -

            ldx #0                 ; sprite data - tiles
            ldy #0                 ; (note: 6502 has STA zp,x but no STA zp,y)
-           lda spritetiles,y
            sta sprite_data+1,x
            inx
            inx
            inx
            inx
            iny
            cpy #letter_cnt
            bne -

            lda #%00000000         ; sprite data - attributes
            ldx #(letter_cnt*4-4)
-           sta sprite_data+2,x
            dex
            dex
            dex
            dex
            bpl -

            bit ppu_status         ; wait for start of VBlank
-           bit ppu_status
            bpl -

            lda #$3f               ; palette (black -> 2nd color of 1st sprite subpalette)
            sta ppu_addr
            lda #$11
            sta ppu_addr
            lda #$0f
            sta ppu_data

            lda #$20               ; prepare to write name and attribute tables
            sta ppu_addr
            lda #$00
            sta ppu_addr

            lda #30                ; write name table 0
            sta temp
--          ldy #4
-           ldx #0
            stx ppu_data
            inx
            stx ppu_data
            inx
            stx ppu_data
            inx
            stx ppu_data
            dey
            bne -
            ldy #4
-           ldx #3
            stx ppu_data
            dex
            stx ppu_data
            dex
            stx ppu_data
            dex
            stx ppu_data
            dey
            bne -
            ldy temp
            dey
            sty temp
            bne --

            ldy #8                 ; write attribute table 0
--          ldx #0
-           lda attr_data,x
            sta ppu_data
            inx
            cpx #8
            bne -
            dey
            bne --

            ldy #0                 ; write name table 1
--          tya
            and #%00000011
            ldx #32
-           sta ppu_data
            dex
            bne -
            iny
            cpy #16
            bne --
            ldy #15
--          tya
            and #%00000011
            ldx #32
-           sta ppu_data
            dex
            bne -
            dey
            cpy #1
            bne --

            ldy #0                 ; write attribute table 1
--          lda attr_data,y
            ldx #8
-           sta ppu_data
            dex
            bne -
            iny
            cpy #8
            bne --

            lda #0
            sta ppu_addr
            sta ppu_addr

            bit ppu_status         ; wait for start of VBlank
-           bit ppu_status
            bpl -

            lda #%10000001         ; enable NMI, use name table 1
            sta ppu_ctrl
            lda #%00011110         ; show background and sprites
            sta ppu_mask

            jmp main_loop

spritetiles ; sprite tiles (note: length must equal letter_cnt; spaces are defined in angle_chgs)
            hex 04 05 06 07 08 09 0a 0b  ; "GRADIENT"
            hex 07 09 0c 0d              ; "DEMO"
            hex 0e 0f                    ; "BY"
            hex 10 06 11 11 09           ; "QALLE"

attr_data   ; attribute table data
            db %00000000, %01010101, %10101010, %11111111
            db %11111111, %10101010, %01010101, %00000000

; --- Main loop -----------------------------------------------------------------------------------

main_loop   jmp main_loop  ; infinite loop

; --- Interrupt routines --------------------------------------------------------------------------

nmi         lda #$00             ; update sprite data
            sta oam_addr
            lda #>sprite_data
            sta oam_dma

            lda direction        ; color_cntr counts between 0 and 255
            beq +
            inc color_cntr       ; animate colors outwards
            jmp ++
+           dec color_cntr       ; animate colors inwards
++          bne +
            lda direction        ; color_cntr is zero; change direction
            eor #%00000001
            sta direction

+           bit ppu_status       ; change background palettes
            lda #$3f
            sta ppu_addr
            lda #$00
            sta ppu_addr
            lda color_cntr
            asl a                ; more "ASL A" instructions -> faster animation
            asl a
            and #%01110000
            tax
            ldy #16
-           lda palettes,x
            sta ppu_data
            inx
            dey
            bne -

            lda #$00             ; reset VRAM address
            sta ppu_addr
            sta ppu_addr

            lda color_cntr       ; name table selection
            asl a
            rol a
            and #%00000001
            eor direction
            ora #%10000000
            sta ppu_ctrl

            inc text_cntr        ; set positions of letter sprites
            ldy text_cntr        ; X = current index of letter, Y = current angle
            ldx #0
-           stx temp             ; store X, set Y position
            txa
            asl a
            asl a
            tax
            lda sine_table,y
            sta sprite_data+0,x
            tya                  ; set X position by increasing angle by 90 degrees
            clc
            adc #$40
            tay
            lda sine_table,y
            clc
            adc #9
            sta sprite_data+3,x
            ldx temp             ; restore X, decrease angle for next letter
            tya
            sec
            sbc angle_chgs,x
            tay
            inx
            cpx #letter_cnt
            bne -

irq         rti                  ; note: IRQ unused

palettes    db colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1
            db colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2
            db colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3
            db colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4
            db colbg,cl5,cl6,cl7, colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5
            db colbg,cl6,cl7,cl8, colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6
            db colbg,cl7,cl8,cl1, colbg,cl1,cl2,cl3, colbg,cl3,cl4,cl5, colbg,cl5,cl6,cl7
            db colbg,cl8,cl1,cl2, colbg,cl2,cl3,cl4, colbg,cl4,cl5,cl6, colbg,cl6,cl7,cl8

sine_table  ; angle (0-255) -> X/Y position of letter sprite (15-214, average=114.5)
            db 115,117,119,122,124,127,129,132,134,136,139,141,144,146,148,150
            db 153,155,157,159,162,164,166,168,170,172,174,176,178,180,182,183
            db 185,187,189,190,192,193,195,196,198,199,200,202,203,204,205,206
            db 207,208,209,209,210,211,212,212,213,213,213,214,214,214,214,214
            db 214,214,214,214,214,214,213,213,213,212,212,211,210,209,209,208
            db 207,206,205,204,203,202,200,199,198,196,195,193,192,190,189,187
            db 185,183,182,180,178,176,174,172,170,168,166,164,162,159,157,155
            db 153,150,148,146,144,141,139,136,134,132,129,127,124,122,119,117
            db 115,112,110,107,105,102,100, 97, 95, 93, 90, 88, 85, 83, 81, 79
            db  76, 74, 72, 70, 67, 65, 63, 61, 59, 57, 55, 53, 51, 49, 47, 46
            db  44, 42, 40, 39, 37, 36, 34, 33, 31, 30, 29, 27, 26, 25, 24, 23
            db  22, 21, 20, 20, 19, 18, 17, 17, 16, 16, 16, 15, 15, 15, 15, 15
            db  15, 15, 15, 15, 15, 15, 16, 16, 16, 17, 17, 18, 19, 20, 20, 21
            db  22, 23, 24, 25, 26, 27, 29, 30, 31, 33, 34, 36, 37, 39, 40, 42
            db  44, 46, 47, 49, 51, 53, 55, 57, 59, 61, 63, 65, 67, 70, 72, 74
            db  76, 79, 81, 83, 85, 88, 90, 93, 95, 97,100,102,105,107,110,112

angle_chgs  ; change of angle after each letter (note: length must equal letter_cnt minus 1)
            db  68, 68, 68, 68, 68, 68, 68, 72
            db  68, 68, 68, 72
            db  68, 72
            db  68, 68, 68, 68

; --- Interrupt vectors ---------------------------------------------------------------------------

            pad $fffa, $ff
            dw nmi, reset, irq  ; note: IRQ unused

; --- CHR ROM -------------------------------------------------------------------------------------

            pad $10000, $ff
            incbin "gradient-chr.bin"
            pad $12000, $ff
