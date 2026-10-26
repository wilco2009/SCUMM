; =====================================================================
;  hr.asm - video HiRes 8x1 de 16 colores (rama hires16). Plan: claude/planning/scumm_hires16.md
;
;  Lo que se ve esta siempre en el mapa del Z80: bitmap HR_BM (6 KB, linea y * 32 + columna), atributos HR_ATT (6 KB, un byte por byte de
;  linea: papel en el nibble alto, tinta en el bajo) y los bufers de entrada del scroll por hardware (derecha / izquierda, un byte por linea).
;  La sala entera (ROOMnn.GFX, hecho por TOOLS/lfl2hr.py) esta en las paginas fisicas ROOMPG0.. y se asoma por la ventana de datos
;  (bloque WINBLK) solo mientras se copia un trozo; despues se restaura la pagina que habia (WINPG, vm_core.asm).
;
;  Formato del .GFX: ver lfl2hr.py. La columna k de la sala esta en el desplazamiento 256 * (k + 1): 32 columnas por pagina de 8 KB.
;
;  Camara: gf_cam / gf_fine son la posicion LOGICA (la que piden los scripts, gf_move_*); hv_cam / hv_fine, la del hardware. hr_frame (una vez
;  por fotograma) acerca la del hardware a la logica: el fino por POKE 2090 y, al pasar de columna, la orden del motor de scroll
;  (puerto $3FEF), que mueve la memoria un byte en el borrado; cuando acaba se rellena el bufer de entrada que toca.
;  Invariante: el bufer de la izquierda tiene la columna hv_cam - 1 y el de la derecha la hv_cam + 32.
; =====================================================================
HR_BM           equ $A000
HR_RBM          equ HR_BM+$1800         ; entrada derecha (bitmap): un byte por linea
HR_LBM          equ HR_BM+$1C00         ; entrada izquierda
HR_ATT          equ $C000
HR_RATT         equ $D800
HR_LATT         equ $DC00
HR_OBJREC       equ HR_BM+$1A07         ; 6 bytes por objeto (hasta 84): desplazamiento (2), columna, linea, columnas, lineas; sitio libre del bloque del bitmap
HR_DLIST        equ HR_BM+$1E00         ; indices de los objetos que se dibujan, del ultimo al primero
HR_COLBUF       equ HR_BM+$1F00         ; la columna que se compone: 128 bytes de bitmap y 128 de atributos
HR_FLAGS        equ HR_ATT+$1A07        ; un byte por objeto (hasta 84): 1 si se dibujaba la ultima vez (sitio libre del bloque de atributos)
HR_NFLAGS       equ HR_ATT+$1B00        ; lo mismo, con el estado de ahora
ROOMPG0         equ 8                   ; paginas fisicas de la sala (8-13)
ROOMMAX         equ 6*8192
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
hv_c0            equ HV+32               ; columnas (minima y maxima) de los objetos que han cambiado
hv_c1            equ HV+33
hv_ch            equ HV+34
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
hr_makecol:     ld (hv_w),de
                ld hl,(gf_cols)
                or a
                sbc hl,de
                jp z,hm_zero
                jp c,hm_zero
                ld hl,(hv_w)
                inc hl
                ld h,l
                ld l,0                  ; desplazamiento = (columna + 1) * 256
                ld de,HR_COLBUF
                ld bc,256
                call hr_fcopy
                xor a
                ld (hv_j),a
hm_o:           ld a,(hv_ndl)
                ld b,a
                ld a,(hv_j)
                cp b
                ret nc
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
                ld b,a
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
                ld e,a
                ld d,0
                ld hl,HR_COLBUF
                add hl,de
                ex de,hl
                ld a,(hv_oh)
                ld c,a
                ld b,0
                ld hl,(hv_so)
                call hr_fcopy
                ld a,(hv_oh)
                ld e,a
                ld d,0
                ld hl,(hv_so)
                add hl,de               ; y detras, sus atributos
                push hl
                ld a,(hv_ol)
                ld e,a
                ld d,0
                ld hl,HR_COLBUF+128
                add hl,de
                ex de,hl
                ld a,(hv_oh)
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

; HL = origen (128 bytes), DE = destino: uno por linea (paso 32)
hr_stride:      ld c,16
hs_g:           ld b,8
hs_l:           ld a,(hl)
                inc hl
                ld (de),a
                ld a,e
                add a,32
                ld e,a
                djnz hs_l
                inc d
                dec c
                jr nz,hs_g
                ret

