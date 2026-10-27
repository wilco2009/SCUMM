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
;  Memoria: $4200-  codigo   $6800 variables  $6900 banderas  $6A00 ranura de cada logica  $6B00 inventario  $6C00 duracion de sonidos
;           $6E00 resumenes por ciclo   $7600 traza   $7F00 pila   $8000 ventana de la logica
; =====================================================================

                org 16896
                jp start
                defs 16914-$
                jp start                ; RAND USR 16914 (y el arnes de PC entran aqui)

SET_FAST        equ $02E7
SLOW_FAST       equ $0207
MAP_PORT        equ $E7
CMD_64C         equ $1C

VARS            equ $6800
FLAGS           equ $6900
LGSLOT          equ $6A00               ; logica -> ranura ($FF = no esta)
INV             equ $6B00               ; sala de cada objeto del inventario (255 = lo lleva el ego)
SNDLEN          equ $6C00               ; duracion de cada sonido en 1/60 s (u16)
SUMM            equ $6E00
SUMMAX          equ 200
TRACE           equ $7600
TRMAX           equ 680
STACK           equ $7F00
LWIN            equ $8000
LPAGE0          equ 16
NSLOTS          equ 8
MAXDEPTH        equ 12
ARGS            equ $5F00               ; argumentos del comando o la condicion en curso

                include "mcu.asm"

start:          di
                ld (sv_sp),sp
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
                call init
                ld a,(stopf)
                or a
                jp nz,finish

; ---------------------------------------------------------------------
;  El ciclo del interprete
; ---------------------------------------------------------------------
main_loop:      ld a,(pctl)
                or a
                jr z,ml_np
                xor a
                ld (VARS+6),a           ; v6 = direccion que pide el jugador (aun sin teclas)
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
ml_end:         xor a                   ; (aqui irian los objetos animados)
                ld (FLAGS+2),a
                ld (FLAGS+4),a
                ld (FLAGS+5),a
                ld (FLAGS+6),a
                ld (VARS+2),a
                ld (VARS+3),a
                ld (VARS+4),a
                ld (VARS+5),a
                call tick_clock
                call summary
                ld hl,(cyc)
                inc hl
                ld (cyc),hl
                ld a,(nsum)
                cp SUMMAX
                jp c,main_loop

finish:         ld bc,$7FEF
                ld a,$0C
                out (c),a
                ld a,CMD_64C
                call mcu_send
                ld a,(sv_i)
                ld i,a
                call SLOW_FAST
                ld sp,(sv_sp)
                ld bc,0
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
                ld hl,nm_inv
                ld de,INV
                ld bc,256
                call load_aux
                ld hl,nm_snd
                ld de,SNDLEN
                ld bc,512
                call load_aux
                ret

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
                ld hl,nm+3
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
                ld a,(de)               ; said: k palabras de 16 bits (aun sin parser: falsa)
                inc de
                add a,a
                ld l,a
                ld h,0
                add hl,de
                ex de,hl
                ld (ip),de
                xor a
                jr di_res
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
                ld hl,(trptr)
                ld a,(curlg)
                ld (hl),a
                inc hl
                ld (hl),e
                inc hl
                ld a,d
                sub LWIN>>8
                ld (hl),a
                inc hl
                ld (trptr),hl
ts_end:         pop de
                ret

; ---------------------------------------------------------------------
;  Sala nueva, reloj, resumen, sonidos
; ---------------------------------------------------------------------
do_new_room:    ld a,(VARS+0)
                ld (VARS+1),a
                ld a,(nr_val)
                ld (VARS+0),a
                xor a
                ld (VARS+3),a
                ld (VARS+4),a
                ld (VARS+5),a
                ld (VARS+2),a
                ld (FLAGS+0),a
                ld (nr_pend),a
                ld (exitall),a
                inc a
                ld (FLAGS+5),a
                ld (pctl),a
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

; ciclo, pasos, suma de variables, suma de los indices de las banderas puestas, sala: 9 bytes por ciclo
summary:        ld hl,(sptr)
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
                ld (sptr),hl
                ld hl,nsum
                inc (hl)
                ld hl,0
                ld (nsteps),hl
                ret

; sonidos cuyo final ya llego: ponen su bandera (se mira al empezar el ciclo)
snd_due:        ld hl,SNDP
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
h_stop_motion:  ld a,(ARGS)
                or a
                ret nz
                ld (VARS+6),a
                ld (pctl),a
                ret
h_start_motion: ld a,(ARGS)
                or a
                ret nz
                inc a
                ld (pctl),a
                ret
h_wander:       ld a,(ARGS)
                or a
                ret nz
                ld (pctl),a
                ret
h_move_obj:     ld a,(ARGS+4)
mo_f:           ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                ld a,(ARGS)
                or a
                ret nz
                ld (pctl),a
                ret
h_move_obj_v:   jr h_move_obj
h_follow_ego:   ld a,(ARGS+2)
                jr mo_flag
h_end_of_loop:  ld a,(ARGS+1)
mo_flag:        ld l,a
                ld h,FLAGS>>8
                ld (hl),0
                ret
h_reverse_loop: jr h_end_of_loop

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

h_get_num:      ld a,(ARGS+1)           ; sin teclado: 0
                ld l,a
                ld h,VARS>>8
                ld (hl),0
                ret
h_parse:        ld a,1
                ld (FLAGS+2),a
                xor a
                ld (VARS+9),a
                ret

h_quit:         ld a,1
                ld (stopf),a
                ret
h_restart_game: jr h_quit

; --- sonido: la bandera f se pone cuando acaba (duracion de la pista 0)
h_sound:        ld a,(ARGS+1)           ; f
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
                ld a,(ARGS)             ; t = SNDLEN[n]
                ld l,a
                ld h,0
                add hl,hl
                ld de,SNDLEN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; DE = t
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
                ret

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
                include "agitab.inc"

nm:             defb "LOG000.AGL",0
nm_inv:         defb "INVROOM.BIN",0
nm_snd:         defb "SNDLEN.BIN",0
sv_sp:          defw 0
sv_i:           defb 0
fh:             defb 0
errc:           defb 0
stopf:          defb 0
exitall:        defb 0
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
