; =====================================================================
;  agivm.asm - interprete de AGI v2 para el ZX81 con SD81 Booster. Etapa 1: el nucleo de las logicas.
;
;  Hace: variables y banderas, bytecode (if / or / not / goto / call), cambio de sala, inventario, sonidos (solo su duracion),
;  reloj y el ciclo del interprete. No hace aun: objetos animados, parser, texto, pantalla.
;  Se comprueba contra el modelo de Python (TOOLS/agi_vm.py): el mismo juego tiene que dar la misma traza de pasos
;  y el mismo resumen por ciclo (ver test_vm.sh).
;
;  Las logicas se leen de la SD como LOGnnn.AGL (convertidas por TOOLS/agi2log.py). El bytecode se ejecuta desde una ventana
;  en el bloque 4 ($8000), que se paginea a una de 8 paginas (16-23): una logica por pagina; la 0 se queda fija en la ranura 0.
;
;  Memoria: $4200-  codigo   $6D00 variables  $6E00 banderas  $6F00 ranura de cada logica  $7000 inventario  $7100 teclas  $7200 controladores
;           $7300 objetos  $7700 argumentos y cadenas  $7E60 fin de los datos   $8000 pila y ventana de la logica
; =====================================================================

                include "gfx4.inc"
                include "tests.inc"            ; TESTS = 1 solo en las pruebas del arnes (test_vm.sh): traza de pasos; en produccion (0) no cuesta nada
                org 16896
                jp start
                defs 16914-$
                jp start                ; RAND USR 16914 (y el arnes de PC entran aqui)

SET_FAST        equ $02E7
SLOW_FAST       equ $0207
MAP_PORT        equ $E7
CMD_64C         equ $1C

VARS            equ $6D00
FLAGS           equ $6E00
LGSLOT          equ $6F00; logica -> ranura ($FF = no esta)
INV             equ $7000; sala de cada objeto del inventario (255 = lo lleva el ego)
SUMM            equ LWIN
SUMMAX          equ 250
TRACE           equ LWIN+$1800
TRMAX           equ 680
OBJ             equ $7300
NOBJ            equ 32
VIEWPAGE        equ PG_VIEWS
STACK           equ $8000
TCOLS           equ 42-2*GFX4           ; columnas de texto: 42 de 6 pixeles en el HiRes, 40 del plano de texto de la FPGA (160w)
TCELL           equ 32+8*GFX4           ; celdas de una linea de pantalla (8 pixeles del bitmap; columnas de texto en 160w)
TPLANE          equ HR_BM+168*80        ; 160w: los 1000 codigos del plano de texto, justo tras la imagen
TFONT           equ $D800               ; 160w: tabla de glifos de 2 KB alineada (registro I); los codigos 0-31 y 128-159 no se usan, asi que su sitio lo comparte el plano de texto
OVB_FONT        equ $2024
OVB_XPAR        equ $2027               ; 160w: draw deja transparentes las celdas de texto bajo el objeto
LWIN            equ $8000
TOKLIM          equ $AA                 ; parte baja del limite de TOKS (TOKS+90)
KEYMAP          equ $7100               ; por tecla ASCII (0-127): controlador y si esta puesto (2 bytes)
CTL             equ $7200               ; controladores activos en este ciclo
NSTR            equ 13                  ; s0-s12 (PQ1 y Larry1 usan la 12); ScummVM tiene 24 + 1
STRS            equ $7710               ; NSTR cadenas de 41 bytes ($7710-$7924)
MSGBUF          equ $7A00               ; alineado a pagina: PROW (fila de prioridad de los sprites) lo usa asi; con $7930 las mascaras del borde derecho fallaban
ROWBUF          equ MSGBUF              ; una fila de prioridad bajo el objeto (pic_check)
TMPM            equ $7B00
WTEXT           equ $7C00
STMP            equ $7930
STMP2           equ $7960
PHR             equ $7D40
WBUF            equ $7D70
TOKS            equ $7CC0
SUBBUF          equ TOKS                ; mensaje anidado (%m) en stringPrintf: 256 bytes, $7CC0-$7DBF (TOKS, PHR y WBUF son del parser y no coinciden en el tiempo)
BSFRN           equ 6                   ; fuentes de texto anidadas (%s, %m)
TOKP            equ $7D20
INW             equ $7990
KEYQ            equ $79B0
TQ              equ $7DC0
EVBUF           equ $7E70
SREC            equ $79C0
TRREC           equ $79D0
OBJP            equ $7EC0               ; x, y previos de cada objeto (xPos_prev, yPos_prev de ScummVM), 2 bytes por objeto
CLR_END         equ $7F00
PG_VIEWS        equ 24
PG_WORDS        equ 25
PG_SND          equ 26
PG_EVT          equ 27
PG_DBG          equ 28
PG_PRI          equ 29
PG_OVL          equ 41
PG_OVC          equ 44
PG_INV          equ 45
PG_OVD          equ 46
PG_OVE          equ 48                  ; overlay A2 (rotulos por software), con call_e
OVE_BGSAVE      equ $2000
OVE_RUN         equ $2003
OVE_BAKE        equ $2006
PG_SAV          equ 47                  ; las ranuras de guardar/cargar (datos), en la ventana
SAV_EX          equ $8000               ; 12 bytes: la ranura existe
SAV_DESC        equ $8010               ; 12 descripciones de 32 bytes
SAV_NEW         equ $8190               ; la descripcion que se guarda / la cabecera que se lee
OVL_KPOLL       equ $2000               ; overlay A (teclado, sprites, rotulos): siempre en el bloque 1
OVL_KDELIV      equ $2003
OVL_ACCEPT      equ $2006
OVL_PREVENT     equ $2009
OVL_DRAW        equ $200C
OVL_SPRINIT     equ $200F
OVL_SORT        equ $2012
OVL_FORCE       equ $2015
OVL_ADDPIC      equ $2018
OVL_SPCLR       equ $201B
OVL_ADDHDR      equ $201E
OVL_PDEDUP      equ $2021
; add.to.pic: los datos viven en la pagina del A1 (bloque 1) tras sus cabeceras de prioridad (SPH); los pares de rangos (SPP), en la del A2
SP_MAX          equ 48                  ; cabeceras de rangos de prioridad
SP_ROWS         equ 2048                ; filas de rangos (2 bytes cada una: 4 KB, toda la pagina del A2 desde SPP)
ST_MAX          equ 48                  ; add.to.pic que se recuerdan desde draw.pic
MG_MAX          equ 12                  ; cajas de linea de control (en el nucleo: can_be_here las mira con otro overlay en el bloque 1)
SPP             equ $3000
ST_FIX          equ $2040+1+NOBJ+NOBJ+1+8*SP_MAX
st_n            equ ST_FIX              ; st_n y STL se guardan juntos (ST_LEN bytes)
STL             equ st_n+1              ; vista, bucle, celda, x, y, prioridad de cada add.to.pic
SCR             equ STL+6*ST_MAX        ; objeto de trabajo de add.to.pic (32 bytes) y la pagina de su bucle
SCR_PG          equ SCR+32
ST_LEN          equ SCR-ST_FIX
OVB_DISPLAY     equ $2000               ; overlay B (texto): se mapea con call_b
OVB_DISPLAY_V   equ $2003
OVB_CLEAR       equ $2006
OVB_STATUS      equ $2009
OVB_SON         equ $200C
OVB_SOFF        equ $200F
OVB_ATTR        equ $2012
OVB_PROMPT      equ $2015
OVB_PRINT       equ $2018
OVB_BOXCLOSE    equ $201B
OVB_GSDRAW      equ $201E
OVB_CLRRECT     equ $2021
OVF_SETMENU      equ $2000
OVF_SETITEM      equ $2003
OVF_ENABLE       equ $2006
OVF_DISABLE      equ $2009
OVF_MENUOPEN     equ $200C
OVF_MENUNAV      equ $200F
OVF_MENUSEL      equ $2012
OVF_MENUCLOSE    equ $2015
OVF_DLGLIST      equ $2018
OVF_MENUON       equ $201B
OVF_DLGDONE      equ $201E
OVF_MENURESET    equ $2021
OVF_DLGINV       equ $2024
PG_OVF          equ 49                  ; overlay F (menus y listas de guardar/cargar/inventario), con call_f
OVC_ECHO        equ $2009
OVC_CANCEL      equ $200C
OVC_CURSOR      equ $200F
OVC_OBJPIC      equ $2012
OVC_DIST        equ $2018
OVC_ANIM        equ $201B
OVC_GETNUM      equ $201E
OVC_PARSE       equ $2021
OVC_DRAW        equ $2024
OVC_FIXPOS      equ $2027
OVC_FOLLOW      equ $202A
OVC_CYCEL       equ $202D
OVC_PRE         equ $2030
OVC_CYCLES      equ $2033
OVC_CLIP        equ $2036
OVC_CMPSTR      equ $2039
OVC_NEWROOM     equ $203C
OVC_MVOD        equ $203F
OVC_GAMEID      equ $2042
OVC_PARSETEXT   equ $2045
OVC_SAID        equ $2048
OVC_SHOW        equ $204B
OVC_TEXTSCR     equ $2015
OVD_READ        equ $2000               ; overlay D (ficheros de guardar/cargar): con call_d
OVD_PREP        equ $2003
OVD_CONF        equ $2006
OVD_DO          equ $2009
OVD_SUM         equ $200C               ; solo con TESTS
OVC_RESTART     equ $2000               ; overlay C (restart.game, status, show.obj): tambien con call_c
OVC_GFXFIX      equ $2003
OVC_OBJDESC     equ $2006
MAXW            equ 6
LPAGE0          equ 16
NSLOTS          equ 8
MAXDEPTH        equ 12
ARGS            equ $7700; argumentos del comando o la condicion en curso

                include "mcu.asm"

