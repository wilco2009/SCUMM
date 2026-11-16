; =====================================================================
;  snd3.asm - sonido del programa de v3 (fase 8; sustituye al simulado de la fase 5b). Player_V2 de ScummVM (startSound / stopSound / getSoundStatus /
;  chainSound / chainNextSound): un sonido a la vez, con prioridad, y uno en cola si el desplazado es reiniciable. Cada sonido es un fichero VGM del chip AY
;  (TOOLS/sound3vgm.py) que reproduce el MCU en segundo plano (PLAY_VGM 34, STOP_VGM 35 y LOOP_VGM 38); el Z80 cuenta los fotogramas que le quedan al
;  actual para saber cuando acaba, y lleva VAR_MUSIC_TIMER como Player_V2Base (modelo: vmgame3.py, modo "real"; las reglas estan alli).
;  La tabla de sonidos esta en DATA.BIN (ld_hdr+10: pagina y direccion): 4 bytes por sonido: prioridad, banderas (bit 0 reiniciable, bit 1 bucle, bit 2 fija el
;  tempo, bit 3 cancion, bit 7 existe) y duracion en fotogramas de 50 Hz (65535: hasta que se pare). Los sucesos llegan desde el nucleo (ev_handler) en mitad de
;  un script: la ventana de datos (bloque 1) vuelve a la pagina del script al acabar (restore_win).
; =====================================================================
SND_REST        equ 1
SND_LOOP        equ 2
SND_TEMPO       equ 4
SND_NAME        equ $9720               ; el nombre del fichero se compone aqui
PF_SNDTPL       equ PROF+15             ; desplazamiento del nombre de los ficheros de sonido en el perfil, y posicion de sus tres cifras
PF_SNDPOS       equ PROF+17
sd_cur          equ SV+162              ; sonido actual (0: ninguno), su prioridad, si es reiniciable, los fotogramas que le quedan (65535: no acaba) y el que espera
sd_cprio        equ SV+163
sd_crest        equ SV+164
sd_next         equ SV+165
sd_left         equ SV+166              ; palabra
sd_nn           equ SV+168              ; el sonido que se trata: numero, prioridad, banderas y duracion
sd_np           equ SV+169
sd_nf           equ SV+170
sd_nd           equ SV+171              ; palabra
sd_nprio        equ SV+173              ; prioridad del que espera
sd_qn           equ SV+174              ; candidato a la cola: numero, prioridad, reiniciable
sd_qp           equ SV+175
sd_qr           equ SV+177

snd_init:       ld hl,SV+162
                ld de,SV+163
                ld bc,13
                ld (hl),0
                ldir
                ld hl,0
                ld (snd_mt),hl
                ld (snd_ctr),hl
                ld (snd_acc),hl
                dec hl
                ld (snd_tpm),hl         ; 65535
                ret

; EVARGS = sonido. Todo termina en snd_end (la ventana vuelve a su pagina)
snd_start:      call sd_start
                jp sd_end
snd_stop:       call sd_stop
                jp sd_end
snd_stopall:    call sd_stopvgm
                xor a
                ld (sd_cur),a
                ld (sd_next),a
                ret
sd_end:         jp restore_win
snd_query:      ld hl,0                 ; HRES = 1 si es el actual o el que espera
                ld (HRES),hl
                ld hl,(EVARGS)
                ld a,h
                or a
                ret nz
                ld a,l
                or a
                ret z
                ld hl,sd_cur
                cp (hl)
                jr z,sq_y
                ld hl,sd_next
                cp (hl)
                ret nz
sq_y:           ld hl,1
                ld (HRES),hl
                ret

; Player_V2::startSound
sd_start:       ld hl,(EVARGS)
                ld a,h
                or a
                ret nz                  ; los sonidos van de 1 a 255
                ld a,l
                or a
                ret z
                ld (sd_nn),a
                call sd_idx             ; B = prioridad, C = banderas, DE = duracion; carry si no existe (no suena)
                ret c
                ld a,b
                ld (sd_np),a
                ld (sd_qp),a
                ld a,c
                ld (sd_nf),a
                and SND_REST
                ld (sd_qr),a
                ld (sd_nd),de
                ld a,(sd_nn)
                ld (sd_qn),a            ; candidato a la cola: el nuevo (si no pasa a sonar)
                xor a
                ld (sd_nprio),a
                ld a,(sd_next)
                or a
                jr z,ss_np
                call sd_idx
                jr c,ss_np
                ld a,b
                ld (sd_nprio),a         ; la prioridad del que espera
