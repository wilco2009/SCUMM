; =====================================================================
;  scumm.asm (v3, fase 5b) - el programa completo del interprete SCUMM v3 (Indy3 EGA) para el ZX81 con SD81 Booster: nucleo (vm_core.asm y los overlays B, C y D),
;  carga de datos (loader.asm), video HiRes con el diseno D3 (hr.asm), camara, sonido simulado y el bucle principal.
;  Plan: SCUMM/V3/PLAN.md; mapa de memoria: SCUMM/V3/FASE3.md; esta fase: FASE3.md, "Fase 5b".
;
;  Fase 7 (ui3.asm, vm_input.asm): interfaz de verbos, frase e inventario en las filas de abajo, mensajes en las 2 de arriba, cursor, raton y teclado (clics, teclas de verbo,
;  ESC, pausa con ESPACIO, SHIFT + R reinicia, SHIFT + X sale al BASIC). Lo que NO esta todavia (fase 8): actores (sprites), sonido real, guardar y cargar, overlay A.
;  El bloque 0 se queda con la ROM del ZX81.
;
;  Cargar: SCUMM.BIN en $4200 y RAND USR 16917 ($4215: la entrada ENTRY_POINT de vm_core.asm, +21).
;  Ensamblar: build_scumm.sh (pasmo scumm.asm scumm.bin scumm.sym) y los overlays ovlb.asm, ovlc.asm y ovld.asm. Los overlays van a la SD (DATA/OVLB.BIN, OVLC.BIN y OVLD.BIN)
;  y el programa los lee a sus paginas fisicas al arrancar (ov_load_all).
;
;  Memoria: $2000-$37FF ventana de datos (paginas de 6 KB)   $4200-$7FFF codigo   $8000-$869F tablas del nucleo   $8700-$87FF variables del programa
;           $8B00-$93C9 actores, nombres, verbos y cadenas   $9500-$95FF banderas de los sonidos   $A000-$BFFF bitmap HiRes   $C000-$DFFF atributos
;           $E000-$FFFF estado del nucleo
; =====================================================================

ENTRY_POINT     equ scumm_main
SV              equ $8700               ; variables del programa (SV+100.. son de hr.asm)
STACK           equ $8AF0               ; la pila ocupa $8A00-$8AEF
PROF            equ $9400               ; el perfil del juego (256 bytes de DATA.BIN; V2/TOOLS/gameprofile.py y, en v3, PROF+255 = saltar la proteccion)
PF_TPLPOS       equ PROF+8              ; donde van las dos cifras de la sala en el nombre del fichero
PF_TPL          equ PROF+13             ; desplazamiento (desde PROF) del nombre de los ficheros de sala
SNDF            equ $9500               ; 256 bytes: banderas de cada sonido (la tabla de sonidos de DATA.BIN, +1 de cada entrada: bit 3 = cancion)
SET_FAST        equ $02E7
SLOW_FAST       equ $0207
CMD_64C         equ $1C

; ---- entradas fijas de los overlays (la direccion de cada una en su overlay; las ponen ovlb.asm, ovlc.asm y ovld.asm: tienen que coincidir con las de vm.asm)
OVB_EXPR        equ 0                   ; overlay B
OVB_OP          equ 3
OVB_DD          equ 6                   ; displayDialog
OVB_STOPTALK    equ 9
OVB_HIDE        equ 12
OVB_SHOWACT     equ 15
OVB_FOLLOW      equ 18
OVB_PUTACT      equ 21
OVB_VNAME       equ 24                  ; fase 7
OVC_OP          equ 0                   ; overlay C
OVC_SENT        equ 3                   ; checkAndRunSentenceScript
OVC_START       equ 6                   ; startScene (C = sala)
OVC_ROOM        equ 9                   ; load_room_state (C = sala, B = 1: con cajas)
OVC_SENTADD     equ 12                  ; doSentence desde fuera
OVC_MOVECAM     equ 15                  ; moveCamera (fase 5b)
OVD_WALK        equ 0                   ; overlay D
OVD_ADJUST      equ 3
OVD_STARTWALK   equ 6
OVD_CALCMF      equ 9
OVLA_PG         equ SV+176              ; pagina del bloque 0 fuera de los overlays B, C y D: la ROM (0). vm_core.asm la lee como variable (ld a,(OVLA_PG))
OVL_DARK        equ 27                  ; (overlay A, fase 8: la linterna; hv_dark es siempre 0 mientras no exista)
OVL_DKMASK      equ 33

                org $4200
                include "vm_core.asm"
                include "mcu.asm"
                include "loader.asm"
                include "hr.asm"
                include "ui3.asm"       ; fase 7: interfaz, mensajes, cursor, teclado y raton

