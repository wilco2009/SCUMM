; vm_core.asm - nucleo residente del interprete SCUMM v3 (Indy3 EGA, ScummEngine_v3old) para el SD81 Booster
;
; Fase 3 de SCUMM/V3/PLAN.md. Mapa de memoria y decisiones: SCUMM/V3/FASE3.md.
; Semantica: la de ScummVM (script.cpp, script_v5.cpp, script_v4.cpp, script_v3.cpp) tal como la transcribe el modelo
; SCUMM/V3/TOOLS/vmmodel3.py (CoreVM en el modo nucleo); el arnes test/test_vm.cpp compara las trazas.
;
; Despachador: es_loop coge el opcode, mira disp_lo/disp_hi (tables3.inc, generada por V3/TOOLS/gen_vmtables3.py) y salta al
; manejador con DE = puntero del script (tras el opcode). Un manejador NATIVO lee sus operandos con rd_var, rd_vb1..3, rd_vw1..3,
; rd_res...; uno GENERICO empieza con `call decode` (especificacion spec_lo/spec_hi -> ARGS). Todos dejan SPTR tras sus operandos.
; Errores: vm_err salta a la pila de la entrada de la API (TOPSP): el error es fatal, como en ScummVM.
;
; Registros: DE = puntero del script mientras se leen operandos. Los lectores devuelven el valor en BC y usan A y HL.

NSLOT           equ 24          ; ranuras (ScummVM 80; maximo medido en Indy3: 17). El modelo usa las mismas (vmcommon3.NUM_SLOT)
NLOCAL          equ 16          ; locales por ranura (vmcommon3.NUM_LOCAL)
MAXNEST         equ 15
MAXCUT          equ 5
MAXARGS         equ 32          ; argumentos de decode (vmcommon3.MAX_ARGS)
MAXESTK         equ 32          ; pila de expression (vmcommon3.MAX_ESTACK)
NGLOBAL         equ 200         ; scripts globales 0-199; los locales de sala son >= 200
NOBJ            equ 1000
SS_DEAD         equ 0
SS_PAUSED       equ 1
SS_RUNNING      equ 2
WIO_INVENTORY   equ 0
WIO_ROOM        equ 1
WIO_GLOBAL      equ 2
WIO_LOCAL       equ 3
WIO_FLOBJECT    equ 4
E_NOSLOT        equ 1
E_NEST          equ 2
E_RANGE         equ 3
E_NOSCRIPT      equ 4
E_BADOBJ        equ 5
E_BADACTOR      equ 7
E_BADOP         equ 8
NACT            equ 13          ; actores (vmcommon3.NUM_ACTORS)
NINV            equ 80          ; ranuras de inventario (vmcommon3.NUM_INVENTORY)
NNAMES          equ 50          ; nombres nuevos de objeto (ScummEngine_v4::readMAXS; vmcommon3.NUM_NEW_NAMES)
OWNER_ROOM      equ $0F
ASIZE           equ 64          ; registro de un actor (Actor.pack() del modelo)
EVPORT          equ $F2         ; sucesos para el back-end (arnes de PC)
EV_SOUND_START  equ 1
EV_SOUND_STOP   equ 2
EV_SOUND_STOPALL equ 3
EV_SOUND_QUERY  equ 4
EV_TEXT         equ 5
EV_OBJSTATE     equ 8
EV_VERB         equ 11
CAM_NORMAL      equ 1           ; CameraMode
CAM_FOLLOW      equ 2
CAM_PANNING     equ 3
CAM_LEFT        equ 10          ; _cameraLeft/_cameraRight del modelo (vmgame3: left=10, right=30)
CAM_RIGHT       equ 30
E_CUTSCENE      equ 10
E_BADSUB        equ 11
E_HALT          equ 12          ; systemOps de reinicio o salida
SCRIPT_NUM_EXCD equ 10001
SCRIPT_NUM_ENCD equ 10002
WINDOW          equ $2000       ; ventana de datos: bloque 1, $2000-$37FF (6 KB de cada pagina)
WINHI           equ $18         ; paginas de 6 KB: un puntero valido tiene (alto - $20) < $18
BIGHI           equ $10         ; D5: en una pagina de un script grande que no es la ultima, solo empiezan instrucciones en 4 KB
OVB_PAGE        equ 49          ; overlay B (D4): manejadores con subopcodes, expression, stringOps y la frase
TABPG           equ 15          ; pagina fisica con las tablas frias de DATA.BIN (ROOMDIR, ODIR, OBJROOM, COSTDIR, COSTDIR2)
HOSTPORT        equ $F1
MAP_PORT        equ $E7

; ---- registro de una ranura (16 bytes)
SL_STAT         equ 0           ; estado (bit 7: congelada)
SL_WHERE        equ 1
SL_NUM          equ 2           ; palabra
SL_PAGE         equ 4           ; pagina de datos del codigo
SL_PTR          equ 5           ; palabra: direccion en la ventana
SL_DELAY        equ 7           ; 32 bits con signo
SL_FLAGS        equ 11          ; bit 5 freezeResistant, bit 6 recursive (como en el opcode de startScript)
SL_FREEZE       equ 12          ; freezeCount
SL_CUTOV        equ 13          ; cutsceneOverride
SL_BIG          equ 14          ; 0, o indice + 1 en BIGDIR (script de mas de una pagina, D5)
SL_DIDEX        equ 15          ; didexec: ya ha corrido en esta vuelta de runAllScripts

; ---- tablas frias (pagina TABPG, se leen con cold_rd por el bloque 0)
COLD_ROOMDIR    equ 0           ; 100 x 32
COLD_ODIR       equ 3200        ; 1000 x 3
COLD_OBJROOM    equ 6200        ; 1000
COLD_COSTDIR    equ 7200        ; 129 x 3
COLD_COSTDIR2   equ 7587        ; 129 x 3 (hasta 7974)

; ---- estado de la capa de juego en el bloque 4 (fase 4a; FASE3.md, "Lo que queda por colocar": el hueco de ODIRBUF de v2)
ACTORS          equ $8B00       ; NACT x ASIZE = 832 B (hasta $8E3F). Campos A_*
NEWNAMES        equ $8E40       ; setObjectName: NNAMES palabras (objeto) y NNAMES x 3 (pagina, direccion de la cadena): 250 B

