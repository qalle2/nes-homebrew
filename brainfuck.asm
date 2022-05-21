; Qalle's Brainfuck (NES, ASM6)

; --- Constants -----------------------------------------------------------------------------------

; notes:
; - only the first sprite slot is actually used, and the other slots only need their Y positions
;   to be set to $ff, so the OAM page accommodates many other variables at addresses
;   not divisible by 4 ($05-$07, $09-$0b, $0d-$0f, ...)
; - "VRAM buffer" = what to write to PPU on next VBlank
; - bottom half of stack ($0100-$017f) is used for other purposes
; - nmi_done: did the NMI routine just run? used for once-per-frame stuff; set by NMI,
;   read and cleared at the start of main loop

; RAM
sprite_data     equ $00    ; OAM page ($100 bytes, see above)
pointer         equ $05    ; memory pointer (2 bytes; e.g. RAM address of Brainfuck program)
program_mode    equ $07    ; see constants below
nmi_done        equ $09    ; see above ($00 = no, $80 = yes)
ppu_ctrl_copy   equ $0a    ; copy of ppu_ctrl
frame_counter   equ $0b    ; for blinking cursors
pad_status      equ $0d    ; joypad status
prev_pad_status equ $0e    ; previous joypad status
vram_buf_adrhi  equ $0f    ; VRAM buffer - high byte of address ($00 = buffer is empty)
vram_buf_adrlo  equ $11    ; VRAM buffer - low  byte of address
vram_buf_value  equ $12    ; VRAM buffer - value
program_len     equ $13    ; length of Brainfuck program (0-$fe)
bf_pc           equ $15    ; program counter of Brainfuck program (preincremented)
output_len      equ $16    ; number of characters printed by the Brainfuck program (0-$fe)
keyb_x          equ $17    ; cursor X position on virtual keyboard (0-15)
keyb_y          equ $19    ; cursor Y position on virtual keyboard (0-5)
temp            equ $1a    ; a temporary variable
bf_program      equ $0200  ; Brainfuck program ($100 bytes)
brackets        equ $0300  ; target addresses of "[" and "]" ($100 bytes)
bf_ram          equ $0400  ; RAM of Brainfuck program ($400 bytes; must be at $xx00)

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
snd_chn         equ $4015
joypad1         equ $4016
joypad2         equ $4017

; joypad button bitmasks
pad_a           equ 1<<7
pad_b           equ 1<<6
pad_sel         equ 1<<5
pad_start       equ 1<<4
pad_u           equ 1<<3
pad_d           equ 1<<2
pad_l           equ 1<<1
pad_r           equ 1<<0

; colors
color_bg        equ $0f  ; background (black)
color_fg        equ $30  ; foreground (white)
color_unused    equ $25  ; unused (pink)

; tiles
tile_block      equ $80  ; solid block
tile_hbar       equ $81  ; horizontal bar
tile_uarr       equ $82  ; up arrow
tile_darr       equ $83  ; down arrow
tile_larr       equ $84  ; left arrow
tile_rarr       equ $85  ; right arrow

; values for program_mode (must be 0, 1, ... because they're used as indexes to jump table)
mode_edit       equ 0    ; editing BF program (must be 0)
mode_prep_run1  equ 1    ; preparing to run BF program, part 1/2
mode_prep_run2  equ 2    ; preparing to run BF program, part 2/2
mode_run        equ 3    ; BF program running
mode_input      equ 4    ; BF program waiting for input
mode_ended      equ 5    ; BF program finished

; misc
blink_rate      equ 3           ; cursor blink rate (0 = fastest, 7 = slowest)
cursor_tile1    equ $20         ; cursor tile 1 (space)
cursor_tile2    equ tile_block  ; cursor tile 2

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
                db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
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
                stx snd_chn             ; disable sound channels

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #$00                ; clear sprite/variables page and Brainfuck code
                tax
-               sta sprite_data,x
                sta bf_program,x
                inx
                bne -

                lda #$ff                ; hide all sprites (set Y positions to $ff;
-               sta sprite_data,x       ; X is still 0)
                inx
                inx
                inx
                inx
                bne -

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$3f                ; set up palette (while still in VBlank; 8*4 bytes)
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                ;
                ldy #8
