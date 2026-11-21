; =====================================================================
;  txtlayer.asm - fase 9: la capa de texto suelto y de cajas encima de la sala, y la ventana movil (SCUMM\V3\FASE3.md, "Fase 9: el dialogo de guardar").
;
;  El dialogo de guardar y cargar de Indy3 (sala 14) pinta los nombres de las partidas con `print` en una posicion (la ranura 1: EV_TEXT [1, x, y, color, banderas, longitud]),
;  rellena filas con `drawBox` (suelta al anfitrion: prog_host) y pone sus botones en x = 208-312: mas alla de los 256 pixeles de la pantalla del ZX81.
;
;  Capa: hasta 16 textos (OV_TXT: 32 bytes cada uno: longitud, x de la sala (palabra), y de pantalla, color de Chroma y 26 caracteres) y 8 cajas (OV_BOX: 8 bytes). Se componen
;  encima de la sala columna a columna (ov_apply, desde hr_makecol: primero las cajas, luego los textos: cada celda de 8 x 1 lleva dos colores, asi que una caja rellena celdas
;  enteras (el borde se redondea a 8 pixeles) y un texto pone sus pixeles con la tinta del color y el papel que ya tenia la celda). La fuente es la de 6 pixeles de la interfaz
;  (TILES; solo mayusculas, 6 pixeles por letra: el SCUMM original usa 8). Un texto en la misma posicion sustituye al anterior (longitud 0 lo borra); una caja borra lo que
;  cubre entera. Todo se borra al cambiar de sala. y es la linea de pantalla (la sala empieza en la 16: HR_TOP).
;
;  Ventana movil: la pantalla del ZX81 enseña 256 de los 320 pixeles de SCUMM. pan_on (cursor a la derecha del todo) la corre 64 pixeles a la derecha; el raton (in_conv) suma
;  pan_px a la x de la escena. cam_update guarda en ov_left el borde izquierdo SIN el desplazamiento (el de SCUMM): las posiciones de la capa se guardan en x de la sala.
; =====================================================================
OV_NT           equ 16
OV_TXT          equ $8800               ; 16 x 32 ($8800-$89FF)
OVT_SZ          equ 32
OVT_MAX         equ 26
OVT_LEN         equ 0
OVT_X           equ 1                   ; palabra
OVT_Y           equ 3
OVT_C           equ 4                   ; byte alto = papel, bajo = tinta: la tinta (codigo de Chroma); el papel sale de la celda
OVT_CH          equ 6
OV_NB           equ 8
OV_BOX          equ $9600               ; 8 x 8 ($9600-$963F)
OV_ZN           equ $96C0               ; fase 9: los objetos (indice desde 0) que un drawObject ha dibujado, en orden: el ultimo queda encima de todo
OV_ZL           equ $96C1               ; hasta 24 ($96C1-$96D8)
OV_ZMAX         equ 24
OV_FLG          equ $9640               ; 128 bytes: 1 en las lineas de la columna en las que un texto ya ha puesto bits (los textos se superponen con OR)
OVB_USED        equ 0
OVB_X0          equ 1                   ; palabra: x de la sala (pixeles) de la primera columna cubierta
OVB_X1          equ 3                   ; palabra: la siguiente a la ultima
OVB_Y0          equ 5
OVB_Y1          equ 6                   ; linea siguiente a la ultima
OVB_C           equ 7                   ; el atributo (papel y tinta iguales)
ov_left         equ SV+202              ; palabra: borde izquierdo de la pantalla de SCUMM en pixeles de la sala (sin el desplazamiento de la ventana)
pan_on          equ SV+204              ; 1: la ventana esta corrida a la derecha
pan_px          equ SV+205              ; palabra: lo que esta corrida (0-64; acotada por el ancho de la sala)
cu_max          equ SV+207              ; palabra: borde izquierdo maximo en pixeles
ov_tx           equ SV+209              ; palabra: x del texto que se anade
ov_ty           equ SV+211
ov_tl           equ SV+212
ov_cnt          equ SV+213              ; temporales de ov_apply
ov_xx           equ SV+214              ; (byte)
ov_fok          equ SV+215              ; fase 10c: 1 si OV_FLG esta a cero (ov_apply no lo borra); lo pone a 0 el texto que marca una linea
ov_g            equ SV+216              ; 3 punteros de glifo (6 bytes) en 216..221
ov_d            equ SV+222              ; 3 desplazamientos (3 bytes)
ov_n            equ SV+225
ov_ink          equ SV+226
ov_ci           equ SV+227              ; linea dentro de la columna
ov_ln           equ SV+228
ov_bx0          equ SV+231              ; palabra: x0 de la caja que se anade (pixeles)
ov_bx1          equ SV+233              ; palabra: x1 (excluida)
ov_cx           equ SV+235              ; palabra: x del primer pixel de la columna que se compone
ov_lo           equ SV+237
ov_hi           equ SV+238
ov_msk          equ SV+239
ov_dc0          equ SV+240              ; columnas sucias de la capa: la primera ($FF: ninguna) y la ultima
ov_dc1          equ SV+241
ov_ts           equ SV+243              ; 10g: palabra: por donde va la lectura de UIBUF al partir un texto largo
ov_rem          equ SV+245              ; 10g: caracteres que faltan por anadir
ov_s            equ SV+247              ; 10g: x del texto mod 8 (donde empieza dentro de su celda)
ov_k            equ SV+246              ; 10g: indice del primer caracter que cae en la columna
OVT_CHK         equ 24                  ; 10g: un texto de mas de 24 caracteres se parte en trozos de 24 (144 pixeles = 18 celdas: cada trozo empieza alineado)
ov_rr2          equ SV+230              ; el ultimo texto que se sustituyo (por turnos)
ov_rr           equ SV+229              ; la ultima caja que se sustituyo (por turnos)