; ---- estado de la VM: bloque 7, siempre mapeado (FASE3.md, "Mapa de memoria")
VARS            equ $E000       ; 256 x u16. Tiene que estar en $E000: rd_var hace ld h,$70 / add hl,hl
OBJST           equ $E200       ; 1000: estado de cada objeto
OBJOWN          equ $E5E8       ; 1000: dueno
OBJCLS          equ $E9D0       ; 1000 x 3: clases (24 bits)
SCRDIR          equ $F588       ; 200 x 3: pagina (0 = no hay; 255 = grande: la direccion es el indice en BIGDIR), direccion
BIGDIR          equ $F7E0       ; 4 x 8: id, paginas, primera pagina, 0, direccion, longitud
SLOTS           equ $F800       ; NSLOT x 16
LOCALS          equ $F980       ; NSLOT x NLOCAL x 2
NEST            equ $FC80       ; MAXNEST x 4: numero (2), donde, ranura
CUTDATA         equ $FCC0       ; MAXCUT x 2
CUTPTR          equ $FCCA       ; MAXCUT x 2: direccion de beginOverride (0 = no hay)
CUTSCR          equ $FCD4       ; MAXCUT: ranura
CUTPG           equ $FCD9       ; MAXCUT: pagina de CUTPTR
ARGS            equ $FD00       ; MAXARGS x 2 (decode); no puede cruzar una frontera de 256
ARGS_END        equ ARGS+2*MAXARGS
VARARG          equ $FD40       ; NLOCAL x 2: getWordVararg
ESTK            equ $FD60       ; MAXESTK x 4: pila de expression (32 bits)
VMV             equ $FDE0       ; variables sueltas del nucleo (hasta $FE5F)
CUR             equ VMV+0       ; ranura en ejecucion o $FF
SPTR            equ VMV+1       ; palabra: puntero del script
OPC             equ VMV+3       ; opcode en curso (los subopcodes lo cambian, como _opcode de ScummVM)
NESTN           equ VMV+4
ARGN            equ VMV+5
HRES            equ VMV+6       ; palabra: resultado del anfitrion
HFLAG           equ VMV+8       ; condicion del anfitrion (saltos)
ERR             equ VMV+9
DELTA           equ VMV+10
CUTSP           equ VMV+11
CUTIDX          equ VMV+12      ; _cutSceneScriptIndex ($FF = ninguno)
CURROOM         equ VMV+13
VACNT           equ VMV+14      ; valores en VARARG que pasan a los locales de la siguiente ranura que se arranque
APIW            equ VMV+15      ; parametros de start_slot y de las entradas: donde, numero, pagina, direccion, verbo, grande, banderas
APIN            equ VMV+16
APIP            equ VMV+18
APIA            equ VMV+19
APIVERB         equ VMV+21
APIBIG          equ VMV+22
APIFL           equ VMV+23
RESV            equ VMV+24      ; palabra: numero de variable del resultado (_resultVarNumber)
JTGT            equ VMV+26      ; palabra: destino de la J de decode
TOPOP           equ VMV+28      ; opcode de la instruccion que se decodifica
ARGP            equ VMV+29      ; palabra
LOCP            equ VMV+31      ; palabra: locales de la ranura en curso
CURSLOT         equ VMV+33      ; palabra: registro de la ranura en curso
TOPSP           equ VMV+35      ; palabra: SP de la entrada de la API (errores)
DS_SP           equ VMV+37      ; palabra: SP de decode (X y Q)
RNTMP           equ VMV+39
RAI             equ VMV+40
RNDST           equ VMV+41      ; palabra: getRandomNr (x = x * 5 + 1, semilla $ACE1)
OVLCUR          equ VMV+43      ; pagina en el bloque 0 (overlay A, B o la ROM/pagina 0 en el arnes)
HOSTVEC         equ VMV+44      ; palabra: rutina del anfitrion (vm_init: host_null; el arnes pone OUT ($F1),A)
ESP             equ VMV+46      ; elementos en ESTK
EXDST           equ VMV+47      ; palabra (sin uso: expression guarda su destino en la pila)
WINPG           equ VMV+49      ; pagina en la ventana de datos
CURRD           equ VMV+50      ; 32 bytes: la entrada de ROOMDIR de la sala en uso
N1              equ VMV+82      ; aritmetica de 32 bits (arith32.asm)
N2              equ VMV+86
NR              equ VMV+90
DR              equ VMV+94
DSGN            equ VMV+98
EVID            equ VMV+99      ; sucesos para el back-end: numero, hasta 6 operandos (palabras) y la rutina que los atiende
EVARGS          equ VMV+100     ; 6 palabras
EVVEC           equ VMV+112     ; palabra (vm_init: ev_null; el arnes pone un OUT ($F2),A / RET)
CAMCUR          equ VMV+114     ; camara (vmgame3.cam): cur, dest (palabras con signo), modo, actor al que sigue, _movingToActor
CAMDEST         equ VMV+116
CAMMODE         equ VMV+118
CAMFOL          equ VMV+119
CAMMOV          equ VMV+120
SSTRIP          equ VMV+121     ; palabra: _screenStartStrip (lo cambia moveCamera: fase 5)
HAVEMSG         equ VMV+123     ; mensajes (los usa stopTalk; los llena la fase 4b)
KEEPTXT         equ VMV+124
USETALK         equ VMV+125
TALKDLY         equ VMV+126     ; palabra
LASTSND         equ VMV+128     ; palabra: last_sound (con signo)
EGOPOS          equ VMV+130     ; _egoPositioned
NBOXES          equ VMV+131     ; cajas de la sala en uso (0 hasta la fase 5: sin cajas)
INVSL           equ VMV+132     ; NINV palabras: el objeto de cada ranura de inventario (0: libre)
VMV_END         equ INVSL+2*NINV ; $FF04
SC              equ VMV_END     ; 24 B de variables temporales de los manejadores de B (no sobreviven a un script anidado)
NSTR            equ 32          ; ids de cadena (vmcommon3.NUM_STRINGS)
STRMAX          equ 480         ; bytes del monton (vmcommon3.STR_HEAP)
NVERB           equ 36          ; ranuras de verbo, la 0 incluida (vmcommon3.NUM_VERBS)
; fase 4b-1: cursor, pantalla principal y cadenas (bloque 7; vm_init los pone a 0 menos MAINTOP/MAINH)
USERPUT         equ SC+24       ; palabra con signo: _userPut (cursorCommand 3, 4, 7, 8)
CURSTATE        equ SC+26       ; palabra con signo: _cursor.state (cursorCommand 1, 2, 5, 6)
MAINTOP         equ SC+28       ; palabra: roomOps 3 (parte de arriba de la pantalla principal; vmgame3: main_top = 16)
MAINH           equ SC+30       ; palabra: roomOps 3 (alto; main_h = 144)
STRLEN          equ SC+32       ; NSTR bytes: longitud de la cadena (con su 0 final); 0 = no existe
STRPOS          equ SC+32+NSTR  ; NSTR palabras: direccion de la cadena en STRHEAP
STREND          equ STRPOS+2*NSTR ; palabra: fin de lo ocupado en STRHEAP (la suma de las longitudes)
FREE_END        equ STREND+2
; fase 4b-2: mensajes (print / printEgo). Estado en el bloque 7 ($FF86-$FFC3); el bufer del mensaje convertido (MSGBUF, MSG_MAX bytes) va
; en el residente, al final de vm_core.asm. Los valores por omision de cada ranura de texto son 11 bytes: xpos, ypos, right, height
; (palabras), color, center, overhead; WRK es la copia de trabajo de la que se esta imprimiendo (decodeParseString)
MSG_MAX         equ 320         ; vmcommon3.MSG_MAX: el mensaje convertido (con su 0 final) cabe en MSGBUF
MSG_DEPTH       equ 4           ; vmcommon3.MSG_DEPTH
STRSL           equ FREE_END    ; 4 x 11: valores por omision de las ranuras de texto 0-3
WRK             equ STRSL+44    ; 11: copia de trabajo
MSGPTR          equ WRK+11      ; palabra: direccion en MSGBUF del siguiente caracter (charset_pos; puede pasar del final)
MSGCNT          equ MSGPTR+2    ; palabra: msg_count
MSGEND          equ MSGCNT+2    ; palabra: direccion del 0 final del mensaje convertido
CHARCOL         equ MSGEND+2    ; charset_color
TXT_END         equ CHARCOL+1   ; $FFC4-$FFFF libres (60 B)
W_X             equ 0
W_Y             equ 2
W_R             equ 4
W_H             equ 6
W_C             equ 8
W_CEN           equ 9
W_OVH           equ 10
; bloque 4 (hueco de ODIRBUF): nombres de actor, verbos y monton de cadenas
ACTNAMES        equ NEWNAMES+NNAMES*5   ; $8F3A: NACT x 3: pagina y direccion de la cadena de actorOps 13 (pagina 0: sin nombre)
VERBS           equ ACTNAMES+3*NACT     ; NVERB x VSZ
VSZ             equ 18
V_ID            equ 0
V_COL           equ 1
V_HI            equ 2
V_DIM           equ 3
V_BK            equ 4
V_MODE          equ 5           ; curmode
V_SAVE          equ 6           ; saveid
V_KEY           equ 7
V_FLG           equ 8           ; bit 0 center, bit 1 type (1 = imagen)
V_IMG           equ 9           ; palabra
V_LEFT          equ 11          ; palabra
V_TOP           equ 13          ; palabra
V_NPG           equ 15          ; nombre: pagina (0 = sin nombre) y direccion (palabra) de la cadena en el script
V_NAD           equ 16
STRHEAP         equ VERBS+NVERB*VSZ     ; STRMAX bytes
HOLE_END        equ STRHEAP+STRMAX      ; hasta $9484 (donde acababa ODIRBUF)

                include "vars_v3.inc"

