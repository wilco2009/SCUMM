; geom.asm - aritmetica de 32 bits y geometria de las cajas de caminar (se incluye desde game.asm)
;
; Es la version en Z80 de las funciones de SCUMM/TOOLS/vmgame.py (check_xy_in_box, adjust_xy,
; closest_pt_on_line, closest_pt_on_box, next_box), que transcriben boxes.cpp y actor.cpp de ScummVM.
; Los enteros de C de ScummVM son de 32 bits: los productos y cocientes de closestPtOnLine se hacen
; igual (producto modulo 2^32, cociente truncado hacia cero).

; ---- datos temporales (bloque 7)
GSCR            equ $F940               ; zona de trabajo (192 bytes)
N1              equ GSCR+0              ; 32 bits
N2              equ GSCR+4
NR              equ GSCR+8
DR              equ GSCR+12             ; resto de la division
DSGN            equ GSCR+16
CK_X            equ GSCR+18             ; checkXYInBoxBounds: entrada y salida
CK_Y            equ GSCR+20
CK_DX           equ GSCR+22
CK_DY           equ GSCR+24
CK_UY           equ GSCR+26             ; campos de la caja, como palabras
CK_LY           equ GSCR+28
CK_ULX          equ GSCR+30
CK_URX          equ GSCR+32
CK_LLX          equ GSCR+34
CK_LRX          equ GSCR+36
CK_XMIN         equ GSCR+38
CK_XMAX         equ GSCR+40
CK_TOP          equ GSCR+42
CK_BOT          equ GSCR+44
CK_DIST         equ GSCR+46
AX_X            equ GSCR+48             ; adjustXYToBeInBox: entrada y salida
AX_Y            equ GSCR+50
AX_BOX          equ GSCR+52
AX_BEST         equ GSCR+54
AX_RX           equ GSCR+56
AX_RY           equ GSCR+58
AX_I            equ GSCR+60
AX_PLAYER       equ GSCR+61
LN_SX           equ GSCR+62             ; closestPtOnLine
LN_SY           equ GSCR+64
LN_EX           equ GSCR+66
LN_EY           equ GSCR+68
LN_PX           equ GSCR+70
LN_PY           equ GSCR+72
LN_LX           equ GSCR+74
LN_LY           equ GSCR+76
LN_A            equ GSCR+78             ; 32 bits
LN_B            equ GSCR+82
LN_C            equ GSCR+86
LN_DIST         equ GSCR+90
LN_RX           equ GSCR+94
LN_RY           equ GSCR+96
PB_X            equ GSCR+98             ; closestPtOnBox
PB_Y            equ GSCR+100
PB_OX           equ GSCR+102
PB_OY           equ GSCR+104
PB_BEST         equ GSCR+106            ; 32 bits
PB_K            equ GSCR+110
PB_BOX          equ GSCR+112            ; ul, ur, ll, lr: 4 puntos de 2 palabras
NBOXES          equ GSCR+128
NOBJS           equ GSCR+129
MATRIXP         equ GSCR+130
OBJSP           equ GSCR+132
ROOMBLOB        equ $FA00

; ============================================================================================ 32 bits
sx32_n1:                                ; N1 = HL con extension de signo
                ld (N1),hl
                ld a,h
                rla
                sbc a,a
                ld (N1+2),a
                ld (N1+3),a
                ret
sx32_n2:
                ld (N2),hl
                ld a,h
                rla
                sbc a,a
                ld (N2+2),a
                ld (N2+3),a
                ret

