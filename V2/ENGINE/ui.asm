; ---------------------------------------------------------------------------------------------------------------
;  Interfaz del juego (la parte de ScummEngine_v2: verbos, linea de frase, cursorCommand). Se incluye desde scumm.asm.
;
;  Pantalla de 24 filas (las 16 primeras son la sala): fila 16 la frase, filas 17-19 los verbos (en el original las
;  filas 19-21 de 25), 20-21 el inventario (todavia no) y 20-23 el texto de los mensajes, que tapa al inventario
;  mientras esta en pantalla. Las columnas de los verbos se reducen de 40 a 32: col = (x * 13 + 4) / 16, y en esa zona se escriben etiquetas
;  cortas (ui_short); la frase lleva el texto completo.
;
;  Los verbos los crean los scripts con o2_verbOps (el nucleo los pasa al programa por HOSTVEC: host_ops).
; ---------------------------------------------------------------------------------------------------------------
UI_VT           equ $8840               ; 15 verbos de 16 bytes: id (0 = libre), columna, fila, modo, texto (11 + 0)
VT_SIZE         equ 16
NVERBS          equ 15
UI_COLS         equ 40                  ; la zona de abajo es de 40 columnas (como el original): se pinta en un bufer virtual (UIVB, de la fila UI_R0 a la 23) y la
UI_R0           equ 16                  ; pantalla muestra 32 de ellas desde UI_OFF (0 u 8); el cursor en un borde cambia de ventana (ui_scroll)
UIVB            equ $9900
; color de cada caracter de las filas 1-3 de la zona (los verbos; la fila 0 no se usa), valor XOR $0F del atributo de Chroma (0 = blanco brillante $0F, la botonera de siempre;
; 1 = $0E amarillo: el verbo bajo el cursor, hicolor de ScummVM (_hiLiteColorVerbArrow = 14); 7 = $08 gris: verbo en modo 2, dimcolor 8). hrui.asm lo pasa a los
; atributos de cada celda de 8 pixeles (OR de los dos caracteres que toca). UI_HOV (detras) = verbo bajo el cursor. Sitio libre, fuera de lo que se guarda
UIAT            equ $9A40
UI_HOV          equ UIAT+160

; ---- A = ranura -> IX
ui_entry:       ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,UI_VT
                add hl,de
                push hl
                pop ix
                ret

ui_init:        ld hl,UI_DIRTY
                ld de,UI_DIRTY+1
                ld bc,UI_VT+NVERBS*VT_SIZE-UI_DIRTY-1
                ld (hl),0
                ldir
                ld a,1
                ld (UI_CURSOR),a
                ld hl,UIVB
                ld a,BLANK
                ld bc,0+(24-UI_R0)*UI_COLS-1
                jp ui_fill

; ------------------------------------------------------------------------------------------ cursorCommand
; ARGS: palabra; el byte alto es el estado de usuario (ver USERSTATE_* de ScummVM)
ui_cursorcmd:   ld a,(ARGS)             ; el byte bajo, si no es 0, es VAR_CURSORSTATE (variable 21)
                or a
                jr z,uc0
                ld l,a
                ld h,0
                ld (VAR_CURSORSTATE),hl
uc0:            ld a,(ARGS+1)
                ld b,a
                bit 2,a                 ; USERSTATE_SET_IFACE
                jr z,uc1
                and $E0
                ld (UI_IFACE),a
                ld a,7
                ld hl,UI_DIRTY
                or (hl)
                ld (hl),a
uc1:            bit 1,b                 ; USERSTATE_SET_CURSOR
                ret z
                ld a,b
                and $10
                jr z,uc2
                ld a,1
uc2:            ld (UI_CURSOR),a
                ret

; --------------------------------------------------------------------------------------------- verbOps
; ARGS: subcodigo; 0: borrar (ranura); $FF: verbo, modo; otro: es el verbo y siguen x, y, ranura, prep y la cadena (STRP)
ui_verbops:     ld a,(ARGS)
                or a
                jp z,uv_del
                cp $FF
                jp z,uv_mode
                ld a,(ARGS+6)           ; ranura
                cp NVERBS
                ret nc
                call ui_entry
                ld a,(ARGS)
                ld (ix+0),a
                ld hl,(ARGS+2)          ; columna = (x * PF_COLMUL + PF_COLADD) >> PF_COLSHIFT (perfil del juego)
                ld h,0
                ld d,h
                ld e,l
                ld hl,0
                ld a,(PF_COLMUL)
                ld b,a
