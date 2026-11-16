; =====================================================================
;  ovc9.asm - fase 9 (overlay C; solo en el programa, PROGRAM = 1): guardar y cargar partidas. Se incluye desde ovlc.asm.
;  ScummEngine_v4::o4_saveLoadGame (script_v4.cpp) y ScummEngine::saveState / loadState (saveload.cpp). El modelo es
;  vmmodel3.CoreVM.save_game / load_game / save_load_game / load_save_names; las pruebas, en FASE3.md ("Fase 9").
;
;  El opcode (a = ranura en los 5 bits bajos y la orden en los 3 altos):  $00 numero de ranuras (100)   $20 unidad (3)
;  $40 cargar (3 bien, 5 mal)   $80 guardar (0 bien, 2 mal)   $C0 existe? (6 si, 7 no). Los ficheros son SAVEnn.SAV con nn = ranura (2 cifras, sin "_"),
;  en la carpeta actual (la del juego). En v3 la ranura va de 1 en adelante y el nombre de la partida es la cadena 9 + ranura (STRINGID_SAVENAME1 = 10),
;  que el script del dialogo de Indy3 (sala 14) llena antes de guardar.
;
;  Un fichero lleva (en este orden): la cabecera (la de DATA.BIN, ld_hdr, 16 bytes, y la direccion de ev_handler, que identifica la version del
;  programa), el nombre (32), OBJCLS (pagina fria 47: las clases de los 1.000 objetos, 3.000), el hueco del bloque 4 (actores, nombres de actor
;  y de objeto y verbos), el monton de cadenas (STRHEAP), las variables del reproductor de sonido, MSGBUF (el mensaje en curso) y el bloque 7 entero ($E000-$FFFF:
;  variables, estados, duenos, sala, frases, ranuras, locales, inventario, camara, cursor, paletas...). 13.5 KB.
;  Lo que NO se restaura (se guarda aparte y se vuelve a poner despues de leer el bloque 7): lo que es del momento y no de la partida: la
;  pila de la API (TOPSP), la pagina del overlay, el indice de runAllScripts, el resultado en curso (RESV), el suceso de entrada y el raton.
;  Al cargar se rehace lo que el estado no lleva: la sala se vuelve a pintar (gf_load_room con CURROOM), la paleta, las filas de texto, los
;  verbos, los objetos y los sprites; el sonido para y empieza otra vez el que sonaba. El script en marcha sigue por donde dice su ranura (se
;  guardo con update_ptr: justo despues del saveLoadGame) y el resultado (3) se escribe en la variable del cargar, como ScummVM (setResult tras
;  loadState).
; =====================================================================
CMD_FWRITE      equ 56
CMD_FCREATE     equ 71
SL_NAME         equ $9740               ; "SAVEnn.SAV" + 0 (11 bytes)
SL_HDR          equ $9750               ; la cabecera que se escribe o se espera (18)
SL_TMP          equ $9762               ; cabecera leida (18); a continuacion, SL_NM (juntos: 50 bytes para leer el nombre sin mas)
SL_NM           equ $9774               ; el nombre (32)
SL_LIVE         equ $97A0               ; los bytes de sl_live guardados mientras se lee el bloque 7 (hasta 64)
sl_h            equ $97E0               ; manejador del fichero
sl_slot         equ $97E1
slp_sid          equ $97E2
wr_err          equ $97E3
wr_h            equ $97E4
wr_src          equ $97E5               ; palabra
wr_cnt          equ $97E7               ; palabra
SL_CLS          equ 3*NOBJ              ; OBJCLS
SL_HOLE         equ HOLE_END-ACTORS     ; del primer actor al final del monton de cadenas
SL_SNDV         equ sd_qr+1-snd_mt      ; las variables del reproductor (SV+154..SV+177)
SL_TOTAL        equ 18+32+SL_CLS+SL_HOLE+STRMAX+SL_SNDV+MSG_MAX+$2000

