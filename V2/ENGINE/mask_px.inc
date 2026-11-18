; la mascara de la celda (ac_mt), sin los pixeles que tapa la sala, a los registros del sprite; conserva HL (el siguiente dato de la celda)
acd_mput:       ld a,(ac_mk)
                or a
                call nz,ac_mask_px
                push hl
                ld a,20
                call ac_wbo
                ld hl,ac_mt
                ld bc,8
                ldir
                pop hl
                ret

; ---- mascara de profundidad por pixel (TOOLS/lfl2gfx.py mask_blob, en DATA.BIN; ROOMDIR+13 = pagina y direccion). Se decodifica en
; BACKBUF la ventana que cubre el personaje: ac_ns tiras de 8 pixeles, de ac_rh filas cada una (el alto del fotograma; tiras * filas < 528), la primera es la fila ac_y0 de la sala.
; Al dibujar cada celda se le quitan a su mascara los pixeles que tapa la sala (ac_mask_px).
; Mientras se decodifica, ac_mt guarda: +0 tira de la ventana, +1 destino (palabra), +3 siguiente tramo (palabra), +5 valor, +6 fila (palabra)
; La cuenta de filas del tramo (+6) empieza en 128 - ac_y0: la fila de la ventana 0 es 128 y la ventana acaba en 128 + ac_rh.
ac_mkdec:       ld a,(iy+2)             ; ancho del fotograma en celdas: con el desplazamiento, una tira mas a cada lado
                add a,2
                ld (ac_ns),a
                ld a,(iy+3)             ; alto en celdas: cada tira ocupa ac_rh bytes en BACKBUF (528): tiras * filas no puede pasar de eso
                add a,a
                add a,a
                add a,a
                ld (ac_rh),a
                ld b,a
                ld a,(ac_ns)
                ld c,a
                ld hl,0
                ld d,0
                ld e,b
mk_cap:         add hl,de
                dec c
                jr nz,mk_cap
                ld de,528
                or a
                sbc hl,de
                jp nc,mk_big            ; no cabe (nc: tiras * filas >= 528; con = 528 tambien se descarta: es el limite)
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
                ld a,(ac_rh)
                dec a
                ld c,a
                ld b,0
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
                ld a,(ac_rh)
                ld e,a
                ld d,0
                add hl,de
                ld (ac_mt+1),hl
                ld hl,ac_mt
                inc (hl)
                ld a,(ac_ns)
                cp (hl)
                jp nz,mk_strip
                call mk_objs            ; las mascaras de los objetos que se dibujan sustituyen a la de la sala bajo ellos
                ld a,(ac_cpage)
                jp map_page             ; el traje vuelve a la ventana de datos
mk_big:
mk_fail:        xor a
                ld (ac_mk),a
                ret

; Mascaras de los objetos (GdiV2::prepareDrawBitmap: la de un objeto dibujado sustituye, ceros incluidos, a la de la sala en sus tiras y filas; se dibujan del ultimo
; al primero, como HR_DLIST). Tras la mascara de la sala (ac_mbl) va la tabla de objetos: su desplazamiento esta en la palabra anterior a ac_mbl; ver
; TOOLS/lfl2gfx.py mask_blob_objs. Variables en ac_mt: +0 objetos que faltan, +1 destino de la tira en BACKBUF (0: fuera de la ventana), +3 siguiente tramo,
; +5 filas hechas de la tira, +6 tiras que faltan, +7 tira de la ventana de la primera del objeto (con signo)
mk_objs:        push ix
                ld a,(hv_ndl)
                or a
                jp z,mo_done
                ld (ac_mt),a