start:          di
                ld (sv_sp),sp
                ld hl,(sv_sp)           ; la direccion de retorno a BASIC: la imagen puede pisarla en el arnes de PC (pila en $CFF8)
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (sv_ret),de
                ld sp,STACK
                ld a,i
                ld (sv_i),a
                call SET_FAST
                ld a,CMD_FULLPAGING
                call mcu_send
                ld b,6                  ; bloques 6 y 7 a sus paginas ($C000 son los atributos de video)
                ld a,6
                call sc_map
                ld b,7
                ld a,7
                call sc_map
                IF GFX4
                xor a
                ld (2069),a             ; sin plano de texto hasta que esten los glifos (ov_load); video_init vuelve a llamarse desde el reinicio y no lo toca
                ENDIF
                call video_init
                call init
                call ov_load
                ld a,(stopf)
                or a
                jp nz,finish
                ld hl,OVC_RESTART       ; el estado inicial es el del reinicio
                call call_c

; ---------------------------------------------------------------------
;  El ciclo del interprete
; ---------------------------------------------------------------------
main_loop:      in a,(ClkPort)          ; las tramas se cuentan desde aqui (ver pace)
                ld hl,hk_seen
                ld (hl),0
                call clr_ctl
                call OVL_KDELIV
                call kb_prompt
                call do_events
                ld a,(pctl)
                or a
                jr z,ml_np
                ld a,(dirhold)
                ld (VARS+6),a           ; v6 = direccion que pide el jugador
ml_np:          call snd_due
                xor a
                ld (exitall),a
                ld hl,OVC_PRE           ; interpretCycle: la direccion del ego, y la de cada objeto segun su movimiento (checkAllMotions)
                call call_c
ml_run:         xor a
                call run_logic          ; la logica 0
                ld a,(stopf)
                or a
                jp nz,finish
                ld a,(nr_pend)
                or a
                jr z,ml_nr
                call do_new_room
                call clr_ctl            ; resetControllers tras cada pasada de la logica 0
                jr ml_run
ml_nr:          ld a,(rs_rerun)         ; restore.game: exitAllLogics y el bucle de interpretCycle repite la logica 0
                or a
                jr z,ml_end
                xor a
                ld (rs_rerun),a
                ld (exitall),a
                ld (FLAGS+2),a
                ld (VARS+4),a
                ld (VARS+5),a
                ld (VARS+9),a
                call clr_ctl
                jr ml_run
ml_end:         ld a,(VARS+6)           ; despues de la logica la direccion del ego es v6
                ld (OBJ+O_DIR),a
                xor a                   ; los codigos de borde se ponen a 0 antes de mover los objetos (el movimiento los pone y la logica del ciclo siguiente los ve); el del ego, solo
                ld (VARS+4),a           ; si hay algun objeto que actualizar (t_cycles)
                ld (VARS+5),a
                call update_objects
                ld hl,OVB_STATUS
                call call_b
                call pace
                call render
                xor a
                ld (inwvalid),a         ; la orden se acaba con el ciclo
                ld (keyn),a
                ld (FLAGS+2),a
                ld (FLAGS+4),a
                ld (FLAGS+12),a         ; RESTORE_JUST_RAN
                ld (VARS+9),a           ; la palabra desconocida y la tecla valen un solo ciclo (playGame)
                ld (VARS+19),a
                ld a,(rs_keep)          ; tras restart.game / restore.game las banderas 5 y 6 las ve la logica 0 del ciclo siguiente
                or a
                jr nz,ml_k6
                ld (FLAGS+5),a
                ld (FLAGS+6),a
                jr ml_k7
ml_k6:          xor a
                ld (rs_keep),a
ml_k7:          call tick_clock
                ld hl,(ncyc)
                ld a,h
                or l
                jr nz,ml_dbg
                ld hl,(cyc)             ; ncyc = 0: modo real, sin resumenes ni limite de ciclos
                inc hl
                ld (cyc),hl
                jp main_loop
ml_dbg:         ld hl,OVD_SUM           ; el resumen de las pruebas (overlay D)
                call call_d
                ld hl,(cyc)
                inc hl
                ld (cyc),hl
                ld a,(nsum)
                cp SUMMAX
                jp nc,finish
                ld de,(ncyc)
                ex de,hl
                or a
                sbc hl,de               ; ncyc - ciclo
                jp nc,main_loop

finish:         ld a,(errc)
                cp 14                   ; 14 = no se pudo cargar el overlay
                jr z,fn_ns
                ld hl,(ncyc)            ; en las pruebas (ncyc > 0) los sprites se quedan para compararlos
                ld a,h
                or l
                jr nz,fn_ns
                call OVL_SPRINIT        ; apaga los sprites al volver a BASIC
                IF GFX4
                xor a
                ld (2069),a             ; y el plano de texto
                ENDIF
                ld a,85                 ; y el doble buffer
                ld (2057),a
fn_ns:
                ld a,PG_DBG             ; deja a la vista el resumen y la traza
                call map_page
                ld bc,$7FEF
                ld a,$0C
                out (c),a
                ld a,CMD_64C
                call mcu_send
                ld a,(sv_i)
                ld i,a
                call SLOW_FAST
                ld sp,(sv_sp)
                ld hl,(sv_sp)
                ld de,(sv_ret)
                ld (hl),e
                inc hl
                ld (hl),d
                ld bc,0
                ret

