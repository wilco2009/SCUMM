; =====================================================================
;  agipic.asm - imagenes del interprete AGI (se incluye desde agivm.asm)
;
;  draw.pic lee PICnnn.GFX (TOOLS/agi2hr.py): el visual en HiRes 8x1 va a $A000 (bitmap) y $C000 (atributos), desplazado 8 lineas
;  (la fila 0 es la de estado); la prioridad (160x168, RLE por filas) se queda en la pagina PG_PRI con un indice de filas delante,
;  y can_be_here la consulta para las lineas de control (0 bloquea, 2 aviso, 3 agua) como el modelo de Python.
;  overlay.pic (solo KQ1): la imagen de la sala con el overlay ya aplicado es otro .GFX (PICAnn.GFX, ver agi2hr.py) que se carga como una imagen normal.
; =====================================================================

HR_BM           equ $A000
HR_ATT          equ $C000
PLANEB          equ 168*32
PRI_RLE         equ LWIN+336            ; el RLE empieza tras el indice de 168 filas (u16)
PRI_MAX         equ 7800

h_draw_pic:     call clr_static
                xor a
                ld (ovl_on),a
                ld a,(ARGS)
                call getv
                ld (lastpic),a
dp_num:         call mk_nm3             ; (dp_num: A = imagen; lo usa cargar partida)
                ld a,(ovl_on)           ; con overlay.pic: PICAnn.GFX (la cifra de las centenas pasa a letra: 0 -> A, 1 -> B, 2 -> C)
                or a
                jr z,dp_o
                ld hl,nm3+7
                ld a,(hl)
                add a,17
                ld (hl),a
dp_o:           ld hl,nm3
                call f_open
                cp $FF
                jr nz,lp_o
                ld a,11
                jp fatal
lp_o:           ld (fh),a
                ld hl,MSGBUF
                ld bc,256
                call f_read_n
                ld a,(MSGBUF)
                cp 'A'
                jp nz,lp_bad
                ld a,(MSGBUF+3)
                cp 'P'
                jp nz,lp_bad
                ld hl,(MSGBUF+10)       ; bytes de prioridad
                ld bc,PRI_MAX
                or a
                sbc hl,bc
                jp nc,lp_bad
                ld hl,(MSGBUF+10)
                ld (prisz),hl
                ld hl,(MSGBUF+12)
                ld (prisz2),hl
                ld bc,PRI_MAX
                or a
                sbc hl,bc
                jp nc,lp_bad
                ld a,(fh)
                ld hl,HR_BM+256
                ld bc,PLANEB
                call f_read_n
                ld a,(fh)
                ld hl,HR_ATT+256
                ld bc,PLANEB
                call f_read_n
                ld a,PG_PRI
                call map_page
                ld a,(fh)
                ld hl,PRI_RLE
                ld bc,(prisz)
                call f_read_n
                call pri_index
                ld a,PG_PRI2
                call map_page
                ld a,(fh)
                ld hl,PRI_RLE
                ld bc,(prisz2)
                call f_read_n
                call pri_index
                ld a,PG_PMX             ; maximos de la prioridad por bloques (para los sprites)
                call map_page
                ld a,(fh)
                ld hl,LWIN
                ld bc,168*20
                call f_read_n
                call unmap_win
                ld hl,OVE_BGSAVE
                call call_e
                ld a,(fh)
                call f_close
                ld a,1
                ld (picvalid),a
                ret
; Con la pagina de prioridad mapeada y su RLE leido en PRI_RLE: el indice (desplazamiento de cada fila) en LWIN
pri_index:
                ld hl,PRI_RLE           ; indice: donde empieza cada fila
                ld de,LWIN
                ld b,168
pi_row:         push hl
                push de
                ld de,PRI_RLE
                or a
                sbc hl,de               ; HL = desplazamiento de la fila
                ex de,hl
                pop hl                  ; HL = posicion en el indice
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ex de,hl                ; DE = indice siguiente
                pop hl                  ; HL = lectura del RLE
                ld c,0
pi_run:         ld a,(hl)
                inc hl
                and 15
                inc a
                add a,c
                ld c,a
                cp 160
                jr c,pi_run
                djnz pi_row
                ret
lp_bad:         ld a,(fh)
                call f_close
                ld a,12
                jp fatal

; A = numero -> "PICnnn.GFX" en nm3
mk_nm3:         ld hl,nm3+7
mk_dig:         ld b,'0'-1
m3_h:           inc b
                sub 100
                jr nc,m3_h
                add a,100
                ld (hl),b
                ld b,'0'-1
m3_t:           inc b
                sub 10
                jr nc,m3_t
                add a,10+'0'
                inc hl
                ld (hl),b
                inc hl
                ld (hl),a
                ret

; Mira la linea ny entre nx y nx+ow-1 de la prioridad: pr_has0 (hay un 0), pr_water (pixeles con 3), pr_land (los demas), pr_sig (hay un 2)
pri_probe:      xor a
                ld (pr_has0),a
                ld (pr_has1),a
                ld (pr_water),a
                ld (pr_land),a
                ld (pr_sig),a
                ld (pp_xs),a
                ld a,PG_PRI
                call map_page
                ld hl,(ny)
                add hl,hl
                ld de,LWIN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,PRI_RLE
                add hl,de               ; HL = RLE de la fila
                ld a,(nx)
                ld (pp_x0),a
                ld b,a
                ld a,(ow)
                add a,b
                ld (pp_x1),a            ; fin (exclusivo)