; ---- variables
sv_sp           equ SV+0
sv_i            equ SV+2
gf_room         equ SV+3
gf_cam          equ SV+4                ; palabra: columna de la camara LOGICA
gf_fine         equ SV+6                ; scroll fino 0-7
gf_cols         equ SV+7                ; palabra
gf_npos         equ SV+9                ; palabra: ultima posicion de la camara (columnas - 32)
gf_have         equ SV+25               ; 1 si hay un .GFX cargado
gf_name         equ SV+48               ; "DATA/ROOMnn.GFX" + 0 (hasta SV+69)
gf_objsec       equ SV+70               ; palabra
gf_size         equ SV+74               ; palabra: tamano del .GFX
ml_acc          equ SV+150              ; vsyncs contados en esta vuelta
in92            equ SV+151              ; fotogramas en la sala 92 (proteccion anticopia)
k_prev          equ SV+152
sm_ov           equ SV+153
snd_mt          equ SV+154              ; palabra: music_timer
snd_tpm         equ SV+156              ; palabra: ticks_per_music_timer (65535 hasta que una cancion fija el tempo)
snd_ctr         equ SV+158              ; palabra: music_ctr
snd_acc         equ SV+160              ; palabra: music_acc
snd_slots       equ SV+162              ; 8 x (id (2), jiffies que le quedan (2)): los sonidos que suenan (modo "timed" del modelo; 0 jiffies = libre)
NSND            equ 8
DBG_START       equ SV+194              ; palabra de depuracion: numero de script a arrancar (la escribe el usuario desde el emulador)
DBG_ROOM        equ SV+196              ; palabra de depuracion: sala a cargar

; ---------------------------------------------------------------------
;  Arranque
; ---------------------------------------------------------------------
scumm_main:     di
                ld (sv_sp),sp
                ld sp,STACK
                ld a,i
                ld (sv_i),a
                call SET_FAST
                xor a
                ld (gf_have),a
                ld (OVLA_PG),a
                ld (in92),a
                ld (k_prev),a
                ld h,a
                ld l,a
                ld (DBG_START),hl
                ld (DBG_ROOM),hl
                ld a,CMD_FULLPAGING
                call mcu_send
                ld b,6                  ; bloques 6 y 7 a sus paginas ($C000 son los atributos de video)
                ld a,6
                call sc_map
                ld b,7
                ld a,7
                call sc_map
                ld a,85
                ld (2058),a             ; WRX apagado
                call hr_init            ; HiRes 8x1: bitmap y atributos a cero
                call ui_init            ; fase 7: pantalla de texto de la interfaz y cursor
                ld bc,$7FEF
                ld a,$20                ; Chroma, modo 0
                out (c),a
                ld a,$FC                ; D3: se desplazan las filas 2-17 (la sala); las 0-1 (mensajes) y 18-23 (interfaz) se quedan quietas
                ld (2091),a
                ld a,$FF
                ld (2092),a
                ld a,$03
                ld (2093),a
                xor a
                ld (2090),a
                call vm_init
                ld hl,ev_handler
                ld (EVVEC),hl
                call snd_init
                call ov_load_all
                jr nc,sm_ov_ok
                ld a,1
                ld (sm_ov),a
                jp sc_quit
sm_ov_ok:       call load_data
                jr nc,sm_ok1
                ld a,2
                ld (sm_ov),a
                jp sc_quit
sm_ok1:         ld hl,1                 ; el script de arranque
                ld (APIN),hl
                call vm_run_script
boot_done:      ld a,(ERR)
                or a
                jp nz,sm_err

main_loop:      xor a                   ; scummLoop dura VAR_TIMER_NEXT jiffies (1/60 s, minimo 1): al menos 5/6 de ese numero de fotogramas
                ld (ml_acc),a
ml_w:           call wait_vs
                ld hl,ml_acc
                add a,(hl)
                ld (hl),a
                ld a,(VAR_TIMER_NEXT)
                cp 40
                jr c,ml_t
                ld a,40