mo_obj:         ld a,(hv_ndl)
                ld hl,ac_mt
                sub (hl)
                ld e,a
                ld d,0
                ld hl,HR_DLIST
                add hl,de
                ld a,(hl)               ; objeto (indice en la lista de la sala)
                ld hl,(ac_mbl)
                dec hl
                ld d,(hl)
                dec hl
                ld e,(hl)
                ld hl,(ac_mbl)
                add hl,de               ; HL = tabla de objetos
                ld c,(hl)
                inc hl
                cp c
                jp nc,mo_nx             ; la sala no tiene tantos
                ld e,a
                ld d,0
                push hl
                ld h,d
                ld l,e
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * objeto
                pop de
                add hl,de
                push hl
                pop ix                  ; IX = entrada del objeto
                ld a,(ix+4)
                or (ix+5)
                jp z,mo_nx              ; sin mascara que aplicar
                ld a,(ix+0)
                ld hl,ac_s0
                sub (hl)
                ld (ac_mt+7),a          ; tira de la ventana de su primera tira
                bit 7,a
                jr nz,mo_neg
                ld hl,ac_ns
                cp (hl)
                jp nc,mo_nx             ; empieza despues de la ventana
                jr mo_in
mo_neg:         add a,(ix+1)            ; tira + tiras: con acarreo y distinta de 0 llega a la ventana
                jp z,mo_nx
                jp nc,mo_nx
mo_in:          ld l,(ix+4)
                ld h,(ix+5)
                ld de,(ac_mbl)
                add hl,de
                ld (ac_mt+3),hl
                ld a,(ix+1)
                ld (ac_mt+6),a
mo_strip:       xor a
                ld (ac_mt+5),a
                ld a,(ac_mt+7)          ; destino de la tira: BACKBUF + ac_rh * tira, o 0 si esta fuera de la ventana
                bit 7,a
                jr nz,mo_out
                ld hl,ac_ns
                cp (hl)
                jr nc,mo_out
                call mk_mul             ; HL = k * ac_rh
                ld de,BACKBUF
                add hl,de
                jr mo_st
mo_out:         ld hl,0
mo_st:          ld (ac_mt+1),hl
mo_run:         ld hl,(ac_mt+3)
                ld b,(hl)               ; longitud
                inc hl
                ld c,(hl)               ; valor
                inc hl
                ld (ac_mt+3),hl
                ld a,(ac_mt+5)
                ld d,a                  ; filas ya hechas
                add a,b
                ld (ac_mt+5),a
                ld hl,(ac_mt+1)
                ld a,h
                or l
                jr z,mo_rn
                ld a,(ix+2)             ; fila de la sala del tramo - fila de la ventana 0
                add a,d
                ld l,a
                ld h,0
                ld de,(ac_y0)
                or a
                sbc hl,de
                ld de,(ac_mt+1)
                call mk_fill
mo_rn:          ld a,(ac_mt+5)
                cp (ix+3)
                jr c,mo_run
                ld hl,ac_mt+7
                inc (hl)
                ld hl,ac_mt+6
                dec (hl)
                jr nz,mo_strip
mo_nx:          ld hl,ac_mt
                dec (hl)
                jp nz,mo_obj
mo_done:        pop ix
                ret

; HL = A * ac_rh (A: 0-8 tiras)
mk_mul:         ld hl,0
                or a
                ret z
                push de
                ld d,0
                ld e,a
                ld a,(ac_rh)
                ld b,e
                ld e,a
mm_l:           add hl,de
                djnz mm_l
                pop de
                ret

; HL = fila de la ventana del primer byte (con signo), DE = tira en BACKBUF, B = longitud, C = valor: lo escribe recortado a la ventana (ac_rh filas)
mk_fill:        bit 7,h
                jr z,mf_p
                ld a,b                  ; empieza antes de la ventana: se quitan las filas de arriba
                add a,l
                ret nc
                ret z
                ld b,a
                ld hl,0
mf_p:           ld a,h
                or a
                ret nz
                ld a,(ac_rh)
                sub l
                ret z
                ret c                   ; empieza despues de la ventana
                cp b
                jr nc,mf_l
                ld b,a                  ; acaba despues: se recorta
mf_l:           add hl,de
                ld a,c
                ld (hl),a
                dec b
                ret z
                ld c,b
                ld b,0
                ld d,h
                ld e,l
                inc de
                ldir
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
                ld a,b                  ; HL = BACKBUF + tira * ac_rh + fila
                push bc
                call mk_mul
                pop bc
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
                push af
                ld a,(ac_rh)
                ld c,a
                ld b,0
                add hl,bc
                ld c,(hl)               ; byte de la tira siguiente
                pop af
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
