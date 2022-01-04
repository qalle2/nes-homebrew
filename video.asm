; plays a short video of Doom gameplay (NES, ASM6)
; 32*24 tiles (64*48 "pixels"), 4 colors, 40 frames, 10 fps
; while one name table is being shown, the program copies 32*4 tiles/frame to another name table
; style:
; - indentation of instructions: 12 spaces
; - maximum length of identifiers: 11 characters
; - indentation of inline comments: uniform within a sub

; --- iNES header ---------------------------------------------------------------------------------

            ; see https://wiki.nesdev.org/w/index.php/INES
            base $0000
            db "NES", $1a            ; file id
            db 2, 1                  ; 32 KiB PRG ROM, 8 KiB CHR ROM
            db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
            pad $0010, $00           ; unused

; --- Constants -----------------------------------------------------------------------------------

; RAM
vram_buffer equ $00    ; 128 bytes; name table data to copy during VBlank
ntdata_ptr  equ $80    ; 2 bytes; read pointer to name table data (low byte first)
ppuaddr_mir equ $82    ; 2 bytes; mirror of ppu_addr (low byte first)
ppuctrl_mir equ $84    ; mirror of ppu_ctrl
counter_lo  equ $85    ; 0-5
counter_hi  equ $86    ; 0 to (frame_count - 1)
run_main    equ $87    ; if negative, allow main loop to run once

; memory-mapped registers
ppu_ctrl    equ $2000
ppu_mask    equ $2001
ppu_status  equ $2002
ppu_scroll  equ $2005
ppu_addr    equ $2006
ppu_data    equ $2007
dmc_freq    equ $4010
snd_ctrl    equ $4015
joypad2     equ $4017

frame_count equ 40     ; number of complete frames

; --- Initialization ------------------------------------------------------------------------------

            base $8000  ; last 32 KiB of CPU memory space

reset       ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
            sei              ; ignore IRQs
            cld              ; disable decimal mode
            ldx #%01000000
            stx joypad2      ; disable APU frame IRQ
            ldx #$ff
            txs              ; initialize stack pointer
            inx
            stx ppu_ctrl     ; disable NMI
            stx ppu_mask     ; disable rendering
            stx dmc_freq     ; disable DMC IRQs
            stx snd_ctrl     ; disable sound channels

            bit ppu_status   ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #0           ; reset counters, let main loop run once
            sta counter_lo
            sta counter_hi
            sec
            ror run_main

            bit ppu_status   ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #$3f         ; set palette (while we're still in VBlank)
            sta ppu_addr
            ldx #$00
            stx ppu_addr
-           lda palette,x
            sta ppu_data
            inx
            cpx #4
            bne -

            lda #$20         ; clear Name and Attribute Tables (VRAM $2000-$27ff)
            sta ppu_addr
            lda #$00
            sta ppu_addr
            ldy #8
--          tax
-           sta ppu_data
            inx
            bne -
            dey
            bne --

            lda #$00         ; clear PPU address
            sta ppu_addr
            sta ppu_addr

            bit ppu_status   ; wait until next VBlank starts
-           bit ppu_status
            bpl -

            lda #%10000000   ; enable NMI, show background
            sta ppu_ctrl
            lda #%00001010
            sta ppu_mask

            jmp main_loop

palette     hex 0f 12 22 30  ; black, dark blue, light blue, white

; --- Main loop -----------------------------------------------------------------------------------

main_loop   bit run_main        ; wait until NMI routine has set flag
            bpl main_loop

            ; ntdata_ptr = ntdata + counter_hi * $300 + counter_lo * $80
            lda counter_lo      ; ntdata_ptr = counter_lo << 7
            lsr a
            sta ntdata_ptr+1
            lda #$00
            ror a
            sta ntdata_ptr+0
            lda counter_hi      ; push counter_hi * 3 and clear carry
            asl a
            adc counter_hi
            pha
            lda #<ntdata        ; ntdata_ptr += ntdata + ((pulled byte) << 8)
            adc ntdata_ptr+0
            sta ntdata_ptr+0
            pla
            adc #>ntdata
            adc ntdata_ptr+1
            sta ntdata_ptr+1

            ldy #0              ; copy 128 bytes (4 rows) of name table (video) data to buffer
-           lda (ntdata_ptr),y  ; (NMI routine can read it faster from there)
            sta vram_buffer,y
            iny
            bpl -

            ; ppuaddr_mir = $2060 + (counter_hi & 1) * $0400 + counter_lo * $80;
            lda counter_hi      ; high byte: $20 | ((counter_hi & 1) << 2) | (counter_lo >> 1)
            and #%00000001
            asl a
            asl a
            asl a
            ora counter_lo
            lsr a
            ora #%00100000
            sta ppuaddr_mir+1
            lda counter_lo      ; low byte: $60 | ((counter_lo & 1) << 7)
            and #%00000001
            lsr a
            ror a
            ora #%01100000
            sta ppuaddr_mir+0

            ldx counter_lo      ; increment counters
            ldy counter_hi
            inx
            cpx #6
            bne +
            ldx #0
            iny
            cpy #frame_count
            bne +
            ldy #0
+           stx counter_lo
            sty counter_hi

            lda counter_hi      ; which name table to show
            and #%00000001      ; (1 on even complete frames, 0 on odd complete frames)
            eor #%00000001
            ora #%10000000
            sta ppuctrl_mir

            lsr run_main        ; clear flag
            jmp main_loop

