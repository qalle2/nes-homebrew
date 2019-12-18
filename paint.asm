    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

OhjelTila equ $00   ; ohjelman tila (0 = piirtotila, 1 = paletinvalintatila)
Ohjain    equ $01   ; peliohjaimen tila
EdOhjain  equ $02   ; edellinen peliohjaimen tila
KurViiJal equ $03   ; kursorinsiirtoviivetta jaljella (piirtotilassa)
KurTyy    equ $04   ; kursorin tyyppi (piirtotilassa; 0 = pieni eli nuoli, 1 = iso eli nelio)
KurX      equ $05   ; kursorin X-sijainti (piirtotilassa; 0 - 63)
KurY      equ $06   ; kursorin Y-sijainti (piirtotilassa; 0 - 47)
Vari      equ $07   ; valittu piirtovari (0 - 3)
PalVarit  equ $08   ; piirtopaletin varit (4 tavua, arvot 0 - 63)
PalValKur equ $0c   ; kursorin sijainti paletinvalintatilassa (0 - 3)
NayMuiOsL equ $0d   ; osoite nayttomuistissa (alempi tavu)
NayMuiOsH equ $0e   ; osoite nayttomuistissa (ylempi tavu)
EpaSuoOsL equ $0f   ; osoite epasuoria osoitustapoja kaytettaessa (alempi tavu)
EpaSuoOsH equ $10   ; osoite epasuoria osoitustapoja kaytettaessa (ylempi tavu)

SprData equ $0200   ; spritedata

PPU_CTRL1  equ $2000
PPU_CTRL2  equ $2001
PPU_STATUS equ $2002
PPU_ADDR   equ $2006
PPU_DATA   equ $2007
SPR_DMA    equ $4014
JOYPAD1    equ $4016

; non-address constants

BTA  = %10000000
BTB  = %01000000
BTSE = %00100000
BTST = %00010000
BTU  = %00001000
BTD  = %00000100
BTL  = %00000010
BTR  = %00000001

black  equ $0f
white  equ $30
red    equ $16
yellow equ $28
olive  equ $18
green  equ $1a
blue   equ $02
purple equ $04

KURVII equ 10   ; kursorinsiirtoviive, kun nuolinappia pidetaan pohjassa

; --------------------------------------------------------------------------------------------------
; iNES header

	inesprg 1  ; PRG ROM size: 1 * 16 KiB
	ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
	inesmir 0  ; name table mirroring: horizontal
	inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

	org $c000
reset:

	lda #$00
	sta PPU_CTRL1
	sta PPU_CTRL2

	tax
	TyhjNollasivu:
		sta $00, x
		inx
		bne TyhjNollasivu

    bit PPU_STATUS
-   bit PPU_STATUS
    bpl -
-   bit PPU_STATUS
    bpl -

; Paletti
	lda #$3F
	ldx #$00
	jsr AsetaPPUosoiteAX

	AlkuPalSilm:
		lda AlkuPaletit, x
        sta PPU_DATA
		inx
		cpx #32
		bne AlkuPalSilm

; CHR-RAM - taustagrafiikka
	jsr NollaaPPUosoite

	ldy #15
	CHRsilmY:
		ldx #15
		CHRsilmX:
			lda CHRRAMtaul1, y
			jsr TulostaNeljasti
			lda CHRRAMtaul1, x
			jsr TulostaNeljasti
			lda CHRRAMtaul2, y
			jsr TulostaNeljasti
			lda CHRRAMtaul2, x
			jsr TulostaNeljasti
			dex
			bpl CHRsilmX
		dey
		bpl CHRsilmY

; CHR-RAM - spritet
	lda #>CHRdata
    sta EpaSuoOsH
	ldy #$00
	sty EpaSuoOsL
	CHRsprSilm:
		lda (EpaSuoOsL), y
        sta PPU_DATA
		iny
		bne CHRsprSilm
			; Vaihdetaan osoitteen enemman merkitseva tavu
			inc EpaSuoOsH
			lda EpaSuoOsH
			cmp #((>CHRdata) + 16)
			bne CHRsprSilm

