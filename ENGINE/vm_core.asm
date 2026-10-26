; vm.asm - nucleo residente del interprete SCUMM v2 para el SD81 Booster
;
; Despachador guiado por tabla, ranuras de script, variables, estados de objeto y control de scripts.
; Todo lo que no es control (actores, texto, sonido...) sale por el puerto $F1 del anfitrion (en el
; arnes de PC lo recoge test_vm.cpp; en la placa seran manejadores en los overlays).
; Semantica: transcrita de ScummVM (script.cpp, script_v2.cpp, script_v5.cpp); ver
; SCUMM/TOOLS/vmmodel.py, que es el modelo de referencia con el que se compara.
; Diseno: claude/planning/scumm_interprete.md
;
; Ensamblar con pasmo:  pasmo vm.asm vm.bin vm.sym   (tables.inc lo genera
; SCUMM/TOOLS/gen_vmtables.py)

NSLOT           equ 24          ; ranuras de script (ScummVM usa 80; el maximo medido es 3)
MAXNEST         equ 15
SS_DEAD         equ 0
SS_PAUSED       equ 1
SS_RUNNING      equ 2
WIO_ROOM        equ 1
WIO_GLOBAL      equ 2
WIO_LOCAL       equ 3
E_NOSLOT        equ 1
E_NEST          equ 2
E_RANGE         equ 3
E_NOSCRIPT      equ 4
E_BADOBJ        equ 5
NOBJ            equ 780         ; objetos globales
SCRIPT_NUM_EXCD equ 10001
SCRIPT_NUM_ENCD equ 10002

; ---- datos (bloque 7, siempre mapeado)
VARS            equ $E000       ; 256 variables de 16 bits
                include "vars_v2.inc"
OBJST           equ $E200       ; estado de cada objeto (780)
PF_OPEN         equ PROF+40     ; perfil del juego: dos objetos (u16, 0 = ninguno) que getState da siempre por abiertos (bit 8 del estado)
ACTN            equ $971E       ; byte: cuantos numeros (0..ACTN-1) son actores y no objetos; NACTORS salvo que el perfil diga otra cosa
WINPG           equ $971F       ; byte: la pagina fisica que tiene la ventana de datos (map_phys)
PF_ACT          equ PROF+44     ; perfil: numero de ids de actor (0 = NACTORS)
OBJOWN          equ $E520       ; dueno de cada objeto (780)
SLOTS           equ $E900       ; NSLOT x 16
; ranura: +0 estado, +1 donde, +2/+3 numero, +4 pagina, +5/+6 puntero, +7..+10 retardo (32 bits con signo)
NEST            equ $EA80       ; MAXNEST x 4: numero(2), donde, ranura
ARGS            equ $EAC0       ; operandos ya resueltos (16 palabras)
CUR             equ $EB00       ; ranura en ejecucion o $FF
SPTR            equ $EB01       ; puntero del script (direccion logica en la ventana del bloque 4)
OPC             equ $EB03       ; opcode en curso
NESTN           equ $EB04
ARGN            equ $EB05       ; numero de operandos
HRES            equ $EB06       ; resultado del anfitrion (palabra)
HFLAG           equ $EB08       ; indicador del anfitrion
FRAMECNT        equ $EB09       ; palabra: lo pone el anfitrion
ERR             equ $EB0B
DELTA           equ $EB0C
SENTNUM         equ $EB0D       ; _sentenceNum
APIW            equ $EB10       ; parametros de las entradas: donde, numero, pagina, direccion, verbo
APIN            equ $EB11
APIP            equ $EB13
APIA            equ $EB14
APIVERB         equ $EB16
RAI             equ $EB17
RNTMP           equ $EB18
SVRV            equ $EB19
SVRN            equ $EB1A
SCRATCH_END     equ $EC00
SCRDIR          equ $EC00       ; 256 x 3: pagina, direccion (0 = sin script)
HOSTPORT        equ $F1
WINBLK          equ 1           ; bloque de la ventana de datos: $2000-$37FF (6 KB de cada pagina)
WINDOW          equ $2000

                org $4200

; ---- entradas para el arnes / el resto del juego
                jp vm_init
                jp vm_run_ext
                jp vm_run_object
                jp vm_run_script
                jp vm_frame
                jp vm_load_room
                jp ENTRY_POINT          ; $4212 = 16914: entrada del programa de la placa (RAND USR 16914; en las pruebas del PC, la instruccion siguiente)