; ============================================================================================ entradas
; (org lo pone quien incluye: $4200 en vm.asm y en scumm.asm)
                jp vm_init              ; +0
                jp vm_run_ext           ; +3   APIW, APIN, APIP, APIA, APIBIG
                jp vm_run_object        ; +6   APIN, APIP, APIA (bloque OBCD), APIVERB
                jp vm_run_script        ; +9   APIN; VACNT valores en VARARG
                jp vm_frame             ; +12  DELTA
                jp vm_set_room          ; +15  APIN = sala
                jp vm_abort             ; +18  abortCutscene
                jp ENTRY_POINT          ; +21

vm_init:        ld (TOPSP),sp
                ld hl,VARS
                ld de,VARS+1
                ld bc,511
                ld (hl),0
                ldir
                ld hl,SLOTS             ; ranuras, locales, pila de ranuras y de cutscenes, argumentos y variables del nucleo
                ld de,SLOTS+1
                ld bc,VMV_END-SLOTS-1
                ld (hl),0
                ldir
                ld a,$FF
                ld (CUR),a
                ld (CUTIDX),a
                ld hl,$ACE1
                ld (RNDST),hl
                ld hl,host_null
                ld (HOSTVEC),hl
                ld a,WINHI
                ld (es_hi+1),a
                ld hl,13                ; resetScummVars (Indy3 EGA DOS): lo que no pone el script de arranque
                ld (VAR_VIDEOMODE),hl
                ld l,3
                ld (VAR_CURRENT_LIGHTS),hl
                ld l,4
                ld (VAR_CHARINC),hl
                ld hl,160               ; game_reset: camara en el centro, sin actores, sin clases de actor
                ld (CAMCUR),hl
                ld (CAMDEST),hl
                ld hl,ev_null
                ld (EVVEC),hl
                ld hl,OBJCLS
                ld de,OBJCLS+1
                ld bc,3*NACT-1
                ld (hl),0
                ldir
                ld hl,ACTORS            ; Actor::initActor(-1) de los NACT actores
                ld a,NACT
vi_act:         ex de,hl
                ld hl,actor_tmpl
                ld bc,ASIZE
                ldir
                ex de,hl
                dec a
                jr nz,vi_act
                ld hl,NEWNAMES          ; sin nombres nuevos
                ld de,NEWNAMES+1
                ld bc,NNAMES*5-1
                ld (hl),0
                ldir
                ld hl,USERPUT           ; fase 4b-1: cursor, cadenas, nombres de actor y verbos a 0 (y la fase 4b-2: mensajes)
                ld de,USERPUT+1
                ld bc,TXT_END-USERPUT-1
                ld (hl),0
                ldir
                ld hl,ACTNAMES
                ld de,ACTNAMES+1
                ld bc,3*NACT+NVERB*VSZ-1
                ld (hl),0
                ldir
                ld hl,16                ; main_top, main_h (vmgame3.game_reset)
                ld (MAINTOP),hl
                ld hl,144
                ld (MAINH),hl
                ld hl,txt_tmpl          ; las 4 ranuras de texto: xpos 0, ypos 0, right 319, height 0, color 15 (_new_string_slot)
                ld de,STRSL
                ld bc,11
                ldir
                ld hl,STRSL
                ld bc,33
                ldir
                ld hl,MSGBUF            ; charset_buf = b'\0', charset_pos = 0, charset_color = 15
                ld (MSGPTR),hl
                ld (MSGEND),hl
                ld (hl),0
                ld a,15
                ld (CHARCOL),a
                ret
txt_tmpl:       defw 0,0,319,0
                defb 15,0,0

vm_run_ext:     ld (TOPSP),sp
                xor a
                ld (VACNT),a
                ld (APIFL),a
                ld a,$FF
                ld (CUR),a
                jp start_slot_new

vm_run_script:  ld (TOPSP),sp
                ld a,$FF
                ld (CUR),a
                ld hl,(APIN)
                xor a
                jp run_script

; runObjectScript del arnes (fase 3): el OBCD lo da el que llama (APIP, APIA); los verbos van en ternas desde +17
vm_run_object:  ld (TOPSP),sp
                ld a,$FF
                ld (CUR),a
                ld hl,(APIN)
                ld a,h
                or l
                ret z
                call stop_object_script
                ld a,(APIP)
                or a
                ret z                   ; el objeto no tiene OBCD
                call alloc_slot
                ld (RNTMP),a
                ld a,(APIP)
                call map_page
                ld hl,(APIA)
                ld de,17
                add hl,de
vro_l:          ld a,(hl)
                or a
                ret z                   ; el verbo no esta
                ld c,a
                ld a,(APIVERB)
                cp c
                jr z,vro_f
                inc c
                jr z,vro_f              ; $FF: cualquier verbo
                inc hl
                inc hl
                inc hl
                jr vro_l
vro_f:          inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                ret z
                ld hl,(APIA)
                add hl,de
                ld (APIA),hl
                ld a,WIO_ROOM
                ld (APIW),a
                xor a
                ld (VACNT),a
                ld (APIFL),a
                ld (APIBIG),a
                ld a,(RNTMP)
                jp start_slot_at

vm_set_room:    ld (TOPSP),sp           ; la sala en uso (sus scripts locales): copia su entrada de ROOMDIR
                ld a,(APIN)
                ld (CURROOM),a
                cp 100
                jr c,vsr_ok
                xor a
vsr_ok:         ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,CURRD
                ld bc,32
                jp cold_rd

vm_abort:       ld (TOPSP),sp
                jp abort_cutscene

vm_frame:       ld (TOPSP),sp           ; un fotograma de scummLoop (modo nucleo): temporizadores, retardos y scripts
                ld a,(DELTA)
                ld e,a
                ld d,0
                ld (VAR_TIMER),de
                ld hl,(VAR_TIMER_TOTAL)
                add hl,de
                ld (VAR_TIMER_TOTAL),hl
                ld hl,VAR_TMR_1
                call vf_add
                ld hl,VAR_TMR_2
                call vf_add
                ld hl,VAR_TMR_3
                call vf_add
                ld hl,VARS+78           ; Indy3 PC: variables 39, 40 y 41
                call vf_add
                ld hl,VARS+80
                call vf_add
                ld hl,VARS+82
                call vf_add
                ld a,e
                cp 16
                jr c,vf_ok
                ld a,15
vf_ok:          push af
                call decrease_delay
                pop af
                call talk_frame         ; talk_delay -= delta y displayDialog
vf_tk:
                ld hl,(HAVEMSG)         ; update_scumm_vars: VAR_HAVE_MSG
                ld h,0
                ld (VAR_HAVE_MSG),hl
                jp run_all
