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
                call sw_restore
                xor a
                ld (sk),a
                ld (rpri),a
hq_p:           ld ix,OBJ
                xor a
                ld (rn),a
hq_o:           ld a,(ix+O_F1)
                and 3
                cp 3
                jr nz,hq_n
                ld a,(rpri)
                cp (ix+O_PRI)
                call z,spr_obj
hq_n:           ld de,32
                add ix,de
                ld hl,rn
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,hq_o
                ld hl,rpri
                inc (hl)
                ld a,(hl)
                cp 16
                jr c,hq_p
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
                ld a,(LWIN)             ; numero de celdas del bucle
                ld b,a
                ld a,(ix+O_CEL)
                cp b
                jr nc,co_bad            ; la celda no existe
                ld l,a
                ld h,0
                add hl,hl
                ld de,LWIN+1
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
spr_obj:        ld a,(ix+O_VIEW)
                ld (hw_tag),a
                ld a,(ix+O_LOOP)
                ld (hw_tag+1),a
                ld a,(ix+O_CEL)
                ld (hw_tag+2),a
                call cel_open
                ret c
                ld a,(cv_fl)
                and 1
                jp nz,sw_blit
                ld a,(sk)
                cp 64
                jp nc,hw_end
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
                xor a
                ld (hw_i),a
hw_tl:          ld a,(hw_i)
                ld hl,hw_n
                cp (hl)
                jp nc,hw_end
                ld a,(sk)
                cp 64
                jp nc,hw_end
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
                call spr_put
hw_skip:        ld hl,(hw_p)
                ld de,26
                add hl,de
                ld (hw_p),hl
                ld hl,hw_i
                inc (hl)
                jr hw_tl
hw_end:         jp unmap_win

; El mosaico en (hw_p) en el sprite sk, en (hw_sx, hw_sy), con la etiqueta hw_tag
spr_put:        ld a,(sk)
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
hp_d1:          ld (hw_dch),a
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
hp_wr:          ld a,(sk)
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
hp_done:        ld hl,sk
                inc (hl)
                ret

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
cv_n:           defb 0
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
