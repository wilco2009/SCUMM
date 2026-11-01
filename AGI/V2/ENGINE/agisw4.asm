; =====================================================================
;  agisw4.asm - GFX4 (modo 160w, 4 bpp): rotulos anchos y add.to.pic por software (se incluye desde agie.asm, overlay A2, en lugar de agisw.asm)
;
;  Los mismos mosaicos de 8x8 con mascara y color por fila que usan los sprites por hardware (Nvvvl.SPR), pintados en la imagen de 160x168 a 4 bpp ($A000, 80 bytes
;  por linea, nibble alto a la izquierda) contra la prioridad de la imagen y de los add.to.pic anteriores (sw_prow: PROW). Mismo resultado que
;  Interp.render4(sw=True) de TOOLS/agi_vm.py.
;
;  add.to.pic (t_bake): se pinta en la pantalla y las lineas que toca pasan a las paginas de fondo limpio (PG_BGB: lineas 0-101, PG_BGA: 102-167).
;  Rotulos anchos (sw4_run, una vez por ciclo): si algo cambia (un rotulo cambia de celda, sitio o prioridad, aparece o desaparece, o se ha pintado un add.to.pic),
;  se devuelven a la pantalla los rectangulos que ocupaban (desde el fondo limpio) y se pintan todos otra vez, de menor a mayor prioridad.
;  El estado de cada rotulo (O_SDR bit 0, O_SVW...) y su rectangulo (S4R: byte de la izquierda, bytes, linea de arriba y de abajo) se guardan por objeto.
; =====================================================================

; La imagen que acaba de dibujarse (4 bpp, 13.440 bytes) pasa a las paginas de fondo; ningun rotulo esta puesto
t_bgsave:       ld a,PG_BGB
                call map_page
                ld hl,HR_BM
                ld de,LWIN
                ld bc,102*80
                ldir
                ld a,PG_BGA
                call map_page
                ld hl,HR_BM+102*80
                ld de,LWIN
                ld bc,PLANE4-102*80
                ldir
                call unmap_win
                jp s4_reset

s4_force:       defb 0                  ; 1 = recomponer los rotulos aunque no cambien (tras un add.to.pic)

; ---------------------------------------------------------------------
;  Un objeto IX (con cel_open ya hecho: cv_* puestos y la pagina del bucle mapeada): sus mosaicos a la imagen. Deja el rectangulo en s4_bx0, s4_nb, s4_y0, s4_y1.
; ---------------------------------------------------------------------
s4_draw:        ld a,(ix+O_Y)
                cp 168
                jr c,sd_a
                ld a,167
sd_a:           ld (s4_y1),a            ; linea de abajo (la y del objeto)
                ld a,(ix+O_Y)
                inc a
                ld d,a
                ld a,(cv_h)
                ld e,a
                ld a,d
                cp e
                jr c,sd_z
                sub e                   ; y - alto + 1
                jr sd_s
sd_z:           xor a
sd_s:           ld (s4_y0),a            ; linea de arriba (recortada)
                ld (s4_yc),a
                ld a,(ix+O_X)           ; byte de la izquierda y bytes que ocupa
                srl a
                ld (s4_bx0),a
                ld a,(ix+O_X)
                ld hl,cv_w
                add a,(hl)
                jr c,sd_xc
                dec a
                cp 160
                jr c,sd_xd
sd_xc:          ld a,159
sd_xd:          srl a
                ld hl,s4_bx0
                sub (hl)
                inc a
                ld (s4_nb),a
sd_row:         ld a,(s4_yc)            ; rel = linea - y + alto - 1
                sub (ix+O_Y)
                ld b,a
                ld a,(cv_h)
                dec a
                add a,b
                ld b,a
                and 7
                ld (s4_r),a
                ld a,b
                rrca
                rrca
                rrca
                and 31
                ld (s4_ty),a
                ld a,(s4_yc)            ; direccion de la linea: HR_BM + 80 * linea
                call s4_off
                ld de,HR_BM
                add hl,de
                ld (s4_rowp),hl
                ld a,(s4_yc)
                add a,8
                ld (sw_y),a
                call sw_prow            ; PROW = prioridad de la imagen (y de los add.to.pic anteriores) en esa linea
                ld iy,(cv_p)
                ld a,(cv_n)
                ld (s4_n),a
