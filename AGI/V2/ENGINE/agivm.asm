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
LWIN            equ $8000
TOKLIM          equ $EA                 ; parte baja del limite de TOKS (TOKS+90)
KEYMAP          equ $7100               ; por tecla ASCII (0-127): controlador y si esta puesto (2 bytes)
CTL             equ $7200               ; controladores activos en este ciclo
STRS            equ $7710               ; 12 cadenas de 41 bytes
MSGBUF          equ $7900
TMPM            equ $7A00
WTEXT           equ $7B00
STMP            equ $7BC0
STMP2           equ $7BF0
PHR             equ $7C20
WBUF            equ $7C50
TOKS            equ $7C90
TOKP            equ $7CF0
INW             equ $7D10
KEYQ            equ $7D30
TQ              equ $7D40
EVBUF           equ $7DF0
SREC            equ $7E40
TRREC           equ $7E50
CLR_END         equ $7E60
PG_VIEWS        equ 24
PG_WORDS        equ 25
PG_SND          equ 26
PG_EVT          equ 27
PG_DBG          equ 28
PG_PRI          equ 29
PG_OVL          equ 41
PG_OVC          equ 44
PG_INV          equ 45
OVL_KPOLL       equ $2000               ; overlay A (teclado, sprites, rotulos): siempre en el bloque 1
OVL_KDELIV      equ $2003
OVL_ACCEPT      equ $2006
OVL_PREVENT     equ $2009
OVL_RENDER      equ $200C
OVL_SPRINIT     equ $200F
OVL_BGSAVE      equ $2012
OVL_FORCE       equ $2015
OVL_ADDPIC      equ $2018
OVL_SPCLR       equ $201B
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
OVB_SETMENU     equ $201E
OVB_SETITEM     equ $2021
OVB_ENABLE      equ $2024
OVB_DISABLE     equ $2027
OVB_MENUOPEN    equ $202A
OVB_MENUNAV     equ $202D
OVB_MENUSEL     equ $2030
OVB_MENUCLOSE   equ $2033
OVB_DLGSAVE     equ $2036
OVB_DLGLOAD     equ $2039
OVB_DLGDONE     equ $203C
OVB_MENURESET   equ $203F
OVB_DLGINV      equ $2042
OVB_GSDRAW      equ $2045
OVC_ECHO        equ $2009
OVC_CANCEL      equ $200C
OVC_CURSOR      equ $200F
OVC_OBJPIC      equ $2012
OVC_DIST        equ $2018
OVC_ANIM        equ $201B
OVC_GETNUM      equ $201E
OVC_PARSE       equ $2021
OVC_DRAW        equ $2024
OVC_TEXTSCR     equ $2015
OVC_RESTART     equ $2000               ; overlay C (restart.game, status, show.obj): tambien con call_c
OVC_INVTXT      equ $2003
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
                call video_init
                call init
                call ov_load
                ld a,(stopf)
                or a
                jp nz,finish

; ---------------------------------------------------------------------
;  El ciclo del interprete
; ---------------------------------------------------------------------
main_loop:      in a,(ClkPort)          ; las tramas se cuentan desde aqui (ver pace)
                ld hl,hk_seen
                ld (hl),0
                ld hl,CTL
                ld de,CTL+1
                ld bc,255
                ld (hl),0
                ldir
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
ml_run:         xor a
                call run_logic          ; la logica 0
                ld a,(stopf)
                or a
                jp nz,finish
                ld a,(nr_pend)
                or a
                jr z,ml_end
                call do_new_room
                jr ml_run
