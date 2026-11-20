; =====================================================================
;  ovd_act.asm - actores de v3 (fase 8). Se incluye desde ovld.asm (overlay D, pagina 46): una entrada mas, OVD_ACTORS (+12), que el bucle principal
;  llama una vez por fotograma (scumm.asm, despues de gd_update). Solo existe en el programa (PROGRAM = 1): el nucleo de pruebas no tiene pantalla.
;
;  Dibuja a los actores de la sala con los sprites de la placa: un sprite por celda de 8 x 8 del blob del traje (V3/TOOLS/costume3.py), con la
;  mascara de profundidad de la sala por pixel. Semantica (la copia en Python es V3/TOOLS/sprites3.py; la comprobacion, test/check_spr.py):
;    - los actores de la sala (CURROOM), visibles y con traje, de menor a mayor y (el de mas abajo, el ultimo: processActors de ScummVM; empate: el de
;      menor numero primero), reciben los sprites 0, 1, 2... en ese orden (a mayor numero de sprite, mas al frente);
;    - la animacion es fotograma * 4 + direccion antigua (newDirToOldDir de ScummVM) del blob principal del traje (COSTDIR) o, si no esta, del extra
;      (COSTDIR2); si tampoco, la del fotograma de quieto (A_STAND). Sin ninguna: el actor no se dibuja;
;    - la postura es  ((contador * pasos) >> 3) mod pasos  con un contador por actor que vuelve a 0 cuando cambia su fotograma (A_FRAME) y suma 1
;      por fotograma dibujado (ACCNT: ultimo fotograma, contador);
;    - x de pantalla = x - camara + dx; y = y - elevacion + dy + HR_TOP - ytop (la sala empieza en la linea 16 de la pantalla y se recorta con hv_ytop);
;      las lineas de un sprite fuera de [16, 144) no se ven (el area de mensajes y la interfaz son del texto);
;    - si no caben todos los sprites de un actor (el 63 es el cursor), no se dibuja: ver D6 en PLAN.md.
;  Cache de firma como en v2: un actor con la misma firma y los mismos sprites que el fotograma anterior no se vuelve a escribir.
; =====================================================================
; (las variables, aq_vars.inc, las incluye scumm.asm: este overlay las lee de scumm.sym)

NOCACHE         equ 0                   ; 1: sin cache (para comparar sprites con y sin ella)

actors_run:     ld a,(gf_have)
                or a
                ret z
                call gf_campx
                ld (aq_cam),hl
                ld hl,(aq_stamp)
                inc hl
                ld (aq_stamp),hl
                xor a
                ld (aq_n),a
                ld (aq_cnt),a
                ld (aq_xn),a
                ld (aq_xm),a
                ld a,(CURROOM)          ; ROOMDIR +27 de la sala: 1 = trajes a 3/4 (SMALL_ROOMS, pack_data3.py)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,COLD_ROOMDIR+27
                add hl,de
                ld de,aq_small
                ld bc,1
                call cold_rd
                ld a,(aq_hold)          ; sala nueva: los sprites siguen apagados hasta saber donde va la camara
                or a
                jr z,au_run
                dec a
                ld (aq_hold),a
                jp au_hide
au_run:         ld b,1                  ; actor 0 no existe
ao_l:           push bc
                ld a,b
                call actor_ix
                pop bc
                ld a,(CURROOM)
                cp (ix+A_ROOM)
                jr nz,ao_next
                ld a,(ix+A_VIS)
                or a
                jr z,ao_next
                ld a,(ix+A_COST)
                or (ix+A_COST+1)
                jr z,ao_next
                ld d,(ix+A_Y)           ; clave = y
                ld a,(aq_cnt)
                ld c,a                  ; C = lugares ocupados
ao_ins:         ld a,c
                or a
                jr z,ao_put
                dec a
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                ld a,(hl)               ; la clave del anterior
                cp d
                jr c,ao_put
                jr z,ao_put
                ld a,(hl)               ; si es mayor se desplaza un lugar
                inc hl
                ld e,(hl)
                inc hl
                ld (hl),a
                inc hl
                ld (hl),e
                dec c
                jr ao_ins
ao_put:         ld a,c
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                ld (hl),d
                inc hl
                ld (hl),b
                ld hl,aq_cnt
                inc (hl)
ao_next:        inc b
                ld a,b
                cp NACT
                jr c,ao_l
                ld a,(aq_cnt)
                or a
                jp z,au_hide
                xor a                   ; pasada 1, de delante a atras: cada actor elige su fotograma y se reparte: los que caben en los 63 sprites normales, y cuando uno no cabe
                ld (aq_tot),a           ; ese y todos los que van mas atras a los extra (que tienen menos prioridad que todos los normales: asi el orden de fondo se conserva)
                ld (aq_tx),a
                ld (aq_ovf),a
                ld a,(aq_cnt)
                ld (aq_li),a
