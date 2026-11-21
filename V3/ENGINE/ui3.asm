; =====================================================================
;  ui3.asm - fase 7: interfaz de v3 (residente; se incluye desde scumm.asm). Pantalla D3 (hr.asm): 16 lineas de mensajes arriba (filas de texto 0-1), 128 de sala
;  (2-17) y 48 de interfaz (18-23). La interfaz es una pantalla de texto de 8 filas x 40 columnas de 6 pixeles (UIVB): las filas 0-1 van a las filas 0-1 de la
;  pantalla y las 2-7 a las 18-23 (hu_srow). Los verbos los coloca el script de Indy3 en coordenadas de SCUMM (320 x 200, filas de 8 lineas desde la 144): la columna
;  es x / 8 y la fila de UIVB es (y - 144) / 8 + 1, asi que la frase (y = 144) cae en la fila 1 (la de abajo de los mensajes) y las seis filas de verbos e inventario
;  (152-199) en las 2-7. Mientras hay un mensaje en pantalla (tx_on) la fila 1 es suya y la frase no se ve. El texto de cada verbo se convierte en el overlay B
;  (ovb_vname). Al reves, el raton: cur_x, cur_y en pixeles de la pantalla -> coordenadas de SCUMM (in_conv). Teclado, raton, cursor, pausa y reinicio: in_poll.
;
;  Teclas (ZX81): letras y cifras = la tecla de SCUMM (los verbos de Indy3 usan las letras en minuscula); Intro = clic izquierdo con el cursor activo; ESPACIO = pausa;
;  SHIFT + 5 6 7 8 = mover el cursor (izquierda, abajo, arriba, derecha); SHIFT + ESPACIO = ESC (salir de la escena cortada / boton derecho); SHIFT + X = salir al BASIC;
;  SHIFT + R = reiniciar el juego. SHIFT + S = F5 (guardar y cargar). Con raton Bluetooth (mouse.asm) mueve el cursor y los botones son los clics.
; =====================================================================
UI_COLS         equ 42                  ; columnas de 6 pixeles: 42 * 6 = 252 de los 256 pixeles de la pantalla
UIVB            equ $98F0               ; 8 filas x 42 columnas de codigos de glifo (0 = vacio); hasta $9A3F (UIBUF)
UIV             equ $9A80               ; variables (UIV..UIV+63)
ui_dirty        equ UIV+0               ; 1: hay que volver a componer los verbos
tx_on           equ UIV+1               ; 1: hay un mensaje en pantalla (filas 0-1)
tx_clr          equ UIV+2               ; color del mensaje (atributo)
tx_col          equ UIV+3               ; donde se escribe la siguiente letra del mensaje
tx_row          equ UIV+4
cur_x           equ UIV+5               ; el cursor en pixeles de la pantalla (0-248, 0-184)
cur_y           equ UIV+6
ik_prev         equ UIV+7               ; tecla pulsada en el fotograma anterior (para detectar la pulsacion)
ib_prev         equ UIV+8               ; botones del raton en el anterior
hu_r            equ UIV+9
hu_g            equ UIV+10
hu_src          equ UIV+11              ; palabra
IT_KIND         equ UIV+13              ; suceso de prueba (el arnes lo escribe con TS_POKE): tipo de INEV (1 clic, 2 clic derecho, 3 tecla, 4 ESC, 5 mover, 6 reiniciar)
IT_X            equ UIV+14              ; palabra: x en pixeles de la pantalla
IT_Y            equ UIV+16              ; palabra: y
IT_KEY          equ UIV+18              ; palabra: tecla
MS_BUF          equ UIV+20              ; mouse.asm: 8 bytes
MS_LX           equ UIV+28
MS_LY           equ UIV+29
ui_tmp          equ UIV+30
ui_col          equ UIV+31
ui_len          equ UIV+32
ui_moved        equ UIV+33
ui_chg          equ UIV+34              ; 1: UIVB ha cambiado (o la pantalla se ha borrado): hr_ui tiene que volver a mirarla
ui_dimf         equ UIV+35              ; 10a: el verbo que se escribe esta atenuado (curmode 2): sus letras van a UIVB con el codigo - 128 (80-127)
ui_dimc         equ UIV+36              ; el atributo de los atenuados (ega2chroma[dimcolor del verbo]; Indy3: 8, gris oscuro)
hu_dim          equ UIV+37              ; hu_group: el grupo que se pinta lleva alguna letra atenuada
hu_n            equ UIV+38              ; caracteres del grupo que se pinta (4; el ultimo de cada fila, el 10, tiene 2)
hu_tmp          equ UIV+39              ; 4 codigos: los 2 del ultimo grupo y 2 vacios
HRUI_PREV       equ $DEB0               ; 8 filas x 42 columnas: el codigo que hay pintado en cada celda (en el bloque de atributos: sitio libre; hasta $DFFF)
HU_GL           equ HR_ATT+$1900        ; 4 glifos x 8 lineas
GLYPH0          equ 210                 ; codigos 210-255: la fuente (46 glifos); el 210 es el espacio
ARROW_UP        equ 208
ARROW_DN        equ 209
TILES           equ font_tiles-ARROW_UP*8

                include "../../COMMON/mouse.asm"

