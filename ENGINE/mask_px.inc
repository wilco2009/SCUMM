; la mascara de la celda (ac_mt), sin los pixeles que tapa la sala, a los registros del sprite; conserva HL (el siguiente dato de la celda)
acd_mput:       ld a,(ac_mk)
                or a
                call nz,ac_mask_px
                push hl
                ld hl,ac_mt
                ld de,2121
                ld bc,8
                ldir
                pop hl
                ret

; ---- mascara de profundidad por pixel (TOOLS/lfl2gfx.py mask_blob, en DATA.BIN; ROOMDIR+13 = pagina y direccion). Se decodifica en
; BACKBUF la ventana que cubre el personaje: ac_ns tiras de 8 pixeles, de 64 filas cada una, la primera es la fila ac_y0 de la sala.
; Al dibujar cada celda se le quitan a su mascara los pixeles que tapa la sala (ac_mask_px).
; Mientras se decodifica, ac_mt guarda: +0 tira de la ventana, +1 destino (palabra), +3 siguiente tramo (palabra), +5 valor, +6 fila (palabra)
; La cuenta de filas del tramo (+6) empieza en 128 - ac_y0: la fila de la ventana 0 es 128 y la ventana acaba en 128 + ac_rh.
ac_mkdec:       ld a,(iy+2)             ; ancho del fotograma en celdas: con el desplazamiento caben 8 tiras
                cp 7
                jp nc,mk_fail
                add a,2
                ld (ac_ns),a
                ld a,(iy+3)             ; alto en celdas: 64 filas como mucho
                cp 9
                jp nc,mk_fail
                add a,a
                add a,a
                add a,a
                ld (ac_rh),a
                ld hl,(ac_x)
                ld de,(ac_cam)
                add hl,de               ; columna de pixeles de la sala del borde izquierdo
                bit 7,h
                jp nz,mk_fail
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                jp nz,mk_fail
                ld a,l
                ld (ac_s0),a
                ld hl,(ac_y)
                ld (ac_y0),hl
                ex de,hl
                ld hl,128
                or a
                sbc hl,de
                jp c,mk_fail            ; la fila 0 de la ventana esta debajo de la sala
                ld a,(ac_mpg)
                call map_page
                ld hl,BACKBUF
                ld (ac_mt+1),hl
                xor a
                ld (ac_mt),a
mk_strip:       ld hl,(ac_mt+1)         ; la tira, a ceros
                ld d,h
                ld e,l
                inc de
                ld (hl),0
                ld bc,63
                ldir
                ld a,(ac_mt)
                ld hl,ac_s0
                add a,(hl)              ; tira de la sala = primera + k
                ld hl,(ac_mbl)
                cp (hl)
                jp nc,mk_next           ; fuera de la sala
                ld l,a
                ld h,0
                add hl,hl
                ld de,(ac_mbl)
                add hl,de
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                jp z,mk_next            ; tira vacia
                ld hl,(ac_mbl)
                add hl,de
                ld (ac_mt+3),hl
                ld hl,128
                ld de,(ac_y0)
                or a
                sbc hl,de
                ld (ac_mt+6),hl
mk_run:         ld hl,(ac_mt+3)
                ld a,(hl)
                or a
                jr z,mk_next
                ld e,a
                ld d,0                  ; DE = longitud
                inc hl
                ld a,(hl)
                ld (ac_mt+5),a          ; valor
                inc hl
                ld (ac_mt+3),hl
                ld hl,(ac_mt+6)
                ld b,h
                ld c,l                  ; BC = inicio del tramo
                add hl,de               ; HL = fin del tramo
                ld (ac_mt+6),hl
                ld de,129
                or a
                sbc hl,de
                jr c,mk_run             ; acaba antes de la ventana
                add hl,de
                ld a,b                  ; inicio = max(inicio, 128)
                or a
                jr nz,mk_s
                ld a,c
                cp 128
                jr nc,mk_s
                ld c,128