; ============================================================================================ API
vm_init:
                ld hl,VARS
                ld (hl),0
                ld de,VARS+1
                ld bc,511
                ldir
                ld hl,SLOTS
                ld (hl),0
                ld de,SLOTS+1
                ld bc,SCRATCH_END-SLOTS-1
                ldir
                ld a,$FF
                ld (CUR),a
                ld hl,ACTORS                    ; initActor(-1) de los 25 actores
                ld (hl),0
                ld de,ACTORS+1
                ld bc,NACTORS*ASIZE-1
                ldir
                xor a
                ld (NBOXES),a
                ld (NOBJS),a
                call act_init
                ld ix,ACTORS
                ld b,NACTORS
                ld c,0
vi_act:
                ld (ix+6),180
                ld (ix+12),180
                ld (ix+11),15
                ld (ix+15),c
                inc c
                ld de,ASIZE
                add ix,de
                djnz vi_act
                ld hl,$ACE1
                ld (RNDST),hl
                xor a
                ld (GD_RAW),a           ; fuera de la zona que limpia vm_init: en la placa no empieza a cero
                ld (CO_N),a
                ld hl,ev_null
                ld (EVVEC),hl
                ld hl,host_null
                ld (HOSTVEC),hl
                ret

; ejecuta una ranura nueva: APIW (donde), APIN (numero), APIP (pagina), APIA (direccion del codigo)
vm_run_ext:
                jp start_new_slot

vm_run_script:
                ld de,(APIN)
                jp run_script

; objeto: APIN (id), APIP (pagina), APIA (bloque OBCD), APIVERB
vm_run_object:
                call alloc_slot         ; runObjectScript pide la ranura antes de buscar el verbo
                ret c
                ld a,(APIP)
                call map_page
                ld hl,(APIA)
                ld de,15
                add hl,de
vro_loop:
                ld a,(hl)
                or a
                ret z                   ; el verbo no esta
                ld c,a
                ld a,(APIVERB)
                cp c
                jr z,vro_found
                ld a,c
                cp $FF
                jr z,vro_found
                inc hl
                inc hl
                jr vro_loop
vro_found:
                inc hl
                ld a,(hl)
                or a
                ret z                   ; offset 0: nada
                ld e,a
                ld d,0
                ld hl,(APIA)
                add hl,de
                ld (APIA),hl
                ld a,WIO_ROOM
                ld (APIW),a
                jp start_new_slot

vm_frame:                               ; un fotograma de scummLoop: retardos, mensaje, variables y scripts
                ld a,(DELTA)
                cp 16
                jr c,vf_ok
                ld a,15
                ld (DELTA),a
vf_ok:
                call decrease_delay
                ld a,(DELTA)
                ld e,a
                ld d,0
                ld hl,(TALKDLY)
                or a
                sbc hl,de
                jr nc,vf_t
                ld hl,0
vf_t:
                ld (TALKDLY),hl
                call display_dialog
                ld a,(ERR)
                or a
                ret nz
                ld a,(HAVEMSG)
                ld l,a
                ld h,0
                ld (VAR_HAVE_MSG),hl          ; VAR_HAVE_MSG
                call process_input      ; el clic o la tecla pendiente: script 4
                ld a,(ERR)
                or a
                ret nz
                call check_sentence     ; la frase que espera: script 2
                ld a,(ERR)
                or a
                ret nz
                call run_all
                ld a,(ERR)
                or a
                ret nz
                ld a,(CURROOM)
                or a
                ret z
                jp walk_actors

; ============================================================================================ ranuras
slot_addr:                              ; A = ranura -> HL (conserva DE)
                ld l,a
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

map_page:       jp map_page_x           ; A = pagina de datos -> ventana de datos (bloque WINBLK). En el programa completo es la cache por demanda de
                                        ; loader.asm; en el nucleo de pruebas (vm.asm) es map_phys: la pagina fisica tal cual
map_phys:       ld b,a
                ld (WINPG),a            ; la pagina que hay en la ventana de datos (la sala la asoma un momento: hr.asm)
                ld c,$E7
                ld a,WINBLK
                out (c),a
                ret

load_slot:                              ; A = ranura: CUR, SPTR y la pagina de su script
                ld (CUR),a
                call slot_addr
                inc hl
                inc hl
                inc hl
                inc hl
                ld a,(hl)
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (SPTR),de
                jp map_page

update_ptr:                             ; updateScriptPtr: el puntero vuelve a la ranura
                ld a,(CUR)
                cp $FF
                ret z
                call slot_addr
                ld de,5
                add hl,de
                ld de,(SPTR)
                ld (hl),e
                inc hl
                ld (hl),d
                ret

break_here:
                call update_ptr
                ld a,$FF
                ld (CUR),a
                ret

alloc_slot:                             ; getScriptSlot: A = ranura libre (HL = su direccion), o ERR y carry
                ld hl,SLOTS+16
                ld b,NSLOT-1
                ld c,1