--              ldx #(4-1)
-               lda palette,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

                ldy #$00                ; fill pattern table 0 (PPU $0000-$0fff) with $00
                tya
                jsr set_ppu_addr        ; Y, A -> address
                ldx #16
-               jsr fill_vram           ; write A Y times
                dex
                bne -

                lda #<pt_data           ; copy data from array to pattern table 0, starting from
                sta pointer+0           ; tile $20
                lda #>pt_data
                sta pointer+1
                ;
                ldy #$02
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                ;
                tax                     ; X = 0, Y = output index within tile
                tay
                ;
--              lda (pointer,x)
                sta ppu_data
                iny                     ; fill 2nd bitplane of every tile with $00
                cpy #8
                bne +
                lda #$00
                jsr fill_vram           ; write A Y times
                ;
+               inc pointer+0
                bne +
                inc pointer+1
                ;
+               lda pointer+1
                cmp #>pt_data_end
                bne --
                lda pointer+0
                cmp #<pt_data_end
                bne --

                ldy #$20                ; fill name & attribute table 0 & 1 ($2000-$27ff) with $00
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                ldx #8
                tay
-               jsr fill_vram           ; write A Y times
                dex
                bne -

                ldx #$ff                ; copy strings to NT0 (edit mode) and NT1 (run mode)
--              inx
                ldy strings,x           ; VRAM address high (0 = end of all strings)
                beq strings_end
                inx
                lda strings,x           ; VRAM address low
                jsr set_ppu_addr        ; Y, A -> address
-               inx
                lda strings,x           ; byte (0 = end of string)
                beq +
                sta ppu_data
                bne -                   ; unconditional
+               beq --                  ; next string (unconditional)

strings_end     ldx #(4-1)              ; draw horizontal bars in NT0 & NT1
-               ldy horz_bars_hi,x
                lda horz_bars_lo,x
                jsr set_ppu_addr        ; Y, A -> address
                ldy #32
                lda #tile_hbar
                jsr fill_vram           ; write A Y times
                dex
                bpl -

                ldy #$26                ; draw virtual keyboard in NT1
                lda #$78
                jsr set_ppu_addr        ; Y, A -> address
                ;
                ldx #32                 ; X = character code
-               txa                     ; print 16 spaces before start of each line
                and #%00001111
                bne +
                ldy #16
                lda #$20
                jsr fill_vram           ; write A Y times
+               stx ppu_data
                inx
                bpl -

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #%10000000          ; enable NMI, show name table 0
                sta ppu_ctrl_copy
                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                jmp main_loop

wait_vbl_start  bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -
                rts

fill_vram       sta ppu_data            ; write A to VRAM Y times
                dey
                bne fill_vram
                rts

palette         ; copied backwards to all subpalettes
                ; note: 2nd color of 1st sprite subpalette blinks and is used for cursors
                db color_unused, color_unused, color_fg, color_bg

                ; pattern table data
                ; 8 bytes = 1st bitplane of 1 tile; 2nd bitplanes are all zeroes
                ; tiles $20-$7e are ASCII
                ;
