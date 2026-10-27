; =====================================================================
;  agihws.asm - sprites por hardware (se incluye desde agitxt.asm, es parte del overlay)
;
;  t_render, una vez por ciclo tras update_objects: los objetos con anim y drawn, de menor a mayor prioridad (a igual prioridad, por numero), reparten
;  sus mosaicos (N%03d%d.SPR, TOOLS/agi2spr.py) entre los sprites 0, 1, 2... (el de indice mas alto tapa al de abajo). De cada sprite se recuerda
;  que se escribio (SHD: activo, x, y y la etiqueta vista/bucle/celda/mosaico): los datos solo se reescriben si cambia la etiqueta y la posicion solo si
;  cambia. Los sprites que sobran se apagan. Es lo mismo que Interp.hw_sprites() del modelo (TOOLS/agi_vm.py).
;  Coordenadas del hardware: pixel + 32; el pixel de AGI a empieza en el HiRes (8a+4)/5 (lo16); la fila 0 de la imagen es la linea 8.
; =====================================================================

SPR_SEL         equ 2100
SPR_ON          equ 2101
SPR_X           equ 2102
SPR_Y           equ 2104
SPR_COL         equ 2105                ; color, forma y mascara: 24 bytes seguidos

t_sinit:        ld hl,SHD
                ld de,SHD+1
                ld bc,511
                ld (hl),0
                ldir
                ld hl,SHD+4
                ld de,8
                ld b,64
si_l:           ld (hl),$FF             ; etiqueta que no coincide con ningun mosaico
                add hl,de
                djnz si_l
                ld hl,vslot
                ld de,vslot+1
                ld bc,NVSLOT-1
                ld (hl),$FF
                ldir
                xor a
                ld (vnext),a
                ld b,0
si_h:           ld a,b
                ld (SPR_SEL),a
                xor a
                ld (SPR_ON),a
                inc b
                ld a,b
                cp 64
                jr c,si_h
                ret

t_render:       call sw_scan
                call sw_close
                call sw_comp
                xor a
                ld (sk),a
                ld hl,PCNT              ; objetos por prioridad (reparto por cubos): primero cuantos hay de cada una
                ld de,PCNT+1
                ld bc,15
                ld (hl),0
                ldir
                ld ix,OBJ
                ld b,NOBJ
hq_c:           ld a,(ix+O_F1)
                and 3
                cp 3
                jr nz,hq_cn
                ld a,(ix+O_PRI)
                cp 16
                jr nc,hq_cn
                ld e,a
                ld d,0
                ld hl,PCNT
                add hl,de
                inc (hl)
hq_cn:          ld de,32
                add ix,de
                djnz hq_c
                ld hl,PCNT              ; donde empieza cada prioridad en ORD
                ld b,16
                xor a
hq_s:           ld c,(hl)
                ld (hl),a
                add a,c
                inc hl
                djnz hq_s
                ld (hq_cnt),a
                ld ix,OBJ
                xor a
                ld (rn),a
hq_p2:          ld a,(ix+O_F1)
                and 3
                cp 3
                jr nz,hq_pn
                ld a,(ix+O_PRI)
                cp 16
                jr nc,hq_pn
                ld e,a
                ld d,0
                ld hl,PCNT
                add hl,de
                ld e,(hl)
                inc (hl)
                ld d,0
                ld hl,ORD
                add hl,de
                ld a,(rn)
                ld (hl),a
hq_pn:          ld de,32
                add ix,de
                ld hl,rn
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,hq_p2
                xor a                   ; y ahora, en orden
                ld (hq_k),a
hq_it:          ld a,(hq_k)
                ld hl,hq_cnt
                cp (hl)
                jr nc,hq_dn
                ld e,a
                ld d,0
                ld hl,ORD
                add hl,de
                ld a,(hl)
                ld (rn),a
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
                call spr_obj
                ld hl,hq_k
                inc (hl)
                jr hq_it
