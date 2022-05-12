; Qalle's Brainfuck (NES, ASM6)
;
; IMPORTANT NOTE: This program is under construction and doesn't work at the moment. If necessary,
; take an old version (before May 2022) from Github.
;
; TODO: don't read VRAM, move stuff away from NMI routine

; --- Constants -----------------------------------------------------------------------------------

; RAM
pointer         equ $00    ; memory pointer (2 bytes)
program_mode    equ $02    ; 0 = editing, 1 = running, 2 = asking for input
pad_status      equ $03    ; joypad status
prev_pad_status equ $04    ; previous joypad status
program_len     equ $05    ; length of Brainfuck program (0-255)
outp_buffer     equ $06    ; 1 byte; screen output buffer
outp_buflen     equ $07    ; 0-1  ; length of screen output buffer
output_len      equ $08    ; number of characters printed by the Brainfuck program
keyboard_x      equ $09    ; virtual keyboard - X position (0-15)
keyboard_y      equ $0a    ; virtual keyboard - Y position (0-5)
input_char      equ $0b    ; virtual keyboard - character (32-127)
temp            equ $0c    ; a temporary variable
run_main_loop   equ $0d    ; MSB = main loop allowed to run? (0=no, 1=yes)
bf_program      equ $0200  ; Brainfuck program ($100 bytes)
brackets        equ $0400  ; target addresses of "[" and "]" ($100 bytes)
bf_ram          equ $0500  ; RAM of Brainfuck program ($100 bytes)
sprite_data     equ $0600  ; 256 bytes

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
oam_dma         equ $4014
snd_chn         equ $4015
joypad1         equ $4016
joypad2         equ $4017

; joypad button bitmasks
pad_a           equ 1<<7  ; A
pad_b           equ 1<<6  ; B
pad_se          equ 1<<5  ; select
pad_st          equ 1<<4  ; start
pad_u           equ 1<<3  ; up
pad_d           equ 1<<2  ; down
pad_l           equ 1<<1  ; left
pad_r           equ 1<<0  ; right

; colors
color_bg        equ $0f  ; background (black)
color_fg        equ $30  ; foreground (white)
color_unused    equ $25  ; unused (pink)

instr_cnt       equ 9    ; number of unique instructions

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
                db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
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

                ldy #$3f                ; set palette (while still in VBlank; 4*8 bytes)
                lda #$00
                jsr set_ppu_addr
                ldy #4
--              ldx #0
-               lda palette,x
                sta ppu_data
                inx
                cpx #8
                bne -
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

                lda #>run_mode          ; set high byte of pointer
                sta pointer+1

                jmp setup_edit_mode

palette         ; copied 4 times to PPU palette
                db color_bg, color_fg, color_unused, color_unused
                db color_bg, color_bg, color_unused, color_unused  ; hidden virtual keyboard
palette_end

init_spr_data   ; initial sprite data
                db 255, '_', %00000000, 255  ; #0: edit mode - cursor
                db 255, $00, %00000001, 255  ; #1: run mode - selected char in background color
                db 255, $8a, %00000000, 255  ; #2: run mode - block filled with foreground color

; --- Set up edit mode ----------------------------------------------------------------------------

setup_edit_mode lda #$00
                sta ppu_ctrl
                sta ppu_mask
                sta program_mode
                sta keyboard_x
                sta keyboard_y

                ldy #$20                ; prepare to write name & attribute table 0
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                ;
                ldx #(rle_editor_top-rle_data)  ; top part of editor
                jsr print_rle_data
                ;
                ldx #0                  ; Brainfuck code
-               lda bf_program,x
                sta ppu_data
                inx
                bne -
                ;
                ldx #(rle_editor_bot-rle_data)  ; bottom part of editor
                jsr print_rle_data
                ;
                lda #%00000000          ; clear attribute table
                ldx #(8*8)
                jsr fill_vram
                ;
                ldy #$22                ; write cursor to name table ($5f = "_")
                lda program_len
                jsr set_ppu_addr        ; Y, A -> address
                lda #$5f
                sta ppu_data

                jmp main_loop

; --- Main loop -----------------------------------------------------------------------------------

main_loop       jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask

