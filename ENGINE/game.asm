; game.asm - capa de juego del interprete SCUMM v2 (se incluye desde vm.asm)
;
; Sonido, mensajes (print / printEgo), actores y cambio de sala (loadRoom). Es la version en Z80 de
; SCUMM/TOOLS/vmgame.py, que es a su vez una transcripcion de ScummVM; ver ahi que esta y que no.
; El dibujo, el sonido y la lectura de salas salen al back-end como sucesos por el puerto $F2.

EVPORT          equ $F2
NACTORS         equ 25
WALK_FRAME      equ 0           ; fotogramas fijos de Actor_v2
STAND           equ 1
INIT_FRAME      equ 2
TALK_STOP       equ 4
TALK_START      equ 5
MSGBUF_SIZE     equ 320
EV_SOUND_START  equ 1
EV_SOUND_STOP   equ 2
EV_SOUND_STOPALL equ 3
EV_SOUND_QUERY  equ 4
EV_TEXT         equ 5
EV_ROOM_LOAD    equ 6
EV_OBJSTATE     equ 8
E_BADROOM       equ 6
ASIZE           equ 48          ; tamano del registro de actor
ODIRBUF         equ $D000       ; 780 x 3: pagina y direccion del bloque de codigo de cada objeto (lo carga loader.asm)

; ---- datos de la capa de juego (bloque 7)
CURROOM         equ $EB40       ; sala actual (_currentRoom)
HAVEMSG         equ $EB41       ; _haveMsg: 0 nada, 1 acabado de escribir, $FF escribiendo
KEEPTXT         equ $EB42
USETALK         equ $EB43
TALKDLY         equ $EB44       ; palabra
MSGCNT          equ $EB46       ; palabra
MSGPTR          equ $EB48       ; palabra: siguiente caracter del bufer de texto
LASTSND         equ $EB4A       ; palabra
STRP            equ $EB4C       ; palabra: inicio de la ultima cadena decodificada
EVID            equ $EB4E
EVARGS          equ $EB50       ; 3 palabras
TXTSUM          equ $EB56
TXTLEN          equ $EB58
TXTN            equ $EB5A
DECST           equ $EB5C
PA_X            equ $EB5D       ; palabra
PA_Y            equ $EB5F       ; palabra
PA_ROOM         equ $EB61
SS_ROOM         equ $EB62
CUREXC_P        equ $EB63       ; codigo de salida de la sala actual: pagina (0 = no hay) y direccion
CUREXC_A        equ $EB64
CURENC_P        equ $EB66
CURENC_A        equ $EB67
HOSTVEC         equ $EB6F       ; palabra: rutina de las instrucciones que van al anfitrion (vm_init: host_null)
EVVEC           equ $EB6B       ; palabra: rutina que atiende los sucesos del back-end (vm_init la pone a ev_null)
TXTSTART        equ $EB6D       ; palabra: donde empieza, en el bufer de texto, lo que escribe display_dialog esta vez
ACTORS          equ $EF00       ; NACTORS x ASIZE
ROOMDIR         equ $F400       ; 64 x 16: pagina de entrada, direccion, pagina de salida, direccion, ancho,
                                ;          pagina, direccion y tamano de los datos de cajas y objetos
MSGBUF          equ $F800       ; MSGBUF_SIZE bytes
; actor: +0 sala, +1/+2 x, +3/+4 y, +5 traje, +6/+7 direccion, +8 moviendose, +9 visible, +10 fotograma,
;        +11 color de habla, +12/+13 direccion de destino, +14 sonido 0, +15 numero

; ============================================================================================ sucesos
ev_emit:                                ; A = suceso; los operandos ya estan en EVARGS
                ld (EVID),a
                ld hl,(EVVEC)           ; la rutina que lo atiende: la del programa de la placa o un resquicio del arnes de PC
                jp (hl)                 ; (NO se escribe en ningun puerto: en el ZX81 un OUT a un puerto par enciende el NMI)
ev_null:        ret

; ============================================================================================ sonido
h_o5_startSound:
                ld hl,0
                ld (VARS+34),hl         ; VAR_MUSIC_TIMER = 0
h_o5_startMusic:
                ld hl,(ARGS)
                ld (VARS+74),hl         ; VAR_LAST_SOUND
                ld (LASTSND),hl
                ld (EVARGS),hl
                ld a,EV_SOUND_START
                jp ev_emit