ml_end:         xor a                   ; los codigos de borde se ponen a 0 antes de mover los objetos (el movimiento los pone y la logica del ciclo siguiente los ve)
                ld (VARS+2),a
                ld (VARS+4),a
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
ml_dbg:         call summary
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
init:           ld hl,LGSLOT
                ld de,LGSLOT+1
                ld bc,255
                ld (hl),$FF
                ldir
                ld hl,slot_lg
                ld de,slot_lg+1
                ld bc,NSLOTS-1
                ld (hl),$FF
                ldir
                ld hl,VARS
                ld de,VARS+1
                ld bc,511               ; variables y banderas
                ld (hl),0
                ldir
                ld a,255
                ld (VARS+8),a
                ld a,2
                ld (VARS+10),a
                ld a,3
                ld (VARS+15),a
                ld a,15
                ld (VARS+22),a
                ld a,41
                ld (VARS+24),a
                ld a,3
                ld (VARS+26),a
                ld a,1
                ld (FLAGS+9),a
                ld (FLAGS+5),a
                ld (FLAGS+11),a
                ld (pctl),a
                ld hl,1
                ld (cyc),hl
                ld hl,TRACE
                ld (trptr),hl
                ld hl,SUMM
                ld (sptr),hl
                ld hl,SNDP              ; sonidos pendientes: todos libres
                ld b,8
in_s:           ld (hl),$FF
                inc hl
                inc hl
                inc hl
                djnz in_s
                ld hl,KEYMAP            ; teclas, controladores
                ld de,KEYMAP+1
                ld bc,511
                ld (hl),0
                ldir
                ld hl,ARGS              ; cadenas, buffers del parser
                ld de,ARGS+1
                ld bc,CLR_END-ARGS-1
                ld (hl),0
                ldir
                ld hl,OBJ
                ld de,OBJ+1
                ld bc,NOBJ*32-1
                ld (hl),0
                ldir
                ld a,36
                ld (horizon),a
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
                call unmap_win
                ld hl,nm_inv
                ld de,INV
                ld bc,256
                call load_aux
                ret

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
ll_free:        ld a,(curlg)
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
                ld hl,LWIN
                ld (ip),hl
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
rl_next:        ld de,(ip)
                ld hl,(lend)
                or a
                sbc hl,de
                ret z
                ret c
                ld a,(exitall)
                or a
                ret nz
                ld a,(stopf)
                or a
                ret nz
                call trace_step
                ld a,(de)
                inc de
                cp $FF
                jp z,do_if
                cp $FE
                jp z,do_goto
                cp NCMDS
                jr c,rl_cmd
                ld a,6
                jp fatal
rl_cmd:         ld c,a
                ld b,0
                ld hl,argtab
                add hl,bc
                ld a,(hl)
                ld hl,ARGS
                or a
                jr z,rl_na
                ld b,a
rl_ca:          ld a,(de)
                inc de
                ld (hl),a
                inc hl
                djnz rl_ca
rl_na:          ld (ip),de
                ld b,0
                ld hl,cmdtab
                add hl,bc
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld de,rl_next
                push de
                jp (hl)

do_goto:        ex de,hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                add hl,de
                ld (ip),hl
                jp rl_next

; DE apunta a las condiciones
do_if:          xor a
                ld (c_orm),a
                ld (c_orres),a
                ld (c_neg),a
                inc a
                ld (c_res),a
di_l:           ld a,(de)
                inc de
                cp $FF
                jp z,di_end
                cp $FD
                jr nz,di_1
                ld a,1
                ld (c_neg),a
                jr di_l
di_1:           cp $FC
                jr nz,di_2
                ld a,(c_orm)
                or a
                jr z,di_open
                ld a,(c_orres)          ; cierra el grupo OR: res = res && orres
                ld hl,c_res
                and (hl)
                ld (hl),a
                xor a
                ld (c_orres),a
                ld (c_orm),a
                jr di_l
di_open:        ld a,1
                ld (c_orm),a
                jr di_l
di_2:           or a
                jp z,di_bad
                cp NCONDS+1
                jp nc,di_bad
                cp $0E
                jr nz,di_norm
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
                jp di_res