; fase 4b-2, cada fotograma: A = delta (<= 15). talk_delay = max(0, talk_delay - delta) (palabra con signo) y, si hay mensaje y no
; queda espera, displayDialog en el overlay B (la salida rapida, sin mensaje, cuesta ~100 T)
talk_frame:     ld e,a
                ld d,0
                ld hl,(TALKDLY)
                ld a,h
                or l
                jr z,tf_dd
                bit 7,h
                jr nz,tf_clr
                or a
                sbc hl,de
                jr nc,tf_set
tf_clr:         ld hl,0
tf_set:         ld (TALKDLY),hl
tf_dd:          ld a,(HAVEMSG)
                or a
                ret z
                ld hl,(TALKDLY)
                ld a,h
                or l
                ret nz
                ld hl,OVB_DD
                jp call_ovb
vf_add:         ld a,(hl)
                add a,e
                ld (hl),a
                inc hl
                ld a,(hl)
                adc a,d
                ld (hl),a
                ret

; registro de un actor recien inicializado (Actor::initActor(-1), Actor_v3: vmgame3.Actor.init_actor); campos A_*
A_ROOM          equ 0
A_X             equ 1
A_Y             equ 3
A_COST          equ 5           ; palabra
A_FACING        equ 7           ; palabra
A_MOVING        equ 9
A_VIS           equ 10
A_FRAME         equ 11
A_TALKC         equ 12
A_TFACE         equ 13          ; palabra: _targetFacing
A_SND0          equ 15
A_WBOX          equ 16
A_ELEV          equ 17          ; palabra
A_WIDTH         equ 19
A_SPEEDX        equ 20
A_SPEEDY        equ 21
A_IGNB          equ 22          ; ignoreBoxes
A_INIT          equ 23          ; fotogramas init, walk, stand, talkStart, talkStop: este orden = los codigos 0x38-0x3C
A_WALK          equ 24
A_STAND         equ 25
A_TSTART        equ 26
A_TSTOP         equ 27
A_ANSPD         equ 28
A_DBOX          equ 29          ; walkdata.destbox
A_CBOX          equ 30          ; walkdata.curbox
A_WFAC          equ 31          ; walkdata.facing
A_STEPX         equ 32
A_DESTX         equ 33          ; walkdata (fase 6): dest, destdir, next, xfrac, yfrac, xadd, yadd, dxf, dyf, step_threshold, point3.x
A_DESTY         equ 35
A_DESTDIR       equ 37
A_NEXTX         equ 39
A_NEXTY         equ 41
A_XFRAC         equ 43
A_YFRAC         equ 45
A_XADD          equ 47
A_YADD          equ 49
A_DXF           equ 51
A_DYF           equ 53
A_STHR          equ 55
A_P3X           equ 57
A_LVX           equ 59          ; ultimas coordenadas validas (v3: adjustXYToBeInBox las reutiliza)
A_LVY           equ 61
A_FLAGS         equ 63          ; bit 0 needRedraw, bit 1 costumeNeedsInit, bit 2 ignoreTurns
actor_tmpl:     defb 0                  ; room
                defw 0,0,0              ; x, y, costume
                defw 180                ; facing
                defb 0,0,0,15           ; moving, visible, frame, talkColor
                defw 180                ; targetFacing
                defb 0,0                ; sound0, walkbox
                defw 0                  ; elevation
                defb 24,8,2,0           ; width, speedx, speedy, ignoreBoxes
                defb 1,2,3,4,5          ; init, walk, stand, talkStart, talkStop
                defb 0,0,0,0,1          ; animSpeed, destbox, curbox, wd facing, stepx
                defw 0,0,0,0,0,0,0,0,0,0,0,0   ; dest x/y, destdir, next x/y, xfrac, yfrac, xadd, yadd, dxf, dyf, step_threshold
                defw 32000,0,0          ; point3.x, lastValid x/y
                defb 0                  ; flags

; sucesos para el back-end: EVID = A y los operandos en EVARGS; el que los atiende es EVVEC (en el arnes de PC, un OUT ($F2),A
; y RET; NO se escribe en ningun puerto en la placa: en el ZX81 un OUT a un puerto par enciende el NMI)
ev_emit:        ld (EVID),a
                ld hl,(EVVEC)
                jp (hl)
ev_null:        ret

err_badobj:     ld a,E_BADOBJ
                jp vm_err
err_badactor:   ld a,E_BADACTOR
                jp vm_err
err_badop:      ld a,E_BADOP
                jp vm_err

; ============================================================================================ el bucle
exec_script:
es_loop:        ld a,(CUR)
                inc a
                ret z
es_go:          ld de,(SPTR)            ; aqui empieza una instruccion (el arnes mide desde aqui)
                ld a,d
                sub WINDOW/256
es_hi:          cp WINHI                ; (se reescribe: WINHI, o BIGHI en una pagina de un script grande que no es la ultima)
                jr nc,es_cross
                ld a,(de)
                inc de
                ld (OPC),a
                ld l,a
                ld h,disp_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                ld hl,es_loop
                push hl
                push bc
es_disp:        ret                     ; al manejador: DE = puntero tras el opcode; su ret vuelve a es_loop

; D5: la instruccion empieza fuera de la franja de la pagina. En un script grande se pasa a la pagina que la tiene; en los demas
; es un error (el puntero se ha salido de la ventana). Pagina k de un script grande: bytes [k * 4096, k * 4096 + 6144).
es_cross:       ld ix,(CURSLOT)
                ld a,(ix+SL_BIG)
                or a
                jp z,err_range
                call big_entry          ; HL = entrada de BIGDIR
                ld a,(ix+SL_PAGE)
                inc hl
                inc hl
                sub (hl)                ; A = k
                ld b,a
                ld hl,-WINDOW
                add hl,de               ; HL = DE - $2000 (con signo)
                ld a,b
                add a,a
                add a,a
                add a,a
                add a,a
                add a,h
                ld h,a                  ; HL = k * 4096 + (DE - $2000) = desplazamiento logico
                bit 7,h
                jp nz,err_range
                ld a,h
                rrca
                rrca
                rrca
                rrca
                and $0F                 ; k' = L >> 12
                ld b,a
                ld a,h
                and $0F
                add a,WINDOW/256
                ld d,a
                ld e,l                  ; DE = $2000 + (L & $FFF)
                ld (SPTR),de
                ld a,(ix+SL_BIG)
                call big_entry
                inc hl
                ld a,b
                cp (hl)                 ; k' < paginas
                jp nc,err_range
                inc hl
                add a,(hl)
                ld (ix+SL_PAGE),a
                ld (ix+SL_PTR),e
                ld (ix+SL_PTR+1),d
                call big_limit
                ld a,(ix+SL_PAGE)
                call map_page
                jp es_go

big_entry:      dec a                   ; A = indice + 1 -> HL = su entrada de BIGDIR
                add a,a
                add a,a
                add a,a
                ld l,a
                ld h,0
                push de
                ld de,BIGDIR
                add hl,de
                pop de
                ret

big_limit:      ld a,(ix+SL_BIG)        ; IX = ranura: el limite de es_hi para su pagina
                or a
                ld a,WINHI
                jr z,bl_set
                ld a,(ix+SL_BIG)
                call big_entry
                inc hl
                ld c,(hl)               ; paginas
                inc hl
                ld a,(ix+SL_PAGE)
                sub (hl)                ; k
                inc a
                cp c
                ld a,WINHI
                jr nc,bl_set            ; la ultima pagina
                ld a,BIGHI
bl_set:         ld (es_hi+1),a
                ret

; ejecuta UNA instruccion en DE (expression, caso 6); el manejador deja SPTR
exec_one:       ld a,(de)
                inc de
                ld (OPC),a
                ld l,a
                ld h,disp_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                push bc
                ret