ml_t:           ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de               ; * 5
                ld de,3
                add hl,de
                ld b,0                  ; / 6
ml_d:           ld de,6
                or a
                sbc hl,de
                jr c,ml_dd
                inc b
                jr ml_d
ml_dd:          ld a,b
                or a
                jr nz,ml_n
                inc a
ml_n:           ld b,a                  ; B = fotogramas que debe durar
                ld a,(ml_acc)
                cp b
                jr c,ml_w
                ld (DELTA),a
ml_dset:        call hr_frame           ; el hardware sigue a la camara nada mas empezar el fotograma
                ld hl,(DBG_START)       ; depuracion: un numero de script (DBG_START) o de sala (DBG_ROOM) escrito aqui desde el emulador (o TS_POKE del arnes) se
                ld a,h                  ; arranca / carga en este fotograma (el motor lo pone a 0)
                or l
                jr z,ml_nd
                ld (APIN),hl
                ld hl,0
                ld (DBG_START),hl
                call vm_run_script
ml_nd:          ld hl,(DBG_ROOM)
                ld a,h
                or l
                jr z,ml_nr
                ld (APIN),hl
                ld hl,0
                ld (DBG_ROOM),hl
                call vm_load_room
ml_nr:          call protection_hook
ml_vm:          call in_poll            ; fase 7: el suceso de entrada del fotograma (INEV)
                call vm_frame
frame_done:     ld a,(ERR)
                or a
                jr nz,sm_err
                call cam_update
                call gd_update
                call ui_frame           ; fase 7: verbos, mensajes y cursor
                call hr_end             ; si el motor de scroll tiene una orden, se cierra ahora (hr.asm)
                jp main_loop

sm_err:         ld a,(ERR)
                ld (sm_ov),a
                jr sc_quit

sc_quit:        call dp_close           ; el DATA.BIN se cierra
                ld a,CMD_STOPVGM        ; el sonido que suene se para
                call mcu_send
                call sc_hide_sprites
                ld b,0                  ; el bloque 0 vuelve a la ROM (la usa SLOW_FAST)
                xor a
                call sc_map
                ld a,85
                ld (2045),a
                ld (2098),a
                ld (2090),a
                ld a,255
                ld (2093),a
                ld bc,$7FEF
                ld a,$0C
                out (c),a
                ld a,CMD_64C
                call mcu_send
                ld a,(sv_i)
                ld i,a
                call SLOW_FAST
                ld sp,(sv_sp)
quit_ret:       ld a,(sm_ov)
                ld c,a                  ; PRINT USR: 0 = salida normal, si no el codigo de error de la VM (o 1: faltan los overlays, 2: falta DATA.BIN)
                ld b,0
                ret

sc_hide_sprites:
                ld b,64
sh1:            ld a,b
                dec a
                ld (2100),a
                xor a
                ld (2101),a
                djnz sh1
                ret

; bloque A, pagina B (paginacion completa)
sc_map:         ld c,MAP_PORT
                out (c),a
                ret

; ---------------------------------------------------------------------
;  Proteccion anticopia (D2, PROF+255 = 1: el perfil pide saltarla): en la sala 92, a los 30 fotogramas Var[57] = 1 (lo que hace el script local 204 al acertar)
;  (vmmodel3.protection_hook)
; ---------------------------------------------------------------------
protection_hook:
                ld a,(CURROOM)
                cp 92
                jr z,ph_92
                xor a
                ld (in92),a
                ret
ph_92:          ld hl,in92
                inc (hl)
                ld a,(PROF+255)
                or a
                ret z
                ld a,(in92)
                cp 31
                ret c
                ld hl,1
                ld (VARS+2*57),hl
                ret

; ---------------------------------------------------------------------
;  Salir (SHIFT + X), reiniciar (SHIFT + R) y pausa (ESPACIO): las llama in_poll (ui3.asm)
; ---------------------------------------------------------------------
sc_quit_key:    jp sc_quit

restart:        ld sp,STACK             ; el juego empieza de nuevo (SHIFT + R): como el arranque, sin volver a leer los overlays
                call dp_close
                call hr_init
                call ui_init
                call vm_init
                ld hl,ev_handler
                ld (EVVEC),hl
                call snd_init
                xor a
                ld (gf_have),a
                ld (in92),a
                call load_data
                jp nc,sm_ok1
                ld a,2
                ld (sm_ov),a
                jp sc_quit