ntdata      ; name table (video) data
            ; IIRC, I copied this from some video on https://tasvideos.org
            ; frame_count frames * 24 rows/frame * 32 tiles/row (tile = byte)

            ; frame 0
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 9a5a595555555555555555555555555555555555555555555555555555555555
            hex eaabaeaa5a5a5955555555555555555555555555555555555555555555555555
            hex fabbafbbaaaaeaaa5a5955555555555555555555555555555555555555555555
            hex 555550a0a5aaaaaaafabaa6a5a55555555555555555555555555555555555555
            hex 5555555566aaaaeaffffaaaaaaaa9a5a5a555555555555555555555555555555
            hex 5555555465aaaaaafafaaaaaaaaaa9a5a6ea5a5555555a5a5a5a5e5a6aa9a5a5
            hex 5659555556aaa9a5a5a5aaaa9a9a9a5966eaeaa9a6a5aaaaaaaa6e9a6a5a6a5a
            hex aaaaaaaaaaaaaaaaaaaaaa9aaaaaaa9a6aaaaaa9aaa5aaaaaaaaaaaaa6aa5555
            hex 66a9a669aaaaaa5a6a9966aaaaaaaaaaaaaeae99a555a5a5a5a5a5a565a55555
            hex a595a5a565aa99555595a6aaaaaaaaaaaaaaaa9a6a55aaa6aaaaaa9a5a5a5555
            hex 5555555555aaa9a5a4a0a060a6aaaaaaaaafaf9965a5a5a5aaaaaaaa6a9a5a59
            hex 55545050504000000000000022aaa9a594619555555555555555555555555554
            hex 0000000000000000000000001669955555555555515555555555555555505105
            hex 000000000000000000000001155555555451155a595505555555551555565a55
            hex 00000000000000000105555550555555515555a5555555554550505150505555
            hex 0000000000010515555555451005055510555451555455555544051555555555
            hex 0000010515541555555051555555555a415515555a59155545051055555a9a5a
            hex 055a6aa555555550541155566aaa999410515555a45155555545515555a5a5a5
            hex aeaaaeaaaaaaaa9a9aaaaaaaaaaa94a75961aeaaaa65aaaaaaaaaa6a9a95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa95ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 1
            hex aaaaeabbaaaaaa9955555555555555565a555555555555555555555555555555
            hex aeaeaaaaaaa6aaaaaa9e5a5555566aaaaa9a5555555555555555555555555555
            hex affefaabaaaaaabafaffffaaaaaaa5a6aaaa9659555555555555555555555555
            hex a5f5f6abaeaaaaaaaaaafabaaa595566a95aaaaa595555555555555555555555
            hex 5555545065aaaaaaaaaeafaa6a995066aaaaaaaaaa9a55555555555555555555
            hex 5555555555aaaababaffffabaa9a4a66aaaaaaaaa5a659555555555555555555
            hex 5555555055aaaabaaaeeeeaaaaaabaaa996a5aaa596599555555565a5a5f6f6a
            hex 5555555555aaaaaaaaaaaaaaaaeabbaaaaaaaaaa6666aaa5a5a5a5aaaa9a5b5a
            hex 5a5a5a5a5aaaaa59555655aaaaa6aaaaaaaaaaaa6a6aaaaaaaa9aaeaaaaafaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaabaaaaaaaaaaaaaaaaa66aa55aaaaaaaaaaaa
            hex 6aa9aa5a66aaab9a5aaa5a6aaaeaabaaaaaaaaaaaaaaaa555a5555555565a555
            hex a595a5a555aaaa99555555aaaaabafaaaaaaaaaaaaaaaa5aaa566aa9a5a9a5a5
            hex 5a59555555aaaaa9a5a5a0a0a0b0f5a5aaaaaaaaaaaaae55a5a5a5a5a6faeaaa
            hex 5a5955a450505000000000000000000066aaaaaaaaa9d9555555555555555555
            hex 0000000000000000000000000000000066aaaaaa955511555555555155555555
            hex 000000000000000000000000000000005a6565a955555555555555555565a555
            hex 0000000000000000000000000000000060a69995555555554504015405515554
            hex 0000000000000000000000000000001144004555455155555554555555555555
            hex 0000000000000000000000000000006654555aaa955555555545155555aaaaaa
            hex 0000000000000000000000000000015500105550515555555555505551556595
            hex 9e5a6e6a9a5a5a5a5a5aaa6aaa6a94679961aeaaaa65aa9aaaaaaa5a9a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa95ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 2
            hex abafaaaaaaa6aaaaaaab5e595555555aaeabbaffaafbd9a6a55a5aaaaaaaaa55
            hex afbefaabaeaaaaaafabbafeeaa5aaaaaaaaaaaaaafab9a5aaaaaaaaaaaaaaa55
            hex a5f5faabaea9aaaaaabaeafeeaaa655565aaaaafbaaaaaaaaaaaaaaaaaaaaa55
            hex 55545465a5a6aaaaaaabaaaaaaa6995555aabaefaaaaaaaaaaaaaaaaaaaa9955
            hex 55554505556aaaaaafbbeeeeaaaad95155bafaffaaaaaaaaa5aa995566a99555
            hex 5555555555aaaaaaaabbfffeaaaa9a5e19aaaaffaeaaaa95555a5a5a6aaa9955
            hex 6555554055aaaaaaaabaeaeeaaaaaeaaeaa6aaaaaaaaaaaaaaeaaaaaaaaa9a5a
            hex 55555555556aaaaaaaaaaaaaaa6aaaaaaeaaaaaeaaaaaaaaaaaaaaaaaaaaaa55
            hex aa5a5a5a5aaaaaaa55555a566aaaa6aaaaaaabaf66aaeaaaaaaaaaaaaaaaaaa5
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaeaeababafeaaaaaaaaaaaaaaaaaaaaaa55
            hex aaa9aa6966aaaaaa9a6a9a55aaaaeaaeaeaaaaaaaeaaaaaaaaeeabaaaaaaaa55
            hex aa55a9a555aaaaaa5565a565a5aaaaaaaaababaeaaa5aaaaaaeebbaaaaeeaa55
            hex 55555555556aa6aa5a5a5aaaaaa5faffefabfea5aaaaaaaaaaeaaaaaaaeeaa5a
            hex a5a565955566aaa550504000000000105060fb55a6eeeaaaaaeeabaaabeeaa95
            hex 5a55a4a050500000000000000000000000005000001062aaaaeebaaaaaeeaa55
            hex 0000000000000000000000000000000000000000000022aaaaaaaaaaaaeaaa55
            hex 0000000000000000000000000000000100000000000011aaaaaaaaaaaaaaaa55
            hex 0000000000000000000000000000005500000000000011aaaaaaaaaaaaaaaa51
            hex 0000000000000000000000000000129d45000000000011656595aaa6aaaaaa55
            hex 00000000000000000000000000001588000000000000229e59555555aaaa9951
            hex 9e5aae6a9a5a5a5a5a5aaaaaaa6a94a79951ae6a9a656aaaaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa55ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 3
            hex 5555a5b5faab9ea9aaaaaaaafffbefaeaaaaabbfffe9aaaaafbebbffffffffff
            hex 555555555565b5ea9aa5aaaaaabaeaaaaa6afffafaaabbaaebafaafaffffffff
            hex 5555550510505556aaaaaaaaafaaaaaaa6aeb5faaaaaafaaffffaaaafafff995
            hex 5555555555455566aaaeaaeeafbfeaaaaaea5566aaaabbaaffefaaaaaae91555
            hex 5555555555555566aaeaaaaafffffeaaaa995565aaaabbaafffeaaaaaa545454
            hex 5565955555504566aaaaaaaafffbeeaaaaaa5f5aaaa9a5a6aaaaaaaa95400541
            hex 5555555555555566aaaaaaaaaaaaaaaaa6eebaaabaaaaaaaeaeaaaa940105155
            hex 5555555555555566aaaaa9a5a5a5e5a6aaaabbaaabaaabaafafaa6aa5a5f6aaa
            hex aaaaaaaaaa5a5a6aaaaa9a5a5a5a6aaaa9a6aaaaaaaaabafffffaafaa9a5a5a5
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaa9aaaaaaaabaaabaaabbaafffeaaaa99555555
            hex a566aaa59a596aaaaaae9a6aaa5566a9a6aeabaaaba9aaa6aae9aaab9a5a5a5a
            hex aaaaaa26aaa95566aaeaa9a5a5a5a6aaaaaaaaaaaaaaaaaaeaaaeaaaa5a5a5a5
            hex 5555555555555566aaaa9955565a5a5a6aafafafafaabaeafbef9a5a5a555555
            hex 555555555a5a59965a6aaaa9a5a5a0a050a0b1f6faaafbeaffa9625fafaaaaaa
            hex 65a5a4905045061aaaa580000000000000000000005060a1f79922aaffbaffff
            hex 050a5a6a65a490500000000000000000000000000000000071901060b0a5fafb
            hex a4a0500000000000000000000000010400000000000000000000000000000010
            hex 0000000000000000000000000000164500000000000000000000000000000000
            hex 0000000000000000000000000000ba5044000000000000000000000000000000
            hex 0000000000000000000000000006960000000000000000000000000000000000
            hex 9e5aae6a9a5a5a5a5a5aaaaaaaaa94679951ae6a9a655a5a5a5aaa5a5a595a9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa55ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 4
            hex 5555555545001051556aaaaaaaafabaaaaaaaaa6bbfffafefbffaabafbaabbff
            hex 555555555555551555aaaaaaaaafbafaabaeaa6aaaeaaaaabffeaaaabbaabbff
            hex 555559555555555555aaaaaaaaeefbffafaeaaaaaaaaaaaaaaaaaaaabbaabbee
            hex 5555aa555555555555aaaaaaaaeebbfeffeefeaaaaaaaaaaaaaaaaaabaa5a5aa
            hex 555555555555051055aaaaaaaaeabbeeffaaeaaaaaaaaaaaaaaa995a5baaabee
            hex 555555555555555555aaaa9aaa5a6aaaaaa9eaa6eaaaaaaaaaaaa9aaaaaaaaaf
            hex 555555555555555555aaaaaaaaa5b5fafaaaaa6aaaaababaaaaaabaeffeafafa
            hex 5a5a5a5a5655555555aa9aaaa9555555555a5a6aaaaabbafabaa9a5bafaeafff
            hex 5aaaaaaaaaaaaaaa5aaaaaaaaa6aaa99aaaaaa9a6aaaaaaaaaaaaaaaffaabbff
            hex 66aaaaaaaaaaaaaaaaaaaaaaaaaaaa99aaaaaaaaaaaabafabaaaaaaabfaabbee
            hex 555a6aaaa59a5a6655aaaaaaaa6a9a55565a6a6aeaaaabafaaaa99aaaa9aaaaa
            hex 6aaaaaaa22aaa95555aaaaaaaea5a5a5a6aaaaaaaaaaaaaaaaaaa9aabaaaaafa
            hex 555555555555555555aaaaaaea15555555555a6aababafaaaa9abaeaffaeafaf
            hex 555555555155555555a6a5a5a6aaaaaaaaa9a5a5b6baffffffefaa9fafaeaaaa
            hex 55555a5a5a5aa9a5a0a69aaaaaa0505000000000000050a0f1e6aaaaffeafbff
            hex 65a5a050500001051a5aa9a590000000000000000000000000000050a0a1f6fa
            hex 000105065a5aaaa5a05000000000150000000000000000000000000000000000
            hex 5aaaaaa4a0500000000000000001694500000000000000000000000000000000
            hex a050000000000000000000000011d81000000000000000000000000000000000
            hex 000000000000000000000000015d850004000000000000000000000000000000
            hex 9e5aae6a9a5a5a5a5a5aaa5aaaaa9467a951ae6a9a655a5a5a5aaa5a5a595a9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa55ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 5
            hex 55555555550404555566aaaaaaaabeeebbfffbefaaaaaafbffffffffffffffff
            hex 55555555555545515566aaa9aaaaaaaaaaffbbeebbeaaabafffebafaffffffff
            hex 55555555555555555566a69a6aa5aaaabbffbbeabbaaaaaaaaaaaaaafafff995
            hex 55555555555555555566aaaaaaaaaa5aa9a5baeabbaaaaaaaaaaaaaaabe91555
            hex 55555555555555555566aaaaaaaaaaaaebab9b5aa9a5baaaaaaaaaaaaa545450
            hex 55555555555555555566a5aa65a9aa55a5a5b6faaaaaaaaaaaaaaaaa94400501
            hex 5a595555555555555566aaaaaa9aaa5555555555565aaaaaaaaaabae5f5b5555
            hex aaaaa9aaaaaa5a595a6aaaaaaaaaaa5a5a6aaaaaaaaa66eaaaaaabaeaeaaaaba
            hex aabaaaeaaaaaaa9aaaaaaaaaaaaaaaaa99aaaaaaaaaaaaaaaaaabaaaeaaaa9a5
            hex aaaaa9aaaaaaa6a9aaaaaaaaaaeeaaaa9966aaaaaaaaaaaaaaaafaeaeaba9955
            hex 5a6a955a5a5a6699a5aaaaaaaaaaaa5a55565a5a5a5abaaeaaaabbaaeeba9a5a
            hex 6aaa44aaaaaa95555566aaaaaaaaaaa5a5a6aaaaaa5aaaaaaaaaaaaaaaa6a5a5
            hex 55a54555555555555566aaaaaaaaea555455555555556aaaaaaaaa9a5a5a5a5a
            hex 55555555555555555566aaaaaaaaaa565a5a5a6aaaaaaafbeaffffefafafafae
            hex 55555455505155555565a6a9a9a9aaaaaaaaa5a4905050a0a1f6faeeffffffee
            hex 55555555555a5a6aaaa65a565aaaa59050000000000000000000005060a0f5ea
            hex 555a5a6aa9a59050000061aaaa99590000000000000000000000000000000000
            hex a9a59050000000000005166aaaa6984500000000000000000000000000000000
            hex 000000000001055a6aaaa5904026440000000000000000000000000000000000
            hex 00000105555aabaaa45000006b9e450b09000000000000000000000000000000
            hex 9e5aaeaaaaaaaa9a5a5aaaaaaabaa4b69951ae6a9a655a5a5a5aaa5a5a595a9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa55ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 6
            hex 555555555555555566aaaaaaaaaaaaaaaaaaaaaaaaaabbfffffffffffbffffff
            hex 555555555555555555aaaaaaaaaaaaaaaaaaaaaaa9aabbffffd4514504b1ffff
            hex 555555555555555566aaaaaaaaaaaaaaaaaaaaaaea59bbf9951504501051b7ff
            hex 555555555555555566aaaaaaaaaaaaaaaaaaaaaa65aaa91555001005550461ff
            hex 555555555555555566aaaabbaaeeaaaaaaaaaaaa5555455054114511545000b2
            hex 5a59665a5555555566aaaabbaaaeaafbaaaaaaaaaaaa44050150515445000010
            hex a6aa99aa5aaaaa566aaaaabbaaeeaabbaaaaaaaa9fae49155545104000000000
            hex 6aaaaaaaaaaaaaa5aaaaaabbaaaaaabbaaaaaaaaaaaaaa9a5e5b5e6baaaaaa44
            hex aaaaaaaaaaaaaa59aaaaaabbaaaaaabbaaaaaaaaaaaaaaa9a5a5a5baaafaaa44
            hex a5aa95aa555a5a556aaaaabbaaaeaabbaaaaaaaa5a5aaa99555551baaaaaaa44
            hex a5a5a6aa5aaaaa5aaaaaaabbaaeaaabbaaaaaaaaaaaaaa9a5a5a6afaaafaaa99
            hex 555555555555555566aaaabaaaaaaabbaaaaaaaaa5a5a5a5aaaaaaaaaaaaaa9a
            hex 555555555555555556aaaaaaaaaaaabaaaaaaaaa555aaaaaffaaafafafabafaf
            hex 555555555555155555aaaaaaaaaaaabaaaaaaaaaaaaaa5aafbaaffffffbbffff
            hex a59555555555500511aaaaaaaaaaaaaaaaaaaaaaa9500000105060a0a0b0f5f5
            hex 555555505555555a5966aaaaaaa955a6aaaaaaaa000000000000000000000000
            hex 55540555566aaaa99565a5a966569866aaa9aa55000000000000000000000000
            hex 55155555555555555559555565664411aa99a56a000000000000000000000000
            hex 0155555555555556aa9a59656b594402aa9956aa000000000000000000000000
            hex 5554515669965aaaaaaaaaaafaffafffa59a6aaa000000000000000000000000
            hex ae5aaeaaaaaaa6a9a9aaaaaaaaaaa4a69961eeaa9a655a5a5a5aaa5a5a595a9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eaaa99556a9aaaaaaea9aa95ba99
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaaaaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa5a555b595

            ; frame 7
            hex 55555555555555555555555555555555555555555555555555555555555556ff
            hex 5555555555555555555555555555555555555555555555555555555555557bff
            hex 555555555555555555555555555555555555555555555555555555555556ffff
            hex 56aa5a55555555555555555555555555555555555555555555555555557bffff
            hex 66aaaa65955a5555555555555555555555555555565a5a5b5f6aafaeaabaffff
            hex 69a65a56aaaaaa95555555555a5a5f5e6aaaa9a5a5e5a5a5a5565a5a5a54b6ea
            hex 96aaaaa6aaaaaaa9a6a9a5a5aaaaaa9a5a5a5a5aaaaaaafafaaafaaaea8421aa
            hex aaaaaaa6aaaaaa9966a9aaaafaeaeaaaaaaa9555aaaaaaaaaaaaaaaaaa9a0055
            hex aaaaaa66aaaaaa996699aaaaaaaaaaaaaa9a5556aa9aaaaaaaaaaaaaaaa90014
            hex 55a59555565a5a5556595555a595a59555555555555555555555565a59690010
            hex aaaaaa5aaaaaaa59669965a5a9a5a9a5a5955555a5a5a5a9a6aaaaaaa9aa5555
            hex 55559555a5a5a5a5a5a5a5a5baaafaaaaaaaa9aaaaaaaaafaf5aafaf9e595555
            hex 5555555555555555555555555555955555555555555555559555a5a5a5a5a5a5
            hex 555555555555565555555555555555555051555555455555955555555565fafb
            hex 555555555551545555555451155a5a59555555555450500504554555555669aa
            hex 5555051a5a5555555554555155555455555555555555555555565a5955545565
            hex 5555545155555555500155155551491155155155454515555565a6a955555555
            hex 555401544000145544555555405688515a995555555555555555555554555555
            hex 04005515555555555555555545154410a5519565555555550411450055555555
            hex 5155555555555555555155556a5a450749105155555555505554500010555050
            hex aeaaaeaaaaaaaaaaaa6aaaaaaaaaa4b69961aeaaaaa5aa5aaa9aaa5a9a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 8
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 5a59555555555555555555555555555555555555555555555555555555555555
            hex aaaaa95a5a555555555555555555555555555555555555555555555555555555
            hex aaaa95a5965a5955555555555555555555555555555555555555565a5a5a5b5f
            hex 9a5a5566aaabaaa99555555555555a5a5a5a5a5a5a9aaaaabaaabafaf5e5a5a5
            hex aaaaa5a6aaab6aaaa9baaaa5aab9f5a5a5a5a5955555565a5a5a5b5fafaeabaf
            hex aaaaa9aaaaaaaa9a55aa5a5aaeaaabaafeeaaaeaa999a6aaaaa9aaaaaaaaaaaa
            hex aaaa99aaaaaaaaaa55aa55aaaaaaaaaaaaaaaaaa999565aaaa99aaaaaaaaaaaa
            hex a9a595a5a5a5a5a555a55566a9aaaaaaaaaaa6aa995555a6aa99aaaaaaaaaaaa
            hex aa9a595a5a5a5a59555a59565a5a5a5a5a5a5a5a555555555555565a56555555
            hex aaaa9a6aaa6a9a9a5a6a5565a9a5a5a5a5a5a5a595555565aaa6aaaaaaaaaaaa
            hex 555555555565a5a565a5a5a5a5bafaaafaaaaaaaaa9a6a6aab5a5b5f5f5a5a5a
            hex 555555555555555555555555555555555555555555555555a5a5a5a5a5a5b5fa
            hex 50515555455555555555555555505555554455555a55555555545055655565a5
            hex 5955555555554401050515551555a55555555450555451555551455455a59555
            hex 555555555055555a6aa95555555545104001051555551555aa55555555555450
            hex 55555515155565955551555555555905555555565a5555515555055555545005
            hex 55545144515555555554555555558410555566aaaa9555555555555545040040
            hex 51050500505041555544505516594401155565a5a55555105555555555554510
            hex ae5aaeaaaa6aaaaaaaaaaaaaaaaa9467a961aeaaaaa5aa5aaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 9
            hex aaaaaaaaaaaaaaaa595555555555555555555555555555555555555555555555
            hex a6aaaaaaaaaaaaa9955555555555555555555555555555555555555555555555
            hex 65a5a5a59555555a595555555555555555555555555555555555555555555555
            hex 5a5aaaaaaaaaaaa9555555555555555555555555555555555555555555555555
            hex a5a5a5965a5a5a5a5a5aaaaa5955555555555555555555555555555555555555
            hex aafaeabafae5a5a5a55555555555555555555555555555555555555555555555
            hex 5a5a5e5b5f5e6baaaa6aaaaaea965a5a5b5e5a5f5f9f5aafafaf9a6bafaaaa9a
            hex aaaaeabaaaaaaaaa6655a6aaaa65a5a5a5a5a5e5a5a5a5a5a5a5a5a5a595a595
            hex aaaaaaaaaaaaaaaa5a5556aaaa565a5a5b5a5a5f5f9f9aafafaf5a6b9f5a5a59
            hex aaaaaaaaaaaaaaaaa95566aaaa65a6aaaaa9aaaabaeaaafaaaaaaaaaaaaaa595
            hex a6aaaaaaaaa9aaaa955566aaaa5565aaaa99aaaaaaaaaaaaaaaaa9aaaaaa6555
            hex 65aaa9a6aa99a6a9555565aaaa555566aa99aaaaaaaaaaaaaaaa9966aaaa5555
            hex 5a5a5a5a5a5555555555555555555565a595a5aaaaaaa5aaaaaa9966aaa95555
            hex aaaaaaaaaaaaaaa9959565aaaa99555a5a5a5a5a5a5a565a5a5a5a5555555555
            hex 5a5a5a6aaaa5a595555555a6a9995565aaaaaaaaaaaaaaaaaaaaaaaaaaa99555
            hex a5f5e5bafaeabaaaaa5a9a5a5e5a5a5a5a5a5a5a5a5a565a5a5a555659555555
            hex 5565a55555555555555595a5a5a5a5a5b6e9aafafafaaafafafaaabaeaaaaaaa
            hex 50514505051565905554545555555544565555595a5a595a595a565555555555
            hex 565a555555555504401555555555665444000155555555655554505050515555
            hex a5955555555554515556aa995555550011455555565a59555555550500555555
            hex aa5aaeaaaaaa9a9aaaaaaaaaaaaa94675961aeaaa9a5aa9aaaaaaaaa9a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 10
            hex 55555555555556a956aaaaaaaaaaaaa995565aaa9555555555555aafbffeaaaa
            hex 55555555556aa66aa966aaaaaaa5555a6aaaaaa95555555aaaaaaaaaaaa59555
            hex 55555555659bbaaa9966a965565aaaaaa9955a5a6aaaaaa9a55555555555655a
            hex 5555555566aaaaaa95555a6aaaa9a55a5aaafea9a595555555555a5aafaf99a6
            hex aa9a5a5566aaa5565965a5965b5ebffae9a59555555a555aaaaabafafaaa9966
            hex aaaaaaaa555a6aa5565aaabaf9a5a55a5a5aafaaaaaa95aaaa66aaaaaaaa9965
            hex 65a6aaaa669a6baaa595565a6faefffaeaa6aaaa6aa55565a566aaaaaaaa9955
            hex 6aaa9a5aa5aa5b5aaaaaaaaaaaaaaaaaaa66aaaa95555555566aaaaaaaaa9966
            hex 6aaaaaaaa6baaaaa9966aaaaaaaaaaaaaa66aaaa59555555aaaaaaaaaaaa9966
            hex aaaaaaaa66aaaaaa9966aaaaaaaaaaaaaa66aaaa9a555555a6aaaaaaaaaa9966
            hex aaaaaaaa66aaaaaa9966aaaaaaaaaaaaaa66aaaaaa55555565a6aaaaaaaa9955
            hex 565a5aaa5565a5a59565aaa6aaaaaaaaaa66aaaaa6555555566aaaaaaaaa9955
            hex 6aaaa9a565aaaa9a595659555555a5a5a565a5a6a55555555566aaaaaaaa9955
            hex 5555555566ab6aa99555aaaaaa9a5a5a5a555555555555555555a5a5a6aa9555
            hex 555555555565a5a6aa5a5aa5a6aaaaaaaaaaaaaa5a5555555555555555555555
            hex 55555155555155555565a6abaf5a69a5aaaaaaaa5555a595669a9a5a5a555555
            hex 555a55555555555555505555a5a6faa99a55a5a5555555555555aaaaaaaaaa9a
            hex 5555555544050545554516596595594561aaeb9e5a5555555555aaaaaaaaaaaa
            hex 55545115565a955555555455555555995155a5a5a6aa595a595565a5aaa6a6aa
            hex 551555a5a55555555555404000541544005196595565a5aaaaaa9a5a5a5565a5
            hex aeaaaeaa9a6aaaa9a9aaaaaaaaaa94a79961aeaaaaa5aaaaaaaaeaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 11
            hex 5555555555555555aaaeaaaaa95565aaa556affefaa996555a6fbffffafaeaaa
            hex 5a555555555555556aaaaa95565555566eaafaa595566aabfffffaaaaaaaaaaa
            hex aaa65a5555555555aaaa956a99555abae9a5555aafbfaabafaaaaaaaaaaaaaaa
            hex aaaa5a6596595555a996aa955aaaa555565aaffefafaaaaaaaaaaaaaaaaaaaaa
            hex a9aaa9a5aaaa9a595aa95baaa555566baeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 5a595555aaaaaa995aaee5565aaaaaaaaa66aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 9a6a5955566aa5a9a55aaeaaaa5566aaaa66aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 5aaaa9a5a6aaaa9aaaeaaaaa9a5556aaaa66aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex aaaaaaa5aaaaaa9aaaaaaaaaaa5566aaaa66aaaaaaaaa9aaaaaaaaaaaaaaaaaa
            hex aaaa9955aaaaaaa9aaaaaaaaaa5566aaaa66aaaaaaaa99aaaaaaaaaaaaaaaaaa
            hex a9a5a555a5a5a595aaaaaaaaaa5565aaaa66aaaaaaaa99aaaaaaaaaaaaaaaaaa
            hex 5a5a5955a6aaaa9a5a555555555595a5a966aaaaaaaa99aaaaaaaaaaaaaaaaaa
            hex aa6a9a66a6a5a595a6aaaa9a5a555555555555a5a5a59565aaaaaaaaaaaaaaaa
            hex a555555555555555aa9ea5a6995565aa9a5a5a595555555555555565a5a5a5a5
            hex 555555555555555555a5eb5a595555aaaaaaaaaaaaaa5a5a5a59555555555555
            hex 5555054505055555555556a5a69a5a65a5aaaaaaaaaaaaaaaaaaaa9a5a595555
            hex 5555555550505155555554555555a6aa9659a5a6aaaaaaaaaaaaaaaaaaaaaaaa
            hex 5555514555555555555a59455555555514a6af5a69a5a5aaaaaaaaaaaaaaaaaa
            hex 155a5aa9a555555554515555555455664465bafbef9e5955a5aaaaaaaaaaaaaa
            hex 55555155555555545054505150500555001159a5aafaaaab5e5965a5a6aaaaaa
            hex ae9aaeaaaaaaaa9aaa6aaaaaaaaa94679961eeaaa9a5aaaaeaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 12
            hex aaaa5aa59a555555556696bf9956bfea99aaaaaaaa6699995555555555669955
            hex aaaaa5a66aa65a5555566aa56affaaaa99aaaaaaaa6699995555555555669955
            hex 65a55555aaaaaaaa596a956beeaaaaaa99aaaaaaaa66a9995555555555555555
            hex a65a5555a6aaaaaaaa966aeaaaaaaaaa99aaaaaaaaaa99995555555555555555
            hex ae5a55555a59a6aa9abaaaaaaaaaaaaa99aaaaaaaaaa99555555555555555555
            hex 5aa5a5a66aa9aa5a99aaaaaaaaaaaaaa99aaaaaaaa9a99555555555555555555
            hex baaa9a5a5aa9aaaa9a66aaaaaaaaaaaa99aaaaaaaa6a99555555555566555555
            hex aaaa5955aaaaaaaa9aa6aaaaaaaaaaaa99aaaaaaaaaa995599555555aa555555
            hex aaaa5555aaaaaaaaaa66aaaaaaaaaaaa99aaaaaaaa65995599555555a6555555
            hex aaaa5555aaaaaaaaa966a6aaa9aaaaaa9566aaa5a95555555555555565555555
            hex 555955555a5a5a5a5a5555555555555555555555555555555555555555555555
            hex aaa95555a6aaaaaaaaa6aaaa5a5a5a5955555555555555555555555555555555
            hex 6aaaaaa5a5a5a5a59566aaaaaaaaaaaaaaaaaa5a9a5555555555555555555555
            hex 9555555555555555555a69a6aaaaaaaaaaaaaaaaaaaa9955565a555559555555
            hex 50555550555555555565ab9f59a5a6aaaaaaaaaa9a55555565a5a5aaaa555566
            hex 5515555555555555565a65b6eaaf5a55a5a5aaaa995555555555555555555555
            hex 51505050555451555555655a65bafbae595565a5a95555555555555555555555
            hex 5555555550410505541555549559a5ea55219e59555555555555555555555555
            hex 55555555565aa9555555555505665a559911fbaf9a5555555555555555555555
            hex 555555505055555555554055515565994400a6aaaaab9a5a5555555555555555
            hex ae5aaeaaaa6aaaaaaaaaaaaaaaaa94a79951aeaaa9a5aaaaaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efbf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 13
            hex 55555565aaaaaaea6a9a55555566aaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 555555565565aaaaba9aa5a55566aaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex aa5a5a65aa5a69a6aaaaaaa96666aaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 5955a5aa9a69a69a69a5aa9956aaaaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex aa995a59a5a6ab6ea59a595565aaaaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 6955a5a6aa9a5aa9a69a9a5555aaaaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 99555666aaaaaaeaab9aa9e9556aaaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 9555666aaaaaaaaaaaaaaaa955aaaaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 555555aaaaaaaaaaaaaaaa995666aaaaaa55aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 555555a6aaa6aaaaaaaaaa995565a5a5955555a5aaa5aaaaaaaaaaaaa5aaaaa9
            hex 555555555555565a5a5a5a595555555555555555555555555555555555556555
            hex 55a555a6aaaaaaaaa6a9aa995555555555555555555555555555555555555555
            hex 55555555aa5a6baeaaa9a5a6565a5a5a55555555555555555555555555555555
            hex 5a5aaaaab9a5a5555555555555a6aaaaaa6aaa5a5a5955555555555555555555
            hex a555555559555545055555555565aaaaaaaaaaaaaaaaaaaa9a5a5a5a55555555
            hex 5555555555555550505050515556aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a
            hex 1555555450514555555555555565aaaa9954aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 55555555555aaaa5955555559a5565aa564566aaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 515455555555515555555555aaaa5a55654051aaaaaaaaaaaaaaaaaaaaaaaaaa
            hex 51555554554155555565555565a6eb9a550411aaaaaaaaaaaaaaaaaaaaaaaaaa
            hex ae5aaeaaaa6aaaa9a9aaaaaaaaaaa4a69951aeaaa9a5aaaaaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55efff55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 14
            hex a5baef5a65aa9a59a6aaaaaaaaaaaaaaa5a5566aaaaa955555a966aaaaaaaaaa
            hex 5565a5a6ab5aa6aa5aa5aa99aaaaa9955a6aaaa9a55555555595aeaaaaaaaaaa
            hex ab9e5a55a6fa9f69a69a6595a5565aaaaaa55555565a55555566aaaaaaaaaaaa
            hex aabafaaa5a59b6ea9fa996596aa9a59555555555bffff95555aaaaaaaaaaaaaa
            hex aaaaaaa9baef9f59b5ea6a555555575f5d55555555565a5aaaa6aaaaaaaaaaaa
            hex aaaaaa99aaaabaeaaf5aa5a69f5e69a5955a5aaaaaaaaaaaaa66aaaaaaaaaaaa
            hex aaaaaa99aaaaaaaaaaaaaa5a6aaafaaaabbeaaaaaaaaaaaaaa66aaaaaaaaaaaa
            hex aaaaaa59aaaaaaaaaaaaaaaabafaffaaabaaaaeaaabaaaf5aa6aaaaaaaaaaaaa
            hex aaaaaa99aaaaaaaaaaaaaaaabaaaffaaa966aa6eaaafafaeea66aaaaaaaaaaaa
            hex aaaaaa55aaaaaaaaaaaaaaaaaaaaffaaeaaaaaaaaaaaaaaaaa66a9aaaaaaaaaa
            hex aaaaaa55aaaaaaaaaaaaa5a5a6a5faa6aaaaaa6aa596aaa9aaaa99aaaaaaaaaa
            hex a5a5a5555555555555565a5a6aaaafaaaaaaaaaaaaabaaaaa96595a6aaaaaaaa
            hex 555555565a6aaaaaaaaaaaa5aaaaafaaaabaebffaffeeaaa9a555555a5aaaaaa
            hex aaaaaaaaaaaaaaaaa5aa6aaafaeaeaa5a6aaa9aaaaa9a5a6aba6595555555555
            hex aaaaaaaaaaa5965abffaa5555a555567baaf9a6a99b5a6aaaa66aa9a59555555
            hex aaaa95555aaffee9965555545050555555545555955555565966aaaaaa5a5555
            hex 555aafaabae99669545515565a59555555456155555565a5a559a6aaaaaa9a59
            hex aafaaa95566995555555555555515555568845105155555555a659aaaaaaaaaa
            hex a595566554011515555550515551555555440055555555555565de66aaaaaaaa
            hex 5569954555555554510555565515556a5a450b595aaa9a555555a65aa6aaaaaa
            hex aa9aaeaaaaaa9a99a9aaaaaaaaaa94a6a9a1feaaa9a5aaaa9a6aaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55efff55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 15
            hex ef9e65aa9a55555555565aaaaaaaaaaaaaaaa5a595555555555556aaaa955555
            hex bafb9e59a69a55aaaaaaaaaaa9a5a595555555555555555555557bed555556ab
            hex 55a5faaa5a955565a5955555555555555555555baf5f59555556ff99566abaaa
            hex af5a65a5ba9a59555555555b5a555555555576fbfff99555557fea9aaaaaa6aa
            hex fafbaf5a65a6fbaf5e5565f6fbe9555555555555555a5a5a66ea7fedaa5566aa
            hex aaaabaaaab5a65a5faab5f565a5a5a6aaaaaaaaaaaaaaaaa656bffd96555a6aa
            hex aaaaaaa9aaaabbafafaafaaaaaafbfaaeaaaaaaaaaaaaaaa66feff9955596aaa
            hex aaaaaa99aaaaaaaafebbffaaabaea6a6abaaaaabaaafaeaa66aaff9955aaa6aa
            hex aaaaaa99aaaaaaaaeebbffaaaaaa66aae9a6aaa9aaa5a6aa66aaff9955aa6aaa
            hex aaaaaa99aaaaaaaaeebbffaaab896aaaaeaaaaffefeffaaa66aaff9955a6aaaa
            hex aaaaaa99aaaaaaaaeabbffaaaaaaaaaaaeaaaaaaaaaaaaaa66aaff9955666aaa
            hex aaaaaa99aaaaaaaaaabafaa6aaaaaa669aa5a595aaa6a6aa66aaff995566aaaa
            hex aaaaaa99a595a555565a6ba9aaaaaaaaaaaaaaaaaaaaaaaa59a6fb995566a6aa
            hex aaa99555555a6aaaaabbfa9aaaaabaeeabafabbfaabaaa669659a59555656aaa
            hex 5555565aaaaaaaaaaaabbfa9aaa6f6fbfefafaaaaaaaaa9aa9aa9e55555565aa
            hex 5aaaaaaaaaa99aabfffaaa95a5b5a6e9a545a6ae69a9aaeaaaaaff9955555555
            hex aaaaaaa9566afae5aaa55559551a5f5a559815a5a5a5e55aa9eeeaaa55595555
            hex aaaaa956baa556555555555576e9b5fa554411555555555955abae995565aa9a
            hex aa966baaa55556aaa6a9555555555556594401555555aaef99aaef99555566aa
            hex 56afee956555550150505554555555a6aa9bbf95555565a59555bb9d555565aa
            hex aaa6aeaaaaaa9aa9996aaaaaaaaa9467a9a1eeaaaaa5aa9aaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55efff55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 16
            hex aa9a5aa5555566a59555555555555555555555555557af5f595555555567fffe
            hex a5a6eb5a555555555555555555555555555555556ffffffff955555556bbfea6
            hex 5955a6aaaa5a5555555556af5f5a555555555555b5f6f99555555556bfaa96bf
            hex aa9a5955b6fbef9e595575fafbfd5555555555555555555a565a59bbe99abfff
            hex aaaaeb9e5965a5fbee9f595555555a5a5a5a6aaaaaaaaaaaaaaa99a56bbbffff
            hex aaa5aaaaaaaf5f5aaafaff6aaaaaabbaabaaaaaaaaaaaaaaaaaa996bffbaffff
            hex aa55aaaaaaaabaffeeafae66aafafaeaaaaaaaaaaaaaaaaaaaae99aaffaaffff
            hex aa55aaaaaaaaaabbaaffffaaaaea559aaaefaaaaabeebaebaaaa99aaffaaffff
            hex aa55aaaaaaaaaafbaafbffaaaaaaa6aaaa99aaaa9a6a9a566aaa99aafbaaffff
            hex aa55aaaaaaaaaabbaabbffaabb9e16aaabfaaaaaffffbffafaaa99aabbaaffbf
            hex aa55aaaaaaaaaabbaabfffaaaaaaaaaabbaaaaaaaaaaaaaaaaaa99aabaaaffbb
            hex aa55aaaa6aaaaaabaafffaa6aaaaaa99aaa5a6aaa9a6aaa5a6aa99aaaaaaffbb
            hex aa55aaaaa6aaa5a595a55a6aaaaaaa9aaaaa9a5a6aaaaa9a6aaa99a6aaaafebb
            hex a955a55555555a5aaabffa99aaaaaa9faaaaaaaaabaeaabbaaa69a5965a6eabf
            hex 555555566aaaaaeaaabaaaabaeaaaffbebefafaffefaaabbaa6a99a69e5965a6
            hex 555a6aaaaaaaaaaaaabffea9ab5aaaa6fa94a7aaabaaaeaaaaaa5a66aaaa9a59
            hex aaaaaaaaa656abbffeeaa965a5a5e5f5955921a6af5a5665aaeaea6aaaaaffae
            hex aaaaaa9566bffaeaa9a5565a5555165955845055a5e5f5baea5a6ab7aeaaffbb
            hex aaa9566aaaa556a55555555556affaef554400655955555555555565fbaafaaa
            hex 9556bea95569555a55555555659555aa9b4a6f9995555555565a5a65b6abaeaa
            hex aeaaaaaaaaaaaaa5a9aaaaaaaaaa94a6a9a1eeaaaaa5aaaaaaaaeaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55efff55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 17
            hex afaaa6e9aaaaaaffbbfafaaaaaaabb99aaaaaaaaaaaaaaaaaaaaaaaaaafaaeaa
            hex ffffaf9a6aaaaaaaaaa9ab9aaaaabbaaa6aaafaaaaabaeaaabafafafaaaaaaaa
            hex ffffffeea6aaabafaa55aa9566aabfafaeaaaaaafbffeeaabaeafaeaaaaaaaaa
            hex ffffffea6aaaaaeeaa55aaaaaaaafaa9aaaaaaaaa9a5a6aaaa55555566aaaaaa
            hex ffffffaa66aaaaaaaa55aaaaaaaa55556aeaaaaa9a5aaaaaaa9a5aafaeaaaaaa
            hex ffffffaaaaaaaaaa5451aaaaaaaaafafaaaaeaaabfffefaebfeffffeffaeaaaa
            hex ffffffaa6aaabfae4555aaaaaabffafafbaaaabafafafaeaaaaaaaaaaaeeaaaa
            hex bbffffaaa6baaaaaaabaeaaaaaffaaaabbaaaaaaaaaaaaabaaabaaaaaaeeaaaa
            hex bfffffaa6aaeaaaaaaaaaaaaaabaaeaabbaaaaaaaaaaaabaaaaaaaaaaaeeaaaa
            hex fbffff9966aaaaaaaaaaaa5a6abaeaa5baaaaabaa9a996aabaaaaaaaaaeaaaaa
            hex aafbfa99a6aaaaaaaaaaaa5a6a9a5a5a69a5a5a659556aaaaa51555455aaaaaa
            hex a5a595556aaaaaaaaaaaaa5a6aaaaaaa595555556aaaaaaaaa7be956aaaaaa9a
            hex 5a5aaa9aa9a6aaaaaaaaaabaaaaabaaaaaaaaaaaaaaaaaaaaaaaafeaabaaeaaa
            hex bafbfeea9566aaaaaaaaaa5a6aaaaaaaaaaaaaaaaaaaaaaaaaaabbaaaaa5aaaa
            hex aafbeeaa95bbaaaaaaaaabffaaaaaaaaaaaaaaaabfffefaaaaaabbaaa9555aaa
            hex aabaaa9a9eaaaaaaaaaaaafbefabffefafafafbffffeeaaaaaaabbaaaa9a5aaa
            hex aaabafaefafaa9aaabefafafafbbfafaf960fafaeaa5aaaaaaaaaaaaaaaaae65
            hex ffffffeaa9a69f595a5659a6bafafafa964477aaafafaaafae5a6aaaaaaaea5a
            hex fffaa6a9a6aabaabdfaf5bffeaaaaaaa6540629e65a5a5b5e5e5b6fefbffefaf
            hex aa5aaa956555515565a5f5f595565a5a550021baffd95aa9465e55565aaa6aa9
            hex aaa6aeaaaa9aaaaaa9aaaaaaaaaaa4a69951aeaae9a5aa9aaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55afbf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 18
            hex aaaa9566aaaaaaaaaaaaabafaaaaeabafaaaaabfffffffffeeafbbfefafebaea
            hex aa505065aaaaaaaaaabfffffffaeaaaaaaaabafafafafafaafeaaaaaaaeeaaee
            hex aa545155aaaaaaaabbfeeabaaafaaaaaabaaaaaaaaeaaaaaabaeaaaaaaeeaaee
            hex aa060a5baaaaeeaabbeeaaaaaabbaaaaaaaaaaaaaaaaaaaabbeeaaaaaaffaaaa
            hex baeaeafaaaaaaaaabbeeaaaaaabbaaaaaaaaaaaaabafaeabbbabaaaaaafbaaaa
            hex aaaaaaaaaaaaeeaaaaeeeeaaaabbaaaaaaaaaaaaaaaaaaaaaaaaeaaaaabaaaaa
            hex aaaaaaaaaaa9e5aaaaeeeeaaaabaaaaaaaaaab996699aa55abaaaafaaaaaaaaa
            hex afaaaaaaaa9a1aaaaaeaeaa5a5aaaaaaaaaaaaa9a5a5a566aabaaaaa9a6aaa9a
            hex aaaaaaaaaaa9a5aaaa555555556aaaaaaaaaaa9a555556aaaaaaaaaa50515555
            hex aaaaaaaaaa9a5aaaaaaa9a5a6aa95555555555a5aa5aaaaaaaaaaaaa456faf9a
            hex aaaaaaaaaa9955aaaaaaaeaaaa555555555555566aaaaaaaaaaaaaaa6affe9a6
            hex aaaaaaaaaaaaaeaaaaaaeeaaaaaaaaaaaa6aaaaaaaaaaaaaaaaaaaaaaaee5a6b
            hex aaaaaaaaaaaaeaaaaaaafeaaaabaaaaaaaaeaaaaaeaaaaaaaaaaaaaaaabafaff
            hex aaaaaaaaaa9955aaaaaaeeaa6aaaaaaaaaaaaaaaeeaaaaaaaaaaaaaaaaaaaaff
            hex aaaaaaaaaaabaeaaaaaaeeaaaaaaaaaaaaaaaaaaeeabafaaaaaaaaaaaaaaaaff
            hex aaaaaaaaabffefaaaaaaeeaaaaaaaaaaaaaeaaaaafffffefaeaaaaaaaaaaaaff
            hex aaaaaaaaaafbffaeaaabefaeaaaaaaaaa9a2abbffffffffeeeaaaaaaaaaaaaff
            hex a9aaaaaaaaaafbeeabffffffffffffbe9655fbffffffeeaaeaaaaaaaaaaaaaff
            hex aabbffffafafafaaaafafafafbffffedba50b7faffeaaaaaaaaaaaaaaaaaaaba
            hex 5955a4b1f5f6fbfefbffafafaeaeae99950062baaa59a6aaaaaaaaaaaaaabbaf
            hex aaa6aeaa9a5aaaa9a9aabaaaaaaae4a79951aeaaa9a5aaaaaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a6a9
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55afbf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 19
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaafaaaabbeeffefeeaaaaaaaaaaaabbaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaffaaabffaaaaaaaaaabbaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbeaaaaaaaaaaaaaaaaabaaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5a6bbaaaaaaaaaaaaaaaaaaaabaaa
            hex aaaaaaaaaaaaaaaaaaaaa9a5aa9955aaa95556aaaaaaaaaaafafaaaaaaaaaaaa
            hex aaaaaaaaaaaaaaaaaaee9a5aaaaa6aaaaa55aaaafaffaaaaaaaaaaaaa5a5aaa9
            hex aaeaaaaaaaaaaaaaaaaaa5a5a5a5a5a59555aaaaaafbaaaa9a5a5a5a5a5aaa9a
            hex 65aaaaaaaaaaaaaaaaaa555555555555556aaaaaaaaaaaaaaaaaaaaaaaa9a5aa
            hex 66aaaaaaaaaaaaaaaaaa56555555555556aaaaaaaaaaaaaaaaaa955050505050
            hex aaaaa9a5a5a5a5a5a6aaaa9a59555556aaaaaaaaaaaaaaaaaaaa550000005555
            hex aa555555555555555565aaaa9a5a56aaaaaaaaaaaaaaaaaaaaaa5905055a6aaa
            hex a9555555555555555555a6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa995566ffffff
            hex 9955555555555555555566aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9955aaffffff
            hex aaaaaaaaaa9a5a5a5a5a6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9a6aaaffffea
            hex aaaaaaaaaaaaaa6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaafffa95
            hex aafbaaaaaaaaabaaaaaaaaaaaaaaab9965aaaaaaaaaaaaaaaaaaaaaaaaef9a5a
            hex aaaabbaaaaaabbeeaaaaaabaaaaaaa6a55a6aaaaaaaaaaaaaabaeaaaaafbffff
            hex baaaaaaaaaaabaaaaaaaaaabaaaa9aa90066aaaaaaaaaaaaaaaaaaaaaaaaaafa
            hex aaaaaaaaaaaaa6aaaaaaaaaaaaaa9e550026aaaaaaaaaaaaaaaaaaaaaaaaaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaeaaaaffef6feea6aaaaaaaaaaaaaaaaaaaaaaaaab
            hex aaa6aeaaaaaaa6a9a9aabaaaaaaaa4a6e9a1aeaaa9a5aaaaaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 20
            hex 66aaaaaa59aaaaaaaaabaeaeaaaaaabafaaaaababaefaaaaaabbaaeeaaaaaaaa
            hex 66ea6aa955aaaaaaabfffefbaaaaaaaaaaaaaaaaaaffaaaaaabbaaaaaaaaaaaa
            hex 66aaaa4815aaaaaafeeaaaaaaaaaaaaaaaaaaaaaabefaaaaaabbaaaaaaaaaaaa
            hex 66eaaf8916aaaaaafeaaaaaaaaaaaaaaaebaeaaaaaaabaaeaabaaaaaaaaaaaaa
            hex 66aefaaafaaaaaaaefaaaabbaaaaaaaaa9aaa5a966aaaafaaaaaaaaaaaa5aaaa
            hex 66aaaaaaaaaaaaaaffaaaabbaaaaaaaa99aaa595aabaaaaaaaa9a5a5a5a5a5a5
            hex 66eaaaaaaaaa55aafae9a5a6aaaaaaaa99555556aaaaaaaa54015a5a4501165a
            hex 66aabaaaaaaaa5aa9955556aa5a5a5a5aa9a5aaaaaaaaaaa55abffea5556aebb
            hex 66aaaaaaaaaaa9aaaaaaaa995555555566aaaaaaaaaaaaaa6affe9665a66ee95
            hex 66aeaaaaaaaa5aaaaaeeaa9a9a6a5aaaaaaaaaaaaaaaaaaaaaeb5fafefaaefaf
            hex 66aaaaaaaaaaaaaaaaeeaaaaaaaaabaaaaaaaaaaaaaaaaaaaaaafaffeeaaaaaa
            hex 9566aaaaaaaa55aaaaeeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaffeeaaaaaa
            hex 56aeaaaaaaaaaeaaaaeeaaaaaaaaaaaaaaaaafafaaaaaaaaaaaaaaffeeaaaaaa
            hex 56aaaaaaaabbffaaaaeaaaaaaaaaaaaaabffffffeeaaaaaaaaaaaaffeeaaaaaa
            hex abaeaaaaaaaafbeeabffefafaeaaaaabfffffffeeaaaaaaaaaaaaaffeeaaaa99
            hex aabaa6abefafaeaafafbfffffffffffffffffeeabaaaaaaaaaaaaaffeaaaaa9a
            hex 99a75e5665f5f6feffafaebafafafaf9a7eaa6aaaaaaaaaaaaaaaabaaaaaaaaa
            hex a6aadfbe6a955faabaeafaffefabae5625aa5aaaaaaaaaaaaaaaaaaaabaaaaaa
            hex 5555a5f6ff6fffaaaaaaaabababbe9aa51fbefaeaaaaaaaa5a65a5aaaaaaaaaa
            hex 5555555565b5ea9565a5a6baaaaa998900b5f6eabafbffafaaaaaaaa9a5aaaaa
            hex aeaaaeaaaa9aaaa9a9aaaaaaaaaa94679961aeaaa9a5baaaaaaaaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afbf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 21
            hex afaa5a55555555f6ffffffee55555555555555555a6aabbffeaaaaa5555555aa
            hex fafbffaf5e595555555565a555555555555bafaaaaaaaaa5a6aaaa9a566bafaf
            hex 65a5bafbffee9f5a555555555559565aaafaa5aaaaaaaa5baeaaabefbffefafb
            hex 9e5a5965a5aafbffef5e566abaea66aaaa9a5aaaaaaabfffffefbafaaaaaaabb
            hex fafbffafafaaa9b5faffa9aaaa9566aaaabffaaeaaaafaaaaaabaaaaaeaaaabb
            hex aaaabaffffeabfef9faeaaaaae456aaabbeeaaaaaaaaaaaaaabaaaaaeaaaaaaa
            hex aaaaaabbffaafbffffffa9aaaaaaaaaabaeeaaaaaaaaaaaaa9aabaaaaaaaaaaa
            hex aaaaaabbffaabaffffff99aaaaaaaa99aae5a5aaaaaa995556aaaa945655516a
            hex aaaaaabbffaaaaffffffaaaaaaaaaa9aaa5a5aa5555565aaaaaaaa5ae99a6aa6
            hex aaaaaabfffaaaaffffff9aaaaaaaaa9aaabbaaaaaaaaaaaaaaaaaaaaabfeaaba
            hex aaaaaafaffaaaaffffffa9a6aaaaaa95aaaaaaaaaaaaaaaaaaaaaaaaaaeeaaaa
            hex aaaaaaaafeaaabffbbff99aaaaaaabafaaaaaaaaaaaaabffffaaaaaaaaeeaaa9
            hex aaaaaaaafeaabafafae9a7aeaaaaaafaeabfefffafaffffeeaaaaaaaaaeeaaaa
            hex aaaaa9a5a55555565a5ba9a6a9b5f6faefefaefbbafabaaaaaaaaaaaaafaaaaa
            hex 555555565a6aafafbbefa9aaeb9f9e6faaaaaafabaeab6fbeeabafaa6aaaaaaa
            hex 5a6aaaafbaaaaaffbaea95555aaab5e5955aa9a5a6aa9f5e555aa4a5a5f6fafb
            hex aaaaaaaaaaaaaaaaabbf9955aaa55555555565a59565bb9f6fa956ae55565a6b
            hex aaaaaaaaaaaaabfffeea55555655554451555a9a555565a5f5b6feef5bbfbafa
            hex aaaaaaabbfaefee9aaa956a9a69966545555a5555555555a55555565a5f5a66a
            hex aaafbffffaaa9aa99555554455555500115555555555555555555555565a5555
            hex eaa6aeaaaaaaa6a9aaaaaaaaaaaa946b5961aeaaaaa5aa9aaa6aaaaaaaa5aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 22
            hex af5a5565aaaa9b59555555555555555955555555555555555555555555555555
            hex fbffaf5a5565baaa5a555555555577ffffff95555555555555555955aaaa5a5a
            hex aaaafaff9e5a65a5aaaf5e59555576fafae9555555555556aaaa9a6faeabefff
            hex aaaaaaaaeaa99a5965b6faff9e5955555555595a6a9a5baaaaaafffafabaaaaa
            hex aaaaaaaaaa99baeaaa5a55b5eaff9f5aaaaa50aaaabfeaeaaaaaaaaaabaaaaaa
            hex aaaaaaaaaa99aaaaaafafbafaeaafaaabaea6aaaaaefaaaaaaaaaaaaa6aaa9a5
            hex aaaaaaaaaa99aaaaaaaaaafbeeffffaaaaaaaaaaa6f9a5a6aaaa9956aaaa56aa
            hex aaaaaaaaaa99aaaaaaaaaabbaabbffaaaaaaaaaa66aaaa5a5a5a6aaaaaaaaaaf
            hex aaaaaaaaaa99aaaaaaaaaaffaabbffaaaaaaaaaaaaaaaaaaaaaaaaabaaaaaabb
            hex aaaaaaaaaa99aaaaaaaaaabfaabbffa96aaaaaabaeaaaeaaaaaabfffeeaaaabb
            hex aaaaaaaaaa99aaaaaaaaaafbaabbff9aaeaaaabafabbfffffffefaa6aaaaaaba
            hex aaaaaaaaaa99aaaaaaaaaabaaabafaa9eaa5b9f5fafaaabbaaaebaeeaaafaaaa
            hex aaaaaaaaaa95a5a555a55555565a5ba9a6aaaaabe9a6a5a6a6aa5f995a555a55
            hex aaaaa9a555555555565aaaabaafbbb99655a6aaa555565a59565f6faeaafee6b
            hex 55555555555a5aaaaaaaaaaaaaaaab5966aaa5555555555655555555545050a1
            hex 55555a6aaaaaaaaaa6a5aaabaefffa9565555555555555555556555555555a59
            hex 6aaaaaaaaaaaaaa9566bbfffeaaa9551a59655555565a5955555555454555555
            hex aaaaaaaaaaa9555aaafaa596a99555515555555555555555555555555555555a
            hex aaaaaaaa9556abea655665955555a4105555565a595555566a9a5a59555555a5
            hex aaaaa5966aaaaa9565955a6a55598500125fbfefaf6e9a555659519555555555
            hex aaa6aeaaaaaaa6a9aaaabaaaaaaa9467a9a1eebaf9a5aaaaaaaaaa9aaa59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 23
            hex aaaaaaaaaabbef5965ea5a955555555555555555555555555555555555555555
            hex aaaaaaaaaaaafaef9e65ba9a5555555555bfefaf99555555555555555a6aabaf
            hex aaaaaaaaaaaaaaaafb9e65a6af5a555565fafaf9555555565a6aaabffffebaaa
            hex aaaaaaaaaaaaaaaaaaaaab59b6fbef5a55555555566aaafefaaaaaaaaabaaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaea9f5aa6fbdf6aab9a6aaabbaeaaaaaaaaa9aaaaa5
            hex aaaaaaaaaaaaaaaaaaaaaaaabafbefafaa66aaaaaaa9aae5a5a9a5965aaaaa6a
            hex aaaaaaaa99aaaaaaaaaaaaaaaaaaeefbff6aaaaaaa99aaaa9a5a5a6aaaaaaaaa
            hex aaaaaaaa99aaaaaaaaaaaaaaaaaaeebbff6aaaaaaaa9aaaaaaaaaaabafaeaaaa
            hex aaaaaaaa99aaaaaaaaaaa6aaaaaaeebbee96aaaaaaafaeafafafaffffaeaaaaa
            hex aaaaaaaa99aaaaaaaaaa66aaaaaaeebaee6baaaaafbfeffefafeeeabafabaeaa
            hex aaaaaaaa99aaaaaaaaaa66aaaaaaeabaeaa99a6a6a6baaeaaaaaea5a995a5559
            hex aaaaaaaa99a6aaaaa9a565555555555a5a65aaaaa9e555a5559565f6baeabada
            hex aaaaa9a5555555555555555a6aaaaebbee55a59a6a5555555155555551555555
            hex 555555555555555a5aaaaaaaaaaaaaaaaf55aaa9955555555555555505555555
            hex 555555555a5aaaaaaaaaaa9996abaffffa559555555555555555555555555659
            hex 565aaaaaaaaaaaaaaaaa955abffae9aaa555a555555565a55555555555555555
            hex aaaaaaaaaaaaaaaaa5567be99559455165a555555559555555565a5555555556
            hex aaaaaaaaaaaaa9956baea555955559115555556fbefbafae9a66a96595555555
            hex aaaaaaaaa99556affea9595565518400555565f55565f5f5a5a59a9a55555555
            hex aaaaaaa5555abffaa5555555565944015555555555555555555565a595555555
            hex aaa6aeaaaaaaa6a9aaaaaaaaaaaa946ba961aeaaaaa5aa9aaaaaaaaaaa59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 24
            hex aaaaaaaaaaaaaaaaaafb9e65ab5955555555555b5a5a55555555555555555555
            hex aaaaaaaaaaaaaaaaaaaafa9e669a5955555557fffffe9555555555555a5aaeba
            hex aaaaaaaaaaaaaaaaaaaaaaea5aa6ef5e555565f5f59555555a5aabaaaaa9a5aa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaa5a65fbef5955555a5aaaa6baa5a6a9a5966aaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaf5ebafb6aaaaaaaaa66aaaa9a5a5aaaaaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaafbebafaaaaaaaaaaaaaaaaaaaaaaabffee
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbaffa9a6aaaaabaeaaaeabafaffffaaa
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbaaff99aaaaaabafbbbfafbfaeeabaeaa
            hex aaaaaaaaaaaaaaaa66aaaaaaaaaaaabbaaffaaeaa5b9e5babaaaaaaaea5f995a
            hex aaaaaaaaaaaaaaaa66aaaaaa66aaaabbaaff9abaaaaabae96555659565f5f9e5
            hex aaaaaaaaaaaaaaaa66aaaaaa66a9aabaaafa55aaaaaa55550555550555441151
            hex aaaaaaaaaaaaaaa965a5a5955555555a5a5b55aaaaa955555555555551451555
            hex a9a5a5a5a5a55555555555555a6aaabaaafe55a55a9a55555415545545515555
            hex 5555555555555555555aaaaaaaaaaaaaaaaf59aaa95555555559555555155555
            hex 5555555555565aaaaaaaaaaaaa956bbefafa5595555555555655555555555555
            hex 5555565a6aaaaaaaaaaaaaa956aaf98561a55555555555555555555555555555
            hex 556aaaaaaaaaaaaaaaaaa956ba9555590155a5955555565f5955595a59565555
            hex aaaaaaaaaaaaaaaaaaa56bbe995555840056555555bffafaffefaa5aa9595555
            hex aaaaaaaaaaaaaaa9556bfee9655659440165555555a5555565e5a5a5969a5955
            hex aaaaaaaaaaaaa9556bfea9555566ba9bbf995055515555555555555555559555
            hex aaa6aeaaaaaaa6a9a9aaaaaaaaaaa4a6a961aeaa9a65aa9aaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 25
            hex aaaaaaaaaa66ba9e55a5faef5e55555565b5e555555555555565a59556aaaaaa
            hex aaaaaaaaaa55aabaaa5a65b6ff9a5555555555565a55aa6aaa5a6aaaaaaaaaaa
            hex aaaaaaaaaa55aaaaaafbaf5ea9bbef59566aaaaaaa5aaabbaaaaaaaaaabfffaa
            hex aaaaaaaaaa55aaaaaaaaaafbefaab6eeaaaaaaaaaaa5aabbaaaaaaabbffeeaaa
            hex aaaaaaaaaa55aaaaaaaaaabafebbef9ea9aaaaaaabefaabfaffffffeea9faeab
            hex aaaaaaaaaa55aaaaaaaaaabaeebbffee66aaaaaaabbfabffaabfaaeeb5f6955a
            hex aaaaaaaaaa95aaaa99aaaaaaeeaaffeeafa9a5f9f5a6eaeaaaaaaabaefee6f9a
            hex aaaaaaaaaa55aaaa99aaaaabeeaaffeea5ab6bafaffa955a59a99955a5f5e5a5
            hex aaaaaaaaaa55aaaaa9aaaaaaeeaaffeea6aaaaab595550555450515461a9a9a6
            hex aaaaaaaaaa55aaaa99aaaaaaeeaaffee66eaaaaa890055114411555510519a6a
            hex aaaaaaaaaa55a6aa99aaaaaaaaa6aad966aaaaaa95554515554515551155a5a5
            hex a9a5a5a555555555555555555a5a5a5e66aaaaaa555555555555545515555555
            hex 55555555555555555aaaaaaaaebafeee65a55a6a555555515555555555555555
            hex 5555555a5a5aaaaaaaaaaaaaaaaaea9956aaaaa5555555555515555555555551
            hex 5a6aaaaaaaaaaaaa66a9aaaaaaabbfee66a5555555555555555555555555565a
            hex aaaaaaaaaaaaaaa9659a6bafffbae499565a5655555566a95555555555555555
            hex aaaaaaaaaaaaa5956abbfefaa699555159555555555555555555555555555555
            hex aaaaaaaaa99556afaaa9955aa9628451a95555555555555555556a5e56595555
            hex aaaaaaa5555abfea5556a555555544105555555b6fff9e5a5a59a55659a55555
            hex aaa5555aaaaaaa955595565aaa9a451f59557bfef5f6ffffdea656aa65595555
            hex aaaaaebaaaaaa6a9aaaaaaaaaaaaa4a69961aeaaaaa5aaaaaaaaeaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa55a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 26
            hex efafaa5555a6faffaa9f595555555555555a6aabaaaabbaaaaaaaaaaaabffffe
            hex fafaffaf9e5a69a5baffef5e55555a6aaaaaaa956aaabbaaaaaaaaafbfffeaa5
            hex aaaaaabafbffef9eaab6fbff9e6aeaaaaaaaaabfaaaabbafbffffffeeaaaafaf
            hex aaaaaaaaaafbffffaaaf5ab6ea956aaaaaaabafbffbbfefafaafaabfaabaf5f5
            hex aaaaaaaaaafbfffeaaffffef9e65aeaaaaaaabafafbffffafbfaaaaaab4e6ba9
            hex aaaaaaaaaabbffeeaabbffffee6baeaaaaf9f5a6abaaaaaaaaaaaaa5bafbef5f
            hex aaaaaaaaaabbffeeaabbffffeeaaab596a569abfeaa5965a5a5a5a5565a6f5f5
            hex aaaaaaaaaabbffeeaabbffffee5a6aeafafaf5e59565a5555a5a5a5a5a5a5aaa
            hex aaaaaaaaaabbffeeaabbffffee555b5fafaeaaa9949050515400115511aaaaa9
            hex aaaaaaaaaabafbeeaabbffffee5566febaeafa99444405115511555510555a5a
            hex aaaaaaaaaaaabbeeaabbfeffee5566eaaaaaaa9945450515560515550155a9a5
            hex aaaaaaaaaaaabbeeaabbeeffee5566aaaaaaaa99555555555555555505555555
            hex aaaaaaaaaaaabaaaa6aaa5a5955566aaaaaaaa95555555445555555155555555
            hex aaaaaaa5a5a5555556565a6bae5566aaa9965a99555555555555555455555555
            hex 5555555556565a5aaabffefbea5565566aaaa955555555555051554501550555
            hex 55559a5aabafeeeaaabbeebaa95566aaaa955655555555a55555555555155540
            hex aaaaaaeaaaaaeaaaaaaaaaabae5545615555555555555555555555555555555a
            hex aaaaaaaaaaaaaaaaaaabbfffe95559055555555555565a595565a55555555555
            hex aa66aaaaaaaaaaaeabfffea6a95584005a55554555a5a9955555555555555555
            hex aa65aaa6aaafffffbaa9aaa55659440165555555555555555555556595554555
            hex aaaaaeaaaaaaa6a5a9aaaaaaaaaa9466a961aeaaaaa5aa9aaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 27
            hex a65699ad679fffffaa555555555b6feebaefaaaaaaaafeabafafeabbeeaaaaaa
            hex aaef57effffafaa595455b6fbaffaaaaaafbaaabafaefbfaaaabaafea9a5a555
            hex 66bbfffae995565baffaefaaaabaebafafaefbaeaaaabaa5a5a5555555555555
            hex 6ea9a5565bafbafaeaaaaaaaafbeaafbaaaaa5a5955555555555555555555555
            hex 565baffaeaaaaaaaafbafaaaa9e5a55555555555555555555555555555555555
            hex f5faaaafaaeaaeafafaa55555555555555555555555555555555555555555555
            hex 55555565aaa6fafaffeebbaf5e59555555555555555555555555555555505555
            hex 55555555aa5a5a5965a5a9f6fabbef5b5454555150514500005515554515565a
            hex 55555555abffffffefaeab9f5eaaaaa9544055110011550001554466aaaaa9a5
            hex 555555556aeaffeafbeabbfefabafffb574c551101145601145540555a5a5a5a
            hex 5555555566aaffaabaaabaeaaaaaaaaa748055151545550905550015a5a5a5aa
            hex 55555555a6aafeaaaaaaaaaaaaaaaaaa55455555555555555555001555555555
            hex 55555555aaaaeaaaaaaaaaaaaaaaaaaa55555555555511555511555555555555
            hex 5555555566aaaaaaaaaaaaaaaaaaaaa954555555554555555555555555555555
            hex 55555555a6aaaaaaaaaaaaaaaaa5965a55451554405154555545115555555554
            hex 5555555566aaaaaaaaaaa6a5556aaaaa45555544115555555554000105045555
            hex 5555555566aaaaaaaa95555aaaaaa95556555555050504154555055565555555
            hex 55555555a6aaa995555aaaaaa9955645555555566a5955555555554504115000
            hex 555555556595565aaaaaaaa95559b65055555565a55555555559555555555545
            hex 55555555565aabaaaaaaa555555696001155511555555555555555555555565a
            hex aeaaaeaaaaaaa6a9a9aaaaaaaaaa94675961aeaaaa65aaaaaaaaaa5a6a99aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 28
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 5555555555555555555555555555555555555555555555555555555555555555
            hex 9a5a595555555555555555555555555555555555555555555555555555555555
            hex ffffaf9a5a555555555555555555555555555555555555555555555555555555
            hex faffffaabbef9f5a555555555555555555555555555555555555555555555555
            hex 55a5a5a6bafafbffef9e5a595555555555555555555554505051655554555051
            hex af9e5a6a5965a5a5baeafbef9e5a555554514400000505050555115514411555
            hex ffffffaaabafaf5f5a6aa9a5e5fa555504115451001144001155545555555a5a
            hex fffafaaabafffefafbaaffffae9f5450001144010011440011550466aaaaa5a5
            hex baaaaaaaaafeeaaaaaaaabaaeafa45555b15441012155511545500515a5a5a6a
            hex aaaaaaaaaaaaaaaaaaaabbaaaaaa5451b0514545151555051555045565a5a5a5
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaa455555555555555555555555405555555555
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaa555555555555555415555551555555555555
            hex aaaaaaaaaaaaaaaaaaaaaaaaaaaa555555455155541155555555555555555555
            hex aaaaaaaaaaaaaaaaaaaaaaaaa556450515555555115555555540115555555555
            hex aaaaaaa9aaaaaaaaa995555a6aaa545155554005554515555555505051005155
            hex aaaaaa99aaaaa595555aaaaaaaa5555555550450515450555544001515051555
            hex aaaaaa956555565aaaaaaaa99555554951554505050011550545041155a55515
            hex aaa99555566aaaaaaaaaa555555566985555565a555555a55555554500105155
            hex 55555a6aaaaaaaaaa555555455556644115aaaaa955555555555505551050050
            hex aeaaaeaaaaaaa6a9aaaaaaaaaaaa94a79961aeaaa9a5aaaaaaaaaa5a6a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 29
            hex 006040005506659a090099555555555555555555555555555555554455555550
            hex 0000000011564d98158559515910555555555555555555555555554544155500
            hex 000400005566ee88668d66455555555555555555555040105152655501050000
            hex 000500005562d58862eeaa999645555455400000400000001155554155400055
            hex 00550400110001841491995559aa554455000000000000001154541550005505
            hex 00504000115554555105555195655544550000010104040455555155051556a5
            hex 010000000001005144545555554544005554545041444040554411a9a5a5555a
            hex 4400050400000000000000001154000055044400114400005544115a5a5aaaa9
            hex 555555555555455511050505010000005544440111450100554411a5a5a5555a
            hex 555555554555555555555555455555885544446111a5500055441066aaaaaaaa
            hex 50505050505050505050505010505040555545555565550559445055a555a5a5
            hex 0000000405040505015505555555555555555555555555545545115555555555
            hex 5545155555555555555555555555555555555550155555455555555555555555
            hex 5555055555505155554555515544105555540155551555545155555555555595
            hex 5545055505155555544010505150555401050505155555545050515555555555
            hex 5455555554410505051515555555555410505150505555000055555555659555
            hex 154104055555955555555544000000010505041556555545055555a555555555
            hex 4010415555550055555550000155555504515555545051555400000054501010
            hex 0000000505441155040000555556a96754155555554500000000000000040000
            hex 0105565555555555001144555555556500105555555545000000115551455000
            hex aeaaaeaaaaaaaaa9aa6aaaaaaaaa94a79961aeaaa9a5aa5aaa6aaa5aaa999a9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 30
            hex 55ffaa11669f608a145099005555555555555555555555554456554011a44000
            hex 55ed661066bb8daa564955455555555555555555555050505565551105000000
            hex 5490660051bbd8ede5559a445555555554505050000000005555541050000115
            hex 50055505451045995555996e5555445500000000000000005111405540011441
            hex 5451145551450595515599b6555544550000000000000001155515400115566a
            hex 0040000055155455555595545554405504010545455111115550565a5a6aa955
            hex 000000005051541044505545540000555411401055400011550065a5a5a5566a
            hex 1505050500000000040000114400005544110000550000115504565a5a6aaaa5
            hex 555555555555104515450505040104554411001456481511550065a5a595565a
            hex 55555555554555555555555555554455441110946544501155001066aaaaaaaa
            hex 00005050505050505050505150144055555515455596451655045155955595a5
            hex 0001050401050505555555555555455555555555555555515504115555555555
            hex 5555555555555555555551555555555555555555555555155555555555555555
            hex 5555555555505555555554555545555451005551155555555555555555555555
            hex 5555555515545151554105555555540155555555555540010555555659555565
            hex 5555505055555555555555440000000000011555150505115565955555565955
            hex 5040011050554455555050551556595555555544505050000000555555555555
            hex 044005155555155544011555555555444511555545000000000511555555aa9f
            hex 15555555555555550014405155555555581155555400401555555655555565a5
            hex 5000005050000000000000100000111544005000000000555555a59a55550155
            hex ae5aae6aaa6a9a9aaa6aaaaaaaaa54a79951ae6a9a65aa9aaaaaaaaaaa995aaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaeea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55afaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 31
            hex ff66ab99a56a5445119955555555555555555554500010405540010544000000
            hex fe14555555669945005555555555555450514000000000015500149040000105
            hex ea5455555527556a995555554455400000000000000000115500164400005050
            hex a9405055567649e5de5455554456000000000000000000005501550000554516
            hex 5155451555665555954410514455000000010104051104444410555555556aaa
            hex 5155155455555544104411444055051514554151111040454400aaaaaaaaa955
            hex 0010505000405150554004010056550051000055440000554011a5a5a595566a
            hex 04000400000000000010550040551544110000554400005504005a5aaa6aaaa9
            hex 4555551045051505050105000055554415000456440001554400a565a5955556
            hex 55555455555555555555155544655144511185658400655540005066aaaaaaaa
            hex 55555155555051545054505040555555551545554605115501005565a5a5a5a5
            hex 5004000000000501154515554455555555555555555555554400555555555555
            hex 0505555555555555555555555555555555555555455551550504515555555555
            hex 5555555555555555455555545155555551451555555511555555555145555545
            hex 5050504515555550515555455554504114545555550455555555555555550555
            hex 555555505050500005054555541555555555555550410515555659565565a595
            hex 50554556555515555450505000001040555055400055565a5955555555555555
            hex 555555505555555540010505040505555544554504505055555555a595555555
            hex 505140515050400515565a555515555565405050000000115555555555555555
            hex 555515544000115555a55554555555595500000000041011555555aa9f565a55
            hex aeaaaeaaaaaaaaa9aa6aaaaaaaaa94a79951aeaaaa65aa5aaaaaaaaaaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 32
            hex ae55a54a04555555555555555555555154500000000000000166954000000000
            hex ff509a6ea9555555555554555400000000000000000000000040000000011a55
            hex ff4571e6ee155155555544564400000000000000000000000159400000115515
            hex aa555559e9560010555544664400000000000000000015005041155555555566
            hex a9a55950405500000000445544000000451104555144550000115555555aaaaa
            hex 5455550504550000005500555555551445451514505011040012aaaaaaa9a955
            hex 5011115450500000050100664455001500005544000011540061a5659555566a
            hex 00000000000000005144006544550011000055440000114400125a5aaaaaaaaa
            hex 1051450505050100040000565455005500005544000015440021a5a5a5a55555
            hex 0514555555555555451544664455005012887a4400169544001054665a9aaaaa
            hex 55555555555555555555406545550455114451490450554400115466a9a9a9aa
            hex 5000000000040000050544555555555555555565554555444411456555555555
            hex 0505155555555555555545555515555555555154555455400011554555555555
            hex 5555555555555555515555555555155554115515555555554500515555555555
            hex 5555555051555555555555055555541155555555510505155555545054515504
            hex 0505055555555400505551555105165545555154005055515555005156555555
            hex 555550050505155555555544105154545149400115555555a555555555555550
            hex 055555555555555400000100040115591698451555a59555555a595555555555
            hex 555144155554500115555544515554506644000000155555555555555555aaaf
            hex 0554055500001555559555455555556b5e44060800555555565a5555555565a6
            hex ae6aaeaaaa5aaaa9aaaaaaaaaaaa94a6e961feaaaaa5aaaaaaaaaaaaaa59aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 33
            hex 5155555555555544565400000000000000000000010100000055555555555555
            hex 5510505555555544665900000000000100000000010500000051555555555555
            hex 0000000010515544669900000001000000050155005500000055555555555555
            hex 000000000000000055540000010454144551451144514400005555555555556a
            hex 04000000000000005555551551154551554510455101040000669aaaaaaaaaaa
            hex 4500000000000000665904554050545010554400001044000066aa99aaa5a555
            hex 500000000000550066994555000044000055440000004400005555595a56556a
            hex 00000000050055405555055500004400005544000001040000669aaaaaaaaaaa
            hex 05154504050005006655545544004409125954000019400000659595a5555555
            hex 555555555555550466994055000055a966a5440006d5000000555051aa6a9aaa
            hex 55555555555555446555555505014455115545006055040000555551aa66a9aa
            hex 505000000000000055555555555545550565a555055644001055551555555555
            hex 0505155515555544555515555551515495555556555a44000055555555555554
            hex 5555455555555451555515555511555511451545054500000011555555505555
            hex 5554505555555555555501555554115555555440055405040011555555555450
            hex 0515555555115555515555010505051555554011555555554400050505555545
            hex 5405050405055555550011555551555516990505050555555505516555555555
            hex 5555551555401050500000001514554466945159555555055040000010400051
            hex 5555555541050515054505559555555669440155455155554501040515450015
            hex 50500015555a595551555500105041bbff9fbfd91055505140001051555a5955
            hex 9e5aaeaaaaaaaa9aaa6aaaaaaaaa54aaa9b1faaaaa65aa5aaaaaaa6aaa95aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 34
            hex 505555554411aa44000000000000000104144000010000000055555555555555
            hex 0000105144116544000000000511441001441045000000000055555555555555
            hex 0000000000115544000114455455104504154051040000000055555555565a6a
            hex 00000000001155555505154554051415510451145400000001566aaaaaaaaaaa
            hex 000000000012aa554455554041455450455500000000000000aaa6aaa96699a5
            hex 000000000021aa554455550000440000155500000000000000a5655555555959
            hex 000000000011555544555500004400005155000000000000005a6a9aaaa69aaa
            hex 04001040001156555555550000450000555544000400000000aaa6a9a9a6a5a5
            hex 550515450522aa5944555500007a495715550011d900000000555555555a595a
            hex 555555555421aa554555550010a54469955504a655000000005a545051aaaaaa
            hex 55555551441155554555550401554451555a05114405000011aa9555516699aa
            hex 0000000000115555555555555555456555695555450000001055555555595555
            hex 5555555545115555054454515090615055555a55550000000011555555555555
            hex 5555555155555555555550555555115505050405140000000011555555555555
            hex 5555555555545055555555555545155555554455950000000011555551554505
            hex 5555555555555555554010505051555501554505050504000015555555555555
            hex 5551555554410505050505155555450015995555555555050000050000005555
            hex 45514105155a5555555555501050500066d45150555155500001555659055555
            hex 40001555555451555555550000000516694400555645554504015555a5555551
            hex 000010515540555554500000555555bbef4f6f99545155555540505050515544
            hex 9e5aaeaaaa6aaa99aa6aaaaaaaaaa4aaa9a1faaaaa65aa9aaa9aaa5a5a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 35
            hex 0051555544004550410510440001450000000000000011000000555555555a5a
            hex 0015555555550000555040055001045500000000000000000000565aaa9aaaaa
            hex 00565a55555455550514545515144104000000000000100000006aaaaa99aa99
            hex 0062aaaa554505555544501111504055000000000000000000006699a5a5a555
            hex 0065a6aa55451555550000004400001500000000000000000000555556595a59
            hex 105555555545155555000000440000550000000000000000000066aaaa99aa9a
            hex 0015565955555555550401044500001500000000000000000010a6a9aaa9aa95
            hex 0062aaaa55441055554021caab04005100000000000000000000555555555555
            hex 5562aaaa55541155550055656999006500000000000000000000555555555565
            hex 44155555555450555504115555440041000000000000000000005aaa59050515
            hex 4011555555555555558515555545119910000000000000000011aaaa99555451
            hex 0411555555545545565554659595519500000000000000000000559555554516
            hex 4551559555450505101050a05195555a00000000000000000000115555555551
            hex 5555545555505155555501050404000000000000000000000000115555515545
            hex 5555554555505155501050555195554500000000000011000001555545155555
            hex 5550505505054505051555551544055500440000000000000010505050505155
            hex 4555555555554555554010505040000001040000000000000515450505001555
            hex 555554055555555545000505050004001644040000100000115555aa5a555555
            hex 1440105050400001155556595504555555400004000001045155555555555551
            hex 555550504001555555aaa5555540451655040154000010400010000011555544
            hex ae5aae6aaa6aaaa9a9aaaaaaaaaa94a6a951aeaa9e65aa5aaa6aaa5a5a59aa9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 36
            hex 55555544001155400000000000000044000000000000000000115a5a66aa5aaa
            hex 5955555545550104000000000000004400000000000000004011aaaaa6aaa6aa
            hex 9a55550451555554000000000000000400000000000000000011a9aa66aa55a5
            hex aa55551051555544000000400000004000400000000000000011a59555565959
            hex a555555051555544000000000000000000000000000000000011595a56aa65a6
            hex 5555555515555544000000000104000000000000000000000011aaaa6aaaaaaa
            hex 5955555555555554000000000000000000000000000000000011a5a565a555a5
            hex aa55550515555544000000000000000000000000000000000011555555555555
            hex aa55550411555555000000000000000000000000000000000011555555555555
            hex 5555554051555544000000000105040000000100000000000411aaaaaa440505
            hex 5555555555555555000040000000000000000000000000004011aaaaaa545551
            hex 5555555155055450000000000000000000000000000000000011556595451505
            hex 5545040010505094000000000000000000000000000000000000015555555551
            hex 4555515545050000000000000000000000000010000000000000555550555545
            hex 5105555450515644000000000000000000000000000000004010505055515555
            hex 5155545001555540000000000000000000000000000000000015054505055555
            hex 000000010515450400000000000000001000000000000004115565a555445555
            hex 5555555555555544000000000000000415440000000000000000001154505055
            hex 5040005554505040000000440000000465004010000000000000000004000011
            hex 0000000000000000000400000000001555000000001440555555555410000051
            hex 9e5a6e6aaa5a9a9aaa6aaaaaaa5a54a69951aeaa9965aa9aaaaaaa9a6a59aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 37
            hex 000000000000000000000000000000000000000000000011aaaa66aa99aaaa99
            hex 000000000000000000000000000000000000000000000011aaaa66a955a55555
            hex 000000000000000000000500000000000000000000000011a5a555565665a5a5
            hex 0000000000000000000104000000000000000000040000015965a59a5a6aa995
            hex 000000000000000000114400000000000000000000000011aaa9a59a5a6aaaa9
            hex 000000000000000000000000000000000000000000000011aaaaa6aa95aaaa99
            hex 000000000000000000000000000000000000000000000011aaa565a555555555
            hex 0000000000000000000000000000000000000000000000015555555555a5a595
            hex 0000000000000000000000000000000000000000000000119a55555555555555
            hex 0000000000000000000000000000000000000000000000119a6aaa69aa9a4440
            hex 000000000000000000010504040000000000000000000011a6aaaaaaaaaa5555
            hex 000000000000000000014400000000000000000000000010aaa9a5a5a6a64451
            hex 000000000000000000114400000000000000000000000011aa55555555555555
            hex 0000000000000000001040000000000000000000000000005554515555555555
            hex 0000000000000000000011554000010000000000000000005500555545155545
            hex 0000000000000000000000000040000000000000000000004000005050515555
            hex 0000000000000000000000000000000004000000000000005155565555555554
            hex 0000000000000000000000000000000045000000000000511050505555555555
            hex 0000000000000000000104000000001648050000040000050001040000114554
            hex 0000000000000000000000000000011544000000000011555555440105155556
            hex 9e5a6e6a9a5a5a5a5a6aaaaaaaaa54679951aeaa9e65aaaaaaaaaa5aaa99aaaa
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 38
            hex 550044000000000000000000000000000000000066aaaaaa66aa95aaa9955555
            hex 55004400000000000000000000040000000000006666aaaa65a555555a5a69a5
            hex 550044000000000000000000000000000000000021a59555565965a5a6595aaa
            hex 55004400000000000000000000000000000000001259a5a5565a59a9a5955a5a
            hex 55004400000000000000000000000000000000002669a5a5565a5aaaaa99aaaa
            hex 5500440000000000000000000000000000000000666aaaaaa6aa95aaaa99aaaa
            hex 55000000000000000000000000040000000000006665aaa965a555a555555555
            hex 55000000000000000000000004000000000000001159565a555555a5a5a5a555
            hex 5500000000000000000000000000000000000000165a9a555555555555555555
            hex 5500000000000000000000000000000000000000666aa9a6aa595a5a54505040
            hex 55000000000000000000000000000000000000006665aaaaaaaaaaaa55555555
            hex 550004000000000000000000000000000000000066556aaaa6a5a5a544554455
            hex 55004400000000000000001000000000000000001255a9955565655555555555
            hex 5500440000000000000000000000000000000000116595555555555555555555
            hex 5500440000000000000000000000000000000000115555445155555555545155
            hex 5500440000000000000000100000000000000000115500010505055555450555
            hex 5500440000000005000000000000000000000000115544505155555555555400
            hex 5500440001050000000400000000000104000000000000005010005515514500
            hex 55004550400005040000000000000016440400000015555659555555a5515555
            hex 4000000000000000000000000000005500000000015555a59555115555451450
            hex 9a5aaeaaaa5a9a9aaa6aaaaaaaaa54679951aeaaaa65aa9aaaaaaa9aaa99aa9a
            hex aaa6eeabaaaa6699aabaaaaa9aaa45abae15eeaa99556a9aaaaaaea9aa95a699
            hex aaaaaaaaaa9a9a555aaaaa9aaaaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae9aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            ; frame 39
            hex 55505540000000005000000055555a5a99a595566aaaa5a5555a59aaaaaaaa99
            hex 0104000000000010000000005565a5555aaaa9a5565a5aaaaaaa95aaaaaaa699
            hex 1144000000000001040000115aaaa995565a6a6aaaaa95aaaaaa99aaaaaa5599
            hex 104400000000115544000011aa9aaaa9aaaaaa66aaaa55aaaaaa99a6a5a55555
            hex 000010000004115544000011a6aaaa99aaaaaa66aa9555a5a55555555555565a
            hex 5500550104001040000000105565a995a595555555555a5a5a6aa9aaa9a55555
            hex 51000010000000000001000055555a5a5a6aa5a5a555555555555555555555bf
            hex 000000000100000500050015669a5a595b5955555555555555555555555555aa
            hex af5f6f455451055555555555aaa9a595aaaaaa5a5955555555555555555555aa
            hex ffffff555555555554555555a6aaaaa9aa9a5a6aa9aaa5aa9a544000000011aa
            hex fafafa5955456555555555556566aa99a9aaaaaaaaaaaaaaaa555555555555aa
            hex 00000050505155545060a0a05566aa9955aaaaaaaaaaa5a5a544554444515155
            hex 0505040000000000000000015565a59596aaaaa5955565a59555154555051555
            hex 55555155550505000500001155565a596aa99555555555555555555555555559
            hex 50505554055555555515555555a5a5a5ab9a55555555555555555555555555aa
            hex 55555550505050015555555041555555555450501156595555555554555556aa
            hex 515545555555555450505000105055555550011556555555555455555a5965ae
            hex 55555555555554000505450505555504514511555555515555550400515155f5
            hex 05155555500115565a5555555544164454550000500011555055401051555659
            hex 5555540054555555545155555555550000040010400015554555550010555595
            hex aa9aaeaa9a6aaa9a9a6aaaaaaaaa94679961aeaa9a65aaaaaaaaaa9a9a59aaaa
            hex aaa6eeabaaaa6699aabaaaaaaaaa45abae15eeaa99556a9aaaaaaea9aa99a699
            hex aaaaaaaaaa9a9a555aaaaa9a9aaa55efaf55aeaaaa5aaa55aaaabaaaaa956a99
            hex aaf5faeaaabae9a5aae5aaf6fae944b6e911aaeafaba9955a5aaeaa9a555b595

            pad ntdata+frame_count*24*32, $ff