; sl_main: A = el byte a del opcode -> HL = el resultado
sl_main:        ld c,a
                and $1F
                ld (sl_slot),a
                ld a,c
                and $E0
                ld hl,100
                ret z                   ; 0: numero de ranuras
                cp $20
                ld l,3
                ret z                   ; 1: unidad
                cp $40
                jp z,sl_load
                cp $80
                jp z,sl_save
                cp $C0
                jp z,sl_test
                ld hl,0
                ret

; la entrada fija OVC_SLOAD (la usa el bucle principal con DBG_SAVE): C = el byte a
sl_entry:       ld a,c
                jr sl_main

; SAVEnn.SAV con nn = ranura
sl_name:        ld hl,sl_tpl
                ld de,SL_NAME
                ld bc,11
                ldir
                ld a,(sl_slot)
                ld b,'0'-1
sln_t:          inc b
                sub 10
                jr nc,sln_t
                add a,10+'0'
                ld hl,SL_NAME+4
                ld (hl),b
                inc hl
                ld (hl),a
                ret
sl_tpl:         defb "SAVE00.SAV",0

; SL_HDR = ld_hdr (16) + la direccion de ev_handler
sl_hdr:         ld hl,ld_hdr
                ld de,SL_HDR
                ld bc,16
                ldir
                ld hl,ev_handler
                ld (SL_HDR+16),hl
                ret

; SL_NM = el nombre de la partida de la ranura: la cadena 9 + ranura (hasta 31 caracteres), o vacio
sl_getname:     ld hl,SL_NM
                ld de,SL_NM+1
                ld bc,31
                ld (hl),0
                ldir
                ld a,(sl_slot)
                add a,9
                cp NSTR
                ret nc
                ld (slp_sid),a
                call sl_strp            ; HL = su direccion; Z si no existe
                ret z
                ld de,SL_NM
                ld b,31
sgn_l:          ld a,(hl)
                or a
                ret z
                ld (de),a
                inc hl
                inc de
                djnz sgn_l
                ret

; sl_strp: slp_sid = id de cadena -> HL = su direccion en STRHEAP, C = su longitud (con el 0); Z si la cadena no existe (id < NSTR)
sl_strp:        ld a,(slp_sid)
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld c,(hl)
                ld a,c
                or a
                ret z
                ld hl,STRPOS
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,STRHEAP
                add hl,de
                or 1                    ; NZ
                ret

; A = (sl_h): escribe BC bytes desde HL
sl_wr:          ld a,(sl_h)
                jp f_write_n

; ---------------------------------------------------------------- guardar
sl_save:        call update_ptr         ; el puntero del script en marcha va a su ranura: al cargar sigue justo despues de este opcode
                call sl_name
                ld hl,SL_NAME
                call f_create
                cp $FF
                ld hl,2
                ret z
                ld (sl_h),a
                xor a
                ld (wr_err),a
                call sl_hdr
                call sl_getname
                ld hl,SL_HDR
                ld bc,18
                call sl_wr
                ld hl,SL_NM
                ld bc,32
                call sl_wr
                call cls_open
                ld hl,WINDOW
                ld bc,SL_CLS
                call sl_wr
                call cls_close
                ld hl,sl_regs
sls_r:          ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                or e
                jr z,sls_b7
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                push hl
                ex de,hl
                call sl_wr
                pop hl
                jr sls_r
sls_b7:         ld hl,$E000
                ld bc,$2000
                call sl_wr
                ld a,(sl_h)
                call f_close
                ld hl,0
                ld a,(wr_err)
                or a
                ret z
                ld hl,2
                ret

; las regiones que van tal cual (direccion, longitud): el hueco del bloque 4, el reproductor de sonido y el mensaje
sl_regs:        defw ACTORS, SL_HOLE
                defw STRHEAP, STRMAX
                defw snd_mt, SL_SNDV
                defw MSGBUF, MSG_MAX
                defw 0

; lo que no se restaura al cargar: (direccion, longitud)
sl_live:        defw DELTA
                defb 1
                defw RESV
                defb 2
                defw TOPOP
                defb 1
                defw TOPSP              ; TOPSP y DS_SP
                defb 4
                defw WINPG
                defb 1
                defw OVLCUR             ; OVLCUR y HOSTVEC
                defb 3
                defw RAI
                defb 1
                defw SC
                defb 24
                defw INEV
                defb 17
                defw 0

