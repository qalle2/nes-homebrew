; Qalle's Brainfuck (NES, ASM6)
;
; IMPORTANT NOTE: This program is undergoing a rewrite. Get an old version (before May 2022) from
; Github if you need more functionality.

; --- Constants -----------------------------------------------------------------------------------

; note: "VRAM buffer" = what to write to PPU on next VBlank

; RAM
pointer         equ $00    ; memory pointer (2 bytes)
program_mode    equ $02    ; 0 = editing, 1 = running, 2 = waiting for input, 3 = finished
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
keyb_cursor_x   equ $0f    ; cursor X position on virtual keyboard (0-15)
keyb_cursor_y   equ $10    ; cursor Y position on virtual keyboard (0-5)
temp            equ $11    ; a temporary variable
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
blink_rate      equ 4           ; cursor blink rate (0 = fastest, 7 = slowest)
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

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$3f                ; set up palette (while still in VBlank; 8*4 bytes)
                lda #$00
                jsr set_ppu_addr
                ;
                ldy #8
--              ldx #(4-1)
-               lda palette,x
                sta ppu_data
                dex
                bpl -
                dey
                bne --

                ; set up pattern table 0 (PPU $0000-$0fff)
                ;
                ldy #$00                ; fill with $00
                tya
                jsr set_ppu_addr
                ;
                ldx #16
-               jsr fill_vram
                dex
                bne -
                ;
                lda #<pt_data           ; set source pointer
                sta pointer+0
                lda #>pt_data
                sta pointer+1
                ;
                ldy #$02                ; VRAM address $0200
                lda #$00
                jsr set_ppu_addr
                ;
                tax
                tay
                ;
--              lda (pointer,x)         ; copy data from array
                sta ppu_data
                iny                     ; after every 8 bytes, write 8 zeroes (2nd bitplane)
                cpy #8
                bne +
                lda #$00
                jsr fill_vram
                ;
+               inc pointer+0           ; increment and compare pointer
                bne +
                inc pointer+1
+               lda pointer+0
                cmp #<(pt_data+$330)    ; NOTE: ASM6 glitches for some reason if I use
                bne --                  ; "cmp #<(pt_data_end-pt_data)"
                lda pointer+1
                cmp #>(pt_data+$330)
                bne --

                ; set up name & attribute table 0 & 1 ($2000-$27ff; NT0 is for edit mode,
                ; NT1 is for run mode)
                ;
                ldy #$20                ; fill with $00
                lda #$00
                jsr set_ppu_addr
                ;
                ldy #8
--              tax
-               sta ppu_data
                inx
                bne -
                dey
                bne --
                ;
                ldx #$ff                ; copy strings
--              inx
                lda strings,x           ; VRAM address high (0 = end of all strings)
                beq strings_end
                sta ppu_addr
                inx
                lda strings,x           ; VRAM address low
                sta ppu_addr
-               inx
                lda strings,x           ; byte (0 = end of string)
                beq +
                sta ppu_data
                bne -                   ; unconditional
+               jmp --                  ; next string
                ;
strings_end     ldx #(4-1)              ; draw horizontal bars
-               ldy horz_bars_hi,x
                lda horz_bars_lo,x
                jsr set_ppu_addr
                ldy #32
                lda #tile_hbar
                jsr fill_vram
                dex
                bpl -
                ;
                ldy #$26                ; virtual keyboard in NT1
                lda #$58
                jsr set_ppu_addr
                ;
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

macro nt_addr _nt, _y, _x
                ; output name table address ($2000-$27bf), high byte first
                dh $2000+(_nt*$400)+(_y*$20)+(_x)
                dl $2000+(_nt*$400)+(_y*$20)+(_x)
endm

strings         ; each string: PPU address high/low, characters, null terminator
                ; address high = 0 ends all strings
                ;
                nt_addr 0, 3, 7
                db "Qalle's Brainfuck", 0
                nt_addr 0, 6, 12
                db "Program:", 0
                nt_addr 0, 18, 4
                db tile_uarr, "=+ ", tile_darr, "=- ", tile_larr, "=< ", tile_rarr, "=> "
                db "B=[ A=]", 0
                nt_addr 0, 20, 5
                db "select+B=, select+A=.", 0
                nt_addr 0, 22, 2
                db "start=BkSp select+start=run", 0
                ;
                nt_addr 1, 3, 7
                db "Qalle's Brainfuck", 0
                nt_addr 1, 6, 12
                db "Output:", 0
                nt_addr 1, 18, 13
                db "Input:", 0
                nt_addr 1, 26, 7
                db tile_uarr, tile_darr, tile_larr, tile_rarr, "A=input B=exit", 0
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

                ldx #cursor_tile1       ; set cursor tile according to frame counter
                lda frame_counter
                and #(1<<blink_rate)
                beq +
                ldx #cursor_tile2