as_loop:
                ld a,(hl)
                or a
                jr z,as_found
                ld de,16
                add hl,de
                inc c
                djnz as_loop
                ld a,E_NOSLOT
                ld (ERR),a
                scf
                ret
as_found:
                ld a,c
                or a
                ret

start_slot_at:                          ; como start_new_slot, pero en la ranura A (se reutiliza)
                push af
                call slot_addr
                jr sns_fill
start_new_slot:                         ; crea la ranura con APIW/APIN/APIP/APIA y la ejecuta anidada
                call alloc_slot
                ret c
                push af
sns_fill:       ld (hl),SS_RUNNING
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
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                pop af
                jp run_nested

; runScriptNested: A = ranura nueva (ya rellena)
run_nested:
                ld (RNTMP),a
                call update_ptr
                ld a,(NESTN)
                cp MAXNEST
                jr c,rn_ok
                ld a,E_NEST
                ld (ERR),a
                ret
rn_ok:
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,NEST
                add hl,de
                push hl
                pop ix                  ; IX = entrada de anidamiento
                ld a,(CUR)
                cp $FF
                jr nz,rn_parent
                ld (ix+0),0
                ld (ix+1),0
                ld (ix+2),$FF
                ld (ix+3),$FF
                jr rn_go
rn_parent:
                ld c,a
                call slot_addr          ; HL = ranura padre
                inc hl
                ld a,(hl)
                ld (ix+2),a             ; donde
                inc hl
                ld a,(hl)
                ld (ix+0),a             ; numero
                inc hl
                ld a,(hl)
                ld (ix+1),a
                ld (ix+3),c             ; ranura
rn_go:
                ld hl,NESTN
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
rn_nodec:
                pop hl                  ; entrada
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                or e
                jr z,rn_none            ; sin padre (o lo han matado)
                ld b,(hl)               ; donde
                inc hl
                ld c,(hl)               ; ranura
                ld a,c
                call slot_addr
                ld a,(hl)
                or a
                jr z,rn_none
                inc hl
                ld a,(hl)
                cp b
                jr nz,rn_none
                inc hl
                ld a,(hl)
                cp e
                jr nz,rn_none
                inc hl
                ld a,(hl)
                cp d
                jr nz,rn_none
                ld a,c
                jp load_slot            ; el padre sigue donde estaba
rn_none:
                ld a,$FF
                ld (CUR),a
                ret

; stopScript: DE = numero
stop_script:
                ld a,d
                or e
                ret z
                ld ix,SLOTS
                ld b,NSLOT
                ld c,0
ss_loop:
                ld a,(ix+2)
                cp e
                jr nz,ss_next
                ld a,(ix+3)
                cp d
                jr nz,ss_next
                ld a,(ix+0)
                or a
                jr z,ss_next
                ld a,(ix+1)
                cp WIO_GLOBAL
                jr z,ss_kill
                cp WIO_LOCAL
                jr nz,ss_next
ss_kill:
                xor a
                ld (ix+0),a
                ld (ix+2),a
                ld (ix+3),a
                ld a,(CUR)
                cp c
                jr nz,ss_next
                ld a,$FF
                ld (CUR),a
ss_next:
                push de
                ld de,16
                add ix,de
                pop de
                inc c
                djnz ss_loop
                ld a,(NESTN)
                or a
                ret z
                ld b,a
                ld ix,NEST
sn_loop:
                ld a,(ix+0)
                cp e
                jr nz,sn_next
                ld a,(ix+1)
                cp d
                jr nz,sn_next
                ld a,(ix+2)
                cp WIO_GLOBAL
                jr z,sn_kill
                cp WIO_LOCAL
                jr nz,sn_next
sn_kill:
                xor a
                ld (ix+0),a
                ld (ix+1),a
                ld a,$FF
                ld (ix+2),a
                ld (ix+3),a
sn_next:
                inc ix
                inc ix
                inc ix
                inc ix
                djnz sn_loop
                ret

; isScriptRunning: DE = numero -> A = 1/0
is_script_running:
                ld ix,SLOTS
                ld b,NSLOT
isr_loop:
                ld a,(ix+2)
                cp e
                jr nz,isr_next
                ld a,(ix+3)
                cp d
                jr nz,isr_next
                ld a,(ix+0)
                or a
                jr z,isr_next
                ld a,(ix+1)
                cp WIO_GLOBAL
                jr z,isr_yes
                cp WIO_LOCAL
                jr z,isr_yes
isr_next:
                push de
                ld de,16
                add ix,de
                pop de
                djnz isr_loop
                xor a
                ret
isr_yes:
                ld a,1
                ret