pt_data         hex 00 00 00 00 00 00 00 00  ; tile $20
                hex 10 10 10 10 10 00 10 00  ; tile $21
                hex 28 28 00 00 00 00 00 00  ; tile $22
                hex 28 28 7c 28 7c 28 28 00  ; tile $23
                hex 10 3c 50 38 14 78 10 00  ; tile $24
                hex 00 44 08 10 20 44 00 00  ; tile $25
                hex 38 44 28 10 2a 44 3a 00  ; tile $26
                hex 10 10 00 00 00 00 00 00  ; tile $27
                hex 08 10 20 20 20 10 08 00  ; tile $28
                hex 20 10 08 08 08 10 20 00  ; tile $29
                hex 00 44 28 fe 28 44 00 00  ; tile $2a
                hex 10 10 10 fe 10 10 10 00  ; tile $2b
                hex 00 00 00 00 08 10 20 00  ; tile $2c
                hex 00 00 00 fc 00 00 00 00  ; tile $2d
                hex 00 00 00 00 00 18 18 00  ; tile $2e
                hex 02 04 08 10 20 40 80 00  ; tile $2f
                hex 7c 82 82 92 82 82 7c 00  ; tile $30
                hex 10 30 10 10 10 10 38 00  ; tile $31
                hex 7c 82 02 7c 80 80 fe 00  ; tile $32
                hex fc 02 02 fc 02 02 fc 00  ; tile $33
                hex 08 18 28 48 fe 08 08 00  ; tile $34
                hex fe 80 80 fc 02 02 fc 00  ; tile $35
                hex 7e 80 80 fc 82 82 7c 00  ; tile $36
                hex fe 04 08 10 20 40 80 00  ; tile $37
                hex 7c 82 82 7c 82 82 7c 00  ; tile $38
                hex 7c 82 82 7e 02 02 fc 00  ; tile $39
                hex 00 10 00 00 00 10 00 00  ; tile $3a
                hex 00 10 00 00 10 20 40 00  ; tile $3b
                hex 08 10 20 40 20 10 08 00  ; tile $3c
                hex 00 00 fe 00 00 fe 00 00  ; tile $3d
                hex 40 20 10 08 10 20 40 00  ; tile $3e
                hex 7c 82 02 0c 10 10 00 10  ; tile $3f
                hex 7c 82 ba ba b4 80 7e 00  ; tile $40
                hex 7c 82 82 fe 82 82 82 00  ; tile $41
                hex fc 42 42 7c 42 42 fc 00  ; tile $42
                hex 7e 80 80 80 80 80 7e 00  ; tile $43
                hex f8 84 82 82 82 84 f8 00  ; tile $44
                hex fe 80 80 fe 80 80 fe 00  ; tile $45
                hex fe 80 80 fe 80 80 80 00  ; tile $46
                hex 7e 80 80 9e 82 82 7e 00  ; tile $47
                hex 82 82 82 fe 82 82 82 00  ; tile $48
                hex 38 10 10 10 10 10 38 00  ; tile $49
                hex 04 04 04 04 04 44 38 00  ; tile $4a
                hex 44 48 50 60 50 48 44 00  ; tile $4b
                hex 80 80 80 80 80 80 fe 00  ; tile $4c
                hex 82 c6 aa 92 82 82 82 00  ; tile $4d
                hex 82 c2 a2 92 8a 86 82 00  ; tile $4e
                hex 7c 82 82 82 82 82 7c 00  ; tile $4f
                hex fc 82 82 fc 80 80 80 00  ; tile $50
                hex 7c 82 82 92 8a 86 7e 00  ; tile $51
                hex fc 82 82 fc 88 84 82 00  ; tile $52
                hex 7e 80 80 7c 02 02 fc 00  ; tile $53
                hex fe 10 10 10 10 10 10 00  ; tile $54
                hex 82 82 82 82 82 82 7c 00  ; tile $55
                hex 82 82 82 82 44 28 10 00  ; tile $56
                hex 82 82 82 92 aa c6 82 00  ; tile $57
                hex 82 44 28 10 28 44 82 00  ; tile $58
                hex 82 44 28 10 10 10 10 00  ; tile $59
                hex fe 04 08 10 20 40 fe 00  ; tile $5a
                hex 38 20 20 20 20 20 38 00  ; tile $5b
                hex 80 40 20 10 08 04 02 00  ; tile $5c
                hex 38 08 08 08 08 08 38 00  ; tile $5d
                hex 10 28 44 00 00 00 00 00  ; tile $5e
                hex 00 00 00 00 00 00 fe 00  ; tile $5f
                hex 10 08 04 00 00 00 00 00  ; tile $60
                hex 00 00 78 04 3c 4c 34 00  ; tile $61
                hex 40 40 78 44 44 44 78 00  ; tile $62
                hex 00 00 3c 40 40 40 3c 00  ; tile $63
                hex 04 04 3c 44 44 44 3c 00  ; tile $64
                hex 00 00 38 44 78 40 3c 00  ; tile $65
                hex 18 24 20 78 20 20 20 00  ; tile $66
                hex 00 00 34 4c 44 3c 04 78  ; tile $67
                hex 40 40 58 64 44 44 44 00  ; tile $68
                hex 00 10 00 10 10 10 10 00  ; tile $69
                hex 00 08 00 08 08 08 48 30  ; tile $6a
                hex 40 40 48 50 60 50 48 00  ; tile $6b
                hex 30 10 10 10 10 10 10 00  ; tile $6c
                hex 00 00 b6 da 92 92 92 00  ; tile $6d
                hex 00 00 58 64 44 44 44 00  ; tile $6e
                hex 00 00 38 44 44 44 38 00  ; tile $6f
                hex 00 00 58 64 44 78 40 40  ; tile $70
                hex 00 00 34 4c 44 3c 04 04  ; tile $71
                hex 00 00 5c 60 40 40 40 00  ; tile $72
                hex 00 00 3c 40 38 04 78 00  ; tile $73
                hex 00 20 78 20 20 28 10 00  ; tile $74
                hex 00 00 44 44 44 4c 34 00  ; tile $75
                hex 00 00 44 44 28 28 10 00  ; tile $76
                hex 00 00 54 54 54 54 28 00  ; tile $77
                hex 00 00 44 28 10 28 44 00  ; tile $78
                hex 00 00 44 44 44 3c 04 78  ; tile $79
                hex 00 00 7c 08 10 20 7c 00  ; tile $7a
                hex 0c 10 10 60 10 10 0c 00  ; tile $7b
                hex 10 10 10 00 10 10 10 00  ; tile $7c
                hex 60 10 10 0c 10 10 60 00  ; tile $7d
                hex 64 98 00 00 00 00 00 00  ; tile $7e
                ;
                hex 04 04 24 44 fc 40 20 00  ; tile $7f (return symbol; needed in keyboard)
                hex ff ff ff ff ff ff ff ff  ; tile $80 (solid block)
                hex 00 00 ff ff ff 00 00 00  ; tile $81 (horizontal bar)
                hex 10 38 54 10 10 10 10 00  ; tile $82 (up arrow)
                hex 10 10 10 10 54 38 10 00  ; tile $83 (down arrow)
                hex 00 20 40 fe 40 20 00 00  ; tile $84 (left arrow)
                hex 00 08 04 fe 04 08 00 00  ; tile $85 (right arrow)