h_o5_stopSound:
                ld hl,(ARGS)
                ld (EVARGS),hl
                ld a,EV_SOUND_STOP
                jp ev_emit
h_o5_stopMusic:
                ld hl,0
                ld (LASTSND),hl
                ld a,EV_SOUND_STOPALL
                jp ev_emit
h_o5_isSoundRunning:                    ; ARGS: resultado, sonido
                ld hl,(ARGS+2)
                ld bc,0
                ld a,h
                or l
                jr z,isr_w
                ld (EVARGS),hl
                ld a,EV_SOUND_QUERY
                call ev_emit
                ld bc,(HRES)
isr_w:
                ld a,(ARGS)
                jp write_var

; ============================================================================================ actores
actor_addr:                             ; A = actor -> IX (conserva DE)
                push de
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl               ; * 16
                ld d,h
                ld e,l
                add hl,hl
                add hl,de               ; * 48
                ld de,ACTORS
                add hl,de
                push hl
                pop ix
                pop de
                ret

deref_actor:                            ; derefActor: DE = numero -> IX; error: ERR y carry
                ld a,d
                or a
                jr nz,da_bad
                ld a,e
                cp NACTORS
                jr nc,da_bad
                call actor_addr
                or a
                ret
da_bad:
                ld a,E_RANGE
                ld (ERR),a
                scf
                ret

start_anim:                             ; startAnimActor: IX = actor, A = fotograma
                cp 56
                jr c,sa_chk
                cp 61
                jr nc,sa_chk
                sub 56
                ld e,a
                ld d,0
                ld hl,sa_table          ; 56..60: inicio, caminar, parado, hablar, dejar de hablar
                add hl,de
                ld a,(hl)
sa_chk:
                ld c,a
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld a,(ix+5)
                or a
                ret z
                ld (ix+10),c
                ret

sa_table:       defb INIT_FRAME,WALK_FRAME,STAND,TALK_START,TALK_STOP

hide_actor:                             ; IX = actor
                ld a,(ix+9)
                or a
                ret z
                ld a,(ix+8)
                or a
                jr z,ha_1
                ld (ix+8),0
                ld a,STAND
                call start_anim
ha_1:
                ld (ix+9),0
                ret

show_actor:                             ; IX = actor
                ld a,(CURROOM)
                or a
                ret z
                ld a,(ix+9)
                or a
                ret nz
                call adjust_actor_pos
                ld a,(ERR)
                or a
                ret nz
                ld a,STAND
                call start_anim
                ld a,INIT_FRAME
                call start_anim
                ld a,TALK_STOP
                call start_anim
                ld (ix+8),0
                ld (ix+9),1
                ret

run_talk_script:                        ; runActorTalkScript: IX = actor, A = fotograma
                ld c,a
                ld hl,(VARS+82)         ; VAR_TALK_ACTOR
                ld a,h
                or l
                ret z
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                ld a,(ix+10)
                cp c
                ret z
                ld a,c
                jp start_anim

put_actor:                              ; IX = actor; PA_X, PA_Y, PA_ROOM
                ld a,(ix+9)
                or a
                jr z,pa_set
                ld a,(CURROOM)
                ld b,a
                ld a,(PA_ROOM)
                cp b
                jr z,pa_set
                ld c,(ix+15)            ; esta visible y cambia de sala: si habla, calla
                ld b,0
                ld hl,(VARS+82)
                or a
                sbc hl,bc
                jr nz,pa_set
                push ix
                call stop_talk
                pop ix
pa_set:
                ld hl,(PA_X)
                ld (ix+1),l
                ld (ix+2),h
                ld hl,(PA_Y)
                ld (ix+3),l
                ld (ix+4),h
                ld a,(PA_ROOM)
                ld (ix+0),a
                ld a,(ix+9)
                or a
                jr z,pa_hidden
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,pa_hide
                ld a,(ix+8)
                or a
                jr z,pa_adj
                ld (ix+8),0
                ld a,STAND
                call start_anim
pa_adj:
                jp adjust_actor_pos
pa_hide:
                jp hide_actor
pa_hidden:
                ld a,(CURROOM)
                cp (ix+0)
                ret nz
                jp show_actor