; ============================================================================================ operandos
; getVar: DE -> BC = valor (u16 de variable; 0x2000: otra palabra de indice). Usa A y HL.
rd_var:         ld a,(de)
                ld l,a
                inc de
                ld a,(de)
                inc de
                or a
                jr nz,rv_x
                ld h,VARS/512
                add hl,hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                ret
rv_x:           ld h,a
                bit 5,h
                call nz,rv_index
                jp var_rd

; getVarOrDirectByte / Word: el bit 0x80, 0x40 o 0x20 del opcode en curso dice si es variable
rd_vb1:         ld a,(OPC)
                rla
                jr c,rd_var
rd_b:           ld a,(de)
                inc de
                ld c,a
                ld b,0
                ret
rd_vb2:         ld a,(OPC)
                and $40
                jr nz,rd_var
                jr rd_b
rd_vb3:         ld a,(OPC)
                and $20
                jr nz,rd_var
                jr rd_b
rd_vw1:         ld a,(OPC)
                rla
                jr c,rd_var
rd_w:           ld a,(de)
                ld c,a
                inc de
                ld a,(de)
                ld b,a
                inc de
                ret
rd_vw2:         ld a,(OPC)
                and $40
                jr nz,rd_var
                jr rd_w
rd_vw3:         ld a,(OPC)
                and $20
                jr nz,rd_var
                jr rd_w

; HL = palabra de variable con 0x2000: lee la palabra de indice (DE) y la suma; deja HL sin 0x2000 (readVar, version <= 5)
rv_index:       push hl
                ld a,(de)
                ld l,a
                inc de
                ld a,(de)
                ld h,a
                inc de
                bit 5,h
                jr z,ri_c
                res 5,h
                call var_rd
                jr ri_add
ri_c:           ld a,h
                and $0F
                ld b,a
                ld c,l
ri_add:         pop hl
                add hl,bc
                res 5,h
                ret

; getResultPos: DE -> RESV
rd_res:         ld a,(de)
                ld l,a
                inc de
                ld a,(de)
                ld h,a
                inc de
                bit 5,h
                call nz,rv_index
                ld (RESV),hl
                ret

; setResult: BC -> la variable RESV
set_res:        ld hl,(RESV)
                ; sigue en var_wr

; writeVar: HL = numero (sin 0x2000), BC = valor. Conserva DE
var_wr:         ld a,h
                or a
                jr nz,vw_x
                ld h,VARS/512
                add hl,hl
                ld (hl),c
                inc hl
                ld (hl),b
                ret
vw_x:           bit 7,h
                jr nz,vw_bit
                bit 6,h
                jp z,err_range
                call loc_addr
                ret c                   ; sin ranura en curso: no se escribe
                ld (hl),c
                inc hl
                ld (hl),b
                ret
vw_bit:         push de
                call bit_addr           ; HL = byte de la variable, A = mascara del bit
                ld e,a
                ld a,b
                or c
                ld a,e
                jr z,vwb_clr
                or (hl)
                ld (hl),a
                pop de
                ret
vwb_clr:        cpl
                and (hl)
                ld (hl),a
                pop de
                ret

; readVar: HL = numero (sin 0x2000) -> BC = valor. Conserva DE
var_rd:         ld a,h
                or a
                jr nz,vr_x
                ld h,VARS/512
                add hl,hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                ret
vr_x:           bit 7,h
                jr nz,vr_bit
                bit 6,h
                jp z,err_range          ; variable >= 256, o 0x1000
                call loc_addr
                jr c,vr_zero
                ld c,(hl)
                inc hl
                ld b,(hl)
                ret
vr_zero:        ld bc,0
                ret
vr_bit:         push de
                call bit_addr
                pop de
                and (hl)
                ld bc,0
                ret z
                inc c
                ret

; HL = 0x4000 | indice -> HL = el local de la ranura en curso; carry si no hay ranura. Error si el indice pasa de 15
loc_addr:       ld a,h
                and $0F
                jp nz,err_range
                ld a,l
                cp NLOCAL
                jp nc,err_range
                ld a,(CUR)
                inc a
                scf
                ret z
                ld a,l
                add a,a
                ld l,a
                ld h,0
                push de
                ld de,(LOCP)
                add hl,de
                pop de
                or a
                ret

; HL = 0x8000 | (v << 4) | bit -> HL = byte de VARS[v] con ese bit, A = mascara (version <= 3: el bit de una variable). Usa DE
bit_addr:       ld a,l
                and $0F
                ld d,a                  ; bit
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld l,h                  ; v = (palabra >> 4) & 0xFF
                ld h,VARS/512
                add hl,hl
                ld a,d
                cp 8
                jr c,ba_lo
                inc hl
                sub 8
ba_lo:          ld d,a
                ld a,1
                inc d
ba_l:           dec d
                ret z
                add a,a
                jr ba_l

; getWordVararg: DE -> VARARG (hasta NLOCAL valores) y VACNT. Deja OPC = $FF, como ScummVM
rd_vararg:      xor a
                ld (VACNT),a
rva_l:          ld a,(de)
                inc de
                ld (OPC),a
                inc a
                ret z
                call rd_vw1
                ld a,(VACNT)
                cp NLOCAL
                jr nc,rva_l             ; ScummVM no guarda mas de 25; el modelo y el Z80, mas de 16
                ld l,a
                inc a
                ld (VACNT),a
                ld h,0
                add hl,hl
                push de
                ld de,VARARG
                add hl,de
                pop de
                ld (hl),c
                inc hl
                ld (hl),b
                jr rva_l

; salto relativo: DE -> el s16 del desplazamiento. do_jump salta; no_jump lo salta
do_jump:        ld a,(de)
                ld l,a
                inc de
                ld a,(de)
                ld h,a
                inc de
                add hl,de
                ld (SPTR),hl
                ret
no_jump:        inc de
                inc de
                ld (SPTR),de
                ret

; comparacion con signo: HL = a, BC = b -> carry si a < b, Z si a == b
scmp:           ld a,h
                xor $80
                ld h,a
                ld a,b
                xor $80
                ld b,a
                or a
                sbc hl,bc
                ret

; ============================================================================================ errores
err_nest:       ld a,E_NEST
                jr vm_err
err_range:      ld a,E_RANGE
                jr vm_err
err_noscript:   ld a,E_NOSCRIPT
                jr vm_err
err_cutscene:   ld a,E_CUTSCENE
                jr vm_err
err_badsub:     ld a,E_BADSUB
                jr vm_err
err_noslot:     ld a,E_NOSLOT
vm_err:         ld (ERR),a              ; fatal: vuelve a quien llamo a la API
                ld a,$FF
                ld (CUR),a
                ld a,(OVLA_PG)
                call map_blk0
                ld sp,(TOPSP)
                ret

; ============================================================================================ paginas
map_page:       jp map_page_x           ; A = pagina de datos -> ventana (bloque 1); conserva HL y DE. Programa: la cache de
                                        ; dp_cache.inc; arnes (vm.asm): la pagina fisica 128 + A
map_phys:       push bc                 ; A = pagina fisica -> bloque 1
                ld (WINPG),a
                ld b,a
                ld c,MAP_PORT
                ld a,1
                out (c),a
                pop bc
                ret

map_blk0:       push bc                 ; A = pagina fisica -> bloque 0 (solo lectura); conserva HL y DE
                ld (OVLCUR),a
                ld b,a
                ld c,MAP_PORT
                xor a
                out (c),a
                pop bc
                ret

; llama a HL en el overlay B y vuelve a dejar en el bloque 0 lo que hubiera; conserva DE (y BC a la vuelta)
call_ovb:       ld a,(OVLCUR)
                push af
                ld a,OVB_PAGE
                call map_blk0
                call jp_hl
                pop af
                jp map_blk0
jp_hl:          jp (hl)