; HiRes nativo: bitmap en $A000, atributos de Chroma (modo 0) en $C000, ambos a cero
video_init:     ld a,85
                ld (2058),a             ; WRX apagado
                xor a
                ld (2043),a
                ld a,HR_BM>>8
                ld (2044),a             ; HFILE = bitmap
                IF GFX4
                ld a,1
                ld (2070),a             ; ventana de imagen: filas de texto 1-21 (lineas 8-175)
                ld a,22
                ld (2071),a
                ld a,85
                ld (2057),a             ; sin doble buffer (el de una ejecucion anterior de HiRes)
                ld a,176
                ld (2045),a             ; 160x200 a 4 bpp
                ld a,$0F
                ld (2068),a             ; texto: papel 0, tinta 15 (el inverso, con el bit 7 del codigo, es negro sobre blanco)
                ld hl,HR_BM
                ld de,HR_BM+1
                ld bc,PLANE4+1000-1     ; la imagen y el plano de texto
                ld (hl),0
                ldir
                ELSE
                ld a,171
                ld (2045),a             ; Superfast HiRes nativo
                ld hl,HR_BM
                ld de,HR_BM+1
                ld bc,$1FFF
                ld (hl),0
                ldir
                ld hl,HR_ATT
                ld de,HR_ATT+1
                ld bc,$1FFF
                ld (hl),0
                ldir
                ENDIF
                ld bc,$7FEF
                ld a,$20                ; Chroma, modo 0
                out (c),a
                ld a,255
                ld (2091),a
                ld (2092),a
                ld (2093),a
                xor a
                ld (2090),a
                ret

sc_map:         ld c,MAP_PORT
                out (c),a
                ret

; ---------------------------------------------------------------------
;  Arranque: tablas y ficheros auxiliares
; ---------------------------------------------------------------------
init:           ld hl,1                 ; el estado de las variables, objetos... lo pone el overlay C (restart) tras cargar los overlays
                ld (cyc),hl
                ld hl,TRACE
                ld (trptr),hl
                ld hl,SUMM
                ld (sptr),hl
                ld a,PG_VIEWS
                ld hl,nm_views
                ld bc,8192
                call load_page
                ld a,PG_WORDS
                ld hl,nm_words
                ld bc,8192
                call load_page
                ld a,PG_SND
                ld hl,nm_snd
                ld bc,512
                call load_page
                ld a,PG_INV
                ld hl,nm_invn
                ld bc,8192
                call load_page
                ld a,PG_EVT
                ld hl,nm_evt
                ld bc,8192
                call load_page
                ld a,PG_EVT
                call map_page
                ld hl,(LWIN)            ; ciclos que se ejecutan
                ld (ncyc),hl
                jp unmap_win

; A = pagina, HL = nombre, BC = bytes -> los lee a la ventana del bloque 4 (pagina A)
load_page:      push hl
                push bc
                call map_page
                pop bc
                pop hl
                ld de,LWIN
                jp load_aux

; HL = nombre, DE = destino, BC = bytes
load_aux:       push de
                push bc
                call f_open
                cp $FF
                jr nz,la_ok
                pop bc
                pop de
                ld a,1
                jp fatal
la_ok:          ld (fh),a
                pop bc
                pop hl
                ld a,(fh)
                call f_read_n
                ld a,(fh)
                jp f_close

fatal:          ld (errc),a
                ld a,1
                ld (stopf),a
                ret

; ---------------------------------------------------------------------
;  Logicas: carga en la ventana y ejecucion
; ---------------------------------------------------------------------
; A = numero de logica. Ejecuta hasta su `return`, el final del codigo o exit_all.
run_logic:      ld c,a
                ld a,(ldepth)
                cp MAXDEPTH
                jr c,rl_ok
                ld a,2
                jp fatal
rl_ok:          ld e,a                  ; empuja el marco: logica, ranura, ip, fin
                ld d,0
                ld l,e
                ld h,d
                add hl,hl
                add hl,de
                add hl,hl               ; *6
                ld de,LSTK
                add hl,de
                ld a,(curlg)
                ld (hl),a
                inc hl
                ld a,(curslot)
                ld (hl),a
                inc hl
                ld de,(ip)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld de,(lend)
                ld (hl),e
                inc hl
                ld (hl),d
                ld hl,ldepth
                inc (hl)
                ld a,c
                call load_logic
                ld a,(stopf)
                or a
                jr nz,rl_pop
                call rl_next
rl_pop:         ld hl,ldepth
                dec (hl)
                ld a,(hl)               ; recupera el marco
                ld e,a
                ld d,0
                ld l,e
                ld h,d
                add hl,hl
                add hl,de
                add hl,hl
                ld de,LSTK
                add hl,de
                ld a,(hl)
                ld (curlg),a
                inc hl
                ld a,(hl)
                ld (curslot),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld (ip),de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (lend),de
                ld a,(curslot)
                cp $FF
                ret z
                jp map_slot

; ventana del bloque 4 -> pagina de la ranura (curslot)
map_slot:       ld a,(curslot)
                add a,LPAGE0
                ld b,a
                ld c,MAP_PORT
                ld a,4
                out (c),a
                ret

; A = logica: la deja en una ranura, mapeada, con ip = LWIN y lend = su final
load_logic:     ld (curlg),a
                ld l,a
                ld h,LGSLOT>>8
                ld a,(hl)
                cp $FF
                jp nz,ll_have
                ld a,(curlg)
                or a
                jr nz,ll_pick
                xor a                   ; la logica 0, siempre en la ranura 0
                jr ll_slot
ll_pick:        ld b,NSLOTS             ; ranura victima: la siguiente en turno que no este en uso
ll_try:         ld a,(vict)
                inc a
                cp NSLOTS
                jr c,ll_v1
                ld a,1
ll_v1:          ld (vict),a
                push bc
                call slot_busy
                pop bc
                jr nz,ll_slot
                djnz ll_try
                ld a,3
                jp fatal
ll_slot:        ld (curslot),a
                ld e,a                  ; si la ranura tenia otra logica, ya no esta
                ld d,0
                ld hl,slot_lg
                add hl,de
                ld a,(hl)
                cp $FF
                jr z,ll_free
                ld e,a
                ld d,LGSLOT>>8
                ld a,$FF
                ld (de),a
ll_free:        ld a,(curslot)          ; logica nueva en la ranura: su sIP al principio
                add a,a
                ld e,a
                ld d,0
                ld hl,slot_sip
                add hl,de
                xor a
                ld (hl),a
                inc hl
                ld (hl),a
                ld a,(curslot)
                ld e,a
                ld d,0
                ld hl,slot_lg
                add hl,de
                ld a,(curlg)
                ld (hl),a
                ld l,a
                ld h,LGSLOT>>8
                ld a,(curslot)
                ld (hl),a
                call map_slot
                call mk_name
                ld hl,nm
                call f_open
                cp $FF
                jr nz,ll_open
                ld a,4
                jp fatal
ll_open:        ld (fh),a
                ld hl,lhdr
                ld bc,2
                call f_read_n
                ld bc,(lhdr)
                ld hl,$2000-2
                or a
                sbc hl,bc
                jr nc,ll_size
                ld a,5
                call fatal
                ld bc,0
