; =====================================================================
;  agitxt.asm - texto del interprete AGI. Es un OVERLAY: se ensambla aparte en $2000 (compila: pasmo agitxt.asm agitxt.bin tras agivm.asm,
;  que le da sus simbolos por agires.inc), se guarda como TEXT.OVL (u16 tamano + codigo, TOOLS/mkovl.py) y agivm.asm lo carga en la pagina PG_OVL
;  y lo deja mapeado en el bloque 1 ($2000-$3FFF). El nucleo lo llama por la tabla de saltos del principio (OVL_* en agivm.asm).
;
;  Mismo comportamiento que TOOLS/agi_text.py y las ordenes de texto de TOOLS/agi_vm.py: fuente de 6x8 (font6.bin), 42 columnas por 24 filas, fila 0 =
;  barra de estado, 1-21 = imagen, 22-23 = pie. Una linea de texto se compone por celdas HiRes de 8 pixeles: la cubierta entera pasa a papel = fondo,
;  tinta = color del texto con el bitmap de los glifos; la cubierta a medias recibe solo sus pixeles, uno a uno, con `plot` (agispr.asm).
;  El texto sobre la imagen se escribe tambien en la copia de fondo (PG_BGB/PG_BGA) y manda redibujar los sprites que toca.
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_display            ; OVL_DISPLAY
                jp t_display_v          ; OVL_DISPLAY_V
                jp t_clear_lines        ; OVL_CLEAR
                jp t_status             ; OVL_STATUS (una vez por ciclo)
                jp t_status_on          ; OVL_SON
                jp t_status_off         ; OVL_SOFF
                jp t_set_attr           ; OVL_ATTR
                jp t_kpoll              ; OVL_KPOLL
                jp t_kdeliv             ; OVL_KDELIV
                jp t_accept             ; OVL_ACCEPT
                jp t_prevent            ; OVL_PREVENT
                jp t_render             ; OVL_RENDER
                jp t_sinit              ; OVL_SPRINIT
                jp t_bgsave             ; OVL_BGSAVE

TXT             equ TMPM

t_set_attr:     ld a,(ARGS)
                and 15
                ld (tfg),a
                ld a,(ARGS+1)
                and 15
                ld (tbg),a
                ret

t_display:      ld a,(ARGS)
                ld (dl_row0),a
                ld a,(ARGS+1)
                ld (tcol0),a
                ld a,(ARGS+2)
                jr td_go
t_display_v:    ld a,(ARGS)
                call getv
                ld (dl_row0),a
                ld a,(ARGS+1)
                call getv
                ld (tcol0),a
                ld a,(ARGS+2)
                call getv
td_go:          ld b,a
                ld a,(curlg)
                ld (bs_lg),a
                ld de,TXT
                ld c,250
                call build_str
                ld a,(tfg)
                call t_chroma
                ld (dl_fg),a
                ld a,(tbg)
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
td_line:        ld a,(dl_row0)
                cp 24
                ret nc
                ld (dl_ptr),hl
                ld b,0
tl_c:           ld a,(hl)
                or a
                jr z,tl_e
                cp 10
                jr z,tl_e
                inc hl
                inc b
                jr tl_c
tl_e:           ld (tterm),a
                ld a,(tcol0)
                ld c,a
                ld a,42
                sub c
                jr nc,tl_m
                xor a
tl_m:           cp b
                jr c,tl_n
                ld a,b
tl_n:           or a
                jr z,tl_next
                ld (dl_n),a
                ld a,(dl_row0)
                ld (dl_row),a
                ld a,c
                ld (dl_col),a
                push hl
                call draw_line
                pop hl
tl_next:        ld a,(tterm)
                or a
                ret z
                inc hl
                ld a,(dl_row0)
                inc a
                ld (dl_row0),a
                jp td_line

; A = color EGA -> codigo de Chroma
t_chroma:       and 15
                ld e,a
                ld d,0
                ld hl,ega2ch
                add hl,de
                ld a,(hl)
                ret

