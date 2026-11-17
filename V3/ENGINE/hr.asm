; =====================================================================
;  hr.asm - video HiRes 8x1 de 16 colores (rama hires16). Plan: claude/planning/scumm_hires16.md
;
;  Lo que se ve esta siempre en el mapa del Z80: bitmap HR_BM (6 KB, linea y * 32 + columna), atributos HR_ATT (6 KB, un byte por byte de
;  linea: papel en el nibble alto, tinta en el bajo) y los bufers de entrada del scroll por hardware (derecha / izquierda, un byte por linea).
;  La sala entera (ROOMnn.GFX, hecho por TOOLS/lfl2hr.py) esta en las paginas fisicas ROOMPG0.. y se asoma por la ventana de datos
;  (bloque WINBLK) solo mientras se copia un trozo; despues se restaura la pagina que habia (WINPG, vm_core.asm).
;
;  Formato del .GFX: version 2 de lfl3hr.py (V3/TOOLS/LFL3HR.md): alto variable (+8), columnas por pagina (+12); la columna k esta en
;  256 + (k / cpp) * 8192 + (k % cpp) * 2 * lineas.
;
;  DISENO D3 (V3/PLAN.md): 192 lineas = 16 de mensajes arriba (filas 0-1), 128 de sala (filas 2-17: HR_TOP) y 48 de interfaz (filas 18-23).
;  Una sala de mas de 128 lineas se recorta: se ven las lineas [hv_ytop, hv_ytop + 128) (hv_ytop = 16 si la sala tiene 144 lineas o mas, que es el
;  alto visible de la pantalla principal de v3: se pierden las 16 de arriba; D3 deja el scroll vertical para cuando haya prueba en la placa).
;
;  Camara: gf_cam / gf_fine son la posicion LOGICA (la que piden los scripts, gf_move_*); hv_cam / hv_fine, la del hardware. hr_frame (una vez
;  por fotograma) acerca la del hardware a la logica: el fino por POKE 2090 y, al pasar de columna, la orden del motor de scroll
;  (puerto $3FEF), que mueve la memoria un byte en el borrado; cuando acaba se rellena el bufer de entrada que toca.
;  Invariante: el bufer de la izquierda tiene la columna hv_cam - 1 y el de la derecha la hv_cam + 32.
; =====================================================================
HR_BM           equ $A000
HR_TOP          equ 16                  ; D3: linea de pantalla de la primera linea de la sala (las 16 de arriba son de los mensajes)
HR_RBM          equ HR_BM+$1800         ; entrada derecha (bitmap): un byte por linea de pantalla (la sala empieza en HR_TOP)
HR_LBM          equ HR_BM+$1C00         ; entrada izquierda
HR_ATT          equ $C000
HR_RATT         equ $D800
HR_LATT         equ $DC00
HR_OBJREC       equ HR_BM+$1A07         ; 6 bytes por objeto (hasta 84): desplazamiento (2), columna, linea, columnas, lineas; sitio libre del bloque del bitmap
HR_DLIST        equ HR_BM+$1E00         ; indices de los objetos que se dibujan, del ultimo al primero
HR_COLBUF       equ HR_BM+$1F00         ; la columna que se compone: 128 bytes de bitmap y 128 de atributos
HR_FLAGS        equ HR_ATT+$1A07        ; un byte por objeto (hasta 84): 1 si se dibujaba la ultima vez (sitio libre del bloque de atributos)
HR_NFLAGS       equ HR_ATT+$1B00        ; lo mismo, con el estado de ahora
HR_ZFL          equ HR_ATT+$1A60        ; fase 10b: 84 bytes, 1 si el objeto esta en OV_ZL (lo dibujo un drawObject: va al final de la lista); lo rellena hr_mkdl
HR_DIRTY        equ HR_ATT+$1980        ; fase 10b: 32 bytes (alineado a 32), un bit por columna del mundo (0-255) que hr_objupd tiene que recomponer (en el bufer de abajo del scroll vertical, que no se usa)
ROOMPG0         equ 8                   ; paginas fisicas de la sala (8-14: la 79 mide 50.602 bytes)
ROOMMAX         equ 7*8192
WINBLK          equ 1                   ; bloque de la ventana de datos
DBGPORT         equ $3FEF

HV              equ SV+100
hv_cam          equ HV+0                ; palabra: columna del hardware
hv_fine         equ HV+2
hv_pend         equ HV+3                ; orden del motor en marcha: 0 ninguna, 1 izquierda, 2 derecha
hv_ndl          equ HV+4
hv_nobj         equ HV+5
hv_objsec       equ HV+6                ; palabra
hv_w            equ HV+8                ; palabra: columna del mundo que se compone
hv_i            equ HV+10
hv_c            equ HV+11
hv_s            equ HV+12
hv_j            equ HV+13
hv_off          equ HV+14               ; palabra x 3: hr_fcopy
hv_dst          equ HV+16
hv_len          equ HV+18
hv_oo           equ HV+20               ; el objeto que se compone
hv_oc           equ HV+22
hv_ol           equ HV+23
hv_on           equ HV+24
hv_oh           equ HV+25
hv_so           equ HV+26
hv_rem          equ HV+28
hv_pg           equ HV+30
hv_y0           equ HV+32               ; fase 10c: lineas de la ventana que componen hr_makecol / hr_put: [hv_y0, 128 - hv_y1), multiplos de 8 (0 y 0: las 128)
hv_y1           equ HV+33
hv_ch            equ HV+34
hv_dark         equ HV+35               ; 1: la sala esta a oscuras (dark.asm): hr_put oscurece los atributos de lo que dibuja
hv_lines        equ HV+36               ; D3: lineas de la sala en el .GFX, las que se ven (<= 128), la primera que se ve, columnas por pagina, 2 * lineas (palabra)
hv_hh           equ HV+37
hv_ytop         equ HV+38
hv_cpp          equ HV+39
hv_l2           equ HV+40
hv_cs           equ HV+42               ; clip de un objeto en la columna: primera linea (absoluta), destino y longitud
hv_cd           equ HV+43
hv_cl           equ HV+44
hv_wlo          equ HV+45               ; fase 10c: lineas de la sala (absolutas) que compone hr_makecol: [hv_wlo, hv_whi)
hv_whi          equ HV+46
hv_dlo          equ HV+47               ; fase 10c: primer indice de la lista de objetos que recorre hr_makecol (0: HR_DLIST; 128: la filtrada de hr_orect, HR_DLIST+128)
hv_ndls         equ HV+48               ; fase 10c: hv_ndl guardado mientras hv_ndl es el final de la lista filtrada
hv_nobg         equ HV+49               ; fase 10c: 1 = hr_makecol no copia el fondo (la lista filtrada empieza por un objeto que cubre todo el rectangulo)
hv_nr           equ SV+242              ; fase 10c: rectangulos ya recompuestos en este hr_objupd (en HR_RECTS)
HR_RECTS        equ HR_BM+$1900         ; fase 10c: hasta 32 x 4 bytes (columna, columnas, hv_y0, hv_y1); el bufer de abajo del scroll vertical, que no se usa
hv_drawn        equ HV+31               ; 0: la sala aun no se ha dibujado (se dibuja ya en su sitio: el salto de la camara, o gd_update si nadie la mueve)