mk_s:           ld a,(ac_rh)
                ld e,a
                ld d,0
                push hl
                ld hl,128
                add hl,de
                ex de,hl                ; DE = fin de la ventana
                pop hl                  ; HL = fin del tramo
                push hl
                ld h,b
                ld l,c
                or a
                sbc hl,de
                pop hl
                jr nc,mk_next           ; empieza despues de la ventana
                push hl
                or a
                sbc hl,de
                pop hl
                jr c,mk_e
                ex de,hl                ; fin = fin de la ventana
mk_e:           or a
                sbc hl,bc               ; HL = filas del tramo dentro de la ventana
                ld a,(ac_mt+5)
                or a
                jr z,mk_run             ; valor 0: ya esta a ceros
                push hl
                ld a,c
                sub 128
                ld e,a
                ld d,0
                ld hl,(ac_mt+1)
                add hl,de
                ex de,hl                ; DE = destino
                pop bc                  ; BC = filas
                ld a,(ac_mt+5)
                ld h,d
                ld l,e
                ld (hl),a
                inc de
                dec bc
                ld a,b
                or c
                jr z,mk_run
                ldir
                jp mk_run
mk_next:        ld hl,(ac_mt+1)
                ld de,64
                add hl,de
                ld (ac_mt+1),hl
                ld hl,ac_mt
                inc (hl)
                ld a,(ac_ns)
                cp (hl)
                jp nz,mk_strip
                ld a,(ac_cpage)
                jp map_page             ; el traje vuelve a la ventana de datos
mk_fail:        xor a
                ld (ac_mk),a
                ret

; AND NOT de la mascara de la sala sobre las 8 filas de ac_mt, para la celda (ac_cx, ac_cy; coordenadas de sprite = pantalla + 32)
ac_mask_px:     push hl
                ld hl,(ac_cx)
                ld de,32
                or a
                sbc hl,de
                ld de,(ac_cam)
                add hl,de               ; columna de pixeles de la sala
                bit 7,h
                jp nz,mp_end
                ld a,l
                and 7
                ld (ac_sh),a
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                jp nz,mp_end
                ld a,l
                ld hl,ac_s0
                sub (hl)
                jp c,mp_end
                ld b,a                  ; B = tira de la ventana
                inc a
                ld hl,ac_ns
                cp (hl)
                jp nc,mp_end            ; hacen falta la tira y la siguiente
                ld a,(ac_cy)
                sub 32
                ld l,a
                ld h,0
                ld de,(ac_y0)
                or a
                sbc hl,de               ; fila de la celda en la ventana
                bit 7,h
                jp nz,mp_end
                ld a,h
                or a
                jp nz,mp_end
                ld a,l
                add a,8
                ld c,a
                ld a,(ac_rh)
                cp c
                jp c,mp_end             ; la celda se sale por abajo
                ld a,b                  ; HL = BACKBUF + tira * 64 + fila
                rrca
                rrca
                ld d,a
                and $3F
                ld h,a
                ld a,d
                and $C0
                ld l,a
                ld de,BACKBUF
                add hl,de
                ld a,c
                sub 8
                ld e,a
                ld d,0
                add hl,de
                ld de,ac_mt
                ld b,8
mp_r:           push bc
                ld a,(hl)               ; byte de la tira
                push hl
                ld bc,64
                add hl,bc
                ld c,(hl)               ; byte de la tira siguiente
                ld b,a
                pop hl
                ld a,(ac_sh)
                or a
                jr z,mp_n
                push hl
                ld h,b
                ld l,c
                ld b,a
mp_s:           add hl,hl
                djnz mp_s
                ld a,h
                pop hl
                jr mp_a
mp_n:           ld a,b
mp_a:           cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                inc de
                inc hl
                pop bc
                djnz mp_r
mp_end:         pop hl
                ret