; ---------------------------------------------------------------------
;  Una linea de texto: dl_ptr, dl_n (1-42), dl_row, dl_col, dl_fg, dl_bg (codigos de Chroma)
; ---------------------------------------------------------------------
draw_line:      ld a,(dl_col)
                ld b,a
                add a,a
                add a,b
                add a,a
                ld (dl_x0),a            ; x0 = col * 6
                rrca
                rrca
                rrca
                and 31
                ld (dl_ca),a
                ld a,(dl_n)
                ld b,a
                add a,a
                add a,b
                add a,a                 ; 6 * n
                ld b,a
                ld a,(dl_x0)
                add a,b
                dec a
                rrca
                rrca
                rrca
                and 31                  ; celda del ultimo pixel
                ld hl,dl_ca
                sub (hl)
                inc a
                ld (dl_nb),a
                xor a
                ld (dl_k),a
dl_kl:          call t_kpoll
                ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(dl_k)
                add a,b
                call t_srow
                ld hl,LB
                ld de,LB+1
                ld bc,67
                ld (hl),0
                ldir
                ld hl,(dl_ptr)
                ld a,(dl_n)
                ld b,a
                ld a,(dl_x0)
                and 7
                ld (dl_s),a
dl_ch:          push bc
                push hl
                ld a,(hl)
                cp 32
                jr c,dl_sp
                cp 128
                jr c,dl_ok
dl_sp:          ld a,32
dl_ok:          sub 32
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,FONT
                add hl,de
                ld a,(dl_k)
                ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                and $FC
                ld h,a
                ld l,0
                ld de,$FC00
                ld a,(dl_s)
                and 7
                jr z,dl_sd
                ld b,a
dl_sl:          srl h
                rr l
                srl d
                rr e
                djnz dl_sl
dl_sd:          ld a,(dl_s)
                rrca
                rrca
                rrca
                and 31
                ld c,a
                ld b,0
                ld ix,LB
                add ix,bc
                ld a,h
                or (ix+0)
                ld (ix+0),a
                ld a,l
                or (ix+1)
                ld (ix+1),a
                ld a,d
                or (ix+34)
                ld (ix+34),a
                ld a,e
                or (ix+35)
                ld (ix+35),a
                ld a,(dl_s)
                add a,6
                ld (dl_s),a
                pop hl
                inc hl
                pop bc
                djnz dl_ch
                xor a
                ld (dl_j),a
dl_cell:        ld a,(dl_j)
                ld e,a
                ld d,0
                ld hl,LB
                add hl,de
                ld c,(hl)               ; bitmap de los glifos
                ld de,34
                add hl,de
                ld b,(hl)               ; cobertura
                ld a,b
                cp $FF
                jr nz,dl_part
                ld a,(dl_j)
                ld hl,dl_ca
                add a,(hl)
                ld e,a
                ld d,0
                ld hl,(srow)
                add hl,de
                ld a,(dl_bg)
                ld e,a
                ld a,(dl_fg)
                cp e
                jr nz,dl_f2
                ld c,0                  ; una celda de un solo color lleva el bitmap a 0
dl_f2:          ld (hl),c
                ld a,h
                add a,$20
                ld h,a
                ld a,e
                rlca
                rlca
                rlca
                rlca
                ld e,a
                ld a,(dl_fg)
                or e
                ld (hl),a
                jr dl_next
dl_part:        or a
                jr z,dl_next
                ld (dl_m),a
                ld a,c
                ld (dl_b),a
                ld a,(dl_j)
                ld hl,dl_ca
                add a,(hl)
                add a,a
                add a,a
                add a,a
                ld (dl_hx),a
                ld a,$80
                ld (dl_bm),a
dl_pix:         ld a,(dl_m)
                ld hl,dl_bm
                and (hl)
                jr z,dl_pn
                ld a,(dl_b)
                and (hl)
                ld a,(dl_fg)
                jr nz,dl_pc
                ld a,(dl_bg)
dl_pc:          ld (sch),a
                ld a,(dl_hx)
                call plot
dl_pn:          ld hl,dl_hx
                inc (hl)
                ld hl,dl_bm
                srl (hl)
                jr nz,dl_pix