; todo borrado (arranque, reinicio y cambio de sala)
ov_clear:       ld hl,OV_TXT
                ld de,OV_TXT+1
                ld bc,OV_NT*OVT_SZ-1
                ld (hl),0
                ldir
                ld hl,OV_BOX
                ld de,OV_BOX+1
                ld bc,OV_NB*8-1
                ld (hl),0
                ldir
                ld a,$FF
                ld (ov_dc0),a
                xor a
                ld (ov_dc1),a
                ld (pan_on),a
                ld (OV_ZN),a
                ld (ov_uirow),a         ; 10g-3: sala nueva: ninguna fila de la interfaz es del marcador
                ld hl,0
                ld (pan_px),hl
                ret

; A = indice de objeto (desde 0) -> Z si esta en la lista de los de drawObject. Conserva todo menos A y las banderas
ov_inzl:        push bc
                push hl
                ld c,a
                ld a,(OV_ZN)
                or a
                jr z,oiz_n
                ld b,a
                ld hl,OV_ZL
oiz_l:          ld a,(hl)
                cp c
                jr z,oiz_y
                inc hl
                djnz oiz_l
oiz_n:          or 1                    ; NZ
                pop hl
                pop bc
                ret
oiz_y:          xor a                   ; Z
                pop hl
                pop bc
                ret

; A = indice de objeto -> al final de la lista (si ya estaba, se quita de donde estaba; si no cabe, se pierde el mas antiguo)
ov_zpush:       push bc
                push de
                push hl
                ld c,a
                ld a,(OV_ZN)
                ld b,a
                or a
                jr z,ozp_add
                ld hl,OV_ZL
ozp_f:          ld a,(hl)
                cp c
                jr z,ozp_rm
                inc hl
                djnz ozp_f
                jr ozp_add
ozp_rm:         ld d,h                  ; HL = donde esta; B = lo que queda contando este: se cierra el hueco
                ld e,l
                inc hl
                dec b
                jr z,ozp_dn
                push bc
                ld c,b
                ld b,0
                ldir
                pop bc
ozp_dn:         ld hl,OV_ZN
                dec (hl)
ozp_add:        ld a,(OV_ZN)
                cp OV_ZMAX
                jr c,ozp_p
                ld hl,OV_ZL+1           ; lleno: se pierde el primero
                ld de,OV_ZL
                ld bc,OV_ZMAX-1
                ldir
                ld a,OV_ZMAX-1
ozp_p:          ld e,a
                ld d,0
                ld hl,OV_ZL
                add hl,de
                ld (hl),c
                inc a
                ld (OV_ZN),a
                pop hl
                pop de
                pop bc
                ret

; al final de hr_mkdl: los objetos de OV_ZL que se dibujan, en orden, detras de los demas en HR_DLIST (el ultimo de la lista es el que queda encima)
ov_zadd:        ld a,(OV_ZN)
                or a
                ret z
                ld b,a
                ld hl,OV_ZL
oz_l:           push bc
                push hl
                ld a,(hl)
                ld (hv_i),a
                call obj_drawn
                jr nc,oz_n
                ld a,(hv_ndl)
                ld e,a
                ld d,0
                ld hl,HR_DLIST
                add hl,de
                ld a,(hv_i)
                ld (hl),a
                ld hl,hv_ndl
                inc (hl)
oz_n:           pop hl
                inc hl
                pop bc
                djnz oz_l
                ret

; columnas sucias (ov_dc0 .. ov_dc1): A = la primera, B = la ultima. Las recompone hr_objupd (ov_merge) en el siguiente fotograma
ov_mark:        ld hl,ov_dc0
                cp (hl)
                jr nc,omk_a
                ld (hl),a
omk_a:          ld a,b
                ld hl,ov_dc1
                cp (hl)
                jr c,omk_b
                ld (hl),a
