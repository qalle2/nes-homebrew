; Qalle's Brainfuck (NES, ASM6)
;
; IMPORTANT NOTE: This program is under construction - only the edit mode is implemented.
; Get an old version (before May 2022) from Github if necessary.

; --- Constants -----------------------------------------------------------------------------------

; note: "VRAM buffer" = what to write to PPU on next VBlank

; RAM
pointer         equ $00    ; memory pointer (2 bytes)
program_mode    equ $02    ; 0 = editing, 1 = running, 2 = asking for input
run_main_loop   equ $03    ; main loop allowed to run? (MSB: 0=no, 1=yes)
ppu_ctrl_copy   equ $04    ; copy of ppu_ctrl
frame_counter   equ $05    ; for blinking cursors
pad_status      equ $06    ; joypad status
prev_pad_status equ $07    ; previous joypad status
vram_buf_adrhi  equ $08    ; VRAM buffer - high byte of address ($00 = buffer is empty)
vram_buf_adrlo  equ $09    ; VRAM buffer - low  byte of address
vram_buf_value  equ $0a    ; VRAM buffer - value
program_len     equ $0b    ; length of Brainfuck program (0-254)
bf_pc           equ $0c    ; program counter (address being run) of Brainfuck program
bf_ram_addr     equ $0d    ; RAM address of Brainfuck program
output_len      equ $0e    ; number of characters printed by the Brainfuck program (0-255)
temp            equ $0f    ; a temporary variable
bf_program      equ $0200  ; Brainfuck program ($100 bytes)
brackets        equ $0300  ; target addresses of "[" and "]" ($100 bytes)
bf_ram          equ $0400  ; RAM of Brainfuck program ($100 bytes)
sprite_data     equ $0500  ; OAM page ($100 bytes)

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
pad_select      equ 1<<5
pad_start       equ 1<<4
pad_up          equ 1<<3
pad_down        equ 1<<2
pad_left        equ 1<<1
pad_right       equ 1<<0

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

; misc
blink_rate      equ 4    ; cursor blink rate (0 = fastest, 7 = slowest)

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
                db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
                pad $0010, $00           ; unused

; --- Initialization ------------------------------------------------------------------------------

                base $c000              ; start of PRG ROM
                pad $f000, $ff          ; last 4 KiB of CPU memory space

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

                ldx #0                  ; clear zero page and Brainfuck code; hide all sprites
-               lda #$00
                sta $00,x
                sta bf_program,x
                lda #$ff
                sta sprite_data,x
                inx
                bne -

                ldx #(3*4-1)            ; initialize used sprites
-               lda init_spr_data,x
                sta sprite_data,x
                dex
                bpl -

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$3f                ; set palette (while still in VBlank; 8*4 bytes)
                lda #$00
                jsr set_ppu_addr
                ldy #8
--              ldx #(4-1)
-               lda palette,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

                ldy #$00                ; prepare to copy pattern table data
                tya
                jsr set_ppu_addr        ; Y, A -> address
                ;
-               sta ppu_data            ; fill tiles $00-$1f (VRAM $0000-$01ff) with $00
                sta ppu_data            ; Y is still 0
                iny
                bne -
                ;
                lda #>pt_data           ; set pointer to pattern table data array
                sta pointer+1           ; (must be at $xx00); Y is still 0
                sty pointer+0
                ;
--              lda (pointer),y         ; copy array to VRAM
                sta ppu_data            ; after every   8 bytes, write 8 zeroes (2nd bitplane)
                iny                     ; after every 256 bytes, increment high byte of pointer
                tya                     ; some garbage will be copied to the end
                and #%00000111
                bne +
                ldx #8
-               sta ppu_data
                dex
                bne -
+               tya
                bne --
                inc pointer+1
                lda pointer+1
                cmp #(>pt_data+4)
                bne --

                ldy #$20                ; clear name & attribute tables 0 & 1 (VRAM $2000-$27ff,
                lda #$00                ; 8*$100 bytes)
                jsr set_ppu_addr        ; Y, A -> address
                ldy #8
--              tax
-               sta ppu_data
                inx
                bne -
                dey
                bne --

                ldx #(str_title-strings)  ; NT0 (edit mode) - strings above Brainfuck code area
                jsr print_string
                ldx #(str_help1-strings)
                jsr print_string
                ldx #(str_help2-strings)
                jsr print_string
                ldx #(str_help3-strings)
                jsr print_string
                ;
                ldy #$21                ; NT0 - horizontal bar above Brainfuck code area
                lda #$e0
                jsr set_ppu_addr        ; Y, A -> address
                ldy #32
                lda #tile_hbar
                jsr fill_vram           ; write A Y times
                ;
                ldy #$23                ; NT0 - horizontal bar below Brainfuck code area
                lda #$00
                jsr set_ppu_addr
                ldy #32
                lda #tile_hbar
                jsr fill_vram

                ldx #(str_output-strings)  ; NT1 (run mode) - string above program output area
                jsr print_string
                ;
                ldy #$24                ; NT1 - horizontal bar above program output area
                lda #$e0
                jsr set_ppu_addr
                ldy #32
                lda #tile_hbar
                jsr fill_vram
                ;
                ldy #$26                ; NT1 - horizontal bar below program output area
                lda #$00
                jsr set_ppu_addr
                ldy #32
                lda #tile_hbar
                jsr fill_vram
                ;
                ldy #$26                ; NT1 - virtual keyboard
                lda #$58
                jsr set_ppu_addr
                ldx #32                 ; X = character code