; ---------------------------------------------------------------------
;  Pagina de la sala -> ventana de datos; hr_unmap devuelve la que habia
; ---------------------------------------------------------------------
hr_map:         add a,ROOMPG0           ; A = pagina de la sala (0-5)
                ld b,a
                ld c,MAP_PORT
                ld a,WINBLK
                out (c),a
                ret

hr_unmap:       ld a,(WINPG)
                ld b,a
                ld c,MAP_PORT
                ld a,WINBLK
                out (c),a
                ret

; HL = desplazamiento en el .GFX, DE = destino, BC = bytes: copia cruzando paginas (deja una pagina de la sala en la ventana)
hr_fcopy:       ld (hv_off),hl
                ld (hv_dst),de
                ld (hv_len),bc
hfc1:           ld bc,(hv_len)
                ld a,b
                or c
                ret z
                ld hl,(hv_off)
                ld a,h
                rrca
                rrca
                rrca
                rrca
                rrca
                and 7
                call hr_map
                ld hl,(hv_off)
                ld a,h
                and $1F
                ld h,a                  ; HL = desplazamiento dentro de la pagina
                ld de,$2000
                ex de,hl                ; DE = desplazamiento, HL = $2000
                or a
                sbc hl,de               ; HL = lo que queda de pagina
                ld bc,(hv_len)
                push hl
                or a
                sbc hl,bc
                pop hl
                jr nc,hfc2              ; queda mas que lo pedido: BC = lo pedido
                ld b,h
                ld c,l                  ; si no, lo que queda de pagina
hfc2:           push bc
                ld hl,$2000
                add hl,de               ; origen en la ventana
                ld de,(hv_dst)
                ldir
                ld (hv_dst),de
                pop bc
                ld hl,(hv_off)
                add hl,bc
                ld (hv_off),hl
                ld hl,(hv_len)
                or a
                sbc hl,bc
                ld (hv_len),hl
                jr hfc1

; ---------------------------------------------------------------------
;  Una columna del mundo (DE) con sus objetos encima, en HR_COLBUF. Fuera de la sala: negra
; ---------------------------------------------------------------------
; Desplazamiento en el .GFX del bitmap de la columna hv_w, de la linea hv_ytop: 256 + (k / cpp) * 8192 + (k % cpp) * 2 * lineas + hv_ytop
hr_coloff:      ld hl,(hv_w)
                ld a,(hv_cpp)
                ld c,a
                ld b,0
                ld d,0                  ; D = k / cpp
hco_d:          or a
                sbc hl,bc
                jr c,hco_e
                inc d
                jr hco_d
hco_e:          add hl,bc               ; HL = k % cpp (< 256)
                ld a,l
                ld e,a                  ; E = k % cpp
                ld hl,256
                ld bc,(hv_l2)
                or a
                jr z,hco_m
hco_l:          add hl,bc
                dec e
                jr nz,hco_l
hco_m:          ld a,d                  ; (k / cpp) * 8192 = (k / cpp) * 32 en el byte alto (k / cpp < 8)
                add a,a
                add a,a
                add a,a
                add a,a
                add a,a
                add a,h
                ld h,a
                ld a,(hv_ytop)
                ld e,a
                ld d,0
                add hl,de
                ret

hr_makecol:     ld (hv_w),de
                ld hl,(gf_cols)
                or a
                sbc hl,de
                jp z,hm_zero
                jp c,hm_zero
                ld a,(hv_hh)
                cp 128
                call c,hm_zero          ; una sala de menos de 128 lineas: el resto de la columna a cero
                ld a,(hv_y1)            ; fase 10c: solo las lineas [hv_y0, 128 - hv_y1) de la ventana (recortadas al alto de la sala)
                ld b,a
                ld a,128
                sub b
                ld hl,hv_hh
                cp (hl)
                jr c,hm_e
                ld a,(hl)
hm_e:           ld hl,hv_ytop
                add a,(hl)
                ld (hv_whi),a
                ld a,(hv_y0)
                add a,(hl)
                ld (hv_wlo),a
                ld b,a
                ld a,(hv_nobg)          ; fase 10c: un objeto lo tapa todo
                or a
                jr nz,hm_nobg
                ld a,(hv_whi)
                sub b                   ; lineas del fondo
                jr z,hm_nobg
                jr c,hm_nobg
                ld (hv_cl),a
                call hr_coloff          ; HL = bitmap de la columna (desde la primera linea que se ve)
                ld a,(hv_y0)
                ld e,a
                ld d,0
                add hl,de
                push hl
                ld hl,HR_COLBUF
                add hl,de
                ex de,hl
                ld a,(hv_cl)
                ld c,a
                ld b,0
                pop hl
                push hl
                call hr_fcopy
                pop hl
                ld a,(hv_lines)
                ld e,a
                ld d,0
                add hl,de               ; y detras, sus atributos
                ld a,(hv_y0)
                or $80
                ld e,a
                ld d,HR_COLBUF>>8       ; HR_COLBUF + 128 + hv_y0 (HR_COLBUF acaba en $00)
                ld a,(hv_cl)
                ld c,a
                ld b,0
                call hr_fcopy
hm_nobg:        ld a,(hv_dlo)           ; fase 10c: la lista entera o la filtrada de hr_orect
                ld (hv_j),a
