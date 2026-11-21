;  ovd_ui.asm - 10g-3: drawBox y print en la zona de los verbos (y >= 144 de SCUMM), desde ov_ui_text / ov_ui_box (txtlayer.asm) por OVD_UITEXT / OVD_UIBOX.
;  Ver el comentario de ov_ui_text en txtlayer.asm. Se incluye desde ovld.asm (overlay D, solo en el programa).
ovd_uitext:
                ld a,(ov_ty)
                add a,4-144
                rrca
                rrca
                rrca
                and 7
                inc a
                cp 8
                ret nc
                push af                 ; la fila queda marcada (ov_uirow): ui_redraw no la borra
                ld b,a
                ld a,1
oxt_b:          rlca
                djnz oxt_b
                ld hl,ov_uirow
                or (hl)
                ld (hl),a
                pop af
                call hu_mul42
                ld de,UIVB
                add hl,de
                push hl
                ld hl,(EVARGS+2)
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,(EVARGS+8)
                and 1
                jr z,out_c
                ld a,(ov_rem)
                srl a
                ld e,a
                ld a,l
                sub e
                jr nc,out_x
                xor a
out_x:          ld l,a
out_c:          ld c,l                  ; columna
                ld b,0
                pop hl
                add hl,bc
                ex de,hl
                ld hl,UIBUF
                ld a,(ov_rem)
                or a
                ret z
                ld b,a
out_l:          ld a,c
                cp UI_COLS
                jr nc,out_e
                ld a,(hl)               ; ASCII -> codigo de glifo (UIVB)
                call ascii_glyph
                add a,GLYPH0
                ld (de),a
                inc hl
                inc de
                inc c
                djnz out_l
out_e:          ld a,1
                ld (ui_chg),a
                ret

ovd_uibox:
                ld a,(ov_ty)
                call ov_uiy
                ld (ov_ty),a
                ld hl,(ARGS+6)
                ld a,h
                or a
                ld a,l
                jr z,oub_a
                ld a,199
oub_a:          call ov_uiy
                inc a
                ld (ov_tl),a
                ld a,(ARGS+8)
                and 15
                ld e,a
                ld d,0
                ld hl,ega2chroma
                add hl,de
                ld a,(hl)
                and 15
                ld (ov_ink),a
                ld hl,(ARGS)
                call ov_x34
                ld (ov_lo),a
                ld hl,(ARGS+4)
                inc hl
                call ov_x34
                ld (ov_hi),a
                ld c,2                  ; las filas de UIVB (2-7: lineas 128 + 8 * fila) que la caja cubre enteras: sus celdas tapadas, a vacio; si la caja va
obt_r:          ld a,c                  ; de lado a lado (x = 0 y x2 >= 319), la fila deja de ser del marcador
                add a,a
                add a,a
                add a,a
                add a,128
                ld hl,ov_ty
                cp (hl)
                jr c,obt_n
                add a,7
                ld hl,ov_tl
                cp (hl)
                jr nc,obt_n
                push bc
                ld a,c
                call hu_mul42
                ld de,UIVB
                add hl,de
                push hl
                ld hl,(ARGS)
                ld de,7
                add hl,de
                call obt_d8
                ld e,a                  ; E = primera columna entera
                push de
                ld hl,(ARGS+4)
                inc hl
                call obt_d8
                pop de
                ld d,a                  ; D = la siguiente a la ultima
                pop hl
                sub e
                jr z,obt_k
                jr c,obt_k
                ld b,a
                push de
                ld d,0
                add hl,de
obt_z:          ld (hl),0
                inc hl
                djnz obt_z
                pop de
                ld a,1
                ld (ui_chg),a
obt_k:          pop bc
                ld a,e
                or a
                jr nz,obt_n
                ld a,d
                cp 40
                jr c,obt_n
                ld b,c
                ld a,$FE
obt_m:          rlca
                djnz obt_m
                ld hl,ov_uirow
                and (hl)
                ld (hl),a
obt_n:          inc c
                ld a,c
                cp 8
                jr c,obt_r
oub_y:          ld a,(ov_ty)
                ld hl,ov_tl
                cp (hl)
                ret nc
                ld c,a
                rrca
                rrca
                rrca
                and $1F
                add a,HR_BM>>8
                ld h,a
                ld a,c
                and 7
                rrca
                rrca
                rrca
                ld l,a                  ; HL = la linea en el bitmap
                ld a,(ov_lo)
                ld b,a
oub_x:          ld a,(ov_hi)
                cp b
                jr z,oub_n
                jr c,oub_n
                push hl
                ld a,b
                rrca
                rrca
                rrca
                and $1F
                add a,l
                ld l,a
                ld a,b
                and 7
                ld c,$80
                jr z,oub_m
oub_s:          srl c
                dec a
                jr nz,oub_s
oub_m:          ld a,(ov_ink)
                or a
                jr z,oub_clr
                ld a,c
                or (hl)
                ld (hl),a
                ld a,h
                add a,(HR_ATT-HR_BM)>>8
                ld h,a
                ld a,(hl)
                and $F0
                ld c,a
                ld a,(ov_ink)
                or c
                ld (hl),a
                jr oub_nx
oub_clr:        ld a,c
                cpl
                and (hl)
                ld (hl),a
oub_nx:         pop hl
                inc b
                jr nz,oub_x
oub_n:          ld hl,ov_ty
                inc (hl)
                jr oub_y

; HL = x de SCUMM -> A = HL / 8, como mucho UI_COLS
obt_d8:         bit 7,h
                jr z,od_p
                xor a
                ret
od_p:           srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld a,h
                or a
                ld a,UI_COLS
                ret nz
                ld a,l
                cp UI_COLS+1
                ret c
                ld a,UI_COLS
                ret

; A = y de SCUMM (>= 144) -> la linea de la pantalla: y - 8, entre 144 y 191
ov_uiy:         sub 8
                cp 144
                jr nc,ouy_a
                ld a,144
ouy_a:          cp 192
                ret c
                ld a,191
                ret

; HL = x de SCUMM (con signo) -> A = x * 3 / 4 (0-255)
ov_x34:         bit 7,h
                jr z,ox_p
                xor a
                ret
ox_p:           ld d,h
                ld e,l
                add hl,hl
                add hl,de
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

