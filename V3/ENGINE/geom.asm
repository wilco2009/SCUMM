; =====================================================================
;  geom.asm - geometria de las cajas de v3 (fase 6), en el overlay D (se incluye desde ovld.asm).
;  Es boxes.cpp de ScummVM (version 3) tal como lo transcribe V3/TOOLS/vmgame3.py: closestPtOnLine, getClosestPtOnBox, checkXYInBoxBounds,
;  inBoxQuickReject, getGates, findPathTowardsOld, getNextBox y adjustXYToBeInBox.
;  Toda la aritmetica de closestPtOnLine y de compareSlope es la de un int de C: 32 bits con signo que desbordan (wrap32 del modelo);
;  los puntos son Common::Point (int16). Una division por cero (ScummVM se cuelga) es E_RANGE.
;  IX = actor en todo el overlay (no se toca); IY = caja (su registro de RBLOB: 4 esquinas de 4 bytes ul, ur, lr, ll; +17 banderas).
;  Variables: GW (bloque 7, vm_core.asm). Nada de esto sobrevive a otra llamada del overlay.
; =====================================================================
LUM             equ GW+0                ; fase 10d (cpl_gen): |lu|, |lv|, sus signos y b
LVM             equ GW+2
LSG             equ GW+4
LBV              equ GW+5                ; 4
LNS              equ GW+26               ; closestPtOnLine: inicio del segmento (x, y), fin, punto (contiguos) y resultado
LNE              equ GW+30
LNP              equ GW+34
LNR              equ GW+38
LU              equ GW+42               ; 32 bits: diferencia del segmento en el eje mayor (u) y en el menor (v)
LV              equ GW+46
LA              equ GW+50
LC              equ GW+54
LDIST           equ GW+58
LSWAP           equ GW+62               ; 1: el eje mayor es y (se trabaja con x e y cambiadas)
MSGN            equ GW+63               ; signo de sdiv
BP              equ GW+64               ; 4: el punto de cpb, cxb y ax_bd
CBBEST          equ GW+68               ; 4: getClosestPtOnBox: mejor distancia (32 bits) y su punto
CBOUT           equ GW+72
CBK             equ GW+76               ; arista / esquina en curso
AXT             equ GW+77               ; palabra: axis_cnt
QAX             equ GW+80
C1              equ GW+81               ; compareSlope: p1, p2, p3 (12 bytes)
C2              equ GW+85
C3              equ GW+89
CL              equ GW+93               ; 4: lado izquierdo
DMS             equ GW+97               ; signo de dmul
GB1P            equ GW+98               ; getGates: punteros de las cajas 1 y 2
GB2P            equ GW+100
GCOR            equ GW+102              ; 8 esquinas (32 B)
GCPT            equ GW+134              ; 8 puntos mas cercanos (32 B)
GDIST           equ GW+166              ; 8 distancias (16 bits, saturadas)
GCLO            equ GW+182              ; closest[3]
GMD             equ GW+185              ; minDist[3] (raiz: un byte)
GBX             equ GW+188              ; box[3]
GI              equ GW+191
GJ              equ GW+192
GMIN            equ GW+193              ; palabra
GA              equ GW+195              ; gateA[0], gateA[1] (8 B)
GB              equ GW+203              ; gateB[0], gateB[1]
P2              equ GW+211              ; findPathTowardsOld: p2 y p3 (x = 32000: no hay)
P3              equ GW+215
FPOS            equ GW+219              ; 4: posicion del actor
FDST            equ GW+223              ; 4: destino final
FBX2            equ GW+227
FFIN            equ GW+228
CBT             equ GW+229              ; fase 10d: umbral de cpb_t (lo pone adjust_xy) y el de la poda en curso
CBTH            equ GW+231
AXPL            equ GW+233              ; el actor es jugador
AXTI            equ GW+234              ; indice del umbral
AXBEST          equ GW+235              ; palabra
AXBB            equ GW+237
AXBOX           equ GW+238
GEOM_END        equ GW+239              ; (walk.asm sigue aqui)

; ---------------------------------------------------------------- utilidades de 16 y 32 bits
sless16:        ld a,h                  ; HL < DE con signo: carry si es menor, Z si igual (destruye H y D)
                xor $80
                ld h,a
                ld a,d
                xor $80
                ld d,a
                or a
                sbc hl,de
                ret

; sdiff: HL - DE con signo (s16, resultado de 17 bits) -> HL = valor absoluto (16 bits), A = 1 si era negativo. Destruye BC
sdiff:          ld a,h
                rla
                sbc a,a
                ld b,a
                ld a,d
                rla
                sbc a,a
                ld c,a
                or a
                sbc hl,de
                ld a,b
                sbc a,c
                rla
                ld a,0
                rla                     ; A = bit de signo
                or a
                ret z
                xor a
                sub l
                ld l,a
                ld a,0
                sbc a,h
                ld h,a
                ld a,1
                ret

; sub17: DE:HL = HL - DE (s16) con extension de signo a 32 bits. Destruye BC
sub17:          ld a,h
                rla
                sbc a,a
                ld b,a
                ld a,d
                rla
                sbc a,a
                ld c,a
                or a
                sbc hl,de
                ld a,b
                sbc a,c
                ld e,a
                ld d,a
                ret

mag17:          bit 7,d                 ; DE:HL (17 bits con signo) -> HL = valor absoluto
                ret z
                xor a
                sub l
                ld l,a
                sbc a,a
                sub h
                ld h,a
                ret

; mul16u: BC * DE -> DE:HL (32 bits sin signo). Si uno de los dos cabe en un byte hace de multiplicador y bastan 8 vueltas
mul16u:         ld hl,0
                ld a,d
                or a
                jr z,mu_8
                ld a,b
                or a
                ld a,16
                jr nz,mu_l
                push bc                 ; BC cabe en un byte: se cambian
                ld b,d
                ld c,e
                pop de
mu_8:           ld d,e
                ld e,l
                ld a,8
mu_l:           add hl,hl
                rl e
                rl d
                jr nc,mu_n
                add hl,bc
                jr nc,mu_n
                inc de
mu_n:           dec a
                jr nz,mu_l
                ret

neg_dehl:       xor a                   ; DE:HL = -DE:HL
                sub l
                ld l,a
                ld a,0
                sbc a,h
                ld h,a
                ld a,0
                sbc a,e
                ld e,a
                ld a,0
                sbc a,d
                ld d,a
                ret