hq_dn:
                xor a
                ld (sw_force),a
                ld a,(sk)               ; apagar los que sobran
hq_off:         cp 64
                ret nc
                ld (hw_k),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SHD
                add hl,de
                ld a,(hl)
                or a
                jr z,hq_nx
                ld (hl),0
                ld a,(hw_k)
                ld (SPR_SEL),a
                xor a
                ld (SPR_ON),a
hq_nx:          ld a,(hw_k)
                inc a
                jr hq_off

; ---------------------------------------------------------------------
;  Vistas: A = vista, B = bucle -> A = pagina de la cache donde esta su N%03d%d.SPR, o $FF si no hay
; ---------------------------------------------------------------------
vc_get:         cp $FF
                ret z
                ld (vwant),a
                ld a,b
                ld (vwantl),a
                ld hl,vslot
                ld de,vslotl
                ld b,NVSLOT
vg_l:           ld a,(vwant)
                cp (hl)
                jr nz,vg_n
                ld a,(vwantl)
                ld c,a
                ld a,(de)
                cp c
                jr z,vg_hit
vg_n:           inc hl
                inc de
                djnz vg_l
                ld a,(vnext)
                ld e,a
                inc a
                and NVSLOT-1
                ld (vnext),a
                ld a,e
                ld (vtry),a
                ld d,0
                ld hl,vslot
                add hl,de
                ld (hl),$FF
                ld a,(vwantl)
                add a,'0'
                ld (nmv+4),a
                ld a,(vwant)
                ld hl,nmv+1
                call mk_dig
                ld hl,nmv
                call f_open
                cp $FF
                ret z
                ld (fh),a
                ld hl,vlen2
                ld bc,2
                call f_read_n
                ld a,(vtry)
                add a,PG_VC0
                call map_page
                ld a,(fh)
                ld hl,LWIN
                ld bc,(vlen2)
                call f_read_n
                ld a,(fh)
                call f_close
                call unmap_win
                ld a,(vtry)
                ld e,a
                ld d,0
                ld hl,vslot
                add hl,de
                ld a,(vwant)
                ld (hl),a
                ld hl,vslotl
                add hl,de
                ld a,(vwantl)
                ld (hl),a
                ld a,(vtry)
                add a,PG_VC0
                ret
vg_hit:         ld a,NVSLOT
                sub b
                add a,PG_VC0
                ret

; A = pixel de AGI (0-160) -> HL = primer pixel HiRes de ese pixel: 8*(a/5) + (0,2,4,5,7)[a%5]
lo16:           ld b,5
                call div8
                ld e,a
                ld d,0
                ld hl,lo_t1
                add hl,de
                ld e,(hl)
                ld l,c
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de
                ret
lo_t1:          defb 0,2,4,5,7

; ---------------------------------------------------------------------
;  Un objeto (IX): sus mosaicos a los siguientes sprites
; ---------------------------------------------------------------------
; IX = objeto -> NC con la pagina de su bucle mapeada y cv_* puestos (celdas, ancho, alto, banderas, huella, mosaicos), o C si no hay celda (sin mapear)
cel_open:       ld a,(ix+O_X)
                cp 160
                jr nc,co_no
                ld a,(ix+O_VIEW)
                ld b,(ix+O_LOOP)
                call vc_get
                cp $FF
                jr z,co_no
                call map_page
                ld a,(LWIN+1)           ; mosaicos que reserva un objeto de este bucle
                ld (cv_mt),a
                ld a,(LWIN)             ; numero de celdas del bucle
                ld b,a
                ld a,(ix+O_CEL)
                cp b
                jr nc,co_bad            ; la celda no existe
                ld l,a
                ld h,0
                add hl,hl
                ld de,LWIN+2
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,LWIN
                add hl,de               ; registro de la celda
                ld a,(hl)
                ld (cv_n),a
                inc hl
                ld a,(hl)
                ld (cv_w),a
                inc hl
                ld a,(hl)
                ld (cv_h),a
                inc hl
                ld a,(hl)
                ld (cv_fl),a
                inc hl
                ld a,(hl)
                ld (cv_hl),a
                inc hl
                ld a,(hl)
                ld (cv_hh),a
                inc hl
                ld (cv_p),hl
                or a
                ret