p1_l:           ld a,(aq_li)
                dec a
                ld (aq_li),a
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                inc hl
                ld a,(hl)
                ld (aq_id),a
                call actor_ix
                call aq_sel             ; NC: IY = su fotograma
                push af
                call aq_aent            ; HL = su entrada de ASEL
                pop af
                jr c,p1_none
                push iy
                pop de
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld de,(aq_blob)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(aq_cpage)
                ld (hl),a
                inc hl
                ld a,(iy+4)
                ld (hl),a
                inc hl
                ld b,a                  ; B = sprites que pide
                ld a,(aq_ovf)
                or a
                jr nz,p1_x
                ld a,(aq_tot)
                add a,b
                cp AC_MAXSPR+1
                jr nc,p1_ovf
                ld (aq_tot),a
                ld (hl),0               ; normales
                jr p1_next
p1_ovf:         ld a,1
                ld (aq_ovf),a
p1_x:           ld a,(aq_tx)
                add a,b
                cp AC_XMAX+1
                jr nc,p1_skip
                ld (aq_tx),a
                ld (hl),1               ; extra
                jr p1_next
p1_skip:        ld (hl),2               ; no cabe ni en los extra: no se dibuja
                jr p1_next
p1_none:        ld de,5
                add hl,de
                ld (hl),0
                inc hl
                ld (hl),2
p1_next:        ld a,(aq_li)
                or a
                jr nz,p1_l
                xor a                   ; pasada 2: los normales, de atras adelante (sprites 0, 1, 2...)
                ld (aq_xm),a
                ld (aq_li),a
p2_l:           call aq_aent
                ld bc,6
                add hl,bc
                ld a,(hl)
                or a
                jr nz,p2_n
                call aq_load
                call aq_cdraw
p2_n:           ld a,(aq_li)
                inc a
                ld (aq_li),a
                ld hl,aq_cnt
                cp (hl)
                jr c,p2_l
                ld a,1                  ; pasada 3: los extra, de delante atras (el de numero mas bajo gana)
                ld (aq_xm),a
                ld a,(aq_cnt)
                ld (aq_li),a
p3_l:           ld a,(aq_li)
                dec a
                ld (aq_li),a
                call aq_aent
                ld bc,6
                add hl,bc
                ld a,(hl)
                dec a
                jr nz,p3_n
                call aq_load
                call aq_cdraw
p3_n:           ld a,(aq_li)
                or a
                jr nz,p3_l
au_hide:        ld a,(aq_xn)            ; sprites extra en uso (POKE 2131: los que sobran dejan de mirarse)
                ld (2131),a
                ld a,(aq_n)             ; los sprites que sobran del fotograma anterior se apagan
                ld b,a
                ld a,(aq_used)
                ld c,a
                ld a,b
                ld (aq_used),a
aq_off:         ld a,b
                cp c
                ret nc
                ld (2100),a
                xor a
                ld (2101),a
                inc b
                jr aq_off

; ---------------------------------------------------------------------------------------------------------------------------------
;  Cache de firma: si un actor tiene la misma firma (camara, posicion, elevacion, fotograma del traje, sala, caja) y los mismos sprites que en el
;  fotograma anterior, sus sprites ya estan bien. Una entrada vale solo si su marca es la del fotograma anterior.
; ---------------------------------------------------------------------------------------------------------------------------------
; HL = la entrada de ASEL del actor aq_li de la lista (6 * aq_li)
aq_aent:        ld a,(aq_li)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl               ; 8 * aq_li
                ld de,ASEL
                add hl,de
                ret

; prepara el actor aq_li de la lista para dibujarlo: aq_id, IX, IY = su fotograma, aq_fr, aq_cpage y la pagina de su traje en la ventana
aq_load:        call aq_aent
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld (aq_blob),bc
                ld a,(hl)
                ld (aq_cpage),a
                ld (aq_fr),de
                push de
                pop iy
                ld a,(aq_li)
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                inc hl
                ld a,(hl)
                ld (aq_id),a
                call actor_ix
                ld a,(aq_cpage)
                jp map_page

; A = el primer sprite de lo que se va a dibujar: el siguiente normal o, en los extra, 64 + el siguiente extra
aq_cur:         ld a,(aq_xm)
                or a
                ld a,(aq_n)
                ret z
                ld a,(aq_xn)
                add a,64
                ret