hm_o:           ld a,(hv_ndl)
                ld b,a
                ld a,(hv_j)
                cp b
                jp nc,ov_apply          ; fase 9: acabados los objetos, la capa de texto y cajas (txtlayer.asm) encima
                ld e,a
                ld d,0
                ld hl,HR_DLIST
                add hl,de
                ld a,(hl)               ; el objeto
                ld hl,hv_nobj
                cp (hl)
                jp nc,hm_next           ; sin registro en el .GFX
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; * 6
                ld de,HR_OBJREC
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                and e
                inc a
                jp z,hm_next            ; $FFFF: sin imagen
                ld (hv_oo),de
                ld a,(hl)
                ld (hv_oc),a
                inc hl
                ld a,(hl)
                ld (hv_ol),a
                inc hl
                ld a,(hl)
                ld (hv_on),a
                inc hl
                ld a,(hl)
                ld (hv_oh),a
                ld hl,(hv_w)
                ld a,(hv_oc)
                ld e,a
                ld d,0
                or a
                sbc hl,de               ; columna dentro del objeto
                jp c,hm_next
                ld a,h
                or a
                jp nz,hm_next
                ld a,l
                ld hl,hv_on
                cp (hl)
                jp nc,hm_next
                push af
                call hm_clip            ; la parte del objeto que cae en las lineas que se componen: hv_cs (primera, absoluta), hv_cd (destino), hv_cl (longitud)
                pop bc                  ; B = columna dentro del objeto (los indicadores, los de hm_clip)
                jp c,hm_next
                jp z,hm_next
                ld a,(hv_oh)
                ld e,a
                ld d,0
                ld hl,0
                inc b
hm_mul:         dec b
                jr z,hm_md
                add hl,de
                add hl,de
                jr hm_mul
hm_md:          ld de,(hv_oo)
                add hl,de
                ld (hv_so),hl           ; donde esta el bitmap de esa columna del objeto
                ld a,(hv_ol)
                ld c,a
                ld a,(hv_cs)
                sub c                   ; A = primera linea dentro de la columna del objeto
                ld e,a
                ld d,0
                ld hl,(hv_so)
                add hl,de               ; origen del bitmap
                push hl
                ld a,(hv_cd)
                ld e,a
                ld d,0
                ld hl,HR_COLBUF
                add hl,de
                ex de,hl                ; destino
                ld a,(hv_cl)
                ld c,a
                ld b,0
                pop hl
                call hr_fcopy
                ld a,(hv_ol)
                ld c,a
                ld a,(hv_cs)
                sub c
                ld e,a
                ld d,0
                ld hl,(hv_so)
                add hl,de
                ld a,(hv_oh)
                ld e,a
                ld d,0
                add hl,de               ; y detras, sus atributos
                push hl
                ld a,(hv_cd)
                ld e,a
                ld d,0
                ld hl,HR_COLBUF+128
                add hl,de
                ex de,hl
                ld a,(hv_cl)
                ld c,a
                ld b,0
                pop hl
                call hr_fcopy
hm_next:        ld hl,hv_j
                inc (hl)
                jp hm_o
hm_zero:        ld hl,HR_COLBUF
                ld de,HR_COLBUF+1
                ld bc,255
                ld (hl),0
                ldir
                ret

; recorta el objeto actual (hv_ol, hv_oh) a las lineas [hv_wlo, hv_whi) (fase 10c; antes la ventana [hv_ytop, hv_ytop + hv_hh)): carry o Z si no queda nada; si no, NC y NZ con hv_cs, hv_cd, hv_cl
hm_clip:        ld a,(hv_ol)
                ld hl,hv_wlo
                cp (hl)
                jr nc,hmc1
                ld a,(hl)               ; start = max(ol, wlo)
hmc1:           ld (hv_cs),a
                ld a,(hv_ol)
                ld hl,hv_oh
                add a,(hl)
                ld b,a                  ; B = ol + oh
                ld a,(hv_whi)
                cp b
                jr c,hmc2
                ld a,b                  ; end = min(ol + oh, ytop + hh)
hmc2:           ld hl,hv_cs
                sub (hl)
                ret z
                ret c
                ld (hv_cl),a
                ld a,(hv_cs)
                ld hl,hv_ytop
                sub (hl)
                ld (hv_cd),a
                or 1
                ret

; HL = origen (128 bytes, sin cruzar de pagina de 256: HR_COLBUF o HR_COLBUF+128), DE = destino: uno por linea (paso 32). Fase 10b: 8 por vuelta, desenrollado
hr_stride:      ld c,16
hs_l:                                   ; (fase 10c: entrando aqui, C = grupos de 8 lineas)
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                ld a,(hl)
                inc l
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                inc d
                dec c
                jr nz,hs_l
                ret

; HR_COLBUF a la columna de pantalla A (0-31), al bufer de la derecha (32) o al de la izquierda ($FF)
hr_put:         ld (hv_s),a
                ld a,(hv_dark)
                or a
                jr z,hp_nd
                ld a,(hv_s)
                call OVL_DKMASK         ; los atributos de lo que queda fuera de la linterna, a 0
hp_nd:          ld a,(hv_s)             ; fase 10c: solo las lineas [hv_y0, 128 - hv_y1)
                cp 32
                jr z,hp_r
                cp $FF
                jr z,hp_l
                ld e,a
                ld d,(HR_BM>>8)+HR_TOP/8
                xor a
                call hp_s
                ld a,(hv_s)
                ld e,a
                ld d,(HR_ATT>>8)+HR_TOP/8
                ld a,128
; E = columna, D = byte alto de la linea 0 de la ventana, A = 0 (bitmap) o 128 (atributos)
hp_s:           ld hl,hv_y0
                add a,(hl)
                ld b,(hl)
                ld l,a
                ld h,HR_COLBUF>>8       ; HL = HR_COLBUF (+ 128) + hv_y0
                ld a,b
                rrca
                rrca
                rrca
                add a,d
                ld d,a                  ; + hv_y0 * 32
                ld a,(hv_y1)
                add a,b
                neg
                add a,128
                rrca
                rrca
                rrca
                ld c,a                  ; grupos de 8 lineas (nunca 0)
                jp hs_l
hp_r:           ld de,HR_RBM+HR_TOP
                ld bc,HR_RATT+HR_TOP
                jr hp_b
hp_l:           ld de,HR_LBM+HR_TOP
                ld bc,HR_LATT+HR_TOP
