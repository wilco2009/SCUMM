; =====================================================================
;  overlay.asm - el codigo del programa que no cabe por debajo de $8000: interfaz (ui.asm), camara (cam.asm) y personajes (actors.asm).
;  Se ensambla aparte (org $0000) y en el arranque scumm.asm lo copia a una pagina de la RAM extendida y la mapea en el bloque 0
;  (solo lectura, sin ROM: los sprites y los POKE siguen activos). Las variables estan en RAM (ovl_vars.inc).
;  Montaje en tres pasos (compila_scumm.bat): pasmo scumm.asm; pasmo overlay.asm (usa scumm.sym); pasmo scumm.asm otra vez (incluye overlay.bin).
; =====================================================================
                include "scumm.sym"
                org $0000
                jp ui_init
                jp ui_update
                jp ui_click
                jp cam_update
                jp actors_update
                jp host_ops
                jp ov_init
                jp ovg_ev               ; sonido: esta en el overlay 2 (overlay2.asm), se entra por las puertas de abajo
                jp ovg_tick
                jp dk_entry
                jp hr_ui
                jp dk_mask
                jp ms_poll
                jp ov_err
                jp ov_drawobj
                jp ui_cmname
                jp ui_nostart
                jp ov_afpx

; Puertas al overlay 2 (snd.asm y save.asm, overlay2.asm): cada una carga en el bloque 0 la pagina del overlay 2 con un OUT; la instruccion siguiente
; (la direccion de despues del OUT) ya se lee del overlay 2, que tiene ahi un JP a su rutina. Al acabar, ov2_exit (overlay2.asm) vuelve a mapear el overlay 1 y
; la instruccion siguiente a ese OUT es el RET de ovg_ret (en esta pagina). Ni el residente ni el fotograma se enteran: dos escrituras de puerto por llamada.
; A (suceso de snd_event) viaja en D; la rutina puede estropear A, BC y D.
ovg_ev:         ld d,a
                ld bc,OVL2_PAGE*256+MAP_PORT
                xor a
                out (c),a
ovg_tick:       ld d,a
                ld bc,OVL2_PAGE*256+MAP_PORT
                xor a
                out (c),a
ovg_sv:         ld d,a
                ld bc,OVL2_PAGE*256+MAP_PORT
                xor a
                out (c),a
                defs 9                  ; sitio de ov2_exit (6 bytes) en el overlay 2: acaba justo antes de ovg_ret
ovg_ret:        ret

; o4_saveLoadGame: la parte que guarda y carga esta en el overlay 2 (sv_saveload); si una carga acabo bien (SV_FIN), la sala y el script se restauran aqui porque
; gf_load_room llama al overlay 1 (OVL_DKMASK, OVL_DARK) y con el overlay 2 en el bloque 0 no podria
ho_saveload:    call ovg_sv
                ld a,(SV_FIN)
                or a
                ret z
                xor a
                ld (SV_FIN),a
                call gf_load_room       ; la imagen de la sala restaurada
                ld a,(SV_PON)           ; la tabla de color de sala (hv_ptab, ya restaurada): gf_load_room puso hv_pon a 0
                ld (hv_pon),a
                or a
                jr z,hsl_np
                ld a,1
                ld (gd_pending),a
                ld (gd_full),a
hsl_np:
                ld a,(CUR)
                call load_slot          ; el script sigue por donde dice su ranura restaurada
                ld hl,3
                ld (HRES),hl
                ret

; sin sonido ni linterna ni nada que sonara: variables a cero (era sdx_ini en snd.asm; son variables de RAM, no necesita el overlay 2)
sdx_ini:        xor a
                ld (fl_xs),a
                ld (fl_ys),a
                ld (dk_ok),a
                ld (sdx_tstep),a
                ld (sdx_tstep+1),a
                ld (sdx_cur),a
                ld (sdx_next),a
                ld (sdx_qn),a
                ld (SV_FIN),a
                ld (TXSPD),a            ; velocidad del texto: la de omision (6)
                ret