pp_l:           ld a,(pp_xs)
                ld b,a                  ; B = principio del tramo
                ld a,(pp_x1)
                cp b
                jr z,pp_end
                jr c,pp_end
                ld a,(hl)
                inc hl
                ld c,a
                and 15
                inc a
                add a,b
                ld e,a                  ; E = fin del tramo
                ld a,c
                rrca
                rrca
                rrca
                rrca
                and 15
                ld c,a                  ; C = valor
                ld a,(pp_x0)            ; inicio del solape = max(x0, B)
                cp b
                jr nc,pp_lo
                ld a,b
pp_lo:          ld d,a                  ; D = inicio
                ld a,(pp_x1)            ; fin del solape = min(x1, E)
                cp e
                jr c,pp_hi
                ld a,e
pp_hi:          sub d
                jr z,pp_nx
                jr c,pp_nx
                ld b,a                  ; B = pixeles del solape
                ld a,c
                or a
                jr nz,pp_a
                inc a
                ld (pr_has0),a
pp_a:           ld a,c
                cp 1
                jr nz,pp_b
                ld (pr_has1),a
pp_b:           ld a,c
                cp 3
                jr nz,pp_land
                ld a,(pr_water)
                add a,b
                ld (pr_water),a
                jr pp_s
pp_land:        ld a,(pr_land)
                add a,b
                ld (pr_land),a
pp_s:           ld a,c
                cp 2
                jr nz,pp_nx
                ld a,1
                ld (pr_sig),a
pp_nx:          ld a,e
                ld (pp_xs),a
                jr pp_l
pp_end:         jp unmap_win

; Cajas de add.to.pic (x, y, ancho, valor | alto << 2) que cruzan la fila ny entre nx y nx+ow-1: abajo y arriba toda la anchura, entre medias los dos lados;
; encienden pr_has0 / pr_has1 / pr_sig segun el valor (0, 1, 2)
mg_probe:       ld a,(mg_n)
                or a
                ret z
                ld b,a
                ld iy,mg_tab
mg_l:           ld a,(iy+3)
                rrca
                rrca
                and 63
                ld c,a                  ; C = alto
                ld d,(iy+1)             ; D = y de abajo
                ld a,(ny)
                cp d
                jr z,mq_row
                ld a,c
                cp 2
                jr c,mq_nx              ; alto 1: solo la linea de abajo
                ld a,d
                sub c
                inc a
                ld e,a                  ; E = fila de arriba
                ld a,(ny)
                cp e
                jr z,mq_row
                jr c,mq_nx
                cp d
                jr nc,mq_nx
                ld a,(iy+0)             ; entre medias: el lado izquierdo o el derecho dentro de [nx, nx+ow)
                call mq_pt
                jr nz,mq_hit
                ld a,(iy+0)
                add a,(iy+2)
                dec a
                call mq_pt
                jr nz,mq_hit
                jr mq_nx
mq_row:         ld c,(iy+0)             ; la anchura entera: x < nx + ow  y  nx < x + w
                ld hl,nx
                ld a,(ow)
                add a,(hl)
                ld d,a
                ld a,c
                cp d
                jr nc,mq_nx
                add a,(iy+2)
                ld e,a
                ld a,(hl)
                cp e
                jr nc,mq_nx
mq_hit:         ld a,(iy+3)
                and 3
                ld hl,pr_has0
                jr z,mq_set
                ld hl,pr_has1
                dec a
                jr z,mq_set
                ld hl,pr_sig
mq_set:         ld (hl),1
mq_nx:          ld de,4
                add iy,de
                djnz mg_l
                ret
; NZ si nx <= A < nx + ow
mq_pt:          ld hl,nx
                sub (hl)
                jr c,mq_pn
                ld hl,ow
                cp (hl)
                jr nc,mq_pn
                or 1
                ret
mq_pn:          xor a
                ret

; Parte de can_be_here que mira la imagen -> A = 0 si el sitio no vale
pic_check:      ld a,(picvalid)
                or a
                jr z,pk_ok
                ld a,(ix+O_PRI)         ; prioridad: la fijada o la de la y candidata
                bit 5,(ix+O_F1)
                jr nz,pk_p
                ld a,(ny)
                call pri_y
pk_p:           cp 15                   ; con 15 no se mira la imagen; las banderas 0 y 3 del ego se apagan
                jr nz,pk_s
                ld a,(curk)
                or a
                jr nz,pk_ok
                ld (FLAGS+0),a
                ld (FLAGS+3),a
                jr pk_ok
pk_s:           call pri_probe
                call mg_probe
                ld a,(curk)
                or a
                jr nz,pk_0
                ld a,(pr_water)         ; ego: bandera 0 = todo agua, bandera 3 = linea de aviso (tambien si se rechaza)
                ld hl,ow
                cp (hl)
                ld a,0
                jr nz,pk_f0
                inc a
pk_f0:          ld (FLAGS+0),a
                ld a,(pr_sig)
                ld (FLAGS+3),a
pk_0:           ld a,(pr_has0)
                or a
                jr nz,pk_no             ; un 0 bloquea siempre (ignore.blocks solo salta los 1 y el rectangulo de block)
                ld a,(pr_has1)
                or a
                jr z,pk_1b
                bit 0,(ix+O_F2)         ; un 1 bloquea a todo objeto que no ignora bloques
                jr z,pk_no
pk_1b:          ld a,(ix+O_WATER)
                cp 2
                jr nz,pk_2
                ld a,(pr_water)         ; on.land: no todo el ancho sobre agua
                ld hl,ow
                cp (hl)
                jr z,pk_no
pk_2:           ld a,(ix+O_WATER)
                cp 1
                jr nz,pk_ok
                ld a,(pr_water)         ; on.water: todo el ancho sobre agua
                ld hl,ow
                cp (hl)
                jr nz,pk_no
pk_ok:          ld a,1
                ret
pk_no:          xor a
                ret