ll_size:        ld (lsize),bc
                ld a,(fh)
                ld hl,LWIN
                call f_read_n
                ld a,(fh)
                call f_close
                ld a,1
                ld (lloaded),a
                jr ll_ends
ll_have:        ld (curslot),a
                call map_slot
ll_ends:        ld a,(curslot)
                add a,a
                ld e,a
                ld d,0
                ld hl,slot_sz
                add hl,de
                ld a,(lloaded)
                or a
                jr z,ll_get
                ld de,(lsize)           ; recien leida: guarda su tamano en la ranura
                ld (hl),e
                inc hl
                ld (hl),d
                xor a
                ld (lloaded),a
                jr ll_set
ll_get:         ld e,(hl)
                inc hl
                ld d,(hl)
ll_set:         ld hl,LWIN
                add hl,de
                ld (lend),hl
                ld a,(curslot)          ; empieza donde dijo set.scan.start (0 si no)
                add a,a
                ld e,a
                ld d,0
                ld hl,slot_sip
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,LWIN
                add hl,de
                ld (ip),hl
                ret
; set.scan.start / reset.scan.start: el sIP de la logica en curso (offset en su codigo)
h_set_scan_start: ld hl,(ip)
                ld de,LWIN
                or a
                sbc hl,de
                ex de,hl
                jr ss_st
h_reset_scan_start: ld de,0
ss_st:          ld a,(curslot)
                add a,a
                ld c,a
                ld b,0
                ld hl,slot_sip
                add hl,bc
                ld (hl),e
                inc hl
                ld (hl),d
                ret

; Z si la ranura A la usa algun marco de la pila (o la logica en curso). Conserva A.
slot_busy:      ld c,a
                ld a,(ldepth)
                ld b,a
                ld hl,LSTK+1
                ld de,6
sb_l:           ld a,b
                or a
                jr z,sb_no
                ld a,(hl)
                cp c
                jr z,sb_yes
                add hl,de
                dec b
                jr sb_l
sb_no:          ld a,c
                or a                    ; NZ (la ranura es >= 1)
                ret
sb_yes:         ld a,c
                cp c                    ; Z
                ret

; "LOGnnn.AGL" para la logica (curlg)
mk_name:        ld a,(curlg)
                ld b,'0'-1
mn_h:           inc b
                sub 100
                jr nc,mn_h
                add a,100
                ld hl,nm+7
                ld (hl),b
                ld b,'0'-1
mn_t:           inc b
                sub 10
                jr nc,mn_t
                add a,10+'0'
                inc hl
                ld (hl),b
                inc hl
                ld (hl),a
                ret

; ---------------------------------------------------------------------
;  El bucle del bytecode
; ---------------------------------------------------------------------
; rl_next: tras un comando (puede haber cambiado exitall/stopf/ip). rl_go: DE = ip, tras un if o un goto (no cambian nada de eso)
rl_next:        ld a,(exitall)
                or a
                ret nz
                ld a,(stopf)
                or a
                ret nz
                ld de,(ip)
rl_go:          ld a,(lend+1)           ; casi siempre basta la parte alta
                cp d
                jr c,rl_end
                jr nz,rl_in
                ld hl,(lend)
                or a
                sbc hl,de
                jr z,rl_end
                jr c,rl_end
rl_in:
                IF TESTS
                call trace_step
                ENDIF
                ld a,(de)
                inc de
                cp $FF
                jp z,do_if
                cp $FE
                jr z,do_goto
                cp NCMDS
                jr c,rl_cmd
                ld a,6
                jp fatal
rl_end:         ld (ip),de
                ret
rl_cmd:         ld c,a                  ; empuja rl_next y el manejador (el ret lo ejecuta), copia los argumentos a ARGS
                ld b,0
                ld hl,argtab
                add hl,bc
                ld a,(hl)
                ld hl,cmdtab
                add hl,bc
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld hl,rl_next
                push hl
                push bc
                ex de,hl
                or a
                jr z,rl_na
                ld c,a
                ld b,0
                ld de,ARGS
                ldir
rl_na:          ld (ip),hl
                ret

do_goto:        ex de,hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                add hl,de
                ex de,hl
                jr rl_go

; DE apunta a las condiciones. B = 1 dentro de un OR, C = 1 si la condicion siguiente va negada
; (el estado vive en registros; equaln/equalv/lessn/lessv/greatern/greaterv/isset/issetv/has van en linea, sin pasar por ARGS)
do_if:          ld bc,0
di_l:           ld a,(de)
                inc de
                cp 12
                jp nc,di_big
                add a,a
                add a,di_ft AND 255
                ld l,a
                ld h,di_ft SHR 8
                ld a,(hl)
                inc l
                ld h,(hl)
                ld l,a
                jp (hl)

                IF ($ AND 255) > 232    ; la tabla no cruza pagina (di_l solo suma la parte baja)
                defs 256-($ AND 255)
                ENDIF
di_ft:          defw di_bad,df_equaln,df_equalv,df_lessn,df_lessv,df_greatern,df_greaterv,df_isset,df_issetv,df_has,df_oir,df_posn

df_oir:         ld a,10                 ; obj.in.room va por el camino general
                jp ds_nosd
; posn en linea (testPosn de ScummVM solo mira x e y): HL = el objeto
df_posn:        ld a,(de)
                inc de
                cp NOBJ
                jp nc,go_bad
                rrca
                rrca
                rrca
                ld l,a
                and $1F
                add a,OBJ SHR 8
                ld h,a
                ld a,l
                and $E0
                add a,O_X
                ld l,a
                push bc
                ld a,(de)
                ld b,a                  ; x1
                inc de
                ld a,(de)
                ld c,a                  ; y1
                inc de
                ld a,(hl)
                cp b
                jr c,dp_f2
                inc hl
                ld a,(hl)
                cp c
                jr c,dp_f2
                dec hl
                ld a,(de)               ; x2
                inc de
                cp (hl)
                jr c,dp_f1
                inc hl
                ld a,(de)               ; y2
                inc de
                cp (hl)
                jr c,dp_f0
                pop bc
                jp di_T
dp_f2:          inc de
dp_f1:          inc de
dp_f0:          pop bc
                jp di_F

df_equaln:      ld a,(de)
                ld l,a
                ld h,VARS>>8
                inc de
                ld a,(de)
                inc de
                cp (hl)
                jp z,di_T
                jp di_F
df_lessn:       ld a,(de)
                ld l,a
                ld h,VARS>>8
                inc de
                ld a,(de)
                inc de
                cp (hl)
                jp z,di_F
                jp c,di_F
                jp di_T
df_greatern:    ld a,(de)
                ld l,a
                ld h,VARS>>8
                inc de
                ld a,(de)
                inc de
                cp (hl)
                jp c,di_T
                jp di_F
df_isset:       ld a,(de)
                inc de
                ld l,a
                ld h,FLAGS>>8
                ld a,(hl)
                or a
                jp nz,di_T
                jp di_F
df_issetv:      ld a,(de)
                inc de
                ld l,a
                ld h,VARS>>8
                ld l,(hl)
                ld h,FLAGS>>8
                ld a,(hl)
                or a
                jp nz,di_T
                jp di_F
df_has:         ld a,(de)
                inc de
                ld l,a
                ld h,INV>>8
                ld a,(hl)
                inc a
                jp z,di_T
                jp di_F
; A = v[arg0], (HL) = v[arg1]
df_vv:          push bc
                ld a,(de)
                inc de
                ld l,a
                ld h,VARS>>8
                ld c,(hl)
                ld a,(de)
                inc de
                ld l,a
                ld a,c
                pop bc
                cp (hl)
                ret
