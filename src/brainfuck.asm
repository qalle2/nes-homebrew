    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory

mode              equ $00  ; 0 = editing, 1 = running, 2 = asking for input
joypad_status     equ $01
program_length    equ $02  ; 0-255
pointer           equ $03  ; 2 bytes
output_buffer     equ $05  ; 1 byte
output_buffer_len equ $06  ; 0-1
output_char_cnt   equ $07  ; number of characters printed by the Brainfuck program
keyboard_x        equ $08  ; virtual keyboard - X position (0-15)
keyboard_y        equ $09  ; virtual keyboard - Y position (0-5)
input_char        equ $0a  ; virtual keyboard - character (32-127)
temp              equ $0b

program_original equ $0200  ; code with spaces (255 bytes)
program_stripped equ $0300  ; code without spaces (255 bytes)
brackets         equ $0400  ; target addresses of "[" and "]" (255 bytes)
brainfuck_ram    equ $0500  ; RAM (256 bytes)

sprite_data equ $0600  ; 256 bytes

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014
joypad1    equ $4016

; PPU memory

vram_name_table0      equ $2000
vram_attribute_table0 equ $23c0
vram_palette          equ $3f00

; non-address constants

button_a      equ 1 << 7
button_b      equ 1 << 6
button_select equ 1 << 5
button_start  equ 1 << 4
button_up     equ 1 << 3
button_down   equ 1 << 2
button_left   equ 1 << 1
button_right  equ 1 << 0

terminator equ $00

sprite_count      equ 2
instruction_count equ 11

black equ $0f
white equ $30

; --------------------------------------------------------------------------------------------------
; Macros

macro wait_for_start_of_vblank
    bit ppu_status
-   bit ppu_status
    bpl -
endm

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:
    lda #$00
    sta ppu_ctrl  ; disable NMI
    sta ppu_mask  ; hide background&sprites
    sta joypad_status
    sta program_length

    ; clear Brainfuck code
    tax
-   sta program_original, x
    inx
    bne -

    ; initialize used sprites, hide other sprites
-   lda initial_sprite_data, x
    sta sprite_data, x
    inx
    cpx #(sprite_count * 4)
    bne -
    lda #$ff
-   sta sprite_data, x
    inx
    bne -

    wait_for_start_of_vblank
-   bit ppu_status
    bpl -

    ; palette

    ; fill with black
    lda #>vram_palette
    ldx #<vram_palette
    jsr set_vram_address
    lda #black
    ldx #32
    jsr write_vram

    ; change first color of first background&sprite subpalette to white
    lda #>(vram_palette + 1)
    ldx #<(vram_palette + 1)
    jsr set_vram_address
    ldy #white
    sty ppu_data
    ldx #<(vram_palette + 4 * 4 + 1)
    jsr set_vram_address
    sty ppu_data

    ; copy CHR data to CHR RAM;
    ; the second (more significant) bitplane of every character is blank

    ; set up source pointer, set target to start of pattern table 0
    lda #>CHRdata
    sta pointer + 1
    ldy #$00
    sty pointer + 0
    sty ppu_addr
    sty ppu_addr
chr_data_copy_loop:
    lda (pointer), y
    sta ppu_data
    iny
    ; if source offset is a multiple of eight, write a blank bitplane to complete the character
    tya
    and #%00000111
    bne +
    ldx #8
-   sta ppu_data
    dex
    bne -
+   ; if source page not finished, just continue loop
    cpy #0
    bne chr_data_copy_loop
    ; increment most significant byte of address; if not all data read, continue loop
    inc pointer + 1
    lda pointer + 1
    cmp #((>CHRdata) + 8)
    bne chr_data_copy_loop

    ; set high byte of pointer to run mode
    lda #>run_mode
    sta pointer + 1

edit_mode:
    lda #$00
    sta ppu_ctrl
    sta ppu_mask
    sta mode
    sta keyboard_x
    sta keyboard_y

    ; set up name table 0 and attribute table 0

    lda #>vram_name_table0
    ldx #<vram_name_table0
    jsr set_vram_address
    ; print top part of editor
    ldx #(rle_data_editor_top - rle_data)
    jsr print_rle_data
    ; print Brainfuck code
    ldx #0