; ESPACIO: pausa. PAUSA arriba hasta que se vuelve a pulsar ESPACIO (el mensaje que hubiera se guarda y se restaura)
do_pause:       ld hl,UIVB
                ld de,UIBUF
                ld bc,40
                ldir
                ld hl,pause_txt
                ld de,UIVB
dpa_t:          ld a,(hl)
                or a
                jr z,dpa_e
                inc hl
                push hl
                call ui_code
                ld (de),a
                inc de
                pop hl
                jr dpa_t
dpa_e:          call hr_ui
dpa_r:          call wait_vs            ; espera a que se suelte ESPACIO y se vuelva a pulsar
                call kbd_scan
                ld a,b
                cp ' '
                jr z,dpa_r
dpa_p:          call wait_vs
                call kbd_scan
                ld a,b
                cp ' '
                jr nz,dpa_p
dpa_u:          call wait_vs
                call kbd_scan
                ld a,b
                cp ' '
                jr z,dpa_u
                ld a,' '
                ld (ik_prev),a
                ld hl,UIBUF
                ld de,UIVB
                ld bc,40
                ldir
                call hr_ui
                ld a,1
                ld (ui_dirty),a
                ret
pause_txt:      defb "GAME PAUSED - PRESS SPACE",0

; espera al siguiente VSYNC; A = cuantos han pasado (>= 1)
wait_vs:        ld a,(vs_extra)         ; un redibujado ya ha esperado el VSYNC de este fotograma
                or a
                jr z,wv_n
                push af
                xor a
                ld (vs_extra),a
                pop af
                ret
wv_n:           in a,(ClkPort)
                ld bc,2000
wv1:            in a,(ClkPort)
                and $7E
                jr nz,wv_ok
                dec bc
                ld a,b
                or c
                jr nz,wv1
                ld a,2
wv_ok:          rrca
                ret

; ---------------------------------------------------------------------
;  Overlays B, C y D: ficheros de DATA/ a sus paginas fisicas (por la ventana de datos). Carry si falla
; ---------------------------------------------------------------------
ov_load_all:    ld hl,ovn_b
                ld a,OVB_PAGE
                call ov_load
                ret c
                ld hl,ovn_c
                ld a,OVC_PAGE
                call ov_load
                ret c
                ld hl,ovn_d
                ld a,OVD_PAGE
                call ov_load
                ret c
                ld a,1
                call map_phys           ; la ventana vuelve a su pagina de arranque
                or a
                ret
ovn_b:          defb "DATA/OVLB.BIN",0
ovn_c:          defb "DATA/OVLC.BIN",0
ovn_d:          defb "DATA/OVLD.BIN",0

; HL = nombre, A = pagina fisica
ov_load:        ld (ov_pg),a
                call f_open
                cp $FF
                jr nz,ovl1
                scf
                ret
ovl1:           ld (ld_h),a
                ld hl,ov_stat           ; fstat: 4 bytes de tamano, 4 de fecha y el estado
                ld a,CMD_FSTAT
                call mcu_send
                ld a,(ld_h)
                call mcu_send
                ld b,4
ovl2:           call mcu_recv
                ld (hl),a
                inc hl
                djnz ovl2
                ld b,5
ovl3:           call mcu_recv
                djnz ovl3
                ld a,(ov_pg)
                call map_phys
                ld bc,(ov_stat)
                ld hl,WINDOW
                ld a,(ld_h)
                call f_read_n
                ld a,(ld_h)
                call f_close
                or a
                ret
ov_pg:          defb 0
ov_stat:        defs 4

; ---------------------------------------------------------------------
;  Sucesos del nucleo (EVVEC): A = suceso. Solo sala, objetos y sonido (fase 5b): el texto, los verbos y el resto llegan con las fases 7 y 8
; ---------------------------------------------------------------------
ev_handler:     push af
                push bc
                push de
                push hl
                push ix
                push iy
                cp EV_TEXT
                jr z,evh_text
                cp EV_VERB
                jr z,evh_verb
                cp EV_ROOM_LOAD
                jr z,evh_room
                cp EV_SOUND_START
                jr z,evh_sstart
                cp EV_SOUND_STOP
                jr z,evh_sstop
                cp EV_SOUND_STOPALL
                jr z,evh_sall
                cp EV_SOUND_QUERY
                jr z,evh_sq
                cp EV_OBJSTATE
                jr z,evh_obj
                cp EV_DRAWOBJ
                jr nz,evh_end
