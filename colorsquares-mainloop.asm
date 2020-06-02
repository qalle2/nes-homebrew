main_loop:
    ; wait until NMI routine has done its job
-   lda nmi_done
    beq -

    inc frame_counter
    jsr pick_squares_to_swap

    lda #0
    sta nmi_done

    jmp main_loop

pick_squares_to_swap:
    ; the location of the left or top square of the square pair to swap
    ldx frame_counter
    lda shuffle_data, x
    tay
    rept 4
        lsr
    endr
    sta moving_square1_x
    sta moving_square2_x
    tya
    and #%00001111
    sta moving_square1_y
    sta moving_square2_y

    ; the another square of the pair is to the right or below on alternating frames
    txa
    and #%00000001
    tax
    inc moving_square2_x, x  ; moving_square2_x or moving_square2_y
    rts

shuffle_data:
    ; 256 bytes
    ; upper nybble = X coordinate (0...e at even indexes, 0...f at odd indexes)
    ; lower nybble = Y coordinate (0...d at even indexes, 0...c at odd indexes)
    hex  2b 35  c4 71  5c b0  46 15  c6 80  d2 18  dc 27  bb 84
    hex  c6 7c  8d 59  e7 f9  8c 46  54 fc  64 ab  04 46  88 83
    hex  2b 89  06 98  33 2c  42 b1  6a 04  43 34  75 66  61 65
    hex  05 2c  17 16  98 cb  85 9a  78 15  03 8b  bb 23  b8 b3
    hex  6a 3c  06 86  c2 88  0d e0  1c b7  d5 20  70 46  59 ec
    hex  30 11  ca 57  64 47  c9 77  93 e4  5b 60  35 e3  a3 22
    hex  88 51  b6 c1  e5 53  9a c0  96 c6  b4 78  a3 66  ac 54
    hex  48 b9  dd d6  29 34  9c 37  91 d9  a0 37  89 77  b5 36
    hex  ad 4a  a2 65  c4 a9  80 e3  49 d1  65 5b  7d 0c  00 56
    hex  aa 96  12 f6  75 d4  a9 b6  28 ba  c5 55  5d 51  d5 f6
    hex  7b 2c  a9 ea  1a 04  ba 56  d2 e1  15 78  c8 d9  88 28
    hex  4c 08  8a 52  45 f1  35 32  28 f6  20 ba  ab 6b  71 c8
    hex  38 61  4a 42  0d 80  d5 b0  bd b8  47 f8  d2 05  ca 7a
    hex  78 c0  07 6b  13 f9  19 b2  45 63  65 c7  36 18  5b a1
    hex  65 f4  55 20  5b c0  cc 06  9b 54  08 79  91 2b  10 83
    hex  44 1c  90 d1  c1 aa  7b 66  7d 5c  08 5c  08 48  d5 17