-               lda program_mode        ; wait until we exit editor in NMI routine
                beq -

                ; start execution

                lda #%00000000          ; disable rendering
                sta ppu_ctrl

                jsr wait_vbl_start      ; wait until next VBlank starts

                ; copy Brainfuck program from VRAM to RAM

                ldy #$22                ; first half (row 16)
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                tax
                lda ppu_data
-               lda ppu_data
                sta bf_program,x
                inx
                bpl -
                jsr reset_ppu_addr

                jsr wait_vbl_start      ; wait until next VBlank starts

                ldy #$22                ; second half (row 20)
                lda #$80
                jsr set_ppu_addr        ; Y, A -> address
                tax
                lda ppu_data
-               lda ppu_data
                sta bf_program,x
                inx
                bne -
                jsr reset_ppu_addr

                ; for each bracket, store address of corresponding bracket
                ldy #0
                dex
                txs                     ; initialize stack pointer to $ff (stack must be empty)
bracket_loop    lda bf_program,y
                cmp #'['
                bne +
                tya                     ; push current address
                pha
                jmp char_done
+               cmp #']'
                bne char_done
                pla                     ; pull address of previous opening bracket;
                tsx                     ; exit if invalid (if stack underflowed)
                beq brackets_done
                sta brackets,y          ; for current bracket, store that address
                tax                     ; for that bracket, store current address
                tya
                sta brackets,x
char_done       iny
                bne bracket_loop
                ; make Y 255 so we can distinguish between different errors, if any
                ; (if we had exited because of a closing bracket without matching opening bracket,
                ; Y would be 0-254)
                dey

brackets_done   bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -

                tsx                     ; if stack pointer is not $ff,
                inx                     ; print an error message on row 25
                beq brackets_ok         ; Y reveals type of error
                lda #$23
                sta ppu_addr
                lda #$20
                sta ppu_addr
                ldx #(str_open_brak-strings)
                iny
                beq +
                ldx #(str_clos_brak-strings)
+               jsr print_string
                jsr reset_ppu_addr
-               jsr read_joypad         ; wait for button press
                sta pad_status
                and #pad_b
                beq -

                bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -

                dec program_mode        ; return to edit mode ($20 = space)
                ldy #$23
                lda #$20
                jsr set_ppu_addr        ; Y, A -> address
                lda #$20
                ldx #32
                jsr fill_vram
                jsr reset_ppu_addr
                jmp main_loop

brackets_ok     lda #%00000000          ; disable rendering
                sta ppu_mask

                ; replace each instruction with the offset of the subroutine
                ; that executes that instruction; the cursor ("_") is an instruction that ends the
                ; program
                ldx #0
ins_repl_loop   lda bf_program,x
                ldy #0
-               cmp bf_instrs,y
                beq +
                iny
                cpy #(instr_cnt-1)
                bne -
+               lda instr_offsets,y     ; if no match, instr_cnt-1 is "end program" instruction
                sta bf_program,x
                inx
                bne ins_repl_loop

                txa                     ; clear RAM for Brainfuck program
-               sta bf_ram,x
                inx
                bne -

                ldy #$20                ; rewrite name table
                lda #$00
                jsr set_ppu_addr        ; Y, A -> address
                ;
                ldx #(rle_exec_top-rle_data)
                jsr print_rle_data
                ;
                ldx #(str_running-strings)
                jsr print_string
                ;
                lda #$20                ; space
                ldx #28
                jsr fill_vram

                ldx #32                 ; virtual keyboard (X = character code)
keyb_loop       txa
                and #%00001111
                bne +
                lda #$20                ; end of line; print 16 spaces ($20 = space)
                ldy #16
-               sta ppu_data
                dey
                bne -
+               stx ppu_data
                inx
                bpl keyb_loop
                lda #$20                ; fill rest of name table ($20 = space)
                ldx #136
                jsr fill_vram

                lda #%01010101          ; write attribute table - hide virtual keyboard for now
                jsr set_keyb_attr

                jsr reset_ppu_addr

                bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -

                jsr set_ppu_regs        ; set ppu_scroll/ppu_ctrl/ppu_mask
                jmp run_mode            ; actual execution of the Brainfuck program

instr_offsets   db value_incr -run_mode  ; offsets of instructions in run mode
                db value_decr -run_mode
                db addr_decr  -run_mode
                db addr_incr  -run_mode
                db loop_start -run_mode
                db loop_end   -run_mode
                db output     -run_mode
                db input      -run_mode
                db program_end-run_mode