evh_obj:        ld a,1                  ; cambia el estado de un objeto: la sala se vuelve a componer (una vez por fotograma, gd_update)
                ld (gd_pending),a
                jr evh_end
evh_text:       call ui_text_ev
                jr evh_end
evh_verb:       ld a,1
                ld (ui_dirty),a
                jr evh_end
evh_room:       call gf_load_room
                jr evh_end
evh_sstart:     call snd_start
                jr evh_end
evh_sstop:      call snd_stop
                jr evh_end
evh_sall:       ld hl,snd_slots
                ld de,snd_slots+1
                ld bc,NSND*4-1
                ld (hl),0
                ldir
                jr evh_end
evh_sq:         call snd_query
evh_end:        pop iy
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ret

; ---------------------------------------------------------------------
;  Sonido simulado (modo "timed" de vmgame3.py): cada sonido dura 60 jiffies, 3600 si es una cancion (SNDF bit 3), y VAR_MUSIC_TIMER avanza como Player_V2Base.
;  La fase 8 lo sustituye por el reproductor real (snd.asm). Maximo NSND sonidos a la vez (si no hay hueco, el nuevo no suena).
; ---------------------------------------------------------------------
snd_init:       ld hl,snd_slots
                ld de,snd_slots+1
                ld bc,NSND*4-1
                ld (hl),0
                ldir
                ld hl,0
                ld (snd_mt),hl
                ld (snd_ctr),hl
                ld (snd_acc),hl
                dec hl
                ld (snd_tpm),hl         ; 65535
                ret

; IX = ranura del sonido EVARGS+0 (si suena: Z), o NZ si no suena
snd_find:       ld bc,(EVARGS)
                ld ix,snd_slots
                ld d,NSND
sf_l:           ld a,(ix+0)
                cp c
                jr nz,sf_n
                ld a,(ix+1)
                cp b
                jr nz,sf_n
                ld a,(ix+2)
                or (ix+3)
                jr z,sf_n               ; 0 jiffies: libre
                xor a                   ; Z
                ret
sf_n:           inc ix
                inc ix
                inc ix
                inc ix
                dec d
                jr nz,sf_l
                or 1                    ; NZ
                ret

snd_start:      call snd_find
                jr z,ss_have
                ld ix,snd_slots         ; un hueco: jiffies = 0
                ld d,NSND
ss_f:           ld a,(ix+2)
                or (ix+3)
                jr z,ss_have
                inc ix
                inc ix
                inc ix
                inc ix
                dec d
                jr nz,ss_f
                ret                     ; sin hueco
ss_have:        ld bc,(EVARGS)
                ld (ix+0),c
                ld (ix+1),b
                ld de,60                ; efecto
                ld a,b
                or a
                jr nz,ss_fx             ; (id > 255: no esta en la tabla)
                ld hl,SNDF
                ld e,c
                ld d,0
                add hl,de
                ld a,(hl)
                ld de,60
                bit 3,a
                jr z,ss_fx
                ld de,3600              ; cancion: music_timer a 0 y tempo de 125 ticks por unidad
                ld hl,0
                ld (snd_mt),hl
                ld hl,125
                ld (snd_tpm),hl
ss_fx:          ld (ix+2),e
                ld (ix+3),d
                ret

snd_stop:       call snd_find
                ret nz
                xor a
                ld (ix+2),a
                ld (ix+3),a
                ret

snd_query:      call snd_find           ; HRES = 1 si suena
                ld hl,0
                jr nz,sq_set
                inc hl
sq_set:         ld (HRES),hl
                ret

; Sound::updateMusicTimer: una vez por fotograma (desde vm_frame, antes de runAllScripts), con el delta sin recortar (DELTA)
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
                ld de,60
                or a
                sbc hl,de
                jr c,st_t
                ld (snd_acc),hl         ; while music_acc >= 60: -= 60
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
st_t:           ld hl,(snd_mt)
                ld (VAR_MUSIC_TIMER),hl
                ld a,(DELTA)            ; a los sonidos que suenan se les quitan los jiffies
                ld e,a
                ld d,0
                ld ix,snd_slots
                ld b,NSND