co_bad:         call unmap_win
co_no:          scf
                ret

; ---------------------------------------------------------------------
;  Un objeto (IX): sus mosaicos a los siguientes sprites (o, si es un rotulo ancho, al bitmap: sw_blit)
; ---------------------------------------------------------------------
spr_obj2:       ld a,(ix+O_VIEW)
                ld (hw_tag),a
                ld a,(ix+O_LOOP)
                ld (hw_tag+1),a
                ld a,(ix+O_CEL)
                ld (hw_tag+2),a
                call cel_open
                ret c
                ld a,(cv_fl)
                and 1
                jp nz,hw_end            ; rotulo ancho: lo dibuja agisw.asm
                ld a,(sk)
                ld (hw_base),a          ; este objeto reserva cv_mt sprites desde aqui
                ld a,(cv_n)
                ld (hw_n),a
                ld a,(cv_h)
                ld (hw_h),a
                ld hl,(cv_p)
                ld (hw_p),hl
                ld a,(ix+O_X)
                call lo16
                ld de,32
                add hl,de
                ld (hw_x0),hl           ; x del hardware del borde izquierdo de la celda
                ld l,(ix+O_Y)
                ld h,0
                ld a,(hw_h)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld de,41                ; 8 (barra de estado) - 1 + 32
                add hl,de
                ld (hw_top),hl          ; y del hardware de la primera linea de la celda (con signo)
                ld a,(picvalid)
                ld (hw_mk),a            ; con imagen, los pixeles tapados por el fondo se quitan de la mascara
                ld a,$FF
                ld (hw_gty),a
                ld a,(ix+O_PRI)
                ld (hw_pri),a
                ld hl,(hw_x0)
                ld de,32
                or a
                sbc hl,de
                ld a,l
                ld (hw_X0),a            ; x HiRes del borde izquierdo
                ld e,a
                ld d,0
                ld a,(cv_w)
                ld l,a
                ld h,0
                add hl,de
                dec hl                  ; x del ultimo pixel
                ld a,h
                or a
                jr z,hw_pl
                ld l,255
hw_pl:          ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                inc l
                ld a,l
                ld (hw_plim),a          ; hasta que pixel de AGI hay que decodificar la prioridad
                dec a
                rrca
                rrca
                rrca
                and 31
                ld (hw_bx1),a           ; bloques de 8 pixeles de AGI que toca el objeto
                ld a,(hw_X0)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,l
                rrca
                rrca
                rrca
                and 31
                ld (hw_bx0),a
                xor a
                ld (hw_i),a
hw_tl:          ld a,(hw_i)
                ld hl,hw_n
                cp (hl)
                jp nc,hw_fin
                ld hl,hw_base
                add a,(hl)
                ld (hw_slot),a          ; el mosaico j va al sprite reservado j
                cp 64
                jp nc,hw_skip
                ld hl,(hw_p)
                ld a,(hl)               ; tx
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(hw_x0)
                add hl,de
                ld (hw_sx),hl
                ld a,h
                cp 2
                jr nc,hw_skip
                cp 1
                jr nz,hw_xok
                ld a,l
                cp 32
                jr nc,hw_skip           ; x >= 288: fuera por la derecha
