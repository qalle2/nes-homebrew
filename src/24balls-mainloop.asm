; 24 Balls - main loop

main_loop:
    ; wait until flag set
-   bit nmi_done
    bpl -

    ; move balls horizontally (all balls on even frames, all except last 8 on odd frames)
    ;
    ldx #(ball_count - 1)
    lda timer
    and #%00000001
    beq +
    ldx #(ball_count - 8 - 1)
+   stx loop_counter
    ;
horizontal_move_loop:
    ldx loop_counter
    ;
    ; direction address -> Y
    ldy horizontal_direction_addresses, x
    ;
    ; offset in sprite data -> X
    txa
    asl
    asl
    asl
    tax
    ;
    ; get current direction
    lda $00, y
    bpl move_right
    ;
    ; move both halves left; if hit left wall, change direction
    dec sprite_page + 3, x
    dec sprite_page + 4 + 3, x
    lda sprite_page + 3, x
    cmp #8
    bne horizontal_loop_end
    lda #$00
    sta $00, y
    jmp horizontal_loop_end
    ;
move_right:
    ; move both halves right; if hit right wall, change direction
    inc sprite_page + 3, x
    inc sprite_page + 4 + 3, x
    lda sprite_page + 3, x
    cmp #(256 - 16 - 8)
    bne horizontal_loop_end
    lda #$ff
    sta $00, y
    ;
horizontal_loop_end:
    dec loop_counter
    bpl horizontal_move_loop

    ; move balls vertically (very similar to previous loop)
    ;
    lda #(ball_count - 1)
    sta loop_counter
    ;
vertical_move_loop:
    ldx loop_counter
    ;
    ; direction address -> Y
    ldy vertical_direction_addresses, x
    ;
    ; offset in sprite data -> X
    txa
    asl
    asl
    asl
    tax
    ;
    ; get current direction
    lda $00, y
    bpl move_down
    ;
    ; move both halves up; if hit top wall, change direction
    dec sprite_page + 0, x
    dec sprite_page + 4 + 0, x
    lda sprite_page + 0, x
    cmp #(16 - 1)
    bne vertical_loop_end
    lda #$00
    sta $00, y
    jmp vertical_loop_end
    ;
move_down:
    ; move both halves down; if hit bottom wall, change direction
    inc sprite_page + 0, x
    inc sprite_page + 4 + 0, x
    lda sprite_page + 0, x
    cmp #(240 - 16 - 16 - 1)
    bne vertical_loop_end
    lda #$ff
    sta $00, y
    ;
vertical_loop_end:
    dec loop_counter
    bpl vertical_move_loop

    jsr sprite_palette_rom_to_ram
    inc timer
    lsr nmi_done  ; clear flag

    jmp main_loop

; -------------------------------------------------------------------------------------------------

horizontal_direction_addresses:
    hex  c1 c2 c3  c5 c6 c7  c9 ca cb  cd ce cf
    hex  d1 d2 d3  d5 d6 d7  d9 da db  dd de df

vertical_direction_addresses:
    hex  e1 e2 e3  e5 e6 e7  e9 ea eb  ed ee ef
    hex  f1 f2 f3  f5 f6 f7  f9 fa fb  fd fe ff