-               txa                     ; print 16 spaces before start of each line
                and #%00001111
                bne +
                ldy #16
                lda #$20
                jsr fill_vram
+               stx ppu_data
                inx
                bpl -

                jsr wait_vbl_start      ; wait until next VBlank starts

                lda #%10000000          ; enable NMI, show name table 0
                sta ppu_ctrl_copy
                jsr set_ppu_regs

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

init_spr_data   ; initial sprite data (Y, tile, attributes, X)
                db 255, '_',        %00000000, 255  ; #0: edit mode - cursor
                db 255, $00,        %00000001, 255  ; #1: run mode - selected char in background color
                db 255, tile_block, %00000000, 255  ; #2: run mode - block filled with foreground color

; --- Main loop - common --------------------------------------------------------------------------

main_loop       bit run_main_loop       ; wait until NMI routine has set flag
                bpl main_loop
                ;
                lsr run_main_loop       ; clear flag

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

                inc frame_counter       ; advance frame counter

                lda program_mode        ; continue according to program mode
                beq main_loop_edit
                jmp main_loop_run

; --- Main loop - edit mode -----------------------------------------------------------------------

main_loop_edit  lda pad_status          ; react to buttons
                cmp prev_pad_status     ; skip if joypad status not changed
                beq char_entry_end
                ;
                cmp #(pad_select|pad_start)
                bne +                   ; if "run" pressed, switch to run mode
                jmp to_run_mode
                ;
+               cmp #pad_start          ; if backspace pressed and there's >= 1 instruction...
                bne +
                ldy program_len
                beq char_entry_end
                ;
                dey                     ; delete last instruction, tell NMI routine to redraw it
                lda #$00
                sta bf_program,y
                sta vram_buf_value
                sty program_len
                sty vram_buf_adrlo
                lda #$22
                sta vram_buf_adrhi
                jmp char_entry_end
                ;
+               ldx #(bf_instrs_end-bf_instrs-1)
-               lda edit_buttons,x      ; if Brainfuck instruction entered and there's < 255
                cmp pad_status          ; instructions...
                bne +
                ldy program_len
                cpy #255
                beq char_entry_end
                ;
                lda bf_instrs,x         ; add instruction, tell NMI routine to redraw it
                sta bf_program,y
                sta vram_buf_value
                sty vram_buf_adrlo
                inc program_len
                lda #$22
                sta vram_buf_adrhi
                jmp char_entry_end
                ;
+               dex
                bpl -

char_entry_end  lda program_len         ; cursor sprite coordinates
                and #%11100000          ; bits of program_len: YYYXXXXX
                lsr a
                lsr a
                adc #(16*8-1)
                sta sprite_data+0+0     ; bits of Y position: 00YYY000
                ;
                lda program_len
                asl a
                asl a
                asl a
                sta sprite_data+0+3     ; bits of X position: XXXXX000

                jmp main_loop

to_run_mode     lda program_len         ; exit if Brainfuck program is empty
                bne +
                jmp main_loop

+               ; for each bracket in Brainfuck program, store index of corresponding bracket in
                ; another array
                ;
                ldy #0                  ; Y = program index, X = multipurpose,
                ldx #$ff                ; stack = currently open brackets
                txs
                ;
-               lda bf_program,y        ; "[": push index
                cmp #'['
                bne +
                tya
                pha
                jmp ++
                ;
+               cmp #']'                ; "]": pull corresponding index; exit on stack underflow
                bne ++                  ; (missing "["); store corresponding index here; store
                pla                     ; this index at corresponding index
                tsx
                beq brackets_end
                sta brackets,y
                tax
                tya
                sta brackets,x
                ;
++              iny
                cpy #program_len
                bne -
                ldy #$ff                ; signal no stack underflow with Y = 255
                ;
brackets_end    tsx                     ; stack pointer -> X, reset stack pointer
                stx temp
                ldx #$ff
                txs
                ldx temp

                cpy #$ff                ; if Y != 255, missing "["
                bne +
                cpx #$ff                ; else if X != 255, missing "]"
                bne +
                ;
                lda #%10000001          ; show run mode name table
                sta ppu_ctrl_copy
                ldx #255                ; hide edit cursor
                stx sprite_data+0+0
                inx                     ; reset Brainfuck program counter, RAM address and
                stx bf_pc               ; output length
                stx bf_ram_addr
                stx output_len
                txa
-               sta bf_ram,x            ; clear Brainfuck RAM
                inx
                bne -
                inc program_mode        ; switch to run mode
                ;
+               jmp main_loop

                ; Brainfuck instructions and corresponding buttons in edit mode
