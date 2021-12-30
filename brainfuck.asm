; Qalle's Brainfuck (NES, ASM6)
; Style:
; - indentation of instructions: 12 spaces
; - maximum length of identifiers: 11 characters
; TODO:
; - high-level structure of code is unclear w.r.t. program mode
; - avoid reading VRAM
; - move stuff away from NMI routine

; --- Constants -----------------------------------------------------------------------------------

; RAM
mode        equ $00    ; 0 = editing, 1 = running, 2 = asking for input
joypad_stat equ $01    ; joypad status
program_len equ $02    ; length of Brainfuck program (0-255)
pointer     equ $03    ; 2 bytes; a general-purpose pointer
outp_buffer equ $05    ; 1 byte; screen output buffer
outp_buflen equ $06    ; 0-1  ; length of screen output buffer
output_len  equ $07    ; number of characters printed by the Brainfuck program
keyboard_x  equ $08    ; virtual keyboard - X position (0-15)
keyboard_y  equ $09    ; virtual keyboard - Y position (0-5)
input_char  equ $0a    ; virtual keyboard - character (32-127)
temp        equ $0b    ; a temporary variable
prog_orig   equ $0200  ; Brainfuck program with spaces (255 bytes)
prog_strip  equ $0300  ; Brainfuck program without spaces (255 bytes)
brackets    equ $0400  ; target addresses of "[" and "]" (255 bytes)
bf_ram      equ $0500  ; RAM of Brainfuck program (256 bytes)
sprite_data equ $0600  ; 256 bytes

; memory-mapped registers
ppu_ctrl    equ $2000
ppu_mask    equ $2001
ppu_status  equ $2002
ppu_addr    equ $2006
ppu_data    equ $2007
dmc_freq    equ $4010
oam_dma     equ $4014
sound_ctrl  equ $4015
joypad1     equ $4016
joypad2     equ $4017

; joypad button bitmasks
pad_a       equ 1<<7
pad_b       equ 1<<6
pad_select  equ 1<<5
pad_start   equ 1<<4
pad_up      equ 1<<3
pad_down    equ 1<<2
pad_left    equ 1<<1
pad_right   equ 1<<0

; colors
color_bg    equ $0f  ; background   (black)
color_fg1   equ $25  ; foreground 1 (pink)
color_fg2   equ $21  ; foreground 2 (cyan)
color_fg3   equ $30  ; foreground 3 (white)

instr_cnt   equ 11  ; number of unique instructions

; --- iNES header ---------------------------------------------------------------------------------

            ; see https://wiki.nesdev.org/w/index.php/INES
            base $0000
            db "NES", $1a            ; file id
            db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
            db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
            pad $0010, $00           ; unused

; --- Main program --------------------------------------------------------------------------------

            base $c000

reset       ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
            sei             ; ignore IRQs
            cld             ; disable decimal mode
            ldx #%01000000
            stx joypad2     ; disable APU frame IRQ
            ldx #$ff
            txs             ; initialize stack pointer
            inx
            stx ppu_ctrl    ; disable NMI
            stx ppu_mask    ; disable rendering
            stx dmc_freq    ; disable DMC IRQs
            stx sound_ctrl  ; disable sound channels

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            ldx #0             ; clear zero page and Brainfuck code; hide all sprites
-           lda #$00
            sta $00,x
            sta prog_orig,x
            lda #$ff
            sta sprite_data,x
            inx
            bne -

            ldx #0               ; initialize used sprites
-           lda initsprdata,x
            sta sprite_data,x
            inx
            cpx #(2*4)
            bne -

            lda #>runmode  ; set high byte of pointer to run mode
            sta pointer+1

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #$3f         ; set palette (while we're still in VBlank; copy the palette array
            ldx #$00         ; 4 times to PPU)
            jsr set_vramadr
            ldy #4
--          ldx #0
-           lda palette,x
            sta ppu_data
            inx
            cpx #8
            bne -
            dey
            bne --

edit_mode   lda #$00
            sta ppu_ctrl
            sta ppu_mask
            sta mode
            sta keyboard_x
            sta keyboard_y

            ; set up name table 0 and attribute table 0

            lda #$20
            ldx #$00
            jsr set_vramadr
            ldx #(rle_edittop-rle_data)  ; top part of editor
            jsr printrledat
            ldx #0                       ; Brainfuck code