neg32:                                  ; HL = direccion de un valor de 32 bits: se cambia de signo
                xor a
                sub (hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                ret

mul32:                                  ; NR = N1 * N2 (32 bits bajos); destruye N1 y N2
                ld hl,0
                ld (NR),hl
                ld (NR+2),hl
m32_l:
                ld hl,(N2)
                ld a,h
                or l
                ld hl,(N2+2)
                or h
                or l
                ret z                   ; N2 = 0: terminado
                ld a,(N2)
                and 1
                jr z,m32_s
                ld hl,(NR)
                ld de,(N1)
                add hl,de
                ld (NR),hl
                ld hl,(NR+2)
                ld de,(N1+2)
                adc hl,de
                ld (NR+2),hl
m32_s:
                ld hl,(N1)
                add hl,hl
                ld (N1),hl
                ld hl,(N1+2)
                adc hl,hl
                ld (N1+2),hl
                ld hl,(N2+2)
                srl h
                rr l
                ld (N2+2),hl
                ld hl,(N2)
                rr h
                rr l
                ld (N2),hl
                jr m32_l

div32s:                                 ; NR = N1 / N2 con signo y truncado hacia cero (N2 != 0)
                ld a,(N1+3)
                ld b,a
                ld a,(N2+3)
                xor b
                ld (DSGN),a             ; bit 7: los signos son distintos
                ld a,(N1+3)
                rla
                jr nc,d32_a
                ld hl,N1
                call neg32
d32_a:
                ld a,(N2+3)
                rla
                jr nc,d32_b
                ld hl,N2
                call neg32
d32_b:
                ld hl,0
                ld (DR),hl
                ld (DR+2),hl
                ld b,32
d32_l:
                push bc
                ld hl,(N1)              ; N1 <<= 1, el bit sale en carry
                add hl,hl
                ld (N1),hl
                ld hl,(N1+2)
                adc hl,hl
                ld (N1+2),hl
                ld hl,(DR)              ; DR = DR * 2 + carry
                adc hl,hl
                ld (DR),hl
                ld hl,(DR+2)
                adc hl,hl
                ld (DR+2),hl
                ; DR >= N2 ?
                ld hl,(DR)
                ld de,(N2)
                or a
                sbc hl,de
                ld (NR),hl              ; DR - N2 provisional
                ld hl,(DR+2)
                ld de,(N2+2)
                sbc hl,de
                jr c,d32_n
                ld (NR+2),hl
                ld hl,(NR)              ; DR = DR - N2
                ld (DR),hl
                ld hl,(NR+2)
                ld (DR+2),hl
                ld hl,N1
                inc (hl)                ; el bit 0 de N1 es 0 tras el desplazamiento
d32_n:
                pop bc
                djnz d32_l
                ld hl,(N1)
                ld (NR),hl
                ld hl,(N1+2)
                ld (NR+2),hl
                ld a,(DSGN)
                rla
                ret nc
                ld hl,NR
                jp neg32

; NR = (HL * DE) / BC con las reglas de C (todo con signo)
muldiv:
                push bc
                push de
                call sx32_n1
                pop hl
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                pop hl
                call sx32_n2
                jp div32s

abs_hl:                                 ; HL = |HL|
                bit 7,h
                ret z
neg_hl:
                ld a,l
                cpl
                ld l,a
                ld a,h
                cpl
                ld h,a
                inc hl
                ret

sless:                                  ; carry si HL < DE con signo; Z si iguales (conserva HL y DE)
                push hl
                push de
                ld a,h
                xor $80
                ld h,a
                ld a,d
                xor $80
                ld d,a
                or a
                sbc hl,de
                pop de
                pop hl
                ret

; ============================================================================================ cajas
box_rec:                                ; A = caja -> HL = su registro; carry si no hay (ERR si es un error)
                ld c,a
                ld a,(NBOXES)
                or a
                jr z,br_none
                ld b,a
                ld a,c
                cp $FF
                jr z,br_none
                cp b
                jr nz,br_chk
                dec a                   ; la caja n se lee como la n-1
                jr br_ok
br_chk:
                jr nc,br_err
br_ok:
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,ROOMBLOB+1
                add hl,de
                or a
                ret
br_none:
                scf
                ret
br_err:
                ld a,E_RANGE
                ld (ERR),a
                scf
                ret

box_flags:                              ; A = caja -> A = banderas (0 si no hay caja); ERR si esta fuera de rango
                call box_rec
                jr c,bf_0
                ld de,7
                add hl,de
                ld a,(hl)
                ret
bf_0:
                xor a
                ret

; checkXYInBoxBounds de Actor_v2: HL = caja; CK_X, CK_Y -> HL = distancia, CK_DX, CK_DY = punto
check_xy:
                ld b,6
                ld de,CK_UY
cx_ld:
                ld a,(hl)
                ld (de),a
                inc hl
                inc de
                xor a
                ld (de),a
                inc de
                djnz cx_ld
                ld hl,(CK_Y)
                ld de,(CK_UY)
                call sless
                jr nc,cx_2
                ld hl,(CK_UY)           ; y < uy
                ld (CK_DY),hl
                ld hl,(CK_ULX)
                ld (CK_XMIN),hl
                ld hl,(CK_URX)
                ld (CK_XMAX),hl
                jp cx_fin
cx_2:
                ld hl,(CK_Y)
                ld de,(CK_LY)
                call sless
                jr c,cx_3
                ld hl,(CK_LY)           ; y >= ly
                ld (CK_DY),hl
                ld hl,(CK_LLX)
                ld (CK_XMIN),hl
                ld hl,(CK_LRX)
                ld (CK_XMAX),hl
                jp cx_fin
cx_3:
                ld hl,(CK_X)
                ld de,(CK_ULX)
                call sless
                jr c,cx_search
                ld de,(CK_LLX)
                call sless
                jr c,cx_search
                ld de,(CK_URX)
                call sless
                jr nc,cx_search
                ld de,(CK_LRX)
                call sless
                jr nc,cx_search
                ld hl,(CK_Y)            ; dentro de la caja
                ld (CK_DY),hl
                ld hl,(CK_X)
                ld (CK_XMIN),hl
                ld (CK_XMAX),hl
                jp cx_fin
cx_search:
                ld hl,(CK_Y)
                ld (CK_DY),hl
                ld hl,(CK_UY)
                ld (CK_TOP),hl
                ld hl,(CK_LY)
                ld (CK_BOT),hl
cx_loop:
                ld hl,(CK_ULX)          ; xmin = (ul + ll) / 2
                ld de,(CK_LLX)
                add hl,de
                srl h
                rr l
                ld (CK_XMIN),hl
                ld hl,(CK_URX)          ; xmax = (ur + lr) / 2
                ld de,(CK_LRX)
                add hl,de
                srl h
                rr l
                ld (CK_XMAX),hl
                ld hl,(CK_TOP)          ; cury = (top + bottom) / 2
                ld de,(CK_BOT)
                add hl,de
                srl h
                rr l
                ld de,(CK_Y)
                push hl
                or a
                sbc hl,de               ; flags de cury - y
                pop hl                  ; HL = cury
                jr z,cx_fin             ; cury == y
                jr c,cx_up
                ld (CK_BOT),hl          ; cury > y
                ld hl,(CK_XMIN)
                ld (CK_LLX),hl
                ld hl,(CK_XMAX)
                ld (CK_LRX),hl
                jr cx_loop
cx_up:
                ld (CK_TOP),hl          ; cury < y
                ld hl,(CK_XMIN)
                ld (CK_ULX),hl
                ld hl,(CK_XMAX)
                ld (CK_URX),hl
                jr cx_loop
cx_fin:
                ld hl,(CK_X)            ; destX = x recortado a [xmin, xmax]
                ld de,(CK_XMIN)
                call sless
                jr nc,cx_f1
                ld hl,(CK_XMIN)
                jr cx_f3
cx_f1:
                ld hl,(CK_XMAX)
                ld de,(CK_X)
                call sless
                jr nc,cx_f2
                ld hl,(CK_XMAX)
                jr cx_f3
cx_f2:
                ld hl,(CK_X)
cx_f3:
                ld (CK_DX),hl
                ld de,(CK_X)            ; xd = |x - destX|
                ex de,hl
                or a
                sbc hl,de
                call abs_hl
                ld (CK_UY),hl           ; (CK_UY ya no hace falta)
                ld hl,(CK_Y)            ; yd = |y - destY| / 4
                ld de,(CK_DY)
                or a
                sbc hl,de
                call abs_hl
                srl h
                rr l
                srl h
                rr l
                ex de,hl                ; DE = yd
                ld hl,(CK_UY)           ; HL = xd
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,cx_d1             ; xd >= yd
                srl h                   ; xd < yd: (xd >> 1) + yd
                rr l
                add hl,de
                ret
cx_d1:
                ex de,hl                ; (yd >> 1) + xd
                srl h
                rr l
                add hl,de
                ret

is_player:                              ; IX = actor -> carry si es el jugador (VAR(42) <= num <= VAR(43))
                ld l,(ix+15)
                ld h,0
                ld de,(VAR_PLAYER_MIN)
                call sless              ; num < VAR(42)?
                jr c,ip_no
                ld hl,(VAR_PLAYER_MAX)
                ld e,(ix+15)
                ld d,0
                call sless              ; VAR(43) < num?
                jr c,ip_no
                scf
                ret
ip_no:
                or a
                ret

; adjustXYToBeInBox de Actor_v2: IX = actor; AX_X, AX_Y -> AX_RX, AX_RY, AX_BOX (255 si no hay caja)
adjust_xy:
                call is_player
                ld a,0
                rla
                ld (AX_PLAYER),a
                ld hl,(AX_X)
                ld (AX_RX),hl
                ld hl,(AX_Y)
                ld (AX_RY),hl
                ld a,$FF
                ld (AX_BOX),a
                ld hl,$00FF
                ld (AX_BEST),hl
                ld a,(NBOXES)
                or a
                ret z
                ld (AX_I),a
ax_loop:
                ld a,(AX_I)
                dec a
                ld (AX_I),a             ; caja = n - 1 - i, de la ultima a la primera
                call box_flags
                ld c,a
                ld a,(ERR)
                or a
                ret nz
                ld a,c
                and $80
                jr z,ax_ok              ; no es invisible
                ld a,c
                and $20
                jr z,ax_next            ; invisible y no es solo del jugador: se salta
                ld a,(AX_PLAYER)
                or a
                jr z,ax_ok              ; solo del jugador y no lo es: se usa
                jr ax_next
ax_ok:
                ld hl,(AX_X)
                ld (CK_X),hl
                ld hl,(AX_Y)
                ld (CK_Y),hl
                ld a,(AX_I)
                call box_rec
                call check_xy
                ld a,h
                or l
                jr z,ax_found
                ex de,hl
                ld hl,(AX_BEST)
                or a
                sbc hl,de               ; best - dist
                jr z,ax_next
                jr c,ax_next            ; dist >= best
                ld (AX_BEST),de
                ld hl,(CK_DX)
                ld (AX_RX),hl
                ld hl,(CK_DY)
                ld (AX_RY),hl
                ld a,(AX_I)
                ld (AX_BOX),a
ax_next:
                ld a,(AX_I)
                or a
                jr nz,ax_loop
                ret
ax_found:
                ld hl,(CK_DX)
                ld (AX_RX),hl
                ld hl,(CK_DY)
                ld (AX_RY),hl
                ld a,(AX_I)
                ld (AX_BOX),a
                ret

; ============================================================================================ puntos mas cercanos
; closestPtOnLine: LN_SX..LN_PY -> LN_RX, LN_RY
closest_line:
                ld hl,(LN_EX)
                ld de,(LN_SX)
                or a
                sbc hl,de
                ld (LN_LX),hl
                ld hl,(LN_EY)
                ld de,(LN_SY)
                or a
                sbc hl,de
                ld (LN_LY),hl
                ld hl,(LN_EX)
                ld de,(LN_SX)
                or a
                sbc hl,de
                jr nz,cl_h
                ld hl,(LN_SX)           ; recta vertical
                ld (LN_RX),hl
                ld hl,(LN_PY)
                ld (LN_RY),hl
                jp cl_clamp
cl_h:
                ld hl,(LN_EY)
                ld de,(LN_SY)
                or a
                sbc hl,de
                jr nz,cl_gen
                ld hl,(LN_PX)           ; recta horizontal
                ld (LN_RX),hl
                ld hl,(LN_SY)
                ld (LN_RY),hl
                jp cl_clamp
cl_gen:
                ld hl,(LN_LX)           ; dist = lx*lx + ly*ly
                ld d,h
                ld e,l
                call sx32_n1
                ld h,d
                ld l,e
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (LN_DIST),hl
                ld hl,(NR+2)
                ld (LN_DIST+2),hl
                ld hl,(LN_LY)
                ld d,h
                ld e,l
                call sx32_n1
                ld h,d
                ld l,e
                call sx32_n2
                call mul32
                ld hl,(LN_DIST)
                ld de,(NR)
                add hl,de
                ld (LN_DIST),hl
                ld hl,(LN_DIST+2)
                ld de,(NR+2)
                adc hl,de
                ld (LN_DIST+2),hl
                ld hl,(LN_LX)           ; |lx| > |ly| ?
                call abs_hl
                ex de,hl
                ld hl,(LN_LY)
                call abs_hl
                or a
                sbc hl,de               ; |ly| - |lx|
                jr nc,cl_y              ; |ly| >= |lx|: se usa la otra rama
                ; ---- |lx| > |ly|: a = sx*ly/lx, b = px*lx/ly
                ld hl,(LN_SX)
                ld de,(LN_LY)
                ld bc,(LN_LX)
                call muldiv
                call st_a
                ld hl,(LN_PX)
                ld de,(LN_LX)
                ld bc,(LN_LY)
                call muldiv
                call st_b
                call calc_c_sy_py       ; c = (a + b - sy + py) * ly * lx / dist
                ld hl,(LN_C)            ; x = c
                ld (LN_RX),hl
                ld hl,(LN_LY)           ; y = c * ly / lx - a + sy
                call c_mul_div          ; NR = c * HL / lx
                ld hl,(NR)
                ld de,(LN_A)
                or a
                sbc hl,de
                ld de,(LN_SY)
                add hl,de
                ld (LN_RY),hl
                jr cl_clamp
cl_y:
                ; ---- otra rama: a = sy*lx/ly, b = py*ly/lx
                ld hl,(LN_SY)
                ld de,(LN_LX)
                ld bc,(LN_LY)
                call muldiv
                call st_a
                ld hl,(LN_PY)
                ld de,(LN_LY)
                ld bc,(LN_LX)
                call muldiv
                call st_b
                call calc_c_sx_px
                ld hl,(LN_C)
                ld (LN_RY),hl
                ld hl,(LN_LX)           ; x = c * lx / ly - a + sx
                call c_mul_div2         ; NR = c * lx / ly
                ld hl,(NR)
                ld de,(LN_A)
                or a
                sbc hl,de
                ld de,(LN_SX)
                add hl,de
                ld (LN_RX),hl
cl_clamp:
                ld hl,(LN_LY)           ; |ly| < |lx| ?
                call abs_hl
                ex de,hl
                ld hl,(LN_LX)
                call abs_hl
                ex de,hl                ; HL = |ly|, DE = |lx|
                or a
                sbc hl,de
                jr nc,cc_y
                ld hl,(LN_LX)           ; ---- recorte por x
                bit 7,h
                jr nz,cc_xneg
                ld hl,(LN_RX)           ; lx > 0
                ld de,(LN_SX)
                call sless
                jr c,cc_start
                ld hl,(LN_EX)
                ld de,(LN_RX)
                call sless
                jr c,cc_end
                ret
cc_xneg:
                ld hl,(LN_SX)           ; lx < 0
                ld de,(LN_RX)
                call sless
                jr c,cc_start
                ld hl,(LN_RX)
                ld de,(LN_EX)
                call sless
                jr c,cc_end
                ret
cc_y:
                ld hl,(LN_LY)           ; ---- recorte por y
                bit 7,h
                jr nz,cc_yneg
                ld hl,(LN_RY)
                ld de,(LN_SY)
                call sless
                jr c,cc_start
                ld hl,(LN_EY)
                ld de,(LN_RY)
                call sless
                jr c,cc_end
                ret
cc_yneg:
                ld hl,(LN_SY)
                ld de,(LN_RY)
                call sless
                jr c,cc_start
                ld hl,(LN_RY)
                ld de,(LN_EY)
                call sless
                jr c,cc_end
                ret
cc_start:
                ld hl,(LN_SX)
                ld (LN_RX),hl
                ld hl,(LN_SY)
                ld (LN_RY),hl
                ret
cc_end:
                ld hl,(LN_EX)
                ld (LN_RX),hl
                ld hl,(LN_EY)
                ld (LN_RY),hl
                ret

st_a:                                   ; LN_A = NR
                ld hl,(NR)
                ld (LN_A),hl
                ld hl,(NR+2)
                ld (LN_A+2),hl
                ret
st_b:
                ld hl,(NR)
                ld (LN_B),hl
                ld hl,(NR+2)
                ld (LN_B+2),hl
                ret

; LN_C = ((A + B - u + v) * ly * lx) / dist  (aritmetica de 32 bits)
calc_c_sy_py:
                ld hl,(LN_SY)
                ld de,(LN_PY)
                jr calc_c
calc_c_sx_px:
                ld hl,(LN_SX)
                ld de,(LN_PX)
calc_c:
                push de
                push hl
                ld hl,(LN_A)            ; t = A + B
                ld de,(LN_B)
                add hl,de
                ld (N1),hl
                ld hl,(LN_A+2)
                ld de,(LN_B+2)
                adc hl,de
                ld (N1+2),hl
                pop hl                  ; t = t - u
                call sx32_n2
                call sub32_n1_n2
                pop hl                  ; t = t + v
                call sx32_n2
                call add32_n1_n2
                ld hl,(LN_LY)           ; t * ly
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                ld hl,(LN_LX)           ; * lx
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                ld hl,(LN_DIST)         ; / dist
                ld (N2),hl
                ld hl,(LN_DIST+2)
                ld (N2+2),hl
                call div32s
                ld hl,(NR)
                ld (LN_C),hl
                ld hl,(NR+2)
                ld (LN_C+2),hl
                ret

add32_n1_n2:                            ; N1 = N1 + N2
                ld hl,(N1)
                ld de,(N2)
                add hl,de
                ld (N1),hl
                ld hl,(N1+2)
                ld de,(N2+2)
                adc hl,de
                ld (N1+2),hl
                ret
sub32_n1_n2:                            ; N1 = N1 - N2
                ld hl,(N1)
                ld de,(N2)
                or a
                sbc hl,de
                ld (N1),hl
                ld hl,(N1+2)
                ld de,(N2+2)
                sbc hl,de
                ld (N1+2),hl
                ret

c_mul_div:                              ; NR = C * HL / lx
                ld bc,(LN_LX)
                jr c_md
c_mul_div2:                             ; NR = C * HL / ly
                ld bc,(LN_LY)
c_md:
                push bc
                push hl
                ld hl,(LN_C)
                ld (N1),hl
                ld hl,(LN_C+2)
                ld (N1+2),hl
                pop hl
                call sx32_n2
                call mul32
                ld hl,(NR)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                pop hl
                call sx32_n2
                jp div32s