; Name Table
	lda #$20
	ldx #$00
	jsr AsetaPPUosoiteAX

	; Ylapalkki (4 rivia)
	lda #$55
	ldx #32
	jsr TulostaMerkkia
	ldx #0
	NameTableYlaosaSilm:
		lda NameTableYlaosa, x
        sta PPU_DATA
		inx
		cpx #96
		bne NameTableYlaosaSilm

	; Piirtoalue (24 rivia)
	lda #$00
	ldx #192
	PiirtoalueSilm:
		jsr TulostaNeljasti
		dex
		bne PiirtoalueSilm

	; Alapalkki (2 rivia)
	lda #$55
	ldx #64
	jsr TulostaMerkkia

; Attribute Table
	; Ylapalkki
	lda #%01010101
	ldx #8
	jsr TulostaMerkkia

	; Piirtoalue
	lda #%00000000
	ldx #48
	jsr TulostaMerkkia

	; Alapalkki
	lda #%00000101
    sta PPU_DATA
	sta PPU_DATA
	ldx #%00000100
	stx PPU_DATA
	ldx #5
	jsr TulostaMerkkia

; Piirtopaletin varit
	ldx #3
	PiirtoVaritSilm:
		lda AlkuPaletit, x
        sta PalVarit, x
		dex
		bpl PiirtoVaritSilm
	inc Vari

; Spritejen alkuarvot
	ldx #TAVSPRTAVUJA - 1
	SprSilm:
		lda TavSpritet, x
        sta SprData, x
		dex
		bpl SprSilm

	lda #$FF
	ldx #TAVSPRTAVUJA
	SprTyhjSilm:
		sta SprData, x
		inx
		bne SprTyhjSilm

	lda #BTSE
    sta EdOhjain
	jsr NollaaPPUosoite
    bit PPU_STATUS
-   bit PPU_STATUS
    bpl -

	lda #%10001000
    sta PPU_CTRL1
	lda #%00011110
    sta PPU_CTRL2

; Ohjelman paasilmukka
PaaSilmukka:
	jmp PaaSilmukka

; --------------------------------------------------------------------------------------------------