-   lda program_original, x
    sta ppu_data
    inx
    bne -
    ; print bottom part of editor
    ldx #(rle_data_editor_bottom - rle_data)
    jsr print_rle_data
    ; clear attribute table
    lda #%00000000
    ldx #(8 * 8)
    jsr write_vram
    ; write cursor to name table
    lda #>(vram_name_table0 + 16 * 32)
    ldx program_length
    jsr set_vram_address
    lda #"_"
    sta ppu_data

    jsr reset_vram_address
    wait_for_start_of_vblank

wait_for_execution_start:
    lda #%10000000
    sta ppu_ctrl
    lda #%00001010
    sta ppu_mask

    ; wait until we exit the editor in the NMI routine
-   lda mode
    beq -

    ; start execution

    ; disable rendering
    lda #%00000000
    sta ppu_ctrl

    ; copy Brainfuck program from VRAM to RAM
    ; first half
    wait_for_start_of_vblank
    lda #>(vram_name_table0 + 16 * 32)
    ldx #<(vram_name_table0 + 16 * 32)
    jsr set_vram_address
    lda ppu_data
-   lda ppu_data
    sta program_original, x
    inx
    bpl -
    jsr reset_vram_address
    ; second half
    wait_for_start_of_vblank
    lda #>(vram_name_table0 + 20 * 32)
    ldx #<(vram_name_table0 + 20 * 32)
    jsr set_vram_address
    lda ppu_data
-   lda ppu_data
    sta program_original, x
    inx
    bne -
    jsr reset_vram_address

    ; copy program without spaces to another array
    lda #$00
    tax
-   sta program_stripped, x
    inx
    bne -
    tay
-   lda program_original, x
    cmp #$20  ; space
    beq +
    sta program_stripped, y
    iny
