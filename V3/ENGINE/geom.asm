; =====================================================================
;  geom.asm - geometria de las cajas de v3 (fase 6), en el overlay D (se incluye desde ovld.asm).
;  Es boxes.cpp de ScummVM (version 3) tal como lo transcribe V3/TOOLS/vmgame3.py: closestPtOnLine, getClosestPtOnBox, checkXYInBoxBounds,
;  inBoxQuickReject, getGates, findPathTowardsOld, getNextBox y adjustXYToBeInBox.
;  Toda la aritmetica de closestPtOnLine y de compareSlope es la de un int de C: 32 bits con signo que desbordan (wrap32 del modelo);
;  los puntos son Common::Point (int16). Una division por cero (ScummVM se cuelga) es E_RANGE.
;  IX = actor en todo el overlay (no se toca); IY = caja (su registro de RBLOB: 4 esquinas de 4 bytes ul, ur, lr, ll; +17 banderas).
;  Variables: GW (bloque 7, vm_core.asm). Nada de esto sobrevive a otra llamada del overlay.
; =====================================================================
GSP             equ GW+0                ; palabra: cima de la pila de 32 bits
GSTK            equ GW+2                ; 6 x 4
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
MSGN            equ GW+63               ; signo de smul
BP              equ GW+64               ; 4: el punto de cpb, cxb y qrej
CBBEST          equ GW+68               ; 4: getClosestPtOnBox: mejor distancia (32 bits) y su punto
CBOUT           equ GW+72
CBK             equ GW+76               ; arista / esquina en curso
AXT             equ GW+77               ; palabra: axis_cnt
QTHR            equ GW+79
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
AXD             equ GW+229              ; adjustXYToBeInBox: el punto pedido (4)
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

; smul: NR = N1 * N2 (int de C: 32 bits bajos). Con los dos en 16 bits sin signo tras quitar el signo, mul16u; si no, mul32 del residente
smul:           xor a
                ld (MSGN),a
                ld a,(N2+3)
                rla
                jr nc,sm_1
                ld hl,N2
                call neg32
                ld a,1
                ld (MSGN),a
sm_1:           ld a,(N1+3)
                rla
                jr nc,sm_2
                ld hl,N1
                call neg32
                ld a,(MSGN)
                xor 1
                ld (MSGN),a
sm_2:           ld hl,(N1+2)
                ld a,h
                or l
                ld hl,(N2+2)
                or h
                or l
                jr nz,sm_big
                ld bc,(N1)
                ld de,(N2)
                call mul16u
                ld (NR),hl
                ld (NR+2),de
                jr sm_sg
sm_big:         call mul32
sm_sg:          ld a,(MSGN)
                or a
                ret z
                ld hl,NR
                jp neg32

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

; ---------------------------------------------------------------- pila de 32 bits (los calculos de closestPtOnLine)
gpush16:        ld e,(hl)               ; apila el s16 de (HL) con su signo
                inc hl
                ld d,(hl)
                ex de,hl
                ld a,h
                rla
                sbc a,a
                ld e,a
                ld d,a
                jr gpush_dehl
gpush32:        ld e,(hl)               ; apila los 32 bits de (HL)
                inc hl
                ld d,(hl)
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ex de,hl
gpush_dehl:     push de                 ; apila DE:HL
                ex de,hl
                ld hl,(GSP)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                pop de
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld (GSP),hl
                ret
gpop_dehl:      ld hl,(GSP)             ; desapila -> DE:HL
                dec hl
                ld d,(hl)
                dec hl
                ld e,(hl)
                dec hl
                ld b,(hl)
                dec hl
                ld c,(hl)
                ld (GSP),hl
                ld h,b
                ld l,c
                ret
gpop32:         push hl                 ; desapila en los 32 bits de (HL)
                call gpop_dehl
                ex de,hl
                ex (sp),hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                pop de
                ld (hl),e
                inc hl
                ld (hl),d
                ret
gadd:           call gpop_dehl
                push de
                push hl
                call gpop_dehl
                pop bc
                add hl,bc
                ex de,hl
                pop bc
                adc hl,bc
                ex de,hl
                jr gpush_dehl
gsub:           call gpop_dehl
                push de
                push hl
                call gpop_dehl
                pop bc
                or a
                sbc hl,bc
                ex de,hl
                pop bc
                sbc hl,bc
                ex de,hl
                jr gpush_dehl
gmul:           ld hl,N2
                call gpop32
                ld hl,N1
                call gpop32
                call smul
                ld hl,NR
                jr gpush32