uv_m:           add hl,de
                djnz uv_m
                ld a,(PF_COLADD)
                ld e,a
                ld d,0
                add hl,de
                ld a,(PF_COLSHIFT)
                ld b,a
uv_s:           srl h
                rr l
                djnz uv_s
                ld a,l
                cp UI_COLS
                jr c,uv_c
                ld a,UI_COLS-1
uv_c:           ld (ix+1),a
                ld a,(ARGS+4)           ; fila = y - PF_ROWSUB
                ld hl,PF_ROWSUB
                sub (hl)
                ld (ix+2),a
                ld (ix+3),1
                ld hl,(STRP)
                ld c,(ix+1)             ; los espacios (y '@') del principio del texto se quitan y la columna avanza lo mismo: cabe en los 11 caracteres
uv_sk:          ld a,(hl)               ; (el verbo de Dave es "        Dave ")
                cp ' '
                jr z,uv_sp
                cp '@'
                jr nz,uv_go
uv_sp:          inc hl
                inc c
                jr uv_sk
uv_go:          ld a,c
                cp UI_COLS
                jr c,uv_ok
                ld a,UI_COLS-1
uv_ok:          ld (ix+1),a
                push ix
                pop de
                ld bc,4
                ex de,hl
                add hl,bc
                ex de,hl                ; DE = texto del verbo
                ld b,11
uv_t:           ld a,(hl)
                or a
                jr z,uv_te
                ld (de),a
                inc hl
                inc de
                djnz uv_t
uv_te:          xor a
                ld (de),a
uv_d:           ld a,(UI_DIRTY)
                or 3
                ld (UI_DIRTY),a
                ret
uv_del:         ld a,(ARGS+2)
                cp NVERBS
                ret nc
                call ui_entry
                ld (ix+0),0
                jr uv_d
uv_mode:        ld a,(ARGS+2)           ; verbo
                call ui_find
                ret nc
                ld a,(ARGS+4)
                ld (ix+3),a
                ld a,(UI_DIRTY)
                or 1
                ld (UI_DIRTY),a
                ret

; IX = verbo -> HL = lo que se escribe en la zona de verbos (con 40 columnas siempre el texto completo: ya no hay etiquetas cortas). Conserva BC y DE
ui_label:       push ix
                pop hl
                inc hl
                inc hl
                inc hl
                inc hl
                ret
; id de verbo y etiqueta (Maniac Mansion: Push 9, Pull 10, Give 3, Open 1, Close 2, Read 12, Walk to 13, Pick up 14, What is 15,
; Unlock 8, New kid 7, Use 11, Turn on 4, Turn off 5, Fix 6)

; A = identificador de verbo -> IX = su ranura, carry si existe
ui_find:        or a
                ret z
                push bc                 ; conserva BC y DE
                push de
                ld c,a
                ld ix,UI_VT
                ld b,NVERBS
                ld de,VT_SIZE
uf_l:           ld a,(ix+0)
                cp c
                jr z,uf_ok
                add ix,de
                djnz uf_l
                pop de
                pop bc
                or a
                ret
uf_ok:          pop de
                pop bc
                scf
                ret

; drawSentence
ui_sentence:    ld a,(UI_DIRTY)
                or 2
                ld (UI_DIRTY),a
                ret

; ------------------------------------------------------------------------------------------------ pantalla
; cada fotograma, fuera de los scripts
ui_update:      call ui_hover
                ld hl,VAR_SENTENCE_VERB           ; si cambia la frase, se vuelve a escribir
                ld de,UI_PREV
                ld b,8
uu_c:           ld a,(de)
                cp (hl)
                jr nz,uu_ch
                inc hl
                inc de
                djnz uu_c
                jr uu_d
uu_ch:          ld hl,VAR_SENTENCE_VERB
                ld de,UI_PREV
                ld bc,8
                ldir
                ld a,(UI_DIRTY)
                or 2
                ld (UI_DIRTY),a
uu_d:           ld a,(VARS)             ; otro protagonista: otro inventario
                ld hl,UI_PEGO
                cp (hl)
                jr z,uu_e
                ld (hl),a
                xor a
                ld (UI_INVO),a
                ld a,(UI_DIRTY)
                or 4
                ld (UI_DIRTY),a