omk_b:          ld a,1
                ld (gd_pending),a
                ret

; hr_objupd: las columnas sucias de la capa pasan a las que recompone (HR_DIRTY) y se borran
ov_merge:       ld a,(ov_dc0)
                cp $FF
                ret z
                ld c,a
                ld a,(ov_dc1)
                sub c
                jr c,omg_r
                inc a
                ld b,a                  ; fase 10b: a las columnas sucias (hr.asm, hr_dmark)
                call hr_dmark
omg_r:          ld a,$FF
                ld (ov_dc0),a
                xor a
                ld (ov_dc1),a
                ret

; ---------------------------------------------------------------------
;  Texto: EVARGS = [1, x, y, color, banderas (bit 0: centrado), longitud]; el texto convertido esta en UIBUF
; ---------------------------------------------------------------------
ov_text_add:    ld hl,(EVARGS+10)       ; longitud (tope 48: UIBUF)
                ld a,h
                or a
                jr z,ota_l
                ld l,48
ota_l:          ld a,l
                cp 49
                jr c,ota_ok
                ld a,48
ota_ok:         ld (ov_rem),a
                ld hl,(EVARGS+2)        ; x de la sala = x de pantalla + el borde izquierdo de SCUMM
                ld de,(ov_left)
                add hl,de
                ld a,(EVARGS+8)
                and 1
                jr z,ota_nc
                ld a,(ov_rem)           ; centrado: x - 3 * longitud (10g: 6 pixeles por caracter)
                ld e,a
                add a,a
                add a,e
                ld e,a
                ld d,0
                or a
                sbc hl,de
ota_nc:         ld de,4                 ; 10g: x + 4 exacta (antes + 4 y redondeada a la celda de 8: el cursor, que sigue al nombre a 6 pixeles por letra, quedaba descolocado hasta 4 px)
                add hl,de                ; (el +4 deja el borde de la cuadricula de la lista, x = 8, fuera de la primera celda del texto)
                ld (ov_tx),hl
                ld hl,(EVARGS+4)
                ld a,h
                or a
                ret nz
                ld a,l
                cp 192
                ret nc
                ld (ov_ty),a
                cp 144                  ; 10g-3: en la zona de los verbos (el marcador del boxeo, script 41): a la pantalla de texto de la interfaz
                jp nc,ov_ui_text
                ld a,(ov_rem)
                or a
                ret z                   ; vacio: no pinta nada (como en SCUMM: lo que habia debajo se queda)
                ld hl,UIBUF
                ld (ov_ts),hl
ota_ch:         ld a,(ov_rem)           ; trozos de hasta OVT_CHK caracteres
                cp OVT_CHK+1
                jr c,ota_c1
                ld a,OVT_CHK
ota_c1:         ld (ov_tl),a
                call ota_one
                ld a,(ov_tl)
                ld c,a
                ld b,0
                ld hl,(ov_ts)
                add hl,bc
                ld (ov_ts),hl
                ld a,(ov_rem)
                sub c
                ret z
                ld (ov_rem),a
                ld hl,(ov_tx)
                ld de,OVT_CHK*6
                add hl,de
                ld (ov_tx),hl
                jr ota_ch

; HL = x (pixeles), A = longitud -> A = la columna de su ultimo pixel ((x + 6 * longitud - 1) / 8)
ov_lastc:       push de
                ex de,hl
                ld l,a
                ld h,0
                call mul6hl
                add hl,de
                dec hl
                pop de
                jp ov_col

; un trozo: ov_tl caracteres desde (ov_ts) en (ov_tx, ov_ty) con el color de EVARGS+6
ota_one:        ld ix,OV_TXT            ; el primero libre; si no hay, el mas antiguo (por turnos)
                ld b,OV_NT
                ld iy,0
ota_s:          ld a,(ix+OVT_LEN)
                or a
                jr nz,ota_n
                push ix
                pop iy
                jr ota_put
ota_n:          ld de,OVT_SZ
                add ix,de
                djnz ota_s
                ld a,(ov_rr2)
                inc a
                and OV_NT-1
                ld (ov_rr2),a
                add a,a                 ; * 32
                add a,a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld iy,OV_TXT
                add iy,de
                ld l,(iy+OVT_X)         ; fase 10b: el texto que se pierde deja sus columnas sucias (antes lo tapaba el rango minimo-maximo de hr_objupd)
                ld h,(iy+OVT_X+1)
                call ov_col
                ld c,a
                ld l,(iy+OVT_X)
                ld h,(iy+OVT_X+1)
                ld a,(iy+OVT_LEN)
                call ov_lastc
                ld b,a
                ld a,c
                call ov_mark