; sdiv: NR = N1 / N2 (int de C: truncada hacia cero; N2 != 0). Sin signo y por casos: divisor de 16 bits (dos divisiones 32/16 de 16 vueltas),
; divisor de 17 a 31 bits (el cociente cabe en 16 bits: 16 vueltas con el resto en DE:HL) y divisor 2^31 (el cociente es 0 o 1)
sdiv:           xor a
                ld (MSGN),a
                ld a,(N2+3)
                rla
                jr nc,sv_1
                ld hl,N2
                call neg32
                ld a,1
                ld (MSGN),a
sv_1:           ld a,(N1+3)
                rla
                jr nc,sv_2
                ld hl,N1
                call neg32
                ld a,(MSGN)
                xor 1
                ld (MSGN),a
sv_2:           ld hl,(N2+2)
                ld a,h
                or l
                jr nz,sv_big
                ld bc,(N2)              ; divisor de 16 bits
                ld hl,0
                ld de,(N1+2)
                ld a,d
                or e
                call nz,dv16
                ld (NR+2),de
                ld de,(N1)
                call dv16
                ld (NR),de
                jr sv_sg
sv_big:         bit 7,h
                jr nz,sv_gen
                ld hl,(N1+2)            ; resto = N1 >> 16 (menor que el divisor); entran los 16 bits bajos de N1
                ld de,0
                ld bc,(N1)
                ld a,16
sb_l:           push af
                sla c
                rl b
                adc hl,hl
                ex de,hl
                adc hl,hl
                ex de,hl
                push hl
                push de
                push bc
                ld bc,(N2)
                or a
                sbc hl,bc
                ex de,hl
                ld bc,(N2+2)
                sbc hl,bc
                ex de,hl
                pop bc
                jr c,sb_no
                inc sp                  ; cabe: se queda con la resta
                inc sp
                inc sp
                inc sp
                inc c
                jr sb_n
sb_no:          pop de
                pop hl
sb_n:           pop af
                dec a
                jr nz,sb_l
                ld (NR),bc
                ld hl,0
                ld (NR+2),hl
                jr sv_sg
sv_gen:         ld hl,(N1+2)            ; divisor 2^31 (era INT_MIN): 1 si el dividendo tambien lo es, si no 0
                ld de,$8000
                or a
                sbc hl,de
                ld hl,0
                ld (NR+2),hl
                jr nz,sv_g1
                inc l
sv_g1:          ld (NR),hl
sv_sg:          ld a,(MSGN)
                or a
                ret z
                ld hl,NR
                jp neg32
; dv16: (HL:DE) / BC con HL < BC -> DE = cociente, HL = resto
dv16:           ld a,16
dv_l:           sla e
                rl d
                adc hl,hl
                jr c,dv_o
                sbc hl,bc
                jr nc,dv_s
                add hl,bc
                jr dv_n
dv_o:           or a
                sbc hl,bc
dv_s:           inc e
dv_n:           dec a
                jr nz,dv_l
                ret

; ---------------------------------------------------------------- utilidades de closestPtOnLine (fase 10d)
abs16:          bit 7,h                 ; HL (s16) -> HL = valor absoluto (16 bits sin signo), A = 1 si era negativo
                ld a,0
                ret z
                sub l
                ld l,a
                sbc a,a
                sub h
                ld h,a
                ld a,1
                ret

adds16:         bit 7,b                 ; DE:HL += BC (s16 extendido a 32 bits)
                add hl,bc
                jr nz,as_n
                ret nc
                inc de
                ret
as_n:           ret c
                dec de
                ret

subs16:         ld a,b                  ; DE:HL -= BC (s16 extendido a 32 bits)
                or a
                sbc hl,bc
                jr c,ss_b
                rla
                ret nc
                inc de
                ret
ss_b:           rla
                ret c
                dec de
                ret

; ud3216: (HL) = 32 bits sin signo, BC = divisor (!= 0) -> (HL) = cociente (32 bits). Conserva BC
ud3216:         push hl
                inc hl
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = la palabra alta
                ld h,d
                ld l,e
                or a
                sbc hl,bc
                jr nc,u32_2
                ex de,hl                ; menor que el divisor: cociente alto 0 y ese resto
                ld de,0
                jr u32_1
u32_2:           ld hl,0
                call dv16               ; DE = alto / BC, HL = resto
u32_1:           ex (sp),hl              ; HL = puntero, en la pila el resto
                inc hl
                inc hl
                ld (hl),e
                inc hl
                ld (hl),d
                dec hl
                dec hl
                dec hl
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = la palabra baja
                ex (sp),hl              ; HL = el resto, en la pila el puntero + 1
                call dv16
                pop hl
                ld (hl),d
                dec hl
                ld (hl),e
                ret

; mul_lo: NR = N1 * N2 (32 bits bajos, sin signo: lo mismo que con signo modulo 2^32): Xlo*Ylo + ((Xlo*Yhi + Xhi*Ylo) << 16)
mul_lo:         ld bc,(N1)
                ld de,(N2)
                call mul16u
                ld (NR),hl
                ld (NR+2),de
                ld de,(N2+2)
                ld a,d
                or e
                jr z,ml_1
                ld bc,(N1)
                call mul16u
                ld de,(NR+2)
                add hl,de
                ld (NR+2),hl
ml_1:           ld bc,(N1+2)
                ld a,b
                or c
                ret z
                ld de,(N2)
                call mul16u
                ld de,(NR+2)
                add hl,de
                ld (NR+2),hl
                ret

; sgn32: (HL) = int de 32 bits -> su valor absoluto en su sitio; A = 1 (NZ) si era negativo, 0 (Z) si no
sgn32:          push hl
                inc hl
                inc hl
                inc hl
                ld a,(hl)
                pop hl
                rla
                ld a,0
                ret nc
                call neg32
                ld a,1
                or a
                ret