hp_b:           push bc
                call hp_n
                ldir
                pop de
                call hp_n
                set 7,l                 ; HR_COLBUF + 128 + hv_y0
                ldir
                ret
; DE = base -> HL = HR_COLBUF + hv_y0, DE = base + hv_y0, BC = lineas
hp_n:           ld a,(hv_y0)
                ld l,a
                ld h,HR_COLBUF>>8
                add a,e
                ld e,a
                adc a,d
                sub e
                ld d,a
                ld a,(hv_y1)
                add a,l
                neg
                add a,128
                ld c,a
                ld b,0
                ret

; ---------------------------------------------------------------------
;  Objetos que se dibujan (obj_drawn, input.asm), del ultimo al primero: el primero queda encima
; ---------------------------------------------------------------------
hr_mkdl:        xor a
                ld (hv_ndl),a
                ld hl,HR_NFLAGS
                ld de,HR_NFLAGS+1
                ld bc,83
                ld (hl),a
                ldir
                ld hl,HR_ZFL            ; fase 10b: los de OV_ZL, marcados (antes se buscaban en la lista para cada objeto)
                ld de,HR_ZFL+1
                ld bc,83
                ld (hl),a
                ldir
                ld a,(OV_ZN)
                or a
                jr z,hd_z0
                ld b,a
                ld de,OV_ZL
hd_z:           ld a,(de)
                inc de
                cp 84
                jr nc,hd_zn
                ld l,a
                ld h,0
                push de
                ld de,HR_ZFL
                add hl,de
                pop de
                ld (hl),1
hd_zn:          djnz hd_z
hd_z0:          ld a,(NROBJ)
                ld (hv_i),a
hd_l:           ld a,(hv_i)
                or a
                jp z,ov_zadd            ; fase 9: acabados los de la sala, los que ha dibujado un drawObject, encima y en su orden
                dec a
                ld (hv_i),a
                call obj_drawn
                jr nc,hd_l
                ld a,(hv_i)
                cp 84
                jr nc,hd_nf
                ld e,a
                ld d,0
                ld hl,HR_NFLAGS
                add hl,de
                ld (hl),1
                ld hl,HR_ZFL
                add hl,de
                ld a,(hl)
                or a
                jr nz,hd_l              ; los de drawObject van al final de la lista (ov_zadd)
                jr hd_add
hd_nf:          ld a,(hv_i)
                call ov_inzl            ; (indice de 84 o mas: se busca en la lista)
                jr z,hd_l
hd_add:
                ld a,(hv_ndl)
                ld e,a
                ld d,0
                ld hl,HR_DLIST
                add hl,de
                ld a,(hv_i)
                ld (hl),a
                ld hl,hv_ndl
                inc (hl)
                jr hd_l

; ---------------------------------------------------------------------
;  Puesta en marcha y borrado de la pantalla
; ---------------------------------------------------------------------
hr_init:        call hr_pal16           ; fase 8: la paleta de 16 con los colores del EGA (el marron)
                xor a
                ld (2043),a
                ld a,HR_BM>>8
                ld (2044),a             ; HFILE = bitmap
                ld a,171
                ld (2045),a             ; Superfast HiRes nativo
                xor a
                ld (hv_pend),a
                ld (hv_ndl),a
                ld (hv_nobj),a
                ld (hv_y0),a            ; fase 10c: las 128 lineas y la lista entera
                ld (hv_y1),a
                ld (hv_dlo),a
                ld (hv_nobg),a
                inc a
                ld (WINPG),a            ; el bloque 1 tiene su pagina de arranque
hr_clear:       ld hl,HR_BM
                ld de,HR_BM+1
                ld bc,$1FFF
                ld (hl),0
                ldir
                ld hl,HR_ATT
                ld de,HR_ATT+1
                ld bc,$1FFF
                ld (hl),0
                ldir
                ret

; ---------------------------------------------------------------------
;  El .GFX de la sala a las paginas de la sala; cabecera y registros de objetos
; ---------------------------------------------------------------------
gf_read:        call gf_make_name
                ld hl,gf_name
                call f_open
                cp $FF
                jr nz,gfr1
                scf
                ret
gfr1:           ld (ld_h),a
                ld hl,ld_stat           ; fstat: 4 bytes de tamano, 4 de fecha y el estado
                ld a,CMD_FSTAT
                call mcu_send
                ld a,(ld_h)
                call mcu_send
                ld b,4
gfr2:           call mcu_recv
                ld (hl),a
                inc hl
                djnz gfr2
                ld b,5
gfr3:           call mcu_recv
                djnz gfr3
                ld hl,(ld_stat+2)
                ld a,h
                or l
                jr nz,gfr_bad
                ld hl,(ld_stat)
                ld (gf_size),hl
                ld (hv_rem),hl
                ld de,ROOMMAX+1
                or a
                sbc hl,de
                jr nc,gfr_bad           ; no cabe en las paginas de la sala
                xor a
                ld (hv_pg),a
gfr_p:          ld hl,(hv_rem)
                ld a,h
                or l
                jr z,gfr_done
                ld a,(hv_pg)
                call hr_map
                ld bc,(hv_rem)
                ld hl,8192
                or a
                sbc hl,bc
                jr nc,gfr_n             ; quedan 8 KB o menos
                ld bc,8192
gfr_n:          push bc
                ld a,(ld_h)
                ld hl,WINDOW
                call f_read_n
                pop bc
                ld hl,(hv_rem)
                or a
                sbc hl,bc
                ld (hv_rem),hl
                ld hl,hv_pg
                inc (hl)
                jr gfr_p
gfr_done:       call hr_unmap
                ld a,(ld_h)
                call f_close
                or a
                ret
gfr_bad:        ld a,(ld_h)
                call f_close
                scf
                ret
ld_stat:        defs 4

; cabecera: "HRGF", version, 0, columnas (2), lineas, objetos, desplazamiento de la seccion de objetos (2)
hr_parse:       xor a
                call hr_map
                ld hl,WINDOW
                ld a,(hl)
                cp 'H'
                jr nz,hpa_bad
                inc hl
                ld a,(hl)
                cp 'R'
                jr nz,hpa_bad
                ld hl,WINDOW+6
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (gf_cols),de
                ex de,hl
                ld de,-32
                add hl,de
                ld (gf_npos),hl         ; ultima posicion de la camara
                ld hl,WINDOW+8
                ld a,(hl)               ; lineas de la sala
                ld (hv_lines),a
                ld c,128
                cp c
                jr c,hpa_h              ; menos de 128: se ven todas
                ld a,c