ota_put:        ld a,(ov_tl)
                ld (iy+OVT_LEN),a
                ld hl,(ov_tx)
                ld (iy+OVT_X),l
                ld (iy+OVT_X+1),h
                ld a,(ov_ty)
                ld (iy+OVT_Y),a
                ld a,(EVARGS+6)
                and 15
                ld e,a
                ld d,0
                ld hl,ega2chroma
                add hl,de
                ld a,(hl)
                ld (iy+OVT_C),a
                push iy
                pop de
                ld hl,OVT_CH
                add hl,de
                ex de,hl
                ld hl,(ov_ts)
                ld a,(ov_tl)
                ld c,a
                ld b,0
                ldir
                ld hl,(ov_tx)           ; sucias: sus columnas
                call ov_col
                ld c,a
                ld hl,(ov_tx)
                ld a,(ov_tl)
                call ov_lastc
                ld b,a
                ld a,c
                jp ov_mark

; ---------------------------------------------------------------------
;  Caja (drawBox): ARGS = [x, y, x2, y2, color] (palabras; x2 e y2 incluidos)
; ---------------------------------------------------------------------
ov_box_add:     ld hl,(ARGS+2)
                ld a,h
                or a
                ret nz
                ld a,l
                cp 192
                ret nc
                ld (ov_ty),a            ; y0
                cp 144                  ; 10g-3: en la zona de los verbos (las barras del boxeo, script 41): pixeles de la interfaz
                jp nc,ov_ui_box
                ld hl,(ARGS+6)
                ld a,h
                or a
                jr z,oba_y1
                ld l,191
oba_y1:         ld a,l
                cp 192
                jr c,oba_y2
                ld a,191
oba_y2:         inc a                   ; y1 (excluida)
                ld (ov_tl),a
                ld hl,(ARGS)            ; x0 de la sala en pixeles (exacto: el borde de la caja no se redondea)
                ld de,(ov_left)
                add hl,de
                bit 7,h
                jr z,oba_x0
                ld hl,0
oba_x0:         ld (ov_bx0),hl
                ld hl,(ARGS+4)          ; x1 = x2 + 1 (excluida)
                ld de,(ov_left)
                add hl,de
                inc hl
                bit 7,h
                jr z,oba_x1
                ld hl,0
oba_x1:         ld (ov_bx1),hl
                ld de,(ov_bx0)
                or a
                sbc hl,de
                ret z
                ret c                   ; x1 <= x0
                ld a,(ov_tl)
                ld b,a
                ld a,(ov_ty)
                cp b
                ret nc                  ; y0 >= y1
                ld a,(ARGS+8)           ; el atributo: papel = tinta = color de Chroma
                and 15
                ld e,a
                ld d,0
                ld hl,ega2chroma
                add hl,de
                ld a,(hl)
                ld c,a
                add a,a
                add a,a
                add a,a
                add a,a
                or c
                ld (ov_ink),a
                ; lo que la caja cubre entero se borra: textos (x0 <= x, x + 6 * longitud <= x1, y0 <= y, y + 8 <= y1)
                ld ix,OV_TXT
                ld b,OV_NT
obb_t:          ld a,(ix+OVT_LEN)
                or a
                jr z,obb_tn
                ld l,(ix+OVT_X)
                ld h,(ix+OVT_X+1)
                ld de,(ov_bx0)
                push hl
                or a
                sbc hl,de
                pop hl
                jr c,obb_tn             ; x < x0
                ld a,(ix+OVT_LEN)
                ld e,a
                add a,a
                add a,e
                add a,a                 ; 6 * longitud
                ld e,a
                ld d,0
                add hl,de
                ld de,(ov_bx1)
                or a
                sbc hl,de
                jr z,obb_ty
                jr nc,obb_tn            ; x + ancho > x1
obb_ty:         ld a,(ix+OVT_Y)
                ld hl,ov_ty
                cp (hl)
                jr c,obb_tn             ; y < y0
                add a,8
                ld c,a
                ld a,(ov_tl)
                cp c
                jr c,obb_tn             ; y1 < y + 8
                ld (ix+OVT_LEN),0
obb_tn:         ld de,OVT_SZ
                add ix,de
                djnz obb_t
                ; cajas: las que cubre entera se borran; despues, un hueco (o la mas antigua por turnos)
                ld ix,OV_BOX
                ld b,OV_NB
                ld iy,0
obb_b:          ld a,(ix+OVB_USED)
                or a
                jr nz,obb_bu
                push iy
                pop de
                ld a,d
                or e
                jr nz,obb_bn
                push ix
                pop iy
                jr obb_bn
obb_bu:         ld l,(ix+OVB_X0)        ; x0 <= X0 de la vieja
                ld h,(ix+OVB_X0+1)
                ld de,(ov_bx0)
                or a
                sbc hl,de               ; X0 - x0
                jr c,obb_bn
                ld l,(ix+OVB_X1)        ; X1 <= x1
                ld h,(ix+OVB_X1+1)
                ld de,(ov_bx1)
                or a
                sbc hl,de
                jr z,obb_by
                jr nc,obb_bn