sd_t:           ld a,(s4_n)
                or a
                jp z,sd_rn
                dec a
                ld (s4_n),a
                ld a,(s4_ty)
                cp (iy+1)
                jr nz,sd_nt
                ld a,(s4_r)
                ld e,a
                ld d,0
                push iy
                pop hl
                add hl,de
                ld de,18
                add hl,de               ; mascara de la fila (+18)
                ld a,(hl)
                or a
                jr z,sd_nt
                ld (s4_m),a
                ld de,-8
                add hl,de
                ld a,(hl)               ; dato (+10)
                ld (s4_p),a
                add hl,de
                ld a,(hl)               ; color: tinta * 16 + papel (+2)
                ld (s4_c),a
                ld a,(iy+0)             ; x del primer pixel = x + tx * 8
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld l,(ix+O_X)
                ld h,0
                add hl,de
                ld (s4_x),hl
                call s4_px
sd_nt:          ld de,26
                add iy,de
                jr sd_t
sd_rn:          ld a,(s4_yc)
                ld hl,s4_y1
                cp (hl)
                ret nc
                inc a
                ld (s4_yc),a
                jp sd_row

; los 8 pixeles de una fila de mosaico: s4_x (x del primero), s4_m (mascara), s4_p (dato: 1 = tinta), s4_c (tinta * 16 + papel), prioridad del objeto IX contra PROW
s4_px:          ld b,$80
                ld c,0
s4_k:           ld a,(s4_m)
                and b
                jr z,s4_nk
                ld hl,(s4_x)
                ld e,c
                ld d,0
                add hl,de
                ld a,h
                or a
                jr nz,s4_nk
                ld a,l
                cp 160
                jr nc,s4_nk
                ld (s4_ax),a
                ld a,(sw_pv)
                or a
                jr z,s4_vis
                ld a,(s4_ax)
                ld l,a
                ld h,PROW>>8
                ld a,(ix+O_PRI)
                cp (hl)
                jr c,s4_nk              ; el fondo tiene mas prioridad: tapa el pixel
s4_vis:         ld a,(s4_p)
                and b
                ld a,(s4_c)
                jr z,s4_pp
                rrca
                rrca
                rrca
                rrca
s4_pp:          and 15
                ld (s4_col),a
                ld hl,(s4_rowp)
                ld a,(s4_ax)
                srl a
                ld e,a
                ld d,0
                add hl,de
                ld a,(s4_ax)
                and 1
                jr nz,s4_lo
                ld a,(hl)
                and $0F
                ld d,a
                ld a,(s4_col)
                rlca
                rlca
                rlca
                rlca
                or d
                ld (hl),a
                jr s4_nk
s4_lo:          ld a,(hl)
                and $F0
                ld d,a
                ld a,(s4_col)
                or d
                ld (hl),a
s4_nk:          inc c
                srl b
                ld a,c
                cp 8
                jr nz,s4_k
                ret

; A = linea -> HL = A * 80
s4_off:         push de
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                pop de
                ret

; A = objeto -> IX = OBJ + 32 * A
s4_ix:          ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,OBJ
                add hl,de
                push hl
                pop ix
                ret

; A = objeto -> HL = S4R + 4 * A
s4_sr:          ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,S4R
                add hl,de
                ret

; Las lineas s4_y0..s4_y1 y los bytes s4_bx0 .. + s4_nb: de las paginas de fondo limpio a la pantalla (s4_dir = 0) o de la pantalla al fondo (1)
s4_copy:        ld a,(s4_y0)
                ld (s4_k2),a
cp_l:           ld a,(s4_k2)
                ld b,PG_BGB
                cp 102
                jr c,cp_p
                sub 102
                ld b,PG_BGA
cp_p:           call s4_off
                ld a,(s4_bx0)
                ld e,a
                ld d,0
                add hl,de
                push hl
                ld a,b
                call map7
                pop hl
                ld de,$E000
                add hl,de               ; HL = el fondo
                push hl
                ld a,(s4_k2)
                call s4_off
                ld de,HR_BM
                add hl,de
                ld a,(s4_bx0)
                ld e,a
                ld d,0
                add hl,de
                ex de,hl                ; DE = la pantalla
                pop hl
                ld a,(s4_nb)
                ld c,a
                ld b,0
                ld a,(s4_dir)
                or a
                jr z,cp_d
                ex de,hl                ; de la pantalla (HL) al fondo (DE)