aq_cdraw:       call aq_hash            ; IX = actor, IY = su fotograma, la pagina del traje en la ventana (aq_load)
                ld (aq_sg),de
                ld a,(aq_id)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * actor
                ld de,ACSIG
                add hl,de
                ld (aq_ent),hl
                IF NOCACHE
                jr acc_miss
                ENDIF
                push hl
                ld de,4
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; marca de la entrada
                ld hl,(aq_stamp)
                dec hl
                or a
                sbc hl,de
                pop hl
                jr nz,acc_miss
                ld e,(hl)
                inc hl
                ld d,(hl)               ; firma de la entrada
                inc hl
                push hl
                ld hl,(aq_sg)
                or a
                sbc hl,de
                pop hl
                jr nz,acc_miss
                call aq_cur
                cp (hl)                 ; el mismo primer sprite
                jr nz,acc_miss
                inc hl
                ld a,(hl)               ; cuantos sprites usa
                ld c,a
                ld hl,aq_n
                ld a,(aq_xm)
                or a
                jr z,acc_a
                ld hl,aq_xn
acc_a:          ld a,(hl)
                add a,c
                ld (hl),a
                ld hl,(aq_ent)
                ld de,4
                add hl,de
                ld de,(aq_stamp)
                ld (hl),e
                inc hl
                ld (hl),d
                ret
acc_miss:       call aq_cur
                ld (aq_n0),a
                call aq_draw
                ld hl,(aq_ent)
                ld de,(aq_sg)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(aq_n0)
                ld (hl),a
                inc hl
                ld c,a
                call aq_cur
                sub c
                ld (hl),a
                inc hl
                ld de,(aq_stamp)
                ld (hl),e
                inc hl
                ld (hl),d
                ret

; DE = firma del actor IX: lo que aq_draw lee de el, de la camara y del fotograma elegido
aq_hash:        ld hl,(aq_cam)
                ld a,(CURROOM)
                call ach
                ld a,(ix+A_X)
                call ach
                ld a,(ix+A_X+1)
                call ach
                ld a,(ix+A_Y)
                call ach
                ld a,(ix+A_Y+1)
                call ach
                ld a,(ix+A_ELEV)
                call ach
                ld a,(ix+A_WBOX)
                call ach
                ld a,(aq_fr)
                call ach
                ld a,(aq_fr+1)
                call ach
                ld a,(aq_cpage)
                call ach
                ld a,(hv_ytop)
                call ach
                ex de,hl
                ret
ach:            ld d,h                  ; HL = HL * 31 + A
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                or a
                sbc hl,de
                add a,l
                ld l,a
                ret nc
                inc h
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Eleccion del fotograma del actor IX (aq_id): carry si no hay nada que dibujar. Actualiza el contador de poses.
; ---------------------------------------------------------------------------------------------------------------------------------
aq_sel:         ld a,(aq_id)            ; contador: vuelve a 0 si cambia el fotograma
                add a,a
                ld e,a
                ld d,0
                ld hl,ACCNT
                add hl,de
                ld a,(ix+A_FRAME)
                cp (hl)
                jr z,as_inc
                ld (hl),a
                inc hl
                ld (hl),0
                jr as_cnt
as_inc:         inc hl
                inc (hl)
as_cnt:         ld a,(ix+A_COST+1)
                or a
                jr nz,as_none
                ld a,(ix+A_COST)
                or a
                jr z,as_none
                cp 129
                jr nc,as_none
                ld (aq_cost),a
                ld l,(ix+A_FACING)
                ld h,(ix+A_FACING+1)
                call aq_olddir
                ld (aq_dir),a
                ld a,(ix+A_FRAME)
                call aq_find
                jr nc,as_found
                ld a,(ix+A_STAND)       ; el fotograma pedido no esta en el traje: el de quieto
                cp (ix+A_FRAME)
                jr z,as_none
                call aq_find
                jr c,as_none
as_found:       ld b,(hl)               ; pasos de la animacion
                ld a,b
                or a
                jr z,as_none
                inc hl
                push hl                 ; la tabla de pasos
                ld a,(aq_id)
                add a,a
                inc a
                ld e,a
                ld d,0
                ld hl,ACCNT
                add hl,de
                ld a,(hl)               ; A = contador
                ld hl,0
                ld d,0
                ld e,b
                ld c,b                  ; C = pasos
                ld b,8
as_mul:         add hl,hl
                rlca
                jr nc,as_m2
                add hl,de
as_m2:          djnz as_mul             ; HL = contador * pasos
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,l                  ; (el limite de pasos del conversor es 8: cabe en un byte)
as_mod:         cp c
                jr c,as_md
                sub c
                jr as_mod
as_md:          add a,a
                ld e,a
                ld d,0
                pop hl
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                and e
                inc a
                jr z,as_none            ; $FFFF: sin imagen
                ld hl,(aq_blob)
                add hl,de
                ld (aq_fr),hl
                push hl
                pop iy
                or a
                ret
as_none:        scf
                ret