edit_buttons    db pad_up, pad_down
                db pad_left, pad_right
                db pad_b, pad_a
                db pad_select|pad_b, pad_select|pad_a
bf_instrs       db "+", "-"
                db "<", ">"
                db "[", "]"
                db ",", "."
bf_instrs_end

; --- Main loop - run mode ------------------------------------------------------------------------

main_loop_run   ; process current instruction
                ;
                ldy bf_pc
                ldx bf_ram_addr
                lda bf_program,y
                ;
                cmp #$2d                ; "-": decrement RAM value
                bne +
                dec bf_ram,x
                jmp instr_done
                ;
+               cmp #$2b                ; "+": increment RAM value
                bne +
                inc bf_ram,x
                jmp instr_done
                ;
+               cmp #$3c                ; "<": decrement RAM pointer
                bne +
                dex
                jmp instr_done
                ;
+               cmp #$3e                ; ">": increment RAM pointer
                bne +
                inx
                jmp instr_done
                ;
+               cmp #$5b                ; "[": jump to corresponding "]" if RAM value is 0
                bne +
                lda bf_ram,x
                bne +
                lda brackets,y
                tay
                jmp instr_done
                ;
+               cmp #$5d                ; "]": jump to corresponding "[" if RAM value is not 0
                bne +
                lda bf_ram,x
                beq +
                lda brackets,y
                tay
                jmp instr_done
                ;
+               cmp #$2e                ; ".": tell NMI routine to output RAM value
                bne +
                lda bf_ram,x
                sta vram_buf_value
                lda output_len
                sta vram_buf_adrlo
                lda #$25
                sta vram_buf_adrhi
                inc output_len
                ;
+               cmp #$2c                ; ",": input value to RAM (not yet implemented)
                bne instr_done
                ;
instr_done      iny                     ; advance program counter; store it & RAM pointer
                sty bf_pc
                stx bf_ram_addr
                cpy program_len         ; if program ended...
                bne +
                ;
                lda #%10000000          ; show run mode name table, switch to run mode
                sta ppu_ctrl_copy
                dec program_mode
                ;
+               jmp main_loop

; --- NMI routine ---------------------------------------------------------------------------------

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                bit ppu_status          ; clear ppu_scroll/ppu_addr latch
                lda #$00                ; do OAM DMA
                sta oam_addr
                lda #>sprite_data
                sta oam_dma

                lda vram_buf_adrhi      ; flush VRAM buffer if address != $00xx
                beq +
                sta ppu_addr
                lda vram_buf_adrlo
                sta ppu_addr
                lda vram_buf_value
                sta ppu_data
                lda #$00
                sta vram_buf_adrhi

+               ldy #$3f                ; set 2nd color of 1st sprite subpalette according to
                lda #$11                ; frame counter
                jsr set_ppu_addr
                ldx #color_bg
                lda frame_counter
                and #(1<<blink_rate)
                beq +
                ldx #color_fg
+               stx ppu_data

                lda program_mode        ; continue according to program mode
                beq nmi_edit_mode
                jmp nmi_run_mode

nmi_edit_mode
                jmp nmi_end

nmi_run_mode

nmi_end         jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

                sec                     ; set flag to let main loop run once
                ror run_main_loop

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti

; --- Subs & arrays used in many places -----------------------------------------------------------

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

print_string    lda strings,x           ; print null-terminated string from array; X = offset
                sta ppu_addr
                inx
                lda strings,x
                sta ppu_addr
                inx
-               lda strings,x
                beq +
                sta ppu_data
                inx
                bne -
+               rts

macro nt_addr _nt, _y, _x
                ; output name table address ($2000-$27bf), high byte first
                dh $2000+_nt*$400+_y*$20+_x
                dl $2000+_nt*$400+_y*$20+_x
endm

strings         ; each string: PPU address high/low, characters, null terminator
                ;
str_title       nt_addr 0, 3, 7
                db "Qalle's Brainfuck", 0
str_help1       nt_addr 0, 6, 4
                db tile_uarr, "=+ ", tile_darr, "=- ", tile_larr, "=< ", tile_rarr, "=> "
                db "B=[ A=]", 0
str_help2       nt_addr 0, 8, 5
                db "select+B=, select+A=.", 0
str_help3       nt_addr 0, 10, 2
                db "start=BkSp select+start=run", 0
                ;
str_output      nt_addr 1, 6, 12
                db "Output:", 0
str_running     nt_addr 0,0,0
                db "Running... (B=end)", 0
str_input       nt_addr 0,0,0
                db "Character? (", tile_uarr, tile_darr, tile_larr, tile_rarr, " A=OK B=end)", 0
str_finish      nt_addr 0,0,0
                db "Finished. Press B.", 0

                if $ - strings > 256
                    error "out of string space"
                endif

                ; pattern table data
                ; 8 bytes = 1st bitplane of 1 tile; 2nd bitplanes are all zeroes
                ; tiles $20-$7e are ASCII
                ;
                align $100, $ff
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

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; note: IRQ unused