; ---------------------------------------------------------------------
;  Puesta en marcha y fotograma
; ---------------------------------------------------------------------
ui_init:        ld hl,UIVB              ; UIVB y las variables, a cero
                ld de,UIVB+1
                ld bc,8*UI_COLS-1
                ld (hl),0
                ldir
                ld hl,UIV
                ld de,UIV+1
                ld bc,63
                ld (hl),0
                ldir
                ld a,124
                ld (cur_x),a
                ld a,64
                ld (cur_y),a
                ld a,$0F
                ld (tx_clr),a
                ld a,1
                ld (ui_dirty),a
                jp cursor_init

; una vez por fotograma, tras los scripts: los verbos si han cambiado, la pantalla de texto y el cursor
ui_frame:       ld a,(ui_dirty)
                or a
                call nz,ui_redraw
                ld a,(ui_chg)
                or a
                jr z,uf_c
                xor a
                ld (ui_chg),a
                call hr_ui              ; (compara 320 celdas: ~25.000 T; solo si algo ha cambiado)
uf_c:           jp cursor_draw

; ---------------------------------------------------------------------
;  Texto: UIVB
; ---------------------------------------------------------------------
; A = ASCII -> A = indice de glifo (0 = espacio)
ascii_glyph:    cp ' '
                jr z,ag_sp
                cp '0'
                jr c,ag_pun
                cp '9'+1
                jr c,ag_dig
                cp 'A'
                jr c,ag_pun
                cp 'Z'+1
                jr c,ag_up
                cp 'a'
                jr c,ag_pun
                cp 'z'+1
                jr nc,ag_pun
                sub 'a'-11
                ret
ag_up:          sub 'A'-11
                ret
ag_dig:         sub '0'-1
                ret
ag_pun:         cp '/'
                jr z,ag_sl
                cp ':'
                jr z,ag_co
                cp '.'
                jr z,ag_do
                cp ','
                jr z,ag_cm
                cp '?'
                jr z,ag_qu
                cp '-'
                jr z,ag_mi
                cp '"'
                jr z,ag_dq
                cp '!'
                jr z,ag_ex
                cp 39
                jr z,ag_ap
ag_sp:          xor a
                ret
ag_sl:          ld a,37
                ret
ag_co:          ld a,38
                ret
ag_do:          ld a,39
                ret
ag_cm:          ld a,40
                ret
ag_qu:          ld a,41
                ret
ag_mi:          ld a,42
                ret
ag_dq:          ld a,43
                ret
ag_ex:          ld a,44
                ret
ag_ap:          ld a,45
                ret

; A = ASCII -> codigo de glifo (los de SCUMM 1-4 son las flechas del inventario)
ui_code:        cp 1
                jr z,uc_up
                cp 3
                jr z,uc_dn
                cp 5
                jr c,uc_bl
                call ascii_glyph
                add a,GLYPH0
                ret
uc_up:          ld a,ARROW_UP
                ret
uc_dn:          ld a,ARROW_DN
                ret
uc_bl:          ld a,GLYPH0
                ret

; borra la pantalla de texto (UIVB) desde la fila A hasta el final
ui_clear_from:  ld c,a                  ; 10g-3: fila a fila; se salta las que tienen texto del marcador (ov_uirow, txtlayer.asm): en ScummVM redibujar
ucf_l:          ld a,c                  ; un verbo solo restaura su rectangulo, asi que lo que el script escribio con print en la zona de los verbos sigue ahi
                cp 8
                ret nc
                ld b,c
                ld a,(ov_uirow)
                inc b