; A = fotograma -> NC y HL = la lista de pasos de la animacion (con el blob en la ventana de datos: aq_blob, aq_cpage), o carry. Busca en el blob
; principal del traje (COSTDIR) y, si la animacion no esta, en el extra (COSTDIR2). Animacion = fotograma * 4 + direccion antigua (aq_dir)
aq_find:        ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld a,(aq_dir)
                ld e,a
                ld d,0
                add hl,de
                ld (aq_anim),hl
                ld hl,COLD_COSTDIR
                ld a,(aq_small)
                or a
                jr z,aq_f1
                ld hl,SM_COSTDIR
aq_f1:          call aq_cd
                ret nc
                ld hl,COLD_COSTDIR2
                ld a,(aq_small)
                or a
                jr z,aq_cd
                ld hl,SM_COSTDIR2
aq_cd:          ld a,(aq_cost)
                ld e,a
                ld d,0
                ld c,l
                ld b,h                  ; BC = base de la tabla
                ld l,e
                ld h,d
                add hl,hl
                add hl,de               ; 3 * traje
                add hl,bc
                ld de,aq_ce
                ld bc,3
                ld a,(aq_small)
                or a
                jr nz,aq_cs
                call cold_rd
                jr aq_cr
aq_cs:          call cls_open           ; salas a 3/4: las tablas estan en CLS_PG; por la ventana (bloque 1), no por el bloque 0, que es este overlay
                ld a,h                  ; (10g: mapear CLS_PG en el bloque 0 quitaba el overlay D de debajo y el Z80 se iba por encima de $8000)
                add a,WINDOW/256
                ld h,a
                ldir
                call cls_close
aq_cr:          ld a,(aq_ce)
                or a
                scf
                ret z                   ; sin blob
                ld (aq_cpage),a
                call map_page
                ld hl,(aq_ce+1)
                ld (aq_blob),hl
                ld de,(aq_anim)
                ld a,d
                or a
                scf
                ret nz                  ; la animacion no cabe en el u8 del numero de animaciones
                ld a,e
                cp (hl)
                ccf
                ret c                   ; animacion >= numero de animaciones
                inc hl
                inc hl
                inc hl
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                scf
                ret z                   ; lista vacia
                ld hl,(aq_blob)
                add hl,de
                or a
                ret

; HL = angulo -> A = direccion antigua: newDirToOldDir de ScummVM (util.cpp): 71-109 derecha (1), 109-251 de frente (2), 251-289 izquierda (0), el resto de espaldas (3)
aq_olddir:      ld a,h
                or a
                jr nz,aod_hi
                ld a,l
                cp 71
                jr c,aod_up
                cp 110
                jr c,aod_r
                cp 252
                jr c,aod_dn
aod_l:          xor a                   ; 252-255 (y 256-289 abajo): izquierda
                ret
aod_hi:         dec h                   ; 256 + l: solo 256-289 es izquierda (251-289)
                jr nz,aod_up
                ld a,l
                cp 34
                jr c,aod_l
aod_up:         ld a,3
                ret
aod_r:          ld a,1
                ret
aod_dn:         ld a,2
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Dibujo de las celdas del fotograma IY del actor IX (la pagina de su traje esta en la ventana)
; ---------------------------------------------------------------------------------------------------------------------------------
aq_draw:        ld l,(ix+A_X)           ; x de pantalla = x - camara + dx
                ld h,(ix+A_X+1)
                ld de,(aq_cam)
                or a
                sbc hl,de
                ld e,(iy+0)
                ld d,0
                bit 7,e
                jr z,acd_dx
                dec d
acd_dx:         add hl,de
                ld (aq_x),hl
                ld l,(ix+A_Y)           ; fila de la sala = y - elevacion + dy
                ld h,(ix+A_Y+1)
                ld e,(ix+A_ELEV)
                ld d,(ix+A_ELEV+1)
                or a
                sbc hl,de
                ld e,(iy+1)
                ld d,0
                bit 7,e
                jr z,acd_dy
                dec d
acd_dy:         add hl,de
                ld (aq_ry),hl
                ld b,(iy+4)
                ld a,(aq_xm)            ; si no caben todos sus sprites no se dibuja a medias
                or a
                jr nz,acd_fx
                ld a,(aq_n)
                add a,b
                cp AC_MAXSPR+1
                ret nc
                jr acd_fo
acd_fx:         ld a,(aq_xn)
                add a,b
                cp AC_XMAX+1
                ret nc