st_s:           ld l,(ix+2)
                ld h,(ix+3)
                ld a,h
                or l
                jr z,st_nx              ; libre
                or a
                sbc hl,de
                jr z,st_gone
                jr nc,st_keep
st_gone:        ld hl,0
st_keep:        ld (ix+2),l
                ld (ix+3),h
st_nx:          inc ix
                inc ix
                inc ix
                inc ix
                djnz st_s
                ret

; ---------------------------------------------------------------------
;  Camara: la posicion logica (gf_cam, gf_fine) sale de CAMCUR (x del centro de la pantalla; v3: la izquierda es cur - 160), acotada a la sala. El hardware la sigue
;  (hr.asm: hr_frame y hr_end). moveCamera y los modos de la camara (seguir a un actor, panoramica) son de las fases 7 y 8: aqui solo la posicion que dejan los scripts.
; ---------------------------------------------------------------------
cam_update:     ld a,(gf_have)
                or a
                ret z
                ld hl,(CAMCUR)
                ld de,-160
                add hl,de
                bit 7,h
                jr z,cu_pos
                ld hl,0
cu_pos:         ex de,hl                ; DE = izquierda en pixeles
                ld hl,(gf_npos)         ; maximo = (columnas - 32) * 8
                bit 7,h
                jr z,cu_mx
                ld hl,0
cu_mx:          add hl,hl
                add hl,hl
                add hl,hl
                push hl
                or a
                sbc hl,de               ; maximo - izquierda
                pop hl
                jr nc,cu_ok
                ex de,hl                ; DE = maximo
cu_ok:          ld a,e
                and 7
                ld (gf_fine),a
                srl d
                rr e
                srl d
                rr e
                srl d
                rr e
                ld (gf_cam),de
                ret

; ---------------------------------------------------------------------
;  Objetos que se dibujan: drawRoomObject de ScummVM (object.cpp): se dibuja si su estado no es 0 y, mientras tiene padre, el estado del padre (& $F) es el que pide.
;  A = indice (desde 0) en la sala -> carry si se dibuja. Registros de 14 bytes en RBLOB (OBJP): id, ..., OB_PAR, OB_PST
; ---------------------------------------------------------------------
od_rec:         dec a                   ; A = indice desde 1 -> HL = registro
                ld l,a
                ld h,0
                add hl,hl
                ld d,h
                ld e,l                  ; 2x
                add hl,hl               ; 4x
                add hl,de               ; 6x
                add hl,hl               ; 12x
                add hl,de               ; 14x
                ld de,(OBJP)
                add hl,de
                ret

obj_drawn:      inc a
                ld (od_b),a             ; b = el objeto (desde 1)
                call od_rec
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,OBJST
                add hl,de
                ld a,(hl)
                and $0F
                ret z                   ; sin estado: no se dibuja (NC)
od_loop:        ld a,(od_b)
                ld hl,NROBJ
                cp (hl)
                jr c,od_re
                jr z,od_re
                scf                     ; un registro que no existe (estado 0, padre 0): sin padre, se dibuja
                ret
od_re:          call od_rec
                push hl
                ld de,OB_PST
                add hl,de
                ld a,(hl)
                ld (od_st),a            ; el estado que pide del padre
                pop hl
                ld de,OB_PAR
                add hl,de
                ld a,(hl)
                or a
                jr nz,od_par
                scf                     ; sin padre: se dibuja
                ret
od_par:         ld (od_b),a
                ld hl,NROBJ
                cp (hl)
                jr c,od_ex
                jr z,od_ex
                xor a                   ; el padre no existe: estado 0
                jr od_cmp
od_ex:          call od_rec
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,OBJST
                add hl,de
                ld a,(hl)
                and $0F
od_cmp:         ld hl,od_st
                cp (hl)
                jr z,od_loop            ; el padre esta como pide: se mira su propio padre
                or a                    ; no: NC, no se dibuja
                ret
od_b:           defb 0
od_st:          defb 0

; ---------------------------------------------------------------------------------------------------------------
;  Final del programa. El codigo tiene que acabar por debajo de $8000: por encima la ULA del ZX81 mete NOPs en la captura de instrucciones.
;  Las tablas del nucleo son solo datos y van aqui.
; ---------------------------------------------------------------------------------------------------------------
code_end:
                IF $ > $8000
                defb CODIGO_POR_ENCIMA_DE_8000
                ENDIF
                org $8000
                include "tables3.inc"
tables_end:
