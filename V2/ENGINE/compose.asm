; =====================================================================
;  compose.asm - compositor de trajes de SCUMM v2 en celdas de 4 bpp (formato B de los sprites). PLAN_TRAJES4.md, etapa 3 (prototipo).
;  Referencia: TOOLS/costume2.py (Costume.render + cells4), que sigue a ScummVM (costume.cpp / akos v2: cada miembro, su imagen RLE por columnas,
;  colocada con su rx/ry y el movimiento acumulado de los miembros anteriores; espejo para la izquierda).
;
;  Entrada (variables CP_*): CP_COST = el traje original (el recurso tal cual: los offsets son desde su principio), CP_EMAP = 16 bytes
;  (color del traje -> codigo Chroma; el 0 es transparente y no se mira), CP_LIMB = 16 bytes (posicion en animCmds de cada miembro, $FF = ninguno),
;  CP_MIR = 1 dibuja al reves (mirando a la izquierda), CP_CAN = lienzo de trabajo, CP_OUT = la pose.
;  Salida en CP_OUT: s16 dx, s16 dy (esquina de la imagen respecto al actor), u8 ancho y alto en celdas, u8 n y n x (u8 cx | cy << 4, 32 bytes de
;  celda: 8 filas de 4 bytes, nibble alto = pixel de la izquierda; 8 bytes de forma: 1 = hay pixel). Las celdas vacias no salen. Carry: nada que dibujar.
; =====================================================================

CP_LE           equ 8                   ; bytes por miembro en la lista: x (2), y (2), ancho, alto, datos (2)

compose:        ld hl,$7FFF             ; caja: minimos a +inf, maximos a -inf
                ld (cp_x0),hl
                ld (cp_y0),hl
                ld hl,$8000
                ld (cp_x1),hl
                ld (cp_y1),hl
                ld hl,0
                ld (cp_xm),hl
                ld (cp_ym),hl
                xor a
                ld (cp_n),a
                ld (cp_i),a
                ld hl,cp_list
                ld (cp_lp),hl
; ---- pasada 1: posicion y tamano de cada miembro
cp_l1:          ld a,(cp_i)
                ld e,a
                ld d,0
                ld hl,(CP_LIMB)
                add hl,de
                ld a,(hl)               ; posicion en animCmds
                cp $FF
                jp z,cp_next
                ld e,a
                ld ix,(CP_COST)
                ld l,(ix+7)
                ld h,(ix+8)             ; cmds
                ld bc,(CP_COST)
                add hl,bc
                add hl,de
                ld a,(hl)
                and $7F
                cp $7B
                jp z,cp_next
                add a,a                 ; codigo * 2
                ld e,a
                ld d,0
                ld a,(cp_i)
                add a,a
                add a,9
                ld c,a
                ld b,0
                ld hl,(CP_COST)
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)               ; BC = tabla de imagenes del miembro
                ld hl,(CP_COST)
                add hl,bc
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld hl,(CP_COST)
                add hl,bc
                push hl
                pop ix                  ; IX = imagen: ancho, alto, rx, ry, mx, my (16 bits) y el RLE
                ld iy,(cp_lp)
                ld a,(ix+0)
                ld (iy+4),a             ; ancho
                ld a,(ix+2)
                ld (iy+5),a             ; alto
                push ix
                pop hl
                ld de,12
                add hl,de
                ld (iy+6),l
                ld (iy+7),h             ; los datos RLE
                ld l,(ix+4)             ; x0 = xm + rx - 72
                ld h,(ix+5)
                ld de,(cp_xm)
                add hl,de
                ld de,-72
                add hl,de
                ld a,(CP_MIR)
                or a
                jr z,cp_nm
                ex de,hl                ; espejo: x0 = 16 - x0 - ancho
                ld hl,16
                or a
                sbc hl,de
                ld e,(ix+0)
                ld d,0
                or a
                sbc hl,de
                jr cp_xs
cp_nm:          ld de,8
                add hl,de               ; a derechas la x se retrasa una franja (ScummVM, v2)