cp_d:           ldir
                ld hl,s4_k2
                inc (hl)
                ld a,(s4_y1)
                cp (hl)
                jr nc,cp_l
                jp map7_back

; IX = objeto -> A = 1 si ahora es un rotulo por software (anim y drawn, con imagen, y celda con mas de 6 mosaicos en una fila); si no, 0
s4_isw:         ld a,(ix+O_F1)
                and 3
                cp 3
                jr nz,s4_no
                ld a,(picvalid)
                or a
                jr z,s4_no
                call cel_open
                jr c,s4_no
                ld a,(cv_fl)
                ld c,a
                call unmap_win
                ld a,c
                and 1
                jr z,s4_no
                ld a,1
                ret
s4_no:          xor a
                ret

; los rotulos puestos vuelven a ser la imagen limpia
s4_restore_all: xor a
                ld (s4_i),a
ra_l:           ld a,(s4_i)
                call s4_ix
                bit 0,(ix+O_SDR)
                jr z,ra_n
                ld a,(s4_i)
                call s4_sr
                ld a,(hl)
                ld (s4_bx0),a
                inc hl
                ld a,(hl)
                ld (s4_nb),a
                inc hl
                ld a,(hl)
                ld (s4_y0),a
                inc hl
                ld a,(hl)
                ld (s4_y1),a
                xor a
                ld (s4_dir),a
                call s4_copy
                res 0,(ix+O_SDR)
ra_n:           ld hl,s4_i
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,ra_l
                ret

; con una imagen nueva (OVE_BGSAVE) no hay rotulos puestos
s4_reset:       ld ix,OBJ
                ld de,32
                ld b,NOBJ
rs_l:           ld (ix+O_SDR),0
                add ix,de
                djnz rs_l
                xor a
                ld (s4_force),a
                ret

; una vez por ciclo, tras el orden de los objetos (hq_cnt, ORD ya copiados)
sw4_run:        xor a
                ld (s4_chg),a
                ld (s4_i),a
p1_l:           ld a,(s4_i)
                call s4_ix
                call s4_isw
                or a
                jr z,p1_ns
                bit 0,(ix+O_SDR)
                jr z,p1_c
                ld a,(ix+O_VIEW)
                cp (ix+O_SVW)
                jr nz,p1_c
                ld a,(ix+O_LOOP)
                cp (ix+O_SLP)
                jr nz,p1_c
                ld a,(ix+O_CEL)
                cp (ix+O_SCL)
                jr nz,p1_c
                ld a,(ix+O_X)
                cp (ix+O_SX)
                jr nz,p1_c
                ld a,(ix+O_Y)
                cp (ix+O_SY)
                jr nz,p1_c
                ld a,(ix+O_PRI)
                cp (ix+O_SPR)
                jr z,p1_nx
p1_c:           ld a,1
                ld (s4_chg),a
                jr p1_nx
p1_ns:          bit 0,(ix+O_SDR)        ; ya no es un rotulo: hay que quitarlo
                jr nz,p1_c
p1_nx:          ld hl,s4_i
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,p1_l
                ld a,(s4_force)
                ld hl,s4_chg
                or (hl)
                ret z
                xor a
                ld (s4_force),a
                call s4_restore_all
                xor a
                ld (s4_k3),a
d1_l:           ld a,(hq_cnt)
                ld hl,s4_k3
                cp (hl)
                ret z
                ret c
                ld e,(hl)
                ld d,0
                ld hl,ORD
                add hl,de
                ld a,(hl)
                ld (s4_i),a
                call s4_ix
                call s4_isw
                or a
                jr z,d1_n
                call cel_open
                jr c,d1_n
                call s4_draw
                call unmap_win
                set 0,(ix+O_SDR)
                ld a,(ix+O_VIEW)
                ld (ix+O_SVW),a
                ld a,(ix+O_LOOP)
                ld (ix+O_SLP),a
                ld a,(ix+O_CEL)
                ld (ix+O_SCL),a
                ld a,(ix+O_X)
                ld (ix+O_SX),a
                ld a,(ix+O_Y)
                ld (ix+O_SY),a
                ld a,(ix+O_PRI)
                ld (ix+O_SPR),a
                ld a,(s4_i)
                call s4_sr
                ld a,(s4_bx0)
                ld (hl),a
                inc hl
                ld a,(s4_nb)
                ld (hl),a
                inc hl
                ld a,(s4_y0)
                ld (hl),a
                inc hl
                ld a,(s4_y1)
                ld (hl),a