set_costume:                            ; IX = actor, A = traje
                ld c,a
                ld a,(ix+9)
                or a
                jr z,sc_plain
                push bc
                call hide_actor
                pop bc
                ld (ix+5),c
                jp show_actor
sc_plain:
                ld (ix+5),c
                ret

h_o2_putActor:                          ; ARGS: actor, x, y
                ld de,(ARGS)
                call deref_actor
                ret c
                ld hl,(ARGS+2)
                ld (PA_X),hl
                ld hl,(ARGS+4)
                ld (PA_Y),hl
                ld a,(ix+0)
                ld (PA_ROOM),a
                jp put_actor

h_o2_putActorInRoom:                    ; ARGS: actor, sala
                ld de,(ARGS)
                call deref_actor
                ret c
                ld a,(ARGS+2)
                ld (ix+0),a
                ld hl,(ARGS+2)
                ld a,h
                or l
                ret nz
                ld (PA_X),hl
                ld (PA_Y),hl
                ld (PA_ROOM),a
                jp put_actor

h_o5_getActorRoom:                      ; ARGS: resultado, actor
                ld de,(ARGS+2)
                ld bc,0
                ld a,d
                or a
                jr nz,gar_w
                ld a,e
                cp NACTORS
                jr nc,gar_w
                call actor_addr
                ld c,(ix+0)
gar_w:
                ld a,(ARGS)
                jp write_var

h_o5_animateActor:                      ; ARGS: actor, animacion
                ld de,(ARGS)
                ld a,d
                or a
                ret nz                  ; actor no valido: no hace nada
                ld a,e
                cp NACTORS
                ret nc
                call actor_addr
                ld a,(ARGS+2)           ; animacion (byte)
                ld b,a
                srl a
                srl a
                ld c,a                  ; C = animacion >> 2
                cp 63                   ; parar
                jr z,an_stop
                cp 62                   ; cambiar de direccion ya
                jr z,an_dir
                cp 61                   ; girar hacia la direccion
                jr z,an_turn
                ld a,c
                jp start_anim
an_stop:
                ld a,STAND
                call start_anim
                ld (ix+8),0
                ret
an_dir:
                ld a,(ix+8)
                and $FB
                ld (ix+8),a
                call old_dir
                ld (ix+6),l
                ld (ix+7),h
                ret
an_turn:
                call old_dir
                ld (ix+12),l
                ld (ix+13),h
                ld a,(ix+8)
                or 4
                ld (ix+8),a
                ret
old_dir:                                ; B = animacion -> HL = direccion nueva (oldDirToNewDir)
                ld a,b
                and 3
                ld l,a
                ld h,0
                add hl,hl
                ld de,old_dir_table
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ret
old_dir_table:  defw 270,90,180,0

h_o2_actorOps:                          ; ARGS: actor, argumento, subopcode [, dato]
                ld de,(ARGS)
                ld a,(ARGS+4)
                ld b,a                  ; subopcode
                ld a,d
                or e
                jr nz,ao_1
                ld a,b
                cp 5
                ret z                   ; actor 0 y color: es el color del texto, sin actor
ao_1:
                push bc
                call deref_actor
                pop bc
                ret c
                ld a,b
                cp 1
                jr z,ao_sound
                cp 4
                jr z,ao_cost
                cp 5
                jr z,ao_color
                cp 2
                ret z                   ; paleta: sin soporte todavia
                cp 3
                ret z                   ; nombre: solo se usa en los codigos de texto 6
                ld a,E_RANGE
                ld (ERR),a
                ret
ao_sound:
                ld a,(ARGS+2)
                ld (ix+14),a
                ret
ao_cost:
                ld a,(ARGS+2)
                jp set_costume
ao_color:
                ld a,(ARGS+2)
                ld (ix+11),a
                ret

; ============================================================================================ mensajes
stop_talk:                              ; stopTalk
                xor a
                ld (HAVEMSG),a
                ld h,a
                ld l,a
                ld (TALKDLY),hl
                ld hl,(VARS+82)
                ld a,h
                or l
                jr z,stk_end
                ld a,h
                or a
                jr nz,stk_end
                ld a,l
                cp $80
                jr nc,stk_end
                cp NACTORS
                jr nc,stk_bad
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,stk_set
                ld a,(USETALK)
                or a
                jr z,stk_set
                ld a,TALK_STOP
                call run_talk_script
                xor a
                ld (USETALK),a