ss_np:          ld a,(sd_cur)
                or a
                jr z,ss_chain
                ld a,(sd_cprio)
                ld hl,sd_np
                cp (hl)                 ; cprio <= prio: el nuevo pasa a sonar
                jr z,ss_chain
                jr nc,ss_cand
ss_chain:       ld a,(sd_cur)           ; el que se desplaza es el candidato (0: ninguno)
                ld (sd_qn),a
                or a
                ld a,0
                jr z,ss_c0
                ld a,(sd_cprio)
ss_c0:          ld (sd_qp),a
                ld a,(sd_cur)
                or a
                ld a,0
                jr z,ss_c1
                ld a,(sd_crest)
ss_c1:          ld (sd_qr),a
                call sd_chain
ss_cand:        ld a,(sd_qn)            ; nr != _current_nr && restartable && (!_next_nr || nprio <= prio)
                ld hl,sd_cur
                cp (hl)
                ret z
                ld a,(sd_qr)
                or a
                ret z
                ld a,(sd_next)
                or a
                jr z,ss_q
                ld a,(sd_nprio)
                ld hl,sd_qp
                cp (hl)
                jr z,ss_q
                ret nc
ss_q:           ld a,(sd_qn)
                ld (sd_next),a
                ret

; Player_V2::stopSound
sd_stop:        ld hl,(EVARGS)
                ld a,h
                or a
                ret nz
                ld a,l
                ld hl,sd_next
                cp (hl)
                jr nz,sp_c
                ld (hl),0
sp_c:           ld hl,sd_cur
                cp (hl)
                ret nz
                or a
                ret z
                call sd_stopvgm
                xor a
                ld (sd_cur),a
                ; sigue en sd_chain_next

; Player_V2Base::chainNextSound
sd_chain_next:  ld a,(sd_next)
                or a
                ret z
                ld (sd_nn),a
                xor a
                ld (sd_next),a
                ld a,(sd_nn)
                call sd_idx
                ret c
                ld a,b
                ld (sd_np),a
                ld a,c
                ld (sd_nf),a
                ld (sd_nd),de
                ; sigue en sd_chain

; Player_V2Base::chainSound: el sonido sd_nn (prioridad sd_np, banderas sd_nf, duracion sd_nd) pasa a ser el actual
sd_chain:       ld a,(sd_nn)
                ld (sd_cur),a
                ld a,(sd_np)
                ld (sd_cprio),a
                ld a,(sd_nf)
                and SND_REST
                ld (sd_crest),a
                ld hl,(sd_nd)
                ld a,(sd_nf)
                and SND_LOOP
                jr z,sc_dur
                ld hl,65535
sc_dur:         ld (sd_left),hl
                ld hl,0
                ld (snd_mt),hl          ; _music_timer = 0 (el contador de ticks no)
                ld a,(sd_nf)
                and SND_TEMPO
                jr z,sc_nt
                ld hl,125
                ld (snd_tpm),hl         ; el sonido fija el tempo (0xFF 14): +1 cada 126 ticks desde ahora y para siempre
sc_nt:          call sd_stopvgm
                ld a,CMD_LOOPVGM
                call mcu_send
                ld a,(sd_nf)
                and SND_LOOP
                jr z,sc_l0
                ld a,1
sc_l0:          call mcu_send
                ld hl,(PF_SNDTPL)       ; el nombre: la plantilla del perfil con las tres cifras del sonido
                ld de,PROF
                add hl,de
                ld de,SND_NAME
sc_n:           ld a,(hl)
                ld (de),a
                inc hl
                inc de
                or a
                jr nz,sc_n
                ld a,(PF_SNDPOS)
                ld e,a
                ld d,0
                ld hl,SND_NAME
                add hl,de
                ld a,(sd_nn)
                ld b,'0'-1
sc_h:           inc b
                sub 100
                jr nc,sc_h
                add a,100
                ld (hl),b
                inc hl
                ld b,'0'-1