; lee BC bytes de la pagina fria TABPG (desplazamiento HL) en DE, por el bloque 0
cold_rd:        ld a,(OVLCUR)
                push af
                ld a,TABPG
                call map_blk0
                ldir
                pop af
                jp map_blk0

; ============================================================================================ ranuras
slot_addr:      ld l,a                  ; A = ranura -> HL (conserva DE)
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                push de
                ld de,SLOTS
                add hl,de
                pop de
                ret

load_slot:      ld (CUR),a              ; A = ranura: CUR, CURSLOT, LOCP, SPTR, didexec, limite y la pagina de su codigo
                push af
                call slot_addr
                ld (CURSLOT),hl
                pop af
                push hl
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,LOCALS
                add hl,de
                ld (LOCP),hl
                pop ix
                ld (ix+SL_DIDEX),1
                ld e,(ix+SL_PTR)
                ld d,(ix+SL_PTR+1)
                ld (SPTR),de
                ld a,(ix+SL_BIG)
                or a
                ld a,WINHI
                call nz,big_limit
                ld (es_hi+1),a
                ld a,(ix+SL_PAGE)
                jp map_page

update_ptr:     ld a,(CUR)              ; updateScriptPtr
                inc a
                ret z
                ld hl,(CURSLOT)
                ld de,SL_PTR
                add hl,de
                ld de,(SPTR)
                ld (hl),e
                inc hl
                ld (hl),d
                ret

break_here:     call update_ptr
                ld a,$FF
                ld (CUR),a
                ret

alloc_slot:     ld hl,SLOTS+16          ; getScriptSlot: A = la primera ranura muerta desde la 1; si no hay, E_NOSLOT
                ld b,NSLOT-1
                ld c,1
                ld de,16
as_l:           ld a,(hl)
                or a
                jr z,as_f
                add hl,de
                inc c
                djnz as_l
                jp err_noslot
as_f:           ld a,c
                ret

; crea una ranura con APIW, APIN, APIP, APIA, APIBIG, APIFL y VACNT valores de VARARG en los locales, y la ejecuta anidada
start_slot_new: call alloc_slot
start_slot_at:  push af                 ; (A = ranura)
                call slot_addr
                ld (hl),SS_RUNNING
                inc hl
                ld a,(APIW)
                ld (hl),a
                inc hl
                ld de,(APIN)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(APIP)
                ld (hl),a
                inc hl
                ld de,(APIA)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                xor a
                ld b,4
ssn_d:          ld (hl),a               ; retardo
                inc hl
                djnz ssn_d
                ld a,(APIFL)
                and $60
                ld (hl),a               ; banderas
                inc hl
                xor a
                ld (hl),a               ; freezeCount
                inc hl
                ld (hl),a               ; cutsceneOverride
                inc hl
                ld a,(APIBIG)
                ld (hl),a
                inc hl
                ld (hl),0               ; didexec
                pop af
                push af
                ld l,a                  ; los locales: los argumentos y ceros
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,LOCALS
                add hl,de
                ex de,hl                ; DE = locales
                ld a,(VACNT)
                add a,a
                jr z,ssn_z
                ld c,a
                ld b,0
                ld hl,VARARG
                ldir
ssn_z:          ld a,(VACNT)
                sub NLOCAL
                neg
                add a,a                 ; bytes que faltan
                jr z,ssn_e
                ld b,a
                xor a
ssn_zl:         ld (de),a
                inc de
                djnz ssn_zl
ssn_e:          xor a
                ld (VACNT),a
                ld (APIBIG),a
                pop af
                ; sigue en run_nested

; runScriptNested: A = ranura nueva (ya rellena)
run_nested:     ld (RNTMP),a
                call update_ptr
                ld a,(NESTN)
                cp MAXNEST
                jp nc,err_nest
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,NEST
                add hl,de
                push hl
                pop ix                  ; IX = entrada de la pila de ranuras
                ld a,(CUR)
                cp $FF
                jr nz,rn_parent
                ld (ix+0),0
                ld (ix+1),0
                ld (ix+2),$FF
                ld (ix+3),$FF
                jr rn_go
rn_parent:      ld (ix+3),a             ; ranura
                ld hl,(CURSLOT)
                inc hl
                ld a,(hl)
                ld (ix+2),a             ; donde
                inc hl
                ld a,(hl)
                ld (ix+0),a             ; numero
                inc hl
                ld a,(hl)
                ld (ix+1),a
rn_go:          ld hl,NESTN
                inc (hl)
                push ix
                ld a,(RNTMP)
                call load_slot
                call exec_script
                ld hl,NESTN
                ld a,(hl)
                or a
                jr z,rn_nodec
                dec (hl)
rn_nodec:       pop hl                  ; la entrada
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                or e
                jr z,rn_none            ; sin padre, o lo han matado
                ld b,(hl)               ; donde
                inc hl
                ld a,(hl)               ; ranura
                push af
                call slot_addr
                pop af
                push hl
                pop ix
                ld c,a
                ld a,(ix+SL_STAT)
                or a
                jr z,rn_none
                ld a,(ix+SL_WHERE)
                cp b
                jr nz,rn_none
                ld a,(ix+SL_NUM)
                cp e
                jr nz,rn_none
                ld a,(ix+SL_NUM+1)
                cp d
                jr nz,rn_none
                ld a,(ix+SL_FREEZE)
                or a
                jr nz,rn_none
                ld a,c
                jp load_slot            ; el padre sigue donde estaba
rn_none:        ld a,$FF
                ld (CUR),a
                ret

; stopScript: HL = numero. Mata las ranuras globales y locales con ese numero y las anula en la pila de ranuras
stop_script:    ld c,WIO_GLOBAL
                ld b,WIO_LOCAL
                ld a,$FF
                jr stop_any
; stopObjectScript: HL = numero de objeto (ranuras de sala, inventario o FLObject)
stop_object_script:
                ld c,WIO_ROOM
                ld b,WIO_INVENTORY
                ld a,WIO_FLOBJECT
stop_any:       ld (sa_w3+1),a          ; las tres "donde" que se matan (la tercera puede ser $FF: ninguna)
                ld a,c
                ld (sa_w1+1),a
                ld a,b
                ld (sa_w2+1),a
                ld a,h
                or l
                ret z
                ex de,hl                ; DE = numero
                ld ix,SLOTS
                ld b,NSLOT
                ld c,0
sa_l:           ld a,(ix+SL_NUM)
                cp e
                jr nz,sa_n
                ld a,(ix+SL_NUM+1)
                cp d
                jr nz,sa_n
                ld a,(ix+SL_STAT)
                or a
                jr z,sa_n
                ld a,(ix+SL_WHERE)
                call sa_where
                jr nz,sa_n
                xor a
                ld (ix+SL_STAT),a
                ld (ix+SL_NUM),a
                ld (ix+SL_NUM+1),a
                ld a,(CUR)
                cp c
                jr nz,sa_n
                ld a,$FF
                ld (CUR),a
sa_n:           push de
                ld de,16
                add ix,de
                pop de
                inc c
                djnz sa_l
                ld a,(NESTN)
                or a
                ret z
                ld b,a
                ld ix,NEST
sn_l:           ld a,(ix+0)
                cp e
                jr nz,sn_n
                ld a,(ix+1)
                cp d
                jr nz,sn_n
                ld a,(ix+2)
                call sa_where
                jr nz,sn_n
                xor a
                ld (ix+0),a
                ld (ix+1),a
                dec a
                ld (ix+2),a
                ld (ix+3),a
sn_n:           inc ix
                inc ix
                inc ix
                inc ix
                djnz sn_l
                ret
sa_where:       ; Z si A es una de las tres "donde"
sa_w1:          cp 0
                ret z