dl_next:        ld hl,dl_j
                inc (hl)
                ld a,(dl_nb)
                cp (hl)
                jp nz,dl_cell
                ld hl,dl_k
                inc (hl)
                ld a,(hl)
                cp 8
                jp nz,dl_kl
                jp text_bg

; A = linea de pantalla -> srow = direccion del bitmap de su primera celda
t_srow:         ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,HR_BM
                add hl,de
                ld (srow),hl
                ld de,$2000
                add hl,de
                ld (sarow),hl
                ret

; ---------------------------------------------------------------------
;  clear.lines: filas A-B con el color C (EGA)
; ---------------------------------------------------------------------
t_clear_lines:  ld a,(ARGS)
                ld (cl_r),a
                ld a,(ARGS+1)
                cp 24
                jr c,cl_e
                ld a,23
cl_e:           ld (cl_end),a
cl_row:         ld a,(cl_end)
                ld hl,cl_r
                cp (hl)
                ret c
                ld a,(hl)
                ld (dl_row),a
                ld a,(ARGS+2)
                call fill_row
                ld hl,cl_r
                inc (hl)
                jr cl_row

; dl_row = fila, A = color EGA: la rellena (bitmap 0, papel = tinta = color)
fill_row:       call t_chroma
                ld c,a
                rlca
                rlca
                rlca
                rlca
                or c
                ld (cl_attr),a
                xor a
                ld (dl_ca),a
                ld a,32
                ld (dl_nb),a
                xor a
                ld (dl_k),a
fr_k:           ld a,(dl_row)
                add a,a
                add a,a
                add a,a
                ld b,a
                ld a,(dl_k)
                add a,b
                call t_srow
                ld hl,(srow)
                ld b,32
                xor a
fr_b:           ld (hl),a
                inc hl
                djnz fr_b
                ld hl,(srow)
                ld a,h
                add a,$20
                ld h,a
                ld a,(cl_attr)
                ld b,32
fr_a:           ld (hl),a
                inc hl
                djnz fr_a
                ld hl,dl_k
                inc (hl)
                ld a,(hl)
                cp 8
                jr nz,fr_k
                jp text_bg

; ---------------------------------------------------------------------
;  Barra de estado
; ---------------------------------------------------------------------
t_status_on:    ld a,1
                ld (st_on),a
                xor a
                ld (st_valid),a
                ret

t_status_off:   xor a
                ld (st_on),a
                ld (dl_row),a
                jp fill_row             ; A = 0: color 0 (negro)

t_status:       ld a,(st_on)
                or a
                ret z
                ld a,(st_valid)
                or a
                jr z,ts_draw
                ld a,(VARS+3)
                ld hl,st_v3
                cp (hl)
                jr nz,ts_draw
                ld a,(VARS+7)
                ld hl,st_v7
                cp (hl)
                jr nz,ts_draw
                ld a,(FLAGS+9)
                ld hl,st_f9
                cp (hl)
                ret z
ts_draw:        ld a,1
                ld (st_valid),a
                ld a,(VARS+3)
                ld (st_v3),a
                ld a,(VARS+7)
                ld (st_v7),a
                ld a,(FLAGS+9)
                ld (st_f9),a
                xor a
                ld (dl_row),a
                ld a,15
                call fill_row
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,60
                ld (bs_max),a
                ld hl,s_score
                call put_str
                ld a,(st_v3)
                call put_dec
                ld hl,s_of
                call put_str
                ld a,(st_v7)
                call put_dec
                call bs_end
                xor a
                call t_chroma
                ld (dl_fg),a
                ld a,15
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                xor a
                ld (dl_row),a
                ld (dl_col),a
                call draw_line
                ld hl,s_son
                ld a,(st_f9)
                or a
                ld a,8
                jr nz,ts_snd
                ld hl,s_soff
                ld a,9
ts_snd:         ld (dl_n),a
                ld (dl_ptr),hl
                ld a,30
                ld (dl_col),a
                jp draw_line

; HL = cadena terminada en 0 -> al texto de salida (bs_put)
put_str:        ld a,(hl)
                or a
                ret z
                inc hl
                push hl
                call bs_put
                pop hl
                jr put_str

