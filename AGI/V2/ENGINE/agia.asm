; =====================================================================
;  agia.asm - overlay A: teclado, sprites por hardware (agihws.asm). Pagina PG_OVL, mapeada siempre en el bloque 1 ($2000).
;  El texto esta en el overlay B (agib.asm); plot, map7 y las variables compartidas, en el nucleo (agispr.asm).
; =====================================================================

                org $2000
                include "agires.inc"
HQ_FIX          equ $2040

                jp t_kpoll              ; OVL_KPOLL
                jp t_kdeliv             ; OVL_KDELIV
                jp t_accept             ; OVL_ACCEPT
                jp t_prevent            ; OVL_PREVENT
                jp t_draw               ; OVL_DRAW
                jp t_sinit              ; OVL_SPRINIT
                jp t_sort               ; OVL_SORT
                jp t_force              ; OVL_FORCE
                jp t_addpic             ; OVL_ADDPIC
                jp t_spclr              ; OVL_SPCLR

; El orden de los objetos que deja t_sort: el overlay A2 (que se mapea en lugar de este) lo lee de aqui, por el bloque 7, asi que va en una direccion fija
                defs HQ_FIX-$
hq_cnt:         defb 0
ORD:            defs NOBJ
VPG:            defs NOBJ
sp_n:           defb 0                  ; objetos fijos (add.to.pic): cuantos y sus cabeceras (agihws.asm)
SPH:            defs 64                 ; 8 * SP_MAX

; ---------------------------------------------------------------------
;  Teclado del ZX81
;
;  t_kpoll se llama muchas veces (en los bucles largos del dibujo y al principio de cada ciclo): lee la matriz, detecta las teclas recien
;  pulsadas y deja eventos en una cola (PQ). No dibuja ni toca el estado del interprete. t_kdeliv, al principio del ciclo, hace un poll,
;  entrega la cola (teclas -> key_push, direccion -> dirhold, linea -> ev_text) y, en modo real, redibuja la linea de entrada si cambio.
;  Capas: base = minusculas y las cifras como funciones (9 = ESC, 0 = borrar, 5/6/7/8 = izquierda / abajo / arriba / derecha del ego,
;  con diagonales), SHIFT = mayusculas y cifras, ENTER+tecla = simbolos; ENTER solo = CR al soltarlo.
;  Cada caracter es un evento de tecla (v19, set.key); con accept.input tambien va a la linea de entrada, que ENTER entrega como texto.
; ---------------------------------------------------------------------
PQ_MAX          equ 16
IL_MAX          equ 39

t_kpoll:        push af
                push bc
                push de
                push hl
                call kb_scan
                call kb_edges
                call kb_dir
                pop hl
                pop de
                pop bc
                pop af
                ret

kb_scan:        ld hl,kb_cur
                ld bc,$FEFE
                ld d,8
ks_l:           in a,(c)
                cpl
                and $1F
                ld (hl),a
                inc hl
                rlc b
                dec d
                jr nz,ks_l
                ret

kb_edges:       ld a,(kb_cur)
                and 1
                ld (kb_shift),a
                ld a,(kb_cur+6)
                and 1
                ld (kb_enter),a
                ld b,a
                ld a,(kb_prev+6)
                and 1
                ld c,a
                ld a,b
                cp c
                jr z,ke_rows            ; ENTER no cambia
                or a
                jr z,ke_rel
                xor a                   ; recien pulsado: aun no ha servido de modificador
                ld (kb_eused),a
                jr ke_rows
ke_rel:         ld a,(kb_eused)         ; soltado: si no fue modificador, es un CR
                or a
                jr nz,ke_rows
                ld a,13
                call kb_emit
ke_rows:        xor a
                ld (ke_r),a
ke_row:         ld a,(ke_r)
                ld e,a
                ld d,0
                ld hl,kb_cur
                add hl,de
                ld b,(hl)
                ld hl,kb_prev
                add hl,de
                ld a,(hl)
                cpl
                and b
                ld c,a                  ; bits recien pulsados
                ld a,e
                or a
                jr nz,ke_n0
                res 0,c                 ; SHIFT y ENTER no son teclas de caracter
ke_n0:          ld a,e
                cp 6
                jr nz,ke_n1
                res 0,c