-           lda prog_orig,x
            sta ppu_data
            inx
            bne -
            ldx #(rle_editbtm-rle_data)  ; bottom part of editor
            jsr printrledat
            lda #%00000000               ; clear attribute table
            ldx #(8*8)
            jsr write_vram
            lda #$22                     ; write cursor to name table ($5f = "_")
            ldx program_len
            jsr set_vramadr
            lda #$5f
            sta ppu_data

            jsr rst_vramadr

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            jmp wait_exec

palette     ; copied 4 times to PPU palette
            db color_bg, color_fg1, color_fg2, color_fg3
            db color_bg, color_bg,  color_bg,  color_bg

initsprdata ; initial sprite data
            db 255, $00, %00000001, 255   ; selected character in background color
            db 255, $8c, %00000000, 255   ; a block filled with foreground color

; --- Main loop -----------------------------------------------------------------------------------

wait_exec   ; wait for execution start
            lda #%10000000  ; enable NMI, show background
            sta ppu_ctrl
            lda #%00001010
            sta ppu_mask

-           lda mode  ; wait until we exit editor in NMI routine
            beq -

            ; start execution

            lda #%00000000  ; disable rendering
            sta ppu_ctrl

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            ; copy Brainfuck program from VRAM to RAM

            lda #$22         ; first half (row 16)
            ldx #$00
            jsr set_vramadr
            lda ppu_data
-           lda ppu_data
            sta prog_orig,x
            inx
            bpl -
            jsr rst_vramadr

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #$22         ; second half (row 20)
            ldx #$80
            jsr set_vramadr
            lda ppu_data
-           lda ppu_data
            sta prog_orig,x
            inx
            bne -
            jsr rst_vramadr

            ; copy program without spaces to another array
            lda #$00
            tax
-           sta prog_strip,x
            inx
            bne -
            tay
-           lda prog_orig,x
            cmp #$20  ; space
            beq +
            sta prog_strip,y
            iny
+           inx
            bne -

            ; for each bracket, store address of corresponding bracket
            ldy #0
            dex
            txs               ; initialize stack pointer to $ff (stack must be empty)
bracketloop lda prog_strip,y
            cmp #'['
            bne +
            tya               ; push current address
            pha
            jmp chardone
+           cmp #']'
            bne chardone
            pla               ; pull address of previous opening bracket;
            tsx               ; exit if invalid (if stack underflowed)
            beq bracksdone
            sta brackets,y    ; for current bracket, store that address
            tax               ; for that bracket, store current address
            tya
            sta brackets,x
chardone    iny
            bne bracketloop
            ; make Y 255 so we can distinguish between different errors, if any (if we had exited
            ; because of a closing bracket without matching opening bracket, Y would be 0-254)
            dey

bracksdone  bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            tsx               ; if stack pointer is not $ff, print an error message on row 25;
            inx               ; Y reveals type of error
            beq brackets_ok
            lda #$23
            ldx #$20
            jsr set_vramadr
            ldx #(str_openbra-strings)
            iny
            beq +
            ldx #(str_closbra-strings)
+           jsr printstring
            jsr rst_vramadr
-           jsr read_joypad    ; wait for button press
            sta joypad_stat
            and #pad_b
            beq -

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            dec mode         ; return to edit mode ($20 = space)
            lda #$23
            ldx #$20
            jsr set_vramadr
            lda #$20
            ldx #32
            jsr write_vram
            jsr rst_vramadr
            jmp wait_exec

brackets_ok lda #%00000000  ; disable rendering
            sta ppu_mask

            ; in the stripped program, replace each instruction with the offset of the subroutine
            ; that executes that instruction; the cursor ("_") is an instruction that ends the
            ; program
            ldx #0
insreplloop lda prog_strip,x
            ldy #0
-           cmp bf_instrs,y
            beq +
            iny
            cpy #(instr_cnt-1)
            bne -
