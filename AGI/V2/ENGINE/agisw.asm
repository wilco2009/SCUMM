; =====================================================================
;  agisw.asm - rotulos anchos al bitmap (se incluye desde agitxt.asm, es parte del overlay)
;
;  Una celda con mas de 6 mosaicos en una fila (los rotulos de las introducciones: hasta 23) no cabe en los sprites (12 por linea): se dibuja en el bitmap.
;  Su borde izquierdo esta en el pixel HiRes lo(x) = 8*cx0 + s; cada fila de cada mosaico aporta a la celda cx0 + tx la parte desplazada s a la derecha y, si s > 0,
;  a la siguiente la que se sale. Una parte con las 8 posiciones opacas escribe el bitmap y el atributo de la celda tal cual; si no, pone sus pixeles uno a uno
;  con `plot`. Mismo resultado que Interp.sw_blit() de TOOLS/agi_vm.py (objetos de menor a mayor prioridad, mosaicos en orden).
;
;  Se compone por LINEAS: cada linea de la zona que cambia se arma en un bufer (LBBM / LBAT) a partir de la copia limpia de la imagen (paginas PG_BGB / PG_BGA,
;  que se leen por el bloque 7) y de todos los rotulos que la tocan, y se escribe en la pantalla de una vez: nunca se ve la zona borrada. Cambia lo que
;  cambia un rotulo (otra celda, forma, sitio, aparece o desaparece, o se escribe texto en la imagen) mas lo que se le solapa. Un rotulo que cambia solo de
;  colores se recompone igual (no se borra nada, asi que se ve como un recoloreado).
;  El estado de cada rotulo esta en los bytes 23-31 de su registro de objeto (O_SDR...); SWR (16 bytes por objeto) lleva sus rectangulos de celdas (cx0, nb, y0, y1;
;  el de antes y el de ahora) y lo que toca hacer.
; =====================================================================

O_SDR           equ 23                  ; bit 0: esta puesto en el bitmap
O_SVW           equ 24                  ; vista, bucle, celda, x, y, prioridad y huella con los que se puso
O_SLP           equ 25
O_SCL           equ 26
O_SX            equ 27
O_SY            equ 28
O_SPR           equ 29
O_SHL           equ 30
O_SHH           equ 31

; La imagen que acaba de dibujarse (en la pantalla) pasa a las paginas de fondo; ningun rotulo esta puesto
t_bgsave:       ld a,PG_BGB
                call map_page
                ld hl,HR_BM+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                ld a,PG_BGA
                call map_page
                ld hl,HR_ATT+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                call unmap_win
                ld ix,OBJ
                ld de,32
                ld b,NOBJ
sqb_l:          ld (ix+O_SDR),0
                add ix,de
                djnz sqb_l
                ld hl,SWR
                ld de,SWR+1
                ld bc,16*NOBJ-1
                ld (hl),0
                ldir
                xor a
                ld (sw_force),a
                ret

; A = objeto -> HL = SWR + 16 * A
swr_ptr:        ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SWR
                add hl,de
                ret

; ---------------------------------------------------------------------
;  Que hay que hacer con cada objeto: SWR+8 = 0 nada, 1 recomponer, 3 quitarlo; SWR+9 = es un rotulo ahora; SWR+10/11 = su huella
; ---------------------------------------------------------------------
sw_scan:        xor a
                ld (sqs_n),a
                ld ix,OBJ