pt_data_end

macro nt_addr _nt, _y, _x
                ; output name table address ($2000-$27bf), high byte first
                dh $2000+(_nt*$400)+(_y*$20)+(_x)
                dl $2000+(_nt*$400)+(_y*$20)+(_x)
endm

strings         ; each string: PPU address high/low, characters, null terminator
                ; address high = 0 ends all strings
                ;
                nt_addr 0, 2, 7
                db "Qalle's Brainfuck", 0
                nt_addr 0, 4, 11
                db "edit mode", 0
                nt_addr 0, 6, 12
                db "Program:", 0
                nt_addr 0, 18, 4
                db tile_uarr, "=+ ", tile_darr, "=-  "
                db tile_larr, "=< ", tile_rarr, "=>  "
                db "B=[ A=]", 0
                nt_addr 0, 20, 9
                db "select+B=,", 0
                nt_addr 0, 21, 9
                db "select+A=.", 0
                nt_addr 0, 22, 12
                db "start=backspace", 0
                nt_addr 0, 23, 5
                db "select+start=run", 0
                ;
                nt_addr 1, 2, 7
                db "Qalle's Brainfuck", 0
                nt_addr 1, 4, 11
                db "run mode", 0
                nt_addr 1, 6, 12
                db "Output:", 0
                nt_addr 1, 18, 9
                db "Input (", tile_uarr, tile_darr, tile_larr, tile_rarr, "A):", 0
                nt_addr 1, 27, 9
                db "B=to edit mode", 0
                ;
                db 0  ; end of all strings

                if $ - strings > 256
                    error "out of string space"
                endif

                ; VRAM addresses of horizontal bars (above/below Brainfuck code area in both
                ; name tables)