uu_e:           ld a,(UI_DIRTY)
                or a
                ret z
                ld b,a
                xor a
                ld (UI_DIRTY),a
                push bc
                bit 0,b
                call nz,ui_draw_verbs
                pop bc
                push bc
                bit 1,b
                call nz,ui_draw_sentence
                pop bc
                bit 2,b
                jr z,uu_blit
                ld a,(hv_top)           ; con el texto arriba el inventario no se tapa nunca
                or a
                jr nz,uu_i
                ld a,(tx_on)            ; mientras hay un mensaje el inventario espera (el texto ocupa las filas 20-23)
                or a
                jr nz,uu_w
uu_i:           call ui_draw_inv
                jr uu_blit
uu_w:           ld a,(UI_DIRTY)
                or 4
                ld (UI_DIRTY),a
uu_blit:        ret                     ; (hr_ui, hrui.asm, pinta UIVB y los mensajes directamente)

; columna de texto (6 pixeles cada una, a partir del pixel 4) de la coordenada x de la pantalla A -> A (0-39)
ui_xcol:        sub 4
                jr nc,ux1
                xor a
ux1:            ld l,0
ux2:            sub 6
                jr c,ux3
                inc l
                jr ux2
ux3:            ld a,l
                cp UI_COLS
                ret c
                ld a,UI_COLS-1
                ret

; HL = direccion de pantalla de la fila A, columna 0
ui_row:         sub UI_R0
                call hu_mul40           ; * 40 (hrui.asm)
                ld de,UIVB
                add hl,de
                ret

ui_clear_row:   call ui_row
                ld a,BLANK
                ld bc,UI_COLS-1
ui_fill:        ld (hl),a               ; A en BC + 1 bytes desde HL
                ld d,h
                ld e,l
                inc de
                ldir
                ret

; ---- los verbos
ui_draw_verbs:  ld a,(PF_VROW)          ; las 3 filas: en blanco, colores a normal (UIAT) y todo se vuelve a pintar (HRUI_PREV: el color solo no cambia los codigos)
                call ui_row
                ld a,BLANK
                call udv_f              ; (ldir deja HL 119 bytes mas alla)
                ld de,HRUI_PREV-UIVB-(3*UI_COLS-1)
                add hl,de
                ld a,$FF
                call udv_f
                ld de,UIAT-HRUI_PREV-(3*UI_COLS-1)
                add hl,de
                xor a
                call udv_f
                ld a,(UI_IFACE)
                bit 7,a
                ret z
                ld ix,UI_VT
                ld b,NVERBS
udv_l:          push bc
                ld a,(ix+0)
                or a
                call nz,ui_draw_verb
                ld de,VT_SIZE
                add ix,de
                pop bc
                djnz udv_l
                ret
udv_f:          ld bc,3*UI_COLS-1       ; A en las 3 filas de verbos desde HL
                jr ui_fill

; verbo bajo el cursor (UI_HOV, 0 = ninguno): si cambia, los verbos se vuelven a escribir (checkV2MouseOver de ScummVM)
ui_hover:       call ui_vhit
                ld hl,UI_HOV
                cp (hl)
                ret z
                ld (hl),a
                ld hl,UI_DIRTY
                set 0,(hl)
                ret

; IX = verbo: se escribe hasta donde empieza el siguiente de su fila (o hasta el borde)
ui_draw_verb:   ld a,(ix+3)
                or a
                ret z
                ld a,(ix+2)
                ld hl,PF_VROW
                sub (hl)
                ret c
                cp 3
                ret nc
                ld c,UI_COLS            ; limite: la columna del verbo mas cercano a la derecha en la misma fila
                ld iy,UI_VT
                ld b,NVERBS
udw_l:          ld a,(iy+0)
                or a
                jr z,udw_n
                ld a,(iy+3)
                or a
                jr z,udw_n
                ld a,(iy+2)
                cp (ix+2)
                jr nz,udw_n
                ld a,(iy+1)
                cp (ix+1)
                jr c,udw_n
                jr z,udw_n
                cp c
                jr nc,udw_n
                ld c,a
udw_n:          push bc
                ld bc,VT_SIZE
                add iy,bc
                pop bc
                djnz udw_l
                ld a,c
                sub (ix+1)
                ld c,a                  ; C = sitio disponible
                call ui_label           ; longitud del texto sin los '@' del final -> E
                ld e,0
                ld d,0
                push hl
udw_t:          ld a,(hl)
                or a
                jr z,udw_te
                inc hl
                inc d
                cp '@'
                jr z,udw_t
                ld e,d
                jr udw_t