ke_n1:          ld a,c
                ld (ke_m),a
                or a
                jr z,ke_nr              ; sin teclas nuevas en la fila
                xor a
                ld (ke_b),a
ke_bit:         ld a,(ke_b)
                inc a
                ld b,a
                ld a,(ke_m)
ke_sh:          rrca
                djnz ke_sh
                jr nc,ke_nb
                ld a,(ke_r)
                ld c,a
                add a,a
                add a,a
                add a,c
                ld c,a
                ld a,(ke_b)
                add a,c                 ; indice de la tecla = fila * 5 + bit
                call kb_key
ke_nb:          ld hl,ke_b
                inc (hl)
                ld a,(hl)
                cp 5
                jr c,ke_bit
ke_nr:          ld hl,ke_r
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,ke_row
                ld hl,kb_cur
                ld de,kb_prev
                ld bc,8
                ldir
                ret

; A = indice de la tecla recien pulsada -> su caracter segun la capa
kb_key:         ld e,a
                ld d,0
                ld a,(kb_enter)
                or a
                jr z,kk_ns
                ld a,1
                ld (kb_eused),a
                ld hl,km_sym
                jr kk_t
kk_ns:          ld a,(kb_shift)
                or a
                ld hl,km_base
                jr z,kk_t
                ld hl,km_shift
kk_t:           add hl,de
                ld a,(hl)
                or a
                ret z

; A = caracter -> evento de tecla y, si se acepta entrada, edicion de la linea
kb_emit:        ld c,a
                cp 2
                jr z,ke_zero            ; ENTER + 0: el digito 0 solo como texto, sin el evento de tecla (KQ1 lo tiene ligado al salto)
                bit 7,c
                jr z,ke_txt
                res 7,c                 ; tecla de funcion: solo el evento, sin editar la linea
                ld a,1
                jp kq_put
ke_zero:        ld c,'0'
                jr ke_ed
ke_txt:         ld a,1
                push bc
                call kq_put
                pop bc
ke_ed:          ld a,(accin)
                or a
                ret z
                ld a,c
                cp 13
                jr z,ed_cr
                cp 8
                jr z,ed_bs
                cp 127
                jr z,ed_bs
                cp 32
                ret c
                cp 127
                ret nc
                ld a,(il_n)
                cp IL_MAX
                ret nc
                ld e,a
                ld d,0
                ld hl,INBUF
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),0
                inc a
                ld (il_n),a
                jr ed_dirty
ed_bs:          ld a,(il_n)
                or a
                ret z
                dec a
                ld (il_n),a
                ld e,a
                ld d,0
                ld hl,INBUF
                add hl,de
                ld (hl),0
                jr ed_dirty
ed_cr:          ld a,(il_n)
                or a
                jr nz,ed_go
                ld a,(gs_on)            ; get.string: ENTER con la linea vacia tambien la entrega (asi se sale del archivo de KQ/SQ)
                or a
                ret z
ed_go:
                ld hl,INBUF
                ld de,PTEXT
                ld bc,41
                ldir
                ld a,3
                ld c,0
                call kq_put
                xor a
                ld (il_n),a
                ld (INBUF),a
ed_dirty:       ld a,1
                ld (kb_dirty),a
                ret

; A = tipo (1 tecla, 2 direccion, 3 linea), C = valor
kq_put:         ld b,a
                ld a,(kq_n)
                cp PQ_MAX
                ret nc
                add a,a
                ld e,a
                ld d,0
                ld hl,PQ
                add hl,de
                ld (hl),b
                inc hl
                ld (hl),c
                ld hl,kq_n
                inc (hl)
                ret

; Direccion del ego con SHIFT + 5/6/7/8: bits arriba 1, derecha 2, abajo 4, izquierda 8 -> direccion de AGI
kb_dir:         ld a,(kb_shift)
                or a
                ld b,0
                jr nz,kd_set            ; con SHIFT las cifras son cifras
                ld a,(kb_cur+4)
                ld c,a
                bit 3,c
                jr z,kd1
                set 0,b
kd1:            bit 2,c
                jr z,kd2
                set 1,b
kd2:            bit 4,c
                jr z,kd3
                set 2,b