horz_bars_hi    dh $20e0, $2200, $24e0, $2600  ; high bytes
horz_bars_lo    dl $20e0, $2200, $24e0, $2600  ; low  bytes

; --- Main loop - common --------------------------------------------------------------------------

main_loop       asl nmi_done            ; to avoid missing the flag being set by NMI routine,
                bcs +                   ; clear and read it using a single instruction
                ;
                lda program_mode        ; not first round after VBlank;
                cmp #mode_run           ; only run mode-specific stuff if in run mode
                bne main_loop
                jsr ml_run
                jmp main_loop
                ;
+               jsr once_per_frame      ; first round after VBlank; run once-per-frame stuff
                jmp main_loop

once_per_frame  ; stuff that's done only once per frame

                lda pad_status          ; store previous joypad status
                sta prev_pad_status

                lda #1                  ; read first joypad or Famicom expansion port controller
                sta joypad1             ; see https://www.nesdev.org/wiki/Controller_reading_code
                sta pad_status
                lsr a
                sta joypad1
-               lda joypad1
                and #%00000011
                cmp #1
                rol pad_status
                bcc -

                ldx #cursor_tile1       ; set cursor tile according to frame counter
                lda frame_counter
                and #(1<<blink_rate)
                beq +
                ldx #cursor_tile2
+               stx sprite_data+0+1

                inc frame_counter       ; advance frame counter

                ; jump to one sub depending on program mode
                ; note: RTS in the subs below will act like RTS in this sub
                ; see https://www.nesdev.org/wiki/Jump_table
                ; and https://www.nesdev.org/wiki/RTS_Trick
                ;
                ldx program_mode        ; push target address minus one, high byte first
                lda jump_table_hi,x
                pha
                lda jump_table_lo,x
                pha
                rts                     ; pull address, low byte first; jump to address plus one

jump_table_hi   dh ml_edit     -1       ; jump table - high bytes
                dh ml_prep_run1-1
                dh ml_prep_run2-1
                dh ml_run      -1
                dh ml_input    -1
                dh ml_ended    -1
                ;
jump_table_lo   dl ml_edit     -1       ; jump table - low bytes
                dl ml_prep_run1-1
                dl ml_prep_run2-1
                dl ml_run      -1
                dl ml_input    -1
                dl ml_ended    -1

; --- Main loop - editing Brainfuck program -------------------------------------------------------

ml_edit         lda pad_status          ; react to buttons
                cmp prev_pad_status     ; skip if joypad status not changed
                beq char_entry_end
                ;
                cmp #(pad_sel|pad_start)
                beq run_program
                ;
                cmp #pad_start
                beq del_last_char       ; backspace
                ;
                ldx #(bf_instrs_end-bf_instrs-1)
-               lda edit_buttons,x      ; enter instruction if corresponding button pressed
                cmp pad_status
                beq enter_instr
                dex
                bpl -

char_entry_end  lda program_len         ; update coordinates of input cursor sprite
                jmp upd_io_cursor       ; ends with RTS

run_program     inc program_mode        ; switch to mode_prepare_run1
                rts                     ; (later to mode_prepare_run2 & mode_run)

del_last_char   ldy program_len         ; if there's >= 1 instruction...
                beq char_entry_end
                ;
                ldy program_len
                dey                     ; delete last instruction, tell NMI routine to redraw it
                lda #$00
                sta bf_program,y
                sta vram_buf_value
                sty program_len
                sty vram_buf_adrlo
                lda #$21
                sta vram_buf_adrhi      ; set this byte last to avoid race condition
                ;
                bne char_entry_end      ; unconditional