obb_by:         ld a,(ix+OVB_Y0)
                ld hl,ov_ty
                cp (hl)
                jr c,obb_bn
                ld a,(ov_tl)
                cp (ix+OVB_Y1)
                jr c,obb_bn
                ld (ix+OVB_USED),0
                push iy
                pop de
                ld a,d
                or e
                jr nz,obb_bn
                push ix
                pop iy
obb_bn:         ld de,8
                add ix,de
                djnz obb_b
                push iy
                pop de
                ld a,d
                or e
                jr nz,obb_set
                ld a,(ov_rr)            ; sin hueco: la mas antigua (por turnos)
                inc a
                and OV_NB-1
                ld (ov_rr),a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld iy,OV_BOX
                add iy,de
                call ov_bake            ; 10g-3: la caja que se pierde se queda pintada en la sala (ScummVM la deja en el bufer de la pantalla)
                ld l,(iy+OVB_X0)        ; fase 10b: la caja que se pierde deja sus columnas sucias
                ld h,(iy+OVB_X0+1)
                call ov_col
                ld c,a
                ld l,(iy+OVB_X1)
                ld h,(iy+OVB_X1+1)
                dec hl
                call ov_col
                ld b,a
                ld a,c
                call ov_mark
obb_set:        ld (iy+OVB_USED),1
                ld hl,(ov_bx0)
                ld (iy+OVB_X0),l
                ld (iy+OVB_X0+1),h
                ld hl,(ov_bx1)
                ld (iy+OVB_X1),l
                ld (iy+OVB_X1+1),h
                ld a,(ov_ty)
                ld (iy+OVB_Y0),a
                ld a,(ov_tl)
                ld (iy+OVB_Y1),a
                ld a,(ov_ink)
                ld (iy+OVB_C),a
                ld hl,(ov_bx0)
                call ov_col
                ld c,a
                ld hl,(ov_bx1)
                dec hl
                call ov_col
                ld b,a
                ld a,c
                jp ov_mark

; 10g-3: IY = caja que sale de la capa: se pinta en el .GFX de la sala (las lineas que se ven), columna a columna, con ov_box_col sobre HR_COLBUF.
; Asi la linea del mapa de viaje (cientos de drawBox de 3 x 3, scripts 88/89) se queda entera, como en el bufer de pantalla de ScummVM, hasta que se recarga la sala
ov_bake:        ld a,(gf_have)
                or a
                ret z
                ld a,(ov_ink)
                push af
                push iy
                pop ix
                ld l,(ix+OVB_X0)
                ld h,(ix+OVB_X0+1)
                call ov_col
                ld (ov_xx),a
obk_l:          ld a,(ov_xx)
                ld l,a
                ld h,0
                ld de,(gf_cols)
                or a
                sbc hl,de
                jr nc,obk_x             ; fuera de la sala
                ld l,a
                ld h,0
                ld (hv_w),hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld (ov_cx),hl
                ex de,hl
                ld l,(ix+OVB_X1)
                ld h,(ix+OVB_X1+1)
                or a
                sbc hl,de
                jr z,obk_x
                jr c,obk_x              ; X1 <= x de la columna: acabada
                call hr_coloff          ; HL = bitmap de la columna desde hv_ytop (la columna no cruza paginas)
                ld a,h
                rlca
                rlca
                rlca
                and 7
                call hr_map
                ld a,h
                and $1F
                or $20
                ld h,a
                ld a,(hv_hh)
                ld c,a
                ld b,0
                push hl
                push bc
                ld de,HR_COLBUF
                ldir
                pop bc
                pop hl
                push hl
                push bc
                call obk_at
                ld de,HR_COLBUF+128
                ldir
                call ov_box_col
                pop bc
                pop hl
                push hl
                push bc
                ex de,hl
                ld hl,HR_COLBUF
                ldir
                pop bc
                pop hl
                call obk_at
                ex de,hl
                ld hl,HR_COLBUF+128
                ldir
                ld hl,ov_xx
                inc (hl)
                jr obk_l
obk_x:          call hr_unmap
                push ix
                pop iy
                pop af
                ld (ov_ink),a
                ret
; HL = bitmap de la columna -> HL = sus atributos (+ hv_lines); conserva BC
obk_at:         ld a,(hv_lines)
                ld e,a
                ld d,0
                add hl,de
                ret