sqs_l:          ld a,(sqs_n)
                call swr_ptr
                ld (sqs_r),hl
                ld de,5
                add hl,de
                ld (hl),0               ; rectangulo nuevo vacio
                ld de,3
                add hl,de
                ld (hl),0               ; que hacer
                inc hl
                ld (hl),0               ; es rotulo ahora
                ld a,(ix+O_F1)
                and 3
                cp 3
                jp nz,sqs_nd
                ld a,(picvalid)
                or a
                jp z,sqs_nd
                call cel_open
                jp c,sqs_nd
                ld a,(cv_fl)
                ld c,a
                call unmap_win
                ld a,c
                and 1
                jp z,sqs_nd
                ld hl,(sqs_r)
                ld de,9
                add hl,de
                ld (hl),1
                inc hl
                ld a,(cv_hl)
                ld (hl),a
                inc hl
                ld a,(cv_hh)
                ld (hl),a
                call sw_geom
                ld hl,(sqs_r)
                ld de,8
                add hl,de
                bit 0,(ix+O_SDR)
                jr z,sqs_ch
                ld a,(ix+O_VIEW)
                cp (ix+O_SVW)
                jr nz,sqs_ch
                ld a,(ix+O_LOOP)
                cp (ix+O_SLP)
                jr nz,sqs_ch
                ld a,(ix+O_X)
                cp (ix+O_SX)
                jr nz,sqs_ch
                ld a,(ix+O_Y)
                cp (ix+O_SY)
                jr nz,sqs_ch
                ld a,(ix+O_PRI)
                cp (ix+O_SPR)
                jr nz,sqs_ch
                ld a,(ix+O_CEL)
                cp (ix+O_SCL)
                jr nz,sqs_ch
                ld a,(cv_hl)
                cp (ix+O_SHL)
                jr nz,sqs_ch
                ld a,(cv_hh)
                cp (ix+O_SHH)
                jr z,sqs_nx             ; nada cambio
sqs_ch:         ld (hl),1
                jr sqs_nx
sqs_nd:         bit 0,(ix+O_SDR)       ; ya no es un rotulo: si estaba puesto, hay que quitarlo
                jr z,sqs_nx
                ld hl,(sqs_r)
                ld de,8
                add hl,de
                ld (hl),3
sqs_nx:         ld de,32
                add ix,de
                ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jp c,sqs_l
                ret

; Rectangulo de celdas y lineas nuevo del objeto IX (sqs_r = su SWR; cv_w, cv_h de su celda): SWR+4..7
sw_geom:        ld a,(ix+O_X)
                call lo16
                ld a,l
                and 7
                ld (sg_s),a
                ld a,l
                rrca
                rrca
                rrca
                and 31
                ld (sg_cx),a
                ld a,(cv_w)             ; celdas que ocupa: (s + ancho + 7) / 8
                ld l,a
                ld h,0
                ld a,(sg_s)
                ld e,a
                ld d,0
                add hl,de
                ld de,7
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld b,l
                ld a,32
                ld hl,sg_cx
                sub (hl)
                jr c,sg_n0
                jr z,sg_n0
                cp b
                jr c,sg_nk
                ld a,b
sg_nk:          ld (sg_nb),a
                jr sg_ny
sg_n0:          xor a
                ld (sg_nb),a
sg_ny:          ld l,(ix+O_Y)           ; lineas: top = y - h + 9 ... top + h - 1, entre 8 y 175
                ld h,0
                ld a,(cv_h)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld de,9
                add hl,de
                ld (sg_top),hl
                ld a,(cv_h)
                ld e,a
                ld d,0
                add hl,de
                dec hl
                bit 7,h
                jr nz,sg_empty
                ld a,h
                or a
                jr nz,sg_y1c
                ld a,l
                cp 8
                jr c,sg_empty
                cp 176
                jr c,sg_y1
sg_y1c:         ld a,175
sg_y1:          ld (sg_y1v),a
                ld hl,(sg_top)
                bit 7,h
                jr nz,sg_y0l
                ld a,h
                or a
                jr nz,sg_empty
                ld a,l
                cp 176
                jr nc,sg_empty
                cp 8
                jr nc,sg_y0
sg_y0l:         ld a,8
sg_y0:          ld (sg_y0v),a
                jr sg_st
sg_empty:       xor a
                ld (sg_nb),a
                ld (sg_y0v),a
                ld (sg_y1v),a
sg_st:          ld hl,(sqs_r)
                ld de,4
                add hl,de
                ld a,(sg_cx)
                ld (hl),a
                inc hl
                ld a,(sg_nb)
                ld (hl),a
                inc hl
                ld a,(sg_y0v)
                ld (hl),a
                inc hl
                ld a,(sg_y1v)
                ld (hl),a
                ret