; HR_COLBUF a la columna de pantalla A (0-31), al bufer de la derecha (32) o al de la izquierda ($FF)
hr_put:         ld (hv_s),a
                cp 32
                jr z,hp_r
                cp $FF
                jr z,hp_l
                ld e,a
                ld d,HR_BM>>8
                ld hl,HR_COLBUF
                call hr_stride
                ld a,(hv_s)
                ld e,a
                ld d,HR_ATT>>8
                ld hl,HR_COLBUF+128
                jp hr_stride
hp_r:           ld hl,HR_COLBUF
                ld de,HR_RBM
                ld bc,128
                ldir
                ld hl,HR_COLBUF+128
                ld de,HR_RATT
                ld bc,128
                ldir
                ret
hp_l:           ld hl,HR_COLBUF
                ld de,HR_LBM
                ld bc,128
                ldir
                ld hl,HR_COLBUF+128
                ld de,HR_LATT
                ld bc,128
                ldir
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
                ld a,(NOBJS)
                ld (hv_i),a
hd_l:           ld a,(hv_i)
                or a
                ret z
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
hd_nf:          ld a,(hv_ndl)
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
hr_init:        xor a
                ld (2043),a
                ld a,HR_BM>>8
                ld (2044),a             ; HFILE = bitmap
                ld a,171
                ld (2045),a             ; Superfast HiRes nativo
                xor a
                ld (hv_pend),a
                ld (hv_ndl),a
                ld (hv_nobj),a
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
                ld hl,(PF_OPEN)         ; los objetos que el perfil da por abiertos (getState, vm_core.asm) se dibujan abiertos desde que se carga la sala
                call gl_open
                ld hl,(PF_OPEN+2)
                call gl_open
                ld hl,160               ; camara: seguir al protagonista, desde el centro
                ld (cam_cx),hl
                ld a,2
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
                ld a,1
                ld (cam_new),a
                ld a,4                  ; los personajes no vuelven a aparecer hasta saber donde van (y la camara ya esta en su sitio)
                ld (ac_hold),a
                call sc_hide_sprites
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
                ld a,(UI_DIRTY)         ; la pantalla se ha borrado entera: la interfaz se vuelve a dibujar
                or 7
                ld (UI_DIRTY),a
                ld a,(gf_room)
                or a
                ret z                   ; sala 0: no hay imagen
                call gf_read
                ret c
                call hr_parse
                ret c
                ld a,1                  ; la sala se dibuja cuando la camara sepa donde esta (cm_snap), no antes en la posicion 0
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
                jp hr_unmap

; al final de la vuelta del bucle principal: si hay una orden del motor, se espera a que acabe (se ejecuta en la linea 254, y el borrado
; vertical sigue ~7 ms) y se cierra el movimiento (fino a 0 o 7 y bufer de entrada) en seguida, con el haz todavia fuera de la pantalla. Si se
; cerrara al principio del fotograma siguiente, una vuelta que dura mas de un fotograma dejaria ver la memoria movida con el fino viejo (salto de 8 px)
hr_end:         ld a,(hv_pend)
                or a
                ret z
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
hfl_cmd:        ld (hv_fine),a
                ld (2090),a
                ld a,1
                jp hr_send
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
hfr_cmd:        ld (hv_fine),a
                ld (2090),a
                ld a,2
                jp hr_send
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
                ld (hv_i),a
                ld (hv_ch),a
                ld (hv_c1),a
                dec a
                ld (hv_c0),a
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
                jr z,hou_n              ; sigue igual
                ld h,d
                ld l,e
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
                jr z,hou_n              ; sin imagen: no hay nada que redibujar
                ld a,1
                ld (hv_ch),a
                ld a,(hl)               ; primera columna
                ld c,a
                inc hl
                inc hl
                ld b,(hl)               ; columnas
                ld hl,hv_c0
                cp (hl)
                jr nc,hou_a
                ld (hl),a
hou_a:          ld a,c
                add a,b
                dec a                   ; ultima columna
                ld hl,hv_c1
                cp (hl)
                jr c,hou_n
                jr z,hou_n
                ld (hl),a
hou_n:          ld hl,hv_i
                inc (hl)
                jr hou_l
hou_cmp:        ld a,(hv_ch)
                or a
                jr z,hou_cp
                xor a
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
                ld hl,hv_c0
                ld a,c
                cp (hl)
                jr c,hou_sn
                ld a,(hv_c1)
                cp c
                jr c,hou_sn
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
hou_cp:         ld hl,HR_NFLAGS
                ld de,HR_FLAGS
                ld bc,84
                ldir
                jp hr_unmap

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
                jp hr_objupd

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