stk_set:
                ld hl,$00FF
                ld (VARS+82),hl
stk_end:
                xor a
                ld (KEEPTXT),a
                ret
stk_bad:
                ld a,E_RANGE
                ld (ERR),a
                ret

emit_a:                                 ; escribe A en el bufer de texto (DE); error si se llena
                ld (de),a
                inc de
                push hl
                ld hl,MSGBUF+MSGBUF_SIZE-1
                or a
                sbc hl,de
                pop hl
                jr c,ea_err
                ret nz
ea_err:
                ld a,E_RANGE
                ld (ERR),a
                ret

dig:                                    ; HL = valor, BC = divisor: emite un digito (sin ceros a la izquierda)
                xor a
dig_1:
                or a
                sbc hl,bc
                jr c,dig_2
                inc a
                jr dig_1
dig_2:
                add hl,bc
                ld c,a
                ld a,(DECST)
                or c
                ret z
                ld a,1
                ld (DECST),a
                ld a,c
                add a,'0'
                jp emit_a
emit_dec:                               ; HL = valor con signo en 16 bits
                bit 7,h
                jr z,ed_pos
                ld a,'-'
                call emit_a
                ld a,l
                cpl
                ld l,a
                ld a,h
                cpl
                ld h,a
                inc hl
ed_pos:
                xor a
                ld (DECST),a
                ld bc,10000
                call dig
                ld bc,1000
                call dig
                ld bc,100
                call dig
                ld bc,10
                call dig
                ld a,l
                add a,'0'
                jp emit_a

; decodeParseString + convertMessageToString: HL = cadena del script, DE = bufer -> bufer con 0 final
CMVAR           equ $EB68
convert_msg:
cm_loop:
                ld a,(hl)
                inc hl
                or a
                jr z,cm_end
                ld b,a                  ; byte en bruto: el bit 7 pide un espacio despues
                and $7F
                cp 8
                jr nc,cm_plain
                or a
                jr z,cm_space           ; codigo 0: se descarta
                cp 4
                jr nc,cm_expand
                ld c,a                  ; 1, 2, 3: se quedan como FF c
                ld a,$FF
                call emit_a
                ld a,c
                call emit_a
                jr cm_space
cm_expand:
                ld c,a                  ; 4..7: el byte siguiente es la variable
                ld a,(hl)
                inc hl
                ld (CMVAR),a
                ld a,c
                cp 4
                jr z,cm_int
                cp 7
                jr z,cm_str
                jr cm_space             ; 5 y 6: sin soporte todavia
cm_int:
                push bc
                push hl
                ld a,(CMVAR)
                call read_var
                ld h,b
                ld l,c
                call emit_dec
                pop hl
                pop bc
                jr cm_space
cm_str:
                push bc
                push hl
                ld a,(CMVAR)
                ld l,a
                ld h,0
                add hl,hl
                push de
                ld de,VARS
                add hl,de
                pop de
cs_loop:
                ld a,h
                cp $E2
                jr nc,cs_done           ; no se sale de las 256 variables
                ld a,(hl)
                or a
                jr z,cs_done
                cp $40
                jr z,cs_skip
                call emit_a
cs_skip:
                inc hl
                inc hl
                jr cs_loop
cs_done:
                pop hl
                pop bc
                jr cm_space
cm_plain:
                cp $40
                jr z,cm_space           ; la arroba se descarta
                call emit_a
cm_space:
                ld a,(ERR)
                or a
                ret nz
                bit 7,b
                jr z,cm_loop
                ld a,$20
                call emit_a
                jr cm_loop
cm_end:
                xor a
                ld (de),a
                ret

; ---- escribir el mensaje (CHARSET_1 de ScummVM, sin dibujar)
talker_ix:                              ; getTalkingActor + derefActorSafe: IX = actor, o carry si no hay
                ld hl,(VARS+82)
                ld a,h
                or a
                jr nz,tk_none
                ld a,l
                cp $FF
                jr z,tk_none
                cp NACTORS
                jr nc,tk_none
                call actor_addr
                or a
                ret
tk_none:
                scf
                ret

