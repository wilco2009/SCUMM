; input.asm - entrada del jugador y frases (se incluye desde game.asm, despues de walk.asm)
;
; Version en Z80 de SCUMM/TOOLS/vmgame.py (find_object, actor_from_pos, g_doSentence, check_sentence, process_input,
; run_object_script): lo que hace ScummVM en v2 con un clic, una tecla y la cola de frases.
;
;   - el programa (o el arnes) deja una entrada pendiente: INP_FLAG = 1, INP_AREA (1 verbo, 2 escena, 3 inventario,
;     4 tecla, 5 frase) e INP_VAL (el verbo, el objeto o la tecla); y actualiza VAR_VIRT_MOUSE_X / Y (variables 30 y 31)
;   - vm_frame la atiende: pone las variables del clic y arranca el script 4 (runInputScript)
;   - doSentence (opcode 0x19...) apila frases en SENTQ; checkAndRunSentenceScript saca la ultima y arranca el
;     script 2 con VAR_ACTIVE_VERB / OBJECT1 / OBJECT2 (y VAR_VERB_ALLOWED)
;   - findObject y actorFromPos dicen que hay bajo el cursor

NUM_SENTENCE    equ 6
SENTQ           equ $FE00       ; NUM_SENTENCE x 8: verbo, objeto A (2), objeto B (2), preposicion, 2 sin uso
INP_FLAG        equ $EB72
INP_AREA        equ $EB73
INP_VAL         equ $EB74       ; palabra
EV_SENTENCE     equ 7
SENTENCE_SCRIPT equ 2
INPUT_SCRIPT    equ 4
OBJREC          equ 11          ; bytes de cada objeto en el bloque de la sala

; variables de trabajo (zona de GSCR, despues de las de walk.asm)
FO_X            equ GSCR+176    ; palabra
FO_Y            equ GSCR+178
FO_T            equ GSCR+180
FO_I            equ GSCR+182
FO_N            equ GSCR+183
FO_B            equ GSCR+184
FO_A            equ GSCR+185
FO_CAP          equ GSCR+186
ROS_VERB        equ GSCR+187
ROS_SLOT        equ GSCR+188
ROS_OBJ         equ GSCR+189    ; palabra

; ---------------------------------------------------------------------------------------------- objeto bajo el cursor
; HL = numero de registro (A) -> IX
fo_rec:         ld c,a
                ld b,0
                ld l,c
                ld h,b
                add hl,hl
                add hl,hl
                add hl,hl               ; * 8
                add hl,bc
                add hl,bc
                add hl,bc               ; * 11
                ld de,(OBJSP)
                add hl,de
                push hl
                pop ix
                ret

fo_state:       ld de,OBJST             ; HL = objeto -> A = su estado
                add hl,de
                ld a,(hl)
                ret

; findObject de v2: FO_X, FO_Y en pixeles -> HL = objeto o 0
find_object:    ld a,(NOBJS)
                or a
                jp z,fo_none
                ld (FO_N),a
                xor a
                ld (FO_I),a
fo_loop:        ld a,(FO_I)
                call fo_rec
                ld l,(ix+0)
                ld h,(ix+1)
                call fo_state
                and 2                   ; intocable
                jp nz,fo_next
                ld a,(FO_I)
                inc a
                ld (FO_B),a
                ld a,32
                ld (FO_CAP),a
fo_chain:       ld a,(FO_N)
                ld hl,FO_B
                cp (hl)
                jr nc,fo_real           ; el padre existe
                xor a                   ; no existe: sin padre y sin estado
                ld (FO_B),a
                jp fo_bounds
fo_real:        ld a,(FO_B)
                dec a
                call fo_rec
                ld a,(ix+10)            ; estado que pide el padre
                ld (FO_A),a
                ld a,(ix+9)             ; padre
                ld (FO_B),a
                or a
                jr z,fo_bounds
                ld c,a
                ld a,(FO_N)
                cp c
                jr c,fo_st0             ; el padre no existe: estado 0
                ld a,c
                dec a
                call fo_rec
                ld l,(ix+0)
                ld h,(ix+1)
                call fo_state
                jr fo_cmp
fo_st0:         xor a
fo_cmp:         and 8
                ld c,a
                ld a,(FO_A)
                cp c
                jp nz,fo_next
                ld hl,FO_CAP
                dec (hl)
                jr nz,fo_chain
                jr fo_next
