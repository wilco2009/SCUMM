; =====================================================================
;  snd.asm - sonido (overlay). Player_V2::startSound / stopSound / getSoundStatus / chainNextSound de ScummVM: un sonido a la vez, con
;  prioridad, y un sonido en cola ("next") si el que se desplaza es reiniciable. Cada sonido es un fichero VGM del chip AY
;  (TOOLS/sound2vgm.py) que reproduce el MCU en segundo plano (ordenes PLAY_VGM 34, STOP_VGM 35 y LOOP_VGM 38); el Z80 solo cuenta
;  los fotogramas que le quedan al sonido actual para saber cuando acaba.
;  Datos del juego: el nombre de los ficheros (perfil, PF_SNDTPL y PF_SNDPOS) y la tabla de sonidos (DATA.BIN, ld_hdr+10: pagina y
;  direccion): 4 bytes por sonido: prioridad, banderas (bit 0 reiniciable, bit 1 bucle, bit 7 existe) y duracion en fotogramas
;  (65535: hasta que se pare).
; =====================================================================
SND_REST        equ 1
SND_LOOP        equ 2
SND_NAME        equ $DC20             ; el nombre del fichero se compone aqui (fuera de BACKBUF, que guarda la sala para la oscuridad)

; A = suceso (EV_SOUND_*), EVARGS = sonido
snd_event:      cp EV_SOUND_STOPALL
                jr z,sdx_stopall
                ld c,a                  ; C = suceso
                cp EV_SOUND_QUERY
                jr nz,sdx_se_nq
                ld hl,0
                ld (HRES),hl            ; resultado por omision: no suena
sdx_se_nq:          ld hl,(EVARGS)
                ld a,h
                or a
                jr nz,sdx_ign            ; los sonidos van de 0 a 255
                ld a,l
                ld b,c
                ld c,a                  ; C = sonido
                ld a,b
                cp EV_SOUND_START
                jr z,sdx_start
                cp EV_SOUND_STOP
                jr z,sdx_stop
                cp EV_SOUND_QUERY
                jr nz,sdx_ign
; getSoundStatus: 1 si es el actual o el siguiente
                ld a,c
                or a
                jr z,sdx_ign
                ld hl,sdx_cur
                cp (hl)
                jr z,sdx_sq_y
                ld hl,sdx_next
                cp (hl)
                jr nz,sdx_ign
sdx_sq_y:           ld hl,1
                ld (HRES),hl
sdx_ign:         jp sdx_remap

sdx_stopall:     call sdx_stopvgm
                xor a
                ld (sdx_cur),a
                ld (sdx_next),a
                jp sdx_remap

; stopSound: si es el siguiente se quita; si es el actual se para y entra el siguiente
sdx_stop:        ld a,(sdx_next)
                cp c
                jr nz,sdx_ss_c
                xor a
                ld (sdx_next),a
sdx_ss_c:           ld a,(sdx_cur)
                cp c
                jr nz,sdx_ign
                call sdx_stopvgm
                xor a
                ld (sdx_cur),a
                call sdx_chain_next
                jp sdx_remap

; startSound(C)
sdx_start:       ld a,c
                or a
                jr z,sdx_ign
                ld (sdx_nn),a
                call sdx_idx             ; B = prioridad, C = banderas, DE = duracion
                jr c,sdx_ign             ; sin fichero: no suena
                ld a,b
                ld (sdx_np),a
                ld a,c
                ld (sdx_nf),a
                ld (sdx_nd),de
                ld a,(sdx_cur)
                or a
                jr z,sdx_st_chain
                ld a,(sdx_cprio)
                ld hl,sdx_np
                cp (hl)                 ; cprio <= prio: el nuevo pasa a sonar
                jr z,sdx_st_chain
                jr c,sdx_st_chain
; el actual manda: el nuevo solo queda en cola si es reiniciable
                ld a,(sdx_nf)
                and SND_REST
                jr z,sdx_ign
                ld a,(sdx_nn)
                ld c,a
                ld a,(sdx_np)
                ld b,a
                jr sdx_st_cand