hw_xok:         ld hl,(hw_p)
                inc hl
                ld a,(hl)               ; ty
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(hw_top)
                add hl,de
                bit 7,h
                jr nz,hw_skip
                ld a,h
                or a
                jr nz,hw_skip
                ld a,l
                cp 25
                jr c,hw_skip            ; y <= 24: fuera por arriba
                cp 224
                jr nc,hw_skip           ; y >= 224: fuera por abajo
                ld (hw_sy),a
                ld a,(hw_i)
                ld (hw_tag+3),a
                xor a
                ld (hw_mm),a
                ld a,(hw_mk)
                or a
                jr z,hw_put
                call hw_mask
                jr z,hw_skip            ; el fondo lo tapa entero
                ld a,(hw_mm)
                or a
                jr z,hw_put
                ld a,(hw_i)
                or $80                  ; etiqueta: mosaico con la mascara recortada
                ld (hw_tag+3),a
hw_put:         call spr_put
                jr hw_nx
hw_skip:        call hw_off1
hw_nx:          ld hl,(hw_p)
                ld de,26
                add hl,de
                ld (hw_p),hl
                ld hl,hw_i
                inc (hl)
                jp hw_tl
hw_end:         jp unmap_win

; Fin de los mosaicos de la celda: los sprites reservados que no usa se apagan y sk salta lo reservado
hw_fin:         ld a,(hw_n)
                ld (hw_i),a
hf_l:           ld a,(hw_i)
                ld hl,cv_mt
                cp (hl)
                jr nc,hf_d
                ld hl,hw_base
                add a,(hl)
                ld (hw_slot),a
                call hw_off1
                ld hl,hw_i
                inc (hl)
                jr hf_l
hf_d:           ld a,(hw_base)
                ld hl,cv_mt
                add a,(hl)
                jr c,hf_c
                cp 65
                jr c,hf_s
hf_c:           ld a,64
hf_s:           ld (sk),a
                jp unmap_win

; Apaga el sprite hw_slot si esta encendido
hw_off1:        ld a,(hw_slot)
                cp 64
                ret nc
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SHD
                add hl,de
                ld a,(hl)
                or a
                ret z
                ld (hl),0
                ld a,(hw_slot)
                ld (SPR_SEL),a
                xor a
                ld (SPR_ON),a
                ret

; ---------------------------------------------------------------------
;  Prioridad frente al fondo: la mascara de cada fila de un mosaico se reduce a los pixeles cuyo pixel de AGI, (5 * x) >> 3, tiene en el plano de
;  prioridad de los sprites (PG_PRI2, por el bloque 7) una prioridad <= la del objeto. Se hace por grupos de mosaicos de la misma fila (ty):
;  para cada una de sus 8 lineas se decodifica la fila del plano una vez (PROW) y se calcula la mascara de todos sus mosaicos (MK).
; ---------------------------------------------------------------------
PROW            equ MSGBUF

; Z si el mosaico hw_i se queda sin ningun pixel visible; si no, hw_mkp apunta a sus 8 mascaras
hw_mask:        ld hl,(hw_p)
                inc hl
                ld a,(hl)
                ld hl,hw_gty
                cp (hl)
                call nz,hw_group
                ld a,(hw_graw)
                or a
                jr z,hm_mk
                ld hl,(hw_p)            ; el fondo no puede tapar nada: la mascara del propio mosaico
                ld de,18
                add hl,de
                ld (hw_mkp),hl
                xor a
                ld (hw_mm),a
                jr hm_ck
hm_mk:          ld a,1
                ld (hw_mm),a
                ld a,(hw_i)
                ld hl,hw_gs
                sub (hl)
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,MK
                add hl,de
                ld (hw_mkp),hl
hm_ck:          ld hl,(hw_mkp)
                ld b,8
                xor a
hm_o:           or (hl)
                inc hl
                djnz hm_o
                or a
                ret

; A = ty del mosaico hw_i: arma MK para todos los mosaicos de esa fila a partir de el
hw_group:       ld (hw_gty),a
                ld a,(hw_i)
                ld (hw_gs),a
                ld hl,(hw_p)
                ld (hw_gp),hl
                ld a,(hw_n)
                ld b,a
                ld a,(hw_i)
                ld c,a
                ld a,b
                sub c
                ld b,a                  ; mosaicos que quedan
                ld c,0