+               stx sprite_data+0+1

                inc frame_counter       ; advance frame counter

                ldx program_mode        ; continue according to program mode
                beq main_loop_edit
                dex
                bne +
                jmp main_loop_run
+               dex
                bne +
                jmp main_loop_input
+               jmp main_loop_ended

; --- Main loop - editing program (mode 0) --------------------------------------------------------

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
                lda #$21
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
                lda #$21
                sta vram_buf_adrhi
                jmp char_entry_end
                ;
+               dex
                bpl -

char_entry_end  lda program_len         ; input cursor sprite coordinates
                and #%11100000          ; bits of program_len: YYYXXXXX
                lsr a
                lsr a
                adc #(8*8-1)
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

; --- Main loop - program running (mode 1) --------------------------------------------------------

main_loop_run   ; process current instruction
                ;
                ldy bf_pc
                cpy #program_len        ; do this here because no check done after ","
                beq program_ended
                ldx bf_ram_addr
                lda bf_program,y
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
                cmp #$2c                ; "," (glitches for some reason if optimized to BNE)
                beq input
                ;
instr_done      iny                     ; advance to next instruction
                sty bf_pc               ; store program counter & RAM pointer
                stx bf_ram_addr

                lda output_len          ; output cursor sprite coordinates
                and #%11100000          ; bits of output_len: YYYXXXXX
                lsr a
                lsr a
                adc #(8*8-1)
                sta sprite_data+0+0     ; bits of Y position: 00YYY000
                ;
                lda output_len
                asl a
                asl a
                asl a
                sta sprite_data+0+3     ; bits of X position: XXXXX000

                jmp main_loop

program_ended   lda #3                  ; switch to "program ended" mode
                sta program_mode
                lda #$ff                ; hide cursor
                sta sprite_data+0+0
                jmp main_loop

dec_value       dec bf_ram,x            ; decrement RAM value
                jmp instr_done

inc_value       inc bf_ram,x            ; increment RAM value
                jmp instr_done

dec_ptr         dex                     ; decrement RAM pointer
                jmp instr_done

inc_ptr         inx                     ; increment RAM pointer
                jmp instr_done

start_loop      lda bf_ram,x            ; jump to corresponding "]" if RAM value is 0
                bne instr_done
                lda brackets,y
                tay
                jmp instr_done

end_loop        lda bf_ram,x            ; jump to corresponding "[" if RAM value is not 0
                beq instr_done
                lda brackets,y
                tay
                jmp instr_done

output          lda bf_ram,x            ; output value from RAM (tell NMI routine to do it)
                sta vram_buf_value
                lda output_len
                sta vram_buf_adrlo
                lda #$25
                sta vram_buf_adrhi
                inc output_len
                jmp instr_done

input           lda #2                  ; input value to RAM (switch to input mode)
                sta program_mode
                lda #0
                sta keyb_cursor_x
                sta keyb_cursor_y
                inc bf_pc               ; advance program counter (we don't run instr_done)
                jmp main_loop

; --- Main loop - program waiting for input (mode 2) ----------------------------------------------

main_loop_input lda prev_pad_status     ; ignore buttons if anything was pressed on last frame
                bne inp_btns_done
                ;
                lda pad_status          ; react to buttons
                ;
                cmp #pad_right
                bne +
                inc keyb_cursor_x
                lda keyb_cursor_x
                and #%00001111
                sta keyb_cursor_x
                jmp inp_btns_done
                ;
+               cmp #pad_left
                bne inp_btns_done
                dec keyb_cursor_x
                lda keyb_cursor_x
                and #%00001111
                sta keyb_cursor_x

inp_btns_done   lda keyb_cursor_y       ; update cursor sprite coordinates
                asl a
                asl a
                asl a
                adc #(19*8-1)
                sta sprite_data+0+0
                ;
                lda keyb_cursor_x
                asl a
                asl a
                asl a
                adc #(8*8)
                sta sprite_data+0+3

                jmp main_loop

; --- Main loop - program ended (mode 3) ----------------------------------------------------------

main_loop_ended lda prev_pad_status     ; if nothing pressed on previous frame and B pressed on
                bne +                   ; this frame...
                lda pad_status
                and #pad_b
                beq +

                lda #0                  ; switch to edit mode
                sta program_mode
                lda #%10000000          ; show run mode name table
                sta ppu_ctrl_copy

+               jmp main_loop

; --- Interrupt routines --------------------------------------------------------------------------

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

+               jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

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

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; note: IRQ unused
