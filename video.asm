; Plays a short video of Doom gameplay on the NES.
; Assembles with ASM6.
; 32*24 tiles (64*48 "pixels"), 4 colors, 40 frames, 10 fps
; While one name table is being shown, the program copies 32*4 tiles/frame to
; another name table.

; --- iNES header -------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 2, 1                  ; 32 KiB PRG ROM, 8 KiB CHR ROM
                db %00000001, %00000000  ; NROM mapper, vertical NT mirroring
                pad $0010, $00           ; unused

; --- Constants ---------------------------------------------------------------

; Notes:
; - 2-byte addresses are stored low byte first
; - boolean variables: $00-$7f = false, $80-$ff = true

; RAM
vram_buffer     equ $00  ; 128 bytes; NT data to copy during VBlank
nt_data_ptr     equ $80  ; 2 bytes; read pointer to NT data
ppu_addr_copy   equ $82  ; 2 bytes; copy of ppu_addr
ppu_ctrl_copy   equ $84  ; copy of ppu_ctrl
counter_lo      equ $85  ; 0-5
counter_hi      equ $86  ; 0 to (frame_count-1)
run_main        equ $87  ; allow main loop to run (boolean)

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
snd_ctrl        equ $4015
joypad2         equ $4017

frame_count     equ 40  ; number of complete frames

; --- Initialization ----------------------------------------------------------

                base $8000              ; last 32 KiB of CPU memory space

reset           ; initialize the NES;
                ; see https://wiki.nesdev.org/w/index.php/Init_code
                ;
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
                stx snd_ctrl            ; disable sound channels

                jsr wait_vbl_start      ; wait until next VBlank starts
                jsr init_ram            ; initialize main RAM

                jsr wait_vbl_start      ; wait until next VBlank starts
                jsr init_ppu_mem        ; initialize PPU memory

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #%10000000          ; enable NMI, use NT0
                sta ppu_ctrl_copy
                jsr set_ppu_regs        ; clear ppu_scroll, update ppu_ctrl
                lda #%00001010          ; show background
                sta ppu_mask

                jmp main_loop

wait_vbl_start  bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -
                rts

init_ram        ; initialize main RAM

                lda #0                  ; reset counters
                sta counter_lo
                sta counter_hi

                sec                     ; set flag to let main loop run once
                ror run_main

                rts

init_ppu_mem    ; initialize PPU memory

                ; set palette (while still in VBlank)
                ;
                ldy #$3f
                lda #$00
                jsr set_ppu_addr        ; Y*256 + A -> PPU address
                tax
                ;
-               lda palette,x
                sta ppu_data
                inx
                cpx #4
                bne -

                ; clear NTs and ATs (8*256 bytes)
                ;
                ldy #$20
                lda #$00
                jsr set_ppu_addr        ; Y*256 + A -> PPU address
                tax
                ldy #8
                ;
-               sta ppu_data
                inx
                bne -
                dey
                bne -

                rts

set_ppu_addr    ; Y*256 + A -> PPU address
                sty ppu_addr
                sta ppu_addr
                rts

palette         hex 0f 12 22 30         ; black, dark blue, light blue, white

; --- Main loop ---------------------------------------------------------------

main_loop       bit run_main            ; wait until NMI routine has set flag
                bpl main_loop

                lsr run_main            ; clear flag

                jsr write_buffer        ; copy NT data to VRAM buffer
                jsr get_ppu_addr        ; get target PPU address
                jsr inc_counters        ; increment counters
                jsr get_ppu_ctrl        ; get value for ppu_ctrl

                jmp main_loop

write_buffer    ; copy NT (video) data for this frame to VRAM buffer
                ; (NMI routine can read it faster from there)

                ; nt_data_ptr = nt_data + counter_hi * $300 + counter_lo * $80

                ; low byte: (<nt_data) + counter_lo * $80
                lda counter_lo
                lsr a
                lda #0
                ror a
                clc
                adc #<nt_data
                sta nt_data_ptr+0

                ; high byte: carry + (>nt_data) + counter_hi*3 + counter_lo/2
                ;
                lda #>nt_data
                adc counter_hi
                adc counter_hi
                adc counter_hi
                sta nt_data_ptr+1
                ;
                lda counter_lo
                lsr a
                clc
                adc nt_data_ptr+1
                sta nt_data_ptr+1

                ; copy 128 bytes (4*32 tiles)
                ldy #0
-               lda (nt_data_ptr),y
                sta vram_buffer,y
                iny
                bpl -

                rts

get_ppu_addr    ; get target PPU address

                ; ppu_addr_copy
                ; = $2060 + counter_hi % 2 * $0400 + counter_lo * $80

                ; low byte: $60 + counter_lo * $80
                lda counter_lo
                lsr a
                lda #%11000000
                ror a
                sta ppu_addr_copy+0

                ; high byte: $20 + counter_hi % 2 * 4 + counter_lo / 2
                lda counter_hi
                and #%00000001
                asl a
                asl a
                asl a
                ora counter_lo
                lsr a
                ora #%00100000
                sta ppu_addr_copy+1

                rts

inc_counters    ; increment counters

                ldx counter_lo
                ldy counter_hi
                ;
                inx
                cpx #6
                bne +
                ldx #0
                ;
                iny
                cpy #frame_count
                bne +
                ldy #0
                ;
+               stx counter_lo
                sty counter_hi

                rts

get_ppu_ctrl    ; get value for ppu_ctrl (which name table to show)

                ; 1 on even complete frames, 0 on odd complete frames
                lda counter_hi
                and #%00000001
                eor #%00000001
                ora #%10000000
                sta ppu_ctrl_copy

                rts

; --- Name table (video) data -------------------------------------------------

nt_data         ; name table data for the video
                ; frame_count frames, 24 rows/frame, 32 tiles/row (tile = byte)
                ; IIRC, I copied this from some video on https://tasvideos.org
                ;
                incbin "video-nt.bin"
                pad nt_data+frame_count*24*32, $ff

; --- Interrupt routines ------------------------------------------------------

                align $100, $ff         ; for speed

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; reset ppu_addr/ppu_scroll latch

                ; copy 128 bytes (4 rows) of video data to name table
                ;
                ldy ppu_addr_copy+1
                lda ppu_addr_copy+0
                jsr set_ppu_addr        ; Y*256 + A -> PPU address
                ;
                ldx #0
-               lda vram_buffer,x
                sta ppu_data
                inx
                bpl -

                jsr set_ppu_regs        ; clear ppu_scroll, update ppu_ctrl

                sec                     ; set flag to let main loop run once
                ror run_main

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti                     ; IRQ unused

set_ppu_regs    ; clear ppu_scroll, update ppu_ctrl
                lda #$00
                sta ppu_scroll
                sta ppu_scroll
                lda ppu_ctrl_copy
                sta ppu_ctrl
                rts

; --- Interrupt vectors -------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; IRQ unused

; --- CHR ROM -----------------------------------------------------------------

                ; all combinations of 2*2 "pixels" in 4 colors
                base $0000
                incbin "video-chr.bin"
                pad $2000, $ff