df_equalv:      call df_vv
                jp z,di_T
                jp di_F
df_lessv:       call df_vv
                jp c,di_T
                jp di_F
df_greaterv:    call df_vv
                jp z,di_F
                jp c,di_F
                jp di_T

; resto de condiciones y los bytes de control
di_big:         cp $FC
                jp nc,di_ctl
                cp $0E
                jr nz,ds_nosd
                ld a,(FLAGS+4)          ; said, como testSaid: f4 (ya se acepto la orden) o sin f2 (no hay orden): falso, sin pasar por el overlay C
                or a
                jr nz,ds_nof
                ld a,(FLAGS+2)
                or a
                jr nz,ds_sd
ds_nof:         ld a,(de)
                inc de
                add a,a
                add a,e
                ld e,a
                jp nc,di_F
                inc d
                jp di_F
ds_nosd:        cp NCONDS+1
                jp nc,di_bad
                push bc
                jr ds_norm
ds_sd:          push bc
                ld a,(de)               ; said: k palabras de 16 bits
                inc de
                ld (saidk),a
                ld (saidp),de
                add a,a
                ld l,a
                ld h,0
                add hl,de
                ex de,hl
                ld (ip),de
                call hc_said
                jr ds_res
ds_norm:        dec a
                ld c,a
                ld b,0
                ld hl,cargtab
                add hl,bc
                ld a,(hl)
                ld hl,ARGS
                or a
                jr z,ds_na
                ld b,a
ds_ca:          ld a,(de)
                inc de
                ld (hl),a
                inc hl
                djnz ds_ca
ds_na:          ld (ip),de
                ld b,0
                ld hl,ccmdtab
                add hl,bc
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                call jp_hl
ds_res:         pop bc
                ld de,(ip)
                or a
                jp nz,di_T
                jp di_F

di_ctl:         cp $FF
                jr z,di_endt
                cp $FD
                jr z,di_neg
                cp $FC
                jr nz,di_bad
                ld a,b
                or a
                jr z,di_open
                ld a,$FF                ; el OR acaba sin ninguna condicion cierta: falso, y se salta hasta el $FF (testIfCode)
                call skip_until
                jr di_endf
di_open:        ld b,1
                jp di_l
di_neg:         ld c,1
                jp di_l
di_bad:         ld a,7
                jp fatal

; condicion cierta / falsa (ya con el NOT aplicado al salir)
di_T:           ld a,c
                or a
                jr nz,di_tn
di_tp:          ld a,b
                or a
                jp z,di_l               ; en un Y, sigue
                ld a,$FC                ; en un OR, la primera cierta salta hasta el $FC que lo cierra
                call skip_until
                ld bc,0
                jp di_l
di_tn:          ld c,0
                jr di_fp
di_F:           ld a,c
                or a
                jr nz,di_fn
di_fp:          ld a,b
                or a
                jp nz,di_l              ; en un OR, sigue
                ld a,$FF                ; en un Y, la primera falsa salta hasta el $FF
                call skip_until
                jr di_endf
di_fn:          ld c,0
                jr di_tp

di_endt:        ex de,hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ex de,hl
                jp rl_go
di_endf:        ex de,hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                add hl,de
                ex de,hl
                jp rl_go

; skipInstructionsUntil: DE = ip, A = $FC o $FF; salta instrucciones de condicion hasta ese byte (inclusive)
skip_until:     ld b,a                  ; destruye BC (do_if lo repone)
su_l:           ld a,(de)
                inc de
                cp b
                ret z
                cp $FC
                jr nc,su_l
                cp $0E
                jr z,su_s
                ld hl,cargtab-1
                add a,l
                ld l,a
                jr nc,su_n
                inc h
su_n:           ld a,(hl)
                add a,e
                ld e,a
                jr nc,su_l
                inc d
                jr su_l
su_s:           ld a,(de)               ; said: n palabras de 16 bits
                ld l,a
                ld h,0
                add hl,hl
                inc hl
                add hl,de
                ex de,hl
                jr su_l

jp_hl:          jp (hl)

; DE = direccion del codigo de operacion: apunta (logica, pc) en la traza y cuenta el paso
                IF TESTS
trace_step:     push de
                ld hl,(nsteps)
                inc hl
                ld (nsteps),hl
                ld hl,(trcount)
                ld bc,TRMAX
                or a
                sbc hl,bc
                jr nc,ts_end
                ld hl,(trcount)
                inc hl
                ld (trcount),hl
                ld a,(curlg)
                ld (TRREC),a
                ld a,e
                ld (TRREC+1),a
                ld a,d
                sub LWIN>>8
                ld (TRREC+2),a
                ld a,PG_DBG
                call map_page
                ld hl,TRREC
                ld de,(trptr)
                ld bc,3
                ldir
                ld (trptr),de
                call unmap_win
ts_end:         pop de
                ret
                ENDIF

; ---------------------------------------------------------------------
;  Sala nueva, reloj, resumen, sonidos
; ---------------------------------------------------------------------
do_new_room:    xor a                   ; la logica 0 se reinicia sin la linea tecleada (bandera 2) ni la palabra desconocida (v9), como en AGI
                ld (FLAGS+2),a
                ld (VARS+9),a
                ld (st_n),a             ; los add.to.pic se olvidan (siguen pintados en la imagen hasta draw.pic)
                call OVL_SPCLR
                call OVL_SPRINIT        ; los sprites se apagan hasta que los objetos de la sala nueva tengan su sitio (se vuelven a poner al acabar el ciclo)
                call h_stop_sound
                ld a,(VARS+0)
                ld (VARS+1),a
                ld hl,OVC_NEWROOM       ; newRoom: todos los objetos (tambien el ego) con paso y tiempos a 1, y las logicas (menos la 0) vuelven a su principio
                call call_c
                ld ix,OBJ               ; todos, el ego tambien (newRoom de ScummVM), dejan de estar animados y dibujados; su animate.obj (logica 0) les pone el resto de banderas
                ld de,32
                ld b,NOBJ
nr_u:           res 0,(ix+O_F1)
                res 1,(ix+O_F1)
                add ix,de
                djnz nr_u
                ld ix,OBJ
                ld a,1
                ld (pctl),a
                xor a
                ld (blkf),a
                ld a,36
                ld (horizon),a
                ld a,(nr_val)
                ld (VARS+0),a
                xor a
                ld (VARS+4),a
                ld (VARS+5),a
                ld de,0
                call obj_cell           ; D = ancho del ego
                ld a,(VARS+2)           ; por que borde entra
                cp 1
                jr nz,nr_2
                ld (ix+O_Y),167
                jr nr_e
nr_2:           cp 2
                jr nz,nr_3
                ld (ix+O_X),0
                jr nr_e
nr_3:           cp 3
                jr nz,nr_4
                ld a,(horizon)
                inc a
                ld (ix+O_Y),a
                jr nr_e
nr_4:           cp 4
                jr nz,nr_e
                ld a,160
                sub d
                ld (ix+O_X),a
nr_e:           xor a
                ld (VARS+2),a
                ld (nr_pend),a
                ld (exitall),a
                inc a
                ld (FLAGS+5),a
                ret

tick_clock:     ld a,(VARS+10)
                or a
                jr nz,tc_1
                inc a
tc_1:           ld b,a
                ld a,20
                call div8               ; C = 20 // v10
                ld a,c
                or a
                jr nz,tc_2
                inc a