; el overlay 2 se copia a su pagina la primera vez (ov_done = 1 lo deja ov_install de scumm.asm; con 2 ya esta copiado: tras un restart la imagen ya no esta)
ov_copy2:       ld a,(ov_done)
                cp 1
                ret nz
                ld b,OVL2_PAGE
                ld a,1
                ld c,MAP_PORT
                out (c),a
                ld hl,OVERLAY2_IMAGE
                ld de,$2000
                ld bc,OV2_COPY
                ldir
                ld b,1                  ; el bloque 1 vuelve a su pagina
                ld a,1
                ld c,MAP_PORT
                out (c),a
                ld a,2
                ld (ov_done),a
                ret

ov_init:        call ov_copy2
                call sdx_ini
                xor a                   ; paleta de 16 de la FPGA (POKE 2063/2064/2066/2067): los 16 colores de Chroma, pero el 6 (amarillo)
                ld (2063),a             ; es el marron del EGA (170,85,0), que Chroma no tiene y que el EGA de v2 usa en lugar del amarillo
                ld hl,ov_pal16
                ld b,16
ov_pl:          ld a,(hl)
                ld (2064),a             ; byte bajo {G,B}
                inc hl
                ld a,(hl)
                ld (2066),a             ; byte alto {BRIGHT,R}: escribe la entrada y avanza el puntero
                inc hl
                djnz ov_pl
                ld a,1
                ld (2067),a             ; paleta de 16 activa
                ld hl,NAMEOV            ; sin nombres cambiados
                ld de,NAMEOV+1
                ld bc,NNAMES*NM_SIZE+NACTORS*3-1
                ld (hl),0
                ldir
                ld hl,160               ; camara: seguir al protagonista, centrada
                ld (cam_cx),hl
                ld a,2
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
                ld a,1
                ld (cam_new),a
                ld hl,0
                ld (cam_dest),hl
                xor a
                ld (ac_n),a
                ld hl,AC_OVF            ; fotogramas de overlay a cero y trajes "ya vistos" a $FF (cualquier traje es nuevo)
                ld de,AC_OVF+1
                ld bc,NACTORS-1
                ld (hl),a
                ldir
                ld hl,AC_LC
                ld de,AC_LC+1
                ld bc,NACTORS-1
                ld (hl),$FF
                ldir
                xor a
                ld (2131),a             ; sin sprites extra; la entrada 1 de los extra (SPRX + 32) no se usa: su Y a 0 por si acaso
                ld (SPRX+35),a
                ret

; (ov_pal16, la paleta de 16 de la FPGA, esta en progdata.inc: son datos y por encima de $8000 no gastan overlay)

; error fatal: ERROR n A<primer operando> O<opcode> S<script>, y espera una tecla (lo llama sm_err de scumm.asm)
ov_err:         call sc_hide_sprites
                xor a
                ld (tx_on),a
                ld a,(ERR)
                ld l,a
                ld h,0
                ld de,ERRPOS
                ld b,2
                push hl
                ld hl,tx_err
                call put_str
                pop hl
                call put_num
                ld a,' '                ; que fallo: A = primer operando, O = opcode (decimal), S = script de la ranura en curso
                call put_chr
                ld a,'A'
                call put_chr
                ld hl,(ARGS)
                ld b,3
                call put_num
                ld a,' '
                call put_chr
                ld a,'O'
                call put_chr
                ld a,(OPC)
                ld l,a
                ld h,0
                ld b,3
                call put_num
                ld a,(CUR)
                cp $FF
                jr z,sme_k
                push af
                ld a,' '
                call put_chr
                ld a,'S'
                call put_chr
                pop af
                call slot_addr
                inc hl
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld b,3
                call put_num
sme_k:          call sc_wait_key
                ret

                include "ui.asm"
                include "hrui.asm"
                include "cam.asm"
                include "actors.asm"
                include "dark.asm"
                include "../../COMMON/mouse.asm"
                IF $ > $2000
                defb EL_OVERLAY_NO_CABE_EN_8_KB
                ENDIF

; drawObject de v2: lleva al objeto a (x, y) si x no es $FF, lo marca como dibujado y apaga los demas objetos de la sala que
; ocupan el mismo rectangulo. ARGS: objeto, x, y
ov_drawobj:
                ld a,(NOBJS)
                or a
                ret z
                ld (FO_N),a
                xor a
                ld (FO_I),a