; -------------------------------------------------------------------------------------------------

                align $100, $ff
run_mode        ldx #$00
                stx outp_buflen
                stx output_len

                ldy #$ff                ; Y/X = address in Brainfuck code/RAM
execute_loop    iny
                lda bf_program,y
                sta pointer+0
                jmp (pointer)

value_incr      inc bf_ram,x
                jmp execute_loop

value_decr      dec bf_ram,x
                jmp execute_loop

addr_decr       dex
                jmp execute_loop

addr_incr       inx
                jmp execute_loop

loop_start      lda bf_ram,x
                bne execute_loop
                lda brackets,y
                tay
                jmp execute_loop

loop_end        lda bf_ram,x
                beq execute_loop
                lda brackets,y
                tay
                jmp execute_loop

output          lda bf_ram,x            ; add character to buffer; wait for NMI routine to flush
                sta outp_buffer
                inc outp_buflen
-               lda outp_buflen
                bne -
                lda output_len
                beq program_end         ; 256 characters printed
                jmp execute_loop

input           bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -

                stx temp
                ldy #$22                ; print message asking for input on row 18
                lda #$40
                jsr set_ppu_addr        ; Y, A -> address
                ldx #(str_input-strings)
                jsr print_string

                lda #%00000000          ; show virtual keyboard
                jsr set_keyb_attr
                jsr reset_ppu_addr

                lda #%00011110          ; show sprites
                sta ppu_mask

                inc program_mode        ; wait for NMI routine to provide input
-               ldx program_mode
                dex
                bne -

                ldy #$22                ; restore text "Running..." on row 18
                lda #$40
                jsr set_ppu_addr        ; Y, A -> address
                ldx #(str_running-strings)
                jsr print_string

                lda #%01010101          ; hide virtual keyboard
                jsr set_keyb_attr
                jsr reset_ppu_addr

                lda #%00001010          ; hide sprites
                sta ppu_mask

                ldx temp                ; restore X

                lda input_char          ; store input
                sta bf_ram,x
                jmp execute_loop

program_end     ; Brainfuck program has finished

                lda #%00000000          ; disable NMI
                sta ppu_ctrl

                bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -

                ldy #$22                ; print message on row 18
                lda #$40
                jsr set_ppu_addr        ; Y, A -> address
                ldx #(str_finish-strings)
                jsr print_string
                jsr reset_ppu_addr

-               jsr read_joypad         ; wait for button press
                sta pad_status
                and #pad_b
                beq -

                jmp setup_edit_mode

; --- NMI routine ---------------------------------------------------------------------------------

nmi             pha                     ; push A, X, Y
                txa
                pha
                tya
                pha

                ldx program_mode        ; continue according to the mode we're in
                beq nmi_edit_mode
                dex
                beq nmi_run_mode
                jmp nmi_input_mode

nmi_edit_mode   jsr read_joypad

                cpx pad_status          ; exit if joypad status hasn't changed
                bne +
                jmp nmi_exit
+               stx pad_status

                ldx program_len         ; if trying to enter a character and there's less than
                inx                     ; 255, add it and exit
                beq char_entry_end
                ldy #(instr_cnt-1)
-               lda edit_buttons,y
                cmp pad_status
                bne +
                lda #$22                ; print character over old cursor; also print new cursor
                sta ppu_addr
                lda program_len
                sta ppu_addr
                lda bf_instrs,y
                sta ppu_data
                lda #'_'
                sta ppu_data
                inc program_len
                jmp nmi_exit
+               dey
                bpl -
char_entry_end

                lda program_len         ; if "backspace" pressed and at least one character
                beq +                   ; written, delete last character and exit
                lda pad_status
                cmp #(pad_st|pad_l)
                bne +
                dec program_len
                ldy #$22                ; print cursor over last char and space over old cursor
                lda program_len
                jsr set_ppu_addr        ; Y, A -> address
                lda #"_"
                sta ppu_data
                lda #$20                ; space
                sta ppu_data
                jmp nmi_exit

+               lda pad_status          ; run program if requested
                cmp #(pad_se|pad_st)
                bne +
                inc program_mode
+               jmp nmi_exit

nmi_run_mode    jsr read_joypad
                sta pad_status

                and #pad_b              ; exit if requested
                beq +
                jmp setup_edit_mode