d1_n:           ld hl,s4_k3
                inc (hl)
                jr d1_l

; add.to.pic: SCR (una copia en BKO, con la pagina de su bucle en bk_pg) a la pantalla y al fondo limpio; los rotulos se recomponen despues (s4_force)
t_bake:         ld a,PG_OVL
                call map7
                ld hl,$E000+SCR-$2000
                ld de,BKO
                ld bc,33
                ldir
                call map7_back
                ld a,(bk_pg)
                cp $FF
                ret z
                ld a,1
                ld (bk_on),a
                ld (s4_force),a
                call s4_restore_all
                ld ix,BKO
                call cel_open
                jr c,bk_end
                call s4_draw
                call unmap_win
                ld a,1
                ld (s4_dir),a
                call s4_copy
bk_end:         xor a
                ld (bk_on),a
                ret

; Los rangos de los objetos fijos (add.to.pic) en la fila sw_py -> PROW (el maximo con lo que hubiera), como pd_patch (agihws.asm): sus datos, en la pagina del A1
; (SPH_FIX, SPN_FIX); PG_PRI2 esta en el bloque 7: se cambia por la del A1 un momento
sw_patch:       ld a,PG_OVL
                call map7
                ld a,($E000+SPN_FIX-$2000)
                or a
                jr z,swp_e
                push iy
                ld b,a
                ld iy,$E000+SPH_FIX-$2000
swp_l:          push bc
                ld a,(sw_py)
                ld l,a
                ld h,0
                ld e,(iy+0)
                ld d,(iy+1)
                or a
                sbc hl,de               ; fila - fila 0 de la celda
                bit 7,h
                jr nz,swp_n
                ld a,h
                or a
                jr nz,swp_n
                ld a,l
                cp (iy+2)
                jr nc,swp_n
                ld l,a
                ld h,0
                add hl,hl
                ld e,(iy+4)
                ld d,(iy+5)
                add hl,de               ; los pares estan en esta pagina (SPP)
                ld a,(hl)               ; ax0
                inc hl
                ld c,a
                ld a,(hl)               ; ax1
                cp c
                jr c,swp_n              ; vacio
                sub c
                inc a
                ld b,a
                ld e,c
                ld d,0
                ld hl,PROW
                add hl,de
                ld d,(iy+3)             ; prioridad
swp_f:          ld a,(hl)
                cp d
                jr nc,swp_k
                ld (hl),d
swp_k:          inc hl
                djnz swp_f
swp_n:          pop bc
                ld de,8
                add iy,de
                djnz swp_l
                pop iy
swp_e:          ld a,PG_PRI2
                jp map7

; La prioridad de la imagen en la linea sw_y (de pantalla: la de imagen + 8) -> PROW (sw_pv = 1), si hay imagen
sw_prow:        xor a
                ld (sw_pv),a
                ld a,(picvalid)
                or a
                ret z
                ld a,(sw_y)
                sub 8
                ret c
                cp 168
                ret nc
                ld e,a
                ld a,160
                ld (hw_plim),a
                ld a,PG_PRI2
                call map7
                ld a,e
                ld (sw_py),a
                call pd_row
                call sw_patch
                call map7_back
                ld a,1
                ld (sw_pv),a
                ret

s4_chg:         defb 0
s4_i:           defb 0
s4_k2:          defb 0
s4_k3:          defb 0
s4_dir:         defb 0
s4_bx0:         defb 0
s4_nb:          defb 0
s4_y0:          defb 0
s4_y1:          defb 0
s4_yc:          defb 0
s4_r:           defb 0
s4_ty:          defb 0
s4_n:           defb 0
s4_m:           defb 0
s4_p:           defb 0
s4_c:           defb 0
s4_col:         defb 0
s4_ax:          defb 0
s4_x:           defw 0
s4_rowp:        defw 0
sw_y:           defb 0
sw_pv:          defb 0
sw_py:          defb 0
S4R:            defs 4*NOBJ
BKO:            defs 32                 ; copia de SCR (A1) y la pagina de su bucle: el add.to.pic que se pinta
bk_pg:          defb 0
bk_on:          defb 0