tc_2:           ld b,a                  ; periodo
                ld a,(ticks)
                inc a
                ld (ticks),a
                cp b
                ret c
                xor a
                ld (ticks),a
                ld hl,VARS+11
                inc (hl)
                ld a,(hl)
                cp 60
                ret c
                ld (hl),0
                inc hl
                inc (hl)
                ld a,(hl)
                cp 60
                ret c
                ld (hl),0
                inc hl
                inc (hl)
                ld a,(hl)
                cp 24
                ret c
                ld (hl),0
                inc hl
                inc (hl)
                ret

; sonidos cuyo final ya llego: ponen su bandera (se mira al empezar el ciclo)
snd_due:        ld a,(FLAGS+9)          ; sonido apagado: se para lo que suene
                or a
                jr nz,sd_on
                ld a,(snd_on)
                or a
                jr z,sd_on
                xor a
                ld (snd_on),a
                ld a,CMD_STOPVGM
                call mcu_send
sd_on:          ld hl,SNDP
                ld b,8
sd_l:           ld a,(hl)
                cp $FF
                jr z,sd_next
                push hl
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,(cyc)             ; vence si due <= ciclo  <=>  no (ciclo < due)
                or a
                sbc hl,de
                pop hl
                jr c,sd_next
                ld e,(hl)
                ld d,FLAGS>>8
                ld a,1
                ld (de),a
                ld (hl),$FF
sd_next:        inc hl
                inc hl
                inc hl
                djnz sd_l
                ret

; ---------------------------------------------------------------------
;  Aritmetica
; ---------------------------------------------------------------------
; A = A / B (B != 0) -> C = cociente, A = resto
div8:           ld c,0
d8_l:           cp b
                ret c
                sub b
                inc c
                jr d8_l

; A = A * B (8 bits bajos)
mul8:           ld c,a
                xor a
                ld d,8
m8_l:           add a,a
                rl b
                jr nc,m8_n
                add a,c
m8_n:           dec d
                jr nz,m8_l
                ret

; HL = HL / DE (DE != 0) -> HL cociente
div16:          ld b,16
                ld a,h
                ld c,l
                ld hl,0
d16_l:          scf
                rl c
                rla
                adc hl,hl
                sbc hl,de
                jr nc,d16_s
                add hl,de
                dec c
d16_s:          djnz d16_l
                ld h,a
                ld l,c
                ret

rand8:          ld hl,(lfsr)
                ld b,8
r8_l:           srl h
                rr l
                jr nc,r8_n
                ld a,h
                xor $B4
                ld h,a
r8_n:           djnz r8_l
                ld (lfsr),hl
                ld a,l
                ret

; ---------------------------------------------------------------------
;  Utilidades de los manejadores
; ---------------------------------------------------------------------
; A = indice de variable -> A = valor (HL cambia)
getv:           ld l,a
                ld h,VARS>>8
                ld a,(hl)
                ret

ret_true:       ld a,1
                ret
ret_false:      xor a
                ret

; HL = FLAGS + arg0
flagptr:        ld a,(ARGS)
                ld l,a
                ld h,FLAGS>>8
                ret
; HL = FLAGS + valor de la variable arg0
flagptrv:       ld a,(ARGS)
                call getv
                ld l,a
                ld h,FLAGS>>8
                ret
; HL = VARS + arg0
varptr:         ld a,(ARGS)
                ld l,a
                ld h,VARS>>8
                ret

; ---------------------------------------------------------------------
;  Comandos (h_<nombre>); los que no estan aqui no hacen nada (h_nop) y gen_agitab.py los deja asi
; ---------------------------------------------------------------------
h_nop:          ret
h_set_game_id:  ld hl,OVC_GAMEID
                jp call_c
clr_ctl:        ld a,(ctl_d)
                or a
                ret z
                xor a
                ld (ctl_d),a
                ld hl,CTL
                ld de,CTL+1
                ld bc,255
                ld (hl),0
                ldir
                ret

; HL = CTL + controlador
ctl_set:        ld (hl),1
                ld a,h
                ld (ctl_d),a
                ret
ctl_d:          defb 1                  ; distinto de 0: hay controladores que borrar (al arrancar, CTL sin iniciar)

h_return:       ld hl,(lend)
                ld (ip),hl
                ret

h_increment:    call varptr
                ld a,(hl)
                cp 255
                ret z
                inc (hl)
                ret
h_decrement:    call varptr
                ld a,(hl)
                or a
                ret z
                dec (hl)
                ret
h_assignn:      call varptr
                ld a,(ARGS+1)
                ld (hl),a
                ret
h_assignv:      ld a,(ARGS+1)
                call getv
                ld b,a
                call varptr
                ld (hl),b
                ret
h_addn:         call varptr
                ld a,(ARGS+1)
                add a,(hl)
                ld (hl),a
                ret
h_addv:         ld a,(ARGS+1)
                call getv
                ld b,a
                call varptr
                ld a,(hl)
                add a,b
                ld (hl),a
                ret
h_subn:         call varptr
                ld a,(hl)
                ld b,a
                ld a,(ARGS+1)
                ld c,a
                ld a,b
                sub c
                ld (hl),a
                ret
h_subv:         ld a,(ARGS+1)
                call getv
                ld c,a
                call varptr
                ld a,(hl)
                sub c
                ld (hl),a
                ret
h_mul_n:        ld a,(ARGS+1)
                ld b,a
                call varptr
                ld a,(hl)
                push hl
                call mul8
                pop hl
                ld (hl),a
                ret
h_mul_v:        ld a,(ARGS+1)
                call getv
                ld b,a
                call varptr
                ld a,(hl)
                push hl
                call mul8
                pop hl
                ld (hl),a
                ret
h_div_n:        ld a,(ARGS+1)
                ld b,a
                jr dv_do
h_div_v:        ld a,(ARGS+1)
                call getv
                ld b,a
dv_do:          call varptr
                ld a,b
                or a
                jr z,dv_0
                ld a,(hl)
                push hl
                call div8
                pop hl
                ld (hl),c
                ret
dv_0:           ld (hl),0
                ret
h_lindirectv:   ld a,(ARGS+1)           ; v[v[a]] = v[b]
                call getv
                ld b,a
                ld a,(ARGS)
                call getv
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret
h_rindirect:    ld a,(ARGS+1)           ; v[a] = v[v[b]]
                call getv
                call getv
                ld b,a
                call varptr
                ld (hl),b
                ret
h_lindirectn:   ld a,(ARGS)             ; v[v[a]] = n
                call getv
                ld l,a
                ld h,VARS>>8
                ld a,(ARGS+1)
                ld (hl),a
                ret

h_set:          call flagptr
                ld (hl),1
                ret
h_reset:        call flagptr
                ld (hl),0
                ret
h_toggle:       call flagptr
                ld a,(hl)
                xor 1
                ld (hl),a
                ret
h_set_v:        call flagptrv
                ld (hl),1
                ret
h_reset_v:      call flagptrv
                ld (hl),0
                ret
h_toggle_v:     call flagptrv
                ld a,(hl)
                xor 1
                ld (hl),a
                ret

h_new_room:     ld a,(ARGS)
nr_set:         ld (nr_val),a
                ld a,1
                ld (nr_pend),a
                ld (exitall),a
                ret
h_new_room_v:   ld a,(ARGS)
                call getv
                jr nr_set
h_call:         ld a,(ARGS)
                jp run_logic
h_call_v:       ld a,(ARGS)
                call getv
                jp run_logic