; HL = rectangulo A, DE = rectangulo B (cx0, nb, y0, y1) -> C si se solapan (y los dos tienen celdas)
ri_chk:         inc hl
                ld a,(hl)
                dec hl
                or a
                jr z,ri_no
                inc de
                ld a,(de)
                dec de
                or a
                jr z,ri_no
                push hl
                push de
                ld a,(de)
                inc de
                ld b,a
                ld a,(de)
                add a,b
                ld c,a
                ld a,(hl)
                cp c
                jr nc,ri_np
                ld a,(hl)
                inc hl
                ld c,a
                ld a,(hl)
                add a,c
                cp b
                jr c,ri_np
                jr z,ri_np
                inc hl
                inc de
                ld a,(hl)
                ld c,a
                inc de
                ld a,(de)
                cp c
                jr c,ri_np
                dec de
                ld a,(de)
                ld c,a
                inc hl
                ld a,(hl)
                cp c
                jr c,ri_np
                pop de
                pop hl
                scf
                ret
ri_np:          pop de
                pop hl
ri_no:          or a
                ret

; Los rotulos que se solapan con uno que cambia tambien se recomponen
sw_close:       ld a,(sw_force)
                or a
                jr z,sq_run
                xor a
                ld (sqs_n),a
sq_f:           ld a,(sqs_n)
                call swr_ptr
                ld de,9
                add hl,de
                ld a,(hl)               ; es rotulo ahora
                or a
                jr z,sq_fn
                dec hl
                ld (hl),1
sq_fn:          ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sq_f
sq_run:         xor a
                ld (sq_chg),a
                ld (sq_i),a
sq_i1:          ld a,(sq_i)
                call swr_ptr
                ld (sq_ri),hl
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr z,sq_in
                xor a
                ld (sq_j),a
sq_j1:          ld a,(sq_j)
                call swr_ptr
                ld (sq_rj),hl
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr nz,sq_jn             ; ya se recompone
                inc hl
                ld a,(hl)
                or a
                jr z,sq_jn              ; no es un rotulo
                ld hl,(sq_rj)
                ld de,4
                add hl,de               ; su rectangulo (el nuevo es el de antes)
                ld de,(sq_ri)
                call ri_chk             ; contra el rectangulo de antes del que cambia
                jr c,sq_hit
                ld hl,(sq_rj)
                ld de,4
                add hl,de
                ld de,(sq_ri)
                inc de
                inc de
                inc de
                inc de                  ; y contra su rectangulo nuevo
                call ri_chk
                jr nc,sq_jn
sq_hit:         ld hl,(sq_rj)
                ld de,8
                add hl,de
                ld (hl),1
                ld a,1
                ld (sq_chg),a
sq_jn:          ld hl,sq_j
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sq_j1
sq_in:          ld hl,sq_i
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sq_i1
                ld a,(sq_chg)
                or a
                jr nz,sq_run
                ret

; ---------------------------------------------------------------------
;  Recomponer
; ---------------------------------------------------------------------
sw_comp:        xor a                   ; rango de lineas de lo que se recompone
                ld (sc_nl),a
                ld (sc_yv),a
                ld (sqs_n),a
sc_y:           ld a,(sqs_n)
                call swr_ptr
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr z,sc_yn
                ld a,(sqs_n)
                call swr_ptr
                call sc_yr              ; rectangulo de antes
                ld a,(sqs_n)
                call swr_ptr
                ld de,4
                add hl,de
                call sc_yr              ; rectangulo nuevo
sc_yn:          ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sc_y
                ld a,(sc_yv)
                or a
                ret z
                xor a                   ; los que se recomponen, en el orden de ORD (prioridad, y, numero)
                ld (sc_k),a
sc_o:           ld a,(sc_k)
                ld hl,hq_cnt
                cp (hl)
                jr nc,sc_ld
                ld e,a
                ld d,0
                ld hl,ORD
                add hl,de
                ld a,(hl)
                ld (sqs_n),a
                call swr_ptr
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr z,sc_on
                inc hl
                ld a,(hl)
                or a
                jr z,sc_on
                ld a,(sc_nl)
                ld e,a
                ld d,0
                ld hl,SWL
                add hl,de
                ld a,(sqs_n)
                ld (hl),a
                ld hl,sc_nl
                inc (hl)
sc_on:          ld hl,sc_k
                inc (hl)
                jr sc_o
sc_ld:
                ld a,(sc_ymin)          ; linea a linea
                ld (sw_y),a