kd3:            ld a,(kb_cur+3)
                bit 4,a
                jr z,kd4
                set 3,b
kd4:            ld c,b
                ld b,0
                ld hl,dirt
                add hl,bc
                ld b,(hl)
kd_set:         ld a,(kb_dprev)
                cp b
                ret z
                ld a,b
                ld (kb_dprev),a
                ld c,b
                ld a,2
                jp kq_put
dirt:           defb 0,1,3,2,5,0,4,0,7,8,0,0,6,0,0,0

t_accept:       ld a,1
                ld (accin),a
                ret
t_prevent:      xor a
                ld (accin),a
                ret

t_kdeliv:       call t_kpoll
                ld a,(kq_n)
                or a
                jr z,kdl_p
                ld b,a
                ld hl,PQ
kdl:            push bc
                push hl
                ld a,(hl)
                inc hl
                ld c,(hl)
                cp 1
                jr z,kdl_k
                cp 2
                jr z,kdl_d
                ld hl,PTEXT
                ld de,EVBUF
                ld bc,41
                ldir
                call ev_text
                jr kdl_n
kdl_k:          ld a,c
                call key_push
                jr kdl_n
kdl_d:          ld a,c
                ld (dirhold),a
kdl_n:          pop hl
                inc hl
                inc hl
                pop bc
                djnz kdl
                xor a
                ld (kq_n),a
kdl_p:          ret


; indice = fila * 5 + bit; fila 0 = A8 (SHIFT Z X C V), 1 = A9 (A S D F G), 2 = A10 (Q W E R T), 3 = A11 (1-5), 4 = A12 (0 9 8 7 6), 5 = A13 (P O I U Y), 6 = A14 (ENTER L K J H), 7 = A15 (SPACE . M N B)
km_base:        defb 0,'z','x','c','v'
                defb 'a','s','d','f','g'
                defb 'q','w','e','r','t'
                defb 3,28,30,5,0                ; 1 = borrar linea (Ctrl-C), 2 = guardar (F5 = codigo 28), 3 = cargar (F7 = codigo 30), 4 = repetir orden (Ctrl-E); 5/6/7/8 = direcciones
                defb 8,27,0,0,0                 ; 0 = borrar, 9 = ESC (la unica)
                defb 'p','o','i','u','y'
                defb 0,'l','k','j','h'
                defb ' ','.','m','n','b'
km_shift:       defb 0,'Z','X','C','V'
                defb 'A','S','D','F','G'
                defb 'Q','W','E','R','T'
                defb '1','2','3','4','5'        ; SHIFT + cifra = la cifra
                defb '0','9','8','7','6'
                defb 'P','O','I','U','Y'
                defb 0,'L','K','J','H'
                defb ' ',9,'M','N','B'
km_sym:         defb 0,':',';','?','/'
                defb 0,92,0,126,96              ; S = \  F = ~  G = `
                defb 39,123,125,91,95           ; Q = '  W = {  E = }  R = [  T = _
                defb '!',64,'#',124,'%'         ; 1 = !  2 = @  3 = #  4 = |  5 = %
                defb 2,0,0,0,'&'                ; 0 = (el digito 0 solo como texto)  6 = &
                defb 34,')','(','$',93          ; P = "  O = )  I = (  U = $  Y = ]
                defb 0,'=','+','-',94           ; L = =  K = +  J = -  H = ^
                defb ' ',',','>','<','*'        ; . = ,  M = >  N = <  B = *

kb_cur:         defs 8
kb_prev:        defs 8
kb_shift:       defb 0
kb_enter:       defb 0
kb_eused:       defb 0
kb_dprev:       defb 0
kq_n:           defb 0
ke_r:           defb 0
ke_m:           defb 0
ke_b:           defb 0
PTEXT:          defs 42
PQ:             defs 2*PQ_MAX


                include "agicel.asm"
                include "agihws.asm"

; Tras una ventana de mensaje: todos los objetos se vuelven a armar (sprites) y los rotulos se recomponen
t_force:        ld ix,OBJ
                ld de,32
                ld b,NOBJ
tfo_l:          res 1,(ix+O_SDR)
                add ix,de
                djnz tfo_l
                ld a,1
                ld (sw_force),a
                ret