enter_instr     ldy program_len         ; if program is < $ff characters...
                cpy #$ff
                beq char_entry_end
                ;
                lda bf_instrs,x         ; add instruction specified by X, tell NMI routine to
                sta bf_program,y        ; draw it
                sta vram_buf_value
                sty vram_buf_adrlo
                inc program_len
                lda #$21
                sta vram_buf_adrhi      ; set this byte last to avoid race condition
                ;
                bne char_entry_end      ; unconditional

                ; Brainfuck instructions and corresponding buttons in edit mode
edit_buttons    db pad_u, pad_d, pad_l, pad_r, pad_b, pad_a, pad_sel|pad_b, pad_sel|pad_a
bf_instrs       db "+",   "-",   "<",   ">",   "[",   "]",   ",",           "."
bf_instrs_end

; --- Main loop - prepare to run, part 1/2 --------------------------------------------------------

ml_prep_run1    jsr find_brackets       ; for each bracket, get index of corresponding bracket
                bcs +
                inc program_mode        ; brackets valid; proceed to mode_prep_run2
                rts
+               dec program_mode        ; error in brackets; return to mode_edit
                rts

find_brackets   ; for each bracket in Brainfuck program, store index of corresponding bracket in
                ; another array
                ; in: bf_program (array), program_len
                ; out: brackets (array), carry (clear = no error, set = error)
                ; trashes: temp, bottom half of stack ($0100-$017f)
                ; note: an interrupt which uses stack must never fire during this sub
                ;
                tsx                     ; original stack pointer -> temp
                stx temp
                ldx #$7f                ; use bottom half of stack for currently open brackets
                txs
                ldy #$ff                ; Y = current program index (preincremented)
                ;
-               iny                     ; next instruction
                cpy program_len
                bne +
                ;
                tsx                     ; end of Brainfuck program
                inx
                bpl bracket_error       ; missing "]" (SP != $7f)
                clc
                bcc bracket_exit        ; brackets valid
                ;
+               lda bf_program,y
                cmp #$5b                ; "["
                bne +
                tsx
                bmi bracket_error       ; maximum number of "["s already open (SP = $ff)
                tya                     ; push current index
                pha
                jmp -
                ;
+               cmp #$5d                ; "]"
                bne -
                pla                     ; pull corresponding index
                tsx
                bmi bracket_error       ; missing "[" (SP = $80)
                sta brackets,y          ; store corresponding index here
                tax                     ; store this index at corresponding index
                tya
                sta brackets,x
                jmp -
                ;
bracket_error   sec
bracket_exit    ldx temp                ; restore original stack pointer
                txs
                rts

; --- Main loop - prepare to run, part 2/2 --------------------------------------------------------

ml_prep_run2    lda #>bf_ram            ; set high byte of BF RAM pointer
                sta pointer+1

                ldx #$ff                ; hide edit cursor, reset Brainfuck program counter
                stx sprite_data+0+0
                stx bf_pc

                inx                     ; reset low byte of BF RAM pointer, output length,
                stx pointer+0           ; keyboard cursor
                stx output_len
                stx keyb_x
                stx keyb_y

                txa                     ; clear Brainfuck RAM
-               sta bf_ram+0,x
                sta bf_ram+$100,x
                sta bf_ram+$200,x
                sta bf_ram+$300,x
                inx
                bne -

                lda #%10000001          ; show run mode name table
                sta ppu_ctrl_copy

                inc program_mode        ; switch to mode_run

                rts

; --- Main loop - Brainfuck program running -------------------------------------------------------

; the only part of main loop that's run as frequently as possible instead of once per frame

ml_run          lda pad_status          ; stop program if B pressed
                cmp #pad_b
                bne +
                jmp to_edit_mode        ; ends with RTS