; isScriptInUse: DE = numero -> A = 1/0 (cualquier ranura con ese numero)
is_script_in_use:
                ld ix,SLOTS
                ld b,NSLOT
isu_loop:
                ld a,(ix+2)
                cp e
                jr nz,isu_next
                ld a,(ix+3)
                cp d
                jr z,isu_yes
isu_next:
                push de
                ld de,16
                add ix,de
                pop de
                djnz isu_loop
                xor a
                ret
isu_yes:
                ld a,1
                ret

; runScript: DE = numero del script global (no recursivo)
run_script:
                ld a,d
                or e
                ret z
                ld (APIN),de
                push de
                call stop_script
                pop de
                ld a,d
                or a
                jr nz,rs_missing
                ld l,e
                ld h,0
                ld c,e
                ld b,0
                add hl,hl
                add hl,bc
                ld bc,SCRDIR
                add hl,bc
                ld a,(hl)
                or a
                jr z,rs_missing
                ld (APIP),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (APIA),de
                ld a,WIO_GLOBAL
                ld (APIW),a
                jp start_new_slot
rs_missing:
                ld a,E_NOSCRIPT
                ld (ERR),a
                ret

cur_number:                             ; HL = numero de la ranura en curso (conserva DE)
                ld a,(CUR)
                call slot_addr
                inc hl
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ret

stop_object_code:                       ; stopObjectCode de v2
                ld a,(CUR)
                call slot_addr
                push hl
                inc hl
                ld a,(hl)
                cp WIO_GLOBAL
                jr z,soc_g
                cp WIO_LOCAL
                jr z,soc_g
                pop hl                  ; objeto o sala: numero 0 y muerta
                xor a
                ld (hl),a
                inc hl
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                jr soc_end
soc_g:
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                pop hl
                call stop_script
soc_end:
                ld a,$FF
                ld (CUR),a
                ret

decrease_delay:                         ; decreaseScriptDelay(DELTA)
                ld ix,SLOTS
                ld b,NSLOT
dd_loop:
                ld a,(ix+0)
                cp SS_PAUSED
                jr nz,dd_next
                ld a,(DELTA)
                ld c,a
                ld a,(ix+7)
                sub c
                ld (ix+7),a
                ld a,(ix+8)
                sbc a,0
                ld (ix+8),a
                ld a,(ix+9)
                sbc a,0
                ld (ix+9),a
                ld a,(ix+10)
                sbc a,0
                ld (ix+10),a
                jp p,dd_next
                ld (ix+0),SS_RUNNING
                xor a
                ld (ix+7),a
                ld (ix+8),a
                ld (ix+9),a
                ld (ix+10),a
dd_next:
                ld de,16
                add ix,de
                djnz dd_loop
                ret

run_all:                                ; runAllScripts
                ld a,$FF
                ld (CUR),a
                xor a
                ld (RAI),a
ra_loop:
                ld a,(RAI)
                cp NSLOT
                ret nc
                call slot_addr
                ld a,(hl)
                cp SS_RUNNING
                jr nz,ra_next
                ld a,(RAI)
                call load_slot
                call exec_script
                ld a,(ERR)
                or a
                ret nz
ra_next:
                ld hl,RAI
                inc (hl)
                jr ra_loop

; ============================================================================================ el bucle
exec_script:
es_loop:
                ld a,(ERR)
                or a
                jr z,es_noerr
                ld a,$FF
                ld (CUR),a
                ret
es_noerr:
                ld a,(CUR)
                cp $FF
                ret z
                ld hl,(SPTR)
                ld a,(hl)
                inc hl
                ld (OPC),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,disp_table
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = especificacion
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)               ; BC = manejador
                ld hl,es_loop
                push hl
                push bc
                ld hl,(SPTR)
                inc hl                  ; tras el opcode
                call decode
                ld (SPTR),hl
                ret                     ; salta al manejador; su ret vuelve a es_loop

; ---- decodificacion de operandos: DE = especificacion, HL = puntero -> HL; deja ARGS y ARGN
decode:
                ld ix,ARGS
dc_next:
                ld a,(de)
                inc de
                or a
                jp z,dc_end
                cp 15
                jr z,dc_special
                cp 3
                jr c,dc_rv
                cp 9
                jr c,dc_bw
                cp 11
                jr c,dc_imm
                jr z,dc_jump
                ld c,a                  ; 12 S, 13 N
                call scan_str
dc_put:
                ld (ix+0),c
                ld (ix+1),b
                inc ix
                inc ix
                jr dc_next
dc_rv:
                cp 2
                ld a,(hl)
                inc hl
                jr z,dc_v
                ld c,a                  ; R: el numero de variable
                ld b,0
                jr dc_put
dc_v:
                call read_var
                jr dc_put
