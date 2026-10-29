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
                call OVL_BGSAVE
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

; Margenes de add.to.pic (x, y, ancho, 0 o 1) que cruzan la fila ny entre nx y nx+ow-1: encienden pr_has0 / pr_has1
mg_probe:       ld a,(mg_n)
                or a
                ret z
                ld b,a
                ld iy,mg_tab
mg_l:           ld a,(ny)
                cp (iy+1)
                jr nz,mg_n2
                ld a,(nx)
                ld c,a                  ; C = nx
                ld a,(ow)
                add a,c
                ld d,a                  ; D = nx + ow
                ld a,(iy+0)
                ld e,a                  ; E = mx
                add a,(iy+2)            ; mx + mw
                cp c
                jr z,mg_n2
                jr c,mg_n2              ; mx + mw <= nx
                ld a,e
                cp d
                jr nc,mg_n2             ; mx >= nx + ow
                ld a,1
                bit 0,(iy+3)
                jr nz,mg_1
                ld (pr_has0),a
                jr mg_n2
mg_1:           ld (pr_has1),a
mg_n2:          ld de,4
                add iy,de
                djnz mg_l
                ret

; Parte de can_be_here que mira la imagen -> A = 0 si el sitio no vale
pic_check:      ld a,(picvalid)
                or a
                jr z,pk_ok
                call pri_probe
                call mg_probe
                ld a,(pr_has0)
                or a
                jr nz,pk_no             ; un 0 bloquea siempre (ignore.blocks solo salta los 1 y el rectangulo de block)
pk_1:           ld a,(curk)             ; un 1 bloquea al ego que no ignora bloques
                or a
                jr nz,pk_1b
                ld a,(pr_has1)
                or a
                jr z,pk_1b
                bit 0,(ix+O_F2)
                jr z,pk_no
pk_1b:          ld a,(ix+O_WATER)
                cp 2
                jr nz,pk_2
                ld a,(pr_water)         ; solo tierra: nada de agua
                or a
                jr nz,pk_no
pk_2:           ld a,(ix+O_WATER)
                cp 1
                jr nz,pk_3
                ld a,(pr_land)          ; solo agua: nada de tierra
                or a
                jr nz,pk_no
pk_3:           ld a,(curk)
                or a
                jr nz,pk_ok
                ld a,(pr_water)         ; ego: bandera 0 = todo agua, bandera 3 = linea de aviso
                ld hl,ow
                cp (hl)
                ld a,0
                jr nz,pk_f0
                inc a
pk_f0:          ld (FLAGS+0),a
                ld a,(pr_sig)
                ld (FLAGS+3),a
pk_ok:          ld a,1
                ret
pk_no:          xor a
                ret