udw_te:         pop hl                  ; HL = texto
                ld a,e
                cp c
                jr c,udw_m
                ld a,c
udw_m:          ld b,a                  ; B = caracteres a escribir
                ld a,(UI_HOV)           ; C = color (UIAT): 1 el verbo bajo el cursor, 7 un verbo en modo 2 (atenuado), 0 el normal
                cp (ix+0)
                ld c,0
                jr nz,udw_k
                inc c
udw_k:          ld a,(ix+3)
                cp 2
                jr nz,udw_a
                ld c,7
udw_a:          push hl
                push bc
                ld a,(ix+2)
                call ui_row
                ld e,(ix+1)
                ld d,0
                add hl,de
                ex de,hl                ; DE = pantalla
                pop bc
                pop hl
udw_c:          ld a,b
                or a
                ret z
                ld a,(hl)
                inc hl
                cp '@'
                jr nz,udw_p
                ld a,' '
udw_p:          call put_chr
                push hl
                ld hl,UIAT-UIVB-1
                add hl,de
                ld (hl),c
                pop hl
                dec b
                jr udw_c

; ---- la frase: verbo, objeto, preposicion, objeto
ui_draw_sentence:
                ld a,(PF_SROW)
                call ui_clear_row
                ld a,(UI_IFACE)
                bit 5,a
                ret z
                ld a,(PF_SROW)
                call ui_row
                ex de,hl
                ld b,UI_COLS            ; B = sitio que queda
                ld a,(VAR_SENTENCE_VERB)          ; verbo
                call ui_find
                jr nc,us_o1
                push ix
                pop hl
                ld a,l
                add a,4
                ld l,a
                jr nc,us_v
                inc h
us_v:           call us_text
us_o1:          ld hl,(VAR_SENTENCE_OBJECT1)         ; objeto 1
                call us_obj
                ld hl,(VAR_SENTENCE_PREPOSITION)         ; preposicion
                ld a,h
                or a
                jr nz,us_o2
                ld a,l
                or a
                jr z,us_o2
                cp 5
                jr nc,us_o2
                ld hl,(PF_PREPS)
                push de                 ; DE es el sitio de la pantalla donde sigue la frase
                ld de,PROF
                add hl,de
                pop de
                dec a
                ld c,a
us_p:           ld a,c
                or a
                jr z,us_pf
                dec c
us_ps:          ld a,(hl)
                inc hl
                or a
                jr nz,us_ps
                jr us_p
us_pf:          call us_text
us_o2:          ld hl,(VAR_SENTENCE_OBJECT2)         ; objeto 2
                jp us_obj


; HL = objeto: un espacio y su nombre
us_obj:         ld a,h
                and $80
                ret nz
                ld a,h
                or l
                ret z
                push bc
                push de
                call ui_objname
                pop de
                pop bc
                ret c
                ld a,b
                or a
                ret z
                ld a,' '
                push bc
                call put_chr
                pop bc
                dec b
                ld hl,UI_NAME
; HL = cadena acabada en 0: se escribe en DE mientras quede sitio (B)
us_text:        ld a,b
                or a
                ret z
                ld a,(hl)
                or a
                ret z
                cp '@'
                ret z
                inc hl
                push hl
                push bc
                call put_chr
                pop bc
                pop hl
                dec b
                jr us_text

; ---- nombre de un objeto: HL = objeto -> UI_NAME; carry si no tiene
ui_objname:     ld de,NOBJ
                push hl
                or a
                sbc hl,de
                pop hl
                jp nc,on_none
                push hl
                call nm_lookup          ; nombre cambiado por setObjectName
                jr nc,on_orig
                pop hl
                push ix
                pop hl
                inc hl
                inc hl
                jr on_c0
on_orig:        pop hl
                ld a,h
                or a
                jr nz,on_obj
                ld a,(ACTN)             ; ids de actor: los del perfil (Zak: 14); los demas son objetos
                cp l
                jr c,on_obj
                jr z,on_obj
                ld e,l                  ; un actor: su nombre esta en el script que lo puso (pagina y direccion)
                ld d,0
                ld hl,ACTNAME
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                jr z,on_none
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                push de
                call map_page
                pop hl
                jr on_c0