dc_bw:
                sub 3
                ld c,0
                cp 3
                jr c,dc_bw1
                sub 3
                ld c,1                  ; palabra
dc_bw1:
                ld b,$80
                or a
                jr z,dc_bw2
                ld b,$40
                cp 1
                jr z,dc_bw2
                ld b,$20
dc_bw2:
                ld a,(OPC)
                and b
                jr nz,dc_bwvar
                ld a,c
                or a
                ld c,(hl)
                inc hl
                ld b,0
                jr z,dc_put
                ld b,(hl)
                inc hl
                jr dc_put
dc_bwvar:
                ld a,(hl)
                inc hl
                call read_var
                jr dc_put
dc_imm:
                cp 10
                ld c,(hl)
                inc hl
                ld b,0
                jr nz,dc_put
                ld b,(hl)
                inc hl
                jr dc_put
dc_jump:
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                push hl
                add hl,bc
                ld c,l
                ld b,h
                pop hl
                jr dc_put
dc_special:
                ld a,(de)
                inc de
                ld c,a
                ld a,(de)
                inc de
                ld b,a
                push de
                ld de,dc_spret
                push de
                push bc
                ret                     ; salta a la rutina: HL = puntero, IX = ARGS
dc_spret:
                pop de
                jp dc_next
dc_end:
                push ix
                pop bc
                ld a,c
                sub ARGS & $FF
                srl a
                ld (ARGN),a
                ret

; ---- subrutinas de lectura (HL = puntero del script)
get_b:                                  ; B = mascara -> BC = byte directo o variable
                ld a,(OPC)
                and b
                jr nz,gb_var
                ld c,(hl)
                inc hl
                ld b,0
                ret
gb_var:
                ld a,(hl)
                inc hl
                jp read_var
get_w:                                  ; B = mascara -> BC = palabra directa o variable
                ld a,(OPC)
                and b
                jr nz,gb_var
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ret
fetch_byte_bc:
                ld c,(hl)
                inc hl
                ld b,0
                ret
emit_bc:
                ld (ix+0),c
                ld (ix+1),b
                inc ix
                inc ix
                ret

; cadena: C = 12 (dialogo: un byte con (c & 0x7F) en 4..7 lleva otro) o 13 (cruda) -> BC = valor
scan_str:
                ld (STRP),hl
                push de
                ld de,0
ss_l:
                ld a,(hl)
                inc hl
                or a
                jr z,ss_end
                push af
                call ss_acc
                pop af
                ld b,a
                ld a,c
                cp 12
                jr nz,ss_l
                ld a,b
                and $7F
                cp 4
                jr c,ss_l
                cp 8
                jr nc,ss_l
                ld a,(hl)
                inc hl
                call ss_acc
                jr ss_l
ss_end:
                ld c,e
                ld b,d
                pop de
                ret
ss_acc:                                 ; DE = DE + A + 257
                push bc
                ld c,a
                ld b,1
                ex de,hl
                add hl,bc
                inc hl
                ex de,hl
                pop bc
                ret

; ---- decodificadores propios (HL = puntero, IX = ARGS; pueden usar A, BC, DE)
dec_actorops:
                ld b,$80
                call get_b
                call emit_bc
                ld b,$40
                call get_b
                call emit_bc
                call fetch_byte_bc
                call emit_bc            ; subopcode
                ld a,c
                cp 2
                jr nz,dao_1
                call fetch_byte_bc
                jp emit_bc
dao_1:
                cp 3
                ret nz
                ld c,13
                call scan_str
                jp emit_bc

dec_verbops:
                call fetch_byte_bc
                call emit_bc            ; verbo
                ld a,c
                or a
                jr z,dv_0
                cp $FF
                jr z,dv_ff
                call fetch_byte_bc
                call emit_bc
                call fetch_byte_bc
                call emit_bc
                ld b,$80
                call get_b
                call emit_bc
                call fetch_byte_bc
                call emit_bc
                ld c,13
                call scan_str
                jp emit_bc
dv_0:
                ld b,$80
                call get_b
                jp emit_bc
dv_ff:
                call fetch_byte_bc
                call emit_bc
                call fetch_byte_bc
                jp emit_bc

dec_dosentence:
                ld b,$80
                call get_b
                call emit_bc
                ld a,b
                or a
                jr nz,dds_long
                ld a,c
                cp $FB
                ret z
                cp $FC
                ret z
dds_long:
                ld b,$40
                call get_w
                call emit_bc
                ld b,$20
                call get_w
                call emit_bc
                call fetch_byte_bc
                jp emit_bc

dec_pseudoroom:
                call fetch_byte_bc
                call emit_bc