display_dialog:
                ld a,(HAVEMSG)
                or a
                ret z
                ld hl,(TALKDLY)
                ld a,h
                or l
                ret nz
                ld a,(HAVEMSG)
                cp 1
                jp z,stop_talk
                call talker_ix
                jr c,dd_noact
                ld a,TALK_START
                call run_talk_script
                ld a,1
                ld (USETALK),a
dd_noact:
                ld hl,60
                ld (TALKDLY),hl
                ld a,(KEEPTXT)
                or a
                jr nz,dd_keep
                ld hl,0
                ld (MSGCNT),hl
                jr dd_type
dd_keep:
                ld hl,(MSGCNT)          ; _talkDelay += _msgCount * velocidad (6)
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl
                ld de,(TALKDLY)
                add hl,de
                ld (TALKDLY),hl
dd_type:
                ld hl,(MSGPTR)
                ld (TXTSTART),hl
                ld hl,0
                ld (TXTSUM),hl
                ld (TXTLEN),hl
                ld (TXTN),hl
dt_loop:
                ld hl,(MSGPTR)
                ld a,(hl)
                inc hl
                ld (MSGPTR),hl
                cp $FF
                jr z,dt_esc
                cp $FE
                jr z,dt_esc
                or a
                jr z,dt_end
                call dt_char            ; un caracter: msgCount, retardo, VAR_CHARCOUNT y resumen
                ld hl,(TXTN)
                inc hl
                ld (TXTN),hl
                jr dt_loop
dt_esc:
                ld hl,(MSGPTR)
                ld a,(hl)
                inc hl
                ld (MSGPTR),hl
                cp 1
                jr z,dt_nl
                cp 2
                jr z,dt_keep
                cp 3
                jr z,dt_wait
                jr dt_loop              ; 8 y los demas se saltan
dt_nl:
                ld hl,320               ; _msgCount = _screenWidth
                ld (MSGCNT),hl
                ld a,13
                call dt_sum
                jr dt_loop
dt_keep:
                xor a
                ld (HAVEMSG),a
                inc a
                ld (KEEPTXT),a
                jr dt_done
dt_wait:
                ld a,$FF
                ld (HAVEMSG),a
                xor a
                ld (KEEPTXT),a
                ld h,a
                ld l,a
                ld (MSGCNT),hl
                jr dt_done
dt_end:
                ld a,1
                ld (HAVEMSG),a
                xor a
                ld (KEEPTXT),a
                ld h,a
                ld l,a
                ld (MSGCNT),hl
dt_done:
                ld hl,(VARS+82)
                ld (EVARGS),hl
                ld hl,(TXTN)
                ld (EVARGS+2),hl
                ld hl,(TXTSUM)          ; valor = suma + longitud * 257
                ld de,(TXTLEN)
                add hl,de
                ld a,h
                add a,e
                ld h,a
                ld (EVARGS+4),hl
                ld a,EV_TEXT
                jp ev_emit

dt_char:                                ; A = caracter
                ld hl,(MSGCNT)
                inc hl
                ld (MSGCNT),hl
                push af
                ld hl,(TALKDLY)
                ld de,6
                add hl,de
                ld (TALKDLY),hl
                ld hl,(VARS+14)         ; VAR_CHARCOUNT++
                inc hl
                ld (VARS+14),hl
                pop af
dt_sum:                                 ; suma el caracter al resumen
                ld hl,(TXTSUM)
                ld e,a
                ld d,0
                add hl,de
                ld (TXTSUM),hl
                ld hl,(TXTLEN)
                inc hl
                ld (TXTLEN),hl
                ret

; actorTalk: HL = actor para el que se escribe (palabra); la cadena esta en STRP
actor_talk:
                push hl
                ld hl,(STRP)
                ld de,MSGBUF            ; el bufer se pisa aunque el mensaje se descarte
                call convert_msg
                pop hl
                ld a,(ERR)
                or a
                ret nz
                ld a,h
                or a
                jr nz,at_actor
                ld a,l
                cp $FF
                jr nz,at_actor
                ld a,(KEEPTXT)          ; sin actor: mensaje del sistema
                or a
                call z,stop_talk
                ld hl,$00FF
                ld (VARS+82),hl
                jr at_go