di_norm:        dec a
                ld c,a
                ld b,0
                ld hl,cargtab
                add hl,bc
                ld a,(hl)
                ld hl,ARGS
                or a
                jr z,di_na
                ld b,a
di_ca:          ld a,(de)
                inc de
                ld (hl),a
                inc hl
                djnz di_ca
di_na:          ld (ip),de
                ld b,0
                ld hl,ccmdtab
                add hl,bc
                add hl,bc
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                call jp_hl
di_res:         ld b,a
                ld a,(c_neg)
                or a
                jr z,di_nn
                ld a,b
                xor 1
                ld b,a
                xor a
                ld (c_neg),a
di_nn:          ld a,(c_orm)
                or a
                jr z,di_and
                ld a,(c_orres)
                or b
                ld (c_orres),a
                jr di_nx
di_and:         ld a,(c_res)
                and b
                ld (c_res),a
di_nx:          ld de,(ip)
                jp di_l
di_end:         ex de,hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,(c_res)
                or a
                jr nz,di_t
                add hl,de
di_t:           ld (ip),hl
                jp rl_next
di_bad:         ld a,7
                jp fatal

jp_hl:          jp (hl)

; DE = direccion del codigo de operacion: apunta (logica, pc) en la traza y cuenta el paso
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

; ---------------------------------------------------------------------
;  Sala nueva, reloj, resumen, sonidos
; ---------------------------------------------------------------------
do_new_room:    xor a                   ; la logica 0 se reinicia sin la linea tecleada (bandera 2) ni la palabra desconocida (v9), como en AGI
                ld (FLAGS+2),a
                ld (FLAGS+0),a          ; banderas 0 y 3 (agua, linea de aviso): las de la sala anterior no valen (la sala nueva las vuelve a calcular al mover el ego)
                ld (FLAGS+3),a
                ld (VARS+9),a
                call OVL_SPCLR
                call OVL_SPRINIT        ; los sprites se apagan hasta que los objetos de la sala nueva tengan su sitio (se vuelven a poner al acabar el ciclo)
                call h_stop_sound
                ld a,(VARS+0)
                ld (VARS+1),a
                ld ix,OBJ+32            ; todos menos el ego dejan de estar animados y dibujados
                ld de,32
                ld b,NOBJ-1
nr_u:           res 0,(ix+O_F1)
                res 1,(ix+O_F1)
                add ix,de
                djnz nr_u
                ld ix,OBJ
                ld a,(ix+O_F1)
                and $DD                 ; el ego sin dibujar ni prioridad fija, y listo para andar (actualiza, cicla, se mueve) aunque la sala anterior le hiciera stop.motion o set.priority
                or $1C
                ld (ix+O_F1),a
                xor a                   ; y observa bloques y objetos (la 7 lo deja con ignore.blocks e ignore.objs al cruzar su puerta)
                ld (ix+O_F2),a
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
                bit 0,(ix+O_F1)
                call nz,obj_cell        ; D = ancho del ego
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
                ld (FLAGS+0),a
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

; ciclo, pasos, suma de variables, suma de los indices de las banderas puestas, sala, objetos, cadenas, entrada: 15 bytes por ciclo
summary:        ld hl,SREC
                ld de,(cyc)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld de,(nsteps)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld (sp_tmp),hl
                ld hl,0
                ld de,VARS
                ld b,0
su_v:           ld a,(de)
                add a,l
                ld l,a
                jr nc,su_v1
                inc h
su_v1:          inc e
                djnz su_v
                push hl                 ; suma de variables
                ld hl,0
                ld de,FLAGS
                ld b,0
                ld c,0
su_f:           ld a,(de)
                or a
                jr z,su_f1
                ld a,c
                add a,l
                ld l,a
                jr nc,su_f1
                inc h