sc_l:           call t_kpoll
                call sw_span
                ld a,(sp_lo)
                ld hl,sp_hi
                cp (hl)
                jr z,sc_do
                jr nc,sc_ln             ; nadie toca esta linea
sc_do:          call lb_load
                xor a
                ld (sc_k),a
sc_k1:          ld a,(sc_k)
                ld hl,sc_nl
                cp (hl)
                jr nc,sc_fl
                ld e,a
                ld d,0
                ld hl,SWL
                add hl,de
                ld a,(hl)
                ld (sa_n),a
                call swr_ptr
                ld de,4
                add hl,de               ; rectangulo nuevo
                call sc_cov
                jr nc,sc_kn
                ld a,(sa_n)
                call sw_apply
sc_kn:          ld hl,sc_k
                inc (hl)
                jr sc_k1
sc_fl:          call lb_flush
sc_ln:          ld a,(sw_y)
                ld hl,sc_ymax
                cp (hl)
                jr nc,sc_fin
                inc a
                ld (sw_y),a
                jr sc_l
sc_fin:         xor a                   ; estado de los que se han recompuesto
                ld (sqs_n),a
                ld ix,OBJ
sc_s:           ld a,(sqs_n)
                call swr_ptr
                ld (sqs_r),hl
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr z,sc_sn
                cp 3
                jr nz,sc_on1
                ld (ix+O_SDR),0
                ld hl,(sqs_r)
                xor a
                ld (hl),a
                inc hl
                ld (hl),a               ; ya no hay rectangulo puesto
                jr sc_sn
sc_on1:         ld (ix+O_SDR),1
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
                ld hl,(sqs_r)
                ld de,10
                add hl,de
                ld a,(hl)
                ld (ix+O_SHL),a
                inc hl
                ld a,(hl)
                ld (ix+O_SHH),a
                ld hl,(sqs_r)           ; el rectangulo de ahora pasa a ser el puesto
                ld d,h
                ld e,l
                ld bc,4
                add hl,bc
                ex de,hl
                ex de,hl
                ld bc,4
                ldir
sc_sn:          ld de,32
                add ix,de
                ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sc_s
                xor a
                ld (sw_force),a
                ret

; HL = rectangulo (cx0, nb, y0, y1): amplia el rango de lineas
sc_yr:          inc hl
                ld a,(hl)
                dec hl
                or a
                ret z
                inc hl
                inc hl
                ld a,(hl)               ; y0
                ld b,a
                inc hl
                ld a,(hl)               ; y1
                ld c,a
                ld a,(sc_yv)
                or a
                jr nz,sc_ye
                ld a,1
                ld (sc_yv),a
                ld a,b
                ld (sc_ymin),a
                ld a,c
                ld (sc_ymax),a
                ret
sc_ye:          ld a,(sc_ymin)
                cp b
                jr c,sc_y2
                ld a,b
                ld (sc_ymin),a
sc_y2:          ld a,(sc_ymax)
                cp c
                ret nc
                ld a,c
                ld (sc_ymax),a
                ret

; HL = rectangulo -> C si cubre la linea sw_y
sc_cov:         inc hl
                ld a,(hl)
                or a
                jr z,sc_cn
                inc hl
                ld a,(sw_y)
                cp (hl)
                jr c,sc_cn
                inc hl
                ld a,(hl)
                ld hl,sw_y
                cp (hl)
                jr c,sc_cn
                scf
                ret
sc_cn:          or a
                ret

; Celdas que hay que componer en la linea sw_y: sp_lo..sp_hi (sp_lo > sp_hi si ninguna)
sw_span:        ld a,255
                ld (sp_lo),a
                xor a
                ld (sp_hi),a
                ld (sqs_n),a
sp_o:           ld a,(sqs_n)
                call swr_ptr
                ld (sp_r),hl
                ld de,8
                add hl,de
                ld a,(hl)
                or a
                jr z,sp_on
                ld hl,(sp_r)
                call sp_one
                ld hl,(sp_r)
                ld de,4
                add hl,de
                call sp_one
sp_on:          ld hl,sqs_n
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,sp_o
                ret