; ---------------------------------------------------------------- closestPtOnLine
; cpl: LNS = inicio, LNE = fin, LNP = punto -> LNR. Se trabaja con el eje mayor u (x si |lx| > |ly|; si no, y, cambiando x por y en todo:
; las formulas de C son las mismas con los ejes cambiados) y el menor v:
;   lv == 0 (segmento vertical u horizontal): ru = pu, rv = sv
;   si no: a = su*lv/lu; b = pu*lu/lv; c = (a + b - sv + pv)*lv*lu/(lu*lu + lv*lv); ru = c; rv = c*lv/lu - a + sv
; y despues se recorta al segmento a lo largo de u. Conserva IX e IY
cplin:            ld hl,(LNE)
                ld de,(LNS)
                call sub17
                ld (LU),hl
                ld (LU+2),de
                call mag17
                push hl                 ; |lx|
                ld hl,(LNE+2)
                ld de,(LNS+2)
                call sub17
                ld (LV),hl
                ld (LV+2),de
                call mag17              ; |ly|
                pop de
                or a
                sbc hl,de               ; |ly| < |lx|: el eje mayor es x
                ld a,0
                jr c,cpl_ns
                ld hl,LNS
                call swap_pt
                ld hl,LNE
                call swap_pt
                ld hl,LNP
                call swap_pt
                ld hl,LU
                ld de,LV
                ld b,4
cpl_sw:         ld a,(de)
                ld c,(hl)
                ld (hl),a
                ld a,c
                ld (de),a
                inc hl
                inc de
                djnz cpl_sw
                ld a,1
cpl_ns:         ld (LSWAP),a
                ld hl,(LV)
                ld a,h
                or l
                jr nz,cpl_gen
                ld hl,(LNP)
                ld (LNR),hl
                ld hl,(LNS+2)
                ld (LNR+2),hl
                jp cpl_clip
cpl_gen:        ld hl,(LU)              ; fase 10d: sin la pila de 32 bits ni mul32 (antes ~38.000 T por llamada). Mismo calculo de C, con
                ld de,(LU+2)            ; signo y modulo 2^32, por los valores absolutos: |lu|, |lv|, |su| y |pu| caben en 16 bits
                call mag17
                ld (LUM),hl
                ld hl,(LV)
                ld de,(LV+2)
                call mag17
                ld (LVM),hl
                ld a,(LU+3)
                rlca
                and 1
                ld b,a
                ld a,(LV+3)
                rlca
                rlca
                and 2
                or b
                ld (LSG),a              ; bit 0: lu < 0; bit 1: lv < 0
                ld bc,(LUM)             ; dist = lu*lu + lv*lv (modulo 2^32)
                ld d,b
                ld e,c
                call mul16u
                ld (LDIST),hl
                ld (LDIST+2),de
                ld bc,(LVM)
                ld d,b
                ld e,c
                call mul16u
                ld bc,(LDIST)
                add hl,bc
                ld (LDIST),hl
                ex de,hl
                ld bc,(LDIST+2)
                adc hl,bc
                ld (LDIST+2),hl
                ld hl,(LNS)             ; a = su*lv/lu: |su*lv| < 2^31 y |a| <= |su| (|lv| <= |lu|): una division de 16 vueltas
                call abs16
                push af
                ld b,h
                ld c,l
                ld de,(LVM)
                call mul16u
                ex de,hl
                ld bc,(LUM)
                call dv16
                pop bc                  ; signo: su, lv y lu
                ld a,(LSG)
                rrca
                xor b
                ld b,a
                ld a,(LSG)
                xor b
                and 1
                ex de,hl
                ld de,0
                call nz,neg_dehl
                ld (LA),hl
                ld (LA+2),de
                ld hl,(LNP)             ; b = pu*lu/lv (|b| < 2^31)
                call abs16
                push af
                ld b,h
                ld c,l
                ld de,(LUM)
                call mul16u
                ld (LBV),hl
                ld (LBV+2),de
                ld hl,LBV
                ld bc,(LVM)
                call ud3216
                pop bc                  ; signo: pu, lu y lv
                ld a,(LSG)
                rrca
                xor b
                ld b,a
                ld a,(LSG)
                xor b
                and 1
                ld hl,LBV
                call nz,neg32
                ld hl,(LBV)              ; t = a + b - sv + pv
                ld de,(LBV+2)
                ld bc,(LA)
                add hl,bc
                ex de,hl
                ld bc,(LA+2)
                adc hl,bc
                ex de,hl
                ld bc,(LNS+2)
                call subs16
                ld bc,(LNP+2)
                call adds16
                ld (N1),hl
                ld (N1+2),de
                ld hl,N1                ; N = t*lv*lu = |t| * (|lv|*|lu|) con el signo de los tres (modulo 2^32)
                call sgn32
                ld b,a
                ld a,(LSG)
                rrca
                xor b
                ld b,a
                ld a,(LSG)
                xor b
                and 1
                push af
                ld bc,(LVM)
                ld de,(LUM)
                call mul16u
                ld (N2),hl
                ld (N2+2),de
                call mul_lo
                pop af
                ld hl,NR
                call nz,neg32
                ld hl,(NR)              ; c = N / dist (int de C)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                ld hl,(LDIST)
                ld (N2),hl
                ld a,h
                or l
                ld hl,(LDIST+2)
                ld (N2+2),hl
                or h
                or l
                jp z,err_range          ; ScummVM dividiria por cero
                call sdiv
                ld hl,(NR)
                ld (LNR),hl             ; ru = c (los 16 bits bajos)
                ld (N1),hl
                ld hl,(NR+2)
                ld (N1+2),hl
                ld hl,N1                ; M = c*lv (modulo 2^32)
                call sgn32
                ld b,a
                ld a,(LSG)
                rrca
                xor b
                and 1
                push af
                ld hl,(LVM)
                ld (N2),hl
                ld hl,0
                ld (N2+2),hl
                call mul_lo
                pop af
                ld hl,NR
                call nz,neg32
                ld hl,NR                ; q = M / lu (int de C)
                call sgn32
                ld b,a
                ld a,(LSG)
                xor b
                and 1
                push af
                ld hl,NR
                ld bc,(LUM)
                call ud3216
                pop af
                ld hl,(NR)
                jr z,cg_q
                xor a
                sub l
                ld l,a
                sbc a,a
                sub h
                ld h,a
cg_q:           ld de,(LA)              ; rv = q - a + sv (16 bits bajos)
                or a
                sbc hl,de
                ld de,(LNS+2)
                add hl,de
                ld (LNR+2),hl
cpl_clip:       ld a,(LU+3)
                rla
                jr c,cpl_neg            ; lu < 0
                ld hl,(LU)
                ld a,h
                or l
                jr z,cpl_neg            ; lu == 0
                ld hl,(LNR)              ; lu > 0: ru < su -> inicio; ru > eu -> fin
                ld de,(LNS)
                call sless16
                jr c,cpl_rs
                ld hl,(LNE)
                ld de,(LNR)
                call sless16
                jr c,cpl_re
                jr cpl_done