;  10g-3: drawBox y print en la zona de los verbos (y >= 144 de SCUMM). En ScummVM van al bufer de los verbos; aqui: el texto a UIVB (columna x / 8, fila
;  (y - 140) / 8 + 1, como los verbos, en blanco) y las cajas como pixeles de las lineas 144-191 (x * 3 / 4, como las columnas de 6 pixeles; y - 8), que se quedan hasta que
;  hr_ui repinta ese grupo. Antes se vacia lo pendiente de la interfaz (ui_redraw, hr_ui) para que no lo borre despues; ui_redraw lo repinta todo si ha habido cajas.
ov_uib          equ UIV+50              ; 1: hay cajas pintadas en la interfaz
ov_uirow        equ UIV+51              ; bit r: la fila r de UIVB tiene texto del marcador (ui_clear_from no la borra)
ov_ui_text:     call ov_uiflush         ; el resto en el overlay D (ovd_ui.asm)
                ld hl,OVD_UITEXT
                jp call_ovd
ov_ui_box:      call ov_uiflush
                ld a,1
                ld (ov_uib),a
                ld hl,OVD_UIBOX
                jp call_ovd

ov_uiflush:     ld a,(ui_dirty)
                or a
                call nz,ui_redraw
                ld a,(ui_chg)
                or a
                ret z
                xor a
                ld (ui_chg),a
                jp hr_ui

; HL = x en pixeles (con signo) -> A = su columna (x / 8; 0 si es negativo, 255 como mucho)
ov_col:         bit 7,h
                jr z,oc_p
                xor a
                ret
oc_p:           srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                ld a,l
                ret z
                ld a,255
                ret

; ---------------------------------------------------------------------
;  Una columna del mundo (hv_w) con la capa encima de HR_COLBUF (la llama hr_makecol al acabar los objetos)
; ---------------------------------------------------------------------
ov_apply:       ld hl,(hv_w)
                ld a,h
                or a
                ret nz
                ld a,l
                ld (ov_xx),a            ; la columna
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (ov_cx),hl           ; x de su primer pixel
                ld a,(ov_fok)           ; fase 10c: solo si algun texto lo ha marcado (borrarlo eran 2.700 T por columna)
                or a
                jr nz,oa_fk
                ld hl,OV_FLG
                ld de,OV_FLG+1
                ld bc,127
                ld (hl),0
                ldir
                inc a
                ld (ov_fok),a
oa_fk:
                ld ix,OV_BOX
                ld b,OV_NB
oa_b:           ld a,(ix+OVB_USED)
                or a
                jr z,oa_bn
                push bc
                call ov_box_col
                pop bc
oa_bn:          ld de,8
                add ix,de
                djnz oa_b
                ld ix,OV_TXT
                ld b,OV_NT
oa_t:           ld a,(ix+OVT_LEN)
                or a
                jr z,oa_tn
                push bc
                call ov_text_col
                pop bc
oa_tn:          ld de,OVT_SZ
                add ix,de
                djnz oa_t
                ret

; IX = caja, ov_cx = x del primer pixel de la columna: los pixeles de la columna que cubre la caja (mascara); entera: relleno con el atributo; en parte: solo esos pixeles
ov_box_col:     ld l,(ix+OVB_X1)
                ld h,(ix+OVB_X1+1)
                ld de,(ov_cx)
                or a
                sbc hl,de               ; X1 - X0 columna
                ret z
                ret c
                ld a,h
                or a
                jr nz,obc_h8
                ld a,l
                cp 9
                jr c,obc_hs
obc_h8:         ld a,8
obc_hs:         ld (ov_hi),a
                ld l,(ix+OVB_X0)
                ld h,(ix+OVB_X0+1)
                or a
                sbc hl,de               ; X0 - X0 columna (con signo)
                bit 7,h
                jr nz,obc_l0
                ld a,h
                or a
                ret nz
                ld a,l
                cp 8
                ret nc                  ; empieza despues de la columna
                jr obc_ls
obc_l0:         xor a
obc_ls:         ld (ov_lo),a
                ld b,a                  ; mascara = ($FF >> lo) y no ($FF >> hi)
                ld a,$FF
                inc b
obc_s1:         dec b
                jr z,obc_s1e
                srl a
                jr obc_s1
obc_s1e:        ld c,a
                ld a,(ov_hi)
                ld b,a
                ld a,$FF
                inc b
obc_s2:         dec b
                jr z,obc_s2e
                srl a
                jr obc_s2
obc_s2e:        cpl
                and c
                ld c,a                  ; C = mascara
                cp $FF
                jr nz,obc_p
                ld a,(ix+OVB_C)         ; entera
                ld (ov_ink),a
                ld a,(ix+OVB_Y0)
                ld c,(ix+OVB_Y1)
                jp ov_fill
obc_p:          ld a,c
                ld (ov_msk),a
                ld a,(ix+OVB_Y0)        ; en parte: lineas [y0, y1) dentro de [16, 144)
                cp 16
                jr nc,obp_a
                ld a,16
obp_a:          ld b,a
                ld a,(ix+OVB_Y1)
                cp 144
                jr c,obp_c
                ld a,144
