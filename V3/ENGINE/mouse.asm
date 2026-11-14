; mouse.asm - raton Bluetooth del SD81 Booster (se incluye desde overlay.asm). Lo llama keys (scumm.asm) una vez por fotograma.
;
; Lee el puerto $3FEF de la FPGA como EXAMPLES/MOUSE/mouseport.inc (OUT $24 elige el indice 20 y toma la foto; 8 INs: x, y, botones, rueda, rawx, rawy,
; seq, estado). Sin ratón (estado distinto de 1: bit 0 = conectado, el resto a 0; con una FPGA vieja el indice 20 no es el raton) no hace nada y devuelve 0:
; el juego va con teclas exactamente igual que antes. Con raton, si la posicion cambia, pone cur_x y cur_y (el teclado puede seguir moviendolo); devuelve
; en A los botones ya colocados como los espera keys: bit 4 izquierdo (el mismo bit que ESPACIO) y bit 5 derecho. Destruye BC, D, HL.
MP_PORT         equ $3FEF

ms_poll:        ld bc,MP_PORT
                ld a,$24
                out (c),a
                ld hl,MS_BUF
                ld d,8
msp_l:          in a,(c)
                ld (hl),a
                inc hl
                dec d
                jr nz,msp_l
                ld a,(MS_BUF+7)         ; estado: solo vale 1 (conectado)
                dec a
                jr z,msp_on
                xor a
                ld (MS_LX),a            ; sin raton: la proxima vez que aparezca, el cursor salta a su posicion
                ld (MS_LY),a
                ret
msp_on:         ld hl,(MS_BUF)          ; L = x, H = y
                ld de,(MS_LX)
                ld a,l
                cp e
                jr nz,msp_mv
                ld a,h
                cp d
                jr z,msp_btn            ; no se ha movido
msp_mv:
                ld (MS_LX),hl
                ld a,l
                cp 249
                jr c,msp_x
                ld a,248
msp_x:          ld (cur_x),a
                ld a,h
                cp 185
                jr c,msp_y
                ld a,184
msp_y:          ld (cur_y),a
msp_btn:        ld a,(MS_BUF+2)
                and 3
                rlca
                rlca
                rlca
                rlca                    ; bit 0 -> 4 (izquierdo), bit 1 -> 5 (derecho)
                ret