ucf_s:          dec b
                jr z,ucf_t
                rrca
                jr ucf_s
ucf_t:          and 1
                jr nz,ucf_n
                ld a,c
                push bc
                call hu_mul42
                ld de,UIVB
                add hl,de
                ld b,UI_COLS
ucf_z:          ld (hl),0
                inc hl
                djnz ucf_z
                pop bc
ucf_n:          inc c
                jr ucf_l

; ---------------------------------------------------------------------
;  Verbos: se componen de nuevo cuando algun verbo cambia (EV_VERB). Cada verbo de texto visible (id, curmode <> 0, saveid = 0) se escribe en su celda:
;  columna x / 8, fila (y - 144) / 8 + 1 de UIVB.
; ---------------------------------------------------------------------
ui_redraw:      ld a,(ov_uirow)         ; 10g-3: mientras haya filas del marcador (ov_uirow) sus barras se quedan; despues, si ha habido cajas en la
                or a                    ; interfaz (txtlayer.asm, ov_ui_box), se repinta toda (HRUI_PREV a $FF) para quitar lo que quede de ellas
                jr nz,ur_nb
                ld a,(ov_uib)
                or a
                jr z,ur_nb
                xor a
                ld (ov_uib),a
                ld hl,HRUI_PREV
                ld de,HRUI_PREV+1
                ld bc,8*UI_COLS-1
                ld (hl),$FF
                ldir
ur_nb:          xor a
                ld (ui_dirty),a
                inc a
                ld (ui_chg),a
                ld a,(tx_on)
                or a
                ld a,1
                jr z,ur_c
                inc a                   ; con un mensaje, la fila 1 es suya
ur_c:           call ui_clear_from
                ld ix,VERBS+VSZ
                ld b,NVERB-1
ur_l:           push bc
                call ui_verb
                pop bc
                ld de,VSZ
                add ix,de
                djnz ur_l
                ret

; IX = verbo
ui_verb:        ld a,(ix+V_ID)
                or a
                ret z
                ld a,(ix+V_SAVE)
                or a
                ret nz
                ld a,(ix+V_MODE)
                or a
                ret z
                bit 1,(ix+V_FLG)
                ret nz
                ld l,(ix+V_TOP)         ; fila = (top - 144) / 8 + 1 (1-7)
                ld h,(ix+V_TOP+1)
                ld de,-144
                add hl,de
                ret nc                  ; top < 144: no es de la interfaz
                ld a,h
                or a
                ret nz
                ld a,l
                cp 56
                ret nc
                rrca
                rrca
                rrca
                and 31
                inc a
                ld c,a                  ; C = fila de UIVB
                ld a,(tx_on)
                or a
                jr z,uv_r
                ld a,c
                cp 2
                ret c                   ; la fila 1 es del mensaje
uv_r:           xor a                   ; 10a: un verbo atenuado (curmode 2: no se puede pinchar, findVerbAtPos solo acepta curmode 1) se pinta con su dimcolor,
                ld (ui_dimf),a          ; como drawVerb de ScummVM (antes salia como los demas y parecia que el clic fallaba: TALK y TRAVEL en el gimnasio)
                ld a,(ix+V_MODE)
                cp 2
                jr nz,uv_nd
                ld (ui_dimf),a
                ld a,(ix+V_DIM)
                and 15
                ld e,a
                ld d,0
                ld hl,ega2chroma
                add hl,de
                ld a,(hl)
                or a
                jr nz,uv_dc
                ld a,8
uv_dc:          ld (ui_dimc),a
uv_nd:          ld l,(ix+V_LEFT)        ; columna = left / 8
                ld h,(ix+V_LEFT+1)
                bit 7,h
                ret nz
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                ret nz
                ld a,l
                cp UI_COLS
                ret nc
                ld (ui_col),a
                ld a,c                  ; destino = UIVB + UI_COLS * fila + columna
                call hu_mul42
                ld a,(ui_col)
                ld e,a
                ld d,0
                add hl,de
                ld de,UIVB
                add hl,de
                push hl
                push ix
                ld hl,OVB_VNAME
                call call_ovb           ; HL = bytes de UIBUF
                pop ix
                pop de                  ; DE = destino
                ld b,l
                ld a,l
                or a
                ret z
                ld a,(ui_col)
                ld c,a
                ld a,UI_COLS
                sub c
                ld c,a                  ; C = columnas que caben
                ld hl,UIBUF