; --- Interrupt routines --------------------------------------------------------------------------

            align $100, $ff    ; don't want the copy loop to cross a page boundary

nmi         pha                ; push A, X (note: not Y)
            txa
            pha

            bit ppu_status     ; clear ppu_addr/ppu_scroll latch and set PPU address
            lda ppuaddr_mir+1
            sta ppu_addr
            lda ppuaddr_mir+0
            sta ppu_addr

            ldx #0             ; copy 128 bytes (4 rows) of video data to name table
-           lda vram_buffer,x  ; TODO: is there enough VBlank time?
            sta ppu_data
            inx
            bpl -

            lda #$00           ; reset PPU address
            sta ppu_addr
            sta ppu_addr

            lda ppuctrl_mir    ; which name table to show
            sta ppu_ctrl

            sec                ; set flag to let main loop run once
            ror run_main

            pla                ; pull X, A
            tax
            pla

irq         rti                ; end of interrupt routines (note: IRQ unused)

; --- Interrupt vectors ---------------------------------------------------------------------------

            pad $fffa, $ff
            dw nmi, reset, irq  ; note: IRQ unused

; --- CHR ROM -------------------------------------------------------------------------------------

            pad $10000, $ff
            incbin "video-chr.bin"  ; all combinations of 2*2 "pixels" in 4 colors
            pad $12000, $ff
