DKTEST         equ 0
; =====================================================================
;  dark.asm - oscuridad (o2_lights) en HiRes (rama hires16). Con VAR_CURRENT_LIGHTS sin el bit 1 (luz de la sala) la sala se ve negra; con el bit 2 (linterna)
;  se ve solo una ventana de fl_xs x fl_ys celdas (lights a, b, 1) alrededor del cursor, sin las cuatro esquinas, como el rectangulo redondeado de ScummVM
;  (drawFlashlight). Los actores y el texto no se tocan.
;
;  Se oscurece con los ATRIBUTOS: papel y tinta a 0 (negro) en todo lo que queda fuera de la ventana; el bitmap no se toca. hr_put (hr.asm) llama a
;  dk_mask con la columna ya compuesta cuando hv_dark vale 1, asi que cualquier dibujado (sala entera, objetos, columnas que entran por el scroll) sale oscurecido.
;  dk_frame, una vez por fotograma (y tras cada movimiento del motor, hr_finish), mueve la ventana: reescribe las columnas de la ventana vieja (ampliada una a cada
;  lado, por si la memoria se ha movido) y de la nueva.
; =====================================================================
dk_pok          equ ACSIG+161           ; la ventana que hay pintada: hay, columna, fila, celdas de ancho y de alto, y la camara
dk_pxs          equ ACSIG+162
dk_pys          equ ACSIG+163
dk_pcam         equ ACSIG+164           ; palabra
dk_s            equ ACSIG+166
dk_lo           equ ACSIG+167
dk_hi           equ ACSIG+168

; A = 0: nada (la sala se pinta oscura por hr_put); A != 0: cada fotograma, mueve la ventana
dk_entry:       or a
                ret z
; no se mira el cursor ni se reescribe nada mientras la sala tenga luz
dk_frame:       ld a,(gf_have)
                or a
                ret z
                ld a,(hv_drawn)
                or a
                ret z
                IF DKTEST
                ld hl,4                 ; prueba: sin luz y con linterna, sea cual sea la variable
                ELSE
                ld hl,(VAR_CURRENT_LIGHTS)
                ENDIF
                bit 1,l
                jr z,dkf_dark
                xor a                   ; con luz
                ld (hv_dark),a
                ld (dk_pok),a
                ld (dk_ok),a
                ret
dkf_dark:       ld a,1
                ld (hv_dark),a
                call dk_win
                ld a,(dk_ok)            ; ¿ha cambiado algo de lo que hay pintado?
                ld hl,dk_pok
                cp (hl)
                jr nz,dkf_ch
                or a
                jr z,dkf_same
                ld a,(dk_c0)
                ld hl,dk_pc
                cp (hl)
                jr nz,dkf_ch
                ld a,(dk_r0)
                ld hl,dk_pr
                cp (hl)
                jr nz,dkf_ch
                ld a,(fl_xs)
                ld hl,dk_pxs
                cp (hl)
                jr nz,dkf_ch
                ld a,(fl_ys)
                ld hl,dk_pys
                cp (hl)
                jr nz,dkf_ch
                ld hl,(hv_cam)
                ld de,(dk_pcam)
                or a
                sbc hl,de
                jr nz,dkf_ch
dkf_same:       ret
dkf_ch:         ld a,255                ; columnas a reescribir: [dk_lo, dk_hi]
                ld (dk_lo),a
                xor a
                ld (dk_hi),a
                ld a,(dk_pok)           ; la ventana vieja, una columna mas a cada lado
                or a
                jr z,dkf_n
                ld a,(dk_pc)
                or a
                jr z,dkf_o1
                dec a
dkf_o1:         call dk_inc_lo
                ld a,(dk_pc)
                ld hl,dk_pxs
                add a,(hl)
                cp 31
                jr c,dkf_o2
                ld a,31
dkf_o2:         call dk_inc_hi
dkf_n:          ld a,(dk_ok)            ; y la nueva
                or a
                jr z,dkf_w
                ld a,(dk_c0)
                call dk_inc_lo
                ld a,(dk_c0)
                ld hl,fl_xs
                add a,(hl)
                dec a
                call dk_inc_hi