obp_c:          sub b
                ret z
                ret c
                ld c,a                  ; lineas
                ld a,b
                sub 16
                ld e,a
                ld d,0
                ld hl,HR_COLBUF+128     ; 10g-3: IY = el ATRIBUTO de la primera linea y el bitmap a -128 (antes IY = bitmap y el atributo a "+128",
                add hl,de               ; que el Z80 lee como -128: las cajas no ponian nunca su color)
                push hl
                pop iy
                ld a,(ix+OVB_C)
                and 15
                ld d,a                  ; D = color
                ld a,(ov_msk)
                ld e,a                  ; E = mascara
                ld b,c
obp_l:          ld a,(iy+0)             ; atributo de la celda
                ld c,a
                rrca
                rrca
                rrca
                rrca
                and 15                  ; papel
                cp d
                jr z,obp_pp
                ld a,c
                and 15                  ; tinta
                cp d
                jr z,obp_ink
                ld a,c                  ; 10g-3: ni papel ni tinta: la tinta de la celda pasa a ser el color de la caja (choque de color) y sus pixeles se pintan;
                and 15                  ; antes pasaban a papel y una caja estrecha (la linea del mapa de viaje: drawBox de 3 x 3) no se veia.
                ld l,a                  ; Si la celda era de un solo color (papel = tinta), su bitmap no significa nada: se borra antes
                ld a,c
                rrca
                rrca
                rrca
                rrca
                and 15
                cp l
                jr nz,obp_k
                ld (iy-128),0
obp_k:          ld a,c
                and $F0
                or d
                ld (iy+0),a
                jr obp_ink
obp_pp:         ld a,e                  ; el color es el papel (o ninguno de los dos): los pixeles pasan a papel
                cpl
                and (iy-128)
                ld (iy-128),a
                jr obp_n
obp_ink:        ld a,e                  ; el color es la tinta: los pixeles pasan a tinta
                or (iy-128)
                ld (iy-128),a
obp_n:          inc iy
                djnz obp_l
                ret

; las lineas de pantalla A (primera) hasta C (la siguiente a la ultima) de la columna, con el atributo ov_ink y el bitmap a 0
ov_fill:        cp 16
                jr nc,of_a
                ld a,16
of_a:           ld b,a
                ld a,c
                cp 144
                jr c,of_c
                ld a,144
of_c:           sub b
                ret z
                ret c
                ld c,a                  ; lineas
                ld a,b
                sub 16                  ; indice en la columna
                ld e,a
                ld d,0
                ld hl,HR_COLBUF+128     ; 10g-3: IY = atributo, bitmap a -128 (ver obp_c)
                add hl,de
                ld a,(ov_ink)
                ld b,c
                push hl
                pop iy
of_l:           ld (iy-128),0
                ld (iy+0),a
                inc iy
                djnz of_l
                ret

ov_ul:          defb 0,0,0,0,0,0,0,$3F  ; subrayado: la ultima linea del glifo de 6 pixeles

; IX = texto; ov_xx = columna. Pinta en HR_COLBUF las 8 lineas del texto que caen en esa columna. 10g: 6 pixeles por caracter desde la x exacta del texto (s = x mod 8 dentro de
; su primera celda): el caracter k ocupa los pixeles s + 6k .. s + 6k + 5 desde el principio de esa celda; en la columna u caen los k con s + 6k - 8u entre -5 y 7 (de uno a tres):
; k0 = (8u - s) / 6 (0 si es negativo) con desplazamiento -((8u - s) mod 6) (o s si u = 0 y s > 0), y los siguientes con + 6 cada uno
ov_text_col:    ld l,(ix+OVT_X)
                ld h,(ix+OVT_X+1)
                ld a,l
                and 7
                ld (ov_s),a
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l                    ; columna del primer pixel
                ld a,(ov_xx)
                sub l
                ret c                   ; la columna esta antes del texto
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl               ; 8u
                ld a,(ov_s)
                ld e,a
                ld d,0
                or a
                sbc hl,de               ; 8u - s
                ld b,0                  ; k0
                bit 7,h
                jr nz,otc_ng
                ld de,6
otc_dv:         or a
                sbc hl,de
                jr c,otc_dd
                inc b
                jr otc_dv
otc_dd:         add hl,de               ; (8u - s) mod 6
                ld a,l
                neg
                jr otc_d0