uvd_l:          ld a,(hl)
                inc hl
                cp $FF
                jr nz,uvd_c
                dec b                   ; $FF y su codigo no se dibujan
                ret z
                inc hl
                dec b
                jr nz,uvd_l
                ret
uvd_c:          push hl
                call ui_code
                ld l,a
                ld a,(ui_dimf)
                or a
                ld a,l
                jr z,uvd_w
                sub 128                 ; atenuado: el mismo glifo con el codigo 80-127 (hr_ui lo pinta con ui_dimc)
uvd_w:          ld (de),a
                inc de
                pop hl
                dec c
                ret z
                djnz uvd_l
                ret

; ---------------------------------------------------------------------
;  Mensajes: el suceso EV_TEXT (EVARGS+0 = 255: borrar; 0: una pagina de PGBUF, EVARGS+4 = color, +8 = longitud)
; ---------------------------------------------------------------------
ui_text_ev:     ld a,1
                ld (ui_chg),a
                ld hl,(EVARGS)
                ld a,h
                or a
                jr nz,ut_clr
                ld a,l
                cp 255
                jr z,ut_clr
                or a
                jr z,ut_msg
                cp 1
                ret nz
                jp ov_text_add          ; fase 9: el texto suelto de print (ranura 1) va a la capa de texto
ut_msg:         ld a,1
                ld (tx_on),a
                ld hl,(EVARGS+4)        ; color EGA del que habla -> tinta Chroma
                ld a,l
                and 15
                ld e,a
                ld d,0
                ld hl,ega2chroma
                add hl,de
                ld a,(hl)
                or a
                jr nz,ut_c
                ld a,$0F
ut_c:           ld (tx_clr),a
                ld hl,(EVARGS+8)        ; longitud
                ld a,h
                or a
                ld a,96
                jr nz,ut_n
                ld a,l
                cp 97
                jr c,ut_n
                ld a,96
ut_n:           or a
                jr z,ut_end
                ld b,a
                ld hl,PGBUF
ut_l:           ld a,(hl)
                inc hl
                push hl
                push bc
                call ut_wrap
                call ut_put
                pop bc
                pop hl
                djnz ut_l
ut_end:         ld a,1
                ld (ui_dirty),a         ; (la fila 1 deja de ser de la frase)
                ret
ut_clr:         xor a
                ld (tx_on),a
                ld (tx_col),a
                ld (tx_row),a
                ld hl,UIVB              ; filas 0 y 1
                ld de,UIVB+1
                ld bc,2*UI_COLS-1
                ld (hl),0
                ldir
                ld a,1
                ld (ui_dirty),a         ; la frase vuelve a verse
                ret

; A = un caracter del mensaje (13: salto de linea)
ut_put:         cp 13
                jr z,ut_nl
                ld c,a
                ld a,(tx_col)
                cp UI_COLS
                jr c,ut_w
                call ut_nl
                ld a,(tx_row)
                cp 2
                ret nc
                xor a
ut_w:           or a
                jr nz,ut_ok
                ld a,c
                cp ' '
                ret z                   ; un espacio al principio de la linea no se escribe
ut_ok:          ld a,(tx_row)
                cp 2
                ret nc
                call hu_mul42
                ld a,(tx_col)
                ld e,a
                ld d,0
                add hl,de
                ld de,UIVB
                add hl,de
                ex de,hl
                ld a,c
                call ui_code
                ld (de),a
                ld hl,tx_col
                inc (hl)
                ret
ut_nl:          xor a
                ld (tx_col),a
                ld hl,tx_row
                inc (hl)
                ret

; partir por palabras: A = el caracter que va a escribirse, HL = el siguiente en PGBUF, B = los que quedan contando este. Si es la primera letra de una palabra que
; no cabe en lo que queda de la fila (y cabe en una fila), salta de linea antes. Conserva A
ut_wrap:        push af
                ld a,(tx_col)
                or a
                jr z,uw_r
                pop af
                push af
                cp ' '
                jr z,uw_r
                cp 13
                jr z,uw_r
                dec hl                  ; HL = este caracter
                ld de,PGBUF
                or a
                sbc hl,de
                add hl,de               ; (conserva HL; Z si es el primero de la pagina)
                jr z,uw_w
                dec hl
                ld a,(hl)
                inc hl
                cp ' '
                jr nz,uw_r              ; sigue una palabra ya empezada