+           lda instoffsets,y  ; if no match, (instr_cnt - 1) is the "end program" instruction
            sta prog_strip,x
            inx
            bne insreplloop

            txa           ; clear RAM for the Brainfuck program
-           sta bf_ram,x
            inx
            bne -

            lda #$20                     ; rewrite name table
            jsr set_vramadr              ; X is still 0
            ldx #(rle_exectop-rle_data)
            jsr printrledat
            ldx #(str_running-strings)
            jsr printstring
            lda #$20  ; space
            ldx #28
            jsr write_vram

            ldx #32           ; virtual keyboard (X = character code)
virtkbdloop txa
            and #%00001111
            bne +
            lda #$20          ; end of line; print 16 spaces ($20 = space)
            ldy #16
-           sta ppu_data
            dey
            bne -
+           stx ppu_data
            inx
            bpl virtkbdloop
            lda #$20         ; fill rest of name table ($20 = space)
            ldx #136
            jsr write_vram

            lda #%01010101   ; write attribute table - hide virtual keyboard for now
            jsr setkeybstat

            jsr rst_vramadr

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #%10000000  ; enable NMI, show background
            sta ppu_ctrl
            lda #%00001010
            sta ppu_mask

            jmp runmode  ; the real execution of the Brainfuck program

            align $100, $ff
runmode     ldx #$00
            stx outp_buflen
            stx output_len

            ldy #$ff          ; Y/X = address in Brainfuck code/RAM
execloop    iny
            lda prog_strip,y
            sta pointer+0
            jmp (pointer)

double_plus inc bf_ram,x
plus        inc bf_ram,x
            jmp execloop

doubleminus dec bf_ram,x
minus       dec bf_ram,x
            jmp execloop

left        dex
            jmp execloop

right       inx
            jmp execloop

openbracket lda bf_ram,x
            bne execloop
            lda brackets,y
            tay
            jmp execloop

closbracket lda bf_ram,x
            beq execloop
            lda brackets,y
            tay
            jmp execloop

period      lda bf_ram,x     ; add character to buffer; wait for NMI routine to flush it
            sta outp_buffer
            inc outp_buflen
-           lda outp_buflen
            bne -
            lda output_len
            beq end_program   ; 256 characters printed
            jmp execloop

comma       bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            stx temp
            lda #$22                  ; print message asking for input on row 18
            ldx #$40
            jsr set_vramadr
            ldx #(str_input-strings)
            jsr printstring

            lda #%00000000            ; show virtual keyboard
            jsr setkeybstat
            jsr rst_vramadr

            lda #%00011110            ; show sprites
            sta ppu_mask

            inc mode                  ; wait for NMI routine to provide input
-           ldx mode
            dex
            bne -

            lda #$22                    ; restore text "Running..." on row 18
            ldx #$40
            jsr set_vramadr
            ldx #(str_running-strings)
            jsr printstring

            lda #%01010101              ; hide virtual keyboard
            jsr setkeybstat
            jsr rst_vramadr

            lda #%00001010              ; hide sprites
            sta ppu_mask

            ldx temp                    ; restore X

            lda input_char              ; store input
            sta bf_ram,x
            jmp execloop

end_program ; the Brainfuck program has finished

            lda #%00000000  ; disable NMI
            sta ppu_ctrl

            bit ppu_status  ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #$22                   ; print message on row 18
            ldx #$40
            jsr set_vramadr
            ldx #(str_finish-strings)
            jsr printstring
            jsr rst_vramadr

-           jsr read_joypad            ; wait for button press
            sta joypad_stat
            and #pad_b
            beq -

            jmp edit_mode

; --- NMI routine ---------------------------------------------------------------------------------

nmi         pha              ; push A, X, Y
            txa
            pha
            tya
            pha

            ldx mode         ; continue according to the mode we're in
            beq nmieditmode
            dex
            beq nmi_runmode
            jmp nmi_inpmode

nmieditmode jsr read_joypad

            cpx joypad_stat  ; exit if joypad status hasn't changed
            bne +
            jmp nmi_exit
+           stx joypad_stat


            ldx program_len     ; if trying to enter a character and there's less than 255 of
            inx                 ; them, add the character and exit
            beq chrentryend
            ldy #(instr_cnt-1)