cpl_neg:        ld hl,(LNS)              ; lu <= 0: ru > su -> inicio; ru < eu -> fin
                ld de,(LNR)
                call sless16
                jr c,cpl_rs
                ld hl,(LNR)
                ld de,(LNE)
                call sless16
                jr c,cpl_re
                jr cpl_done
cpl_rs:         ld hl,(LNS)
                ld (LNR),hl
                ld hl,(LNS+2)
                ld (LNR+2),hl
                jr cpl_done
cpl_re:         ld hl,(LNE)
                ld (LNR),hl
                ld hl,(LNE+2)
                ld (LNR+2),hl
cpl_done:       ld a,(LSWAP)
                or a
                ret z
                ld hl,LNR
swap_pt:        ld e,(hl)               ; el punto de (HL): x <-> y
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld (hl),d
                dec hl
                ld (hl),e
                dec hl
                ld (hl),b
                dec hl
                ld (hl),c
                ret

; sqd: Common::Point::sqrDist(BP, LNR) -> DE:HL (0xFFFFFF si una diferencia llega a 0x1000)
sqd:            ld hl,(BP)
                ld de,(LNR)
                call sdiff
                ld a,h
                cp $10
                jr nc,sqd_far
                push hl
                ld hl,(BP+2)
                ld de,(LNR+2)
                call sdiff
                ld a,h
                cp $10
                jr nc,sqd_far1
                ld b,h
                ld c,l
                ld d,h
                ld e,l
                call mul16u             ; dy * dy
                pop bc
                push de
                push hl
                ld d,b
                ld e,c
                call mul16u             ; dx * dx
                pop bc
                add hl,bc
                ex de,hl
                pop bc
                adc hl,bc
                ex de,hl
                ret
sqd_far1:       pop hl
sqd_far:        ld hl,$FFFF
                ld de,$00FF
                ret

; cpb: getClosestPtOnBox(IY = caja, BP = punto) -> HL = distancia al cuadrado saturada a 16 bits ($FFFF si es mayor), CBOUT = el punto
; (0, 0 si ninguna arista da menos de 0xFFFFFF) y CBBEST = la distancia entera.
; cpb_t (fase 10d): lo mismo con poda por arista para quien solo quiere la caja si da menos que CBT (adjust_xy): no calcula las aristas
; cuya cota (edge_lb) llega al umbral (el menor de CBT y la mejor de la caja hasta ahi). Si la caja da menos que CBT, el resultado y el
; punto son los de cpb (la primera arista con la menor distancia no se poda); si no, da CBT o mas. Bit 7 de CBK: con poda
cpb:            xor a
                jr cpb_0
cpb_t:          ld hl,(CBT)
                ld (CBTH),hl
                ld a,$80
cpb_0:          ld hl,$FFFF
                ld (CBBEST),hl
                ld hl,$00FF
                ld (CBBEST+2),hl
                ld hl,0
                ld (CBOUT),hl
                ld (CBOUT+2),hl
cpb_l:          ld (CBK),a
                call corner             ; arista k: de la esquina k a la k + 1
                ld de,LNS
                ld bc,4
                ldir
                ld a,(CBK)
                inc a
                call corner
                ld bc,4
                ldir                    ; LNE
                ld hl,BP
                ld bc,4
                ldir                    ; LNP
                ld a,(CBK)
                rla
                jr nc,cpb_c
                call edge_lb
                ld de,(CBTH)
                or a
                sbc hl,de
                jr nc,cpb_n             ; la arista no puede bajar del umbral
cpb_c:          call cplin
                call sqd
                push hl
                push de
                ld bc,(CBBEST)
                or a
                sbc hl,bc
                ex de,hl
                ld bc,(CBBEST+2)
                sbc hl,bc               ; carry: es menor que la mejor
                pop de
                pop hl
                jr nc,cpb_n
                ld (CBBEST),hl
                ld (CBBEST+2),de
                ld a,d
                or e
                jr nz,cpb_o
                ld de,(CBTH)            ; el umbral de la poda baja con la mejor de la caja
                push hl
                sbc hl,de
                pop hl
                jr nc,cpb_o
                ld (CBTH),hl
cpb_o:          ld hl,(LNR)
                ld (CBOUT),hl
                ld hl,(LNR+2)
                ld (CBOUT+2),hl
cpb_n:          ld a,(CBK)
                inc a
                ld b,a
                and 3
                ld a,b
                jr nz,cpb_l
                ld hl,(CBBEST+2)
                ld a,h
                or l
                ld hl,$FFFF
                ret nz
                ld hl,(CBBEST)
                ret

corner:         and 3                   ; A = esquina (modulo 4) -> HL = su direccion en la caja IY. Conserva DE
                add a,a
                add a,a
                ld c,a
                ld b,0
                push iy
                pop hl
                add hl,bc
                ret

; ---------------------------------------------------------------- compareSlope y checkXYInBoxBounds
; dmul: (HL - DE) * (BC' - DE') ... los cuatro s16 vienen en la pila de llamadas de cslope; ver alli
; cslope: compareSlope(p1 = (HL), p2 = (DE), p3 = (BC)): (p2.y - p1.y) * (p3.x - p1.x) <= (p3.y - p1.y) * (p2.x - p1.x), con los productos
; como int de C (32 bits). A = 1 (NZ) si se cumple, 0 (Z) si no. Conserva IX e IY
cslope:         push bc
                push de
                ld de,C1
                ld bc,4
                ldir
                pop hl
                ld bc,4
                ldir
                pop hl
                ld bc,4
                ldir
                ld hl,(C2+2)            ; lado izquierdo
                ld de,(C1+2)
                call sdiff
                ld (DMS),a
                push hl
                ld hl,(C3)
                ld de,(C1)
                call cs_mul
                ld (CL),hl
                ld (CL+2),de
                ld hl,(C3+2)            ; lado derecho
                ld de,(C1+2)
                call sdiff
                ld (DMS),a
                push hl
                ld hl,(C2)
                ld de,(C1)
                call cs_mul             ; DE:HL = derecho
                ld a,d                  ; izquierdo <= derecho con signo: se invierten los bits de signo y se compara sin signo
                xor $80
                ld d,a
                ld a,(CL+3)
                xor $80
                ld (CL+3),a
                ld bc,(CL)
                or a
                sbc hl,bc
                ex de,hl
                ld bc,(CL+2)
                sbc hl,bc               ; derecho - izquierdo: carry si derecho < izquierdo
                ld a,0
                ccf
                adc a,0
                ret