on_obj:         ld e,l
                ld d,h
                add hl,hl
                add hl,de
                ld de,ODIRBUF
                add hl,de
                ld a,(hl)
                or a
                jr z,on_none
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                push de
                call map_page
                pop hl                  ; HL = bloque del objeto; el nombre esta en bloque + (bloque + 14)
                ld e,l
                ld d,h
                ld bc,14
                add hl,bc
                ld c,(hl)
                ld b,0
                ex de,hl
                add hl,bc               ; HL = nombre
on_c0:          ld de,UI_NAME
                ld b,31
on_c:           ld a,(hl)
                inc hl
                or a
                jr z,on_end
                ld c,a
                and $7F
                cp 32
                jr nc,on_ok
                ld a,' '
on_ok:          cp 127
                jr c,on_p
                ld a,' '
on_p:           ld (de),a
                inc de
                dec b
                jr z,on_end
                bit 7,c                 ; el bit 7: el caracter va seguido de un espacio
                jr z,on_c
                ld a,' '
                ld (de),a
                inc de
                dec b
                jr nz,on_c
on_end:         xor a
                ld (de),a
                ld a,(UI_NAME)
                or a
                jr z,on_none
                or a
                ret
on_none:        scf
                ret

; ---- codigos de texto 5 y 6 de los mensajes (convertVerbMessage / convertNameMessage de ScummVM). Entrada: C = el codigo (5 o 6), CMVAR = la variable,
;      DE = destino en el bufer de mensajes (convert_msg, game.asm). Salida: DE avanzado con el nombre; ERR si el bufer se llena. Conserva BC y HL.
;      El valor 0 (o sin nombre) no da nada. Los nombres se copian tal cual con la conversion de on_c (el bit 7 = un espacio detras)
ui_cmname:      push bc
                push hl
                push de
                ld a,(CMVAR)
                call read_var           ; BC = valor
                ld a,b
                or c
                jr z,cmn_zero
                ld hl,4
                add hl,sp
                ld a,(hl)               ; el codigo (el C guardado)
                ld h,b
                ld l,c
                call ui_nameof          ; HL = verbo / objeto o actor -> UI_NAME (carry si no tiene); mueve la ventana de datos
                push af
                ld a,(CUR)              ; y la cadena del script sigue en su pagina: se vuelve a mapear
                call slot_addr
                ld de,4
                add hl,de
                ld a,(hl)
                call map_page
                pop af
                pop de
                jr c,cmn_fin
                ld hl,UI_NAME
cmn_l:          ld a,(hl)
                or a
                jr z,cmn_fin
                inc hl
                call emit_a
                ld a,(ERR)
                or a
                jr z,cmn_l
                jr cmn_fin
cmn_zero:       pop de
cmn_fin:        pop hl
                pop bc
                ret

; ---- no arrancar el script E si la sala es la del perfil (PF_NOSTART, startScript): Z si no se arranca (conserva DE)
ui_nostart:     ld hl,PF_NOSTART
                ld b,4
uns_l:          ld a,(hl)
                inc hl
                or a
                jr z,uns_n
                cp e
                jr nz,uns_n
                ld a,(CURROOM)
                cp (hl)
                ret z
uns_n:          inc hl
                djnz uns_l
                or 1
                ret

; ---- codigos de texto 5 y 6 de los mensajes (convert_msg, game.asm): A = 5 verbo / 6 objeto o actor, HL = su valor -> UI_NAME; carry si no tiene
ui_nameof:      cp 5
                jp nz,ui_objname        ; convertNameMessage: getObjOrActorName
                ld a,h                  ; convertVerbMessage: el texto del verbo con ese id (el de la ranura, de hasta 11 caracteres)
                or a
                jr nz,on_none
                ld a,l
                call ui_find
                jr nc,on_none
                push ix
                pop hl
                ld de,4
                add hl,de
                ld de,UI_NAME
                ld bc,12
                ldir
                ld a,(UI_NAME)
                or a
                jr z,on_none
                ret

; ---- clic en la parte de abajo de la pantalla (cur_y >= 128): fila 16 frase, 17-19 verbos
ui_hrow:        ld a,(UI_CURSOR)        ; C = fila del cursor; Z si no hay cursor (o la fila 0)
                or a
                ret z
                ld a,(cur_y)
                srl a
                srl a
                srl a
                ld c,a
                ret
ui_click:       call ui_hrow
                ret z
                ld hl,PF_SROW
                cp (hl)
                jr nz,uk_v
                ld a,5                  ; zona de la frase
                ld hl,0
                jr uk_set