cp_xs:          ld (iy+0),l
                ld (iy+1),h
                ld de,(cp_x0)           ; minimo x
                call cp_lt
                jr nc,cp_x0k
                ld (cp_x0),hl
cp_x0k:         ld e,(ix+0)
                ld d,0
                add hl,de               ; x0 + ancho
                ld de,(cp_x1)
                ex de,hl
                call cp_lt              ; cp_x1 < x0 + ancho?
                jr nc,cp_x1k
                ld (cp_x1),de
cp_x1k:         ld l,(ix+6)             ; y0 = ym + ry - 100
                ld h,(ix+7)
                ld de,(cp_ym)
                add hl,de
                ld de,-100
                add hl,de
                ld (iy+2),l
                ld (iy+3),h
                ld de,(cp_y0)
                call cp_lt
                jr nc,cp_y0k
                ld (cp_y0),hl
cp_y0k:         ld e,(ix+2)
                ld d,0
                add hl,de
                ld de,(cp_y1)
                ex de,hl
                call cp_lt
                jr nc,cp_y1k
                ld (cp_y1),de
cp_y1k:         ld hl,(cp_xm)           ; xm += mx, ym -= my
                ld e,(ix+8)
                ld d,(ix+9)
                add hl,de
                ld (cp_xm),hl
                ld hl,(cp_ym)
                ld e,(ix+10)
                ld d,(ix+11)
                or a
                sbc hl,de
                ld (cp_ym),hl
                ld hl,cp_n
                inc (hl)
                ld de,CP_LE
                add iy,de
                ld (cp_lp),iy
cp_next:        ld hl,cp_i
                inc (hl)
                ld a,(hl)
                cp 16
                jp c,cp_l1
                ld a,(cp_n)
                or a
                scf
                ret z
; ---- el lienzo: un byte por pixel ($FF = transparente), por COLUMNAS (como el RLE de SCUMM): pixel (x, y) en CAN + x * alto + y
                ld hl,(cp_x1)
                ld de,(cp_x0)
                or a
                sbc hl,de
                ld de,7
                add hl,de
                srl l
                srl l
                srl l                   ; el ancho cabe en un byte (menos de 256 pixeles)
                ld a,l
                ld (cp_cw),a
                ld hl,(cp_y1)
                ld de,(cp_y0)
                or a
                sbc hl,de
                ld de,7
                add hl,de
                srl l
                srl l
                srl l
                ld a,l
                ld (cp_ch),a
                add a,a
                add a,a
                add a,a
                ld (cp_hc),a            ; alto del lienzo en pixeles (una columna)
                ld e,a
                ld d,0
                ld a,(cp_cw)
                add a,a
                add a,a
                add a,a
                ld b,a                  ; ancho en pixeles
                ld hl,0
cp_mul:         add hl,de
                djnz cp_mul
                ld b,h
                ld c,l
                ld hl,(CP_CAN)
                ld (hl),$FF
                dec bc
                ld d,h
                ld e,l
                inc de
                ldir
; ---- pasada 2: cada miembro, en orden (el siguiente tapa al anterior)
                ld hl,cp_list
                ld (cp_lp),hl
cp_l2:          ld iy,(cp_lp)
                ld l,(iy+6)
                ld h,(iy+7)
                ld (cp_src),hl
                xor a
                ld (cp_run),a           ; sin racha pendiente
                ld a,(iy+0)             ; lx = x0 - X0 (cabe en un byte)
                ld hl,cp_x0
                sub (hl)
                ld b,a
                ld a,(CP_MIR)
                or a
                ld a,b
                jr z,cp_c0
                add a,(iy+4)
                dec a                   ; al reves se empieza por la columna de la derecha
cp_c0:          ld e,a                  ; HL = X * alto
                ld d,0
                ld a,(cp_hc)
                ld b,a
                ld hl,0
                inc b
                jr cp_cm1
cp_cm:          add hl,de
cp_cm1:         djnz cp_cm
                ld a,(iy+2)             ; + ly
                ld de,cp_y0
                ex de,hl
                sub (hl)
                ex de,hl
                ld e,a
                ld d,0
                add hl,de
                ld de,(CP_CAN)
                add hl,de
                ld (cp_cp),hl           ; principio de la columna
                ld a,(iy+4)
                ld (cp_col),a           ; columnas que quedan