; el segundo factor es HL - DE; el valor absoluto del primero esta en la pila (bajo la direccion de vuelta) y su signo en DMS -> DE:HL
cs_mul:         call sdiff
                ld c,a
                ld a,(DMS)
                xor c
                ld (DMS),a
                pop bc                  ; la vuelta
                pop de                  ; |primer factor|
                push bc
                ld b,h
                ld c,l
                call mul16u
                ld a,(DMS)
                or a
                ret z
                jp neg_dehl

; axis_cnt: HL = t (s16), A = 0 (x) o 2 (y), IY = caja -> B = esquinas con la coordenada mayor que t, C = con la coordenada menor
axis_cnt:       ld (AXT),hl
                ld e,a
                ld d,0
                push iy
                pop hl
                add hl,de
                ld bc,0
                ld a,4
ac_l:           push af
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                inc hl
                inc hl
                push hl
                ld hl,(AXT)
                call sless16
                jr c,ac_gt
                jr z,ac_nx
                inc c
                jr ac_nx
ac_gt:          inc b
ac_nx:          pop hl
                pop af
                dec a
                jr nz,ac_l
                ret

; cxb: checkXYInBoxBounds (version < 7) con la caja IY y el punto BP -> A = 1 si esta dentro (o en el borde), 0 si no
cxb:            ld hl,(BP)
                xor a
                call axis_cnt
                ld a,b
                cp 4
                jr z,cxb_f
                ld a,c
                cp 4
                jr z,cxb_f
                ld hl,(BP+2)
                ld a,2
                call axis_cnt
                ld a,b
                cp 4
                jr z,cxb_f
                ld a,c
                cp 4
                jr z,cxb_f
                xor a
cxb_l:          ld (CBK),a
                inc a
                call corner
                ex de,hl
                ld a,(CBK)
                call corner
                ld bc,BP
                call cslope
                or a
                ret z
                ld a,(CBK)
                inc a
                cp 4
                jr c,cxb_l
                ld a,1
                ret
cxb_f:          xor a
                ret

; cxb_num: como cxb con el numero de caja en A: la caja invalida ($FF) da 0; sin cajas o con una caja que no existe, E_RANGE
cxb_num:        cp $FF
                jr z,cxb_f
                ld c,a
                ld b,0
                call box_addr
                jp c,err_range
                push hl
                pop iy
                jr cxb

; ---------------------------------------------------------------- getGates y findPathTowardsOld
isqrt16:        ld de,0                 ; HL -> A = parte entera de la raiz
                ld bc,$4000
is_l:           push hl
                ex de,hl
                push hl
                add hl,bc
                ex de,hl
                or a
                sbc hl,de
                jr c,is_no
                pop de
                srl d
                rr e
                ex de,hl
                add hl,bc
                ex de,hl
                inc sp
                inc sp
                jr is_n
is_no:          pop de
                srl d
                rr e
                pop hl
is_n:           srl b
                rr c
                srl b
                rr c
                ld a,b
                or c
                jr nz,is_l
                ld a,e
                ret

absd:           sub (hl)                ; A = |A - (HL)|
                ret nc
                neg
                ret

; gates: getGates(caja 1 = (GB1P), caja 2 = (GB2P)) -> GA (gateA[0], gateA[1]) y GB. Fase 10d: si el par (caja del actor IX, FBX2) esta en la
; tabla de puertas de la sala (GT_OFF de la pagina CLS_PG, por la ventana; ordenada por caja 1 y caja 2; gt_load), se copia de alli
; (pack_data3.gate_table la calcula con get_gates). Si la tabla es de otra sala o no tiene el par, se calcula como siempre
gates:          call cls_open
                ld hl,GT_OFF+WINDOW
                ld a,(ROOMRES)
                cp (hl)
                jr nz,gt_cx
                inc hl
                ld a,(hl)
                or a
                jr z,gt_cx
                ld b,a
                inc hl
                ld c,(ix+A_WBOX)
                ld de,GT_ENTRY
gtl_l:          ld a,(hl)
                cp c
                jr z,gtl_1
                jr nc,gt_cx             ; (ordenada: ya ha pasado la caja 1)
gtl_n:          add hl,de
                djnz gtl_l
gt_cx:          call cls_close
                jr gt_calc
gtl_1:          inc hl
                ld a,(FBX2)
                cp (hl)
                dec hl
                jr nz,gtl_n
                inc hl
                inc hl
                ld a,(hl)               ; linea de gateA | linea de gateB << 4
                inc hl                  ; los dos puntos
                push af
                and 15
                ld de,GA
                call gtl_set
                pop af
                rrca
                rrca
                rrca
                rrca
                and 15
                ld de,GB
                call gtl_set
                jp cls_close
gtl_set:        push hl                 ; A = linea, HL = el punto, DE = la puerta: como set_gate (L < 4: esquina L de la caja 1 y el punto;
                cp 4                    ; si no, el punto y la esquina L - 4 de la caja 2) -> HL = el punto siguiente
                jr nc,gls_2
                add a,a
                add a,a
                ld c,a
                ld b,0
                ld hl,(GB1P)
                add hl,bc
                ld c,4
                ldir                    ; la esquina
                pop hl
                ld c,4
                ldir                    ; el punto
                ret
gls_2:          sub 4
                add a,a
                add a,a
                ld c,a
                ld b,0
                ld hl,(GB2P)
                add hl,bc
                ex (sp),hl              ; HL = el punto, en la pila la esquina
                ld c,4
                ldir
                ex (sp),hl
                ld c,4
                ldir
                pop hl
                ret
gt_calc:        ld hl,(GB1P)
                ld de,GCOR
                ld bc,16
                ldir
                ld hl,(GB2P)
                ld bc,16
                ldir
                xor a
gt_l:           ld (GI),a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,GCOR
                add hl,de
                ld de,BP
                ld bc,4
                ldir
                ld a,(GI)
                cp 4
                ld hl,(GB2P)            ; las esquinas de la caja 1 se acercan a la 2 y al reves
                jr c,gt_b
                ld hl,(GB1P)