hg_c:           ld a,b
                or a
                jr z,hg_cd
                inc hl
                ld a,(hw_gty)
                cp (hl)
                dec hl
                jr nz,hg_cd
                inc c
                ld a,c
                cp 8
                jr nc,hg_cd
                ld de,26
                add hl,de
                dec b
                jr hg_c
hg_cd:          ld a,c
                ld (hw_gn),a
                ld a,(hw_gty)           ; py de la primera linea = top + ty*8 - 40
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(hw_top)
                add hl,de
                ld de,40
                or a
                sbc hl,de
                ld (hw_gb),hl
                xor a                   ; antes de armar nada: ¿alguna de las 8 filas puede tener el fondo por encima?
                ld (hg_r),a
hg_pre:         ld a,(hg_r)
                ld e,a
                ld d,0
                ld hl,(hw_gb)
                add hl,de
                ld a,h
                or a
                jr nz,hg_pn
                ld a,l
                cp 168
                jr nc,hg_pn
                ld (hg_py),a
                call hg_need
                jr nz,hg_dec
hg_pn:          ld hl,hg_r
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,hg_pre
                ld a,1
                ld (hw_graw),a          ; ninguna: sin mascara que armar
                ret
hg_dec:         xor a
                ld (hw_graw),a
                ld (hg_r),a
hg_row:         ld a,(hg_r)
                ld e,a
                ld d,0
                ld hl,(hw_gb)
                add hl,de
                ld a,h
                or a
                jr nz,hg_all            ; fuera de la imagen: sin prioridad
                ld a,l
                cp 168
                jr nc,hg_all
                ld (hg_py),a
                call hg_need
                jr z,hg_all             ; el fondo no puede taparlo en esta fila
                ld a,PG_PRI2
                call map7
                ld a,(hg_py)
                call pd_row
                call map7_back
                xor a
                ld (hg_full),a
                jr hg_t0
hg_all:         ld a,1
                ld (hg_full),a
hg_t0:          ld hl,(hw_gp)
                ld (hg_tp),hl
                xor a
                ld (hg_j),a
hg_t:           ld a,(hg_j)
                ld hl,hw_gn
                cp (hl)
                jr nc,hg_rn
                ld a,(hg_full)
                or a
                ld c,$FF
                jr nz,hg_m
                ld hl,(hg_tp)           ; hx0 = X0 + tx * 8
                ld a,(hl)
                add a,a
                add a,a
                add a,a
                ld l,a
                ld h,0
                jr nc,hg_x
                inc h
hg_x:           ld a,(hw_X0)
                ld e,a
                ld d,0
                add hl,de
                call hg_okb
                ld c,a
hg_m:           ld hl,(hg_tp)           ; mascara de la fila r
                ld de,18
                add hl,de
                ld a,(hg_r)
                ld e,a
                ld d,0
                add hl,de
                ld a,(hl)
                and c
                ld c,a
                ld a,(hg_j)             ; MK[j * 8 + r]
                add a,a
                add a,a
                add a,a
                ld hl,hg_r
                add a,(hl)
                ld e,a
                ld d,0
                ld hl,MK
                add hl,de
                ld (hl),c
                ld hl,(hg_tp)
                ld de,26
                add hl,de
                ld (hg_tp),hl
                ld hl,hg_j
                inc (hl)
                jr hg_t
hg_rn:          ld hl,hg_r
                inc (hl)
                ld a,(hl)
                cp 8
                jp c,hg_row
                ret