sp_one:         push hl
                call sc_cov
                pop hl
                ret nc
                ld a,(hl)
                ld c,a                  ; cx0
                inc hl
                ld a,(hl)
                add a,c
                dec a                   ; ultima celda
                ld b,a
                ld a,(sp_lo)
                cp c
                jr c,sp_a
                ld a,c
                ld (sp_lo),a
sp_a:           ld a,(sp_hi)
                cp b
                ret nc
                ld a,b
                ld (sp_hi),a
                ret

; La linea sw_y de la imagen limpia (sp_lo..sp_hi) al bufer
lb_load:        ld a,PG_BGB
                ld de,LBBM
                call lb_plane
                ld a,PG_BGA
                ld de,LBAT
                call lb_plane
                jp map7_back
lb_plane:       push de
                call map7
                ld a,(sw_y)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(sp_lo)
                ld c,a
                ld b,0
                add hl,bc
                ld de,$DF00             ; la fila 0 de la imagen es la linea 8
                add hl,de               ; origen
                pop de
                ex de,hl
                add hl,bc               ; destino en el bufer
                ex de,hl
                ld a,(sp_hi)
                sub c
                inc a
                ld c,a
                ld b,0
                ldir
                ret

; El bufer (sp_lo..sp_hi) a la linea sw_y de la pantalla
lb_flush:       ld a,(sw_y)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(sp_lo)
                ld c,a
                ld b,0
                add hl,bc
                ld (lf_o),hl
                ld a,(sp_hi)
                sub c
                inc a
                ld (lf_n),a
                ld hl,LBBM
                add hl,bc
                ld de,(lf_o)
                push hl
                ld hl,HR_BM
                add hl,de
                ex de,hl
                pop hl
                ld a,(lf_n)
                ld c,a
                ld b,0
                ldir
                ld a,(sp_lo)
                ld c,a
                ld b,0
                ld hl,LBAT
                add hl,bc
                ld de,(lf_o)
                push hl
                ld hl,HR_ATT
                add hl,de
                ex de,hl
                pop hl
                ld a,(lf_n)
                ld c,a
                ld b,0
                ldir
                ret

; ---------------------------------------------------------------------
;  La fila de la linea sw_y del objeto sa_n al bufer
; ---------------------------------------------------------------------
sw_apply:       ld a,(sa_n)
                ld l,a
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
                call cel_open
                ret c
                ld l,(ix+O_Y)           ; t = y - (y_obj - h + 9)
                ld h,0
                ld a,(cv_h)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld de,9
                add hl,de
                ex de,hl
                ld a,(sw_y)
                ld l,a
                ld h,0
                or a
                sbc hl,de
                ld a,l
                and 7
                ld (sa_r),a
                ld a,l
                rrca
                rrca
                rrca
                and 31
                ld (sa_ty),a
                ld a,(ix+O_X)
                call lo16
                ld a,l
                and 7
                ld (sa_s),a
                ld a,l
                rrca
                rrca
                rrca
                and 31
                ld (sa_cx),a
                ld hl,(cv_p)
                ld (sa_p),hl
                xor a
                ld (sa_i),a
sa_t:           ld a,(sa_i)
                ld hl,cv_n
                cp (hl)
                jp nc,hw_end
                ld hl,(sa_p)
                inc hl
                ld a,(hl)               ; ty del mosaico
                ld hl,sa_ty
                cp (hl)
                jp c,sa_nx              ; todavia no
                jp nz,hw_end            ; ya nos pasamos (los mosaicos van por filas)
                ld hl,(sa_p)
                ld a,(sa_r)
                ld e,a
                ld d,0
                add hl,de
                ld (sa_rp),hl
                ld de,18
                add hl,de
                ld a,(hl)
                or a
                jp z,sa_nx
                ld (sa_m),a
                ld hl,(sa_rp)
                ld de,10
                add hl,de
                ld a,(hl)
                ld (sa_pix),a
                ld hl,(sa_rp)
                ld de,2
                add hl,de
                ld a,(hl)
                ld (sp_col),a
                ld hl,(sa_p)
                ld a,(hl)               ; tx
                ld hl,sa_cx
                add a,(hl)
                ld (sa_cell),a
                ld a,(sa_s)
                or a
                jr nz,sa_sh
                ld a,(sa_cell)
                ld (sp_cell),a
                ld a,(sa_m)
                ld (sp_m),a
                ld a,(sa_pix)
                ld (sp_p),a
                call sw_part
                jr sa_nx