; el nuevo pasa a ser el actual; el que sonaba pasa a la cola si es reiniciable
sdx_st_chain:       ld a,(sdx_cur)
                ld c,a                  ; C = el que se desplaza (0: ninguno)
                ld a,(sdx_cprio)
                ld b,a                  ; B = su prioridad
                ld a,(sdx_crest)
                ld d,a                  ; D = si es reiniciable
                push bc
                push de
                call sdx_chain
                pop de
                pop bc
                ld a,c
                or a
                jr z,sdx_ign
                ld a,d
                or a
                jp z,sdx_ign
; candidato a la cola: C = sonido, B = prioridad
sdx_st_cand:        ld a,(sdx_cur)
                cp c
                jp z,sdx_ign             ; el que suena ya es ese
                ld a,(sdx_next)
                or a
                jr z,sdx_st_q
                ld a,(sdx_nprio)
                cp b                    ; nprio <= prio
                jr z,sdx_st_q
                jp nc,sdx_ign
sdx_st_q:           ld a,c
                ld (sdx_next),a
                ld a,b
                ld (sdx_nprio),a
                jp sdx_ign

; cada fotograma: al sonido actual le quedan menos
snd_tick:       ld a,(sdx_cur)
                or a
                ret z
                call sdx_mtimer
                ld hl,(sdx_left)
                ld a,h
                and l
                inc a
                ret z                   ; 65535: no acaba solo
                ld a,(DELTA)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jr c,sdx_sk_end
                jr z,sdx_sk_end
                ld (sdx_left),hl
                ret
sdx_sk_end:         xor a
                ld (sdx_cur),a
                jp sdx_chain_next

; chainNextSound: si hay uno en cola, pasa a sonar
sdx_chain_next:  ld a,(sdx_next)
                or a
                ret z
                ld (sdx_nn),a
                xor a
                ld (sdx_next),a
                ld a,(sdx_nn)
                call sdx_idx
                ret c
                ld a,b
                ld (sdx_np),a
                ld a,c
                ld (sdx_nf),a
                ld (sdx_nd),de
                jr sdx_chain

; A = sonido -> B = prioridad, C = banderas, DE = duracion; carry si no existe
sdx_idx:         push af
                ld a,(ld_hdr+10)
                or a
                jr z,sdx_si_no
                call map_page
                pop af
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,(ld_hdr+11)
                add hl,de
                ld b,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                bit 7,c
                jr z,sdx_si_no2
                or a
                ret
sdx_si_no:          pop af
sdx_si_no2:         scf
                ret

; reproduce el sonido sdx_nn (prioridad sdx_np, banderas sdx_nf, duracion sdx_nd): pasa a ser el actual
sdx_chain:       call sdx_tinfo
                ld a,(sdx_nn)
                ld (sdx_cur),a
                ld a,(sdx_np)
                ld (sdx_cprio),a
                ld a,(sdx_nf)
                and SND_REST
                ld (sdx_crest),a
                ld hl,(sdx_nd)
                ld a,(sdx_nf)
                and SND_LOOP
                jr z,sdx_sc_dur
                ld hl,65535
sdx_sc_dur:         ld (sdx_left),hl
                call sdx_stopvgm
                ld a,CMD_LOOPVGM
                call mcu_send
                ld a,(sdx_nf)
                and SND_LOOP
                jr z,sdx_sc_l0
                ld a,1
sdx_sc_l0:          call mcu_send
                ld hl,(PF_SNDTPL)       ; el nombre: la plantilla del perfil con las tres cifras del sonido
                ld de,PROF
                add hl,de
                ld de,SND_NAME
sdx_sc_n:           ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,sdx_sc_n
                ld a,(PF_SNDPOS)
                ld e,a
                ld d,0
                ld hl,SND_NAME
                add hl,de
                ld a,(sdx_nn)
                ld b,'0'-1
sdx_sc_h:           inc b
                sub 100
                jr nc,sdx_sc_h
                add a,100
                ld (hl),b
                inc hl
                ld b,'0'-1