dp_loop:
                call fetch_byte_bc
                ld a,c
                or a
                ret z
                call emit_bc
                jr dp_loop

; ============================================================================================ variables
var_addr:                               ; A = variable -> HL (conserva DE)
                ld l,a
                ld h,0
                add hl,hl
                push de
                ld de,VARS
                add hl,de
                pop de
                ret

read_var:                               ; readVar de v2: A = variable -> BC = valor (conserva HL, DE)
                push hl
                ld l,a
                ld h,0
                add hl,hl
                ld bc,VARS
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)
                cp 14
                jr c,rv_done
                cp 17
                jr nc,rv_done
                ld l,c                  ; las variables 14-16 son punteros a otra variable
                ld h,0
                add hl,hl
                ld bc,VARS
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)
rv_done:
                pop hl
                ret

write_var:                              ; writeVar: A = variable, BC = valor (conserva HL, DE)
                push hl
                push af
                cp 40                   ; VAR_CUTSCENEEXIT_KEY: 4, 13 y 64 se convierten en 27
                jr nz,wv_store
                ld a,b
                or a
                jr nz,wv_store
                ld a,c
                cp 4
                jr z,wv_27
                cp 13
                jr z,wv_27
                cp 64
                jr nz,wv_store
wv_27:
                ld bc,27
wv_store:
                pop af
                call var_addr
                ld (hl),c
                inc hl
                ld (hl),b
                pop hl
                ret

; ============================================================================================ manejadores del nucleo
h_o5_stopObjectCode:
                jp stop_object_code
h_o5_breakHere:
                jp break_here

h_o2_delay:                             ; operandos: b b b (retardo = $FFFFFF - valor)
                ld a,(CUR)
                call slot_addr
                push hl
                pop ix
                ld a,(ARGS)
                cpl
                ld (ix+7),a
                ld a,(ARGS+2)
                cpl
                ld (ix+8),a
                ld a,(ARGS+4)
                cpl
                ld (ix+9),a
                xor a
                ld (ix+10),a
                ld (ix+0),SS_PAUSED
                jp break_here

h_o5_delayVariable:
                ld a,(CUR)
                call slot_addr
                push hl
                pop ix
                ld hl,(ARGS)
                ld (ix+7),l
                ld (ix+8),h
                ld a,h
                rla
                sbc a,a                 ; extension de signo
                ld (ix+9),a
                ld (ix+10),a
                ld (ix+0),SS_PAUSED
                jp break_here

; saltos: ARGS = valores y, al final, el destino. cond falsa -> salta.
do_jump3:       ld hl,(ARGS+4)
                ld (SPTR),hl
                ret
do_jump2:       ld hl,(ARGS+2)
                ld (SPTR),hl
                ret
h_o5_jumpRelative:
                ld hl,(ARGS)
                ld (SPTR),hl
                ret
h_o5_equalZero:                         ; cond: a == 0
                ld hl,(ARGS)
                ld a,h
                or l
                ret z
                jr do_jump2
h_o5_notEqualZero:                      ; cond: a != 0
                ld hl,(ARGS)
                ld a,h
                or l
                ret nz
                jr do_jump2
h_o5_isEqual:                           ; cond: b == a
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                ret z
                jr do_jump3
h_o5_isNotEqual:                        ; cond: b != a
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                jr z,do_jump3
                ret
h_o2_isGreater:                         ; cond: b > a (sin signo)
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                jr c,do_jump3
                jr z,do_jump3
                ret
h_o2_isGreaterEqual:                    ; cond: b >= a
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                jr c,do_jump3
                ret
h_o2_isLess:                            ; cond: b < a
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                jr nc,do_jump3
                ret
h_o2_isLessEqual:                       ; cond: b <= a
                ld hl,(ARGS+2)
                ld de,(ARGS)
                or a
                sbc hl,de
                ret c
                ret z
                jr do_jump3

; variables
h_o5_move:
h_o2_assignVarByte:
                ld a,(ARGS)
                ld bc,(ARGS+2)
                jp write_var
h_o2_assignVarWordIndirect:
                ld a,(ARGS)
                call var_addr
                ld a,(hl)               ; _scummVars[n] es el numero de la variable de destino
                ld bc,(ARGS+2)
                jp write_var
h_o5_increment:
                ld a,(ARGS)
                push af
                call read_var
                inc bc
                pop af
                jp write_var
h_o5_decrement:
                ld a,(ARGS)
                push af
                call read_var
                dec bc
                pop af
                jp write_var
h_o2_add:
                ld a,(ARGS)
                jr add_common
h_o2_addIndirect:
                ld a,(ARGS)
                call var_addr
                ld a,(hl)