sa_sh:          ld a,(sa_cell)          ; parte A: desplazada s a la derecha
                ld (sp_cell),a
                ld a,(sa_s)
                ld b,a
                ld a,(sa_m)
sa_s1:          srl a
                djnz sa_s1
                ld (sp_m),a
                ld a,(sa_s)
                ld b,a
                ld a,(sa_pix)
sa_s2:          srl a
                djnz sa_s2
                ld (sp_p),a
                call sw_part
                ld a,(sa_cell)          ; parte B: lo que se sale, a la celda siguiente
                inc a
                ld (sp_cell),a
                ld a,(sa_s)
                ld c,a
                ld a,8
                sub c
                ld b,a
                ld a,(sa_m)
sa_s3:          add a,a
                djnz sa_s3
                ld (sp_m),a
                ld a,(sa_s)
                ld c,a
                ld a,8
                sub c
                ld b,a
                ld a,(sa_pix)
sa_s4:          add a,a
                djnz sa_s4
                ld (sp_p),a
                call sw_part
sa_nx:          ld hl,(sa_p)
                ld de,26
                add hl,de
                ld (sa_p),hl
                ld hl,sa_i
                inc (hl)
                jp sa_t

; sp_cell (0-31), sp_m, sp_p, sp_col (tinta*16 + papel) al bufer
sw_part:        ld a,(sp_m)
                or a
                ret z
                ld a,(sp_cell)
                cp 32
                ret nc
                ld a,(sp_m)
                cp $FF
                jr nz,spp_pl
                ld a,(sp_cell)
                ld e,a
                ld d,0
                ld hl,LBBM
                add hl,de
                ld a,(sp_p)
                ld (hl),a
                ld hl,LBAT
                add hl,de
                ld a,(sp_col)
                rrca
                rrca
                rrca
                rrca                    ; papel * 16 + tinta
                ld (hl),a
                ret
spp_pl:         ld hl,LBBM
                ld (srow),hl
                ld hl,LBAT
                ld (sarow),hl
                ld a,(sp_cell)
                add a,a
                add a,a
                add a,a
                ld (sp_hx),a
                ld a,$80
                ld (sp_bm),a
spp_l:          ld a,(sp_m)
                ld hl,sp_bm
                and (hl)
                jr z,spp_n
                ld a,(sp_p)
                and (hl)
                ld a,(sp_col)
                jr z,spp_p
                rrca
                rrca
                rrca
                rrca
spp_p:          and 15
                ld (sch),a
                ld a,(sp_hx)
                call plot
spp_n:          ld hl,sp_hx
                inc (hl)
                ld hl,sp_bm
                srl (hl)
                jr nz,spp_l
                ret

sqs_n:          defb 0
sqs_r:          defw 0
sg_s:           defb 0
sg_cx:          defb 0
sg_nb:          defb 0
sg_top:         defw 0
sg_y0v:         defb 0
sg_y1v:         defb 0
sq_chg:         defb 0
sq_i:           defb 0
sq_j:           defb 0
sq_ri:          defw 0
sq_rj:          defw 0
sc_nl:          defb 0
sc_yv:          defb 0
sc_ymin:        defb 0
sc_ymax:        defb 0
sc_pri:         defb 0
sc_k:           defb 0
sw_y:           defb 0
sp_lo:          defb 0
sp_hi:          defb 0
sp_r:           defw 0
lf_o:           defw 0
lf_n:           defb 0
sa_n:           defb 0
sa_r:           defb 0
sa_ty:          defb 0
sa_s:           defb 0
sa_cx:          defb 0
sa_p:           defw 0
sa_i:           defb 0
sa_rp:          defw 0
sa_m:           defb 0
sa_pix:         defb 0
sa_cell:        defb 0
sp_cell:        defb 0
sp_m:           defb 0
sp_p:           defb 0
sp_col:         defb 0
sp_hx:          defb 0
sp_bm:          defb 0
SWL:            defs NOBJ
LBBM:           defs 32
LBAT:           defs 32
SWR:            defs 16*NOBJ
