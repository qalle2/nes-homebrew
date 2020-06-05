main_loop:
    bit nmi_done
    bpl main_loop

    ; save old joypad status, read joypad
    lda joypad_status
    sta prev_joypad_status
    jsr read_joypad

    lsr nmi_done  ; clear flag

    jmp main_loop

; --------------------------------------------------------------------------------------------------

read_joypad:
    ; Read joypad status, save to joypad_status.
    ; Bits: A, B, select, start, up, down, left, right.

    ldx #$01
    stx joypad_status
    stx joypad1
    dex
    stx joypad1
    ; "OR" of joypad1's 2 LSBs -> carry
-   lda joypad1
    sta temp
    lsr
    ora temp
    ror
    ; store carry in joypad_status
    rol joypad_status
    ; loop until the "1" we initialized joypad_status with comes out
    bcc -
    rts