dro_find:       ld a,(FO_I)
                call fo_rec
                ld e,(ix+0)
                ld d,(ix+1)
                ld hl,(ARGS)
                or a
                sbc hl,de
                jr z,dro_found
                ld hl,FO_I
                inc (hl)
                ld a,(FO_N)
                cp (hl)
                jr nz,dro_find
                ret
dro_found:      push ix
                pop iy
                ld a,(ARGS+2)           ; x = $FF: no se mueve; si no, el objeto se dibuja en (x*8, y*8) como en ScummVM (o2_drawObject)
                cp $FF
                jr z,dro_nomove
                ld c,a
                ld a,(ARGS+4)
                ld b,a
                cp (iy+6)
                jr nz,dro_mv
                ld a,c
                cp (iy+5)
                jr z,dro_nomove
dro_mv:         ld (iy+5),c
                ld (iy+6),b
                ld a,(FO_I)             ; el registro del .GFX (columna, linea) sigue al objeto; sin registro, solo cambia la posicion
                ld hl,hv_nobj
                cp (hl)
                jr nc,dro_mvd
                cp 84
                jr nc,dro_mvd
                ld e,a
                ld d,0
                ld l,e
                ld h,d
                add hl,hl
                add hl,de
                add hl,hl               ; * 6
                ld de,HR_OBJREC+2
                add hl,de
                ld (hl),c               ; columna
                inc hl
                ld a,b
                add a,a
                add a,a
                add a,a
                ld (hl),a               ; linea (pixeles)
dro_mvd:        ld a,1
                ld (gd_full),a          ; la sala se compone entera (los dos sitios del objeto)
                ld (gd_pending),a
dro_nomove:     xor a
                ld (FO_I),a
dro_loop:       ld a,(FO_I)
                call fo_rec
                push ix
                pop de
                push iy
                pop hl
                or a
                sbc hl,de
                jr z,dro_next
                ld a,(ix+5)
                cp (iy+5)
                jr nz,dro_next
                ld a,(ix+6)
                cp (iy+6)
                jr nz,dro_next
                ld a,(ix+7)
                cp (iy+7)
                jr nz,dro_next
                ld a,(ix+8)
                cp (iy+8)
                jr nz,dro_next
                ld l,(ix+0)
                ld h,(ix+1)
                call fo_state
                res 3,(hl)
dro_next:       ld hl,FO_I
                inc (hl)
                ld a,(FO_N)
                cp (hl)
                jr nz,dro_loop
                ld c,8
                jp st_set

; getActorFromPos (input.asm), la prueba de columna: testGfxUsageBit(x / 8, actor). IX = actor, C = su numero, DE = franja x del clic (x / 8) -> carry si
; esta entre las franjas de 8 pixeles que cubre lo dibujado: ACB (ac_draw) da izquierda y derecha (bytes con signo) respecto de x * 8; las franjas son
; (x*8+izq)>>3 .. (x*8+der-1)>>3, o sea izq-7 <= franja*8 - x*8 < der. Sin dato (no dibujado en ACB, o actor > ACB_N): 16 pixeles alrededor de x.
ov_afpx:        ld l,(ix+1)
                ld h,(ix+2)
                ex de,hl
                or a
                sbc hl,de               ; HL = (franja - x) * 8 = principio de la franja del clic respecto de x * 8
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,$F808             ; D = -8, E = 8
                ld a,c
                cp ACB_N+1
                jr nc,afx_c
                dec a
                add a,a
                add a,a
                push hl
                ld l,a
                ld h,0
                ld de,ACB
                add hl,de
                ld d,(hl)               ; izquierda
                inc hl
                ld e,(hl)               ; derecha: 0 = el actor no ha dibujado nada
                pop hl
                ld a,e
                or a
                jr nz,afx_c
                ld de,$F808
afx_c:          ld a,d
                rla
                sbc a,a
                ld b,a
                ld c,d                  ; BC = izquierda
                push hl
                or a
                sbc hl,bc
                ld bc,7
                add hl,bc               ; HL = d - izq + 7: negativo = antes del principio
                bit 7,h
                pop hl
                jr nz,afx_no
                ld a,e
                rla
                sbc a,a
                ld b,a
                ld c,e                  ; BC = derecha
                or a
                sbc hl,bc               ; d - der: negativo = antes del final
                add hl,hl               ; carry = signo
                ret
afx_no:         or a
                ret