acd_fo:
                ld hl,(aq_x)            ; 10d: lo que cada celda sumaba a x y a la fila, una vez por actor
                ld de,32
                add hl,de
                ld (aq_x32),hl
                ld hl,(aq_ry)
                ld de,HR_TOP+32
                add hl,de
                ld a,(hv_ytop)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld (aq_y32),hl
                call aq_mkdec           ; la mascara de la sala bajo el actor (puede quitar aq_mk)
                ld hl,(aq_blob)         ; 10d: la tabla de celdas del traje, una vez por actor
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,(aq_blob)
                add hl,de
                ld (aq_ctab),hl
                ld b,(iy+4)
                push iy
                pop hl
                ld de,5
                add hl,de
acd_cell:       ld a,b
                or a
                jp z,acd_end
                ld a,(hl)               ; referencia: cx | cy << 4 y el indice de la celda en el fondo de celdas del traje
                ld (aq_pos),a
                ld c,a                  ; (y en C)
                inc hl
                ld e,(hl)
                inc hl
                ld (aq_nx),hl           ; la siguiente referencia
                ld d,0
                ld hl,(aq_ctab)
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a                  ; HL = offset de la celda (banderas, forma, mascara, color)
                ld de,(aq_blob)
                add hl,de
                push bc
                push hl                 ; la celda (sus banderas: bit 0 mascara completa, bit 1 color uniforme)
                ld a,c
                and $0F
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(aq_x32)          ; (aq_x + 32)
                add hl,de
                bit 7,h
                jp nz,acd_skp2
                ld (aq_cx),hl
                ld de,319
                or a
                sbc hl,de
                jp nc,acd_skp2
                ld a,c                  ; y de la celda de pantalla = fila de la sala + 8 * cy + HR_TOP - ytop (+32 del sprite)
                srl a
                and $78                 ; 8 * cy
                ld e,a
                ld d,0
                ld hl,(aq_y32)          ; (aq_ry + HR_TOP + 32 - hv_ytop)
                add hl,de
                bit 7,h
                jp nz,acd_skp2
                ld a,h
                or a
                jp nz,acd_skp2
                ld a,l
                ld (aq_cy),a
                sub 32                  ; 10d: directo (aq_drc = 1) si no hay mascara de la sala y las 8 filas caen en [AC_YMIN, AC_YMAX):
                jr c,acd_nd             ; entonces aq_mask_px no se llama y aq_clip no cambia nada (ver aq_clip)
                cp AC_YMIN
                jr c,acd_nd
                cp AC_YMAX-7
                jr nc,acd_nd
                ld a,(aq_mk)
                or a
                jr nz,acd_nd
                inc a
                jr acd_sd
acd_nd:         xor a
acd_sd:         ld (aq_drc),a
                call aq_slot            ; el siguiente sprite (normal o extra): su posicion escrita y donde van forma, mascara y colores
                jp c,acd_skp2
                pop hl                  ; la celda
                ld a,(hl)               ; banderas (A sobrevive a ldi)
                inc hl
                ld de,(aq_sp)           ; forma
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                push af
                ld c,a
                ld a,(aq_drc)
                or a
                jr z,acd_ms             ; el camino de siempre (aq_mt y acd_mput)
                bit 0,c
                jr nz,acd_df
                ld de,(aq_sm)           ; directo: la mascara de la celda a los registros del sprite
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                jr acd_c0
acd_df:         ex de,hl                ; directo, mascara completa
                ld hl,(aq_sm)
                call acd_ff
                ex de,hl
                jr acd_c0
acd_ms:         bit 0,c
                jr z,acd_m1
                push hl                 ; mascara completa
                ld hl,aq_mt
                call acd_ff
                pop hl
                call acd_mput
                jr acd_c0
acd_m1:         ld de,aq_mt
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                call acd_mput
acd_c0:         pop af
                bit 1,a
                jr z,acd_c1
                ld a,(hl)               ; color uniforme
                ld hl,(aq_sc)
                call acd_fa
                jr acd_skip
acd_c1:         ld de,(aq_sc)
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                jr acd_skip
acd_skp2:       pop hl                  ; (la celda)
acd_skip:       ld hl,(aq_nx)
                pop bc
                dec b
                jp acd_cell
acd_end:        ld a,(aq_cpage)         ; la mascara de la sala movio la ventana: el traje vuelve
                jp map_page
acd_ff:         ld a,$FF                ; 8 bytes desde HL con A ($FF en acd_ff)
acd_fa:         ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                ret

; la mascara de la celda (aq_mt), sin los pixeles que tapa la sala ni las lineas que caen fuera de la sala en pantalla, a los registros del sprite; conserva HL
acd_mput:       push hl
                ld a,(aq_mk)
                or a
                call nz,aq_mask_px
                call aq_clip
                ld hl,aq_mt
                ld de,(aq_sm)
                ldi                     ; (10d: 8 ldi en vez de ldir)
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                pop hl
                ret