uk_v:           ld hl,PF_VROW
                sub (hl)
                ret c
                cp 3
                jp nc,uk_inv
                call ui_vhit
                ld l,a
                ld h,0
                ld a,1                  ; zona de verbos (HL = verbo, 0 si no hay)
                jr uk_set
; A = el verbo clicable (modo 1) bajo el cursor, 0 si no hay (o el cursor no esta en las filas de los verbos)
ui_vhit:        call ui_hrow
                jr z,uk_nv
                ld a,c
                ld hl,PF_VROW
                sub (hl)
                cp 3
                jr nc,uk_nv
                ld a,(cur_x)
                call ui_xcol
                ld b,a                  ; columna
                ld ix,UI_VT
                ld d,NVERBS
uk_l:           ld a,(ix+0)
                or a
                jr z,uk_n
                ld a,(ix+3)
                cp 1
                jr nz,uk_n
                ld a,(ix+2)
                cp c
                jr nz,uk_n
                ld a,b                  ; columna - izquierda dentro del texto completo (con sus '@')
                sub (ix+1)
                jr c,uk_n
                ld e,a
                call ui_label           ; solo cuenta el texto visible: hay un caracter que no es relleno ('@' o espacio) desde ahi
                ld a,e
                or a
                jr z,uk_sc
uk_len:         ld a,(hl)
                or a
                jr z,uk_n
                inc hl
                dec e
                jr nz,uk_len
uk_sc:          ld a,(hl)
                or a
                jr z,uk_n
                cp '@'
                jr z,uk_nx
                cp ' '
                jr nz,uk_hit
uk_nx:          inc hl
                jr uk_sc
uk_hit:         ld a,(ix+0)
                ret
uk_n:           push de
                ld de,VT_SIZE
                add ix,de
                pop de
                dec d
                jr nz,uk_l
uk_nv:          xor a
                ret
uk_set:         ld (INP_AREA),a
                ld (INP_VAL),hl
                ld a,1
                ld (INP_FLAG),a
                ret

; ---------------------------------------------------------------------------------------------------- inventario
; A = numero de objetos del protagonista (los que tienen su numero de actor como dueno), en el orden de las ranuras de INVSL
ui_inv_count:   push bc                 ; conserva BC (los llamadores comparan despues con B)
                ld a,(VARS)
                ld c,a
                ld d,0
                ld hl,INVSL
                ld b,NINV
uic_l:          push hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                call inv_own
                pop hl
                inc hl
                inc hl
                cp c
                jr nz,uic_n
                inc d
uic_n:          djnz uic_l
                pop bc
                ld a,d
                ret

; A = n (desde 1) -> HL = el n-esimo objeto del protagonista por orden de ranura (0 si no hay)
ui_inv_find:    ld d,a
                ld a,(VARS)
                ld c,a
                ld hl,INVSL
                ld b,NINV
uif_l:          push hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                push hl
                call inv_own
                pop hl
                cp c
                jr nz,uif_n
                dec d
                jr z,uif_f
uif_n:          pop hl
                inc hl
                inc hl
                djnz uif_l
                ld hl,0
                ret
uif_f:          pop de
                ret

; HL = objeto -> A = su dueno ($FF si el objeto es 0)
inv_own:        ld a,h
                or l
                jr nz,io_1
                ld a,$FF
                ret
io_1:           push de
                ld de,OBJOWN
                add hl,de
                pop de
                ld a,(hl)
                ret

ui_draw_inv:    ld a,(PF_IROW)
                call ui_clear_row
                ld a,(PF_IROW)
                inc a
                call ui_clear_row
                ld a,(UI_IFACE)
                bit 6,a
                ret z
                xor a
                ld (UI_TMP),a
udi_l:          ld a,(UI_INVO)
                ld hl,UI_TMP
                add a,(hl)
                inc a
                call ui_inv_find
                ld a,h
                or l
                jr z,udi_arrows
                call ui_objname
                jr c,udi_n
                ld a,(UI_TMP)
                srl a
                ld hl,PF_IROW
                add a,(hl)
                call ui_row
                ld a,(UI_TMP)
                and 1
                ld de,0
                ld b,18                 ; nombres: columna izquierda 0-17, flechas en la 19, columna derecha 21-39
                jr z,udi_c
                ld de,21
                ld b,19
udi_c:          add hl,de
                ex de,hl
                ld hl,UI_NAME
                call us_text