hpa_h:          ld (hv_hh),a
                ld a,(hv_lines)
                ld c,0                  ; primera linea que se ve: 0, o 16 si la sala tiene 144 lineas o mas (se pierden las de arriba)
                cp 144
                jr c,hpa_y
                ld c,16
hpa_y:          ld a,c
                ld (hv_ytop),a
                ld hl,WINDOW+12
                ld a,(hl)
                ld (hv_cpp),a
                ld a,(hv_lines)
                ld l,a
                ld h,0
                add hl,hl
                ld (hv_l2),hl           ; 2 * lineas
                ld hl,WINDOW+9
                ld a,(hl)
                ld (hv_nobj),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (hv_objsec),de
                call hr_unmap
                ld a,(hv_nobj)
                or a
                ret z
                cp 85
                jr nc,hpa_bad2          ; no caben los registros
                ld c,a
                ld b,0
                ld h,b
                ld l,c
                add hl,hl
                add hl,bc
                add hl,hl               ; 6 por objeto
                ld b,h
                ld c,l
                ld hl,(hv_objsec)
                ld de,HR_OBJREC
                call hr_fcopy
                call hr_unmap
                or a
                ret
hpa_bad:        call hr_unmap
hpa_bad2:       scf
                ret

gf_load_room:   ld a,(EVARGS)
                ld (gf_room),a
                call hr_settle
                xor a
                ld (gf_have),a
                ld (gf_fine),a
                ld (hv_fine),a
                ld (hv_ndl),a
                ld (hv_nobj),a
                ld (hv_drawn),a
                ld (2090),a
                ld h,a
                ld l,a
                ld (gf_cam),hl
                ld (hv_cam),hl
                ld (gf_objsec),hl
                call hr_clear
                ld a,1                  ; fase 7: la pantalla de texto (arriba y abajo) se ha borrado: hr_ui la vuelve a pintar
                ld (ui_chg),a
                ld a,(gf_room)
                or a
                ret z                   ; sala 0: no hay imagen
                call gf_read
                ret c
                call hr_parse
                ret c
                ld a,1                  ; la sala se dibuja cuando la camara sepa donde esta (cam_update), no antes en la posicion 0
                ld (gf_have),a
                ret

; "DATA/ROOMnn.GFX"
gf_make_name:   ld hl,(PF_TPL)
                ld de,PROF
                add hl,de
                ld de,gf_name
gmn0:           ld a,(hl)               ; el nombre de los ficheros de sala del perfil, acabado en 0
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,gmn0
                ld a,(gf_room)
                ld b,'0'-1
gmn1:           inc b
                sub 10
                jr nc,gmn1
                add a,10+'0'
                ld hl,PF_TPLPOS
                ld e,(hl)
                ld d,0
                ld hl,gf_name
                add hl,de
                ld (hl),b
                inc hl
                ld (hl),a
                ret

; ---------------------------------------------------------------------
;  Motor de scroll
; ---------------------------------------------------------------------
; NZ si el motor esta ocupado (OUT $20 elige el indice 16 del puerto; el bit 7 es "ocupado")
hr_busy:        ld bc,DBGPORT
                ld a,$20
                out (c),a
                in a,(c)
                and $80
                ret

; A = 1 izquierda, 2 derecha
hr_send:        ld (hv_pend),a
                ld d,a
                ld bc,DBGPORT
                ld a,$41
                out (c),a
                ld a,d
                out (c),a
                ret

; espera a que el motor acabe y cierra el movimiento
hr_settle:      ld a,(hv_pend)
                or a
                ret z
hs_w:           call hr_busy
                jr nz,hs_w

; el movimiento ha acabado: la camara del hardware avanza una columna y se rellena el bufer de entrada que ha quedado vacio
hr_finish:      ld a,(hv_pend)
                ld b,a
                xor a
                ld (hv_pend),a
                ld hl,(hv_cam)
                ld a,b
                cp 1
                jr nz,hfn_r
                inc hl                  ; izquierda: la memoria se ha movido un byte a la izquierda; el bufer de la izquierda ya tiene la columna que ha salido
                ld (hv_cam),hl
                xor a
                ld (hv_fine),a
                ld (2090),a
                ld de,32
                add hl,de
                ex de,hl
                call hr_makecol
                ld a,32
                call hr_put
                call hr_dk
                jp hr_unmap
hfn_r:          dec hl                  ; derecha
                ld (hv_cam),hl
                ld a,7
                ld (hv_fine),a
                ld (2090),a
                dec hl
                ex de,hl
                call hr_makecol
                ld a,$FF
                call hr_put
                call hr_dk
                jp hr_unmap
hr_dk:          ld a,(hv_dark)
                or a
                ret z
                ld a,1
                jp OVL_DARK             ; la linterna sigue a la camara (dark.asm)

; al FINAL de la vuelta del bucle principal: si la camara tiene que cruzar de columna, aqui se manda la orden del motor, se espera a que acabe (se ejecuta en
; la linea 254; la espera sustituye a la del VSYNC, que se haria igual) y se cierra el movimiento (fino a 0 o 7 y bufer de entrada) en seguida, con el haz
; fuera de la pantalla. Asi el movimiento de la memoria y el cambio del fino quedan pegados aunque la vuelta dure mas de un fotograma. hr_frame solo mueve
; el fino dentro de la columna.
hr_end:         ld a,(gf_have)
                or a
                ret z
                ld a,(hv_drawn)
                or a
                ret z
                ld a,(hv_pend)
                or a
                jp nz,hr_settle
                call gf_lpos
                push hl
                call gf_campx
                ex de,hl
                pop hl
                or a
                sbc hl,de               ; logica - hardware
                ret z
                jr c,he_right
                ld a,(hv_fine)
                cp 7
                ret nz
                ld a,1
                call hr_send
                jp hr_settle
he_right:       ld a,(hv_fine)
                or a
                ret nz
                ld a,2
                call hr_send
                jp hr_settle