nmi:
	jsr LueOhjain
	sta Ohjain

	lda OhjelTila
	bne NMI_paletinvalintatila
	jmp NMI_piirtotila

	NMI_paletinvalintatila:
		ldx PalValKur
		ldy PalVarit, x

		; Luetaan napit vain, jos edellisella framella ei ole painettu mitaan
		lda EdOhjain
		bne EiLuetaNappeja1
			lda Ohjain
			cmp #BTU
			beq KursoriYlos
			cmp #BTD
			beq KursoriAlas
			cmp #BTL
			beq PienennaVariaVahan
			cmp #BTR
			beq SuurennaVariaVahan
			cmp #BTB
			beq PienennaVariaPaljon
			cmp #BTA
			beq SuurennaVariaPaljon
			cmp #BTSE
			beq TakaisinPiirtotilaan
			jmp EiLuetaNappeja1

			KursoriYlos:
				dex
				dex
			KursoriAlas:
				inx
				txa
				and #%00000011
				sta PalValKur
				tax
				jmp EiLuetaNappeja1

			PienennaVariaVahan:
				dey
				dey
			SuurennaVariaVahan:
				iny
				tya
				and #%00111111
				sta PalVarit, x
				jmp EiLuetaNappeja1

			PienennaVariaPaljon:
				tya
				sbc #$10
				jmp Pienennetty
			SuurennaVariaPaljon:
				tya
				adc #$0F
				Pienennetty:
				and #%00111111
				sta PalVarit, x
				jmp EiLuetaNappeja1

			TakaisinPiirtotilaan:
				; Paletinvalintaruutu piiloon
				lda #$FF
				ldx #PALVALSPRTAVUJA - 1
				PalValPiilSilm:
					sta SprData + TAVSPRTAVUJA, x
					dex
					bpl PalValPiilSilm
				inx
				stx OhjelTila
				jmp PoistuNMIsta

			EiLuetaNappeja1:

		; Kursorin Y-koordinaatti
		txa
		asl
		asl
		asl
		adc #$AF
		sta SprData + TAVSPRTAVUJA

		; Vasen varinumero
		lda PalVarit, x
		lsr
		lsr
		lsr
		lsr
		clc
		adc #$10
		sta SprData + TAVSPRTAVUJA + 5 * 4 + 1

		; Oikea varinumero
		lda PalVarit, x
		and #%00001111
		clc
		adc #$10
		sta SprData + TAVSPRTAVUJA + 6 * 4 + 1

		; Paivitetaan valittuna oleva vari paletteihin
		lda #$3F
		jsr AsetaPPUosoiteAX
		ldy PalVarit, x
		sty PPU_DATA
		sta PPU_ADDR
		lda SprPalTaul, x
        sta PPU_ADDR
		sty PPU_DATA
		jsr NollaaPPUosoite
		jmp PoistuNMIsta

	NMI_piirtotila:
		; Select, start ja B luetaan vain, jos edellisella framella ei ole painettu mitaan niista
		lda EdOhjain
		and #BTB|BTSE|BTST
		bne EiLuetaNappeja2
			lda Ohjain
			and #BTB|BTSE|BTST
			cmp #BTSE
			beq Paletinvalintatilaan
			cmp #BTST
			beq KursorityypinVaihto
			cmp #BTB
			beq PiirtovarinVaihto
			jmp EiLuetaNappeja2

			Paletinvalintatilaan:
				ldx #PALVALSPRTAVUJA - 1
				PalValEsiinSilm:
					lda PalValSpritet, x
                    sta SprData + TAVSPRTAVUJA, x
					dex
					bpl PalValEsiinSilm
				lda #$FF
                sta SprData   ; piirtokursori piiloon
				lda #1
                sta OhjelTila
				lda #0
                sta PalValKur
				jmp PoistuNMIsta

			KursorityypinVaihto:
				lda KurTyy
				eor #%00000001
				sta KurTyy
				beq EiKoordinaattejaParillisiksi
					lda KurX
					and #%00111110
					sta KurX
					lda KurY
					and #%00111110
					sta KurY
					EiKoordinaattejaParillisiksi:
				jmp EiLuetaNappeja2

			PiirtovarinVaihto:
				ldx Vari
				inx
				txa
				and #%00000011
				sta Vari

			EiLuetaNappeja2:

		; Saako kayttaja siirtaa kursoria
		dec KurViiJal
		bpl KursoriaEiSaaSiirtaa

		; Vasen ja oikea nuoli
		lda Ohjain
		and #BTL|BTR
		tax
		lda KurX
		cpx #BTL
		beq Vasen
		cpx #BTR
		beq Oikea
		jmp EiVasenOikea
		Vasen:
			clc
			sbc KurTyy
			jmp EiVasenOikea
		Oikea:
			adc KurTyy
			EiVasenOikea:
		and #%00111111
		sta KurX

		; Yla- ja alanuoli
		lda Ohjain
		and #BTU|BTD
		tax
		lda KurY
		cpx #BTU
		beq Yla
		cpx #BTD
		beq Ala
		jmp EiYlaAla
		Yla:
			clc
			sbc KurTyy
			bpl EiTaysille
				lda #48
				sbc KurTyy
				EiTaysille:
			jmp EiYlaAla
		Ala:
			adc KurTyy
			cmp #48
			bne EiNollaan
				lda #0
				EiNollaan:
			EiYlaAla:
		and #%00111111
		sta KurY

		; Asetetaan viive uudelleen
		lda #KURVII
        sta KurViiJal

		KursoriaEiSaaSiirtaa:

		; Jos ei paineta nuolta, nollataan kursorinsiirtoviive
		lda Ohjain
		and #BTU|BTD|BTL|BTR
		bne PainettuNuolta
			sta KurViiJal
			PainettuNuolta:

		; Piirto: jos painettu A:ta, muutetaan yksi nayttomuistin tavu.
		; Alue: $2080 - $237F (768 tavua).

		lda Ohjain
		and #BTA
		beq EiPainettuA

		; Osoitteen enemman merkitseva tavu
		lda KurY
		lsr
		lsr
		lsr
		tax
		lda NayMuiOsMuunnosH, x
        sta NayMuiOsH

		; Osoitteen vahemman merkitseva tavu
		lda KurY
		and #%00001110
		lsr
		tax
		lda KurX
		lsr
		ora NayMuiOsMuunnosL, x
		sta NayMuiOsL

		; Muodostetaan tavulle uusi arvo
		lda KurTyy
		beq PieniKursori
			; Iso kursori
			ldx Vari
			lda PiirtovariIlmaisimet, x
			jmp UusiArvoLuotu
		PieniKursori:
			; X = sijainti 8 * 8 pikselin palan sisalla (0 - 3)
			lda KurX
			ror
			lda KurY
			rol
			and #%00000011
			tax
			; Y = sijainti * 4 + piirtovari
			asl
			asl
			ora Vari
			tay
			; Luetaan vanha arvo ja tehdaan muutokset siihen
			lda NayMuiOsH
			sta PPU_ADDR
			lda NayMuiOsL
			sta PPU_ADDR
			lda PPU_DATA
			lda PPU_DATA
			and PalaAndArvot, x
			ora PalaOrArvot, y
		UusiArvoLuotu:

		; Kirjoitetaan uusi arvo
		ldx NayMuiOsH
		stx PPU_ADDR
		ldx NayMuiOsL
		stx PPU_ADDR
		sta PPU_DATA

		EiPainettuA:

		; Piirtovari alapalkin taustagrafiikkapalaan
		lda #$23
		ldx #$88
		jsr AsetaPPUosoiteAX
		ldx Vari
		lda PiirtovariIlmaisimet, x
        sta PPU_DATA

		jsr NollaaPPUosoite

		; Spritet

		; Kursorin kuva
		lda #2
		clc
		adc KurTyy
		sta SprData + 1

		; Kursorin X-koordinaatti
		lda KurX
		asl
		asl
		ldx KurTyy
		bne IsoKursori1
			adc #2
			IsoKursori1:
		sta SprData + 3

		; Kursorin Y-koordinaatti
		lda KurY
		asl
		asl
		adc #31
		ldx KurTyy
		bne IsoKursori2
			adc #2
			IsoKursori2:
		sta SprData

		; X-koordinaattinumerot
		lda KurX
		lsr
		tax
		lda HaeYkkosetTaul, x
		adc #0
		sta SprData + 2 * 4 + 1
		lda HaeKymmenetTaul, x
		sta SprData + 4 + 1

		; Y-koordinaattinumerot
		lda KurY
		lsr
		tax
		lda HaeYkkosetTaul, x
		adc #0
		sta SprData + 4 * 4 + 1
		lda HaeKymmenetTaul, x
		sta SprData + 3 * 4 + 1

	PoistuNMIsta:
		lda #$02
        sta SPR_DMA   ; spritedatan siirto
		lda Ohjain
        sta EdOhjain
		rti

