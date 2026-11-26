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
                jp z,ovg_ho
                cp $7A
                jp z,ui_verbops
                cp $40
                jp z,ovg_ho
                cp $54
                jp z,ui_setname
                cp $70
                jp z,ovg_ho
                cp $22
                jp z,ho_saveload
                cp $18
                jr z,ho_restart
                cp $33
                jp z,ovg_ho
                cp $52
                jp z,ho_fol
                cp $24
                jp z,ho_ego
                ld a,c
                cp $CC                  ; pseudoRoom
                jr z,ho_pseudo
                ld a,c
                cp $AC                  ; drawSentence
                jp z,ui_sentence
                ret
; pseudoRoom(real, sala, sala, ..., 0): _resourceMapper[sala & $7F] = real para las salas >= 128 (MAPTAB, game.asm); ARGS = real y las salas (palabras)
ho_pseudo:      ld a,(ARGN)
                dec a
                ret z
                ld b,a
                ld hl,ARGS+2
hps_l:           ld a,(hl)
                inc hl
                inc hl
                sub 128
                jr c,hps_n
                cp PSEUDO_N
                jr nc,hps_n
                ld e,a
                ld d,0
                push hl
                ld hl,MAPTAB+128
                add hl,de
                ld a,(ARGS)
                ld (hl),a
                pop hl
hps_n:           djnz hps_l
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
                push ix                 ; (el nucleo usa IX)
                call he_pos
                pop ix
                ret
he_pos:         ld a,(VARS)             ; o2_loadRoomWithEgo (script_v2.cpp:1461-1463): camera._cur.x = camera._dest.x = x del protagonista, en el acto: lo que un script haga a
                call cp_act             ; continuacion (panCameraTo, setCameraAt) parte de ahi. El salto de la ventana (cam_new) espera a que la sala este lista (cam_update)
                ret nc
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld l,(ix+1)
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld (cam_cx),hl
                jp cm_clamp
ho_fol:         push ix                 ; (el nucleo usa IX)
                call hf_do
                pop ix
                ret
hf_do:          ld a,2                  ; actorFollowCamera (setCameraFollows + setCameraAt, camera.cpp:34-48,62-86): sigue al actor; no se esta moviendo hacia el (modo 2)
                ld (cam_mode),a
                ld a,(ARGS)
                ld (cam_fol),a
                call cp_act
                ret nc
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld l,(ix+1)             ; HL = x del actor en pixeles
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(cam_cx)
                or a
                sbc hl,de
                jr nc,fo1
                ld a,h                  ; |actor - centro|
                cpl
                ld h,a
                ld a,l
                cpl
                ld l,a
                inc hl
fo1:            ld de,-161              ; a mas de 160 (_screenWidth / 2): la camara salta (si no, el barrido lo hace cm_fol al pasar de los disparadores)
                add hl,de
                ret nc
                ld l,(ix+1)
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld (cam_cx),hl
                call cm_clamp
                jp cm_snap
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

; la ventana alcanza el centro de golpe: la camara salta y se vuelve a dibujar la sala
cm_snap:        ld a,(gf_have)
                or a
                ret z
                call cm_target
                ld hl,(cu_t)
                jp gf_jump

; cam_cx entre 128 y ancho - 128 (nuestra ventana mide 256: asi llega a los dos bordes de la sala) y VAR_CAMERA_POS_X =
; cam_cx acotado a VAR_CAMERA_MIN_X..MAX_X (160 y ancho - 160, como en el original) / 8
cm_clamp:       ld hl,(VAR_CAMERA_MIN_X)        ; minimo del centro = VAR_CAMERA_MIN_X - 32 (160 - 32 = 128 por omision)
                ld de,-32
                add hl,de
                ex de,hl
                ld hl,(cam_cx)
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

; el objetivo de la camara, en pixeles: cam_cx - 128 entre 0 y el ultimo sitio de la sala -> cu_t
cm_target:      ld hl,(cam_cx)
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
                ret c
                ld (cu_t),de
                ret

; la camara logica se mueve hacia cam_cx - 128 (entre 0 y el ultimo sitio de la sala), B pixeles como mucho (el hardware la sigue: hr_frame)
cm_show_b:      push bc
                call cm_target
                pop bc
cs_l:           push bc
                call gf_lpos
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
                ld a,(cam_new)          ; salto pendiente tras cargar la sala con la camara ya fijada por un script (modos 0 y 1): la ventana salta a cam_cx;
                or a                    ; en los modos 2 y 3 lo hace cm_fol sobre el actor
                jr z,cu_a
                ld a,(cam_mode)
                cp 2
                jr nc,cu_a
                xor a
                ld (cam_new),a
                ld a,3
                ld (ac_hold),a
                call cm_clamp
                jp cm_snap
