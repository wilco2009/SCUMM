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
UI_VT           equ $CD40               ; 15 verbos de 16 bytes: id (0 = libre), columna, fila, modo, texto (11 + 0)
VT_SIZE         equ 16
NVERBS          equ 15

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
                ret

; ------------------------------------------------------------------------------------------ cursorCommand
; ARGS: palabra; el byte alto es el estado de usuario (ver USERSTATE_* de ScummVM)
ui_cursorcmd:   ld a,(ARGS)             ; el byte bajo, si no es 0, es VAR_CURSORSTATE (variable 21)
                or a
                jr z,uc0
                ld l,a
                ld h,0
                ld (VARS+42),hl
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
                jr z,uv_del
                cp $FF
                jr z,uv_mode
                ld a,(ARGS+6)           ; ranura
                cp NVERBS
                ret nc
                call ui_entry
                ld a,(ARGS)
                ld (ix+0),a
                ld hl,(ARGS+2)          ; columna = (x * 13 + 4) / 16
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                ld b,h
                ld c,l
                add hl,hl
                add hl,bc
                add hl,de
                ld de,4
                add hl,de
                ld b,4
uv_s:           srl h
                rr l
                djnz uv_s
                ld a,l
                cp 32
                jr c,uv_c
                ld a,31
uv_c:           ld (ix+1),a
                ld a,(ARGS+4)           ; fila = y - 2 (las filas 19-21 del original son las 17-19 nuestras)
                sub 2
                ld (ix+2),a
                ld (ix+3),1
                ld hl,(STRP)
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

; IX = verbo -> HL = lo que se escribe en la zona de verbos (la etiqueta corta o el texto)
ui_label:       push bc                 ; conserva BC
                call ui_label0
                pop bc
                ret
ui_label0:      ld a,(ix+0)
                ld hl,ui_short
ul_l:           ld c,(hl)
                inc hl
                bit 7,c
                jr nz,ul_none
                cp c
                jr z,ul_ok
ul_s:           ld a,(hl)
                inc hl
                or a
                jr nz,ul_s
                ld a,(ix+0)
                jr ul_l
ul_ok:          ret
ul_none:        push ix
                pop hl
                ld a,l
                add a,4
                ld l,a
                ret nc
                inc h
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
ui_update:      ld hl,VARS+52           ; si cambia la frase, se vuelve a escribir
                ld de,UI_PREV
                ld b,8
uu_c:           ld a,(de)
                cp (hl)
                jr nz,uu_ch
                inc hl
                inc de
                djnz uu_c
                jr uu_d
uu_ch:          ld hl,VARS+52
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
                ret z
                ld a,(tx_on)            ; mientras hay un mensaje el inventario espera (el texto ocupa las filas 20-23)
                or a
                jr nz,uu_w
                jp ui_draw_inv
uu_w:           ld a,(UI_DIRTY)
                or 4
                ld (UI_DIRTY),a
                ret

; HL = direccion de pantalla de la fila A, columna 0
ui_row:         ld l,a
                ld h,0
                ld e,l
                ld d,h
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de
                ld de,DFILE+1
                add hl,de
                ret

ui_clear_row:   call ui_row
                ld d,h
                ld e,l
                inc de
                ld bc,31
                ld (hl),BLANK
                ldir
                ret

; ---- los verbos
ui_draw_verbs:  ld a,VERB_ROW0
                call ui_clear_row
                ld a,VERB_ROW0+1
                call ui_clear_row
                ld a,VERB_ROW0+2
                call ui_clear_row
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

; IX = verbo: se escribe hasta donde empieza el siguiente de su fila (o hasta el borde)
ui_draw_verb:   ld a,(ix+3)
                or a
                ret z
                ld a,(ix+2)
                cp VERB_ROW0
                ret c
                cp VERB_ROW0+3
                ret nc
                ld c,32                 ; limite: la columna del verbo mas cercano a la derecha en la misma fila
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
                push hl
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
                dec b
                jr udw_c

; ---- la frase: verbo, objeto, preposicion, objeto
ui_draw_sentence:
                ld a,SENT_ROW
                call ui_clear_row
                ld a,(UI_IFACE)
                bit 5,a
                ret z
                ld a,SENT_ROW
                call ui_row
                ex de,hl
                ld b,32                 ; B = sitio que queda
                ld a,(VARS+52)          ; verbo
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
us_o1:          ld hl,(VARS+54)         ; objeto 1
                call us_obj
                ld hl,(VARS+58)         ; preposicion
                ld a,h
                or a
                jr nz,us_o2
                ld a,l
                or a
                jr z,us_o2
                cp 5
                jr nc,us_o2
                ld hl,us_preps
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
us_o2:          ld hl,(VARS+56)         ; objeto 2
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
                ld de,UI_NAME
                ld b,31
                jr on_c