uw_w:           ld c,0                  ; C = letras de la palabra
uw_c:           ld a,(hl)
                cp ' '
                jr z,uw_e
                cp 13
                jr z,uw_e
                inc c
                inc hl
                djnz uw_c
uw_e:           ld a,c
                cp UI_COLS+1
                jr nc,uw_r              ; no cabe ni en una fila entera: se parte donde toque
                ld a,(tx_col)
                add a,c
                cp UI_COLS+1
                jr c,uw_r
                call ut_nl
uw_r:           pop af
                ret

; ---------------------------------------------------------------------
;  hr_ui: pinta UIVB en el bitmap y los atributos (solo los grupos de 4 caracteres que han cambiado desde la ultima vez). Fila r de UIVB -> fila hu_srow(r)
;  de la pantalla. (La fuente: TILES; blanco brillante sobre negro; las filas 0-1 con el color del que habla mientras hay mensaje.)
; ---------------------------------------------------------------------
hr_ui:          push ix
                xor a
                ld (hu_r),a
hu_row:         ld a,(hu_r)
                call hu_mul42
                ld de,UIVB
                add hl,de
                push hl                 ; origen
                ld a,(hu_r)
                call hu_mul42
                ld de,HRUI_PREV
                add hl,de
                ex de,hl                ; DE = lo pintado
                pop hl
                xor a
                ld (hu_g),a
hu_gr:          ld a,(hu_g)             ; 10 grupos de 4 caracteres (3 bytes) y uno de 2 (el byte 30 y la mitad del 31)
                cp 10
                ld a,4
                jr nz,hu_n4
                ld a,2
hu_n4:          ld (hu_n),a
                push hl
                push de
                ld c,a
hu_cmp:         ld a,(de)
                cp (hl)
                jr nz,hu_diff
                inc hl
                inc de
                dec c
                jr nz,hu_cmp
                pop de
                pop hl
                ld a,(hu_n)
                ld c,a
                ld b,0
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                jr hu_next
hu_diff:        pop de
                pop hl
                ldi
                ldi
                ld a,(hu_n)
                cp 2
                jr z,hu_d2
                ldi
                ldi                     ; lo nuevo pasa a lo pintado
hu_d2:          ld (hu_src),hl
                push hl
                push de
                call hu_group
                pop de
                pop hl
hu_next:        ld a,(hu_g)
                inc a
                ld (hu_g),a
                cp 11
                jr nz,hu_gr
                ld a,(hu_r)
                inc a
                ld (hu_r),a
                cp 8
                jr nz,hu_row
                pop ix
                ret

hu_mul42:       ld l,a                  ; A * 42 -> HL (destruye DE)
                ld h,0
                ld e,l
                ld d,h
                add hl,hl
                add hl,hl
                add hl,de               ; 5
                add hl,hl               ; 10
                add hl,hl               ; 20
                add hl,de               ; 21
                add hl,hl               ; 42
                ret

hu_srow:        cp 2                    ; fila de UIVB -> fila de la pantalla (0, 1, 18-23)
                ret c
                add a,16
                ret

; pinta el grupo hu_g de la fila hu_r: los 4 codigos estan antes de (hu_src)
hu_group:       xor a
                ld (hu_dim),a
                ld a,(hu_n)
                cp 2
                ld hl,(hu_src)
                jr z,hg_h
                ld bc,-4
                add hl,bc
                jr hg_go
hg_h:           dec hl                  ; el grupo de 2: sus dos codigos y dos vacios
                dec hl
                ld de,hu_tmp
                ldi
                ldi
                xor a
                ld (de),a
                inc de
                ld (de),a
                ld hl,hu_tmp
hg_go:          ld de,HU_GL
                ld b,4
hg_c:           push bc
                push hl
                ld a,(hl)
                cp ARROW_UP
                jr nc,hg_s
                cp ARROW_UP-128         ; 10a: 80-127 = el glifo + 128, atenuado: el grupo entero (24 pixeles) toma el atributo ui_dimc
                jr c,hg_z
                cp 128
                jr nc,hg_z
                add a,128
                ld hl,hu_dim
                ld (hl),1
                jr hg_s
hg_z:           ld hl,hu_zero
                jr hg_cp