add_common:
                call var_addr
                ld e,(hl)
                inc hl
                ld d,(hl)
                dec hl
                push hl
                ex de,hl
                ld bc,(ARGS+2)
                add hl,bc
                ex de,hl
                pop hl
                ld (hl),e
                inc hl
                ld (hl),d
                ret
h_o2_subtract:
                ld a,(ARGS)
                jr sub_common
h_o2_subIndirect:
                ld a,(ARGS)
                call var_addr
                ld a,(hl)
sub_common:
                call var_addr
                ld e,(hl)
                inc hl
                ld d,(hl)
                dec hl
                push hl
                ex de,hl
                ld bc,(ARGS+2)
                or a
                sbc hl,bc
                ex de,hl
                pop hl
                ld (hl),e
                inc hl
                ld (hl),d
                ret
h_o5_setVarRange:                       ; ARGS: variable, cuenta; los valores siguen en el script
                ld a,(ARGS+2)
                or a
                jp z,bv_bad
                ld (SVRN),a
                ld a,(ARGS)
                ld (SVRV),a
svr_loop:
                ld hl,(SPTR)
                ld a,(OPC)
                and $80
                jr nz,svr_w
                ld c,(hl)
                inc hl
                ld b,0
                jr svr_put
svr_w:
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
svr_put:
                ld (SPTR),hl
                ld a,(SVRV)
                call write_var
                ld hl,SVRV
                inc (hl)
                ld hl,SVRN
                dec (hl)
                jr nz,svr_loop
                ret
bv_bad:
                ld a,E_RANGE
                ld (ERR),a
                ret
h_o2_getBitVar:                         ; ARGS: resultado, variable (palabra), B1
                ld hl,(ARGS+2)
                ld de,(ARGS+4)
                add hl,de
                ld a,l
                and 15
                ld b,a
                ld a,h
                cp 16
                jp nc,bv_bad
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                add hl,hl
                ld de,VARS
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,b
                or a
                jr z,gbv_0
gbv_l:
                srl d
                rr e
                djnz gbv_l
gbv_0:
                ld a,e
                and 1
                ld c,a
                ld b,0
                ld a,(ARGS)
                jp write_var
h_o2_setBitVar:                         ; ARGS: variable (palabra), B1, B2
                ld hl,(ARGS)
                ld de,(ARGS+2)
                add hl,de
                ld a,l
                and 15
                ld b,a
                ld a,h
                cp 16
                jp nc,bv_bad
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                add hl,hl
                ld de,VARS
                add hl,de
                ld de,1
                ld a,b
                or a
                jr z,sbv_1
sbv_l:
                sla e
                rl d
                djnz sbv_l
sbv_1:
                ld bc,(ARGS+4)
                ld a,b
                or c
                jr z,sbv_clear
                ld a,(hl)
                or e
                ld (hl),a
                inc hl
                ld a,(hl)
                or d
                ld (hl),a
                ret
sbv_clear:
                ld a,e
                cpl
                and (hl)
                ld (hl),a
                inc hl
                ld a,d
                cpl
                and (hl)
                ld (hl),a
                ret

; scripts
h_o2_startScript:
                ld de,(ARGS)
                ld a,d
                or a
                jr nz,hss_go
                ld a,e
                cp 87
                jr nz,hss_155
                push de                 ; no arrancar el 87 si corren el 88 o el 89
                ld de,88
                call is_script_running
                pop de
                or a
                ret nz
                push de
                ld de,89
                call is_script_running
                pop de
                or a
                ret nz
                jr hss_go
hss_155:
                cp 155
                jr nz,hss_go
                ld hl,(VARS+240)        ; variable 120
                dec hl
                ld a,h
                or l
                jr nz,hss_go
                ret
hss_go:
                jp run_script
h_o2_stopScript:
                ld de,(ARGS)
                ld a,d
                or e
                jr nz,hst_1
                call cur_number
                ex de,hl
hst_1:
                call cur_number
                or a
                sbc hl,de
                jp z,stop_object_code
                jp stop_script
h_o2_chainScript:
                ld de,(ARGS)
                push de
                call cur_number
                ex de,hl
                call stop_script
                ld a,$FF
                ld (CUR),a
                pop de
                jp run_script
h_o5_isScriptRunning:                   ; ARGS: resultado, script
                ld de,(ARGS+2)
                call is_script_running
                ld c,a
                ld b,0
                ld a,(ARGS)
                jp write_var
h_o2_waitForMessage:
                ld hl,(VAR_HAVE_MSG)          ; VAR_HAVE_MSG
                ld a,h
                or l
                ret z
                jr wait_back1
h_o2_waitForSentence:
                ld a,(SENTNUM)
                or a
                jr nz,wait_back1
                ld de,2
                call is_script_in_use
                or a
                ret z