; pone a 0 las filas de la mascara (aq_mt) cuya linea de pantalla esta fuera de [AC_YMIN, AC_YMAX); la y del sprite es aq_cy (linea + 32)
aq_clip:        ld a,(aq_cy)
                sub 32                  ; A = linea de pantalla de la fila 0 (puede ser negativa: carry)
                jr c,acl_neg
                cp AC_YMIN
                jr c,acl_top
                cp AC_YMAX-7
                ret c                   ; las 8 filas caben: todas dentro
                cp AC_YMAX
                jr nc,acl_all
                sub AC_YMAX-8           ; A = 1..7: filas dentro = 8 - A
                ld b,a
                ld a,8
                sub b
                jr acl_tail             ; deja las primeras A filas
acl_neg:        neg                     ; A = -linea (1..32): es la linea 0 + (negativa)
                add a,AC_YMIN           ; filas fuera por arriba = AC_YMIN + (-linea)
                jr acl_head
acl_top:        ld b,a
                ld a,AC_YMIN
                sub b                   ; filas fuera por arriba = AC_YMIN - linea
acl_head:       cp 8
                jr nc,acl_all
                ld b,a                  ; B = filas a borrar al principio (1..7)
                ld de,aq_mt
acl_h:          xor a
                ld (de),a
                inc de
                djnz acl_h
                ret
acl_tail:       ld c,a                  ; C = filas que quedan (0..7)
                ld b,0
                ld hl,aq_mt
                add hl,bc
                ld a,8
                sub c
                ld b,a
acl_t:          ld (hl),0
                inc hl
                djnz acl_t
                ret
acl_all:        ld hl,aq_mt
                ld b,8