sa_w2:          cp 0
                ret z
sa_w3:          cp 0
                ret

; isScriptRunning: HL = numero -> A = 1/0 (ranura viva global o local)
is_script_running:
                ex de,hl
                ld ix,SLOTS
                ld b,NSLOT
isr_l:          ld a,(ix+SL_NUM)
                cp e
                jr nz,isr_n
                ld a,(ix+SL_NUM+1)
                cp d
                jr nz,isr_n
                ld a,(ix+SL_STAT)
                or a
                jr z,isr_n
                ld a,(ix+SL_WHERE)
                cp WIO_GLOBAL
                jr z,isr_y
                cp WIO_LOCAL
                jr z,isr_y
isr_n:          push de
                ld de,16
                add ix,de
                pop de
                djnz isr_l
                xor a
                ret
isr_y:          ld a,1
                ret

; runScript: HL = numero, A = banderas (bit 5 freezeResistant, bit 6 recursive); VACNT valores de VARARG van a los locales
run_script:     ld (APIFL),a
                ld a,h
                or l
                jr nz,rs_go
                ld (VACNT),a            ; script 0: nada (los argumentos leidos no pasan a otra ranura)
                ret
rs_go:
                ld (APIN),hl
                ld a,(APIFL)
                and $40
                call z,stop_script
                ld hl,(APIN)
                ld a,h
                or a
                jr nz,rs_local
                ld a,l
                cp NGLOBAL
                jr nc,rs_local
                ld c,l                  ; SCRDIR + 3 * n
                ld b,0
                add hl,hl
                add hl,bc
                ld bc,SCRDIR
                add hl,bc
                ld a,(hl)
                or a
                jp z,err_noscript
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc a
                jr z,rs_big
                dec a
                ld (APIP),a
                ld (APIA),de
                xor a
                ld (APIBIG),a
rs_g:           ld a,WIO_GLOBAL
                ld (APIW),a
                jp start_slot_new
rs_big:         ld a,e                  ; grande: la direccion es su indice en BIGDIR
                inc a
                ld (APIBIG),a
                call big_entry
                inc hl
                inc hl
                ld a,(hl)
                ld (APIP),a             ; primera pagina
                inc hl
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (APIA),de
                jr rs_g
rs_local:       ld a,(CURRD+9)          ; scripts locales de la sala en uso: n x (id, pagina, direccion)
                or a
                jp z,err_noscript
                ld a,h
                or a
                jp nz,err_noscript
                ld a,(CURRD+9)
                ld b,a
                ld a,(CURRD+18)
                call map_page
                ld hl,(CURRD+19)
                ld a,(APIN)
rl_l:           cp (hl)
                jr z,rl_f
                inc hl
                inc hl
                inc hl
                inc hl
                djnz rl_l
                jp err_noscript
rl_f:           inc hl
                ld a,(hl)
                ld (APIP),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (APIA),de
                xor a
                ld (APIBIG),a
                ld a,WIO_LOCAL
                ld (APIW),a
                jp start_slot_new

; stopObjectCode
stop_object_code:
                ld ix,(CURSLOT)
                ld a,(ix+SL_WHERE)
                cp WIO_GLOBAL
                jr z,soc_g
                cp WIO_LOCAL
                jr z,soc_g
                ld l,(ix+SL_NUM)
                ld h,(ix+SL_NUM+1)
                call stop_object_script
                jr soc_e
soc_g:          xor a
                ld (ix+SL_NUM),a
                ld (ix+SL_NUM+1),a
                ld (ix+SL_STAT),a
soc_e:          ld a,$FF
                ld (CUR),a
                ret

; decreaseScriptDelay: A = cuanto
decrease_delay: ld c,a
                ld ix,SLOTS
                ld b,NSLOT
                ld de,16
dd_l:           ld a,(ix+SL_STAT)
                cp SS_PAUSED
                jr nz,dd_n
                ld a,(ix+SL_DELAY)
                sub c
                ld (ix+SL_DELAY),a
                ld a,(ix+SL_DELAY+1)
                sbc a,0
                ld (ix+SL_DELAY+1),a
                ld a,(ix+SL_DELAY+2)
                sbc a,0
                ld (ix+SL_DELAY+2),a
                ld a,(ix+SL_DELAY+3)
                sbc a,0
                ld (ix+SL_DELAY+3),a
                jp p,dd_n
                ld (ix+SL_STAT),SS_RUNNING
                xor a
                ld (ix+SL_DELAY),a
                ld (ix+SL_DELAY+1),a
                ld (ix+SL_DELAY+2),a
                ld (ix+SL_DELAY+3),a
dd_n:           add ix,de
                djnz dd_l
                ret

; runAllScripts (version >= 3: didexec)
run_all:        ld hl,SLOTS+SL_DIDEX
                ld de,16
                ld b,NSLOT
                xor a
ra_c:           ld (hl),a
                add hl,de
                djnz ra_c
                ld a,$FF
                ld (CUR),a
                xor a
                ld (RAI),a
ra_l:           call slot_addr
                ld a,(hl)
                cp SS_RUNNING
                jr nz,ra_n
                ld de,SL_DIDEX
                add hl,de
                ld a,(hl)
                or a
                jr nz,ra_n
                ld a,(RAI)
                call load_slot
                call exec_script
ra_n:           ld hl,RAI
                inc (hl)
                ld a,(hl)
                cp NSLOT
                jr c,ra_l
                ret

; freezeScripts: BC = bandera (no 0)
freeze_scripts: ld a,b                  ; flag >= 0x80 con signo: congela tambien las resistentes
                or a
                jr nz,fz_neg
                ld a,c
                and $80
                jr fz_go
fz_neg:         rla
                ccf
                sbc a,a                 ; B < $80 (positivo y >= 256) -> $FF; negativo -> 0
fz_go:          ld (fz_all+1),a
                ld ix,SLOTS
                ld b,NSLOT
                ld c,0
fz_l:           ld a,(CUR)
                cp c
                jr z,fz_n
                ld a,(ix+SL_STAT)
                or a
                jr z,fz_n
                ld a,(ix+SL_FLAGS)
                and $20
                jr z,fz_y
fz_all:         ld a,0
                or a
                jr z,fz_n
fz_y:           set 7,(ix+SL_STAT)
                inc (ix+SL_FREEZE)
fz_n:           ld de,16
                add ix,de
                inc c
                djnz fz_l
                ld a,(CUTIDX)           ; (la cola de frases la congela la fase 5)
                cp $FF
                ret z
                call slot_addr
                res 7,(hl)
                ld de,SL_FREEZE
                add hl,de
                ld (hl),0
                ret

unfreeze_scripts:
                ld ix,SLOTS
                ld b,NSLOT
                ld de,16
uf_l:           bit 7,(ix+SL_STAT)
                jr z,uf_n
                dec (ix+SL_FREEZE)
                jr nz,uf_n
                res 7,(ix+SL_STAT)
uf_n:           add ix,de
                djnz uf_l
                ret

; abortCutscene
abort_cutscene: ld a,(CUTSP)
                ld e,a
                ld d,0
                ld hl,CUTPTR
                add hl,de
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld a,b
                or c
                ret z
                xor a
                ld (hl),a
                dec hl
                ld (hl),a               ; cut_ptr = 0 (se hace aqui; nada lo lee antes)
                ld hl,CUTPG
                add hl,de
                ld a,(hl)
                push af
                ld hl,CUTSCR
                add hl,de
                ld a,(hl)
                call slot_addr
                push hl
                pop ix
                pop af
                ld (ix+SL_PAGE),a
                ld (ix+SL_PTR),c
                ld (ix+SL_PTR+1),b
                ld (ix+SL_STAT),SS_RUNNING
                ld (ix+SL_FREEZE),0
                ld a,(ix+SL_CUTOV)
                or a
                jr z,ac_v
                dec (ix+SL_CUTOV)