h_random:       ld a,(ARGS)             ; lo, hi, variable destino
                ld b,a
                ld a,(ARGS+1)
                cp b
                jr c,rn_0               ; hi < lo
                sub b
                inc a
                ld d,a                  ; n = hi-lo+1 (0 = 256)
                call rand8
                ld c,a
                ld a,d
                or a
                ld a,c
                jr z,rn_add
                ld b,d
                call rem8
rn_add:         ld hl,ARGS
                add a,(hl)
                ld b,a
                jr rn_st
rn_0:           ld a,(ARGS)
                ld b,a
rn_st:          ld a,(ARGS+2)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret
rem8:           cp b
                ret c
                sub b
                jr rem8

h_program_control: xor a
                ld (pctl),a
                ret
h_player_control: ld a,1
                ld (pctl),a
                xor a
                ld (OBJ+O_MOTION),a     ; el ego deja de seguir cualquier movimiento programado
                ret
; --- inventario
h_get:          ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld (hl),255
                ret
h_get_v:        ld a,(ARGS)
                call getv
                ld l,a
                ld h,INV>>8
                ld (hl),255
                ret
h_drop:         ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld (hl),0
                ret
h_put:          ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld a,(ARGS+1)
                ld (hl),a
                ret
h_put_v:        ld a,(ARGS+1)
                call getv
                ld b,a
                ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld (hl),b
                ret
h_get_room_v:   ld a,(ARGS)             ; v[b] = sala del objeto v[a]
                call getv
                ld l,a
                ld h,INV>>8
                ld b,(hl)
                ld a,(ARGS+1)
                ld l,a
                ld h,VARS>>8
                ld (hl),b
                ret

h_quit:         ld a,1
                ld (stopf),a
                ret
; restart.game: confirmacion y, con ENTER, el estado vuelve al del arranque (overlay C) y se sale de la logica en curso
h_restart_game: call h_stop_sound       ; cmdRestartGame: stopSound; con la bandera 16 (AUTO_RESTART) reinicia sin preguntar
                ld a,(FLAGS+16)
                or a
                jr nz,hr_go
                ld a,2
                call pr_rawgo
                ld a,(stopf)
                or a
                ret nz
                ld a,(pw_last)
                cp 13
                ret nz                  ; ESC: sigue la partida
hr_go:          ld hl,OVF_MENUON        ; itemEnableAll
                call call_f
                ld hl,OVC_RESTART
                call call_c
                ld a,1
                ld (FLAGS+6),a          ; la logica 0 conserva los menus y vuelve a la sala 2
                ld (rs_keep),a
                xor a
                ld (st_n),a
                call OVL_SPCLR
                call ov_tail
                ld a,1
                ld (exitall),a
                jp OVL_FORCE
; pause, status (inventario) y show.obj son ventanas de mensaje: pr_raw 1 = pausa, 2 = confirmar el reinicio (textos del overlay B), 3 = el texto ya esta en TMPM
h_pause:        ld a,1
pr_rawgo:       ld (pr_raw),a
                ld a,255
                ld (pr_row),a
                xor a
                ld (pr_w),a
                call pr_go
                xor a
                ld (pr_raw),a
                ret
h_status:       ld hl,OVF_DLGINV        ; InventoryMgr::show: pantalla de texto, lista de objetos (overlay F) y el mismo bucle de menu.input; al acabar, graphics
                call call_f
                call h_text_screen
                ld a,(FLAGS+13)         ; con la bandera 13 se elige un objeto (v25 = el elegido o 255); sin ella, cualquier tecla
                or a
                ld a,1
                jr nz,hs_m
                inc a
hs_m:           ld (mi_dlg),a
                call mi_nk
                xor a
                ld (mi_dlg),a
                ld a,(stopf)
                or a
                ret nz
                ld hl,OVF_DLGDONE
                call call_f
                jp h_graphics
h_show_mem:     ld a,5                  ; show.mem: messageBox("Enough memory")
                jr pr_rawgo
h_show_obj_v:   ld a,(ARGS)
                call getv
                ld (ARGS),a
h_show_obj:     ld hl,OVC_OBJDESC
                call call_c
                ld a,(oc_res)
                or a
                ret z
                ld a,4
                jr pr_rawgo
pr_raw:         defb 0
oc_res:         defb 0
oc_pw:          defb 0                  ; show.obj: ancho (HiRes) del dibujo, 0 = sin dibujo
pr_bw:          defb 0                  ; geometria de la ventana (la deja t_print, la usa el dibujo del overlay C)
pr_top:         defb 0
pr_cxl:         defb 0

; --- sonido: la bandera f se pone cuando acaba (duracion de la pista 0)
h_sound:        call snd_stop           ; el que suene se para (y su bandera se pone, como startSound -> stopSound)
                ld a,(ARGS+1)           ; f
                ld c,a
                ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                ld hl,SNDP              ; quita un pendiente de la misma bandera
                ld b,8
so_c:           ld a,(hl)
                cp c
                jr nz,so_n
                ld (hl),$FF
so_n:           inc hl
                inc hl
                inc hl
                djnz so_c
                ld a,PG_SND             ; t = SNDLEN[n]
                call map_page
                ld a,(ARGS)
                ld l,a
                ld h,0
                add hl,hl
                ld de,LWIN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = t
                push de
                call unmap_win
                pop de
                ld a,(VARS+10)
                or a
                jr nz,so_v
                inc a
so_v:           ld c,a                  ; BC = v10 (>= 1)
                ld b,0
                ld h,b
                ld l,c
                add hl,hl
                add hl,bc               ; HL = 3*v10
                ex de,hl                ; DE = 3*v10, HL = t
                add hl,hl               ; 2t
                add hl,de               ; numerador 2t + 3*v10
                push hl
                ld h,b
                ld l,c
                add hl,hl
                add hl,bc
                add hl,hl               ; 6*v10
                ex de,hl                ; DE = denominador
                pop hl
                call div16              ; HL = ciclos
                ld a,h
                or a
                jr nz,so_ok
                ld a,l
                cp 2
                jr nc,so_ok
                ld hl,2
so_ok:          ld de,(cyc)
                add hl,de               ; ciclo de vencimiento
                ld de,SNDP
                ld b,8
so_f:           ld a,(de)
                cp $FF
                jr z,so_put
                inc de
                inc de
                inc de
                djnz so_f
                ld a,8
                jp fatal
so_put:         ld a,(ARGS+1)
                ld (de),a
                inc de
                ld a,l
                ld (de),a
                inc de
                ld a,h
                ld (de),a
                jp snd_play

; stop.sound: el sonido se para y su bandera se pone
h_stop_sound:   call snd_stop
                ld a,CMD_STOPVGM
                jp mcu_send

; las banderas de los sonidos pendientes se ponen y se quedan libres
snd_stop:       ld hl,SNDP
                ld b,8
sst_l:           ld a,(hl)
                cp $FF
                jr z,sst_n
                ld e,a
                ld d,FLAGS>>8
                ld a,1
                ld (de),a
                ld (hl),$FF
sst_n:           inc hl
                inc hl
                inc hl
                djnz sst_l
                ret