cu_a:           ld a,(cam_mode)
                cp 1
                jr z,cm_pan
                cp 2
                jr z,cm_fol
                cp 3
                jr z,cm_fol
cm_norm:        call cm_edge            ; sin actor al que seguir, el cursor en el borde de la pantalla la desplaza
                jp cm_fin
cm_pan:         ld hl,(cam_cx)
                ld de,(cam_dest)
                or a
                sbc hl,de
                jp z,cp_end
                jr c,cp_up
                ld hl,(cam_cx)
                ld de,8
                or a
                sbc hl,de
                ld (cam_cx),hl
                jp cm_fin
; el pan ha llegado: la camara queda quieta y el cursor en el borde puede desplazarla (cm_edge); el destino la acompana. Nuestra ventana (256) es mas estrecha
; que la pantalla original (320): un script que reanuda el seguimiento al pasar de cierta x (sala 3, x < 656) deja el limite izquierdo de la ventana por encima de esa x
; y el protagonista no podria llegar a ella nunca
cp_end:         call cm_edge
                call cm_clamp
                ld hl,(cam_cx)
                ld (cam_dest),hl
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
cf1:            call cp_act
                jp nc,cm_norm
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,cm_norm
                ld c,(ix+1)             ; BC = x / 8 (celdas); destino = x * 8
                ld b,(ix+2)
                ld h,b
                ld l,c
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
; seguimiento de moveCamera (camera.cpp:119-159): BC = celda del actor (x / 8). Modo 2: la camara espera; cuando el actor pasa a mas de 10 celdas (80 pixeles; los
; disparadores 10 y 30 de ScummVM sobre 40 tiras, centro en la 20) del centro, pasa al modo 3 (_movingToActor): va tras el a 8 pixeles por fotograma hasta que
; la celda de la camara es la suya y vuelve al modo 2. Adaptacion: nuestra ventana mide 256 (32 celdas), los +-80 caben dentro (hay 48 pixeles de margen) y
; cm_clamp (cm_fin) hace de limite del destino (128..ancho-128, no 160..ancho-160: la ventana estrecha llega asi a los dos bordes de la sala)
; el actor no se ha movido y la camara no va tras el (modo 2): sigue donde esta, y el cursor en el borde de la pantalla puede desplazarla (cm_edge). Nuestra ventana
; (256) es mas estrecha que la pantalla del original (320): sin esto el actor parado en un extremo la dejaria pegada a el, sin poder ver el otro lado (p. ej. la sala 30).
; En cuanto el actor se mueve vale la regla de ScummVM (disparadores de 80 pixeles)
cf2:            ld hl,cm_lx
                ld a,c
                cp (hl)
                ld (hl),a
                jr nz,cf_go
                ld a,(cam_mode)
                cp 3
                jp nz,cm_norm
cf_go:
                ld a,(cam_mode)
                cp 3
                jr z,cf_mv
                ld hl,(cam_cx)
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                or a
                sbc hl,bc               ; centro - actor, en celdas
                ld de,10
                add hl,de
                ld de,21
                or a
                sbc hl,de               ; -10..10: dentro de la zona muerta
                jr c,cm_fin
                ld a,3
                ld (cam_mode),a
cf_mv:          ld h,b
                ld l,c
                add hl,hl
                add hl,hl
                add hl,hl
                ex de,hl                ; DE = x del actor en pixeles
                ld hl,(cam_cx)
                push hl                 ; centro de antes
                or a
                sbc hl,de
                jr z,cf_a
                ld hl,(cam_cx)
                ld de,8
                jr c,cf_p
                or a
                sbc hl,de
                jr cf_s
cf_p:           add hl,de
cf_s:           ld (cam_cx),hl
                call cm_clamp
cf_a:           pop de
                ld c,(ix+1)             ; (cm_clamp destruye BC)
                ld b,(ix+2)
                ld hl,(cam_cx)
                or a
                sbc hl,de
                jr z,cf_arr             ; la camara no se ha movido (en el limite del recorrido o ya esta): llegada
                ld hl,(cam_cx)
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                or a
                sbc hl,bc
                jr nz,cm_fin
cf_arr:         ld a,2                  ; ha llegado: de nuevo a esperar
                ld (cam_mode),a
cm_fin:         call cm_clamp
                ld b,4
                jp cm_show_b

; el cursor en el borde derecho (cur_x >= 240) o izquierdo (cur_x <= 8) mueve el centro de la camara
cm_edge:
                IF DEMO = 0
                ld a,(UI_CURSOR)        ; cursor apagado (cutscene, camara fijada por el script): el borde no la mueve
                or a
                ret z
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