sdx_sc_t:           inc b
                sub 10
                jr nc,sdx_sc_t
                add a,10+'0'
                ld (hl),b
                inc hl
                ld (hl),a
                ld hl,SND_NAME          ; PLAY_VGM: orden, longitud, nombre; responde el estado
                ld b,0
sdx_sc_len:         ld a,(hl)
                or a
                jr z,sdx_sc_go
                inc hl
                inc b
                jr sdx_sc_len
sdx_sc_go:          ld hl,SND_NAME
                ld a,CMD_PLAYVGM
                call mcu_send
                ld a,b
                call mcu_send
                inc b
                jr sdx_sc_pt
sdx_sc_ps:          ld a,(hl)
                inc hl
                call sdx_zx             ; PLAY_VGM espera el nombre en codigos del ZX81
                call mcu_send
sdx_sc_pt:          djnz sdx_sc_ps
                jp mcu_recv

; A = ASCII (espacio, '.', '/', cifras, mayusculas) -> codigo del ZX81
sdx_zx:          cp '/'
                jr nz,sdx_zx1
                ld a,$18
                ret
sdx_zx1:            cp '.'
                jr nz,sdx_zx2
                ld a,$1B
                ret
sdx_zx2:            cp 'A'
                jr c,sdx_zx3
                sub 'A'-$26
                ret
sdx_zx3:            cp '0'
                ret c                   ; el espacio y lo demas: 0
                sub '0'-$1C
                ret

sdx_stopvgm:     ld a,CMD_STOPVGM
                jp mcu_send

; los sucesos llegan en mitad de un script: la ventana de datos vuelve a la pagina del script que se esta ejecutando
sdx_remap:       ld a,(CUR)
                cp $FF
                ret z
                call slot_addr
                ld de,4
                add hl,de
                ld a,(hl)
                jp map_page

; VAR_MUSIC_TIMER: la tabla de sonidos tiene detras otra de 4 bytes por sonido (valor inicial, 0, intervalo en 1/8 de fotograma);
; al arrancar el sonido sdx_nn se pone el valor inicial y despues sube 1 cada intervalo
sdx_tinfo:       push de
                push hl
                ld a,(ld_hdr+10)
                or a
                jr z,sdx_ti_no
                call map_page
                ld a,(sdx_nn)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,(ld_hdr+11)
                add hl,de
                ld de,1024
                add hl,de
                ld a,(hl)
                inc hl
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (sdx_tstep),de
                ld (sdx_tctr),de
                ld l,a
                ld h,0
                jr sdx_ti_set
sdx_ti_no:          ld hl,0
                ld (sdx_tstep),hl
sdx_ti_set:         ld (VAR_MUSIC_TIMER),hl
                pop hl
                pop de
                ret

; cada fotograma
sdx_mtimer:      push bc
                push de
                push hl
                ld hl,(sdx_tstep)
                ld a,h
                or l
                jr z,sdx_mt_x
                ld b,h
                ld c,l                  ; BC = intervalo
                ld a,(DELTA)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ex de,hl                ; DE = fotogramas * 8
                ld hl,(sdx_tctr)
                or a
                sbc hl,de
sdx_mt_l:           bit 7,h
                jr nz,sdx_mt_t
                ld a,h
                or l
                jr nz,sdx_mt_s
sdx_mt_t:           add hl,bc
                push hl
                ld hl,(VAR_MUSIC_TIMER)
                inc hl
                ld (VAR_MUSIC_TIMER),hl
                pop hl
                jr sdx_mt_l
sdx_mt_s:           ld (sdx_tctr),hl
sdx_mt_x:           pop hl
                pop de
                pop bc
                ret

sdx_ini:         xor a
                ld (fl_xs),a
                ld (fl_ys),a
                ld (dk_ok),a
                ld (sdx_tstep),a
                ld (sdx_tstep+1),a
                ld (sdx_cur),a
                ld (sdx_next),a
                ret