+   inx
    bne -

    ; for each bracket, store address of corresponding bracket
    ldy #0
    dex
    txs     ; initialize stack pointer to $ff (we haven't done this before; the stack is empty)
brackets_loop:
    lda program_stripped, y
    cmp #'['
    bne +
    ; push current address
    tya
    pha
    jmp character_done
+   cmp #']'
    bne character_done
    ; pull address of previous opening bracket; exit if invalid (if stack underflowed)
    pla
    tsx
    beq brackets_done
    ; for current bracket, store that address
    sta brackets, y
    ; for that bracket, store current address
    tax
    tya
    sta brackets, x
character_done:
    iny
    bne brackets_loop
    ; make Y 255 so we can distinguish between different errors, if any (if we had exited because
    ; of a closing bracket without matching opening bracket, Y would be 0-254)
    dey
brackets_done:

    ; if stack pointer is not $ff, print an error message; Y reveals type of error
    tsx
    inx
    beq brackets_ok
    wait_for_start_of_vblank
    lda #>(vram_name_table0 + 25 * 32)
    ldx #<(vram_name_table0 + 25 * 32)
    jsr set_vram_address
    ldx #(string_opening_bracket - strings)
    iny
    beq +
    ldx #(string_closing_bracket - strings)
+   jsr print_string
    jsr reset_vram_address
    ; wait for button press
-   jsr read_joypad
    sta joypad_status
    and #button_b
    beq -
    ; return to edit mode
    dec mode
    wait_for_start_of_vblank
    lda #$23
    ldx #$20
    jsr set_vram_address
    lda #$20  ; space
    ldx #32
    jsr write_vram
    jsr reset_vram_address
    jmp wait_for_execution_start

brackets_ok:
    ; disable rendering
    lda #%00000000
    sta ppu_mask

    ; in the stripped program, replace each instruction with the offset of the subroutine that
    ; executes that instruction; the cursor ("_") is an instruction that ends the program
    ldx #0
instruction_replace_loop:
    lda program_stripped, x
    ldy #0
-   cmp instructions, y
    beq +
    iny
    cpy #(instruction_count - 1)
    bne -
    ; if no match, (instruction_count - 1) is the "end program" instruction
+   lda instruction_offsets, y
    sta program_stripped, x
    inx
    bne instruction_replace_loop

    ; clear RAM for the Brainfuck program
    txa
-   sta brainfuck_ram, x
    inx
    bne -

    ; rewrite name table
    lda #>vram_name_table0
    jsr set_vram_address  ; X is still 0
    ldx #(rle_data_code_execution_top - rle_data)
    jsr print_rle_data
    ldx #(string_running - strings)
    jsr print_string
    lda #$20  ; space
    ldx #28
    jsr write_vram
    ; virtual keyboard
    ldx #32   ; ASCII code
virtual_keyboard_loop:
    txa
    and #%00001111
    bne +
    ; end of line; print 16 spaces
    lda #$20  ; space
    ldy #16
-   sta ppu_data
    dey
    bne -
+   stx ppu_data
    inx
    bpl virtual_keyboard_loop
    ; fill rest of name table
    lda #$20  ; space
    ldx #136
    jsr write_vram

    ; write attribute table - hide virtual keyboard for now
    lda #%01010101
    jsr set_virtual_keyboard_status

    jsr reset_vram_address
    wait_for_start_of_vblank

    ; enable NMI
    lda #%10000000
    sta ppu_ctrl

    ; enable background
    lda #%00001010
    sta ppu_mask

    ; the real execution of the Brainfuck program
    jmp run_mode

    org $c300
run_mode:
    ldx #$00
    stx output_buffer_len
    stx output_char_cnt

    ; Y: address in Brainfuck code
    ; X: address in Brainfuck RAM
    ldy #$ff
execution_loop:
    iny
    lda program_stripped, y
    sta pointer + 0
    jmp (pointer)

double_plus:
    inc brainfuck_ram, x
plus:
    inc brainfuck_ram, x
    jmp execution_loop

double_minus:
    dec brainfuck_ram, x
minus:
    dec brainfuck_ram, x
    jmp execution_loop

left:
    dex
    jmp execution_loop

right:
    inx
    jmp execution_loop

opening_bracket:
    lda brainfuck_ram, x
    bne execution_loop
    lda brackets, y
    tay
    jmp execution_loop

closing_bracket:
    lda brainfuck_ram, x
    beq execution_loop
    lda brackets, y
    tay
    jmp execution_loop

period:
    ; add character to buffer; wait for NMI routine to flush it
    lda brainfuck_ram, x
    sta output_buffer
    inc output_buffer_len
-   lda output_buffer_len
    bne -
    lda output_char_cnt
    beq end_program   ; 256 characters printed
    jmp execution_loop

comma:
    stx temp
    ; print message asking for input
    wait_for_start_of_vblank
    lda #>(vram_name_table0 + 18 * 32)
    ldx #<(vram_name_table0 + 18 * 32)
    jsr set_vram_address
    ldx #(string_input - strings)
    jsr print_string

    ; show virtual keyboard
    lda #%00000000
    jsr set_virtual_keyboard_status
    jsr reset_vram_address

    ; show sprites
    lda #%00011110
    sta ppu_mask

    ; wait for NMI routine to provide input
    inc mode
-   ldx mode
    dex
    bne -

    ; restore text "Running..."
    lda #>(vram_name_table0 + 18 * 32)
    ldx #<(vram_name_table0 + 18 * 32)
    jsr set_vram_address
    ldx #(string_running - strings)
    jsr print_string

    ; hide virtual keyboard
    lda #%01010101
    jsr set_virtual_keyboard_status
    jsr reset_vram_address

    ; hide sprites
    lda #%00001010
    sta ppu_mask

    ldx temp  ; restore X

    ; store input
    lda input_char
    sta brainfuck_ram, x
    jmp execution_loop

end_program:
    ; the Brainfuck program has finished

    ; disable NMI
    lda #%00000000
    sta ppu_ctrl

    wait_for_start_of_vblank

    ; print the text "Finished."
    lda #>(vram_name_table0 + 18 * 32)
    ldx #<(vram_name_table0 + 18 * 32)
    jsr set_vram_address
    ldx #(string_finished - strings)
    jsr print_string
    jsr reset_vram_address

    ; wait for button press
-   jsr read_joypad
    sta joypad_status
    and #button_b
    beq -

    jmp edit_mode

; --------------------------------------------------------------------------------------------------
; Non-maskable interrupt routine

nmi:
    ; I know php&plp in NMI is unnecessary, but I want to keep the binary identical to the old
    ; version
    php
    pha
    txa
    pha
    tya
    pha

    ; continue according to the mode we're in
    ldx mode
    beq nmi_edit_mode
    dex
    beq nmi_run_mode
    jmp nmi_input_mode

nmi_edit_mode:
    jsr read_joypad

    ; exit if joypad status hasn't changed
    cpx joypad_status
    bne +
    jmp nmi_exit
+   stx joypad_status

    ; if trying to enter a character and there's less than 255 of them, add the character and exit
    ldx program_length
    inx
    beq character_entry_end
    ldy #(instruction_count - 1)
-   lda instruction_buttons, y
    cmp joypad_status
    bne +
    ; print the character over the old cursor; also print the new cursor
    lda #>(vram_name_table0 + 16 * 32)
    ldx program_length
    jsr set_vram_address
    lda instructions, y
    sta ppu_data
    lda #'_'
    sta ppu_data
    inc program_length
    jmp reset_vram_address_and_exit_nmi
+   dey
    bpl -
character_entry_end:

    ; if "backspace" pressed and at least one character written, delete last character and exit
    lda program_length
    beq +
    lda joypad_status
    cmp #(button_start | button_left)
    bne +
    dec program_length
    ; print cursor over last character and space over old cursor
    lda #>(vram_name_table0 + 16 * 32)
    ldx program_length
    jsr set_vram_address
    lda #"_"
    sta ppu_data
    lda #$20  ; space
    sta ppu_data
    jmp reset_vram_address_and_exit_nmi

+   ; run the program if requested
    lda joypad_status
    cmp #(button_select | button_start)
    bne +
    inc mode
+   jmp nmi_exit

nmi_run_mode:
    jsr read_joypad
    sta joypad_status

    ; exit if requested
    and #button_b
    beq +
    jmp edit_mode
+

    ; print character from buffer if necessary
    lda output_buffer_len
    bne +
    jmp nmi_exit
+   lda output_buffer
    cmp #$0a
    beq newline
    lda #>(vram_name_table0 + 8 * 32)
    ldx output_char_cnt
    jsr set_vram_address
    lda output_buffer
    sta ppu_data
    inc output_char_cnt
    dec output_buffer_len
    jmp reset_vram_address_and_exit_nmi
newline:
    ; count rest of line towards maximum number of characters to output
    lda output_char_cnt
    and #%11100000
    adc #(32 - 1)  ; carry still set by cmp
    sta output_char_cnt
    dec output_buffer_len
    jmp nmi_exit

nmi_input_mode:
    jsr read_joypad

    ; react to buttons if joypad status has changed
    cmp joypad_status
    beq keyboard_end
    sta joypad_status
    lsr
    bcs keyboard_right   ; button: right
    lsr
    bcs keyboard_left    ; button: left
    lsr
    bcs keyboard_down    ; button: down
    lsr
    bcs keyboard_up      ; button: up
    lsr
    lsr
    lsr
    bcs keyboard_quit    ; button: B
    lsr
    bcs keyboard_accept  ; button: A
    jmp keyboard_end   ; none of the above
keyboard_left:
    ldx keyboard_x
    dex
    txa
    and #%00001111
    sta keyboard_x
    jmp keyboard_end
keyboard_right:
    ldx keyboard_x
    inx
    txa
    and #%00001111
    sta keyboard_x
    jmp keyboard_end
keyboard_up:
    ldx keyboard_y
    dex
    bpl +
    ldx #5
+   stx keyboard_y
    jmp keyboard_end
keyboard_down:
    ldx keyboard_y
    inx
    cpx #6
    bne +
    ldx #0
+   stx keyboard_y
    jmp keyboard_end
keyboard_accept:
    dec mode  ; back to run mode
    jmp keyboard_end
keyboard_quit:
    jmp edit_mode
keyboard_end:

    ; Y position of sprites
    lda keyboard_y
    asl
    asl
    asl
    tax
    adc #(20 * 8 - 1)
    sta sprite_data + 0
    sta sprite_data + 4

    ; sprite 0 tile and the entered character
    txa
    asl       ; keyboard_y * 16
    adc #$20  ; keyboard starts at character $20
    adc keyboard_x
    sta sprite_data + 1
    cmp #$7f  ; store last symbol on keyboard as real newline
    bne +
    lda #$0a
+   sta input_char

    ; X position of sprites
    lda keyboard_x
    asl
    asl
    asl
    adc #(8 * 8)
    sta sprite_data + 3
    sta sprite_data + 4 + 3

    lda #>sprite_data
    sta oam_dma

reset_vram_address_and_exit_nmi:
    jsr reset_vram_address
nmi_exit:
    pla
    tay
    pla
    tax
    pla
    plp  ; see note above
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

set_vram_address:
    sta ppu_addr
    stx ppu_addr
    rts

write_vram:
    ; write A to VRAM X times
-   sta ppu_data
    dex
    bne -
    rts

print_string:
    ; print a null-terminated string in table strings starting from offset X
-   lda strings, x
    beq +
    sta ppu_data
    inx
    bne -
+   rts

print_rle_data:
    ; print run length encoded data in table rle_data starting from offset X
    ; compressed block:
    ;   - length minus one; length is 2-128
    ;   - byte to repeat
    ; uncompressed block:
    ;   - $80 | (length - 1); length is 1-128
    ;   - as many bytes as length is
    ; terminator: $00
rle_block:
    ldy rle_data, x   ; block type
    beq rle_data_end  ; terminator
    bpl +
    ; uncompressed block
-   inx
    lda rle_data, x
    sta ppu_data
    dey
    bmi -
    jmp block_end
+   ; compressed block
    inx
    lda rle_data, x
-   sta ppu_data
    dey
    bpl -
block_end:
    inx
    bne rle_block
rle_data_end:
    rts

read_joypad:
    ; return in A and X
    ldx #1
    stx joypad1
    dex
    stx joypad1
    ldy #8
-   lda joypad1
    ror
    txa
    rol
    tax
    dey
    bne -
    rts

set_virtual_keyboard_status:
    ; write A to attribute table 0 on virtual keyboard 12 times
    ldx #>(vram_attribute_table0 + 5 * 8 + 2)
    stx ppu_addr
    ldx #<(vram_attribute_table0 + 5 * 8 + 2)
    stx ppu_addr
    ldx #12
-   sta ppu_data
    dex
    bne -
    rts

; --------------------------------------------------------------------------------------------------
; Tables

; Brainfuck instructions
instructions:
    db "+"
    db "-"
    db "<"
    db ">"
    db "["
    db "]"
    db "."
    db ","
    db $8a  ; double plus
    db $8b  ; double minus
    db " "  ; space in edit mode, "end program" in run mode
; buttons in edit mode
instruction_buttons:
    db button_up
    db button_down
    db button_left
    db button_right
    db button_b
    db button_a
    db button_select | button_a
    db button_select | button_b
    db button_start | button_up
    db button_start | button_down
    db button_start | button_right
; offsets for run mode
instruction_offsets:
    db plus            - run_mode
    db minus           - run_mode
    db left            - run_mode
    db right           - run_mode
    db opening_bracket - run_mode
    db closing_bracket - run_mode
    db period          - run_mode
    db comma           - run_mode
    db double_plus     - run_mode
    db double_minus    - run_mode
    db end_program     - run_mode

rle_data:
    ; run length encoded name table data (see print_rle_data for format)

rle_data_editor_top:
    ; edit screen before the Brainfuck code
    db 102 - 1, " "
    db $80 | (1 - 1), $82
    db 17 - 1, $80
    db $80 | (1 - 1), $83
    db 13 - 1, " "
    db $80 | (19 - 1), $81, "KHS-NES-Brainfuck", $81
    db 13 - 1, " "
    db $80 | (1 - 1), $84
    db 17 - 1, $80
    db $80 | (1 - 1), $85
    db 40 - 1, " "
    db $80 | (8 - 1), $86, "=+  ", $87, "=-"
    db 3 - 1, " "
    db $80 | (8 - 1), $88, "=<  ", $89, "=>"
    db 3 - 1, " "
    db $80 | (8 - 1), "B=[  A=]"
    db 35 - 1, " "
    db $80 | (9 - 1), "start-", $86, "=", $8a
    db 3 - 1,  " "
    db $80 | (13 - 1), "start-", $89, "=space"
    db 7 - 1, " "
    db $80 | (9 - 1), "start-", $87, "=", $8b
    db 3 - 1,  " "
    db $80 | (41 - 1), "start-", $88, "=backspace  select-B=,  select-A=."
    db 42 - 1, " "
    db $80 | (16 - 1), "select-start=run"
    db 47 - 1, " "
    db 32 - 1, $80
    db terminator

rle_data_editor_bottom:
    ; edit screen after the Brainfuck code
    db 32 - 1, $80
    db 128 - 1, " "
    db 32 - 1, " "
    db terminator

rle_data_code_execution_top:
    ; run screen before the text "Running"
    db 128 - 1, " "
    db 32 - 1, " "
    db $80 | (7 - 1), "Output:"
    db 57 - 1, " "
    db 32 - 1, $80
    db 128 - 1, " "
    db 128 - 1, " "
    db 32 - 1, $80
    db 32 - 1, " "
    db terminator

strings:
string_opening_bracket:
    db "Error: '[' without ']'. Press B."
    db terminator
string_closing_bracket:
    db "Error: ']' without '['. Press B."
    db terminator
string_running:
    db "Running... (B=end)          "
    db terminator
string_input:
    db "Character? (", $86, $87, $88, $89, " A=OK B=end)"
    db terminator
string_finished:
    db "Finished. Press B."
    db terminator

initial_sprite_data:
    db $ff, $00, %00000001, $ff   ; selected character in black
    db $ff, $8c, %00000000, $ff   ; a white block

; --------------------------------------------------------------------------------------------------
; CHR data
;   - 256 characters
;   - one bitplane (1 byte = 8 * 1 pixels, 8 bytes = character)
;   - printable ASCII at correct positions
;   - some extra characters

    pad $c800
CHRdata:
    dsb 32 * 8, $00  ; characters $00-$1f: blank

    ; characters $20-$3f: space and !"#$%&'()*+,-./0123456789:;<=>?
    hex 00 00 00 00 00 00 00 00
    hex 10 10 10 10 10 00 10 00
    hex 28 28 00 00 00 00 00 00
    hex 28 28 7c 28 7c 28 28 00
    hex 10 3c 50 38 14 78 10 00
    hex 00 44 08 10 20 44 00 00
    hex 38 44 28 10 2a 44 3a 00
    hex 10 10 00 00 00 00 00 00
    hex 08 10 20 20 20 10 08 00
    hex 20 10 08 08 08 10 20 00
    hex 00 44 28 fe 28 44 00 00
    hex 10 10 10 fe 10 10 10 00
    hex 00 00 00 00 08 10 20 00
    hex 00 00 00 fc 00 00 00 00
    hex 00 00 00 00 00 18 18 00
    hex 02 04 08 10 20 40 80 00
    hex 7c 82 82 92 82 82 7c 00
    hex 10 30 10 10 10 10 38 00
    hex 7c 82 02 7c 80 80 fe 00
    hex fc 02 02 fc 02 02 fc 00
    hex 08 18 28 48 fe 08 08 00
    hex fe 80 80 fc 02 02 fc 00
    hex 7e 80 80 fc 82 82 7c 00
    hex fe 04 08 10 20 40 80 00
    hex 7c 82 82 7c 82 82 7c 00
    hex 7c 82 82 7e 02 02 fc 00
    hex 00 10 00 00 00 10 00 00
    hex 00 10 00 00 10 20 40 00
    hex 08 10 20 40 20 10 08 00
    hex 00 00 fe 00 00 fe 00 00
    hex 40 20 10 08 10 20 40 00
    hex 7c 82 02 0c 10 10 00 10

    ; characters $40-$5f: @ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_
    hex 7c 82 ba ba b4 80 7e 00
    hex 7c 82 82 fe 82 82 82 00
    hex fc 42 42 7c 42 42 fc 00
    hex 7e 80 80 80 80 80 7e 00
    hex f8 84 82 82 82 84 f8 00
    hex fe 80 80 fe 80 80 fe 00
    hex fe 80 80 fe 80 80 80 00
    hex 7e 80 80 9e 82 82 7e 00
    hex 82 82 82 fe 82 82 82 00
    hex 38 10 10 10 10 10 38 00
    hex 04 04 04 04 04 44 38 00
    hex 44 48 50 60 50 48 44 00
    hex 80 80 80 80 80 80 fe 00
    hex 82 c6 aa 92 82 82 82 00
    hex 82 c2 a2 92 8a 86 82 00
    hex 7c 82 82 82 82 82 7c 00
    hex fc 82 82 fc 80 80 80 00
    hex 7c 82 82 92 8a 86 7e 00
    hex fc 82 82 fc 88 84 82 00
    hex 7e 80 80 7c 02 02 fc 00
    hex fe 10 10 10 10 10 10 00
    hex 82 82 82 82 82 82 7c 00
    hex 82 82 82 82 44 28 10 00
    hex 82 82 82 92 aa c6 82 00
    hex 82 44 28 10 28 44 82 00
    hex 82 44 28 10 10 10 10 00
    hex fe 04 08 10 20 40 fe 00
    hex 38 20 20 20 20 20 38 00
    hex 80 40 20 10 08 04 02 00
    hex 38 08 08 08 08 08 38 00
    hex 10 28 44 00 00 00 00 00
    hex 00 00 00 00 00 00 fe 00

    ; characters $60-$7f: `abcdefghijklmnopqrstuvwxyz{|}~
    hex 10 08 04 00 00 00 00 00
    hex 00 00 78 04 3c 4c 34 00
    hex 40 40 78 44 44 44 78 00
    hex 00 00 3c 40 40 40 3c 00
    hex 04 04 3c 44 44 44 3c 00
    hex 00 00 38 44 78 40 3c 00
    hex 18 24 20 78 20 20 20 00
    hex 00 00 34 4c 44 3c 04 78
    hex 40 40 58 64 44 44 44 00
    hex 00 10 00 10 10 10 10 00
    hex 00 08 00 08 08 08 48 30
    hex 40 40 48 50 60 50 48 00
    hex 30 10 10 10 10 10 10 00
    hex 00 00 b6 da 92 92 92 00
    hex 00 00 58 64 44 44 44 00
    hex 00 00 38 44 44 44 38 00
    hex 00 00 58 64 44 78 40 40
    hex 00 00 34 4c 44 3c 04 04
    hex 00 00 5c 60 40 40 40 00
    hex 00 00 3c 40 38 04 78 00
    hex 00 20 78 20 20 28 10 00
    hex 00 00 44 44 44 4c 34 00
    hex 00 00 44 44 28 28 10 00
    hex 00 00 54 54 54 54 28 00
    hex 00 00 44 28 10 28 44 00
    hex 00 00 44 44 44 3c 04 78
    hex 00 00 7c 08 10 20 7c 00
    hex 0c 10 10 60 10 10 0c 00
    hex 10 10 10 00 10 10 10 00
    hex 60 10 10 0c 10 10 60 00
    hex 64 98 00 00 00 00 00 00
    hex 04 04 24 44 fc 40 20 00

    ; characters $80-$8c
    hex 00 00 ff ff ff 00 00 00  ; $80: horizontal thick line
    hex 38 38 38 38 38 38 38 38  ; $81: vertical thick line
    hex 00 00 0f 1f 3f 3c 38 38  ; $82: curved thick line from bottom to right
    hex 00 00 e0 f0 f8 78 38 38  ; $83: curved thick line from bottom to left
    hex 38 3c 3f 1f 0f 00 00 00  ; $84: curved thick line from top to right
    hex 38 78 f8 f0 e0 00 00 00  ; $85: curved thick line from top to left
    hex 10 38 54 10 10 10 10 00  ; $86: up arrow
    hex 10 10 10 10 54 38 10 00  ; $87: down arrow
    hex 00 20 40 fe 40 20 00 00  ; $88: left arrow
    hex 00 08 04 fe 04 08 00 00  ; $89: right arrow
    hex 00 40 44 e4 4e 44 04 00  ; $8a: double plus
    hex 00 00 f0 00 1e 00 00 00  ; $8b: double minus
    hex ff ff ff ff ff ff ff ff  ; $8c: solid block

    pad $d000, $00  ; the rest of the 256 characters are blank

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