hg_s:           ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                push de
                ld de,TILES
                add hl,de
                pop de
hg_cp:          ld bc,8
                ldir
                pop hl
                inc hl
                pop bc
                djnz hg_c
                ld a,(hu_g)             ; destino: fila de pantalla,                 byte 3 * grupo, linea 0
                ld c,a
                add a,a
                add a,c
                ld l,a
                ld a,(hu_r)
                call hu_srow
                add a,HR_BM>>8
                ld h,a
                ld ix,HU_GL
                ld b,8
hg_l:           ld a,(ix+0)             ; x1 << 2 | x2 >> 4
                add a,a
                add a,a
                ld c,a
                ld a,(ix+8)
                srl a
                srl a
                srl a
                srl a
                or c
                ld (hl),a
                inc hl
                ld a,(ix+8)             ; (x2 & 15) << 4 | x3 >> 2
                and 15
                add a,a
                add a,a
                add a,a
                add a,a
                ld c,a
                ld a,(ix+16)
                srl a
                srl a
                or c
                ld (hl),a
                inc hl
                ld a,(ix+16)            ; (x3 & 3) << 6 | x4
                and 3
                rrca
                rrca
                or (ix+24)
                ld c,a
                ld a,(hu_g)
                cp 10
                jr z,hg_s3              ; el grupo 10 no tiene tercer byte (caeria en la linea siguiente)
                ld (hl),c
hg_s3:          ld de,30
                add hl,de
                inc ix
                djnz hg_l
                ld a,(hu_g)             ; los atributos de esos 3 bytes
                ld c,a
                add a,a
                add a,c
                ld l,a
                ld a,(hu_r)
                call hu_srow
                add a,HR_ATT>>8
                ld h,a
                ld b,8
                call hu_clr
                ld c,a
hg_a:           ld (hl),c
                inc hl
                ld (hl),c
                inc hl
                ld a,(hu_g)
                cp 10
                jr z,hg_a3
                ld (hl),c
hg_a3:          ld de,30
                add hl,de
                djnz hg_a
                ret
; A = atributo del texto de la fila hu_r: blanco brillante, o (filas 0-1 con un mensaje) el color del que habla
hu_clr:         ld a,(hu_r)
                cp 2
                jr nc,hc_w
                ld a,(tx_on)
                or a
                jr z,hc_w
                ld a,(tx_clr)
                ret
hc_w:           ld a,(hu_dim)
                or a
                ld a,$0F
                ret z
                ld a,(ui_dimc)
                ret
hu_zero:        defs 8,0

; ---------------------------------------------------------------------
;  Cursor (el sprite 63: una flecha blanca con borde negro)
; ---------------------------------------------------------------------
cursor_init:    ld a,63
                ld (2100),a
                ld hl,2105
                ld b,8
cin_c:          ld (hl),$F0             ; tinta blanca, papel negro
                inc hl
                djnz cin_c
                ld de,cur_pix
                ld b,8
cin_p:          ld a,(de)
                ld (hl),a
                inc hl
                inc de
                djnz cin_p
                ld de,cur_pix
                ld b,8
cin_m:          ld a,(de)               ; mascara = forma + un borde
                ld c,a
                srl a
                or c
                ld (hl),a
                inc hl
                inc de
                djnz cin_m
                xor a
                ld (2101),a
                ret
cur_pix:        defb $80,$C0,$E0,$F0,$F8,$E0,$B0,$18

; se ve si _cursor.state > 0
cursor_draw:    ld a,63
                ld (2100),a
                ld hl,(CURSTATE)
                xor a
                bit 7,h
                jr nz,cd_s
                ld a,h
                or l
                jr z,cd_s
                ld a,1
cd_s:           ld (2101),a
                ld a,(cur_x)
                add a,32
                ld l,a
                ld a,0
                adc a,0
                ld h,a
                ld (2102),hl
                ld a,(cur_y)
                add a,32
                ld (2104),a
                ret