-           lda editbuttons,y
            cmp joypad_stat
            bne +
            lda #$22            ; print the character over the old cursor; also print the new
            ldx program_len     ; cursor
            jsr set_vramadr
            lda bf_instrs,y
            sta ppu_data
            lda #'_'
            sta ppu_data
            inc program_len
            jmp nmi_exit
+           dey
            bpl -
chrentryend

            lda program_len            ; if "backspace" pressed and at least one character
            beq +                      ; written, delete last character and exit
            lda joypad_stat
            cmp #(pad_start|pad_left)
            bne +
            dec program_len
            lda #$22                   ; print cursor over last character and space over old
            ldx program_len            ; cursor
            jsr set_vramadr
            lda #"_"
            sta ppu_data
            lda #$20  ; space
            sta ppu_data
            jmp nmi_exit

+           lda joypad_stat              ; run program if requested
            cmp #(pad_select|pad_start)
            bne +
            inc mode
+           jmp nmi_exit

nmi_runmode jsr read_joypad
            sta joypad_stat

            and #pad_b         ; exit if requested
            beq +
            jmp edit_mode

+           lda outp_buflen   ; print character from buffer if necessary
            bne +
            jmp nmi_exit
+           lda outp_buffer
            cmp #$0a
            beq newline
            lda #$21
            ldx output_len
            jsr set_vramadr
            lda outp_buffer
            sta ppu_data
            inc output_len
            dec outp_buflen
            jmp nmi_exit
newline     lda output_len    ; count rest of line towards maximum number of characters to output
            and #%11100000
            adc #(32-1)       ; carry still set by cmp
            sta output_len
            dec outp_buflen
            jmp nmi_exit

nmi_inpmode jsr read_joypad

            cmp joypad_stat  ; react to buttons if joypad status has changed
            beq keyb_end
            sta joypad_stat
            lsr
            bcs keyb_right   ; button: right
            lsr
            bcs keyb_left    ; button: left
            lsr
            bcs keyb_down    ; button: down
            lsr
            bcs keyb_up      ; button: up
            lsr
            lsr
            lsr
            bcs keyb_quit    ; button: B
            lsr
            bcs keyb_accept  ; button: A
            jmp keyb_end     ; none of the above
keyb_left   ldx keyboard_x
            dex
            txa
            and #%00001111
            sta keyboard_x
            jmp keyb_end
keyb_right  ldx keyboard_x
            inx
            txa
            and #%00001111
            sta keyboard_x
            jmp keyb_end
keyb_up     ldx keyboard_y
            dex
            bpl +
            ldx #5
+           stx keyboard_y
            jmp keyb_end
keyb_down   ldx keyboard_y
            inx
            cpx #6
            bne +
            ldx #0
+           stx keyboard_y
            jmp keyb_end
keyb_accept dec mode        ; back to run mode
            jmp keyb_end
keyb_quit   jmp edit_mode
keyb_end

            lda keyboard_y  ; Y position of sprites
            asl
            asl
            asl
            tax
            adc #(20*8-1)
            sta sprite_data+0
            sta sprite_data+4

            txa                ; sprite 0 tile and the entered character
            asl                ; keyboard_y * 16
            adc #$20           ; keyboard starts at character $20
            adc keyboard_x
            sta sprite_data+1
            cmp #$7f           ; store last symbol on keyboard as real newline
            bne +
            lda #$0a
+           sta input_char

            lda keyboard_x  ; X position of sprites
            asl
            asl
            asl
            adc #(8*8)
            sta sprite_data+3
            sta sprite_data+4+3

            lda #>sprite_data
            sta oam_dma

nmi_exit    jsr rst_vramadr  ; reset VRAM address; ; pull Y, X, A
            pla
            tay
            pla
            tax
            pla

            rti

; --- Subs ----------------------------------------------------------------------------------------

rst_vramadr lda #$00
            sta ppu_addr
            sta ppu_addr
            rts

set_vramadr sta ppu_addr
            stx ppu_addr
            rts

write_vram  sta ppu_data     ; write A to VRAM X times
            dex
            bne write_vram
            rts

