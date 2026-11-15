; ovc7.asm - fase 5b (overlay C): moveCamera de v3 (ScummEngine::moveCamera, version < 7) y camera_moved. Una vez por fotograma desde vm_frame (OVC_MOVECAM), con la sala en uso,
; justo despues de walkActors (como scummLoop). Semantica: vmgame3.move_camera / camera_moved. Estado: CAMCUR, CAMDEST (s16), CAMMODE, CAMFOL, CAMMOV, SSTRIP, VAR_CAMERA_MIN_X /
; MAX_X / FAST_X. snap_scroll (solo lo pone el motor de v7) es siempre 0: snap = VAR_CAMERA_FAST_X <> 0. Temporales en SC: +0 pos (cur al entrar), +2 snap, +4 t, +6 limite derecho.
; Si la camara se ha movido, suceso EV_CAMERA [cur] (como el modelo).

ovc_movecam:    ld hl,(CAMCUR)
                ld (SC+0),hl
                ld hl,(VAR_CAMERA_FAST_X)
                ld a,h
                or l
                ld (SC+2),a
                ld hl,(CAMCUR)
                ld a,l
                and $F8
                ld l,a
                ld (CAMCUR),hl          ; cur &= 0xFFF8
                ld de,(VAR_CAMERA_MIN_X)
                call sless              ; cur < MIN_X ?
                jr nc,mc_1
                ld hl,(CAMCUR)
                ld a,(SC+2)
                or a
                jr z,mc_a
                ld hl,(VAR_CAMERA_MIN_X)
                jr mc_aset
mc_a:           ld de,8
                add hl,de
mc_aset:        ld (CAMCUR),hl
                jp mc_done
mc_1:           ld hl,(VAR_CAMERA_MAX_X)
                ld de,(CAMCUR)
                call sless              ; MAX_X < cur ?
                jr nc,mc_2
                ld hl,(CAMCUR)
                ld a,(SC+2)
                or a
                jr z,mc_b
                ld hl,(VAR_CAMERA_MAX_X)
                jr mc_bset
mc_b:           ld de,-8
                add hl,de
mc_bset:        ld (CAMCUR),hl
                jp mc_done
mc_2:           ld a,(CAMMODE)
                cp CAM_FOLLOW
                jr nz,mc_3
                ld a,(CAMFOL)
                call actor_ix           ; IX = el actor al que sigue
                call mc_t               ; HL = t = x // 8 - _screenStartStrip
                ld (SC+4),hl
                ld de,CAM_LEFT
                call sless
                jr c,mc_out             ; t < left
                ld hl,CAM_RIGHT
                ld de,(SC+4)
                call sless
                jr nc,mc_3              ; right < t ?
mc_out:         ld a,(SC+2)
                or a
                jr z,mc_mov
                ld hl,35                ; snap: t > 40 - 5: dest = x + 80
                ld de,(SC+4)
                call sless
                jr nc,mc_s1
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,80
                add hl,de
                ld (CAMDEST),hl
mc_s1:          ld hl,(SC+4)            ; t < 5: dest = x - 80
                ld de,5
                call sless
                jr nc,mc_3
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,-80
                add hl,de
                ld (CAMDEST),hl
                jr mc_3
mc_mov:         ld a,1
                ld (CAMMOV),a           ; _movingToActor = true
mc_3:           ld a,(CAMMOV)
                or a
                jr z,mc_4
                ld a,(CAMFOL)
                call actor_ix
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld (CAMDEST),hl         ; dest = x del actor
mc_4:           ld hl,(CAMDEST)
                ld de,(VAR_CAMERA_MIN_X)
                call sless
                jr nc,mc_5
                ld hl,(VAR_CAMERA_MIN_X)
                ld (CAMDEST),hl
mc_5:           ld hl,(VAR_CAMERA_MAX_X)
                ld de,(CAMDEST)
                call sless
                jr nc,mc_6
                ld hl,(VAR_CAMERA_MAX_X)
                ld (CAMDEST),hl
mc_6:           ld a,(SC+2)
                or a
                jr z,mc_7
                ld hl,(CAMDEST)         ; snap: cur = dest
                ld (CAMCUR),hl
                jr mc_8
mc_7:           ld hl,(CAMCUR)
                ld de,(CAMDEST)
                call sless
                jr nc,mc_7b
                ld hl,(CAMCUR)          ; cur < dest: cur += 8
                ld de,8
                add hl,de
                ld (CAMCUR),hl
mc_7b:          ld hl,(CAMDEST)
                ld de,(CAMCUR)
                call sless
                jr nc,mc_8
                ld hl,(CAMCUR)          ; cur > dest: cur -= 8
                ld de,-8
                add hl,de
                ld (CAMCUR),hl
mc_8:           ld a,(CAMMOV)
                or a
                jr z,mc_done
                ld a,(CAMFOL)
                call actor_ix
                ld hl,(CAMCUR)          ; si ya esta en la columna del actor, deja de ir hacia el
                sra h
                rr l
                sra h
                rr l
                sra h
                rr l
                ex de,hl
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                sra h
                rr l
                sra h
                rr l
                sra h
                rr l
                or a
                sbc hl,de
                jr nz,mc_done
                xor a
                ld (CAMMOV),a
mc_done:        call camera_moved
                ld hl,(SC+0)
                ld de,(CAMCUR)
                or a
                sbc hl,de
                ret z
                ld (EVARGS),de
                ld a,EV_CAMERA
                jp ev_emit

; IX = actor -> HL = x // 8 - _screenStartStrip
mc_t:           ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                sra h
                rr l
                sra h
                rr l
                sra h
                rr l
                ld de,(SSTRIP)
                or a
                sbc hl,de
                ret

; camera_moved: cur dentro de [160, ancho de la sala - 160] y _screenStartStrip = cur // 8 - 20
camera_moved:   ld hl,(CURRD+6)         ; ancho de la sala en uso (0: no hay, 320)
                ld a,h
                or l
                jr nz,cmv_w
                ld hl,320
cmv_w:          ld de,-160
                add hl,de
                ld (SC+6),hl
                ld hl,(CAMCUR)
                ld de,160
                call sless
                jr nc,cmv_1
                ld hl,160
                ld (CAMCUR),hl
                jr cmv_s
cmv_1:          ld hl,(SC+6)
                ld de,(CAMCUR)
                call sless              ; ancho - 160 < cur ?
                jr nc,cmv_s
                ld hl,(SC+6)
                ld (CAMCUR),hl
cmv_s:          ld hl,(CAMCUR)
                sra h
                rr l
                sra h
                rr l
                sra h
                rr l
                ld de,-20
                add hl,de
                ld (SSTRIP),hl
                ret