on_orig:        pop hl
                ld a,h
                or a
                jr nz,on_obj
                ld a,l
                cp NACTORS
                jr nc,on_obj
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
                ld de,UI_NAME
                ld b,31
                jr on_c
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
                ld de,UI_NAME
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

; ---- clic en la parte de abajo de la pantalla (cur_y >= 128): fila 16 frase, 17-19 verbos
ui_click:       ld a,(UI_CURSOR)
                or a
                ret z
                ld a,(cur_y)
                srl a
                srl a
                srl a                   ; fila
                ld c,a
                cp SENT_ROW
                jr nz,uk_v
                ld a,5                  ; zona de la frase
                ld hl,0
                jr uk_set
uk_v:           cp VERB_ROW0
                ret c
                cp VERB_ROW0+3
                jp nc,uk_inv
                ld a,(cur_x)
                srl a
                srl a
                srl a
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
uk_hit:         ld l,(ix+0)
                ld h,0
                ld a,1                  ; zona de verbos
                jr uk_set
uk_n:           push de
                ld de,VT_SIZE
                add ix,de
                pop de
                dec d
                jr nz,uk_l
                ld hl,0                 ; en la zona de verbos pero sin verbo
                ld a,1
uk_set:         ld (INP_AREA),a
                ld (INP_VAL),hl
                ld a,1
                ld (INP_FLAG),a
                ret

; ---------------------------------------------------------------------------------------------------- inventario
; A = numero de objetos del protagonista (los que tienen su numero de actor como dueno)
ui_inv_count:   ld a,(VARS)
                ld c,a
                ld b,0
                ld hl,OBJOWN+1
                ld de,NOBJ-1
uic_l:          ld a,(hl)
                cp c
                jr nz,uic_n
                inc b
uic_n:          inc hl
                dec de
                ld a,d
                or e
                jr nz,uic_l
                ld a,b
                ret

; A = n (desde 1) -> HL = el n-esimo objeto del protagonista por numero de objeto (0 si no hay)
ui_inv_find:    ld b,a
                ld a,(VARS)
                ld c,a
                ld hl,OBJOWN+1
                ld de,1
uif_l:          ld a,(hl)
                cp c
                jr nz,uif_n
                dec b
                jr z,uif_f
uif_n:          inc hl
                inc de
                ld a,d
                cp 3
                jr c,uif_l
                jr nz,uif_none
                ld a,e
                cp $0C
                jr c,uif_l
uif_none:       ld hl,0
                ret
uif_f:          ex de,hl
                ret

ui_draw_inv:    ld a,INV_ROW0
                call ui_clear_row
                ld a,INV_ROW0+1
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
                add a,INV_ROW0
                call ui_row
                ld a,(UI_TMP)
                and 1
                ld de,0
                jr z,udi_c
                ld de,17
udi_c:          add hl,de
                ex de,hl
                ld hl,UI_NAME
                ld b,15
                call us_text
udi_n:          ld hl,UI_TMP
                inc (hl)
                ld a,(hl)
                cp 4
                jr c,udi_l
udi_arrows:     ld a,(UI_INVO)
                or a
                jr z,udi_dn
                ld a,INV_ROW0
                call ui_row
                ld de,15
                add hl,de
                ex de,hl
                ld a,'U'
                call put_chr
                ld a,'P'
                call put_chr
udi_dn:         ld a,(UI_INVO)
                add a,4
                ld b,a
                call ui_inv_count
                cp b
                ret z
                ret c
                ld a,INV_ROW0+1
                call ui_row
                ld de,15
                add hl,de
                ex de,hl
                ld a,'D'
                call put_chr
                ld a,'N'
                jp put_chr

; clic en las filas 20-21: un objeto (columnas 0-14 y 17-31) o una flecha (15-16)
uk_inv:         cp INV_ROW0+2
                ret nc
                ld a,(UI_IFACE)
                bit 6,a
                ret z
                ld a,(cur_x)
                srl a
                srl a
                srl a
                cp 15
                jr c,uki_l
                cp 17
                jr c,uki_a
                ld e,1
                jr uki_o
uki_l:          ld e,0
uki_o:          ld a,c
                sub INV_ROW0
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
                cp INV_ROW0
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
                ld hl,(VARS+42)
                ld (UI_SV21),hl
                ld hl,200
                ld (VARS+42),hl
                xor a
                ld (UI_IFACE),a
                ld (UI_CURSOR),a
                jr uc_dirty
ui_endcut:      ld a,(UI_SIF)
                ld (UI_IFACE),a
                ld a,(UI_SCUR)
                ld (UI_CURSOR),a
                ld hl,(UI_SV21)
                ld (VARS+42),hl
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