udi_n:          ld hl,UI_TMP
                inc (hl)
                ld a,(hl)
                cp 4
                jr c,udi_l
udi_arrows:     ld a,(UI_INVO)
                or a
                jr z,udi_dn
                ld a,(PF_IROW)
                call ui_row
                ld de,19
                add hl,de
                ld (hl),ARROW_UP
udi_dn:         ld a,(UI_INVO)
                add a,4
                ld b,a
                call ui_inv_count
                cp b
                ret z
                ret c
                ld a,(PF_IROW)
                inc a
                call ui_row
                ld de,19
                add hl,de
                ld (hl),ARROW_DN
                ret

; clic en las filas 20-21: un objeto (columnas 0-14 y 17-31) o una flecha (15-16)
uk_inv:         ld a,c
                ld hl,PF_IROW
                sub (hl)
                ret c
                cp 2
                ret nc
                ld a,(UI_IFACE)
                bit 6,a
                ret z
                ld a,(cur_x)
                call ui_xcol
                cp 18
                jr c,uki_l
                cp 21
                jr c,uki_a
                ld e,1
                jr uki_o
uki_l:          ld e,0
uki_o:          ld a,c
                ld hl,PF_IROW
                sub (hl)
                add a,a
                add a,e
                ld hl,UI_INVO
                add a,(hl)
                inc a
                call ui_inv_find
                ld a,h
                or l
                ret z
                ld a,3                  ; zona del inventario: el objeto
                jp uk_set
uki_a:          ld a,c
                ld hl,PF_IROW
                cp (hl)
                jr nz,uki_d
                ld a,(UI_INVO)
                cp 2
                ret c
                sub 2
                ld (UI_INVO),a
                jr uki_r
uki_d:          ld a,(UI_INVO)
                add a,4
                ld b,a
                call ui_inv_count
                cp b
                ret z
                ret c
                ld a,(UI_INVO)
                add a,2
                ld (UI_INVO),a
uki_r:          ld a,(UI_DIRTY)
                or 4
                ld (UI_DIRTY),a
                ret

; cutscene() (A original = $40) y endCutscene() ($C0): el jugador no ve la interfaz ni el cursor durante la cutscene; al acabar vuelve todo
; y la camara sigue al protagonista (o2_cutscene / o2_endCutscene de ScummVM)
ui_cutscene:    ld a,c
                cp $C0
                jr z,ui_endcut
                ld a,(UI_IFACE)
                ld (UI_SIF),a
                ld a,(UI_CURSOR)
                ld (UI_SCUR),a
                ld hl,(VAR_CURSORSTATE)
                ld (UI_SV21),hl
                ld hl,200
                ld (VAR_CURSORSTATE),hl
                xor a
                ld (UI_IFACE),a
                ld (UI_CURSOR),a
                jr uc_dirty
ui_endcut:      ld a,(UI_SIF)
                ld (UI_IFACE),a
                ld a,(UI_SCUR)
                ld (UI_CURSOR),a
                ld hl,(UI_SV21)
                ld (VAR_CURSORSTATE),hl
                ld a,2
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
uc_dirty:       ld a,(UI_DIRTY)
                or 7
                ld (UI_DIRTY),a
                ret

; ---- setObjectName (A original = $54): ARGS = objeto y STRP = el nombre
; HL = objeto -> IX = su entrada y carry si tiene nombre cambiado
nm_lookup:      ld a,h
                or l
                ret z
nm_find:        ld ix,NAMEOV
                ld de,NM_SIZE
                ld b,NNAMES
nf_l:           ld a,(ix+0)
                cp l
                jr nz,nf_n
                ld a,(ix+1)
                cp h
                jr nz,nf_n
                scf
                ret
nf_n:           add ix,de
                djnz nf_l
                or a
                ret
ui_setname:     ld hl,(ARGS)
                ld a,h
                or l
                ret z
                push hl
                call nm_find
                jr c,sn_have
                ld hl,0
                call nm_find            ; una entrada libre
                jr c,sn_have
                pop hl
                ret
sn_have:        pop hl
                ld (ix+0),l
                ld (ix+1),h
                push ix
                pop de
                inc de
                inc de
                ld hl,(STRP)
                ld b,NM_SIZE-3
sn_c:           ld a,(hl)
                or a
                jr z,sn_e
                ld (de),a
                inc hl
                inc de
                djnz sn_c
sn_e:           xor a
                ld (de),a
                ret