cp_c:           ld hl,(cp_cp)
                ld b,(iy+5)             ; pixeles de la columna
cp_px:          ld a,(cp_run)
                or a
                jr nz,cp_have
                push hl                 ; racha nueva: color (nibble alto) y longitud (bajo; 0 = el byte siguiente)
                ld hl,(cp_src)
                ld a,(hl)
                inc hl
                ld c,a
                and 15
                jr nz,cp_r1
                ld a,(hl)
                inc hl
cp_r1:          ld (cp_src),hl
                ld (cp_run),a
                ld a,c
                rrca
                rrca
                rrca
                rrca
                and 15
                jr z,cp_tr              ; color 0: transparente
                ld hl,(CP_EMAP)
                add a,l
                ld l,a
                jr nc,cp_em
                inc h
cp_em:          ld a,(hl)
                and 15
                jr cp_cs
cp_tr:          ld a,$FF
cp_cs:          ld (cp_cl),a
                pop hl
                ld a,(cp_run)
cp_have:        cp b                    ; k = min(racha, lo que queda de columna)
                jr c,cp_k
                ld a,b
cp_k:           ld c,a
                ld a,(cp_run)
                sub c
                ld (cp_run),a
                ld a,b
                sub c
                ld b,a
                ld a,(cp_cl)
                cp $FF
                jr z,cp_skp
                ld e,c                  ; k pixeles de color
cp_put:         ld (hl),a
                inc hl
                dec e
                jr nz,cp_put
                jr cp_dn
cp_skp:         ld e,c                  ; k transparentes: se saltan
                ld d,0
                add hl,de
cp_dn:          ld a,b
                or a
                jr nz,cp_px
                ld hl,(cp_cp)           ; columna siguiente (al reves, la de la izquierda)
                ld a,(cp_hc)
                ld e,a
                ld d,0
                ld a,(CP_MIR)
                or a
                jr nz,cp_cl1
                add hl,de
                jr cp_cl2
cp_cl1:         sbc hl,de
cp_cl2:         ld (cp_cp),hl
                ld hl,cp_col
                dec (hl)
                jp nz,cp_c
                ld de,CP_LE
                add iy,de
                ld (cp_lp),iy
                ld hl,cp_n
                dec (hl)
                jp nz,cp_l2
; ---- pasada 3: el lienzo a celdas de 4 bpp con su forma; las vacias no salen. Fila a fila de la celda: los 8 pixeles estan a un alto de
;      columna (cp_hc) uno de otro. Pixel transparente = $FF: su bit 7 da la forma (al reves) y su nibble no importa (la mascara lo tapa).
                ld ix,(CP_OUT)
                ld hl,(cp_x0)
                ld (ix+0),l
                ld (ix+1),h
                ld hl,(cp_y0)
                ld (ix+2),l
                ld (ix+3),h
                ld a,(cp_cw)
                ld (ix+4),a
                ld a,(cp_ch)
                ld (ix+5),a
                ld (ix+6),0
                ld (cp_cnt),ix          ; contador de celdas
                ld de,7
                add ix,de               ; IX = celda siguiente de la salida
                ld a,(cp_hc)            ; paso de 8 columnas = 8 * alto
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (cp_c8),hl
                ld hl,(CP_CAN)
                ld (cp_rowp),hl         ; fila de celdas: lienzo en (0, cy * 8)
                ld a,(cp_ch)
                ld (cp_cy),a            ; filas de celdas que quedan
cp_oy:          ld hl,(cp_rowp)
                ld (cp_cp),hl
                xor a
                ld (cp_cx),a
cp_ox:          ld a,(cp_cy)            ; posicion: cx | cy << 4 (cy contado desde arriba)
                ld b,a
                ld a,(cp_ch)
                sub b
                add a,a
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(cp_cx)
                or b
                ld (ix+0),a
                push ix
                pop iy
                inc iy                  ; IY = fila 0 de la celda (4 bytes por fila); la forma va en IY + 32
                ld a,(cp_hc)
                ld e,a
                ld d,0
                ld hl,(cp_cp)
                ld a,8
                ld (cp_k8),a            ; filas