; una vez por fotograma: la camara del hardware hacia la logica (hasta 8 pixeles)
hr_frame:       ld a,(gf_have)
                or a
                ret z
                ld a,(hv_drawn)
                or a
                ret z
                ld a,(hv_pend)
                or a
                call nz,hr_settle       ; (no deberia: hr_end ya lo ha cerrado al acabar el fotograma anterior)
hf_free:        call gf_lpos
                push hl
                call gf_campx
                ex de,hl
                pop hl
                or a
                sbc hl,de               ; logica - hardware
                ret z
                jr c,hf_right
                call hf_cnt
                ld a,(hv_fine)
hfl_l:          cp 7
                jr z,hfl_cmd
                inc a
                djnz hfl_l
                jr hf_set
hfl_cmd:        jr hf_set               ; en 7: cruzar de columna lo hace hr_end, al final de la vuelta
hf_right:       ld a,h
                cpl
                ld h,a
                ld a,l
                cpl
                ld l,a
                inc hl
                call hf_cnt
                ld a,(hv_fine)
hfr_l:          or a
                jr z,hfr_cmd
                dec a
                djnz hfr_l
                jr hf_set
hfr_cmd:        jr hf_set
hf_set:         ld (hv_fine),a
                ld (2090),a
                ret
hf_cnt:         ld a,h                  ; B = min(HL, 8)
                or a
                ld b,8
                ret nz
                ld a,l
                cp 8
                ret nc
                ld b,a
                ret

; ---------------------------------------------------------------------
;  La sala entera
; ---------------------------------------------------------------------
gf_draw_window: call hr_settle
                call hr_dclr            ; fase 10b: se dibuja todo: nada sucio
                xor a
                ld (hv_ch),a
                ld (hv_y0),a            ; fase 10c: las 128 lineas y la lista entera
                ld (hv_y1),a
                ld (hv_dlo),a
                ld (hv_nobg),a
                ld a,1
                ld (hv_drawn),a
                ld hl,(gf_cam)
                ld (hv_cam),hl
                ld a,(gf_fine)
                ld (hv_fine),a
                ld (2090),a
                xor a
                ld (gd_pending),a
                ld (hv_c),a
                call hr_mkdl
                ld hl,HR_NFLAGS
                ld de,HR_FLAGS
                ld bc,84
                ldir
dw_l:           ld a,(hv_c)
                ld e,a
                ld d,0
                ld hl,(hv_cam)
                add hl,de
                ex de,hl
                call hr_makecol
                ld a,(hv_c)
                call hr_put
                ld hl,hv_c
                inc (hl)
                ld a,(hl)
                cp 32
                jr c,dw_l
                ld hl,(hv_cam)
                ld de,32
                add hl,de
                ex de,hl
                call hr_makecol         ; el bufer de la derecha
                ld a,32
                call hr_put
                ld hl,(hv_cam)
                dec hl
                ex de,hl
                call hr_makecol         ; y el de la izquierda
                ld a,$FF
                call hr_put
                jp hr_unmap

; un objeto ha cambiado de estado: solo se vuelven a componer las columnas de los objetos cuyo "se dibuja" ha cambiado (y que estan en pantalla o en los bufers)
hr_objupd:      call hr_settle
                xor a
                ld (gd_pending),a
                call hr_mkdl
                xor a
                ld (hv_nr),a            ; fase 10c: ningun rectangulo recompuesto
                call ov_merge           ; fase 9: las columnas que ha tocado la capa de texto y cajas (txtlayer.asm), enteras (fase 10c: antes que los objetos, para no repetirlas)
                xor a
                ld (hv_i),a
hou_l:          ld a,(hv_i)
                ld hl,hv_nobj
                cp (hl)
                jr nc,hou_cmp
                cp 84
                jr nc,hou_cmp
                ld e,a
                ld d,0
                ld hl,HR_FLAGS
                add hl,de
                ld b,(hl)
                ld hl,HR_NFLAGS
                add hl,de
                ld a,(hl)
                cp b
                ld a,e
                call nz,hr_orect        ; ha cambiado: se recompone su rectangulo (fase 10c; en la 10b sus columnas enteras; antes un rango del minimo al maximo)
hou_n:          ld hl,hv_i
                inc (hl)
                jr hou_l
hou_cmp:        ld a,(hv_ch)
                or a
                jr z,hou_cp
                xor a
                ld (hv_ch),a
                ld (hv_c),a             ; 0 = bufer de la izquierda, 1-32 = columnas de pantalla 0-31, 33 = bufer de la derecha
hou_s:          ld a,(hv_c)
                ld e,a
                ld d,0
                ld hl,(hv_cam)
                add hl,de
                dec hl                  ; columna del mundo
                ld a,h
                or a
                jr nz,hou_sn
                ld c,l
                ld a,l
                call hr_dbit
                and (hl)
                jr z,hou_sn             ; no esta sucia
                ld e,c
                ld d,0
                call hr_makecol
                ld a,(hv_c)
                or a
                jr nz,hou_nl
                ld a,$FF
                jr hou_p
hou_nl:         dec a
hou_p:          call hr_put
hou_sn:         ld hl,hv_c
                inc (hl)
                ld a,(hl)
                cp 34
                jr c,hou_s
                call hr_dclr
hou_cp:         ld hl,HR_NFLAGS
                ld de,HR_FLAGS
                ld bc,84
                ldir
                jp hr_unmap

; fase 10c: A = objeto (indice desde 0, < hv_nobj) que ha cambiado: se recomponen ya sus columnas que estan en pantalla o en los bufers, pero solo las lineas
; que toca (redondeadas a 8), salvo las columnas sucias de la capa, que recompone enteras hr_objupd despues. Fuera de esas lineas no cambia nada.
hr_orect:       ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * objeto
                ld de,HR_OBJREC
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                and e
                inc a
                ret z                   ; sin imagen: no hay nada que redibujar
                ld c,(hl)               ; primera columna
                inc hl
                ld a,(hl)
                ld (hv_ol),a
                inc hl
                ld b,(hl)               ; columnas
                inc hl
                ld a,(hl)
                ld (hv_oh),a
                ld a,(hv_ytop)          ; recortado a la ventana entera
                ld (hv_wlo),a
                ld hl,hv_hh
                add a,(hl)
                ld (hv_whi),a
                push bc
                call hm_clip
                pop bc
                ret c
                ret z                   ; no se ve ninguna de sus lineas
                ld a,(hv_cd)
                ld e,a
                and $F8
                ld (hv_y0),a
                ld a,(hv_cl)
                add a,e
                add a,7
                and $F8
                neg
                add a,128
                ld (hv_y1),a
                ld a,b
                or a
                jr z,hor_z
                call hr_rdup            ; fase 10c: dentro de otro ya recompuesto (los dos estados de una animacion suelen ocupar el mismo sitio): nada
                jr z,hor_z
                push bc
                call hr_ofilt           ; solo los objetos que tocan el rectangulo
                pop bc