; --------------------------------------------------------------------------------------------------

LueOhjain:
	; Luetaan peliohjaimen tila A:han ja X:aan.
	; Bitit: A, B, select, start, yla, ala, vasen, oikea.
	ldx #1
	stx JOYPAD1
	dex
	stx JOYPAD1
	ldy #8
	OhjainLukuSilm:
		lda JOYPAD1
		ror
		txa
		rol
		tax
		dey
		bne OhjainLukuSilm
	rts

NollaaPPUosoite:
	lda #$00
    sta PPU_ADDR
	sta PPU_ADDR
	rts

AsetaPPUosoiteAX:
	sta PPU_ADDR
	stx PPU_ADDR
	rts

TulostaNeljasti:
	sta PPU_DATA
	sta PPU_DATA
	sta PPU_DATA
	sta PPU_DATA
	rts

TulostaMerkkia:
	; Tulostaa A:n X kertaa
	MerkTulSilm:
		sta PPU_DATA
		dex
		bne MerkTulSilm
	rts

; --------------------------------------------------------------------------------------------------

CHRRAMtaul1: db $FF,$F0,$FF,$F0, $0F,$00,$0F,$00, $FF,$F0,$FF,$F0, $0F,$00,$0F,$00
CHRRAMtaul2: db $FF,$FF,$F0,$F0, $FF,$FF,$F0,$F0, $0F,$0F,$00,$00, $0F,$0F,$00,$00

NayMuiOsMuunnosH: db $20, $21, $21, $22, $22, $23
NayMuiOsMuunnosL: db $80, $A0, $C0, $E0, $00, $20, $40, $60

HaeKymmenetTaul:
	; Kerran oikealle shiftattu luku --> kymmenkantaisten kymmenten (0 - 6) grafiikkamerkki
	db $10,$10,$10,$10,$10, $11,$11,$11,$11,$11, $12,$12,$12,$12,$12
	db $13,$13,$13,$13,$13, $14,$14,$14,$14,$14, $15,$15,$15,$15,$15
	db $16,$16
HaeYkkosetTaul:
	; Kerran oikealle shiftattu luku --> kymmenkantaisten ykkosten (0/2/4/6/8) grafiikkamerkki
	db $10,$12,$14,$16,$18, $10,$12,$14,$16,$18, $10,$12,$14,$16,$18
	db $10,$12,$14,$16,$18, $10,$12,$14,$16,$18, $10,$12,$14,$16,$18
	db $10,$12