; ---------------------------------------------------------------------
;  Teclado del ZX81
;
;  t_kpoll se llama muchas veces (en los bucles largos del dibujo y al principio de cada ciclo): lee la matriz, detecta las teclas recien
;  pulsadas y deja eventos en una cola (PQ). No dibuja ni toca el estado del interprete. t_kdeliv, al principio del ciclo, hace un poll,
;  entrega la cola (teclas -> key_push, direccion -> dirhold, linea -> ev_text) y, en modo real, redibuja la linea de entrada si cambio.
;  Capas (como EXAMPLES/EDIT): base = minusculas, SHIFT = mayusculas (SHIFT+1 = ESC, SHIFT+9 = borrar, SHIFT+0 = DEL), ENTER+tecla =
;  simbolos; ENTER solo = CR al soltarlo. Direccion del ego: SHIFT + 5 (izq), 6 (abajo), 7 (arriba), 8 (der), con diagonales.
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
                ld hl,ke_r
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
                ld a,1
                push bc
                call kq_put
                pop bc
                ld a,(accin)
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
                ret z
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
                jr z,kd_set
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
kdl_p:          ld hl,(ncyc)            ; la linea de entrada solo se dibuja en modo real (ncyc = 0)
                ld a,h
                or l
                ret nz
                ld a,(accin)
                ld hl,kb_lacc
                cp (hl)
                jr z,kp_ch
                ld (hl),a
                ld a,1
                ld (kb_dirty),a
kp_ch:          ld a,(kb_dirty)
                or a
                ret z
                xor a
                ld (kb_dirty),a
                ld a,23
                ld (dl_row),a
                xor a
                call fill_row
                ld a,(accin)
                or a
                ret z
                ld hl,TXT
                ld (bs_dp),hl
                xor a
                ld (bs_n),a
                ld a,60
                ld (bs_max),a
                ld hl,s_prompt
                call put_str
                ld hl,INBUF
                call put_str
                ld a,'_'
                call bs_put
                ld a,15
                call t_chroma
                ld (dl_fg),a
                xor a
                call t_chroma
                ld (dl_bg),a
                ld hl,TXT
                ld (dl_ptr),hl
                ld a,(bs_n)
                ld (dl_n),a
                ld a,23
                ld (dl_row),a
                xor a
                ld (dl_col),a
                jp draw_line

s_prompt:       defb "> ",0

; indice = fila * 5 + bit; fila 0 = A8 (SHIFT Z X C V), 1 = A9 (A S D F G), 2 = A10 (Q W E R T), 3 = A11 (1-5), 4 = A12 (0 9 8 7 6), 5 = A13 (P O I U Y), 6 = A14 (ENTER L K J H), 7 = A15 (SPACE . M N B)
km_base:        defb 0,'z','x','c','v'
                defb 'a','s','d','f','g'
                defb 'q','w','e','r','t'
                defb '1','2','3','4','5'
                defb '0','9','8','7','6'
                defb 'p','o','i','u','y'
                defb 0,'l','k','j','h'
                defb ' ','.','m','n','b'
km_shift:       defb 0,'Z','X','C','V'
                defb 'A','S','D','F','G'
                defb 'Q','W','E','R','T'
                defb 27,0,0,0,0                 ; SHIFT+1 = ESC; 2-5: sin caracter (5 = izquierda)
                defb 127,8,0,0,0                ; SHIFT+0 = DEL, SHIFT+9 = borrar; 8, 7, 6: direcciones
                defb 'P','O','I','U','Y'
                defb 0,'L','K','J','H'
                defb ' ',9,'M','N','B'
