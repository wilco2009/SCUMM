; ovl2_ops.asm - operaciones del anfitrion poco frecuentes (host_ops, cam.asm) que viven en el overlay 2 para dejar sitio en el overlay 1:
;   roomOps ($33), cutscene/endCutscene ($40/$C0), cursorCommand ($60) y lights ($70). Se entra por ovg_ho (overlay.asm) con D = el codigo original
;   (con el bit 7); solo llaman al residente. Antes estaban en cam.asm y ui.asm.
ov2_ho:         ld hl,ov2_exit
                push hl
                ld a,d
                ld c,a                  ; ui_cutscene mira el bit 7 en C
                and $7F
                cp $33
                jp z,ho_roomops
                cp $40
                jp z,ui_cutscene
                cp $70
                jp z,ho_lights
                jp ui_cursorcmd          ; $60

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

; roomOps(a, b, subop) (o2_roomOps de ScummVM): ARGS = a, b, subop. Subop 1 (SO_ROOM_SCROLL): VAR_CAMERA_MIN_X = a * 8,
; VAR_CAMERA_MAX_X = b * 8, los dos entre 160 y ancho - 160. Los demas subops no hacen nada en v2.
ho_roomops:     ld a,(ARGS+4)
                and $1F
                cp 2
                jr z,ho_rcolor
                cp 1
                ret nz
                ld a,(ARGS)
                call rs_clamp
                ld (VAR_CAMERA_MIN_X),hl
                ld a,(ARGS+2)
                call rs_clamp
                ld (VAR_CAMERA_MAX_X),hl
                ret
; subop 2 (SO_ROOM_COLOR): _roomPalette[b] = a (colores EGA 0-15) y la sala se vuelve a pintar. hv_ptab es la misma tabla en indices de Chroma (ega2chroma):
; el fondo y los objetos se pintan a traves de ella (hr_put -> dk_mask -> rp_remap); startScene la deja en la identidad (gf_load_room: hv_pon = 0)
ho_rcolor:      ld a,(ARGS)
                cp 16
                ret nc
                ld a,(ARGS+2)
                cp 16
                ret nc
                ld a,(hv_pon)
                or a
                jr nz,hrc_t
                ld hl,hv_ptab           ; tabla en la identidad
                ld b,16
hrc_i:          ld (hl),a
                inc hl
                inc a
                djnz hrc_i
hrc_t:          ld hl,ega2chroma
                ld a,(ARGS)
                ld e,a
                ld d,0
                add hl,de
                ld c,(hl)               ; C = color de Chroma de a
                ld hl,ega2chroma
                ld a,(ARGS+2)
                ld e,a
                add hl,de
                ld e,(hl)               ; E = color de Chroma de b
                ld hl,hv_ptab
                add hl,de
                ld (hl),c
                ld hl,hv_ptab           ; ¿sigue siendo la identidad? entonces no hace falta remapear
                ld b,16
                ld c,0
                ld d,0
hrc_c:          ld a,(hl)
                cp c
                jr z,hrc_n
                ld d,1
hrc_n:          inc hl
                inc c
                djnz hrc_c
                ld a,d
                ld (hv_pon),a
                ld a,1
                ld (gd_pending),a
                ld (gd_full),a
                ret
rs_clamp:       ld l,a                  ; HL = A * 8 acotado a 160..ancho - 160
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ex de,hl
                ld hl,160
                or a
                sbc hl,de
                jr c,rc1
                ld de,160
rc1:            ld hl,(gf_cols)         ; ancho de la sala / 8 (EV_ROOM_LOAD ya cargo la imagen)
                ld a,h
                or l
                jr z,rc2
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,-160
                add hl,bc
                or a
                sbc hl,de               ; maximo - valor
                jr nc,rc2
                add hl,de               ; valor = maximo
                ex de,hl
rc2:            ex de,hl
                ret

ho_lights:      ld a,(ARGS+4)           ; lights(a, b, c): c = 1 -> linterna de a x b celdas; en los dos casos se vuelve a pintar la sala
                cp 1
                jr nz,hl_r
                ld a,(ARGS)
                ld (fl_xs),a
                ld a,(ARGS+2)
                ld (fl_ys),a
hl_r:           ld a,1
                ld (gd_pending),a
                ld (gd_full),a
                ret