otc_ng:         ld a,(ov_s)             ; u = 0 y s > 0: el primero va desplazado s a la derecha
otc_d0:         ld (ov_d),a
                ld a,b
                cp (ix+OVT_LEN)
                ret nc                  ; despues del texto
                ld (ov_k),a
                ld e,a
                push bc
                call otc_gp
                pop bc
                ld (ov_g),hl
                ld a,1
                ld (ov_n),a
                ld a,(ov_d)
                add a,6                 ; desplazamiento del segundo
                cp 8
                jr nc,otc_cd            ; no cae en la columna
                ld c,a
                ld a,(ov_k)
                inc a
                cp (ix+OVT_LEN)
                jr nc,otc_cd            ; no hay segundo
                ld e,a
                push bc
                call otc_gp
                pop bc
                ld (ov_g+2),hl
                ld a,c
                ld (ov_d+1),a
                ld a,2
                ld (ov_n),a
                ld a,c
                add a,6                 ; el tercero
                cp 8
                jr nc,otc_cd
                ld c,a
                ld a,(ov_k)
                add a,2
                cp (ix+OVT_LEN)
                jr nc,otc_cd
                ld e,a
                push bc
                call otc_gp
                pop bc
                ld (ov_g+4),hl
                ld a,c
                ld (ov_d+2),a
                ld a,3
                ld (ov_n),a
otc_cd:         ld a,(ov_n)
                or a
                ret z
                ld a,(ix+OVT_C)
                and 15
                ld (ov_ink),a
                xor a
                ld (ov_ln),a
otc_r:          ld a,(ix+OVT_Y)
                ld c,a
                ld a,(ov_ln)
                add a,c                 ; linea de pantalla
                cp 16
                jr c,otc_nx
                cp 144
                jr nc,otc_nx
                sub 16
                ld (ov_ci),a
                call ov_row
otc_nx:         ld hl,ov_ln
                inc (hl)
                ld a,(hl)
                cp 8
                jr c,otc_r
                ret
otc_no:         pop hl
                ret

; IX = texto, E = indice del caracter -> HL = su glifo (el subrayado, el cursor del dialogo de guardar, no esta en la fuente)
otc_gp:         push ix
                pop hl
                ld d,0
                add hl,de
                ld de,OVT_CH
                add hl,de
                ld a,(hl)
                cp '_'
                ld hl,ov_ul
                ret z
                call ascii_glyph
                add a,GLYPH0
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,TILES
                add hl,de
                ret

; la linea ov_ln del texto (ov_n caracteres en ov_g / ov_d) a la linea ov_ci de la columna
ov_row:         ld a,(ov_n)
                ld b,a
                ld c,0                  ; fila de bits
                ld iy,ov_g
                ld hl,ov_d
orw_c:          push hl
                ld a,(ov_ln)
                ld e,a
                ld d,0
                ld l,(iy+0)
                ld h,(iy+1)
                add hl,de
                ld a,(hl)               ; fila del glifo: 6 bits en 5..0
                pop hl
                add a,a
                add a,a                 ; bits 7..2
                ld e,(hl)               ; desplazamiento con signo: >= 0 a la derecha, < 0 a la izquierda
                bit 7,e
                jr nz,orw_l
                inc e
orw_rr:         dec e
                jr z,orw_o
                srl a
                jr orw_rr
orw_l:          ld d,a
                ld a,e
                neg
                ld e,a
                ld a,d
orw_ll:         add a,a
                dec e
                jr nz,orw_ll
orw_o:          or c
                ld c,a
                inc hl
                inc iy
                inc iy
                djnz orw_c
                ld a,c                  ; 10g: una fila sin pixeles del texto no toca el fondo (antes borraba la celda: con el cursor en la celda del borde derecho del cuadro del dialogo se llevaba la linea vertical)
                or a
                ret z
                ld a,(ov_ci)            ; destino: la linea de la columna
                ld e,a
                ld d,0
                ld hl,OV_FLG
                add hl,de
                xor a
                ld (ov_fok),a           ; fase 10c: OV_FLG ya no esta a cero
                ld a,(hl)
                or a
                ld (hl),1
                ld hl,HR_COLBUF
                add hl,de
                jr z,orw_nw
                ld a,(hl)               ; otro texto ya puso bits en esta linea: se suman (el atributo es el del primero)
                or c
                ld (hl),a
                ret
orw_nw:         ld (hl),c
                ld hl,HR_COLBUF+128
                add hl,de
                ld a,(hl)               ; atributo: el papel que ya tenia, la tinta del texto
                and $F0
                ld c,a
                ld a,(ov_ink)
                or c
                ld (hl),a
                ret

; ---------------------------------------------------------------------
;  Ventana movil
; ---------------------------------------------------------------------
; una vez por fotograma, tras mover el cursor: a la derecha del todo se corre; a la izquierda del todo vuelve
pan_update:     ld a,(cur_x)
                cp 232
                jr c,pu_lo
                ld a,1
                ld (pan_on),a
                ret
pu_lo:          cp 100
                ret nc
                xor a
                ld (pan_on),a
                ret

; prog_host: lo que el programa hace de los opcodes que el nucleo deja al anfitrion (A = el opcode): drawBox (3F, 7F, BF, FF)
prog_host:      and $3F
                cp $3F
                ret nz
                jp ov_box_add