PalaAndArvot:
	db %00111111, %11001111, %11110011, %11111100

PalaOrArvot:
	db %00000000, %01000000, %10000000, %11000000
	db %00000000, %00010000, %00100000, %00110000
	db %00000000, %00000100, %00001000, %00001100
	db %00000000, %00000001, %00000010, %00000011

PiirtovariIlmaisimet: db $00, $55, $AA, $FF
SprPalTaul: db $1A, $1B, $1E, $1F

	; Name Tablen ylaosa, jossa on ohjelman logo
NameTableYlaosa:
	db $55,$55,$55,$66,$66,$66,$66,$66, $A5,$55,$55,$66,$A6,$66,$A5,$66
	db $A5,$55,$55,$66,$A6,$66,$A6,$66, $66,$A6,$65,$A9,$55,$55,$55,$55
	db $55,$55,$55,$66,$96,$66,$A6,$65, $A6,$75,$F5,$66,$66,$66,$A5,$65
	db $A6,$75,$F5,$66,$A5,$66,$A6,$66, $66,$66,$55,$99,$55,$55,$55,$55
	db $55,$55,$55,$65,$65,$65,$65,$65, $A5,$55,$55,$65,$65,$65,$A5,$65
	db $A5,$55,$55,$65,$55,$65,$65,$65, $65,$65,$55,$95,$55,$55,$55,$55

AlkuPaletit:
	; Taustagrafiikka
	db white, red, green, blue   ; piirtoalue; samat kuin kahdessa viimeisessa spritepaletissa
	db white, yellow, green, purple   ; yla- ja alapalkki
	db white, white, white, white   ; ei kaytossa
	db white, white, white, white   ; ei kaytossa
	; Spritet
	db white, yellow, black, olive   ; statuspalkin peitesprite, statuspalkin teksti, kursori
	db white, black, white, yellow   ; paletinvalintaruutu - tekstit ja nuoli
	db white, black, white, red   ; paletinvalintaruutu - valitut varit 0 ja 1
	db white, black, green, blue   ; paletinvalintaruutu - valitut varit 2 ja 3

	; Tavalliset spritet. Y, kuva, ominaisuudet, X.
TavSpritet:
	db $00    ,    $02, %00000000, 0 * 8   ; kursori
	db 28 * 8 - 1, $00, %00000000, 1 * 8   ; X-kymmenet
	db 28 * 8 - 1, $00, %00000000, 2 * 8   ; X-ykkoset
	db 28 * 8 - 1, $00, %00000000, 5 * 8   ; Y-kymmenet
	db 28 * 8 - 1, $00, %00000000, 6 * 8   ; Y-ykkoset
	db 28 * 8 - 1, $04, %00000000, 3 * 8   ; pilkku
	db 28 * 8 - 1, $01, %00000000, 9 * 8   ; peite 1
	db 29 * 8 - 1, $01, %00000000, 8 * 8   ; peite 2
	db 29 * 8 - 1, $01, %00000000, 9 * 8   ; peite 3
	TavSpritetLoppu:

	; Paletinvalintaspritet
PalValSpritet:
	db 22 * 8 - 1, $07, %00000001, 1 * 8   ; kursori
	db 22 * 8 - 1, $08, %00000010, 2 * 8   ; valittu vari 0
	db 23 * 8 - 1, $09, %00000010, 2 * 8   ; valittu vari 1
	db 24 * 8 - 1, $08, %00000011, 2 * 8   ; valittu vari 2
	db 25 * 8 - 1, $09, %00000011, 2 * 8   ; valittu vari 3
	db 26 * 8 - 1, $01, %00000001, 1 * 8   ; varinumeron 1. numero
	db 26 * 8 - 1, $01, %00000001, 2 * 8   ; varinumeron 2. numero
	db 21 * 8 - 1, $05, %00000001, 1 * 8   ; "PAL", vasen puoli
	db 21 * 8 - 1, $06, %00000001, 2 * 8   ; "PAL", oikea puoli
	db 22 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
	db 23 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
	db 24 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
	db 25 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
	PalValSpritetLoppu:

TAVSPRTAVUJA    = TavSpritetLoppu    - TavSpritet
PALVALSPRTAVUJA = PalValSpritetLoppu - PalValSpritet

; --------------------------------------------------------------------------------------------------
; CHR data (256 tiles)

	pad $d000
CHRdata:
	incbin "paint.chr"

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

	pad $fffa
	dw nmi, reset, 0