; ---------------------------------------------------------------------
;  Entrada: una vez por fotograma antes de vm_frame. Deja el suceso en INEV (vm_input.asm) con las coordenadas de SCUMM.
; ---------------------------------------------------------------------
; cur_x, cur_y (pixeles de la pantalla) -> (INEV+1), (INEV+3): en la sala y arriba, x e y tal cual; en la interfaz (y >= 144) x = columna de 6 pixeles * 8 e y + 8
in_conv:        ld a,(cur_y)
                cp 144
                jr nc,ic_if
                ld l,a
                ld h,0
                ld (INEV+3),hl
                ld a,(cur_x)
                ld l,a
                ld a,(pan_on)           ; fase 9: la ventana movil: el cursor es de la pantalla y la x de SCUMM suma lo que esta corrida DE VERDAD (la camara del hardware, no la
                ld de,(pan_px)          ; logica: el scroll tarda unos fotogramas y se pincha donde se ve el boton)
                or d
                or e
                jr z,ic_np
                push hl
                call gf_campx           ; HL = la camara del hardware en pixeles
                ld de,(ov_left)
                or a
                sbc hl,de               ; menos la de SCUMM: lo que esta corrida ahora
                bit 7,h
                jr z,ic_pp
                ld hl,0
ic_pp:          pop de
                add hl,de
                ld de,0
ic_np:          add hl,de
                ld (INEV+1),hl
                ret
ic_if:          or 7                    ; 10g: el clic cae al final de la celda de 8 lineas (y) y de 8 pixeles (x): un verbo cuyo top / left no es multiplo de 8 se pinta en la celda de abajo / de la izquierda y
                add a,8                 ; con y = top de la celda no se acertaba (frases de las conversaciones)
                ld l,a
                ld h,0
                ld (INEV+3),hl
                ld a,(cur_x)
                ld c,0                  ; hr_ui pinta la columna c en el pixel 6 * c (sin margen)
ic_d:           sub 6
                jr c,ic_e
                inc c
                jr ic_d
ic_e:           ld a,c
                cp UI_COLS
                jr c,ic_c
                ld a,UI_COLS-1
ic_c:           ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                set 2,l
                set 1,l
                set 0,l                 ; + 7
                ld (INEV+1),hl
                ret

; el teclado: B = la primera tecla pulsada (ASCII; 0 ninguna; las teclas de letras en minuscula), C = 1 si SHIFT esta pulsado
kbd_scan:       ld c,0
                ld b,0
                ld hl,kbd_tab
                ld d,$FE
ks_row:         ld a,d
                in a,(254)
                cpl
                ld (ui_tmp),a
                ld e,5
ks_key:         ld a,(ui_tmp)
                rrca
                ld (ui_tmp),a
                jr nc,ks_nk
                ld a,(hl)
                or a
                jr nz,ks_has
                ld c,1                  ; (el 0 de la tabla es SHIFT)
                jr ks_nk
ks_has:         ld b,a                  ; la ultima gana si hay varias; vale
ks_nk:          inc hl
                dec e
                jr nz,ks_key
                ld a,d
                rlca
                ld d,a
                cp $FE                  ; tras $7F vuelve a $FE
                jr nz,ks_row
                ret
kbd_tab:        defb 0,'z','x','c','v'          ; $FE
                defb 'a','s','d','f','g'        ; $FD
                defb 'q','w','e','r','t'        ; $FB
                defb '1','2','3','4','5'        ; $F7
                defb '0','9','8','7','6'        ; $EF
                defb 'p','o','i','u','y'        ; $DF
                defb 13,'l','k','j','h'         ; $BF
                defb ' ','.','m','n','b'        ; $7F

; in_poll: sucesos del fotograma -> INEV
in_poll:        ld a,(IT_KIND)          ; suceso de prueba del arnes: sustituye al teclado y al raton
                or a
                jr z,ip_hw
                cp 6
                jp z,restart
                ld c,a
                xor a
                ld (IT_KIND),a
                ld a,(IT_X)
                ld (cur_x),a
                ld a,(IT_Y)
                ld (cur_y),a
                ld hl,(IT_KEY)
                ld (INEV+5),hl
                ld a,c
                jp ip_set