+               lda vram_buf_adrhi      ; wait until NMI routine has flushed VRAM buffer
                beq +
                rts

+               ldx bf_pc               ; incremented PC -> X; check for end of program
                inx
                cpx program_len
                beq to_ended_mode       ; switch to "program ended" mode (ends with RTS)

                lda bf_program,x        ; instruction -> A
                ldy #0                  ; always 0; only used in indirect addressing

                ; process current instruction
                ;
                cmp #$2d                ; "-"
                beq dec_value
                cmp #$2b                ; "+"
                beq inc_value
                cmp #$3c                ; "<"
                beq dec_ptr
                cmp #$3e                ; ">"
                beq inc_ptr
                cmp #$5b                ; "["
                beq start_loop
                cmp #$5d                ; "]"
                beq end_loop
                cmp #$2e                ; "."
                beq output
                jmp input               ; ","
                ;
instr_done      stx bf_pc               ; store new program counter
                lda output_len          ; update coordinates of output cursor sprite
                jmp upd_io_cursor       ; ends with RTS

to_ended_mode   lda #mode_ended         ; switch to "program ended" mode
                sta program_mode
                lda #$ff                ; hide cursor
                sta sprite_data+0+0
                rts

dec_value       lda (pointer),y         ; decrement RAM value
                sec
                sbc #1
                sta (pointer),y
                jmp instr_done

inc_value       lda (pointer),y         ; increment RAM value
                clc
                adc #1
                sta (pointer),y
                jmp instr_done

dec_ptr         dec pointer+0           ; decrement RAM pointer
                lda pointer+0
                cmp #$ff
                bne instr_done
                dec pointer+1
                lda pointer+1
                cmp #$03
                bne instr_done
                lda #$07
                sta pointer+1
                bpl instr_done          ; unconditional

inc_ptr         inc pointer+0           ; increment RAM pointer
                bne instr_done
                inc pointer+1
                lda pointer+1
                cmp #$08
                bne instr_done
                lda #$04
                sta pointer+1
                bpl instr_done          ; unconditional

start_loop      lda (pointer),y         ; jump to corresponding "]" if RAM value is 0
                bne instr_done
                lda brackets,x
                tax
                jmp instr_done

end_loop        lda (pointer),y         ; jump to corresponding "[" if RAM value is not 0
                beq instr_done
                lda brackets,x
                tax
                jmp instr_done

output          lda (pointer),y         ; if newline ($0a)...
                cmp #$0a
                bne +
                ;
                lda output_len          ; move output cursor to start of next line
                adc #(32-1)             ; carry is always set
                and #%11100000
                sta output_len
                jmp ++
                ;
+               sta vram_buf_value      ; otherwise output value from RAM via NMI routine
                lda output_len
                sta vram_buf_adrlo
                lda #$25
                sta vram_buf_adrhi      ; set this byte last to avoid race condition
                inc output_len
                ;
++              beq to_ended_mode       ; if $100 characters printed, end program (ends with RTS)
                jmp instr_done

input           inc program_mode        ; input value to RAM (switch to mode_input)
                jmp instr_done

; --- Main loop - Brainfuck program waiting for input ---------------------------------------------

ml_input        lda prev_pad_status     ; ignore buttons if anything was pressed on last frame
                bne upd_keyb_cursor     ; update cursor sprite coordinates (ends with RTS)

                lda pad_status          ; react to buttons
                lsr a
                bcs keyb_right          ; pad right
                lsr a
                bcs keyb_left           ; pad left
                lsr a
                bcs keyb_down           ; pad down
                lsr a
                bcs keyb_up             ; pad up
                lsr a
                lsr a
                lsr a
                bcs to_edit_mode        ; B; back to edit mode (ends with RTS)
                bne keyb_input          ; A
                ;
                beq upd_keyb_cursor     ; unconditional, ends with RTS

keyb_right      ldx keyb_x
                inx
                bpl +                   ; unconditional
keyb_left       ldx keyb_x
                dex