+               lda outp_buflen         ; print character from buffer if necessary
                bne +
                jmp nmi_exit
+               lda outp_buffer
                cmp #$0a
                beq newline
                ldy #$21
                lda output_len
                jsr set_ppu_addr        ; Y, A -> address
                lda outp_buffer
                sta ppu_data
                inc output_len
                dec outp_buflen
                jmp nmi_exit
newline         lda output_len          ; count rest of line towards maximum number of characters
                and #%11100000          ; to output
                adc #(32-1)             ; carry still set by CMP
                sta output_len
                dec outp_buflen
                jmp nmi_exit

nmi_input_mode  jsr read_joypad

                cmp pad_status          ; react to buttons if joypad status has changed
                beq keyb_end
                sta pad_status
                lsr
                bcs keyb_right          ; button: right
                lsr
                bcs keyb_left           ; button: left
                lsr
                bcs keyb_down           ; button: down
                lsr
                bcs keyb_up             ; button: up
                lsr
                lsr
                lsr
                bcs keyb_quit           ; button: B
                lsr
                bcs keyb_accept         ; button: A
                jmp keyb_end            ; none of the above
keyb_left       ldx keyboard_x
                dex
                txa
                and #%00001111
                sta keyboard_x
                jmp keyb_end
keyb_right      ldx keyboard_x
                inx
                txa
                and #%00001111
                sta keyboard_x
                jmp keyb_end
keyb_up         ldx keyboard_y
                dex
                bpl +
                ldx #5
+               stx keyboard_y
                jmp keyb_end
keyb_down       ldx keyboard_y
                inx
                cpx #6
                bne +
                ldx #0
+               stx keyboard_y
                jmp keyb_end
keyb_accept     dec program_mode        ; back to run mode
                jmp keyb_end
keyb_quit       jmp setup_edit_mode
keyb_end

                lda keyboard_y          ; Y position of sprites
                asl
                asl
                asl
                tax
                adc #(20*8-1)
                sta sprite_data+1*4+0
                sta sprite_data+2*4+0

                txa                     ; sprite 0 tile and entered character
                asl                     ; keyboard_y * 16
                adc #$20                ; keyboard starts at character $20
                adc keyboard_x
                sta sprite_data+1*4+1
                cmp #$7f                ; store last symbol on keyboard as real newline
                bne +
                lda #$0a
+               sta input_char

                lda keyboard_x          ; X position of sprites
                asl
                asl
                asl
                adc #(8*8)
                sta sprite_data+1*4+3
                sta sprite_data+2*4+3

                lda #>sprite_data
                sta oam_dma

nmi_exit        jsr reset_ppu_addr      ; reset VRAM address

                sec                     ; set flag to let main loop run once
                ror run_main_loop

                pla                     ; pull Y, X, A
                tay
                pla
                tax
                pla

irq             rti

edit_buttons    db pad_u                ; buttons in edit mode
                db pad_d
                db pad_l
                db pad_r
                db pad_b
                db pad_a
                db pad_se|pad_a
                db pad_se|pad_b
                db pad_st|pad_r

; --- Subs & arrays used in many places -----------------------------------------------------------

wait_vbl_start  bit ppu_status          ; wait until next VBlank starts
-               bit ppu_status
                bpl -
                rts

reset_ppu_addr  lda #$00
                sta ppu_addr
                sta ppu_addr
                rts

set_ppu_addr    sty ppu_addr            ; set PPU address from Y & A
                sta ppu_addr
                rts

set_ppu_regs    lda #$00                ; reset PPU scroll
                sta ppu_scroll
                sta ppu_scroll
                lda #%10000000          ; enable NMI
                sta ppu_ctrl
                lda #%00011110          ; show background & sprites
                sta ppu_mask
                rts

fill_vram       sta ppu_data            ; write A to VRAM X times
                dex
                bne fill_vram
                rts

print_string    lda strings,x           ; print null-terminated string from array; X = offset
                beq +
                sta ppu_data
                inx
                bne print_string
+               rts

strings         ; null-terminated strings
str_open_brak   db "Error: '[' without ']'. Press B.", 0
str_clos_brak   db "Error: ']' without '['. Press B.", 0
str_running     db "Running... (B=end)          ", 0
str_input       db "Character? (", $86, $87, $88, $89, " A=OK B=end)", 0
str_finish      db "Finished. Press B.", 0