acl_a:          ld (hl),0
                inc hl
                djnz acl_a
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Mascara de profundidad por pixel (TOOLS/lfl2gfx.py mask_blob, en DATA.BIN; CURRD+15 = pagina y direccion). aq_mkdec decide si se usa para el
;  actor IX (la sala la tiene, la caja del actor tiene mascara y el fotograma cabe en la ventana de 8 tiras x 64 filas) y decodifica en MKBUF
;  la ventana que cubre el fotograma: aq_ns = ancho en celdas + 2 tiras de 8 pixeles (la tira k es la s0 + k de la sala) de aq_rh = alto * 8 filas
;  (la primera es la fila aq_ry de la sala). Cada celda toma sus 8 columnas de la tira de su columna y de la siguiente, desplazadas aq_sh bits.
; ---------------------------------------------------------------------------------------------------------------------------------
aq_mkdec:       xor a
                ld (aq_mk),a
                ld a,(CURRD+15)
                or a
                ret z
                ld (aq_mpg),a
                ld hl,(CURRD+16)
                ld (aq_mbl),hl
                ld a,(ix+A_WBOX)
                cp 255                  ; 10a: sin caja (kOldInvalidBox: el actor ignora las cajas, como Indy al salir por la puerta del gimnasio): en v3 la mascara
                jr z,mk_box             ; es 1 (getMaskFromBox de ScummVM, WORKAROUND de los bugs #791 y #897); antes se quedaba sin mascara
                ld hl,NBOXES
                cp (hl)
                ret nc
                ld c,a
                ld b,0
                call box_addr
                ret c
                ld de,16
                add hl,de
                ld a,(hl)               ; mascara de la caja
                or a
                ret z
mk_box:         ld a,(iy+2)             ; ancho en celdas: con el desplazamiento caben 8 tiras
                cp 7
                ret nc
                add a,2
                ld (aq_ns),a
                ld a,(iy+3)             ; alto en celdas: 64 filas como mucho
                cp 9
                ret nc
                add a,a
                add a,a
                add a,a
                ld (aq_rh),a
                ld hl,(aq_x)            ; columna de la sala del borde izquierdo del fotograma
                ld de,(aq_cam)
                add hl,de
                ld a,l                  ; 10a: la columna puede ser negativa (el actor asoma por el borde izquierdo de la sala: la puerta del gimnasio);
                and 7                   ; antes se quitaba la mascara entera y el actor salia por delante de la pared
                ld (aq_sh),a
                sra h                   ; tira = columna / 8 con signo (hacia abajo)
                rr l
                sra h
                rr l
                sra h
                rr l
                ld a,h
                or a
                jr z,mk_pos
                inc a
                ret nz                  ; menos de -256: fuera
                ld a,l
                cp $F8
                ret c                   ; mas de 8 tiras a la izquierda de la sala: no se ve nada del fotograma
                jr mk_s0
mk_pos:         ld a,l
                cp $F8
                ret nc                  ; (las tiras 248-255 no existen: aq_s0 >= $F8 quiere decir -8..-1)
mk_s0:          ld (aq_s0),a
                ld a,(aq_mpg)
                call map_page
                ld hl,MKBUF
                ld (aq_dd),hl
                xor a
                ld (aq_k),a             ; tira k de la ventana
mk_strip:       ld hl,(aq_dd)           ; la tira, a ceros: 10d, solo sus aq_rh filas (las celdas caen dentro del fotograma: costume3.py
                ld (hl),0               ; las saca de su rejilla de ancho x alto; las filas de mas abajo no se leen)
                ld a,(aq_rh)
                sub 2
                jr c,mk_z
                inc a
                ld c,a
                ld b,0
                ld d,h
                ld e,l
                inc de
                ldir
mk_z:
                ld a,(aq_s0)
                ld hl,aq_k
                add a,(hl)              ; tira de la sala = s0 + k
                ld e,a
                sbc a,a
                ld d,a                  ; D = $FF si la suma ha dado la vuelta
                ld a,(aq_s0)
                cp $F8
                sbc a,a                 ; $FF si s0 >= 0
                xor d                   ; 10a: vale si s0 >= 0 y no da la vuelta, o si s0 < 0 (-8..-1) y la da (la tira ya es >= 0)
                jp z,mk_next
                ld a,e
                ld hl,(aq_mbl)
                cp (hl)
                jp nc,mk_next           ; fuera de la sala
                ld l,a
                ld h,0
                add hl,hl
                ld de,(aq_mbl)
                add hl,de
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jp z,mk_next            ; tira vacia
                ld hl,(aq_mbl)
                add hl,de
                ld (aq_dp),hl
                ld hl,(aq_ry)
                ld a,h                  ; fila de la ventana por la que va el decodificador = -ry
                cpl
                ld h,a
                ld a,l
                cpl
                ld l,a
                inc hl
                ld (aq_dr),hl
mk_run:         ld hl,(aq_dp)
                ld a,(hl)
                or a
                jp z,mk_next
                inc hl
                ld c,(hl)               ; valor
                inc hl
                ld (aq_dp),hl
                ld e,a
                ld d,0                  ; DE = longitud
                ld hl,(aq_dr)           ; HL = inicio del tramo; el siguiente empieza donde acaba este
                push hl
                add hl,de
                ld (aq_dr),hl           ; HL = fin del tramo
                pop de                  ; DE = inicio
                bit 7,h
                jr nz,mk_run            ; acaba antes de la ventana (fin < 0)
                ld a,h
                or l
                jr z,mk_run             ; fin = 0: tampoco entra
                ld a,c
                or a
                jr z,mk_run             ; valor 0: ya esta a ceros
                bit 7,d
                jr z,mk_s1
                ld de,0                 ; inicio = max(inicio, 0)
mk_s1:          ld a,d
                or a
                jp nz,mk_next           ; empieza a partir de la fila 256: nada mas entra
                ld a,(aq_rh)
                cp e
                jp z,mk_next            ; inicio >= alto de la ventana: la tira ha acabado (los demas tramos empiezan despues)
                jp c,mk_next
                ld a,h                  ; fin = min(fin, alto)
                or a
                jr nz,mk_cap
                ld a,(aq_rh)
                cp l
                jr nc,mk_e1
mk_cap:         ld a,(aq_rh)
                ld l,a
mk_e1:          ld a,l
                sub e                   ; A = filas del tramo dentro de la ventana
                jr z,mk_run
                ld b,a
                ld hl,(aq_dd)
                add hl,de               ; destino = tira + inicio (D = 0)
                ld a,c
mk_f:           ld (hl),a
                inc hl
                djnz mk_f
                jr mk_run
mk_next:        ld hl,(aq_dd)
                ld de,64
                add hl,de
                ld (aq_dd),hl
                ld hl,aq_k
                inc (hl)
                ld a,(aq_ns)
                cp (hl)
                jp nz,mk_strip
                ld a,1
                ld (aq_mk),a
                ld a,(aq_cpage)         ; el traje vuelve a la ventana de datos
                jp map_page

; AND NOT de la mascara de la sala sobre las 8 filas de aq_mt para la celda aq_pos: columna cx y fila cy del fotograma (la ventana empieza en el fotograma)
aq_mask_px:     push hl
                ld a,(aq_pos)
                ld c,a
                and $0F
                ld b,a                  ; B = tira de la ventana
                rrca
                rrca
                ld d,a
                and $3F
                ld h,a
                ld a,d
                and $C0
                ld l,a                  ; HL = 64 * tira
                ld de,MKBUF
                add hl,de
                ld a,c
                srl a
                srl a
                srl a
                srl a
                add a,a
                add a,a
                add a,a                 ; fila de la celda en la ventana
                ld e,a
                ld d,0
                add hl,de
                push iy                 ; fase 10d: IY = la tira siguiente y una variante del bucle por desplazamiento (antes, un bucle de
                push hl                 ; desplazamientos por fila: mp_s, mp_r y mp_a eran un tercio de una vuelta con 6 actores)
                pop iy
                ld bc,64
                add iy,bc
                ld de,aq_mt
                ld a,(aq_sh)
                add a,a
                ld c,a
                ld b,0
                push hl
                ld hl,mp_tab
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ex (sp),hl              ; en la pila, la variante; HL = la tira
                ld b,8
                ret
mp_done:        pop iy
                pop hl
                ret
mp_tab:         defw mp_v0,mp_v1,mp_v2,mp_v3,mp_v4,mp_v5,mp_v6,mp_v7
mp_v0:          ld a,(hl)               ; sin desplazamiento: solo la tira
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                djnz mp_v0
                jp mp_done
mp_v1:          ld c,(iy+0)             ; (tira << 1) | (siguiente >> 7)
                ld a,(hl)
                sla c
                rla
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v1
                jp mp_done
mp_v2:          ld c,(iy+0)             ; (tira << 2) | (siguiente >> 6)
                ld a,(hl)
                sla c
                rla
                sla c
                rla
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v2
                jp mp_done
mp_v3:          ld c,(iy+0)             ; (tira << 3) | (siguiente >> 5)
                ld a,(hl)
                sla c
                rla
                sla c
                rla
                sla c
                rla
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v3
                jp mp_done
mp_v4:          ld c,(iy+0)             ; (tira << 4) | (siguiente >> 4)
                ld a,(hl)
                sla c
                rla
                sla c
                rla
                sla c
                rla
                sla c
                rla
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v4
                jp mp_done
mp_v5:          ld c,(iy+0)             ; (tira << 5) | (siguiente >> 3) = byte bajo de (tira:siguiente) >> 3 (10d)
                ld a,(hl)
                srl a
                rr c
                srl a
                rr c
                srl a
                rr c
                ld a,c
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v5
                jp mp_done
mp_v6:          ld c,(iy+0)             ; (tira << 6) | (siguiente >> 2) = byte bajo de (tira:siguiente) >> 2 (10d)
                ld a,(hl)
                srl a
                rr c
                srl a
                rr c
                ld a,c
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v6
                jp mp_done
mp_v7:          ld c,(iy+0)             ; (tira << 7) | (siguiente >> 1) = byte bajo de (tira:siguiente) >> 1 (10d)
                ld a,(hl)
                srl a
                rr c
                ld a,c
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                inc iy
                djnz mp_v7
                jp mp_done

; el siguiente sprite de la pasada (normal: POKEs 2100-2104; extra: su entrada en la sombra, {hoja 0, j, campo} = $0000 + 32 * j, que lee la FPGA con POKE 2129 = 0 y 2131 = numero de extras):
; escribe su posicion (aq_cx, aq_cy) y deja en aq_sp, aq_sm y aq_sc donde van la forma, la mascara y los colores. Carry si no hay hueco
aq_slot:        ld a,(aq_xm)
                or a
                jr nz,sl_x
                ld a,(aq_n)
                cp AC_MAXSPR
                jr c,sl_ok
                scf
                ret
sl_ok:          ld (2100),a
                inc a
                ld (aq_n),a
                ld hl,(aq_cx)
                ld (2102),hl
                ld a,(aq_cy)
                ld (2104),a
                ld a,1
                ld (2101),a
                ld a,(aq_sp+1)          ; 10d: los punteros de los normales ya estan (los de los extra estan por debajo de $0400)
                cp 2113/256
                jr z,slo_r
                ld hl,2113
                ld (aq_sp),hl
                ld hl,2121
                ld (aq_sm),hl
                ld hl,2105
                ld (aq_sc),hl
slo_r:          or a
                ret
sl_x:           ld a,(aq_xn)
                cp AC_XMAX
                jr c,sl_xok
                scf
                ret
sl_xok:         ld c,a                  ; j. 10d: la entrada es $0000 + 32 * j y sus campos (+1..+29) no cruzan un limite de 256 B
                inc a
                ld (aq_xn),a
                ld a,c
                rrca
                rrca
                rrca
                ld h,a
                and $E0
                ld l,a
                xor h
                ld h,a                  ; HL = 32 * j
                inc l
                ld de,(aq_cx)
                ld (hl),e               ; x (+1, +2: el bit 8) e y (+3)
                inc l
                ld (hl),d
                inc l
                ld a,(aq_cy)
                ld (hl),a
                ld a,l
                add a,29-3
                ld l,a
                ld (hl),0               ; formato A
                sub 29-4
                ld l,a
                ld (aq_sc),hl           ; +4
                add a,8
                ld l,a
                ld (aq_sp),hl           ; +12
                add a,8
                ld l,a
                ld (aq_sm),hl           ; +20
                or a
                ret