su_f1:          inc c
                inc e
                djnz su_f
                ex de,hl                ; DE = suma de banderas
                pop bc                  ; BC = suma de variables
                ld hl,(sp_tmp)
                ld (hl),c
                inc hl
                ld (hl),b
                inc hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(VARS+0)
                ld (hl),a
                inc hl
                push hl
                call objsum
                ex de,hl
                pop hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                push hl
                call strsum
                ex de,hl
                pop hl
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                push hl
                call miscsum
                ex de,hl
                pop hl
                ld (hl),e
                inc hl
                ld (hl),d
                ld a,PG_DBG
                call map_page
                ld hl,SREC
                ld de,(sptr)
                ld bc,15
                ldir
                ld (sptr),de
                call unmap_win
                ld hl,nsum
                inc (hl)
                ld hl,0
                ld (nsteps),hl
                ret

; HL = horizonte + control + bloque + los 23 primeros bytes de cada objeto
objsum:         ld hl,0
                ld a,(horizon)
                call adda
                ld a,(pctl)
                call adda
                ld a,(blkf)
                call adda
                ld de,OBJ
                ld b,NOBJ
os_o:           ld c,23
os_i:           ld a,(de)
                add a,l
                ld l,a
                jr nc,os_n
                inc h
os_n:           inc de
                dec c
                jr nz,os_i
                ld a,e
                add a,9
                ld e,a
                jr nc,os_p
                inc d
os_p:           djnz os_o
                ret
adda:           add a,l
                ld l,a
                ret nc
                inc h
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
h_restart_game: ld a,2
                call pr_rawgo
                ld a,(stopf)
                or a
                ret nz
                ld a,(pw_last)
                cp 13
                ret nz                  ; ESC (o cualquier otra tecla): sigue la partida
                ld hl,OVC_RESTART
                call call_c
                ld a,1
                ld (FLAGS+6),a          ; la logica 0 conserva los menus y vuelve a la sala 2
                ld (rs_keep),a
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
h_status:       ld a,(FLAGS+13)         ; con la bandera 13 se elige un objeto (v25 = el elegido o 255): lista de un menu y el mismo bucle de menu.input
                or a
                jr z,hs_txt
                ld hl,OVB_DLGINV
                call call_b
                ld a,(oc_res)
                or a
                jr z,hs_none
                ld a,1
                ld (mi_dlg),a
                call mi_nk
                xor a
                ld (mi_dlg),a
                ld a,(stopf)
                or a
                ret nz
                ld hl,OVB_DLGDONE
                call call_b
                ld a,(mn_res)
                ld (VARS+25),a
                ret
hs_none:        ld a,255
                ld (VARS+25),a
hs_txt:         ld hl,OVC_INVTXT
                call call_c
                ld a,3
                jr pr_rawgo
h_show_obj_v:   ld a,(ARGS)
                call getv
                ld (ARGS),a
h_show_obj:     ld hl,OVC_OBJDESC
                call call_c
                ld a,(oc_res)
                or a
                ret z
                ld a,3
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
ntok:           defb 0
intok:          defb 0
mi:             defb 0
mk:             defb 0
bp_j:           defb 0
fw_found:       defb 0
fw_num:         defw 0
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
pd_v:           defb 0
pd_s:           defb 0
ss_i:           defb 0
picvalid:       defb 0
prisz:          defw 0
prisz2:         defw 0
pr_has0:        defb 0
pr_has1:        defb 0
mg_n:           defb 0
mg_tab:         defs 32
pr_water:       defb 0
pr_land:        defb 0
pr_sig:         defb 0
pp_xs:          defb 0
pp_x0:          defb 0
pp_x1:          defb 0
horizon:        defb 36
blk:            defs 4
blkf:           defb 0
curk:           defb 0
nx:             defw 0
ny:             defw 0
mdx:            defw 0
mdy:            defw 0
ow:             defb 0
oh:             defb 0
qw:             defb 0
bdr:            defb 0
pk_d:           defb 0
vclamp:         defb 0
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
slot_sz:        defs NSLOTS*2
SNDP:           defs 8*3
LSTK:           defs MAXDEPTH*6