km_sym:         defb 0,':',';','?','/'
                defb 0,92,0,126,96              ; S = \  F = ~  G = `
                defb 39,123,125,91,95           ; Q = '  W = {  E = }  R = [  T = _
                defb '!',64,'#',124,'%'         ; 1 = !  2 = @  3 = #  4 = |  5 = %
                defb 0,0,0,0,'&'                ; 6 = &
                defb 34,')','(','$',93          ; P = "  O = )  I = (  U = $  Y = ]
                defb 0,'=','+','-',94           ; L = =  K = +  J = -  H = ^
                defb ' ',',','>','<','*'        ; . = ,  M = >  N = <  B = *

kb_cur:         defs 8
kb_prev:        defs 8
kb_shift:       defb 0
kb_enter:       defb 0
kb_eused:       defb 0
kb_dprev:       defb 0
kb_dirty:       defb 0
kb_lacc:        defb 0
accin:          defb 1
il_n:           defb 0
kq_n:           defb 0
ke_r:           defb 0
ke_m:           defb 0
ke_b:           defb 0
INBUF:          defs 41
PTEXT:          defs 42
PQ:             defs 2*PQ_MAX

s_score:        defb " Score:",0
s_of:           defb " of ",0
s_son:          defb "Sound:on"
s_soff:         defb "Sound:off"

tfg:            defb 15
tbg:            defb 0
tcol0:          defb 0
tterm:          defb 0
st_on:          defb 0
st_valid:       defb 0
st_v3:          defb 0
st_v7:          defb 0
st_f9:          defb 0
cl_r:           defb 0
cl_end:         defb 0
cl_attr:        defb 0
dl_ptr:         defw 0
dl_n:           defb 0
dl_row:         defb 0
dl_row0:        defb 0
dl_col:         defb 0
dl_fg:          defb 0
dl_bg:          defb 0
dl_x0:          defb 0
dl_ca:          defb 0
dl_nb:          defb 0
dl_k:           defb 0
dl_s:           defb 0
dl_j:           defb 0
dl_m:           defb 0
dl_b:           defb 0
dl_hx:          defb 0
dl_bm:          defb 0
LB:             defs 68


; A = pixel HiRes (0-255), sch = color, srow = direccion del bitmap de la fila
plot:           ld b,a
                and 7
                ld e,a
                ld d,0
                ld hl,masks
                add hl,de
                ld a,(hl)
                ld (pmk),a
                ld a,b
                rrca
                rrca
                rrca
                and 31
                ld e,a
                ld d,0
                ld hl,(sarow)
                add hl,de
                push hl                 ; byte de atributos
                ld hl,(srow)
                add hl,de
                ex de,hl                ; DE = byte del bitmap
                pop hl                  ; HL = byte de atributos
                ld a,(hl)
                ld b,a
                and 15
                ld (pk),a
                ld a,b
                rrca
                rrca
                rrca
                rrca
                and 15
                ld (pp),a
                ld a,(sch)
                ld b,a                  ; B = color nuevo
                ld a,(pk)
                ld c,a
                ld a,(pp)
                cp c
                jr nz,pl_two
                ld a,c                  ; celda de un solo color: sus bits estan a 0 y se quedan asi si el color es el mismo
                cp b
                jr z,pl_clr
                jr pl_ri
pl_two:         ld a,(pk)
                cp b
                jr z,pl_set
                ld a,(pp)
                cp b
                jr z,pl_clr
                push hl
                push de
                ld a,b
                rlca
                rlca
                rlca
                rlca
                ld e,a
                ld d,0
                ld hl,sdist_tab
                add hl,de
                push hl
                ld a,(pp)
                ld e,a
                add hl,de
                ld c,(hl)               ; distancia al papel
                pop hl
                ld a,(pk)
                ld e,a
                add hl,de
                ld a,(hl)               ; distancia a la tinta
                cp c
                pop de
                pop hl
                jr z,pl_ri
                jr c,pl_ri
                ld a,b                  ; el papel esta mas lejos que la tinta: sustituye al papel
                rlca
                rlca
                rlca
                rlca
                ld c,a
                ld a,(pk)
                or c
                ld (hl),a
                jr pl_clr
pl_ri:          ld a,(pp)
                rlca
                rlca
                rlca
                rlca
                or b
                ld (hl),a
pl_set:         ld a,(pmk)
                ld c,a
                ld a,(de)
                or c
                ld (de),a
                ret
pl_clr:         ld a,(pmk)
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                ret

masks:          defb 128,64,32,16,8,4,2,1
sch:            defb 0
srow:           defw 0
sarow:          defw 0
pk:             defb 0
pp:             defb 0
pmk:            defb 0

                include "sprtab.inc"
                include "agihws.asm"
                include "agisw.asm"

FONT:
                include "font6.inc"