; ---------------------------------------------------------------- existe
sl_test:        call sl_name
                ld hl,SL_NAME
                call f_open
                cp $FF
                ld hl,7
                ret z
                call f_close
                ld hl,6
                ret

; ---------------------------------------------------------------- cargar
sl_load:        call sl_name
                ld hl,SL_NAME
                call f_open
                cp $FF
                ld hl,5
                ret z
                ld (sl_h),a
                ld a,CMD_FSTAT          ; el tamano tiene que ser el de un guardado de esta version (si no, no se toca nada)
                call mcu_send
                ld a,(sl_h)
                call mcu_send
                ld hl,SL_TMP
                ld b,4
sll_s:          call mcu_recv
                ld (hl),a
                inc hl
                djnz sll_s
                ld b,5
sll_s2:         call mcu_recv
                djnz sll_s2
                ld hl,(SL_TMP+2)
                ld a,h
                or l
                jp nz,sll_bad
                ld hl,(SL_TMP)
                ld de,SL_TOTAL
                or a
                sbc hl,de
                jp nz,sll_bad
                call sl_hdr             ; la cabecera tiene que ser la de este DATA.BIN y de este programa
                ld a,(sl_h)
                ld hl,SL_TMP
                ld bc,50                ; cabecera y nombre
                call f_read_n
                ld hl,SL_TMP
                ld de,SL_HDR
                ld b,18
sll_c:          ld a,(de)
                cp (hl)
                jp nz,sll_bad
                inc hl
                inc de
                djnz sll_c
                ; a partir de aqui el estado cambia
                ld hl,sl_live
                ld de,SL_LIVE
sst_l:          ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,b
                or c
                jr z,sst_e
                ld a,(hl)
                inc hl
                push hl
                ld h,b
                ld l,c
                ld c,a
                ld b,0
                ldir
                pop hl
                jr sst_l
sst_e:          call cls_open
                ld a,(sl_h)
                ld hl,WINDOW
                ld bc,SL_CLS
                call f_read_n
                call cls_close
                ld hl,sl_regs
sll_r:          ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                or e
                jr z,sll_b7
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                push hl
                ex de,hl
                ld a,(sl_h)
                call f_read_n
                pop hl
                jr sll_r
sll_b7:         ld a,(sl_h)
                ld hl,$E000
                ld bc,$2000
                call f_read_n
                ld a,(sl_h)
                call f_close
                ld hl,sl_live           ; lo que no se restaura vuelve a su sitio
                ld de,SL_LIVE
sun_l:          ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,b
                or c
                jr z,sun_e
                ld a,(hl)
                inc hl
                push hl
                push bc
                ld c,a
                ld b,0
                ld h,d
                ld l,e
                pop de
                ldir
                ex de,hl
                pop hl
                jr sun_l
sun_e:          call aq_init            ; sprites: la cache de firma y los contadores de poses
                ld a,(CURROOM)          ; la sala se vuelve a pintar (con los objetos que dice OBJST) y los actores esperan dos fotogramas
                ld (EVARGS),a
                ld a,EV_ROOM_LOAD
                call ev_handler
                ld a,EV_PALETTE
                call ev_handler
                ld hl,255               ; las filas de mensajes de arriba, borradas
                ld (EVARGS),hl
                ld a,EV_TEXT
                call ev_handler
                ld a,EV_VERB            ; verbos y objetos se vuelven a componer
                call ev_handler
                ld a,EV_OBJSTATE
                call ev_handler
                call sl_snd
                ld a,(CUR)              ; el script en marcha sigue por su ranura restaurada
                cp $FF
                call nz,load_slot
                ld hl,3
                ret
sll_bad:        ld a,(sl_h)
                call f_close
                ld hl,5
                ret