print_rle_data  ; print run-length-encoded data from the rle_data array starting from offset X
                ; compressed block:
                ;   - length minus one; length is 2-128
                ;   - byte to repeat
                ; uncompressed block:
                ;   - $80 | (length - 1); length is 1-128
                ;   - as many bytes as length is
                ; terminator: $00
                ;
--              ldy rle_data,x          ; start block, get block type
                beq +++                 ; terminator
                bpl +
-               inx                     ; uncompressed block
                lda rle_data,x
                sta ppu_data
                dey
                bmi -
                jmp ++
+               inx                     ; compressed block
                lda rle_data,x
-               sta ppu_data
                dey
                bpl -
++              inx                     ; end of block
                bne --
+++             rts                     ; end of blocks

read_joypad     ldx #1                  ; return joypad status in A, X
                stx joypad1
                dex
                stx joypad1
                ldy #8
-               lda joypad1
                ror
                txa
                rol
                tax
                dey
                bne -
                rts

set_keyb_attr   ldx #$23                ; write A to attribute table 0 on virtual keyboard 12 times
                stx ppu_addr            ; $23ea = $23c0 + 5 * 8 + 2
                ldx #$ea
                stx ppu_addr
                ldx #12
-               sta ppu_data
                dex
                bne -
                rts

bf_instrs       db "+"                  ; Brainfuck instructions
                db "-"                  ; " " = space in edit mode, "end program" in run mode
                db "<"                  ; (this needs to be changed)
                db ">"
                db "["
                db "]"
                db "."
                db ","
                db " "

rle_data        ; run-length-encoded name table data (see print_rle_data for format)
                ;
rle_editor_top  ; top of editor screen (before Brainfuck code)
                db 102-1, " "
                db $80|(1-1), $82
                db  17-1, $80
                db $80|(1-1), $83
                db  13-1, " "
                db $80|(19-1), $81, "Qalle's Brainfuck", $81
                db  13-1, " "
                db $80|(1-1), $84
                db  17-1, $80
                db $80|(1-1), $85
                db  40-1, " "
                db $80|(8-1), $86, "=+  ", $87, "=-"
                db  3-1, " "
                db $80|(8-1), $88, "=<  ", $89, "=>"
                db  3-1, " "
                db $80|(8-1), "B=[  A=]"
                db  47-1, " "
                db $80|(13-1), "start-", $89, "=space"
                db  19-1, " "
                db $80|(41-1), "start-", $88, "=backspace  select-B=,  select-A=."
                db  42-1, " "
                db $80|(16-1), "select-start=run"
                db  47-1, " "
                db  32-1, $80
                db 0                    ; terminator
                ;
rle_editor_bot  ; bottom of editor screen (after Brainfuck code)
                db  32-1, $80
                db 128-1, " "
                db  32-1, " "
                db 0                    ; terminator
                ;
rle_exec_top    ; top of execution screen (before the text "Running")
                db 128-1, " "
                db  32-1, " "
                db $80|(7-1), "Output:"
                db  57-1, " "
                db  32-1, $80
                db 128-1, " "
                db 128-1, " "
                db  32-1, $80
                db  32-1, " "
                db 0                    ; terminator

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
                hex 00 00 ff ff ff 00 00 00  ; tile $80 (horizontal bar)
                hex 38 38 38 38 38 38 38 38  ; tile $81 (vertical bar)
                hex 00 00 0f 1f 3f 3c 38 38  ; tile $82 (top left corner)
                hex 00 00 e0 f0 f8 78 38 38  ; tile $83 (top right corner)
                hex 38 3c 3f 1f 0f 00 00 00  ; tile $84 (bottom left corner)
                hex 38 78 f8 f0 e0 00 00 00  ; tile $85 (bottom right corner)
                hex 10 38 54 10 10 10 10 00  ; tile $86 (up arrow)
                hex 10 10 10 10 54 38 10 00  ; tile $87 (down arrow)
                hex 00 20 40 fe 40 20 00 00  ; tile $88 (left arrow)
                hex 00 08 04 fe 04 08 00 00  ; tile $89 (right arrow)
                hex ff ff ff ff ff ff ff ff  ; tile $8a (solid color 1)

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff
                dw nmi, reset, irq      ; note: IRQ unused