fo_bounds:      ld a,(FO_I)
                call fo_rec
                ld l,(ix+5)             ; izquierda = x * 8
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(FO_X)
                ex de,hl
                or a
                sbc hl,de               ; x - izquierda
                jp c,fo_next
                ld l,(ix+5)             ; derecha = (x + ancho) * 8
                ld h,0
                ld e,(ix+7)
                ld d,0
                add hl,de
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(FO_X)
                or a
                sbc hl,de               ; derecha - x
                jp z,fo_next
                jp c,fo_next
                ld l,(ix+6)             ; arriba = y * 8
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(FO_Y)
                ex de,hl
                or a
                sbc hl,de
                jp c,fo_next
                ld l,(ix+6)             ; abajo = (y + alto) * 8
                ld h,0
                ld e,(ix+8)
                ld d,0
                add hl,de
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(FO_Y)
                or a
                sbc hl,de
                jp z,fo_next
                jp c,fo_next
                ld l,(ix+0)
                ld h,(ix+1)
                ret
fo_next:        ld hl,FO_I
                inc (hl)
                ld a,(FO_N)
                cp (hl)
                jp nz,fo_loop
fo_none:        ld hl,0
                ret

h_o2_findObject:                        ; ARGS: resultado, x, y (x * 8 e y * 2 son pixeles)
                ld hl,(ARGS+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld (FO_X),hl
                ld hl,(ARGS+4)
                add hl,hl
                ld (FO_Y),hl
                call find_object
                ld b,h
                ld c,l
                ld a,(ARGS)
                jp write_var

; getActorFromPos aproximado: el primer actor visible de la sala cuyo rectangulo de 16 x 32 contiene el punto
h_o2_actorFromPos:
                ld hl,(ARGS+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld (FO_X),hl
                ld hl,(ARGS+4)
                add hl,hl
                ld (FO_Y),hl
                ld ix,ACTORS+ASIZE
                ld b,NACTORS-1
                ld c,1
afp_l:          push bc
                ld a,(CURROOM)
                cp (ix+0)
                jp nz,afp_next
                ld a,(ix+9)
                or a
                jp z,afp_next
                ld l,(ix+1)             ; x * 8 - 8 <= x < x * 8 + 8
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,8
                or a
                sbc hl,de
                ex de,hl                ; DE = izquierda
                ld hl,(FO_X)
                call sless              ; x < izquierda ?
                jp c,afp_next
                ld l,(ix+1)
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,8
                add hl,de               ; derecha
                ld de,(FO_X)
                call sless              ; derecha < x ?
                jp c,afp_next
                jp z,afp_next           ; derecha = x: fuera
                ld l,(ix+3)             ; y * 2 - 32 <= y < y * 2
                ld h,(ix+4)
                add hl,hl
                ld de,32
                or a
                sbc hl,de
                ex de,hl
                ld hl,(FO_Y)
                call sless
                jp c,afp_next
                ld l,(ix+3)
                ld h,(ix+4)
                add hl,hl
                ld de,(FO_Y)
                call sless              ; abajo < y ?
                jp c,afp_next
                jp z,afp_next
                pop bc
                ld a,c
                ld c,a
                ld b,0
                jp afp_w
afp_next:       ld de,ASIZE
                add ix,de
                pop bc
                inc c
                djnz afp_l
                ld bc,0
afp_w:          ld a,(ARGS)
                jp write_var

; ---------------------------------------------------------------------------------------------- objetos: codigo y verbos
; DE = objeto, ROS_VERB = verbo -> A = offset del verbo en su bloque (0 = no hay); APIA = direccion del bloque con su
; pagina en la ventana de datos. Cuando no esta (o no hay codigo), 0
object_entry:   ld (ROS_OBJ),de
                ld l,e
                ld h,d
                call where_is_object
                or a
                ret z                   ; el objeto no esta en la sala ni en un inventario
                ld de,(ROS_OBJ)
                ld l,e
                ld h,d
                add hl,hl
                add hl,de               ; * 3
                ld de,ODIRBUF
                add hl,de
                ld a,(hl)
                or a
                ret z                   ; sin bloque de codigo
                ld (ROS_PAGE),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (APIA),de
                call map_page
                ld hl,(APIA)
                ld de,15
                add hl,de
oe_l:           ld a,(hl)
                or a
                ret z                   ; fin de la tabla
                ld c,a
                ld a,(ROS_VERB)
                cp c
                jr z,oe_f
                ld a,c
                cp $FF
                jr z,oe_f
                inc hl
                inc hl
                jr oe_l
oe_f:           inc hl
                ld a,(hl)
                ret

; vuelve a poner en la ventana de datos la pagina del script en curso
restore_win:    ld a,(CUR)
                cp $FF
                ret z
                call slot_addr
                ld de,4
                add hl,de
                ld a,(hl)
                jp map_page

; DE = objeto, A = verbo -> A = 1 si el objeto tiene codigo para ese verbo
verb_allowed:   ld (ROS_VERB),a
                call object_entry
                or a
                push af
                call restore_win
                pop af
                ld a,0
                ret z
                inc a
                ret

; runObjectScript: DE = objeto, A = verbo, B = ranura que se reutiliza ($FF: una libre)
run_object_script:
                ld (ROS_VERB),a
                ld a,b
                ld (ROS_SLOT),a
                ld a,d
                or e
                ret z
                ld (ROS_OBJ),de
                ld l,e
                ld h,d
                call where_is_object
                or a
                ret z
                ld a,(ROS_SLOT)
                cp $FF
                jr nz,ros_have
                call alloc_slot
                ret c
                ld (ROS_SLOT),a
ros_have:       ld de,(ROS_OBJ)
                call object_entry
                or a
                jr z,ros_none
                ld e,a
                ld d,0
                ld hl,(APIA)
                add hl,de
                ld (APIA),hl
                ld hl,(ROS_OBJ)
                ld (APIN),hl
                ld a,WIO_ROOM
                ld (APIW),a
                ld a,(ROS_PAGE)         ; la pagina del bloque, para la ranura
                ld (APIP),a
                ld a,(ROS_SLOT)
                jp start_slot_at
ros_none:       jp restore_win
ROS_PAGE        equ GSCR+191

; stopObjectScript: DE = objeto: mata las ranuras de objeto con ese numero
stop_object_script:
                ld ix,SLOTS
                ld b,NSLOT
                ld c,0
sos_l:          ld a,(ix+2)
                cp e
                jr nz,sos_n
                ld a,(ix+3)
                cp d
                jr nz,sos_n
                ld a,(ix+0)
                or a
                jr z,sos_n
                ld a,(ix+1)
                cp WIO_ROOM
                jr z,sos_k
                or a                    ; WIO_INVENTORY = 0
                jr z,sos_k
                cp 4                    ; WIO_FLOBJECT
                jr nz,sos_n
sos_k:          xor a
                ld (ix+0),a
                ld (ix+2),a
                ld (ix+3),a
                ld a,(CUR)
                cp c
                jr nz,sos_n
                ld a,$FF
                ld (CUR),a
sos_n:          push de
                ld de,16
                add ix,de
                pop de
                inc c
                djnz sos_l
                ld ix,NEST
                ld b,MAXNEST
sos_nl:         ld a,(ix+0)
                cp e
                jr nz,sos_nn
                ld a,(ix+1)
                cp d
                jr nz,sos_nn
                ld a,(ix+2)
                cp WIO_ROOM
                jr z,sos_nk
                or a
                jr z,sos_nk
                cp 4
                jr nz,sos_nn
sos_nk:         xor a
                ld (ix+0),a
                ld (ix+1),a
                ld a,$FF
                ld (ix+3),a
                ld (ix+2),a
sos_nn:         push de
                ld de,4
                add ix,de
                pop de
                djnz sos_nl
                ret

; ---------------------------------------------------------------------------------------------- doSentence
h_o2_doSentence:                        ; ARGS: verbo, objeto A, objeto B, subopcode (los tres ultimos salvo con $FB y $FC)
                ld hl,(ARGS)
                ld a,l
                cp $FC
                jr z,ds_fc
                cp $FB
                jr z,ds_fb
                ld a,(SENTNUM)
                cp NUM_SENTENCE
                jr c,ds_push
                ld a,E_RANGE
                ld (ERR),a
                ret
ds_fc:          xor a
                ld (SENTNUM),a
                ld de,SENTENCE_SCRIPT
                jp stop_script
ds_fb:          jp reset_sentence
ds_push:        ld l,a                  ; HL = SENTQ + 8 * SENTNUM
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SENTQ
                add hl,de
                ld a,(ARGS)
                ld (hl),a
                inc hl
                ld de,(ARGS+2)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld de,(ARGS+4)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,d
                or e
                ld a,0
                jr z,ds_p0
                inc a
ds_p0:          ld (hl),a
                ld hl,SENTNUM
                inc (hl)
                ld a,(ARGS+6)
                or a
                ret z                   ; subopcode 0: se queda en la cola
                dec (hl)                ; las demas la sacan
                cp 1
                jr z,ds_exec
                cp 2
                jr z,ds_print
                ld a,E_RANGE
                ld (ERR),a
                ret
ds_print:       ld hl,(ARGS)
                ld h,0
                ld (VARS+52),hl         ; VAR_SENTENCE_VERB
                ld (EVARGS),hl
                ld hl,(ARGS+2)
                ld (VARS+54),hl
                ld (EVARGS+2),hl
                ld hl,(ARGS+4)
                ld (VARS+56),hl
                ld (EVARGS+4),hl
                ld a,EV_SENTENCE
                jp ev_emit
ds_exec:        ld a,(ARGS)
                cp 254
                jr nz,dse_1
                ld de,(ARGS+2)
                jp stop_object_script
dse_1:          cp 253
                jr z,dse_sp
                cp 250
                jr z,dse_sp
                ld l,a
                ld h,0
                ld (VARS+16),hl         ; VAR_ACTIVE_VERB
                ld hl,(ARGS+2)
                ld (VARS+18),hl         ; VAR_ACTIVE_OBJECT1
                ld hl,(ARGS+4)
                ld (VARS+20),hl         ; VAR_ACTIVE_OBJECT2
                jr dse_slot
dse_sp:         ld a,253
                ld (ARGS),a
dse_slot:       ld ix,SLOTS             ; una ranura que ya corre el codigo de ese objeto se reutiliza
                ld b,NSLOT
                ld c,0
                ld de,(ARGS+2)
dse_l:          ld a,(ix+2)
                cp e
                jr nz,dse_n
                ld a,(ix+3)
                cp d
                jr nz,dse_n
                ld a,(ix+0)
                or a
                jr z,dse_n
                ld a,(ix+1)
                cp WIO_ROOM
                jr z,dse_f
                or a
                jr z,dse_f
                cp 4
                jr z,dse_f
dse_n:          push de
                ld de,16
                add ix,de
                pop de
                inc c
                djnz dse_l
                ld c,$FF
dse_f:          ld b,c
                ld de,(ARGS+2)
                ld a,(ARGS)
                jp run_object_script

; ---------------------------------------------------------------------------------------------- frase y entrada
; checkAndRunSentenceScript de v2
check_sentence: ld de,SENTENCE_SCRIPT
                call is_script_in_use
                or a
                ret nz
                ld a,(SENTNUM)
                or a
                ret z
                dec a
                ld (SENTNUM),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SENTQ
                add hl,de
                push hl
                pop ix
                ld a,(ix+5)             ; preposicion y objeto B = objeto A: se descarta
                or a
                jr z,cs_go
                ld l,(ix+1)
                ld h,(ix+2)
                ld e,(ix+3)
                ld d,(ix+4)
                or a
                sbc hl,de
                ret z
cs_go:          ld l,(ix+0)
                ld h,0
                ld (VARS+16),hl         ; VAR_ACTIVE_VERB
                ld l,(ix+1)
                ld h,(ix+2)
                ld (VARS+18),hl
                ld l,(ix+3)
                ld h,(ix+4)
                ld (VARS+20),hl
                ld e,(ix+1)
                ld d,(ix+2)
                ld a,(ix+0)
                call verb_allowed
                ld l,a
                ld h,0
                ld (VARS+36),hl         ; VAR_VERB_ALLOWED
                ld a,$FF
                ld (CUR),a
                ld de,SENTENCE_SCRIPT
                jp run_script

; runInputScript de v2: la entrada pendiente (INP_FLAG)
process_input:  ld a,(INP_FLAG)
                or a
                ret z
                xor a
                ld (INP_FLAG),a
                ld a,(INP_AREA)
                ld l,a
                ld h,0
                ld (VARS+64),hl         ; VAR_CLICK_AREA
                ld hl,(INP_VAL)
                cp 1
                jr nz,pi_1
                ld (VARS+66),hl         ; VAR_CLICK_VERB
                jr pi_go
pi_1:           cp 3
                jr nz,pi_2
                ld (VARS+70),hl         ; VAR_CLICK_OBJECT
                jr pi_go
pi_2:           cp 4
                jr nz,pi_go
                ld (VARS+78),hl         ; VAR_KEYPRESS
pi_go:          ld a,$FF
                ld (CUR),a
                ld de,INPUT_SCRIPT
                jp run_script

; ---------------------------------------------------------------------------------------------- objetos que se dibujan
; drawRoomObject de v2 (igual que ScummVM): el objeto A (indice en la lista de la sala, desde 0) se dibuja si su estado tiene el bit 8 y los padres tienen el
; estado pedido, sin mirar el dueno: un objeto recogido sigue dibujado (la llave: al recogerla se pone su bit 8 y su cuadro negro tapa el hueco bajo el felpudo).
; Salida: carry si se dibuja
obj_drawn:      ld (FO_I),a
                ld a,(NOBJS)
                ld (FO_N),a
                ld a,(FO_I)
                call fo_rec
                ld l,(ix+0)
                ld h,(ix+1)
                call fo_state
                and 8
                ret z                   ; sin el bit 8 propio no se dibuja (NC)
od_go:
                ld a,(FO_I)
                inc a
                ld (FO_B),a
                ld a,32
                ld (FO_CAP),a
od_chain:       ld a,(FO_N)
                ld hl,FO_B
                cp (hl)
                jr nc,od_real
                scf                     ; el padre no existe: sin padre, se dibuja
                ret
od_real:        ld a,(FO_B)
                dec a
                call fo_rec
                ld a,(ix+10)
                ld (FO_A),a
                ld a,(ix+9)
                ld (FO_B),a
                or a
                jr nz,od_par
                scf
                ret
od_par:         ld c,a
                ld a,(FO_N)
                cp c
                jr c,od_st0
                ld a,c
                dec a
                call fo_rec
                ld l,(ix+0)
                ld h,(ix+1)
                call fo_state
                jr od_cmp
od_st0:         xor a
od_cmp:         and 8
                ld c,a
                ld a,(FO_A)
                cp c
                ret nz                  ; el estado del padre no es el pedido: NC
                ld hl,FO_CAP
                dec (hl)
                jr nz,od_chain
                or a
                ret

; drawObject de v2 (sin cambiar de sitio al objeto): lo marca como dibujado y apaga los demas objetos de la sala que
; ocupan el mismo rectangulo. ARGS: objeto, x, y
h_o2_drawObject:
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
                xor a
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

; getObjectOwner: ARGS: resultado, objeto
h_o5_getObjectOwner:
                ld hl,(ARGS+2)
                ld de,NOBJ
                or a
                sbc hl,de
                jr c,go_ok
                ld a,E_BADOBJ
                ld (ERR),a
                ret
go_ok:          add hl,de
                ld de,OBJOWN
                add hl,de
                ld c,(hl)
                ld b,0
                ld a,(ARGS)
                jp write_var

; setOwnerOf: ARGS: objeto, dueno (0: quita el objeto de los inventarios y para sus scripts)
h_o2_setOwnerOf:
                ld hl,(ARGS)
                ld a,h
                or l
                ret z
                call state_get          ; HL = &estado, A = estado; error: carry
                ret c
                push af
                ld hl,(ARGS)
                ld de,OBJOWN
                add hl,de
                ld a,(ARGS+2)
                ld (hl),a
                or a
                jr nz,so_ev
                ld de,(ARGS)
                call stop_object_script
so_ev:          pop af
                jp st_event

; pickupObject: ARGS: objeto
h_o2_pickupObject:
                ld hl,(ARGS)
                ld a,h
                or l
                jr nz,po_1
                ld a,E_BADOBJ
                ld (ERR),a
                ret
po_1:           call state_get
                ret c
                ld hl,(ARGS)
                ld de,OBJOWN
                add hl,de
                ld a,(hl)
                cp 15
                jr z,po_do
                or a
                ret nz                  ; ya esta en un inventario
po_do:          ld a,(VARS)             ; el protagonista
                ld (hl),a
                ld hl,(ARGS)
                ld de,OBJST
                add hl,de
                ld a,(hl)
                or $0A
                ld (hl),a
                jp st_event

; getDist: ARGS: resultado, a, b. Maximo de |dx| y |dy| entre dos objetos o actores ($FF si alguno no tiene posicion)
GD_A            equ $FF00               ; palabra
GD_B            equ $FF02
GD_X1           equ $FF04
GD_Y1           equ $FF06
GD_X2           equ $FF08
GD_Y2           equ $FF0A
GD_FA           equ $FF0C               ; 1: a es un actor
GD_FB           equ $FF0D
GD_RAW          equ $FF0E
CO_ARG          equ $FF10               ; getClosestObjActor: objeto o actor, distancia minima, el actor y el contador
CO_D            equ $FF12
CO_I            equ $FF14
CO_N            equ $FF15

h_o5_getDist:
                ld hl,(ARGS+2)
                ld (GD_A),hl
                call gd_isact
                ld (GD_FA),a
                ld hl,(ARGS+4)
                ld (GD_B),hl
                call gd_isact
                ld (GD_FB),a
                ld hl,GD_FA
                and (hl)
                jp z,gd_pos             ; los dos son actores de la misma sala que no es la actual: distancia 0
                ld a,(GD_A)
                call actor_addr
                ld c,(ix+0)
                ld a,(GD_B)
                call actor_addr
                ld a,(ix+0)
                cp c
                jp nz,gd_pos
                or a
                jp z,gd_pos
                ld b,a
                ld a,(CURROOM)
                cp b
                jp z,gd_pos
                ld bc,0
                jp gd_out
gd_pos:         ld hl,(GD_A)
                call object_or_actor_xy
                jp c,gd_ff
                ld hl,(WK_OX)
                ld (GD_X1),hl
                ld hl,(WK_OY)
                ld (GD_Y1),hl
                ld hl,(GD_B)
                call object_or_actor_xy
                jp c,gd_ff
                ld hl,(WK_OX)
                ld (GD_X2),hl
                ld hl,(WK_OY)
                ld (GD_Y2),hl
                ld a,(GD_FA)            ; actor -> objeto: el punto del objeto se ajusta a una caja del actor
                or a
                jp z,gd_cmp
                ld a,(GD_FB)
                or a
                jp nz,gd_cmp
                ld a,(GD_A)
                call actor_addr
                ld hl,(GD_X2)
                ld (AX_X),hl
                ld hl,(GD_Y2)
                ld (AX_Y),hl
                call adjust_xy
                ld a,(ERR)
                or a
                ret nz
                ld hl,(AX_RX)
                ld (GD_X2),hl
                ld hl,(AX_RY)
                ld (GD_Y2),hl
gd_cmp:         ld hl,(GD_X1)
                ld de,(GD_X2)
                or a
                sbc hl,de
                call gd_abs
                push hl
                ld hl,(GD_Y1)
                ld de,(GD_Y2)
                or a
                sbc hl,de
                call gd_abs
                pop de                  ; DE = |dx|, HL = |dy|
                push hl
                or a
                sbc hl,de
                pop hl
                jp nc,gd_mx
                ex de,hl
gd_mx:          ld b,h
                ld c,l
gd_out:         ld a,(GD_RAW)           ; 1: solo devuelve la distancia en BC (getClosestObjActor)
                or a
                ret nz
                ld a,(ARGS)
                jp write_var
gd_ff:          ld bc,$00FF
                jp gd_out
gd_abs:         bit 7,h
                ret z
                ld a,l
                cpl
                ld l,a
                ld a,h
                cpl
                ld h,a
                inc hl
                ret
; HL = objeto o actor -> A = 1 si es un actor
gd_isact:       ld a,h
                or a
                jp nz,gd_no
                ld a,l
                cp NACTORS
                jp nc,gd_no
                ld a,1
                ret
gd_no:          xor a
                ret

; ------------------------------------------------------------------------------------ getRandomNr y cutscenes
RNDST           equ $EB90               ; palabra: generador (x = x * 5 + 1); semilla $ACE1 en vm_init
CUTPTR          equ $EB92               ; palabra: donde sigue el script si se salta la cutscene (beginOverride); 0: no hay
CUTSLOT         equ $EB94               ; ranura del script que ha hecho beginOverride

h_o5_getRandomNr:                       ; ARGS: resultado, max -> 0..max
                ld hl,(RNDST)
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                inc hl
                ld (RNDST),hl
                ld c,h                  ; byte aleatorio
                ld a,(ARGS+2)
                inc a
                jr z,rn_full            ; max = 255: el byte tal cual
                ld e,a
                ld d,0
                ld hl,0
                ld b,8
rn_m:           add hl,hl
                rlc c
                jr nc,rn_n
                add hl,de
rn_n:           djnz rn_m
                ld c,h                  ; (byte * (max + 1)) >> 8
rn_full:        ld b,0
                ld a,(ARGS)
                jp write_var

h_o2_cutscene:                          ; sin frases pendientes ni script de frases; lo demas (interfaz) lo hace el anfitrion
                xor a
                ld (SENTNUM),a
                ld de,SENTENCE_SCRIPT
                call stop_script
                call reset_sentence
                jp h_host

h_o2_endCutscene:
                ld hl,0
                ld (VARS+10),hl         ; VAR_OVERRIDE = 0
                ld (CUTPTR),hl
                jp h_host

h_o2_beginOverride:                     ; ARGS: b, w: el salto que sigue ya esta leido; si se salta la cutscene el script sigue en ese salto
                ld a,(CUR)
                ld (CUTSLOT),a
                ld hl,(SPTR)
                dec hl
                dec hl
                dec hl
                ld (CUTPTR),hl
                jp h_host

; el jugador salta la cutscene: el script que hizo beginOverride sigue en su salto y VAR_OVERRIDE = 1
vm_abort_cutscene:
                ld hl,(CUTPTR)
                ld a,h
                or l
                ret z
                ld a,(CUTSLOT)
                cp NSLOT
                ret nc
                call slot_addr
                ld de,5
                add hl,de
                ld de,(CUTPTR)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld b,4                  ; sin retardo pendiente
                xor a
vac_d:          ld (hl),a
                inc hl
                djnz vac_d
                ld a,(CUTSLOT)
                call slot_addr
                ld (hl),2               ; en marcha
                ld hl,1
                ld (VARS+10),hl
                ld hl,0
                ld (CUTPTR),hl
                ret

; getClosestObjActor (R, W1): el actor (de 0 a NACTORS - 1) mas cercano al objeto o actor W1; a igual distancia gana el de numero mas alto; $FF si ninguno
h_o5_getClosestObjActor:
                ld hl,(ARGS+2)
                ld (CO_ARG),hl
                ld hl,$00FF
                ld (CO_D),hl
                ld a,$FF
                ld (CO_I),a
                ld a,NACTORS
                ld (CO_N),a
co_l:           ld a,(CO_N)
                dec a
                ld (CO_N),a
                ld l,a
                ld h,0
                ld (ARGS+4),hl
                ld hl,(CO_ARG)
                ld (ARGS+2),hl
                ld a,1
                ld (GD_RAW),a
                call h_o5_getDist
                xor a
                ld (GD_RAW),a
                ld a,(ERR)
                or a
                ret nz
                ld hl,(CO_D)
                or a
                sbc hl,bc
                jr c,co_n
                jr z,co_n
                ld (CO_D),bc
                ld a,(CO_N)
                ld (CO_I),a
co_n:           ld a,(CO_N)
                or a
                jr nz,co_l
                ld a,(CO_I)
                ld c,a
                ld b,0
                ld a,(ARGS)
                jp write_var

; setBoxFlags (B1, b): las banderas de una caja de la sala actual
h_o3_setBoxFlags:
                ld a,(ARGS)
                call box_rec
                ret c
                ld de,7
                add hl,de
                ld a,(ARGS+2)
                ld (hl),a
                ret

; lights (B1, b, b): c = 0 -> VAR_CURRENT_LIGHTS (variable 12); el resto lo hace el anfitrion
h_o2_lights:
                ld a,(ARGS+4)
                or a
                jr nz,li_h
                ld hl,(ARGS)
                ld h,0
                ld (VARS+24),hl
li_h:           jp h_host

; getObjPreposition (R, W1): la preposicion del objeto (bits 5-7 del byte 12 de su bloque); 0 si no esta en la sala ni en un inventario
h_o2_getObjPreposition:
                ld de,(ARGS+2)
                ld l,e
                ld h,d
                call where_is_object
                or a
                jr z,gp_0
                ld de,(ARGS+2)
                ld l,e
                ld h,d
                add hl,hl
                add hl,de
                ld de,ODIRBUF
                add hl,de
                ld a,(hl)
                or a
                jr z,gp_0
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                push de
                call map_page
                pop hl
                ld de,12
                add hl,de
                ld a,(hl)
                rlca
                rlca
                rlca
                and 7
                ld c,a
                ld b,0
                push bc
                call restore_win
                pop bc
                jr gp_w
gp_0:           ld bc,0
gp_w:           ld a,(ARGS)
                jp write_var
