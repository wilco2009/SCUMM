; La camara de los scripts: cam_cx es el centro de una pantalla de 320 pixeles (como en el juego original) y VAR_CAMERA_POS_X
; (variable 2) es cam_cx / 8. Modos: 0 normal (setCameraAt), 1 desplazamiento (panCameraTo, 8 pixeles por fotograma) y
; 2 seguir a un actor (actorFollowCamera; $FF = VAR_EGO). Nuestra ventana mide 256: se ve desde cam_cx - 128.

; las instrucciones que el nucleo deja al anfitrion: A = opcode; aqui solo las de la camara
host_ops:       ld c,a
                and $7F
                cp $12
                jp z,ho_pan
                cp $32
                jp z,ho_set
                cp $60
                jp z,ui_cursorcmd
                cp $7A
                jp z,ui_verbops
                cp $40
                jp z,ui_cutscene
                cp $54
                jp z,ui_setname
                cp $70
                jp z,ho_lights
                cp $22
                jp z,ho_saveload
                cp $18
                jr z,ho_restart
                cp $52
                jr z,ho_fol
                cp $24
                jr z,ho_ego
                ld a,c
                cp $AC                  ; drawSentence
                jp z,ui_sentence
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
                ret
ho_restart:     ld a,1
                ld (rs_flag),a
                ret
ho_ego:         ld a,2                  ; loadRoomWithEgo: la camara salta al protagonista y lo sigue
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
                ld a,1
                ld (cam_new),a
                ret
ho_fol:         ld a,(ARGS)             ; actorFollowCamera
                ld (cam_fol),a
                ld a,2
                ld (cam_mode),a
                ret
ho_pan:         ld a,1                  ; panCameraTo(x): el destino es x * 8
                ld (cam_mode),a
                call cm_arg8
                ld (cam_dest),hl
                ret
ho_set:         xor a                   ; setCameraAt(x): salta ahi
                ld (cam_mode),a
                call cm_arg8
                ld (cam_cx),hl
                call cm_clamp
                jp cm_snap
cm_arg8:        ld a,(ARGS)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ret

; la ventana alcanza el centro de golpe (hasta 160 vueltas de 8 pixeles)
cm_snap:        ld a,(gf_have)
                or a
                ret z
                xor a                   ; sin esperar al VSYNC en cada vuelta
                ld (gd_sync),a
                ld c,160
cn_l:           ld b,8
                push bc
                call cm_show_b
                pop bc
                dec c
                jr nz,cn_l
                ld a,1
                ld (gd_sync),a
                jp gf_flip              ; y una sola copia con VSYNC

; cam_cx entre 128 y ancho - 128 (nuestra ventana mide 256: asi llega a los dos bordes de la sala) y VAR_CAMERA_POS_X =
; cam_cx acotado a VAR_CAMERA_MIN_X..MAX_X (160 y ancho - 160, como en el original) / 8
cm_clamp:       ld hl,(cam_cx)
                ld de,128
                or a
                sbc hl,de
                jr nc,cc1
                ld (cam_cx),de
cc1:            ld hl,(VAR_CAMERA_MAX_X)
                ld de,32
                add hl,de
                ld de,(cam_cx)
                or a
                sbc hl,de
                jr nc,cc2
                ld hl,(VAR_CAMERA_MAX_X)
                ld de,32
                add hl,de
                ld (cam_cx),hl
cc2:            ld bc,(cam_cx)          ; valor de la variable
                ld hl,(VAR_CAMERA_MIN_X)
                ld d,b
                ld e,c
                or a
                sbc hl,de               ; minimo - cx
                jr c,cc3
                ld bc,(VAR_CAMERA_MIN_X)
cc3:            ld hl,(VAR_CAMERA_MAX_X)
                ld d,b
                ld e,c
                or a
                sbc hl,de               ; maximo - cx
                jr nc,cc4
                ld bc,(VAR_CAMERA_MAX_X)
cc4:            ld h,b
                ld l,c
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld (VAR_CAMERA_X),hl
                ret

; la ventana se mueve hacia cam_cx - 128 (entre 0 y el ultimo sitio de la sala), B pixeles como mucho
cm_show_b:      ld hl,(cam_cx)
                ld de,128
                or a
                sbc hl,de
                jr nc,cs1
                ld hl,0
cs1:            ld (cu_t),hl
                ld hl,(gf_npos)
                add hl,hl
                add hl,hl
                add hl,hl
                ex de,hl                ; DE = maximo
                ld hl,(cu_t)
                or a
                sbc hl,de
                jr c,cs2
                ld (cu_t),de
cs2:
cs_l:           push bc
                call gf_campx
                ld de,(cu_t)
                or a
                sbc hl,de               ; actual - objetivo
                jr z,cs_end
                jr c,cs_right
                call gf_move_left
                jr cs_n
cs_right:       call gf_move_right
cs_n:           pop bc
                djnz cs_l
                ret
cs_end:         pop bc
                ret

; un paso de la camara por fotograma
cam_update:     ld a,(gf_have)
                or a
                ret z
                ld a,(cam_mode)
                cp 1
                jr z,cm_pan
                cp 2
                jr z,cm_fol
cm_norm:        call cm_edge            ; sin actor al que seguir, el cursor en el borde de la pantalla la desplaza
                jp cm_fin
cm_pan:         ld hl,(cam_cx)
                ld de,(cam_dest)
                or a
                sbc hl,de
                jp z,cm_fin
                jr c,cp_up
                ld hl,(cam_cx)
                ld de,8
                or a
                sbc hl,de
                ld (cam_cx),hl
                jp cm_fin
cp_up:          ld hl,(cam_cx)
                ld de,8
                add hl,de
                ld (cam_cx),hl
                jp cm_fin
cm_fol:         ld a,(cam_fol)
                cp $FF
                jr nz,cf1
                ld a,(VARS)             ; VAR_EGO
cf1:            cp NACTORS
                jp nc,cm_norm
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,cm_norm
                ld l,(ix+1)             ; destino = x * 8
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(cam_new)
                or a
                jr z,cf2
                xor a                   ; primera vez en la sala: salta
                ld (cam_new),a
                ld a,3                  ; los personajes esperan a que la camara este en su sitio
                ld (ac_hold),a
                ld (cam_cx),hl
                call cm_clamp
                jp cm_snap
cf2:            ld de,(cam_cx)
                or a
                sbc hl,de               ; destino - centro
                jp z,cm_fin
                jr c,cf_l
                ld de,-16               ; a menos de 16 pixeles no se mueve
                add hl,de
                jp nc,cm_fin
                ld hl,(cam_cx)
                ld de,8
                add hl,de
                ld (cam_cx),hl
                jp cm_fin
cf_l:           ld de,16
                add hl,de
                jp c,cm_fin
                ld hl,(cam_cx)
                ld de,8
                or a
                sbc hl,de
                ld (cam_cx),hl
cm_fin:         call cm_clamp
                ld b,4
                jp cm_show_b

; el cursor en el borde derecho (cur_x >= 240) o izquierdo (cur_x <= 8) mueve el centro de la camara
cm_edge:
                IF DEMO = 0
                ld a,(cur_y)            ; en la parte de abajo el borde cambia la ventana de la interfaz (ui_scroll), no la camara
                cp 128
                ret nc
                ld a,(cur_x)
                cp 240
                jr c,ce1
                ld hl,(cam_cx)
                ld de,8
                add hl,de
                ld (cam_cx),hl
                ret
ce1:            cp 9
                ret nc
                ld hl,(cam_cx)
                ld de,8
                or a
                sbc hl,de
                ld (cam_cx),hl
                ENDIF
                ret