; NZ si en la fila hg_py algun bloque del objeto tiene un maximo de prioridad mayor que la del objeto (PG_PMX, por el bloque 7)
hg_need:        ld a,PG_PMX
                call map7
                ld a,(hg_py)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld d,h
                ld e,l                  ; 4 * py
                add hl,hl
                add hl,hl
                add hl,de               ; 20 * py
                ld a,(hw_bx0)
                ld e,a
                ld d,0
                add hl,de
                ld de,$E000
                add hl,de
                ld a,(hw_bx1)
                ld b,a
                ld a,(hw_bx0)
                ld c,a
                ld a,b
                sub c
                inc a
                ld b,a                  ; bloques
                ld a,(hw_pri)
                ld c,a
hn_l:           ld a,(hl)
                cp c
                jr c,hn_n
                jr z,hn_n
                ld a,1
                jr hn_r
hn_n:           inc hl
                djnz hn_l
                xor a
hn_r:           push af
                call map7_back
                pop af
                or a
                ret

; HL = x HiRes del primer pixel -> A = pixeles visibles (bit 7 = el primero) segun PROW y hw_pri
hg_okb:         ld b,8
                ld c,0
hk_l:           sla c
                ld a,h
                or a
                jr nz,hk_v              ; x >= 256: fuera de la pantalla
                push hl
                ld d,0
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de               ; 5 * x
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld de,PROW
                add hl,de
                ld a,(hl)
                ld hl,hw_pri
                cp (hl)
                pop hl
                jr c,hk_v
                jr nz,hk_n              ; la del fondo es mayor
hk_v:           inc c
hk_n:           inc hl
                djnz hk_l
                ld a,c
                ret

; A = fila de la imagen, PG_PRI2 en el bloque 7 -> PROW (prioridad de los pixeles de AGI hasta hw_plim)
pd_row:         ld l,a
                ld h,0
                add hl,hl
                ld de,$E000
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,$E000+336
                add hl,de
                ld de,PROW
pd_l:           ld a,(hl)
                inc hl
                ld b,a
                rrca
                rrca
                rrca
                rrca
                and 15
                ld c,a
                ld a,b
                and 15
                inc a
                ld b,a
                ld a,c
pd_f:           ld (de),a
                inc de
                djnz pd_f
                ld a,(hw_plim)
                ld c,a
                ld a,e
                cp c
                jr c,pd_l
                ret

; Objeto sin cambios desde el ciclo anterior (mismos datos y mismo primer sprite): se salta sus sprites; si no, se arma y se anota
spr_obj:        ld a,(sk)
                ld (hw_sk0),a
                bit 1,(ix+O_SDR)
                jr z,sob_go
                push ix
                pop hl
                ld de,O_SVW
                add hl,de
                push ix
                pop de
                inc de
                inc de
                ld b,6
sob_c:          ld a,(de)
                cp (hl)
                jr nz,sob_go
                inc hl
                inc de
                djnz sob_c
                ld a,(rn)
                add a,a
                ld e,a
                ld d,0
                ld hl,HWI
                add hl,de
                ld a,(sk)
                cp (hl)
                jr nz,sob_go
                inc hl
                ld a,(hl)
                ld hl,sk
                add a,(hl)
                ld (hl),a
                ret
sob_go:         call spr_obj2
                set 1,(ix+O_SDR)
                push ix
                pop hl
                inc hl
                inc hl
                push ix
                pop de
                push hl
                ld hl,O_SVW
                add hl,de
                ex de,hl
                pop hl
                ld bc,6
                ldir
                ld a,(rn)
                add a,a
                ld e,a
                ld d,0
                ld hl,HWI
                add hl,de
                ld a,(hw_sk0)
                ld (hl),a
                inc hl
                ld c,a
                ld a,(sk)
                sub c
                ld (hl),a
                ret

; El mosaico en (hw_p) en el sprite sk, en (hw_sx, hw_sy), con la etiqueta hw_tag
spr_put:        ld a,(hw_slot)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SHD
                add hl,de
                ld (hw_sh),hl
                ld de,4
                add hl,de
                ld de,hw_tag
                ld b,4
hp_c:           ld a,(de)
                cp (hl)
                jr nz,hp_dch
                inc hl
                inc de
                djnz hp_c
                xor a
                jr hp_d1
