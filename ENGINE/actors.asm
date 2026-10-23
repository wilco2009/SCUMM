actors_update:  ld a,(gf_have)
                or a
                ret z
                call gf_campx
                ld (ac_cam),hl
                xor a
                ld (ac_n),a
                ld a,(ac_hold)          ; sala nueva: los sprites siguen apagados hasta saber donde van
                or a
                jr z,au_run
                dec a
                ld (ac_hold),a
                jr au_hide
au_run:         ld ix,ACTORS+ASIZE
                ld b,NACTORS-1
ac_l:           push bc
                ld a,NACTORS
                sub b
                ld (ac_id),a
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,ac_next
                ld a,(ix+9)             ; visible
                or a
                call nz,ac_draw
ac_next:        ld de,ASIZE
                add ix,de
                pop bc
                djnz ac_l
au_hide:        ld a,(ac_n)             ; los sprites que sobran del fotograma anterior se apagan
                ld b,a
                ld a,(ac_used)
                ld c,a
                ld a,b
                ld (ac_used),a
ac_off:         ld a,b
                cp c
                ret nc
                ld (2100),a
                xor a
                ld (2101),a
                inc b
                jr ac_off


; HL = angulo (0, 90, 180, 270) -> A = direccion de v2: 0 izquierda, 1 derecha, 2 de frente, 3 de espaldas
ac_olddir:      ld a,h
                or a
                jr nz,aod_hi
                ld a,l
                cp 45
                jr c,aod_up
                cp 135
                jr c,aod_r
                cp 225
                jr c,aod_dn
                xor a
                ret
aod_hi:         ld a,l
                cp 59                   ; 315 - 256
                jr nc,aod_up
                xor a
                ret
aod_up:         ld a,3
                ret
aod_r:          ld a,1
                ret
aod_dn:         ld a,2
                ret

; IX = actor: sus sprites segun los fotogramas de su traje (TOOLS/costume2.py)
ac_draw:        xor a                   ; mascara de profundidad: solo si la sala la tiene y la caja del personaje tiene mascara
                ld (ac_mk),a
                ld hl,(gf_mask)
                ld a,h
                or l
                jr z,acd_nomk
                ld a,(ix+16)
                ld hl,NBOXES
                cp (hl)
                jr nc,acd_nomk
                call box_rec
                jr c,acd_nomk
                ld de,6
                add hl,de
                ld a,(hl)
                or a
                jr z,acd_nomk
                ld a,1
                ld (ac_mk),a
acd_nomk:       ld a,(ix+5)             ; traje
                or a
                ret z
                cp 64
                ret nc
                ld e,a
                ld d,0
                ld hl,COSTDIR
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                ret z                   ; sin datos: no se dibuja
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_blob),de
                call map_page
                ld l,(ix+6)
                ld h,(ix+7)
                call ac_olddir
                ld c,a                  ; C = direccion
                ld a,(HAVEMSG)          ; hablando: la animacion 4 + direccion (la boca), si el traje la tiene
                or a
                jr z,acd_nt
                ld a,(ac_id)
                ld b,a
                ld a,(VARS+82)          ; VAR_TALK_ACTOR
                cp b
                jr nz,acd_nt
                ld a,c
                add a,4
                ld c,a
                ld hl,(ac_blob)
                cp (hl)
                jr nc,acd_tno
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                jr z,acd_tno
                inc (ix+45)
                jr acd_anim
acd_tno:        ld a,c
                sub 4
                ld c,a
acd_nt:         ld a,(ix+10)            ; fotograma: 0 caminar; el resto, quieto
                or a
                jr z,acd_walk
                xor a                   ; quieto: la primera pose de caminar
                ld (ix+45),a
                jr acd_anim
acd_walk:       inc (ix+45)             ; contador de fotogramas de caminata
acd_anim:       ld hl,(ac_blob)
                ld a,c
                cp (hl)                 ; numero de animaciones
                ret nc
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                ret z
                ld hl,(ac_blob)
                add hl,de               ; HL = lista de la animacion: pasos y offsets de fotograma
                ld b,(hl)
                inc hl
                ld a,b
                or a
                ret z
                ld a,(ix+45)            ; pose = (contador / 8) mod pasos
                srl a
                srl a
                srl a
acd_mod:        cp b
                jr c,acd_md
                sub b
                jr acd_mod
acd_md:         add a,a
                ld e,a
                ld d,0
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                and e
                inc a
                ret z                   ; $FFFF: sin imagen
                ld hl,(ac_blob)
                add hl,de
                push hl
                pop iy                  ; IY = fotograma: dx, dy, cw, ch, n, celdas
                ld l,(ix+1)             ; x * 8 - camara + dx
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(ac_cam)
                or a
                sbc hl,de
                ld e,(iy+0)
                ld d,0
                bit 7,e
                jr z,acd_dx
                dec d