ip_hw:          ld a,(cur_x)            ; 10g-3: la posicion de antes se toma ANTES del raton (antes, despues de ms_poll: mover el raton no era un
                ld h,a                  ; suceso 5, VAR_VIRT_MOUSE no cambiaba hasta el clic y "What is" no sacaba el nombre al pasar por encima)
                ld a,(cur_y)
                ld l,a
                push hl                 ; posicion antes del raton y del teclado
                call ms_poll            ; A = botones del raton (bit 4 izquierdo, bit 5 derecho); mueve cur_x y cur_y
                ld e,a
                push de
                call kbd_scan           ; B = tecla, C = SHIFT
                pop de
                ld a,c
                or a
                jr z,ip_ns
                ld a,b                  ; con SHIFT: 5 6 7 8 mueven el cursor
                cp '5'
                jr z,ip_l
                cp '8'
                jr z,ip_r
                cp '7'
                jr z,ip_u
                cp '6'
                jr nz,ip_ns
                ld a,(cur_y)
                add a,3
                cp 185
                jr nc,ip_moved
                ld (cur_y),a
                jr ip_moved
ip_l:           ld a,(cur_x)
                sub 3
                jr nc,ip_lx
                xor a
ip_lx:          ld (cur_x),a
                jr ip_moved
ip_r:           ld a,(cur_x)
                add a,3
                jr c,ip_moved
                cp 249
                jr nc,ip_moved
                ld (cur_x),a
                jr ip_moved
ip_u:           ld a,(cur_y)
                sub 3
                jr nc,ip_uy
                xor a
ip_uy:          ld (cur_y),a
ip_moved:       ld b,0                  ; (la tecla de movimiento no es una tecla del juego)
ip_ns:          ld a,b                  ; tecla nueva (flanco)
                ld hl,ik_prev
                cp (hl)
                ld (hl),a
                jr nz,ip_kn
                xor a
ip_kn:          ld d,a                  ; D = tecla nueva (0 si es la misma que antes o ninguna)
                ld a,e
                ld hl,ib_prev           ; botones nuevos (flanco)
                ld b,(hl)
                ld (hl),a
                cpl
                ld l,a
                ld a,b
                cpl
                and e
                ld e,a                  ; E = botones recien pulsados  (A = ~prev & actual)
                ld a,l                  ; (no se usa mas)
                ; SHIFT: SPACE = ESC, X = salir, R = reiniciar
                ld a,c
                or a
                jr z,ip_nosh
                ld a,d
                cp ' '
                jr z,ip_esc
                cp 'x'
                jp z,sc_quit_key
                cp 'r'
                jp z,restart
                cp 's'
                jr z,ip_f5
                cp '0'
                jr z,ip_bs
                ld d,0
ip_nosh:        pop hl                  ; posicion de antes: si ha cambiado, el cursor se ha movido
                ld a,(cur_x)
                cp h
                jr nz,ip_mv
                ld a,(cur_y)
                cp l
                jr z,ip_nmv
ip_mv:          ld a,1
                jr ip_mf
ip_nmv:         xor a
ip_mf:          ld (ui_moved),a
                bit 5,e                 ; clic derecho
                jr nz,ip_rc
                bit 4,e                 ; clic izquierdo
                jr nz,ip_lc
                ld a,d
                or a
                jr z,ip_nk
                cp ' '
                jp z,do_pause
                cp 13                   ; Intro: clic izquierdo con el cursor activo
                jr nz,ip_key
                ld hl,(CURSTATE)
                bit 7,h
                jr nz,ip_key
                ld a,h
                or l
                jr z,ip_key
ip_lc:          ld a,1
                jp ip_set
ip_rc:          ld a,2
                jp ip_set
ip_esc:         pop hl
                ld a,4
                jp ip_set
ip_bs:          pop hl                  ; fase 9: SHIFT + 0 (el RUBOUT del ZX81) = borrar (8) en el dialogo de guardar
                ld hl,8
                ld (INEV+5),hl
                ld a,3
                jp ip_set
ip_f5:          pop hl                  ; fase 9: SHIFT + S = F5 (la tecla 319 que abre el dialogo de guardar y cargar de Indy3: el script 8 la manda al 9)
                ld hl,319
                ld (INEV+5),hl
                ld a,3
                jp ip_set
ip_key:         ld l,d
                ld h,0
                ld (INEV+5),hl
                ld a,3
                jp ip_set
ip_nk:          ld a,(ui_moved)
                or a
                ret z
                ld a,5
ip_set:         ld (INEV),a
                cp 1
                jr z,ip_pos
                cp 5
                ret nz
ip_pos:         jp in_conv

ega2chroma:     defb 0,1,4,5,2,3,6,7,8,9,12,13,10,11,14,15
font_tiles:     incbin "font_tiles.bin"         ; TOOLS/gen_font3.py: los codigos 208-255 (384 bytes)