hp_dch:         ld a,1
hp_d1:          ld b,a
                ld a,(hw_mm)            ; con la mascara recortada depende de la posicion: siempre se reescribe
                or b
                ld (hw_dch),a
                ld hl,(hw_sh)
                ld a,(hl)
                or a
                jr z,hp_pch             ; estaba apagado
                inc hl
                ld a,(hw_sx)
                cp (hl)
                jr nz,hp_pch
                inc hl
                ld a,(hw_sx+1)
                cp (hl)
                jr nz,hp_pch
                inc hl
                ld a,(hw_sy)
                cp (hl)
                jr nz,hp_pch
                xor a
                ld (hw_pch),a
                ld a,(hw_dch)
                or a
                jr z,hp_done            ; ni datos ni posicion
                jr hp_wr
hp_pch:         ld a,1
                ld (hw_pch),a
hp_wr:          ld a,(hw_slot)
                ld (SPR_SEL),a
                ld a,(hw_dch)
                or a
                jr z,hp_nd
                ld hl,(hw_p)
                inc hl
                inc hl
                ld de,SPR_COL
                ld bc,24
                ldir
                ld a,(hw_mm)
                or a
                jr z,hp_nd
                ld hl,(hw_mkp)
                ld de,SPR_COL+16
                ld bc,8
                ldir
hp_nd:          ld a,(hw_pch)
                or a
                jr z,hp_ns
                ld hl,(hw_sx)
                ld (SPR_X),hl           ; 2102 y 2103
                ld a,(hw_sy)
                ld (SPR_Y),a
                ld a,1
                ld (SPR_ON),a
hp_ns:          ld hl,(hw_sh)
                ld (hl),1
                inc hl
                ld a,(hw_sx)
                ld (hl),a
                inc hl
                ld a,(hw_sx+1)
                ld (hl),a
                inc hl
                ld a,(hw_sy)
                ld (hl),a
                inc hl
                ex de,hl
                ld hl,hw_tag
                ld bc,4
                ldir
hp_done:        ret

; vistas en cache: vista y bucle de cada ranura
vslot:          defb $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
vslotl:         defs NVSLOT
vnext:          defb 0
vwant:          defb 0
vwantl:         defb 0
vtry:           defb 0
vlen2:          defw 0
nmv:            defb "N0000.SPR",0
sk:             defb 0
rpri:           defb 0
rn:             defb 0
hw_k:           defb 0
hw_n:           defb 0
hq_cnt:         defb 0
hq_k:           defb 0
hw_mm:          defb 0
hw_graw:        defb 0
PCNT:           defs 16
ORD:            defs NOBJ
hw_bx0:         defb 0
hw_bx1:         defb 0
hw_mk:          defb 0
hw_gty:         defb 0
hw_gs:          defb 0
hw_gn:          defb 0
hw_gp:          defw 0
hw_gb:          defw 0
hw_mkp:         defw 0
hw_pri:         defb 0
hw_X0:          defb 0
hw_plim:        defb 0
hw_sk0:         defb 0
hg_r:           defb 0
hg_py:          defb 0
hg_full:        defb 0
hg_tp:          defw 0
hg_j:           defb 0
MK:             defs 64
HWI:            defs 64
cv_n:           defb 0
cv_mt:          defb 0
hw_base:        defb 0
hw_slot:        defb 0
cv_w:           defb 0
cv_h:           defb 0
cv_fl:          defb 0
cv_hl:          defb 0
cv_hh:          defb 0
cv_p:           defw 0
hw_h:           defb 0
hw_i:           defb 0
hw_p:           defw 0
hw_x0:          defw 0
hw_top:         defw 0
hw_sx:          defw 0
hw_sy:          defb 0
hw_sh:          defw 0
hw_dch:         defb 0
hw_pch:         defb 0
hw_tag:         defs 4
SHD:            defs 8*64