wait_back1:
                ld hl,(SPTR)
                dec hl
                ld (SPTR),hl
                jp break_here
; estados de objeto
state_get:                              ; ARGS[0] = objeto -> HL = &estado, A = estado; error: carry y ERR
                ld hl,(ARGS)
                ld de,NOBJ
                or a
                sbc hl,de
                jr nc,sg_bad
                add hl,de
                ld de,OBJST
                add hl,de
                push hl
                ld de,(ARGS)
                ld hl,(PF_OPEN)
                call sg_cmp
                jr z,sg_hack
                ld hl,(PF_OPEN+2)
                call sg_cmp
                jr z,sg_hack
                pop hl
                jr sg_ok
act_init:       ld a,(PF_ACT)           ; ids de actor: los del perfil, o NACTORS si no dice
                or a
                jr nz,ai_ok
                ld a,NACTORS
ai_ok:          ld (ACTN),a
                ret

cp_act:         push hl                 ; compara A con el numero de ids de actor (flags como cp NACTORS)
                ld hl,ACTN
                cp (hl)
                pop hl
                ret

sg_cmp:         ld a,h                  ; Z si el objeto del perfil (HL, 0 = ninguno) es DE
                or l
                jr z,sg_cmpn
                or a
                sbc hl,de
                ret
sg_cmpn:        or 1
                ret
sg_hack:        pop hl
                bit 3,(hl)
                jr nz,sg_ok
                set 3,(hl)              ; getState lo da por abierto; se avisa para que se vuelva a dibujar
                push hl
                ld a,(hl)
                ld l,a
                ld h,0
                ld (EVARGS+2),hl
                ld hl,(ARGS)
                ld (EVARGS),hl
                ld a,EV_OBJSTATE
                call ev_emit
                pop hl
sg_ok:
                ld a,(hl)
                or a
                ret
sg_bad:
                ld a,E_BADOBJ
                ld (ERR),a
                scf
                ret
st_set:
                push bc
                call state_get
                pop bc
                ret c
                or c
                ld (hl),a
                jr st_event
st_clear:
                push bc
                call state_get
                pop bc
                ret c
                ld b,a
                ld a,c
                cpl
                and b
                ld (hl),a
st_event:                               ; avisa al programa: objeto y estado nuevo
                ld l,a
                ld h,0
                ld (EVARGS+2),hl
                ld hl,(ARGS)
                ld (EVARGS),hl
                ld a,EV_OBJSTATE
                jp ev_emit
st_zero:                                ; ifStateZeroCommon: salta si (estado & mascara) == 0
                push bc
                call state_get
                pop bc
                ret c
                and c
                ret nz
                jr st_jump
st_nonzero:                             ; ifStateNotZeroCommon: salta si (estado & mascara) != 0
                push bc
                call state_get
                pop bc
                ret c
                and c
                ret z
st_jump:
                ld hl,(ARGS+2)
                ld (SPTR),hl
                ret
h_o2_setStateIntrinsicOn:
                ld c,8
                jr st_set
h_o2_setStateIntrinsicOff:
                ld c,8
                jr st_clear
h_o2_setStateLocked:
                ld c,4
                jr st_set
h_o2_setStateUnlocked:
                ld c,4
                jr st_clear
h_o2_setStateUntouchable:
                ld c,2
                jr st_set
h_o2_setStateTouchable:
                ld c,2
                jr st_clear
h_o2_setStatePickupable:
                ld c,1
                jr st_set
h_o2_setStateUnpickupable:
                ld c,1
                jr st_clear
h_o2_ifStateIntrinsicOff:
                ld c,8
                jr st_zero
h_o2_ifStateIntrinsicOn:
                ld c,8
                jr st_nonzero
h_o2_ifStateUnlocked:
                ld c,4
                jr st_zero
h_o2_ifStateLocked:
                ld c,4
                jr st_nonzero
h_o2_ifStateTouchable:
                ld c,2
                jr st_zero
h_o2_ifStateUntouchable:
                ld c,2
                jr st_nonzero
h_o2_ifStatePickupable:
                ld c,1
                jr st_nonzero
h_o2_ifStateUnpickupable:
                ld c,1
                jr st_zero

; ---- el anfitrion (en el arnes de PC; en la placa seran los manejadores de los overlays)
h_host:
                ld a,(OPC)
                ld hl,(HOSTVEC)
                jp (hl)                 ; acaba con RET
host_null:      ret
h_host_r:
                ld a,(OPC)
                ld hl,(HOSTVEC)
                call call_hl
                ld a,(ARGS)
                ld bc,(HRES)
                jp write_var
call_hl:        jp (hl)

; ============================================================================================ tablas
                include "game.asm"