gt_b:           push hl
                pop iy
                call cpb
                ex de,hl
                ld a,(GI)
                add a,a
                ld c,a
                ld b,0
                ld hl,GDIST
                add hl,bc
                ld (hl),e
                inc hl
                ld (hl),d
                ld a,(GI)
                add a,a
                add a,a
                ld c,a
                ld hl,GCPT
                add hl,bc
                ex de,hl
                ld hl,CBOUT
                ld bc,4
                ldir
                ld a,(GI)
                inc a
                cp 8
                jr c,gt_l
                xor a                   ; los tres puntos mas cercanos
gt_j:           ld (GJ),a
                ld hl,$FFFF
                ld (GMIN),hl
                ld e,a
                ld d,0
                ld hl,GCLO
                add hl,de
                ld (hl),0               ; (sin candidato: 0, como el modelo; en C queda sin inicializar)
                xor a
gt_i:           ld (GI),a
                add a,a
                ld e,a
                ld d,0
                ld hl,GDIST
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,(GMIN)
                ex de,hl
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,gt_n              ; dist[i] >= min
                ld (GMIN),hl
                ld a,(GJ)
                ld e,a
                ld d,0
                ld hl,GCLO
                add hl,de
                ld a,(GI)
                ld (hl),a
gt_n:           ld a,(GI)
                inc a
                cp 8
                jr c,gt_i
                ld a,(GJ)
                ld e,a
                ld d,0
                ld hl,GCLO
                add hl,de
                ld a,(hl)
                push af
                add a,a
                ld e,a
                ld hl,GDIST
                add hl,de
                ld (hl),$FF             ; dist[closest[j]] = 0xFFFF
                inc hl
                ld (hl),$FF
                ld hl,(GMIN)
                call isqrt16
                ld c,a
                ld a,(GJ)
                ld e,a
                ld d,0
                ld hl,GMD
                add hl,de
                ld (hl),c
                pop af
                cp 4
                ld a,0
                adc a,0
                xor 1                   ; 1 si el punto es de la segunda caja
                ld hl,GBX
                add hl,de
                ld (hl),a
                ld a,(GJ)
                inc a
                cp 3
                jp c,gt_j
                ld a,(GBX)              ; box[0] == box[1] y |d0 - d1| < 4
                ld hl,GBX+1
                cp (hl)
                jr nz,gs_3
                ld a,(GMD)
                ld hl,GMD+1
                call absd
                cp 4
                jr c,gs_01
gs_3:           ld a,(GBX)              ; box[0] == box[2] y d0 == d2
                ld hl,GBX+2
                cp (hl)
                jr nz,gs_4
                ld a,(GMD)
                ld hl,GMD+2
                cp (hl)
                jr z,gs_02
gs_4:           ld a,(GBX+1)            ; box[1] == box[2] y d1 == d2
                ld hl,GBX+2
                cp (hl)
                jr nz,gs_5
                ld a,(GMD+1)
                ld hl,GMD+2
                cp (hl)
                jr z,gs_12
gs_5:           ld a,(GMD)              ; |d0 - d2| < 4: con box[0] == box[2], (0, 2); si no, (1, 2)
                ld hl,GMD+2
                call absd
                cp 4
                jr nc,gs_7
                ld a,(GBX)
                ld hl,GBX+2
                cp (hl)
                jr z,gs_02
                jr gs_12
gs_7:           ld a,(GMD)              ; |d0 - d1| < 4
                ld hl,GMD+1
                call absd
                cp 4
                jr c,gs_01
                ld bc,$0000
                jr gs_set
gs_01:          ld bc,$0001
                jr gs_set
gs_02:          ld bc,$0002
                jr gs_set
gs_12:          ld bc,$0102
gs_set:         push bc
                ld a,b
                call gs_cl
                ld de,GA
                call set_gate
                pop bc
                ld a,c
                call gs_cl
                ld de,GB
set_gate:       ld (GI),a               ; A = linea (0-7), DE = puerta: con una esquina de la caja 1 va primero la esquina; si no, el punto
                add a,a
                add a,a
                ld c,a
                ld b,0
                ld hl,GCOR
                add hl,bc
                push hl
                ld hl,GCPT
                add hl,bc
                ld a,(GI)
                cp 4
                jr nc,sg_1
                ex (sp),hl
sg_1:           ld bc,4
                ldir
                pop hl
                ld bc,4
                ldir
                ret
gs_cl:          ld e,a
                ld d,0
                ld hl,GCLO
                add hl,de
                ld a,(hl)
                ret

; fpo: Actor_v3::findPathTowardsOld(IX = actor, cajas en GB1P y GB2P, FBX2 = numero de la caja 2, FFIN = caja final) -> P2 y P3
fpo:            call gates
                ld hl,32000
                ld (P2),hl
                ld (P3),hl
                push ix
                pop hl
                inc hl                  ; A_X
                ld de,FPOS
                ld bc,4
                ldir
                push ix
                pop hl
                ld bc,A_DESTX
                add hl,bc
                ld bc,4
                ldir                    ; FDST
                ld a,(FBX2)
                ld hl,FFIN
                cp (hl)
                jr nz,fp_1
                ld bc,GA                ; el actor entre las dos puertas?
                call fp_cs
                push af
                ld bc,GB
                call fp_cs
                pop bc
                cp b
                jr z,fp_1
                ld bc,GA+4
                call fp_cs
                push af
                ld bc,GB+4
                call fp_cs
                pop bc
                cp b
                ret nz
fp_1:           ld hl,GA+4              ; p3 = closestPtOnLine(gateA[1], gateB[1], pos)
                ld de,LNS
                ld bc,4
                ldir
                ld hl,GB+4
                ld bc,4
                ldir
                ld hl,FPOS
                ld bc,4
                ldir
                call cplin
                ld hl,LNR
                ld de,P3
                ld bc,4
                ldir
                ld bc,GA
                call fp_cs3
                push af
                ld bc,GB
                call fp_cs3
                pop bc
                cp b
                ret nz
                ld hl,GA                ; p2 = closestPtOnLine(gateA[0], gateB[0], pos)
                ld de,LNS
                ld bc,4
                ldir
                ld hl,GB
                ld bc,4
                ldir
                ld hl,FPOS
                ld bc,4
                ldir
                call cplin
                ld hl,LNR
                ld de,P2
                ld bc,4
                ldir
                ret
fp_cs:          ld hl,FPOS
                ld de,FDST
                jp cslope