at_actor:
                ex de,hl
                call deref_actor
                ret c
                ld a,(CURROOM)
                cp (ix+0)
                ret nz                  ; el actor no esta en la sala: el mensaje se pierde
                ld a,(KEEPTXT)
                or a
                jr nz,at_1
                push ix
                call stop_talk
                pop ix
                ld a,(ERR)
                or a
                ret nz
at_1:
                ld l,(ix+15)
                ld h,0
                ld (VARS+82),hl
                ld a,TALK_START
                call run_talk_script
                ld a,1
                ld (USETALK),a
at_go:
                ld hl,MSGBUF
                ld (MSGPTR),hl
                ld hl,0
                ld (TALKDLY),hl
                ld a,$FF
                ld (HAVEMSG),a
                ld h,0
                ld l,a
                ld (VARS+6),hl          ; VAR_HAVE_MSG
                ld hl,0
                ld (VARS+14),hl         ; VAR_CHARCOUNT
                jp display_dialog

h_o5_print:                             ; ARGS: actor, valor de la cadena; STRP = su inicio
                ld hl,(ARGS)
                jp actor_talk
h_o5_printEgo:
                ld hl,(VARS)            ; VAR_EGO (un byte)
                ld h,0
                jp actor_talk

; ============================================================================================ cambio de sala
kill_scripts:                           ; killScriptsAndResources: mueren las ranuras de sala y locales
                ld ix,SLOTS
                ld b,NSLOT
ks_loop:
                ld a,(ix+1)
                cp WIO_ROOM
                jr z,ks_kill
                cp 4
                jr z,ks_kill
                cp WIO_LOCAL
                jr nz,ks_next
ks_kill:
                ld (ix+0),SS_DEAD
ks_next:
                ld de,16
                add ix,de
                djnz ks_loop
                ret

reset_sentence:
                ld hl,(VARS+76)         ; VAR_BACKUP_VERB
                ld (VARS+52),hl         ; VAR_SENTENCE_VERB
                ld hl,0
                ld (VARS+54),hl
                ld (VARS+56),hl
                ld (VARS+58),hl
                ret

run_scene_script:                       ; A = pagina, HL = direccion, DE = numero (0 = no hay)
                or a
                ret z
                ld (APIP),a
                ld (APIA),hl
                ld (APIN),de
                ld a,WIO_ROOM
                ld (APIW),a
                jp start_new_slot

; HL = sala (palabra): startScene
start_scene:
                ld a,h
                or a
                jr nz,ss_bad
                ld a,l
                or a
                jr z,ss_ok
                cp 64
                jr nc,ss_bad
                push hl
                call room_entry         ; HL = ROOMDIR + sala * 16
                ld de,6
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                pop hl
                jr nz,ss_ok             ; el ancho no es 0: la sala existe
ss_bad:
                ld a,E_BADROOM
                ld (ERR),a
                ret
ss_ok:
                ld a,l
                ld (SS_ROOM),a
                call stop_talk
                ld a,(ERR)
                or a
                ret nz
                ld a,(CUR)
                cp $FF
                jr z,ss_noc
                call slot_addr          ; si el script en curso es de sala o local, se abandona
                inc hl
                ld a,(hl)
                cp WIO_ROOM
                jr z,ss_clr
                cp 4
                jr z,ss_clr
                cp WIO_LOCAL
                jr nz,ss_noc
ss_clr:
                ld a,$FF
                ld (CUR),a
ss_noc:
                ld a,(CUREXC_P)         ; codigo de salida de la sala que se deja
                ld hl,(CUREXC_A)
                ld de,SCRIPT_NUM_EXCD
                call run_scene_script
                ld a,(ERR)
                or a
                ret nz
                call kill_scripts
                call reset_sentence
                ld ix,ACTORS+ASIZE
                ld b,NACTORS-1
ss_hide:
                push bc
                call hide_actor
                pop bc
                ld de,ASIZE
                add ix,de
                djnz ss_hide
                ld a,(SS_ROOM)
                ld l,a
                ld h,0
                ld (VARS+8),hl          ; VAR_ROOM
                ld (VARS+72),hl         ; VAR_ROOM_RESOURCE
                ld (CURROOM),a
                or a
                jr nz,ss_load
                ld (CUREXC_P),a         ; sala 0: no hay scripts
                ld (CURENC_P),a
                ret