hor_l:          push bc
                call hr_orc
                pop bc
                inc c
                jr z,hor_e
                djnz hor_l
hor_e:          ld a,(hv_ndls)
                ld (hv_ndl),a
hor_z:          xor a
                ld (hv_y0),a
                ld (hv_y1),a
                ld (hv_dlo),a
                ld (hv_nobg),a
                ret
; C = columna, B = columnas, hv_y0 / hv_y1: Z si cabe en uno de los rectangulos de HR_RECTS; si no, NZ y se apunta (si hay sitio). Conserva BC
hr_rdup:        ld a,(hv_nr)
                or a
                jr z,hrd_add
                ld e,a
                ld hl,HR_RECTS
hrd_l:          ld a,(hl)
                cp c
                jr nz,hrd_n
                inc hl
                ld a,(hl)
                cp b
                jr nz,hrd_n1
                inc hl
                ld a,(hv_y0)
                cp (hl)
                jr c,hrd_n2             ; empieza mas arriba
                inc hl
                ld a,(hv_y1)
                cp (hl)
                jr c,hrd_n3             ; acaba mas abajo
                xor a
                ret
hrd_n:          inc hl
hrd_n1:         inc hl
hrd_n2:         inc hl
hrd_n3:         inc hl
                dec e
                jr nz,hrd_l
                ld a,(hv_nr)
hrd_add:        cp 32
                jr nc,hrd_x             ; lleno: no se apunta
                add a,a
                add a,a
                ld l,a
                ld h,HR_RECTS>>8        ; HR_RECTS acaba en $00
                ld (hl),c
                inc l
                ld (hl),b
                inc l
                ld a,(hv_y0)
                ld (hl),a
                inc l
                ld a,(hv_y1)
                ld (hl),a
                ld hl,hv_nr
                inc (hl)
hrd_x:          or 1
                ret
; C = primera columna, B = cuantas, lineas [hv_y0, 128 - hv_y1) de la ventana: los objetos de HR_DLIST que tocan ese rectangulo, en su orden, a
; HR_DLIST+128 (hv_dlo = 128, hv_ndl = 128 + cuantos; el de antes en hv_ndls). Asi hr_makecol no recorre en cada columna los que no la tocan
hr_ofilt:       xor a
                ld (hv_nobg),a
                ld a,c
                ld (hv_c),a             ; primera columna
                add a,b
                jr nc,hf_e
                ld a,$FF
hf_e:           ld (hv_s),a             ; la siguiente a la ultima
                ld a,(hv_ytop)
                ld hl,hv_y0
                add a,(hl)
                ld (hv_wlo),a           ; lineas de la sala (absolutas)
                ld a,128
                ld hl,hv_y1
                sub (hl)
                ld hl,hv_ytop
                add a,(hl)
                ld (hv_whi),a
                ld a,(hv_ndl)
                ld (hv_ndls),a
                cp 128
                ret nc                  ; (no cabe al lado: la lista entera)
                ld b,a
                ld a,128
                ld (hv_ndl),a
                ld (hv_dlo),a
                ld a,b
                or a
                ret z
                ld de,HR_DLIST
hf_l:           ld a,(de)
                push de
                push bc
                call hf_obj
                pop bc
                pop de
                inc e
                djnz hf_l
                ret
; A = objeto: si toca el rectangulo, al final de la lista filtrada
hf_obj:         ld hl,hv_nobj
                cp (hl)
                ret nc                  ; sin registro (hr_makecol se lo salta)
                ld c,a
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * objeto
                ld de,HR_OBJREC
                add hl,de
                ld a,(hl)
                inc hl
                and (hl)
                inc a
                ret z                   ; sin imagen
                inc hl
                ld e,(hl)               ; primera columna
                ld a,(hv_s)
                cp e
                ret c
                ret z                   ; empieza despues del rectangulo
                ld b,0                  ; B = 0 si cubre todo el rectangulo (cada lado que no lo cubre suma 1)
                ld a,(hv_c)
                cp e
                jr nc,hfv1
                inc b
hfv1:           inc hl
                ld d,(hl)               ; primera linea
                inc hl
                ld a,e
                add a,(hl)              ; + columnas
                jr c,hf_c1
                ld e,a
                ld a,(hv_c)
                cp e
                ret nc                  ; acaba antes del rectangulo
                ld a,(hv_s)
                cp e
                jr c,hf_c1
                jr z,hf_c1
                inc b
hf_c1:          inc hl
                ld a,(hv_whi)
                cp d
                ret c
                ret z                   ; empieza por debajo
                ld a,(hv_wlo)
                cp d
                jr nc,hfv2
                inc b
hfv2:           ld a,d
                add a,(hl)              ; + lineas
                ld e,a
                ld a,(hv_wlo)
                cp e
                ret nc                  ; acaba por encima
                ld a,(hv_whi)
                cp e
                jr c,hfv3
                jr z,hfv3
                inc b
hfv3:           ld a,b
                or a
                jr nz,hf_app
                ld a,128                ; lo tapa todo (los objetos son opacos): lo anterior de la lista y el fondo no se ven
                ld (hv_ndl),a
                ld a,1
                ld (hv_nobg),a
hf_app:         ld a,(hv_ndl)
                ld e,a
                ld d,HR_DLIST>>8        ; HR_DLIST acaba en $00
                ld a,c
                ld (de),a
                ld hl,hv_ndl
                inc (hl)
                ret
; C = columna del mundo: si esta en pantalla o en un bufer y no es sucia de la capa, se recompone (con hv_y0 / hv_y1)
hr_orc:         ld e,c
                ld d,0
                ld hl,(hv_cam)
                dec hl
                ex de,hl
                or a
                sbc hl,de               ; 0 = bufer de la izquierda, 1-32 = pantalla, 33 = bufer de la derecha
                ld a,h
                or a
                ret nz
                ld a,l
                cp 34
                ret nc
                ld b,a
                ld a,c
                call hr_dbit
                and (hl)
                ret nz                  ; sucia de la capa: entera, despues
                push bc
                ld e,c
                ld d,0
                call hr_makecol
                pop af                  ; A = B
                sub 1                   ; 0 -> $FF (bufer de la izquierda)
                jp hr_put