fp_cs3:         ld hl,FPOS
                ld de,P3
                jp cslope

; ---------------------------------------------------------------- getNextBox (v3)
; gnb: B = desde, C = hasta (desde != hasta, desde != $FF) -> A = la caja siguiente; carry si no hay camino (-1 o un valor negativo de la
; matriz). La matriz (MATP: tamano u16 y los bytes) lleva por cada caja ternas (primera, ultima, siguiente) acabadas en $FF, con un $FF
; inicial opcional; no se lee mas alla de su final (la de la sala 46 esta truncada). WORKAROUND de ScummVM: sala 46, de la 1 a la 0 -> 0
gnb:            ld a,c
                cp $FF
                jr z,gnb_none
                ld a,(NBOXES)
                ld e,a
                ld a,b
                cp e
                jp nc,err_range
                ld a,c
                cp e
                jp nc,err_range
                ld a,(ROOMRES)
                cp 46
                jr nz,gnb_1
                ld a,b
                dec a
                jr nz,gnb_1
                ld a,c
                or a
                jr nz,gnb_1
                xor a
                ret
gnb_1:          ld hl,(MATP)
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ex de,hl
                add hl,de
                ex de,hl                ; HL = matriz, DE = su final
                call gnb_lt
                jr nc,gnb_sk
                ld a,(hl)
                inc a
                jr nz,gnb_sk
                inc hl
gnb_sk:         ld a,b                  ; salta las filas de las cajas anteriores
                or a
                jr z,gnb_f
                call gnb_lt
                jr nc,gnb_f
gnb_r:          call gnb_lt
                jr nc,gnb_re
                ld a,(hl)
                inc a
                jr z,gnb_re
                inc hl
                inc hl
                inc hl
                jr gnb_r
gnb_re:         inc hl
                dec b
                jr gnb_sk
gnb_f:          ld b,$FF                ; -1
gnb_s:          call gnb_lt
                jr nc,gnb_x
                ld a,(hl)
                inc a
                jr z,gnb_x
                inc hl
                inc hl
                call gnb_lt             ; la terna entera esta dentro?
                dec hl
                dec hl
                jr nc,gnb_n
                ld a,c
                cp (hl)
                jr c,gnb_n              ; hasta < primera
                inc hl
                ld a,(hl)
                dec hl
                cp c
                jr c,gnb_n              ; ultima < hasta
                inc hl
                inc hl
                ld b,(hl)
                dec hl
                dec hl
gnb_n:          inc hl
                inc hl
                inc hl
                jr gnb_s
gnb_x:          ld a,b
                cp $80
                ccf
                ret
gnb_none:       scf
                ret
gnb_lt:         push hl                 ; carry si HL < DE
                or a
                sbc hl,de
                pop hl
                ret

; ---------------------------------------------------------------- adjustXYToBeInBox
; actor_cls: -> A = tercer byte de las clases del actor IX (bit 6 jugador, bit 2 volteo en x, bit 1 volteo en y: las clases 31, 30 y 29
; de ScummVM, que con GF_SMALL_HEADER son la 23, la 19 y la 18)
actor_cls:      call actor_num
                ld l,a
                ld h,0
                call cls_open
                call cls_ptr
                inc hl
                inc hl
                ld a,(hl)
                push af
                call cls_close
                pop af
                ret

; edge_lb (fase 10d): arista LNS -> LNE, punto BP -> HL = cota inferior de sqrDist(punto, closestPtOnLine) ($FFFF: 65.535 o mas). Exacta:
; closestPtOnLine siempre deja la coordenada del eje mayor de la arista (x si |ly| < |lx|; si no, y) dentro del segmento (recorta, o es la
; del punto en las aristas verticales y horizontales), asi que sqrDist >= d * d, con d la distancia del punto a ese intervalo en ese eje.
; Usa AXT y QAX (libres dentro de cpb)
edge_lb:        ld hl,(LNE)
                ld de,(LNS)
                call sdiff
                push hl                 ; |lx|
                ld hl,(LNE+2)
                ld de,(LNS+2)
                call sdiff
                pop de
                or a
                sbc hl,de               ; carry: |ly| < |lx|, eje x
                ld de,0
                jr c,el_ax
                ld e,2
el_ax:          ld hl,LNE
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                push hl                 ; el final de la arista en el eje
                ld hl,LNS
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)               ; el principio
                ld hl,BP
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a                  ; el punto
                push hl
                ld d,b
                ld e,c
                call sdiff              ; |p - s| y su signo
                ld (AXT),hl
                ld (QAX),a
                pop hl
                pop de
                call sdiff              ; |p - e|
                ld b,a
                ld a,(QAX)
                cp b
                jr nz,el_0              ; el punto esta entre los dos: cota 0
                ld de,(AXT)
                push hl
                or a
                sbc hl,de
                pop hl
                jr c,el_m
                ex de,hl                ; d = la menor de las dos
el_m:           ld a,h
                or a
                jr nz,el_far            ; d >= 256
                ld b,a
                ld c,l
                ld d,a
                ld e,l
                jp mul16u               ; HL = d * d
el_far:         ld hl,$FFFF
                ret
el_0:           ld hl,0
                ret

; adjust_xy: Actor::adjustXYToBeInBox(IX = actor, WKX, WKY) -> WKX, WKY y WKBOX. Con ignoreBoxes, el punto tal cual y caja invalida; sin
; cajas, las ultimas coordenadas validas. Tres pasadas (umbral 30, 80 y sin umbral) sobre las cajas de la ultima a la primera.
; Fase 10d (mismo resultado, menos calculo): (1) checkXYInBoxBounds solo en la primera pasada: si llega a la segunda, el punto no esta en
; ninguna de las cajas que se miran (las que la primera no miro tienen el punto a mas de 30 pixeles de sus 4 esquinas en x o en y, y
; checkXYInBoxBounds las descarta por lo mismo); (2) getClosestPtOnBox con poda por arista (cpb_t, umbral AXBEST): una caja solo
; cuenta si da menos que AXBEST; (3) inBoxQuickReject(umbral) es "ax_bd > umbral", y ax_bd se calcula una vez por caja (ax_getd)
ADB             equ GCOR                ; ax_bd de cada caja (la primera pasada lo guarda y la segunda lo lee), si hay ADB_N cajas o menos
ADB_N           equ 125                 ; (GCOR..FDST: getGates y findPathTowardsOld no corren durante adjust_xy)