ss_load:
                ld a,(SS_ROOM)
                ld l,a
                ld h,0
                call room_entry         ; HL = entrada de la sala
                push hl
                pop iy
                ld a,(iy+0)
                ld (CURENC_P),a
                ld l,(iy+1)
                ld h,(iy+2)
                ld (CURENC_A),hl
                ld a,(iy+3)
                ld (CUREXC_P),a
                ld l,(iy+4)
                ld h,(iy+5)
                ld (CUREXC_A),hl
                call load_blob          ; cajas de caminar, matriz de rutas y objetos de la sala
                ld a,(SS_ROOM)
                ld l,a
                ld h,0
                ld (EVARGS),hl
                ld a,EV_ROOM_LOAD       ; cuando ya estan las cajas y los objetos de la sala
                call ev_emit
                ld l,(iy+6)             ; ancho de la sala
                ld h,(iy+7)
                ld de,160
                ld (VARS+46),de         ; VAR_CAMERA_MIN_X
                or a
                sbc hl,de
                ld (VARS+48),hl         ; VAR_CAMERA_MAX_X
                ld ix,ACTORS+ASIZE      ; showActors
                ld b,NACTORS-1
ss_show:
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,ss_snext
                push bc
                call show_actor
                pop bc
ss_snext:
                ld de,ASIZE
                add ix,de
                djnz ss_show
                ld a,(CURENC_P)         ; codigo de entrada de la sala nueva
                ld hl,(CURENC_A)
                ld de,SCRIPT_NUM_ENCD
                call run_scene_script
                ld a,(ERR)
                or a
                ret nz
                ld de,5
                jp run_script           ; v1 y v2 arrancan siempre el script 5

; copia los datos de cajas y objetos de la sala (IY = su entrada en ROOMDIR) y deja los punteros
load_blob:
                ld a,(iy+8)
                or a
                jr z,lb_none
                ld l,(iy+9)
                ld h,(iy+10)
                ld c,(iy+11)
                ld b,(iy+12)
                push bc
                push hl
                ld a,(iy+8)
                call map_page
                pop hl
                pop bc
                ld de,ROOMBLOB
                ldir
                ld a,(CUR)              ; el script en curso recupera su pagina
                cp $FF
                jr z,lb_ptrs
                call slot_addr
                ld de,4
                add hl,de
                ld a,(hl)
                call map_page
lb_ptrs:
                ld a,(ROOMBLOB)
                ld (NBOXES),a
                ld c,a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,ROOMBLOB+1
                add hl,de               ; matriz
                ld (MATRIXP),hl
                ld a,c
                or a
                jr z,lb_nm
                ld b,c
                ld e,c
                inc e
                ld d,0                  ; DE = n + 1
lb_mul:
                add hl,de
                djnz lb_mul
lb_nm:
                ld a,(hl)               ; numero de objetos
                ld (NOBJS),a
                inc hl
                ld (OBJSP),hl
                ret
lb_none:
                xor a
                ld (NBOXES),a
                ld (NOBJS),a
                ret

room_entry:                             ; HL = sala -> HL = ROOMDIR + sala * 16
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,ROOMDIR
                add hl,de
                ret

load_room_hl:                           ; loadRoom: HL = sala; no hace nada si ya esta en ella
                ld a,(CURROOM)
                cp l
                jp nz,start_scene
                ld a,h
                or a
                ret z
                jp start_scene
h_o5_actorFollowCamera:                 ; si el actor esta en otra sala, empieza esa escena; despues el anfitrion lleva la camara
                ld hl,(ARGS)
                ld a,l
                cp NACTORS
                jr nc,afc_host
                call actor_addr
                ld b,(ix+0)
                ld a,b
                or a
                jr z,afc_host
                ld a,(CURROOM)
                cp b
                jr z,afc_host
                ld a,(OPC)
                push af
                ld a,(ARGN)
                push af
                ld hl,(ARGS)
                push hl
                ld l,b
                ld h,0
                call start_scene
                pop hl
                ld (ARGS),hl
                pop af
                ld (ARGN),a
                pop af
                ld (OPC),a
                ld a,(ERR)
                or a
                ret nz
afc_host:       jp h_host
h_o5_loadRoom:
                ld hl,(ARGS)
                jr load_room_hl
vm_load_room:
                ld hl,(APIN)
                jr load_room_hl

                include "geom.asm"
                include "walk.asm"
                include "input.asm"
