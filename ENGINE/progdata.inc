; GENERADO A MANO: datos del programa (sin codigo) que van por encima de $8000 (scumm.asm) o junto a las tablas (pruebas del PC)
TURN_TABLE:     defb 0,2,2,3,2,1,2,3,0,1,2,1,0,1,0,3
tx_nodata:      defb "NO DATA",0
tx_err:         defb "ERROR ",0
cur_pix:        defb $80,$C0,$E0,$F0,$F8,$E0,$B0,$18
font_src:       defb 0
                defb 28,29,30,31,32,33,34,35,36,37
                defb 38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
                defb 24,14,27,26,15,22,11,$80,$81
font_cus:       defb $00,$18,$18,$18,$18,$00,$18,$00        ; !
                defb $00,$08,$08,$10,$00,$00,$00,$00        ; '
ega2chroma:     defb 0,1,4,5,2,3,6,7,8,9,12,13,10,11,14,15
                include "game_data.inc"