; fase 10b: columnas sucias (fase 10c: hr_omark, que marcaba las de un objeto, ya no hace falta). hr_dmark: C = primera, B = cuantas (0: nada). Pone hv_ch
hr_dmark:       ld a,b
                or a
                ret z
                ld a,1
                ld (hv_ch),a
hdm_l:          ld a,c
                call hr_dbit
                or (hl)
                ld (hl),a
                inc c
                ret z
                djnz hdm_l
                ret
; A = columna -> HL = su byte de HR_DIRTY, A = su bit (destruye E)
hr_dbit:        ld e,a
                rrca
                rrca
                rrca
                and $1F
                or HR_DIRTY&$FF
                ld l,a
                ld h,HR_DIRTY>>8
                ld a,e
                and 7
                ld e,a
                ld a,1
                ret z
hdb_l:          add a,a
                dec e
                jr nz,hdb_l
                ret
hr_dclr:        ld hl,HR_DIRTY
                ld b,32
                xor a
hdc_l:          ld (hl),a
                inc hl
                djnz hdc_l
                ret

; salto de la camara: HL = posicion en pixeles (se acota a la sala)
gf_jump:        ld a,l
                and 7
                ld c,a
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld de,(gf_npos)
                push hl
                or a
                sbc hl,de
                pop hl
                jr c,gj_ok
                ld h,d
                ld l,e
                ld c,0
gj_ok:          ld (gf_cam),hl
                ld a,c
                ld (gf_fine),a
                jp gf_draw_window

gd_sync:        defb 1
gd_pending:     defb 0                  ; hay que volver a dibujar la sala
gd_full:        defb 0                  ; 1: entera (cambio de luces); 0: solo los objetos que han cambiado
vs_extra:       defb 0
gf_flip:        ret

; una vez por fotograma: el redibujado pedido (cambio de objetos, luces) o el movimiento del hardware
gd_update:      ld a,(gf_have)
                or a
                ret z
                ld a,(hv_drawn)
                or a
                jp z,gf_draw_window     ; nadie ha movido la camara: se dibuja donde esta
                ld a,(gd_pending)
                or a
                ret z
                ld a,(gd_full)
                or a
                jp z,hr_objupd
                xor a
                ld (gd_full),a
                jp gf_draw_window       ; cambio de luces: todo

; camara logica (la de los scripts): los movimientos de gf_move_* no tocan el hardware
gf_move_right:  ld hl,(gf_cam)
                ld de,(gf_npos)
                or a
                sbc hl,de
                ret nc                  ; ya en la ultima posicion
                ld a,(gf_fine)
                inc a
                cp 8
                jr c,gmr_set
                ld hl,(gf_cam)
                inc hl
                ld (gf_cam),hl
                xor a
gmr_set:        ld (gf_fine),a
                ret

gf_move_left:   ld a,(gf_fine)
                or a
                jr z,gml_cam
                dec a
                ld (gf_fine),a
                ret
gml_cam:        ld hl,(gf_cam)
                ld a,h
                or l
                ret z
                dec hl
                ld (gf_cam),hl
                ld a,7
                ld (gf_fine),a
                ret

; posicion logica de la camara en pixeles -> HL
gf_lpos:        ld hl,(gf_cam)
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(gf_fine)
                ld e,a
                ld d,0
                add hl,de
                ret

; posicion de la camara DEL HARDWARE (la que se ve) en pixeles -> HL (la usan los personajes para colocar sus sprites)
gf_campx:       ld hl,(hv_cam)
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(hv_fine)
                ld e,a
                ld d,0
                add hl,de
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Paleta de 16 de la FPGA (POKE 2063 puntero, 2064 byte bajo {G, B}, 2066 byte alto {BRIGHT, R} y avanza, 2067 = 1 la activa; densidades 0-15): los 16 colores del EGA. El codigo
;  de Chroma de cada color del EGA es el mismo indice salvo el marron (6): el amarillo oscuro de Chroma no es el marron del EGA (170, 85, 0) y lfl2gfx.chroma_rgb ya
;  cuenta con esta paleta (como la 5b de v2, `ov_pal16` de V2/ENGINE/overlay.asm: la v3 la habia perdido). pal16_tab: lo, hi por color.
; ---------------------------------------------------------------------------------------------------------------------------------
hr_pal16:       xor a
                ld (2063),a
                ld hl,pal16_tab
                ld b,16
p16_l:          ld a,(hl)
                inc hl
                ld (2064),a
                ld a,(hl)
                inc hl
                ld (2066),a
                djnz p16_l
                ld a,1
                ld (2067),a
                ret

; la paleta de 16 segun _roomPalette y _shadowPalette: el pixel k de la imagen (el codigo de Chroma k = el color k del EGA) sale como el color SHADOWPAL[ROOMPAL[k]] del EGA.
; Los trajes usan los mismos 16 codigos: su color k sale igual que el del fondo (en ScummVM los trajes no pasan por _roomPalette; solo se nota si una sala remapea un color que
; tambien llevan los personajes)
hr_pal_apply:   xor a
                ld (2063),a
                ld b,16
                ld c,0
hpa_l:          ld e,c
                ld d,0
                ld hl,ROOMPAL
                add hl,de
                ld a,(hl)
                ld e,a
                ld hl,SHADOWPAL
                add hl,de
                ld a,(hl)               ; color del EGA
                add a,a                 ; 2 bytes por color en pal16_tab
                ld e,a
                ld hl,pal16_tab
                add hl,de
                ld a,(hl)
                ld (2064),a
                inc hl
                ld a,(hl)
                ld (2066),a             ; pal16[k] y el puntero avanza
                inc c
                djnz hpa_l
                ret

pal16_tab:      defb $00,$00,$0F,$00,$00,$0F,$0F,$0F,$F0,$00,$FF,$00,$70,$1F,$FF,$0F
                defb $00,$F0,$0F,$F0,$00,$FF,$0F,$FF,$F0,$F0,$FF,$F0,$F0,$FF,$FF,$FF
