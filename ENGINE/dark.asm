; =====================================================================
;  dark.asm - oscuridad (o2_lights). Con VAR_CURRENT_LIGHTS sin el bit 1 (luz de la sala) la sala se ve negra; con el bit 2 (linterna)
;  se ve solo una ventana de fl_xs x fl_ys celdas (lights a, b, 1) alrededor del cursor, sin las cuatro esquinas, como el rectangulo
;  redondeado de ScummVM (drawFlashlight). Los actores y el texto no se tocan. Se pinta de BACKBUF (la sala completa) a la pantalla.
; =====================================================================
; A = 0: pinta la sala con la oscuridad (lo llama gf_flip en vez de copiar el bufer trasero); A != 0: cada fotograma, mueve la ventana
dk_entry:       or a
                jp nz,dk_frame
dk_apply:       call dk_win
                ld a,(dk_c0)
                ld (dk_pc),a
                ld a,(dk_r0)
                ld (dk_pr),a
                ld hl,BACKBUF+1
                ld (dk_src),hl
                ld hl,DFILE+1
                ld (dk_dst),hl
                xor a
                ld (dk_row),a
dka_r:          ld hl,(dk_dst)
                ld (hl),BLANK
                ld d,h
                ld e,l
                inc de
                ld bc,32
                ldir
                ld a,(dk_ok)
                or a
                jr z,dka_nx
                ld a,(dk_row)
                ld hl,dk_r0
                sub (hl)
                jr c,dka_nx
                ld hl,fl_ys
                cp (hl)
                jr nc,dka_nx
                ld c,a                  ; C = fila dentro de la ventana
                ld a,(fl_xs)
                ld b,a                  ; B = celdas por fila
                ld d,0                  ; D = primera celda (1 si es una fila de las esquinas)
                ld a,b
                cp 3
                jr c,dka_c
                ld a,c
                or a
                jr z,dka_k
                ld a,(fl_ys)
                dec a
                cp c
                jr nz,dka_c
dka_k:          inc d
                dec b
                dec b
dka_c:          ld a,(dk_c0)
                add a,d
                ld e,a
                ld d,0
                ld hl,(dk_src)
                add hl,de
                push hl
                ld hl,(dk_dst)
                add hl,de
                ex de,hl
                pop hl
                ld c,b
                ld b,0
                ldir
dka_nx:         ld hl,(dk_src)
                ld de,33
                add hl,de
                ld (dk_src),hl
                ld hl,(dk_dst)
                add hl,de
                ld (dk_dst),hl
                ld hl,dk_row
                inc (hl)
                ld a,(hl)
                cp 16
                jr c,dka_r
                ret

dk_frame:       ld a,(gf_have)
                or a
                ret z
                ld hl,(VAR_CURRENT_LIGHTS)
                bit 1,l
                ret nz                  ; sala con luz
                bit 2,l
                ret z                   ; a oscuras y sin linterna: no cambia
                call dk_win
                ld a,(dk_ok)
                or a
                ret z
                ld a,(dk_c0)
                ld hl,dk_pc
                cp (hl)
                jp nz,dk_apply
                ld a,(dk_r0)
                ld hl,dk_pr
                cp (hl)
                ret z
                jp dk_apply

; la ventana de la linterna: dk_ok (0: no hay), dk_c0 y dk_r0 (primera columna y fila); el centro es el cursor
dk_win:         xor a
                ld (dk_ok),a
                ld hl,(VAR_CURRENT_LIGHTS)
                bit 2,l
                ret z
                ld a,(fl_xs)
                or a
                ret z
                ld a,(fl_ys)
                or a
                ret z
                ld a,(gf_fine)
                ld e,a
                ld d,0
                ld a,(cur_x)
                ld l,a
                ld h,0
                add hl,de
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l                    ; HL = columna del cursor
                ld a,(fl_xs)
                srl a
                ld e,a
                ld d,0
                or a
                sbc hl,de
                bit 7,h
                jr z,dkw_1
                ld hl,0
dkw_1:          ld a,(fl_xs)
                ld e,a
                ld a,33
                sub e
                jr nc,dkw_2
                xor a
dkw_2:          ld e,a                  ; E = ultima columna de salida
                ld a,l
                cp e
                jr c,dkw_3
                ld a,e
dkw_3:          ld (dk_c0),a
                ld a,(fl_ys)
                add a,a
                add a,a
                ld e,a                  ; E = mitad del alto en pixeles
                ld a,(cur_y)
                ld l,a
                ld h,0
                ld d,0
                ld bc,4
                add hl,bc
                or a
                sbc hl,de
                bit 7,h
                jr z,dkw_4
                ld hl,0
dkw_4:          srl h
                rr l
                srl h
                rr l
                srl h
                rr l                    ; HL = fila
                ld a,(fl_ys)
                ld e,a
                ld a,16
                sub e
                jr nc,dkw_5
                xor a
dkw_5:          ld e,a
                ld a,l
                cp e
                jr c,dkw_6
                ld a,e
dkw_6:          ld (dk_r0),a
                ld a,1
                ld (dk_ok),a
                ret