; el sonido para y vuelve a empezar el que sonaba (el estado del reproductor viene del fichero)
sl_snd:         call sd_stopvgm
                ld a,(sd_cur)
                or a
                ret z
                ld (sd_nn),a
                ld a,(WINPG)
                push af
                ld a,(sd_nn)
                call sd_idx             ; B prioridad, C banderas; carry si no existe (cambia la ventana de datos)
                jr c,sl_s0
                ld a,c
                ld (sd_nf),a
                pop af
                call map_phys
                jp sc_nt                ; parar, bucle y PLAY_VGM
sl_s0:          pop af
                jp map_phys

; ---------------------------------------------------------------- nombres de las partidas (saveLoadVars 2 al cargar)
; OVC_NAME1: SC+9 = id de cadena que existe (call_ovc pisa A); SC+4 = el primer id del rango (a). La cadena a + k - 1 recibe el nombre de la partida k (los caracteres
; fuera de 32-122 y el 64, como "_"), o queda vacia si la partida no existe
sl_name1:       ld a,(SC+9)
                ld (slp_sid),a
                ld b,a
                ld a,(SC+4)
                ld c,a
                ld a,b
                sub c
                inc a                   ; ranura = id - a + 1
                jr z,slp_none
                cp 32
                jr nc,slp_none
                ld (sl_slot),a
                call sl_name
                ld hl,SL_NAME
                call f_open
                cp $FF
                jr z,slp_none
                ld (sl_h),a
                ld hl,SL_TMP
                ld bc,50
                call f_read_n
                ld a,(sl_h)
                call f_close
                call sl_strp            ; HL = destino, C = longitud
                ret z
                ex de,hl
                ld hl,SL_NM
                ld a,c
                sub 2
                jr nc,slp_n
                xor a
slp_n:           ld b,a                  ; hasta longitud - 2 caracteres
                or a
                jr z,slp_end
slp_l:           ld a,(hl)
                or a
                jr z,slp_end
                cp 32
                jr c,slp_sub
                cp 123
                jr nc,slp_sub
                cp 64
                jr nz,slp_ok
slp_sub:         ld a,'_'
slp_ok:          ld (de),a
                inc hl
                inc de
                djnz slp_l
slp_end:         xor a
                ld (de),a
                ret
slp_none:        call sl_strp
                ret z
                ld (hl),0
                ret

; ---------------------------------------------------------------- ficheros (de V2/ENGINE/save.asm)
; HL = nombre acabado en 0 -> A = manejador ($FF si no se puede crear): crea el fichero o lo vacia
f_create:       ld b,0
                push hl
fcr_l:          ld a,(hl)
                or a
                jr z,fcr_e
                inc hl
                inc b
                jr fcr_l
fcr_e:          pop hl
                ld a,CMD_FCREATE
                call mcu_send
                ld a,b
                call mcu_send
                inc b
                jr fcr_t
fcr_s:          ld a,(hl)
                inc hl
                call mcu_send
fcr_t:          djnz fcr_s
                jp mcu_recv

; A = manejador, HL = origen, BC = cuantos (cualquier cantidad): en trozos de CHUNK; wr_err pasa a distinto de 0 si el MCU rechaza alguno
f_write_n:      ld (wr_h),a
                ld (wr_src),hl
                ld (wr_cnt),bc
fwn_l:          ld bc,(wr_cnt)
                ld a,b
                or c
                ret z
                ld hl,CHUNK
                or a
                sbc hl,bc
                jr c,fwn_full
                ld d,b
                ld e,c
                jr fwn_go
fwn_full:       ld de,CHUNK
fwn_go:         push de
                ld a,CMD_FWRITE
                call mcu_send
                ld a,(wr_h)
                call mcu_send
                ld a,e
                call mcu_send
                ld a,d
                call mcu_send
                ld hl,(wr_src)
fwn_b:          ld a,(hl)
                inc hl
                call mcu_send
                dec de
                ld a,d
                or e
                jr nz,fwn_b
                ld (wr_src),hl
                call mcu_recv
                ld hl,wr_err
                or (hl)
                ld (hl),a
                pop de
                ld hl,(wr_cnt)
                or a
                sbc hl,de
                ld (wr_cnt),hl
                jr fwn_l