; ax_bd: IY = caja, BP = punto -> A = la mayor de las distancias del punto al rectangulo envolvente de la caja en x y en y (0 si esta
; dentro en ese eje), saturada a 255. inBoxQuickReject(umbral) (qrej) descarta la caja si x - umbral pasa de las 4 esquinas, o x + umbral
; no llega a ninguna, o lo mismo en y (con la saturacion de 16 bits sale lo mismo que con enteros): justo cuando esta distancia > umbral
ax_bd:          ld hl,(BP)
                call bd_ax
                ld (AXT),a
                inc iy
                inc iy
                ld hl,(BP+2)
                call bd_ax
                dec iy
                dec iy
                ld b,a
                ld a,(AXT)
                cp b
                ret nc
                ld a,b
                ret
; bd_ax: HL = coordenada del punto, IY = la de la esquina 0 en ese eje (las otras a +4, +8 y +12) -> A = distancia del punto al intervalo
; [menor, mayor] de las 4 esquinas (0 si esta dentro), saturada a 255. Se compara sin signo con el bit de signo invertido
bd_ax:          ld a,h
                xor $80
                ld h,a
                push hl                 ; el punto
                ld e,(iy+0)
                ld a,(iy+1)
                xor $80
                ld d,a                  ; DE = la menor
                ld b,d
                ld c,e                  ; BC = la mayor
                ld l,(iy+4)
                ld a,(iy+5)
                xor $80
                ld h,a
                call bd_mm
                ld l,(iy+8)
                ld a,(iy+9)
                xor $80
                ld h,a
                call bd_mm
                ld l,(iy+12)
                ld a,(iy+13)
                xor $80
                ld h,a
                call bd_mm
                pop hl
                ld a,c
                sub l
                ld a,b
                sbc a,h
                jr c,bd_hi              ; el punto pasa de la mayor
                ld a,l
                sub e
                ld a,h
                sbc a,d
                jr c,bd_lo              ; no llega a la menor
                xor a
                ret
bd_hi:          or a
                sbc hl,bc
                jr bd_s
bd_lo:          ex de,hl
                or a
                sbc hl,de
bd_s:           ld a,h
                or a
                ld a,255
                ret nz
                ld a,l
                ret
bd_mm:          ld a,l                  ; HL = una esquina: DE = min(DE, HL), BC = max(BC, HL)
                sub e
                ld a,h
                sbc a,d
                jr nc,mm_1
                ld d,h
                ld e,l
                ret
mm_1:           ld a,c
                sub l
                ld a,b
                sbc a,h
                ret nc
                ld b,h
                ld c,l
                ret

; ax_getd: IY = caja AXBOX -> A = ax_bd: la primera pasada lo calcula y lo guarda en ADB, la segunda lo lee (con mas de ADB_N cajas, se calcula)
ax_getd:        ld a,(NBOXES)
                cp ADB_N+1
                jp nc,ax_bd
                ld a,(AXBOX)
                ld e,a
                ld d,0
                ld hl,ADB
                add hl,de
                ld a,(AXTI)
                or a
                ld a,(hl)
                ret nz
                push hl
                call ax_bd
                pop hl
                ld (hl),a
                ret

adjust_xy:      ld a,$FF
                ld (WKBOX),a
                ld a,(ix+A_IGNB)
                or a
                ret nz
                ld a,(NBOXES)
                or a
                jp z,ax_lv
                ld hl,(WKX)
                ld (BP),hl
                ld hl,(WKY)
                ld (BP+2),hl
                call actor_cls
                and $40
                ld (AXPL),a
                xor a
ax_t:           ld (AXTI),a
                ld hl,$FFFF
                ld (AXBEST),hl
                ld a,$FF
                ld (AXBB),a
                ld a,(NBOXES)
ax_l:           dec a
                ld (AXBOX),a
                ld c,a
                ld b,0
                call box_addr
                push hl
                pop iy
                ld a,(iy+17)
                bit 7,a
                jr z,ax_vis
                bit 5,a
                jp z,ax_next            ; invisible
                ld a,(AXPL)
                or a
                jp nz,ax_next           ; invisible y solo para jugadores, y lo es
ax_vis:         ld a,(AXTI)
                cp 2
                jr z,ax_cl
                call ax_getd            ; (3)
                ld c,a
                ld a,(AXTI)
                or a
                ld a,30
                jr z,ax_q
                ld a,80
ax_q:           cp c
                jp c,ax_next            ; inBoxQuickReject
                ld a,(AXTI)
                or a
                jr nz,ax_cl             ; (1)
                call cxb
                or a
                jr z,ax_cl
                ld hl,(BP)              ; dentro de la caja
                ld (ix+A_LVX),l
                ld (ix+A_LVX+1),h
                ld hl,(BP+2)
                ld (ix+A_LVY),l
                ld (ix+A_LVY+1),h
                ld a,(AXBOX)
                ld (WKBOX),a
                jr ax_lv
ax_cl:          ld hl,(AXBEST)          ; (2)
                ld (CBT),hl
                call cpb_t
                ld de,(AXBEST)
                push hl
                or a
                sbc hl,de
                pop hl
                jp nc,ax_next
                ld de,(CBOUT)
                ld (ix+A_LVX),e
                ld (ix+A_LVX+1),d
                ld de,(CBOUT+2)
                ld (ix+A_LVY),e
                ld (ix+A_LVY+1),d
                ld a,h
                or l
                jr nz,ax_s
                ld a,(AXBOX)
                ld (WKBOX),a
                jr ax_lv
ax_s:           ld (AXBEST),hl
                ld a,(AXBOX)
                ld (AXBB),a
ax_next:        ld a,(AXBOX)
                or a
                jp nz,ax_l
                ld a,(AXTI)
                cp 2
                jr z,ax_ret
                or a
                ld hl,900               ; umbral al cuadrado
                jr z,ax_c
                ld hl,6400
ax_c:           ld de,(AXBEST)
                or a
                sbc hl,de
                jr nc,ax_ret
                ld a,(AXTI)
                inc a
                jp ax_t
ax_ret:         ld a,(AXBB)
                ld (WKBOX),a
ax_lv:          ld l,(ix+A_LVX)
                ld h,(ix+A_LVX+1)
                ld (WKX),hl
                ld l,(ix+A_LVY)
                ld h,(ix+A_LVY+1)
                ld (WKY),hl
                ret