ac_v:           ld hl,1
                ld (VAR_OVERRIDE),hl
                ret

; ============================================================================================ decodificador generico
; decode: DE = puntero tras el opcode; la especificacion de OPC (spec_lo/spec_hi) -> ARGS (ARGN palabras), RESV (R de arriba),
; JTGT (J); DE queda tras los operandos. Las fichas: V3/TOOLS/gen_vmtables3.py y scumm3dis.py (SPEC)
decode:         ld a,(OPC)
                ld (TOPOP),a
                ld l,a
                ld h,spec_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                ld hl,ARGS
                ld (ARGP),hl
                ld (DS_SP),sp
                ld h,b
                ld l,c
                call ds_run
ds_done:        ld a,(ARGP)
                sub ARGS AND 255
                rrca
                ld (ARGN),a
                ld a,(TOPOP)
                ld (OPC),a
                ret
ds_stop:        ld sp,(DS_SP)           ; X, o Q con $FE: la instruccion acaba
                jr ds_done

ds_run:         ld a,(hl)               ; HL = fichas
                inc hl
                or a
                ret z
                cp 20
                jr nc,ds_struct
                push hl
                add a,a
                ld l,a
                ld h,0
                ld bc,ds_jt-2
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                call jp_hl
                pop hl
                jr ds_run
ds_jt:          defw dt_R,dt_v,dt_B1,dt_B2,dt_B3,dt_W1,dt_W2,dt_W3,dt_b,dt_w,dt_J,dt_L,dt_S,dt_O,dt_o,dt_Q,ds_stop,dt_Z,dt_N

ds_struct:      cp 21
                jr z,ds_loop
                ld c,(hl)               ; SW: mascara, tabla
                inc hl
                push hl
                inc hl
                inc hl
                ex (sp),hl              ; (SP) = sigue; HL = tabla
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld a,(de)
                inc de
                ld (OPC),a
                and c
                call ds_sub
                pop hl
                jr ds_run
ds_loop:        push hl                 ; LOOP: fin, mascara, conversion, tabla
                ld a,(hl)
                ld (dl_end+1),a
dl_next:        pop hl
                push hl
                ld a,(de)
                inc de
dl_end:         cp 0
                jr z,dl_done
                ld (OPC),a
                inc hl
                ld c,(hl)               ; mascara
                inc hl
                ld b,(hl)               ; conversion
                inc hl
                push hl
                ld a,b
                or a
                ld a,(OPC)
                call nz,dl_conv
                and c
                pop hl
                push af
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                pop af
                call ds_sub
                pop hl                  ; (la sub-lista pudo cambiar dl_end: se vuelve a poner)
                push hl
                ld a,(hl)
                ld (dl_end+1),a
                jr dl_next
dl_done:        pop hl
                ld bc,5
                add hl,bc
                jp ds_run
dl_conv:        and $1F                 ; actorOps: convertTable de GF_SMALL_HEADER (A = opcode -> A = OPC traducido)
                jp z,err_badsub
                cp 21
                jp nc,err_badsub
                push hl
                push bc
                ld l,a
                ld h,0
                ld bc,act_conv-1
                add hl,bc
                ld a,(OPC)
                and $E0
                or (hl)
                ld (OPC),a
                pop bc
                pop hl
                ret
act_conv:       defb 1,0,0,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,20

; A = k, HL = tabla (n, n x defw, por omision) -> emite k y ejecuta su sub-lista
ds_sub:         push hl
                ld c,a
                ld b,0
                call emit               ; (conserva BC)
                pop hl
                ld a,c
                cp (hl)
                jr c,dsb_in
                ld a,(hl)               ; k >= n: la de por omision (va tras las n entradas)
dsb_in:         inc hl
                ld c,a
                ld b,0
                add hl,bc
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                or h
                jp z,err_badsub
                jp ds_run

emit:           ld hl,(ARGP)            ; BC -> ARGS
                ld a,l
                cp ARGS_END AND 255
                jp z,err_range
                ld (hl),c
                inc hl
                ld (hl),b
                inc hl
                ld (ARGP),hl
                ret

dt_R:           call rd_res
                ld bc,(RESV)
                jr emit
dt_v:           call rd_var
                jr emit
dt_B1:          call rd_vb1
                jr emit
dt_B2:          call rd_vb2
                jr emit
dt_B3:          call rd_vb3
                jr emit
dt_W1:          call rd_vw1
                jr emit
dt_W2:          call rd_vw2
                jr emit
dt_W3:          call rd_vw3
                jr emit
dt_b:           call rd_b
                jr emit
dt_w:           call rd_w
                jr emit
dt_J:           call rd_w
                ld h,d
                ld l,e
                add hl,bc
                ld (JTGT),hl
                ret
dt_L:           ld a,(de)
                inc de
                ld (OPC),a
                inc a
                ret z
                call rd_vw1
                call emit
                jr dt_L
dt_S:           call scan_str
                jr emit
dt_o:           ld a,(de)
                inc de
                ld (OPC),a
                ld c,a
                ld b,0
                jr emit
dt_O:           ld a,(de)
                inc de
                ld (OPC),a
                ret
dt_Q:           ld hl,(ARGP)            ; el ultimo valor es $FE: acaba
                dec hl
                ld a,(hl)
                dec hl
                or a
                ret nz
                ld a,(hl)
                cp $FE
                ret nz
                jp ds_stop
dt_Z:           ld a,(de)
                inc de
                or a
                ret z
                ld c,a
                ld b,0
                call emit
                jr dt_Z
dt_N:           call rd_b               ; setVarRange: n y n valores
                push bc
                call emit
                pop bc
                ld b,c
                inc b
dtn_l:          dec b
                ret z
                push bc
                ld a,(TOPOP)
                rla
                jr c,dtn_w
                call rd_b
                jr dtn_e
dtn_w:          call rd_w
dtn_e:          call emit
                pop bc
                jr dtn_l

; cadena (resStrLen): DE -> BC = str_value de sus bytes en bruto sin el 0 (suma + 257 * longitud)
scan_str:       ld hl,0
ss_l:           ld a,(de)
                inc de
                or a
                jr z,ss_e
                call ss_acc
                inc a
                jr nz,ss_l              ; no era $FF
                ld a,(de)               ; $FF + codigo; salvo 1, 2, 3 y 8, dos bytes mas
                inc de
                call ss_acc
                or a
                jr z,ss_two
                cp 4
                jr c,ss_l
                cp 8
                jr z,ss_l
ss_two:         ld a,(de)
                inc de
                call ss_acc
                ld a,(de)
                inc de
                call ss_acc
                jr ss_l
ss_e:           ld b,h
                ld c,l
                ret
ss_acc:         push bc                 ; HL += A + 257 (conserva A)
                ld c,a
                ld b,1
                add hl,bc
                inc hl
                pop bc
                ret

; ============================================================================================ anfitrion
h_host:         call decode
                ld (SPTR),de
host_call:      ld a,(TOPOP)
                ld hl,(HOSTVEC)
                jp (hl)
host_null:      ret
h_host_r:       call decode
                ld (SPTR),de
                call host_call
                ld bc,(HRES)
                jp set_res
h_host_j:       call decode
                ld (SPTR),de
                call host_call
                ld a,(HFLAG)
                or a
                ret nz
                ld hl,(JTGT)
                ld (SPTR),hl
                ret

                include "arith32.asm"
                include "vm_ops.asm"
MSGBUF:         defs MSG_MAX            ; fase 4b-2: charset_buf (el mensaje convertido, con su 0 final)