acd_dx:         add hl,de
                ld (ac_x),hl
                ld l,(ix+3)             ; y * 2 + dy
                ld h,(ix+4)
                add hl,hl
                ld e,(iy+1)
                ld d,0
                bit 7,e
                jr z,acd_dy
                dec d
acd_dy:         add hl,de
                ld (ac_y),hl
                ld b,(iy+4)
                ld a,(ac_n)             ; si no caben todos sus sprites (63 como mucho; el 63 es el cursor) no se dibuja a medias
                add a,b
                cp 64
                ret nc
                push iy
                pop hl
                ld de,5
                add hl,de
acd_cell:       ld a,b
                or a
                ret z
                ld (ac_cp),hl
                inc hl
                ld a,(hl)               ; banderas: bit 0 mascara completa, bit 1 color uniforme
                ld (ac_fl),a
                ld e,10                 ; tamano de la celda: posicion, banderas, forma (8) y, si no, mascara (8) y color (8 o 1)
                bit 0,a
                jr nz,acd_s1
                ld e,18
acd_s1:         bit 1,a
                jr z,acd_s2
                inc e
                jr acd_s3
acd_s2:         ld a,e
                add a,8
                ld e,a
acd_s3:         ld d,0
                ld hl,(ac_cp)
                add hl,de
                ld (ac_nx),hl
                ld hl,(ac_cp)
                push bc
                ld a,(hl)               ; cx | cy << 4
                ld c,a
                and $0F
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(ac_x)
                add hl,de
                ld de,32
                add hl,de
                bit 7,h
                jp nz,acd_skip
                ld (ac_cx),hl
                ld de,319
                or a
                sbc hl,de
                jp nc,acd_skip
                ld a,c
                srl a
                srl a
                srl a
                srl a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(ac_y)
                add hl,de
                ld de,32
                add hl,de
                bit 7,h
                jp nz,acd_skip
                ld a,h
                or a
                jp nz,acd_skip
                ld a,l
                ld (ac_cy),a
                ld a,(ac_mk)
                or a
                jr z,acd_nm
                call ac_masked          ; la celda queda detras de un objeto de la sala: no se dibuja
                jp c,acd_skip
acd_nm:         ld a,(ac_n)
                cp 63                   ; el 63 es el cursor
                jp nc,acd_skip
                ld (2100),a
                inc a
                ld (ac_n),a
                ld hl,(ac_cx)
                ld (2102),hl
                ld a,(ac_cy)
                ld (2104),a
                ld a,1
                ld (2101),a
                ld hl,(ac_cp)
                inc hl
                inc hl
                ld de,2113              ; forma
                ld bc,8
                ldir
                ld a,(ac_fl)
                bit 0,a
                jr z,acd_m1
                push hl                 ; mascara completa
                ld hl,2121
                ld b,8
acd_m0:         ld (hl),$FF
                inc hl
                djnz acd_m0
                pop hl
                jr acd_c0
acd_m1:         ld de,2121
                ld bc,8
                ldir
acd_c0:         ld a,(ac_fl)
                bit 1,a
                jr z,acd_c1
                ld a,(hl)               ; color uniforme
                ld hl,2105
                ld b,8
acd_c2:         ld (hl),a
                inc hl
                djnz acd_c2
                jp acd_skip
acd_c1:         ld de,2105
                ld bc,8
                ldir
acd_skip:       ld hl,(ac_nx)
                pop bc
                dec b
                jp acd_cell

; carry si la celda del sprite (ac_cx, ac_cy; coordenadas de sprite = pantalla + 32) cae en una celda de la mascara de la sala (se mira su centro)
ac_masked:      ld hl,(ac_cx)
                ld de,28
                or a
                sbc hl,de
                ld de,(ac_cam)
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                ret nz                  ; NC
                ld a,l
                ld hl,gf_cols
                cp (hl)
                ret nc
                ld l,a
                ld h,0
                add hl,hl
                ld de,(gf_mask)
                add hl,de
                ld a,(ac_cy)
                sub 28
                jr nc,am_y
                or a
                ret
am_y:           srl a
                srl a
                srl a
                cp 16
                ret nc
                ld b,a
                srl a
                srl a
                srl a
                ld e,a
                ld d,0
                add hl,de
                ld a,b
                and 7
                ld b,a
                inc b
                ld a,(hl)
am_s:           rrca
                djnz am_s
                ret