+               txa
                and #%00001111
                sta keyb_x
                bpl upd_keyb_cursor     ; unconditional, ends with RTS
                ;
keyb_down       ldx keyb_y
                inx
                cpx #6
                bne +
                ldx #0
                beq +                   ; unconditional
keyb_up         ldx keyb_y
                dex
                bpl +
                ldx #(6-1)
+               stx keyb_y
                jmp upd_keyb_cursor     ; ends with RTS
                ;
keyb_input      lda keyb_y              ; store character at cursor to Brainfuck RAM
                asl a
                asl a
                asl a
                asl a
                adc #$20
                ora keyb_x
                ;
                cmp #$7f                ; return symbol ($7f) as newline ($0a)
                bne +
                lda #$0a
                ;
+               ldy #0
                sta (pointer),y
                ;
                dec program_mode        ; switch to mode_run
                ;
                rts

upd_keyb_cursor lda keyb_y              ; update coordinates of keyboard cursor sprite
                asl a
                asl a
                asl a
                adc #(20*8-1)           ; carry is always clear
                sta sprite_data+0+0
                ;
                lda keyb_x
                asl a
                asl a
                asl a
                adc #(8*8)              ; carry is always clear
                sta sprite_data+0+3
                ;
                rts

; --- Main loop - Brainfuck program ended ---------------------------------------------------------

ml_ended        lda pad_status          ; if B pressed...
                and #pad_b
                bne to_edit_mode        ; switch to edit mode (ends with RTS)
                rts

; --- Main loop - subs used in more than one program mode -----------------------------------------

to_edit_mode    lda #mode_edit          ; switch to edit mode (from run/input/ended mode)
                sta program_mode
                lda #%10000000          ; show edit mode name table
                sta ppu_ctrl_copy
                rts

upd_io_cursor   pha                     ; update coordinates of input/output cursor sprite
                and #%11100000          ; in: A = input/output length
                lsr a
                lsr a
                adc #(8*8-1)
                sta sprite_data+0+0
                ;
                pla
                asl a
                asl a
                asl a
                sta sprite_data+0+3
                ;
                rts

; --- Interrupt routines --------------------------------------------------------------------------

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; clear ppu_scroll/ppu_addr latch
                ;
                lda #$00                ; do OAM DMA
                sta oam_addr
                lda #>sprite_data
                sta oam_dma

                ldy vram_buf_adrhi      ; flush VRAM buffer if address != $00xx
                beq buf_flush_done
                ;
                lda vram_buf_adrlo
                jsr set_ppu_addr        ; Y, A -> address
                lda vram_buf_value
                sta ppu_data
                ;
                lda #$00
                sta vram_buf_adrhi

buf_flush_done  lda program_mode        ; if in one of "prepare to run" modes,
                ldy #$25                ; fill top or bottom half of output area
                ;                       ; (write byte $00 $80 times to VRAM $2500 or $2580)
                cmp #mode_prep_run1
                bne +
                lda #$00
                beq ++                  ; unconditional
                ;
+               cmp #mode_prep_run2
                bne clear_done
                lda #$80
                ;
++              jsr set_ppu_addr        ; Y, A -> address
                lda #$00
                ldx #$40
-               sta ppu_data
                sta ppu_data
                dex
                bne -

clear_done      jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                lda #%10000000          ; set flag to let once-per-frame stuff run
                sta nmi_done            ; note: other negative values won't do

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti

; --- Subs involving PPU registers (used in initialization & NMI routine) -------------------------

set_ppu_addr    sty ppu_addr            ; set PPU address from Y & A
                sta ppu_addr
                rts

set_ppu_regs    lda #$00                ; reset PPU scroll
                sta ppu_scroll
                sta ppu_scroll
                lda ppu_ctrl_copy       ; set ppu_ctrl from copy
                sta ppu_ctrl
                lda #%00011110          ; show background & sprites
                sta ppu_mask
                rts

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; note: IRQ unused