cp_ky:          push hl
                ld c,0
                ld a,(hl)               ; pixeles 0 y 1
                add hl,de
                rla
                rl c
                rla
                rla
                rla
                and $F0
                ld b,a
                ld a,(hl)
                add hl,de
                rla
                rl c
                rra
                and $0F
                or b
                ld (iy+0),a
                ld a,(hl)               ; 2 y 3
                add hl,de
                rla
                rl c
                rla
                rla
                rla
                and $F0
                ld b,a
                ld a,(hl)
                add hl,de
                rla
                rl c
                rra
                and $0F
                or b
                ld (iy+1),a
                ld a,(hl)               ; 4 y 5
                add hl,de
                rla
                rl c
                rla
                rla
                rla
                and $F0
                ld b,a
                ld a,(hl)
                add hl,de
                rla
                rl c
                rra
                and $0F
                or b
                ld (iy+2),a
                ld a,(hl)               ; 6 y 7
                add hl,de
                rla
                rl c
                rla
                rla
                rla
                and $F0
                ld b,a
                ld a,(hl)
                rla
                rl c
                rra
                and $0F
                or b
                ld (iy+3),a
                ld a,c
                cpl
                ld (iy+32),a            ; forma de la fila (1 = hay pixel)
                ld bc,4
                add iy,bc
                ld a,(cp_k8)            ; la forma de la fila siguiente esta 3 bytes mas abajo de IY + 32: corregido abajo
                pop hl
                inc hl
                dec a
                ld (cp_k8),a
                jr nz,cp_ky
                ld bc,-32               ; IY volvio 32 bytes de mas (8 filas x 4): las formas quedaron en IY + 32 + 4 * fila, hay que juntarlas
                add iy,bc
                ld a,(iy+32)            ; formas en +33, +37, ... +61 de la celda -> +33..+40
                ld (cp_sh),a
                ld a,(iy+36)
                ld (cp_sh+1),a
                ld a,(iy+40)
                ld (cp_sh+2),a
                ld a,(iy+44)
                ld (cp_sh+3),a
                ld a,(iy+48)
                ld (cp_sh+4),a
                ld a,(iy+52)
                ld (cp_sh+5),a
                ld a,(iy+56)
                ld (cp_sh+6),a
                ld a,(iy+60)
                ld (cp_sh+7),a
                ld hl,cp_sh
                push iy
                pop de
                ld bc,32
                ex de,hl
                add hl,bc
                ex de,hl
                ld bc,8
                ldir
                ld hl,cp_sh             ; si la forma tiene algo, la celda se queda
                ld b,8
                xor a
cp_any:         or (hl)
                inc hl
                djnz cp_any
                or a
                jr z,cp_skip
                ld bc,41
                add ix,bc
                ld hl,(cp_cnt)
                ld bc,6
                add hl,bc
                inc (hl)
cp_skip:        ld hl,(cp_cp)           ; celda siguiente a la derecha: 8 columnas
                ld bc,(cp_c8)
                add hl,bc
                ld (cp_cp),hl
                ld a,(cp_cx)
                inc a
                ld (cp_cx),a
                ld hl,cp_cw
                cp (hl)
                jp c,cp_ox
                ld hl,(cp_rowp)         ; fila de celdas siguiente: 8 pixeles mas abajo en la columna
                ld bc,8
                add hl,bc
                ld (cp_rowp),hl
                ld hl,cp_cy
                dec (hl)
                jp nz,cp_oy
                or a
                ret

; HL < DE con signo (16 bits): carry
cp_lt:          push hl
                ld a,h
                xor d
                jp m,cp_lts             ; signos distintos: el negativo es el menor
                or a
                sbc hl,de
                pop hl
                ret
cp_lts:         pop hl
                bit 7,h
                scf
                ret nz
                or a
                ret