dkf_w:          ld a,(dk_ok)            ; lo que hay pintado pasa a ser esto
                ld (dk_pok),a
                ld a,(dk_c0)
                ld (dk_pc),a
                ld a,(dk_r0)
                ld (dk_pr),a
                ld a,(fl_xs)
                ld (dk_pxs),a
                ld a,(fl_ys)
                ld (dk_pys),a
                ld hl,(hv_cam)
                ld (dk_pcam),hl
                ld a,(dk_lo)
                ld b,a
                ld a,(dk_hi)
                cp b
                ret c                   ; nada que reescribir
                ld a,b
dkf_l:          ld (dk_s),a
                ld e,a
                ld d,0
                ld hl,(hv_cam)
                add hl,de
                ex de,hl
                call hr_makecol
                ld a,(dk_s)
                call hr_put
                ld a,(dk_s)
                inc a
                ld hl,dk_hi
                cp (hl)
                jr c,dkf_l
                jr z,dkf_l
                jp hr_unmap

dk_inc_lo:      ld hl,dk_lo
                cp (hl)
                ret nc
                ld (hl),a
                ret
dk_inc_hi:      ld hl,dk_hi
                cp (hl)
                ret c
                ret z
                ld (hl),a
                ret

; la ventana de la linterna: dk_ok (0: no hay), dk_c0 y dk_r0 (primera columna de memoria y primera fila de celdas); el centro es el cursor
dk_win:         xor a
                ld (dk_ok),a
                IF DKTEST
                ld hl,4                 ; prueba: sin luz y con linterna, sea cual sea la variable
                ELSE
                ld hl,(VAR_CURRENT_LIGHTS)
                ENDIF
                bit 2,l
                ret z
                ld a,(fl_xs)
                or a
                ret z
                ld a,(fl_ys)
                or a
                ret z
                ld a,(hv_fine)
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
                ld a,32
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

; A = columna de pantalla (0-31; 32 y mas: las de entrada del scroll, siempre negras): pone a 0 los atributos de HR_COLBUF que quedan fuera de la ventana
dk_mask:        cp 32
                jr nc,dm_all
                ld c,a
                ld a,(dk_ok)
                or a
                jr z,dm_all
                ld a,(dk_c0)
                ld b,a
                ld a,c
                sub b
                jr c,dm_all             ; a la izquierda de la ventana
                ld b,a                  ; B = columna dentro de la ventana
                ld hl,fl_xs
                cp (hl)
                jr nc,dm_all            ; a la derecha
                ld a,(dk_r0)
                add a,a
                add a,a
                add a,a
                ld d,a                  ; D = primera linea
                ld a,(dk_r0)
                ld hl,fl_ys
                add a,(hl)
                add a,a
                add a,a
                add a,a
                ld e,a                  ; E = ultima linea + 1
                ld a,(fl_xs)
                cp 3
                jr c,dm_go              ; las esquinas solo se quitan con 3 columnas o mas
                ld a,b
                or a
                jr z,dm_edge
                ld a,(fl_xs)
                dec a
                cp b
                jr nz,dm_go
dm_edge:        ld a,d                  ; columna del borde: sin la primera ni la ultima celda
                add a,8
                ld d,a
                ld a,e
                sub 8
                ld e,a
dm_go:          ld hl,HR_COLBUF+128     ; lo de arriba
                ld a,d
                or a
                jr z,dm_b
                ld b,a
                xor a
dm_t:           ld (hl),a
                inc hl
                djnz dm_t
dm_b:           ld a,128                ; y lo de abajo
                sub e
                ret z
                ld b,a
                ld l,e
                ld h,0
                ld de,HR_COLBUF+128
                add hl,de
                xor a
dm_u:           ld (hl),a
                inc hl
                djnz dm_u
                ret
dm_all:         ld hl,HR_COLBUF+128
                ld de,HR_COLBUF+129
                ld bc,127
                ld (hl),0
                ldir
                ret