gdiv:           ld hl,N2
                call gpop32
                ld hl,N1
                call gpop32
                ld hl,(N2)
                ld a,h
                or l
                ld hl,(N2+2)
                or h
                or l
                jp z,err_range          ; ScummVM dividiria por cero
                call sdiv
                ld hl,NR
                jp gpush32

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
cpl_gen:        ld hl,GSTK
                ld (GSP),hl
                ld hl,LU                ; dist = lu*lu + lv*lv
                call gpush32
                ld hl,LU
                call gpush32
                call gmul
                ld hl,LV
                call gpush32
                ld hl,LV
                call gpush32
                call gmul
                call gadd
                ld hl,LDIST
                call gpop32
                ld hl,LNS                ; a = su*lv/lu
                call gpush16
                ld hl,LV
                call gpush32
                call gmul
                ld hl,LU
                call gpush32
                call gdiv
                ld hl,LA
                call gpop32
                ld hl,LNP                ; b = pu*lu/lv
                call gpush16
                ld hl,LU
                call gpush32
                call gmul
                ld hl,LV
                call gpush32
                call gdiv
                ld hl,LA                ; c = (a + b - sv + pv)*lv*lu/dist
                call gpush32
                call gadd
                ld hl,LNS+2
                call gpush16
                call gsub
                ld hl,LNP+2
                call gpush16
                call gadd
                ld hl,LV
                call gpush32
                call gmul
                ld hl,LU
                call gpush32
                call gmul
                ld hl,LDIST
                call gpush32
                call gdiv
                ld hl,LC
                call gpop32
                ld hl,(LC)              ; ru = c (un Common::Point: los 16 bits bajos)
                ld (LNR),hl
                ld hl,LC                ; rv = c*lv/lu - a + sv
                call gpush32
                ld hl,LV
                call gpush32
                call gmul
                ld hl,LU
                call gpush32
                call gdiv
                ld hl,LA
                call gpush32
                call gsub
                ld hl,LNS+2
                call gpush16
                call gadd
                call gpop_dehl
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
; (0, 0 si ninguna arista da menos de 0xFFFFFF) y CBBEST = la distancia entera
cpb:            ld hl,$FFFF
                ld (CBBEST),hl
                ld hl,$00FF
                ld (CBBEST+2),hl
                ld hl,0
                ld (CBOUT),hl
                ld (CBOUT+2),hl
                xor a
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
                call cplin
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
                ld hl,(LNR)
                ld (CBOUT),hl
                ld hl,(LNR+2)
                ld (CBOUT+2),hl
cpb_n:          ld a,(CBK)
                inc a
                cp 4
                jr c,cpb_l
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

; qrej: inBoxQuickReject(IY = caja, BP = punto, A = umbral) -> NZ si el punto esta a mas de `umbral` de la caja en x o en y
qrej:           ld (QTHR),a
                xor a
                call qr_axis
                ret nz
                ld a,2
qr_axis:        ld (QAX),a
                ld e,a
                ld d,0
                ld hl,BP
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                push hl
                ld a,(QTHR)
                ld e,a
                ld d,0
                or a
                sbc hl,de               ; t = v - umbral (saturado: mas alla de -32768 no cambia el resultado)
                jp po,qa_1
                ld hl,$8000
qa_1:           ld a,(QAX)
                call axis_cnt
                pop hl
                ld a,c
                cp 4
                jr z,qa_y               ; t es mayor que las 4 esquinas
                ld a,(QTHR)
                ld e,a
                ld d,0
                or a
                adc hl,de               ; t = v + umbral
                jp po,qa_2
                ld hl,$7FFF
qa_2:           ld a,(QAX)
                call axis_cnt
                ld a,b
                cp 4
                jr z,qa_y               ; t es menor que las 4
                xor a
                ret
qa_y:           ld a,1
                or a
                ret

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

; gates: getGates(caja 1 = (GB1P), caja 2 = (GB2P)) -> GA (gateA[0], gateA[1]) y GB
gates:          ld hl,(GB1P)
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

; adjust_xy: Actor::adjustXYToBeInBox(IX = actor, WKX, WKY) -> WKX, WKY y WKBOX. Con ignoreBoxes, el punto tal cual y caja invalida; sin
; cajas, las ultimas coordenadas validas. Tres pasadas (umbral 30, 80 y sin umbral) sobre las cajas de la ultima a la primera
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
                jr z,ax_next            ; invisible
                ld a,(AXPL)
                or a
                jr nz,ax_next           ; invisible y solo para jugadores, y lo es
ax_vis:         ld a,(AXTI)
                cp 2
                jr z,ax_noq
                or a
                ld a,30
                jr z,ax_q
                ld a,80
ax_q:           call qrej
                jr nz,ax_next
ax_noq:         call cxb
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
ax_cl:          call cpb
                ld de,(AXBEST)
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,ax_next
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