; el MCU reproduce SNDnnn.VGM (TOOLS/agi2snd.py) de la carpeta del juego en segundo plano; con el sonido apagado (bandera 9) no suena
snd_play:       ld a,(FLAGS+9)
                or a
                ret z
                ld (snd_on),a
                ld a,CMD_STOPVGM
                call mcu_send
                ld a,CMD_LOOPVGM
                call mcu_send
                xor a
                call mcu_send
                ld a,CMD_PLAYVGM
                call mcu_send
                ld a,14
                call mcu_send
                ld a,$38                ; S N D / S N D (codigos del ZX81)
                call mcu_send
                ld a,$33
                call mcu_send
                ld a,$29
                call mcu_send
                ld a,$18
                call mcu_send
                ld a,$38
                call mcu_send
                ld a,$33
                call mcu_send
                ld a,$29
                call mcu_send
                ld a,(ARGS)
                ld (snd_r),a
                ld a,100
                call snd_dig
                ld a,10
                call snd_dig
                ld a,1
                call snd_dig
                ld a,$1B                ; . V G M
                call mcu_send
                ld a,$3B
                call mcu_send
                ld a,$2C
                call mcu_send
                ld a,$32
                call mcu_send
                jp mcu_recv
snd_dig:        ld c,a
                ld b,$1B
sdg_l:           inc b
                ld a,(snd_r)
                sub c
                ld (snd_r),a
                jr nc,sdg_l
                add a,c
                ld (snd_r),a
                ld a,b
                jp mcu_send
snd_r:          defb 0
snd_on:         defb 0

; ---------------------------------------------------------------------
;  Condiciones (hc_<nombre>): devuelven A = 1 o 0
; ---------------------------------------------------------------------
hc_false:       xor a
                ret
hc_equaln:      ld a,(ARGS)
                call getv
                ld hl,ARGS+1
                cp (hl)
                jp z,ret_true
                jp ret_false
hc_equalv:      call two_vars
                cp b
                jp z,ret_true
                jp ret_false
hc_lessn:       ld a,(ARGS)
                call getv
                ld hl,ARGS+1
                cp (hl)
                jp c,ret_true
                jp ret_false
hc_lessv:       call two_vars
                cp b
                jp c,ret_true
                jp ret_false
hc_greatern:    ld a,(ARGS)
                call getv
                ld hl,ARGS+1
                cp (hl)
                jp z,ret_false
                jp c,ret_false
                jp ret_true
hc_greaterv:    call two_vars
                cp b
                jp z,ret_false
                jp c,ret_false
                jp ret_true
hc_isset:       call flagptr
                ld a,(hl)
                or a
                jp z,ret_false
                jp ret_true
hc_issetv:      call flagptrv
                ld a,(hl)
                or a
                jp z,ret_false
                jp ret_true
hc_has:         ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld a,(hl)
                cp 255
                jp z,ret_true
                jp ret_false
hc_obj_in_room: ld a,(ARGS)
                ld l,a
                ld h,INV>>8
                ld b,(hl)
                ld a,(ARGS+1)
                call getv
                cp b
                jp z,ret_true
                jp ret_false
; A = v[arg0], B = v[arg1]
two_vars:       ld a,(ARGS+1)
                call getv
                ld b,a
                ld a,(ARGS)
                jp getv

; ---------------------------------------------------------------------
;  Datos
; ---------------------------------------------------------------------
                include "agiobj.asm"
                include "agiin.asm"
                include "agipic.asm"
                include "agispr.asm"
                include "agitab.inc"

nm:             defb "LOG/LOG000.AGL",0
nm_inv:         defb "DATA/INVROOM.BIN",0
nm_snd:         defb "DATA/SNDLEN.BIN",0
nm_views:       defb "DATA/VIEWS.HDR",0
nm_words:       defb "DATA/WORDS.BIN",0
nm_evt:         defb "DATA/EVENTS.BIN",0
nm_invn:        defb "DATA/INVNAMES.BIN",0
nm2:            defb "LOG/LOG000.MSG",0
nm3:            defb "PIC/PIC000.GFX",0
sv_sp:          defw 0
sv_i:           defb 0
sv_ret:         defw 0
fh:             defb 0
errc:           defb 0
stopf:          defb 0
rs_keep:        defb 0
rs_rerun:       defb 0                  ; restore.game acaba de ejecutarse: la logica 0 se repite en este ciclo
rs_warm:        defb 0                  ; ya hubo un arranque: el reinicio conserva las cadenas (agiInit no las borra con _restartGame)
gfix:           defb 0                  ; set.game.id: 1 = SQ1, 2 = Larry 1 (apanos de ScummVM por juego)
exitall:        defb 0
lastpic:        defb 0                  ; la ultima imagen dibujada (para rehacerla al cargar una partida)
ovl_on:         defb 0                  ; 1 = la imagen lleva su overlay.pic (va justo despues de lastpic: se guardan juntos)
tfg:            defb 15                 ; el color del texto (set.text.attribute): tinta y fondo (los usan el overlay B y C)
tbg:            defb 0
nr_pend:        defb 0
nr_val:         defb 0
pctl:           defb 1
cyc:            defw 1
ticks:          defb 0
lfsr:           defw $ACE1
nsteps:         defw 0
nsum:           defb 0
sidx:           defb 0
sp_tmp:         defw 0
ncyc:           defw 0
evp:            defw 2
evend:          defb 0
ev_kind:        defb 0
dirhold:        defb 0
keyn:           defb 0
tqn:            defb 0
tqh:            defb 0
inwcnt:         defb 0
inwvalid:       defb 0
said_done:      defb 0
saidp:          defw 0
saidk:          defb 0
wcount:         defb 0
wtp:            defw WTEXT
pt_src:         defw 0
fw_num:         defw 0
fw_unk:         defb 0
fw_len:         defb 0
fw_p:           defw 0
pm_pos:         defw 0
fw_end:         defw 0
mr_dst:         defw 0
mr_m:           defb 0
mrb:            defs 4
mrn:            defb 0
fh2:            defb 0
bs_lg:          defb 0
bs_dp:          defw 0
bs_sp:          defw 0
bs_max:         defb 0
bs_n:           defb 0
bs_kind:        defb 0
bs_num:         defb 0
bs_fd:          defb 0
bs_md:          defb 0
bs_w:           defb 0
bs_dg:          defs 3
BSFR:           defs 4*BSFRN
pd_v:           defb 0
pd_s:           defb 0
ss_i:           defb 0
picvalid:       defb 0
prisz:          defw 0
prisz2:         defw 0
mg_n:           defb 0
mg_tab:         defs 4*MG_MAX       ; x, y, ancho, valor | alto << 2
pp_xs:          defb 0
pp_x0:          defb 0
pp_x1:          defb 0
horizon:        defb 36
blk:            defs 4
blkf:           defb 0
curk:           defb 0
mgd:            defb 0
nx:             defw 0
ny:             defw 0
ow:             defb 0
oh:             defb 0
qw:             defb 0
bdr:            defb 0
pk_d:           defb 0
vclamp:         defb 0
vs_cp:          defw 0
VSC:            defs 128,$FF            ; cache de vscan (agiobj.asm)
ocn:            defb 0
occ:            defb 0
trcount:        defw 0
trptr:          defw TRACE
sptr:           defw SUMM
curlg:          defb 0
curslot:        defb $FF
ip:             defw LWIN
lend:           defw LWIN
ldepth:         defb 0
vict:           defb 0
lhdr:           defw 0
lsize:          defw 0
lloaded:        defb 0
c_res:          defb 0
c_orm:          defb 0
c_orres:        defb 0
c_neg:          defb 0
slot_lg:        defs NSLOTS
slot_sip:       defs NSLOTS*2
slot_sz:        defs NSLOTS*2
SNDP:           defs 8*3
LSTK:           defs MAXDEPTH*6