sc_t:           inc b
                sub 10
                jr nc,sc_t
                add a,10+'0'
                ld (hl),b
                inc hl
                ld (hl),a
                ld hl,SND_NAME          ; PLAY_VGM: orden, longitud, nombre; responde el estado
                ld b,0
sc_len:         ld a,(hl)
                or a
                jr z,sc_go
                inc hl
                inc b
                jr sc_len
sc_go:          ld hl,SND_NAME
                ld a,CMD_PLAYVGM
                call mcu_send
                ld a,b
                call mcu_send
                inc b
                jr sc_pt
sc_ps:          ld a,(hl)
                inc hl
                call sd_zx              ; PLAY_VGM espera el nombre en codigos del ZX81
                call mcu_send
sc_pt:          djnz sc_ps
                jp mcu_recv

; A = ASCII (espacio, '.', '/', cifras, mayusculas) -> codigo del ZX81
sd_zx:          cp '/'
                jr nz,sz1
                ld a,$18
                ret
sz1:            cp '.'
                jr nz,sz2
                ld a,$1B
                ret
sz2:            cp 'A'
                jr c,sz3
                sub 'A'-$26
                ret
sz3:            cp '0'
                ret c                   ; el espacio y lo demas: 0
                sub '0'-$1C
                ret

sd_stopvgm:     ld a,CMD_STOPVGM
                jp mcu_send

; A = sonido -> B = prioridad, C = banderas, DE = duracion; carry si no existe. Cambia la ventana de datos (el que llama la deja con restore_win)
sd_idx:         push af
                ld a,(ld_hdr+10)
                or a
                jr z,si_no
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
                jr z,si_no2
                or a
                ret
si_no:          pop af
si_no2:         scf
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Cada fotograma (desde vm_frame, antes de runAllScripts), con DELTA (fotogramas de 50 Hz): Player_V2Base::nextTick a 236 Hz, Sound::updateMusicTimer y el
;  fin del sonido actual
; ---------------------------------------------------------------------------------------------------------------------------------
snd_tick:       ld a,(DELTA)
                ld c,a
                ld hl,(snd_acc)
                ld de,236
                or a
                jr z,st_w
st_mul:         add hl,de               ; music_acc += delta * 236
                dec c
                jr nz,st_mul
                ld (snd_acc),hl
st_w:           ld hl,(snd_acc)
                ld de,50
                or a
                sbc hl,de
                jr c,st_t
                ld (snd_acc),hl         ; while music_acc >= 50: -= 50, un tick
                ld hl,(snd_ctr)
                ld de,(snd_tpm)
                or a
                sbc hl,de               ; music_ctr >= ticks_per_music_timer ?
                jr c,st_inc
                ld hl,0
                ld (snd_ctr),hl
                ld hl,(snd_mt)
                inc hl
                ld (snd_mt),hl
                jr st_w
st_inc:         ld hl,(snd_ctr)
                inc hl
                ld (snd_ctr),hl
                jr st_w
; VAR_MUSIC_TIMER = t - ((t * 14438 + 2^20 - 1) >> 20)  (vmgame3.music_var)
st_t:           ld de,(snd_mt)
                ld bc,14438
                call sd_mul16           ; DE:HL = t * 14438
                ld a,h
                or l
                ld hl,15
                jr z,st_q
                inc hl                  ; 15 + (la parte baja no es 0)
st_q:           add hl,de               ; + la parte alta
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l                    ; >> 4 (= >> 20 del producto)
                ex de,hl
                ld hl,(snd_mt)
                or a
                sbc hl,de
                ld (VAR_MUSIC_TIMER),hl
                ld hl,(sd_left)         ; al actual se le quitan los fotogramas
                ld a,(sd_cur)
                or a
                ret z
                ld a,h
                and l
                inc a
                ret z                   ; 65535: no acaba solo
                ld a,(DELTA)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jr c,st_end
                jr z,st_end
                ld (sd_left),hl
                ret
st_end:         xor a
                ld (sd_cur),a
                call sd_chain_next
                jp sd_end

; DE:HL = BC * DE (sin signo)
sd_mul16:       ld hl,0
                ld a,16
sm_l:           add hl,hl
                rl e
                rl d
                jr nc,sm_n
                add hl,bc
                jr nc,sm_n
                inc de
sm_n:           dec a
                jr nz,sm_l
                ret