printstring lda strings,x    ; print null-terminated string from strings array starting from
            beq +            ; offset X
            sta ppu_data
            inx
            bne printstring
+           rts

printrledat ; print run-length-encoded data from the rle_data array starting from offset X
            ; compressed block:
            ;   - length minus one; length is 2-128
            ;   - byte to repeat
            ; uncompressed block:
            ;   - $80 | (length - 1); length is 1-128
            ;   - as many bytes as length is
            ; terminator: $00
--          ldy rle_data,x  ; start block, get block type
            beq +++         ; terminator
            bpl +
-           inx             ; uncompressed block
            lda rle_data,x
            sta ppu_data
            dey
            bmi -
            jmp ++
+           inx             ; compressed block
            lda rle_data,x
-           sta ppu_data
            dey
            bpl -
++          inx             ; end of block
            bne --
+++         rts             ; end of blocks

read_joypad ldx #1       ; return joypad status in A, X
            stx joypad1
            dex
            stx joypad1
            ldy #8
-           lda joypad1
            ror
            txa
            rol
            tax
            dey
            bne -
            rts

setkeybstat ldx #$23      ; write A to attribute table 0 on virtual keyboard 12 times
            stx ppu_addr  ; $23ea = $23c0 + 5 * 8 + 2
            ldx #$ea
            stx ppu_addr
            ldx #12
-           sta ppu_data
            dex
            bne -
            rts

; --- Arrays --------------------------------------------------------------------------------------

bf_instrs   db "+"  ; Brainfuck instructions ($8a = double plus, $8b = double minus,
            db "-"  ; " " = space in edit mode, "end program" in run mode)
            db "<"
            db ">"
            db "["
            db "]"
            db "."
            db ","
            db $8a
            db $8b
            db " "

editbuttons db pad_up  ; buttons in edit mode
            db pad_down
            db pad_left
            db pad_right
            db pad_b
            db pad_a
            db pad_select|pad_a
            db pad_select|pad_b
            db pad_start|pad_up
            db pad_start|pad_down
            db pad_start|pad_right

instoffsets db plus       -runmode  ; offsets of instructions in run mode
            db minus      -runmode
            db left       -runmode
            db right      -runmode
            db openbracket-runmode
            db closbracket-runmode
            db period     -runmode
            db comma      -runmode
            db double_plus-runmode
            db doubleminus-runmode
            db end_program-runmode

rle_data    ; run-length-encoded name table data (see printrledat for format)
rle_edittop ; top of editor screen (before Brainfuck code)
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
            db  35-1, " "
            db $80|(9-1), "start-", $86, "=", $8a
            db  3-1,  " "
            db $80|(13-1), "start-", $89, "=space"
            db  7-1, " "
            db $80|(9-1), "start-", $87, "=", $8b
            db  3-1,  " "
            db $80|(41-1), "start-", $88, "=backspace  select-B=,  select-A=."
            db  42-1, " "
            db $80|(16-1), "select-start=run"
            db  47-1, " "
            db  32-1, $80
            db $00  ; terminator
rle_editbtm ; bottom of editor screen (after Brainfuck code)
            db  32-1, $80
            db 128-1, " "
            db  32-1, " "
            db $00  ; terminator

rle_exectop ; top of execution screen (before the text "Running")
            db 128-1, " "
            db  32-1, " "
            db $80|(7-1), "Output:"
            db  57-1, " "
            db  32-1, $80
            db 128-1, " "
            db 128-1, " "
            db  32-1, $80
            db  32-1, " "
            db $00  ; terminator

strings     ; null-terminated strings
str_openbra db "Error: '[' without ']'. Press B.", $00
str_closbra db "Error: ']' without '['. Press B.", $00
str_running db "Running... (B=end)          ", $00
str_input   db "Character? (", $86, $87, $88, $89, " A=OK B=end)", $00
str_finish  db "Finished. Press B.", $00

; --- Interrupt vectors ---------------------------------------------------------------------------

            pad $fffa, $ff
            dw nmi, reset, 0

; --- CHR ROM -------------------------------------------------------------------------------------

            pad $10000, $ff
            incbin "brainfuck-chr.bin"
            pad $12000, $ff
