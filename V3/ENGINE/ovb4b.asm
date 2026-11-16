; =====================================================================
;  ovb4b.asm - manejadores de la fase 4b-1 en el overlay B (se incluye desde ovlb.asm tras ovb4.asm): estados y clases, inventario,
;  cadenas, cursor y verbos, actorOps y los de sala y recursos que en el modelo completo son sobre todo del anfitrion.
;  Semantica: ScummVM tal como la transcribe V3/TOOLS/vmmodel3.py (CORE_OPS) + vmgame3.py. Mismas convenciones que ovb4.asm: se entra
;  por ovb_op con DE = puntero tras el opcode; los lectores del residente (rd_vb1...) devuelven BC; SPTR se deja antes de nada que pueda
;  correr un script (aqui nada lo hace); las temporales SC+n no sobreviven a un script anidado. Los ayudantes dicen si conservan DE.
; =====================================================================

; ---------------------------------------------------------------- estados de objeto (8 bits)
b_setState:     call rd_vw1             ; objeto
                push bc
                call rd_vb2             ; estado
                ld (SPTR),de
                pop hl
                call chk_obj_hl         ; E_BADOBJ
                ld a,b                  ; putState: 0..255
                or a
                jp nz,err_range
                push hl
                ld de,OBJST
                add hl,de
                ld (hl),c
                pop hl
                ld (EVARGS),hl
                ld (EVARGS+2),bc
                ld a,EV_OBJSTATE
                jp ev_emit

; ifState / ifNotState: la condicion verdadera no salta
get_st_cmp:     call rd_vw1             ; -> Z si el estado del objeto es igual al valor (con 16 bits); conserva DE
                push bc
                call rd_vb2
                pop hl
                push de
                call chk_obj_hl
                ld de,OBJST
                add hl,de
                ld a,(hl)
                pop de
                ld h,a
                ld a,b
                or a
                ret nz                  ; el valor no cabe en un byte: distinto
                ld a,h
                cp c
                ret
b_ifState:      call get_st_cmp
                jp z,no_jump
                jp do_jump
b_ifNotState:   call get_st_cmp
                jp nz,no_jump
                jp do_jump

; ---------------------------------------------------------------- clases de objeto (24 bits, con la traduccion de GF_SMALL_HEADER)
; cls_xlat: C = valor de la clase (bits 0-6) -> A = clase 1..24 (29 -> 18, 30 -> 19, 31 -> 23, 32 -> 24); E_RANGE si no
cls_xlat:       ld a,c
                and $7F
                jp z,err_range
                cp 33
                jp nc,err_range
                cp 29
                jr c,cx_lo
                cp 31
                jr nc,cx_h2
                sub 11
                ret
cx_h2:          sub 8
                ret
cx_lo:          cp 25                   ; los 24 bits de OBJCLS (el modelo da E_RANGE por encima)
                ret c
                jp err_range

; cls_addr: HL = objeto, A = clase 1..24 -> HL = el byte de OBJCLS EN LA VENTANA (con CLS_PG mapeada: cls_open), A = la mascara del bit (destruye BC, DE)
cls_addr:       dec a
                ld c,a
                ld e,l
                ld d,h
                add hl,hl
                add hl,de
                ld de,WINDOW
                add hl,de
                ld a,c
                rrca
                rrca
                rrca
                and $1F
                ld e,a
                ld d,0
                add hl,de
                ld a,c
                and 7
                ld b,a
                ld a,1
                inc b
ca_l:           dec b
                ret z
                add a,a
                jr ca_l

; putClass: HL = objeto, BC = valor de la clase (bit 7: activar); conserva DE. Usa SC+2, SC+3
put_class:      push de
                call chk_obj_hl
                push hl
                call cls_xlat
                ld (SC+2),a
                ld a,c
                and $80
                ld (SC+3),a
                ld a,(SC+2)
                call cls_addr
                ld b,a
                call cls_open
                ld a,(SC+3)
                or a
                ld a,b
                jr z,pc_off
                or (hl)
                ld (hl),a
                call cls_close
                jr pc_act
pc_off:         cpl
                and (hl)
                ld (hl),a
                call cls_close
pc_act:         pop hl                  ; Actor::classChanged: 1 <= objeto < NACT y la clase 22 (ignorar cajas)
                ld a,(SC+2)
                cp 22
                jr nz,pc_end
                ld a,h
                or a
                jr nz,pc_end
                ld a,l
                or a
                jr z,pc_end
                cp NACT
                jr nc,pc_end
                call actor_ix
                ld a,(SC+3)
                or a
                ld a,0
                jr z,pc_ig
                inc a
pc_ig:          ld (ix+A_IGNB),a
pc_end:         pop de
                ret

; getClass: HL = objeto, BC = valor de la clase -> Z si el bit esta a 0; conserva DE (destruye BC)
get_class:      push de
                call chk_obj_hl
                call cls_xlat
                call cls_addr
                ld b,a
                call cls_open
                ld a,b
                and (hl)
                ld b,a
                call cls_close
                ld a,b
                or a                    ; Z si el bit estaba a 0
                pop de
                ret

b_setClass:     call rd_vw1
                ld (SC+0),bc
sc_l:           ld a,(de)
                inc de
                ld (OPC),a
                inc a
                jr z,sc_end
                call rd_vw1
                ld a,b
                or c
                jr z,sc_zero
                ld hl,(SC+0)
                call put_class
                jr sc_l
sc_zero:        ld hl,(SC+0)            ; clase 0: se borran las clases del objeto (y, si es un actor, ignoreBoxes)
                push de
                call chk_obj_hl
                ld e,l
                ld d,h
                add hl,hl
                add hl,de
                ld de,WINDOW
                add hl,de
                call cls_open
                xor a
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                call cls_close
                ld hl,(SC+0)
                ld a,h
                or a
                jr nz,scz_e
                ld a,l
                cp NACT
                jr nc,scz_e
                call actor_ix
                ld (ix+A_IGNB),0
scz_e:          pop de
                jr sc_l
sc_end:         ld (SPTR),de
                ret

b_ifClassOfIs:  call rd_vw1
                ld (SC+0),bc
                ld a,1
                ld (SC+4),a             ; la condicion
ic_l:           ld a,(de)
                inc de
                ld (OPC),a
                inc a
                jr z,ic_end
                call rd_vw1
                ld (SC+2),bc
                ld hl,(SC+0)
                call get_class
                push af                 ; Z: el bit estaba a 0
                ld a,(SC+2)
                and $80
                ld b,a
                pop af
                jr z,ic_b0
                ld a,b                  ; el bit estaba a 1: falla si la clase no pedia "activada"
                or a
                jr nz,ic_l
ic_f:           xor a
                ld (SC+4),a
                jr ic_l
ic_b0:          ld a,b                  ; el bit estaba a 0: falla si la clase pedia "activada"
                or a
                jr nz,ic_f
                jr ic_l
ic_end:         ld a,(SC+4)
                or a
                jp nz,no_jump
                jp do_jump

; ---------------------------------------------------------------- inventario
; inv_scan: BC = dueno, DE = idx (0: solo contar) -> HL = el objeto que ocupa el lugar idx entre los del dueno (0 si no hay), SC+0 = cuantos son
inv_scan:       ld hl,0
                ld (SC+0),hl
                ld (SC+4),hl
                ld (SC+2),de
                ld a,b
                or a
                ret nz                  ; un dueno de mas de un byte no coincide con ninguno
                ld a,c
                ld (SC+6),a
                ld hl,INVSL
                ld b,NINV
is_l:           ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld a,d
                or e
                jr z,is_n
                push hl
                push bc
                ld hl,OBJOWN
                add hl,de
                ld a,(SC+6)
                cp (hl)
                jr nz,is_p
                ld hl,(SC+0)
                inc hl
                ld (SC+0),hl
                ld bc,(SC+2)
                or a
                sbc hl,bc
                jr nz,is_p
                ld (SC+4),de
is_p:           pop bc
                pop hl
is_n:           djnz is_l
                ld hl,(SC+4)
                ret

b_findInventory:
                call rd_res
                call rd_vb1
                push bc
                call rd_vb2
                ld (SPTR),de
                ld d,b
                ld e,c
                pop bc
                call inv_scan
                ld b,h
                ld c,l
                jp set_res

b_getInventoryCount:
                call rd_res
                call rd_vb1
                ld (SPTR),de
                ld de,0
                call inv_scan
                ld bc,(SC+0)
                jp set_res

b_getActorWidth:
                call get_prep
                ld c,(ix+A_WIDTH)
                ld b,0
                jp set_res

; ---------------------------------------------------------------- cadenas (stringOps, getStringWidth)
; Las cadenas viven en STRHEAP, una tras otra, sin huecos: STRLEN[id] (con su 0 final; 0 = no existe), STRPOS[id] y STREND (el fin
; de lo ocupado). Cambiar el tamano de una desplaza la cola (str_resize), asi que el total ocupado es siempre la suma de las longitudes.
; Los limites son los del modelo (vmcommon3: NUM_STRINGS, STR_HEAP, MAX_STRLEN). Temporales: SC+8..SC+17 (str_resize).

; str_chk: BC = id -> A = id; E_RANGE si no esta en 0..NSTR-1
str_chk:        ld a,b
                or a
                jp nz,err_range
                ld a,c
                cp NSTR
                jp nc,err_range
                ret

; str_chk_exist: BC = id -> A = id, HL = &STRLEN[id]; E_RANGE si no esta en 0..NSTR-1 o no existe
str_chk_exist:  call str_chk
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld a,(hl)
                or a
                jp z,err_range
                ld a,e
                ret

; str_ptr: A = id -> HL = direccion de la cadena en STRHEAP (destruye A, DE)
str_ptr:        ld e,a
                ld d,0
                ld hl,STRPOS
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,STRHEAP
                add hl,de
                ret

; scan_len: DE = principio de una cadena del script -> HL = su longitud en bytes con el 0 final (resStrLen), DE tras ella
scan_len:       ld hl,0
sl_l:           ld a,(de)
                inc de
                inc hl
                or a
                ret z
                inc a
                jr nz,sl_l
                ld a,(de)               ; $FF + codigo; salvo 1, 2, 3 y 8, dos bytes mas
                inc de
                inc hl
                or a
                jr z,sl_two
                cp 4
                jr c,sl_l
                cp 8
                jr z,sl_l
sl_two:         inc de
                inc de
                inc hl
                inc hl
                jr sl_l

; str_resize: A = id, BC = nueva longitud (0..255; 0 la borra) -> la cadena pasa a tener esa longitud (contenido de los bytes nuevos
; sin definir); las que estaban detras se desplazan. E_RANGE si no cabe en el monton. Destruye todo salvo IX
str_resize:     ld (SC+8),a
                ld (SC+10),bc
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld a,(hl)
                ld (SC+9),a             ; longitud de ahora
                or a
                jr nz,sr_have
                ld hl,(STREND)          ; nueva: va al final del monton
                ld (SC+12),hl
                ld hl,STRPOS
                add hl,de
                add hl,de
                ld bc,(STREND)
                ld (hl),c
                inc hl
                ld (hl),b
                jr sr_pos2
sr_have:        ld hl,STRPOS
                add hl,de
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld (SC+12),bc
sr_pos2:        ld hl,(SC+10)           ; delta = nueva - de ahora
                ld a,(SC+9)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                ld (SC+14),hl
                ld de,(STREND)          ; el total nuevo tiene que caber
                add hl,de
                ld de,STRMAX+1
                or a
                sbc hl,de
                jp nc,err_range
                ld hl,(SC+12)           ; la cola: de pos + longitud actual hasta STREND
                ld a,(SC+9)
                ld e,a
                ld d,0
                add hl,de
                ld de,(STREND)
                ex de,hl
                or a
                sbc hl,de
                ld b,h
                ld c,l                  ; BC = bytes de la cola
                ld a,b
                or c
                jr z,sr_moved
                ld hl,(SC+14)
                ld a,h
                or l
                jr z,sr_moved
                bit 7,h
                jr nz,sr_shrink
                push bc                 ; crece: la cola sube delta (de atras adelante)
                ld hl,(STREND)
                ld de,STRHEAP
                add hl,de
                dec hl
                ld de,(SC+14)
                push hl
                add hl,de
                ex de,hl
                pop hl
                pop bc
                lddr
                jr sr_moved
sr_shrink:      push bc                 ; se acorta: la cola baja
                ld hl,(SC+12)
                ld de,STRHEAP
                add hl,de
                ld de,(SC+10)
                add hl,de
                push hl                 ; destino
                ld hl,(SC+12)
                ld a,(SC+9)
                ld e,a
                ld d,0
                add hl,de
                ld de,STRHEAP
                add hl,de               ; origen
                pop de
                pop bc
                ldir
sr_moved:       ld ix,STRPOS            ; las cadenas que estaban detras se corren delta
                ld hl,STRLEN
                ld b,NSTR
sr_u:           ld a,(hl)
                or a
                jr z,sr_un
                ld e,(ix+0)
                ld d,(ix+1)
                push hl
                ld hl,(SC+12)
                or a
                sbc hl,de               ; carry: su posicion es mayor que la de esta
                jr nc,sr_up
                ld hl,(SC+14)
                add hl,de
                ld (ix+0),l
                ld (ix+1),h
sr_up:          pop hl
sr_un:          inc hl
                inc ix
                inc ix
                djnz sr_u
                ld hl,(STREND)
                ld de,(SC+14)
                add hl,de
                ld (STREND),hl
                ld a,(SC+8)
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld a,(SC+10)
                ld (hl),a
                ret

b_stringOps:    ld a,(de)
                inc de
                ld (OPC),a
                and $1F
                cp 1
                jr z,so_load
                cp 2
                jp z,so_copy
                cp 3
                jp z,so_setch
                cp 4
                jp z,so_getch
                cp 5
                jp z,so_create
                ld (SPTR),de            ; los demas subopcodes no hacen nada
                ret

so_load:        call rd_vb1             ; loadString: la cadena del script se copia al monton
                call str_chk
                ld (SC+0),a
                push de
                call scan_len
                ld (SPTR),de
                ld (SC+2),hl
                ld a,(SC+0)
                ld bc,0
                call str_resize         ; la vieja fuera
                ld hl,(SC+2)
                ld a,h
                or a
                jp nz,err_range         ; mas de 255 bytes
                ld c,l
                ld b,0
                ld a,(SC+0)
                call str_resize
                ld a,(SC+0)
                call str_ptr
                ex de,hl
                pop hl
                ld bc,(SC+2)
                ldir
                ret

so_copy:        call rd_vb1             ; copyString(a, b): a pasa a ser una copia de b (a == b: E_RANGE)
                push bc
                call rd_vb2
                ld (SPTR),de
                pop hl
                push hl
                or a
                sbc hl,bc
                pop hl
                jp z,err_range
                ld (SC+4),bc
                ld b,h
                ld c,l
                call str_chk
                ld (SC+0),a
                ld bc,0
                call str_resize         ; a se borra
                ld bc,(SC+4)            ; si b no existe, nada mas
                ld a,b
                or a
                ret nz
                ld a,c
                cp NSTR
                ret nc
                ld (SC+6),a
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld a,(hl)
                or a
                ret z
                ld (SC+2),a
                ld c,a
                ld b,0
                ld a,(SC+0)
                call str_resize
                ld a,(SC+6)
                call str_ptr
                push hl
                ld a,(SC+0)
                call str_ptr
                ex de,hl
                pop hl
                ld a,(SC+2)
                ld c,a
                ld b,0
                ldir
                ret

so_setch:       call rd_vb1             ; setStringChar(a, b, c): b < longitud + 2; si b >= longitud la cadena crece con ceros
                push bc
                call rd_vb2
                push bc
                call rd_vb3
                ld (SPTR),de
                ld a,c
                ld (SC+6),a
                pop bc
                ld (SC+4),bc
                pop bc
                call str_chk_exist      ; A = id, HL = &STRLEN[id]
                ld (SC+0),a
                ld a,(hl)
                ld (SC+2),a             ; longitud
                ld e,a
                ld d,0
                ld hl,(SC+4)
                or a
                sbc hl,de
                jr c,ss_set             ; b < longitud: se escribe sin mas
                inc de                  ; b >= longitud: crece solo si b < longitud + 2
                inc de
                ld hl,(SC+4)
                or a
                sbc hl,de
                ret nc                  ; b >= longitud + 2: nada
                ld hl,(SC+4)            ; crece hasta b + 1 bytes
                inc hl
                ld a,h
                or a
                jp nz,err_range
                ld c,l
                ld b,0
                ld a,(SC+0)
                call str_resize
                ld a,(SC+0)
                call str_ptr
                ld a,(SC+2)
                ld e,a
                ld d,0
                add hl,de
                ld a,(SC+4)
                inc a
                sub e
                ld b,a
                xor a
ss_z:           ld (hl),a
                inc hl
                djnz ss_z
ss_set:         ld a,(SC+0)
                call str_ptr
                ld de,(SC+4)
                add hl,de
                ld a,(SC+6)
                ld (hl),a
                ret

so_getch:       call rd_res             ; getStringChar: resultado, id, indice; fuera de la cadena da 0
                call rd_vb1
                push bc
                call rd_vb2
                ld (SPTR),de
                ld (SC+4),bc
                pop bc
                call str_chk_exist
                ld (SC+0),a
                ld a,(hl)
                ld e,a
                ld d,0
                ld hl,(SC+4)
                or a
                sbc hl,de
                ld bc,0
                jp nc,set_res
                ld a,(SC+0)
                call str_ptr
                ld de,(SC+4)
                add hl,de
                ld c,(hl)
                ld b,0
                jp set_res

so_create:      call rd_vb1             ; createString(a, b): b bytes a cero (b = 0: borrarla)
                push bc
                call rd_vb2
                ld (SPTR),de
                ld (SC+4),bc
                pop bc
                call str_chk
                ld (SC+0),a
                ld bc,(SC+4)
                ld a,b
                or a
                jp nz,err_range
                ld a,(SC+0)
                ld bc,0
                call str_resize
                ld a,(SC+4)
                or a
                ret z
                ld c,a
                ld b,0
                ld a,(SC+0)
                call str_resize
                ld a,(SC+0)
                call str_ptr
                ld a,(SC+4)
                ld b,a
                xor a
sc_z:           ld (hl),a
                inc hl
                djnz sc_z
                ret

b_getStringWidth:
                call rd_res
                call rd_vb1
                ld (SPTR),de
                call str_chk_exist
                ld b,(hl)               ; longitud (con el 0 final)
                call str_ptr
                ld de,0                 ; caracteres (CharsetRenderer::getStringWidth: hasta el primer 0; ni '@' ni los codigos $FF / $FE)
gw_l:           ld a,b
                or a
                jr z,gw_e
                ld a,(hl)
                inc hl
                dec b
                or a
                jr z,gw_e
                cp 10
                jr z,gw_e
                cp 13
                jr z,gw_e
                cp '@'
                jr z,gw_l
                cp 255
                jr z,gw_c
                cp 254
                jr nz,gw_n
gw_c:           ld a,b                  ; un codigo: el byte siguiente
                or a
                jr z,gw_e
                ld a,(hl)
                inc hl
                dec b
                cp 3
                jr z,gw_e
                cp 9
                jr z,gw_e
                cp 1
                jr z,gw_e
                cp 2
                jr z,gw_e
                cp 8
                jr z,gw_8
                cp 10
                jr z,gw_2
                cp 21
                jr z,gw_2
                cp 12
                jr z,gw_2
                cp 13
                jr z,gw_2
                cp 14
                jr z,gw_2
gw_n:           inc de                  ; otro codigo o un caracter: cuenta
                jr gw_l
gw_2:           ld a,b                  ; salta dos bytes
                sub 2
                jr c,gw_e
                ld b,a
                inc hl
                inc hl
                jr gw_l
gw_8:           ld a,b                  ; while (text[pos++] == ' ') {}
                or a
                jr z,gw_e
                ld a,(hl)
                inc hl
                dec b
                cp ' '
                jr z,gw_8
                jr gw_l
gw_e:           ex de,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld b,h
                ld c,l
                jp set_res

; ---------------------------------------------------------------- cursor (cursorCommand)
; Lee con la especificacion generica (decode: ARGS = [k, operandos...]) y actua sobre _userPut y _cursor.state; luego, la linea H.
b_cursorCommand:
                call decode
                ld (SPTR),de
                ld a,(ARGS)
                cp 12
                jr z,cc_12
                cp 9
                jp nc,host_call         ; 10, 11, 13, 14 y los demas: solo el anfitrion
                or a
                jp z,host_call
                dec a                   ; k - 1 = 0..7: bit 1: 0 cursor, 1 userPut; 0, 1, 2, 3: poner 1 o 0; 4..7: sumar o restar 1
                ld c,a
                and 2
                ld hl,CURSTATE
                jr z,cc_p
                ld hl,USERPUT
cc_p:           ld a,c
                cp 4
                jr nc,cc_inc
                and 1
                xor 1
                ld (hl),a
                inc hl
                ld (hl),0
                jp host_call
cc_inc:         ld e,(hl)
                inc hl
                ld d,(hl)
                bit 0,a
                jr nz,cc_dec
                inc de
                jr cc_w
cc_dec:         dec de
cc_w:           ld (hl),d
                dec hl
                ld (hl),e
                jp host_call
cc_12:          ld hl,(ARGS+2)          ; SO_CURSOR_SET: 0..3
                ld a,h
                or a
                jp nz,err_range
                ld a,l
                cp 4
                jp nc,err_range
                jp host_call

; ---------------------------------------------------------------- verbos (verbOps, saveRestoreVerbs)
; VERBS: NVERB registros de VSZ bytes (V_*). La ranura 0 es una ranura de trabajo, como en ScummVM. El nombre es un puntero al texto
; del script (pagina y direccion), no una copia.

; verb_ix: A = ranura -> IX = su registro (destruye HL, BC; conserva DE)
verb_ix:        ld l,a                  ; VERBS + 19 * ranura (VSZ = 19 = 16 + 3)
                ld h,0
                ld b,h
                ld c,l
                add hl,hl
                add hl,bc
                ld b,h
                ld c,l                  ; BC = 3 * ranura
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,bc
                ld bc,VERBS
                add hl,bc
                push hl
                pop ix
                ret

; verb_find: A = id de verbo, C = saveid -> A = ranura (0 si no esta). Destruye HL, B, IX; conserva DE y C
verb_find:      push de
                ld ix,VERBS+VSZ
                ld de,VSZ
                ld b,NVERB-1
                ld h,1
vf_l:           cp (ix+V_ID)
                jr nz,vf_n
                ld l,a
                ld a,(ix+V_SAVE)
                cp c
                ld a,l
                jr z,vf_y
vf_n:           add ix,de
                inc h
                djnz vf_l
                xor a
                pop de
                ret
vf_y:           ld a,h
                pop de
                ret

; kill_verb: A = ranura (0: nada): verbid, curmode, saveid y nombre a 0; suceso E 11 [ranura, 0]. Conserva DE
; vd_draw (fase 7): ScummEngine::drawVerb en lo que mira la entrada. IX = el verbo: si es visible (id <> 0, curmode <> 0, saveid = 0 y de texto) V_LEN = columnas de su nombre
; ya convertido (convertMessageToString: los codigos $FF cuentan como sus bytes), con tope de 40. Conserva IX y DE. El nombre es un puntero (pagina y direccion) al texto del script
vd_draw:        ld a,(ix+V_ID)
                or a
                ret z
                ld a,(ix+V_MODE)
                or a
                ret z
                ld a,(ix+V_SAVE)
                or a
                ret nz
                bit 1,(ix+V_FLG)
                ret nz                  ; con imagen: sin rectangulo
                push de
                ld a,1                  ; modo 1: solo cuenta
                call vd_conv
                ld hl,(CM_LEN)
                ld a,h
                or a
                ld a,40
                jr nz,vd_s
                ld a,l
                cp 41
                jr c,vd_s
                ld a,40
vd_s:           ld (ix+V_LEN),a
                pop de
                ret

; vd_conv: IX = verbo, A = modo (1 solo cuenta, 2 a UIBUF): convierte su nombre (CM_LEN = bytes). Conserva IX
vd_conv:        push ix
                ld (CM_MODE),a
                ld hl,0
                ld (CM_LEN),hl
                ld (CM_SUM),hl
                xor a
                ld (CM_DEP),a
                ld a,(ix+V_NPG)
                or a
                jr z,vc_e
                ld l,(ix+V_NAD)
                ld h,(ix+V_NAD+1)
                ld de,$FFFF
                ld (CM_REM),de
                call map_page           ; (conserva HL y DE)
                call cm_run
                ld ix,(CURSLOT)         ; la ventana vuelve a la pagina del script en curso
                ld a,(ix+SL_PAGE)
                call map_page
vc_e:           pop ix
                ret

; ovb_vname (entrada +24 de B; fase 7): IX = verbo -> UIBUF = su nombre convertido (los codigos $FF incluidos), HL = cuantos bytes (tope 48). Para dibujar el verbo
ovb_vname:      ld hl,(CURSLOT)         ; fuera de un script no hay ranura en curso: una falsa cuya pagina es la del nombre (cm_nest devuelve la ventana a la de CURSLOT)
                push hl
                ld a,(ix+V_NPG)
                ld (FAKESL+SL_PAGE),a
                ld hl,FAKESL
                ld (CURSLOT),hl
                ld a,2
                call vd_conv
                pop hl
                ld (CURSLOT),hl
                ld hl,(CM_LEN)
                ld a,h
                or a
                jr nz,vn_cap            ; (HL = bytes: A no sirve, call_ovb lo pisa)
                ld a,l
                cp 49
                ret c
vn_cap:         ld hl,48
                ret

kill_verb:      or a
                ret z
                push de
                push af
                call verb_ix
                ld (ix+V_ID),0
                ld (ix+V_MODE),0
                ld (ix+V_SAVE),0
                ld (ix+V_NPG),0
                pop af
                ld l,a
                ld h,0
                ld (EVARGS),hl
                ld hl,0
                ld (EVARGS+2),hl
                ld a,EV_VERB
                call ev_emit
                pop de
                ret

; vb_byte: BC = valor de un operando; lo guarda en (IX + A) (un byte). Para los vo_ de un campo de un byte
b_verbOps:      call rd_vb1
                ld a,b
                or a
                jp nz,err_range         ; el verbo: 0..255
                ld a,c
                ld (SC+0),a
                ld c,0
                call verb_find
                ld (SC+1),a             ; ranura
                call verb_ix
                ld a,(SC+0)
                ld (ix+V_ID),a
vo_l:           ld a,(de)
                inc de
                ld (OPC),a
                inc a
                jp z,vo_end
                ld a,(SC+1)             ; vs: el registro de la ranura (k = 9 la puede cambiar)
                call verb_ix
                ld a,(OPC)
                and $1F
                cp 3
                jr z,vo_col
                cp 4
                jr z,vo_hi
                cp 16
                jr z,vo_dim
                cp 18
                jr z,vo_key
                cp 23
                jr z,vo_bk
                cp 5
                jp z,vo_pos
                cp 6
                jr z,vo_m1
                cp 7
                jr z,vo_m0
                cp 17
                jr z,vo_m2
                cp 2
                jp z,vo_name
                cp 8
                jr z,vo_kill
                cp 9
                jp z,vo_new
                cp 19
                jr z,vo_cen
                cp 1
                jr z,vo_img1
                cp 22
                jp z,vo_img22
                jp err_badsub           ; (el 20, nombre desde una cadena, no esta soportado: ver vmmodel3.o_verbOps)
vo_col:         call rd_vb1
                ld (ix+V_COL),c
                jp vo_l
vo_hi:          call rd_vb1
                ld (ix+V_HI),c
                jp vo_l
vo_dim:         call rd_vb1
                ld (ix+V_DIM),c
                jp vo_l
vo_key:         call rd_vb1
                ld (ix+V_KEY),c
                jp vo_l
vo_bk:          call rd_vb1
                ld (ix+V_BK),c
                jp vo_l
vo_m1:          ld (ix+V_MODE),1
                jp vo_l
vo_m0:          ld (ix+V_MODE),0
                jp vo_l
vo_m2:          ld (ix+V_MODE),2
                jp vo_l
vo_cen:         set 0,(ix+V_FLG)
                jp vo_l
vo_kill:        ld a,(SC+1)
                call kill_verb
                jp vo_l
vo_img1:        call rd_vw1             ; la imagen se lee y se descarta; con ranura, type = 1
                ld a,(SC+1)
                or a
                jp z,vo_l
                set 1,(ix+V_FLG)
                jp vo_l
vo_pos:         call rd_vw1
                ld (ix+V_LEFT),c
                ld (ix+V_LEFT+1),b
                call rd_vw2
                ld (ix+V_TOP),c
                ld (ix+V_TOP+1),b
                jp vo_l
vo_img22:       call rd_vw1
                push bc
                call rd_vb2
                pop bc
                ld a,(SC+1)
                or a
                jp z,vo_l
                ld a,(ix+V_IMG)
                cp c
                jr nz,vo_i22
                ld a,(ix+V_IMG+1)
                cp b
                jp z,vo_l
vo_i22:         set 1,(ix+V_FLG)
                ld (ix+V_IMG),c
                ld (ix+V_IMG+1),b
                jp vo_l
vo_name:        push ix                 ; nombre = el texto del script (pagina de la ranura en curso y direccion)
                ld ix,(CURSLOT)
                ld a,(ix+SL_PAGE)
                pop ix
                ld (ix+V_NPG),a
                ld (ix+V_NAD),e
                ld (ix+V_NAD+1),d
                call scan_len
                res 1,(ix+V_FLG)        ; type = 0
                xor a
                ld (ix+V_IMG),a
                ld (ix+V_IMG+1),a
                jp vo_l
vo_new:         ld a,(SC+0)             ; verbo nuevo: la ranura que ya tenga ese id o la primera libre
                ld c,0
                call verb_find
                or a
                jr nz,vn_have
                ld ix,VERBS+VSZ
                push de
                ld de,VSZ
                ld b,NVERB-1
                ld a,1
vn_l:           ld c,a
                ld a,(ix+V_ID)
                or a
                ld a,c
                jr z,vn_fnd
                add ix,de
                inc a
                djnz vn_l
                jp err_range            ; sin ranura libre
vn_fnd:         pop de
vn_have:        ld (SC+1),a
                call verb_ix
                ld a,(SC+0)
                ld (ix+V_ID),a
                ld (ix+V_COL),2
                ld (ix+V_HI),14
                ld (ix+V_DIM),8
                xor a
                ld (ix+V_MODE),a
                ld (ix+V_SAVE),a
                ld (ix+V_KEY),a
                ld (ix+V_FLG),a
                ld (ix+V_IMG),a
                ld (ix+V_IMG+1),a
                ld (ix+V_NPG),a
                jp vo_l
vo_end:         ld (SPTR),de
                ld a,(SC+1)
                or a
                push af
                call verb_ix
                pop af
                call nz,vd_draw         ; fase 7: drawVerb (solo el rectangulo; la ranura 0 no se dibuja)
                ld l,(ix+V_ID)
                ld h,0
                ld (EVARGS),hl
                ld l,(ix+V_MODE)
                ld (EVARGS+2),hl
                ld a,EV_VERB
                jp ev_emit

; saveRestoreVerbs: subopcode (1 guardar, 2 restaurar, 3 borrar los guardados), a, b, c: para cada verbo a..b con saveid c
b_saveRestoreVerbs:
                ld a,(de)
                inc de
                ld (OPC),a
                ld (SC+18),a
                call rd_vb1
                ld (SC+0),bc
                call rd_vb2
                ld (SC+2),bc
                call rd_vb3
                ld (SC+4),bc
                ld (SPTR),de
                ld a,(SC+18)
                or a
                jp z,err_badsub
                cp 4
                jp nc,err_badsub
                ld a,(SC+1)             ; a, b y c: 0..255
                ld hl,SC+3
                or (hl)
                ld hl,SC+5
                or (hl)
                jp nz,err_range
sr_loop:        ld a,(SC+0)
                ld hl,SC+2
                cp (hl)
                jr z,sr_do
                jr nc,sr_done           ; a > b
sr_do:          ld a,(SC+18)
                cp 2
                jr z,sr_rest
                jr nc,sr_del
                ld a,(SC+0)             ; 1: guardar (saveid = c) los que no lo estan
                ld c,0
                call verb_find
                or a
                jr z,sr_next
                call verb_ix
                ld a,(ix+V_SAVE)
                or a
                jr nz,sr_next
                ld a,(SC+4)
                ld (ix+V_SAVE),a
                jr sr_next
sr_rest:        ld a,(SC+0)             ; 2: restaurar: el actual (saveid 0) se borra y el guardado pasa a ser el actual
                ld a,(SC+4)
                ld c,a
                ld a,(SC+0)
                call verb_find
                or a
                jr z,sr_next
                ld c,0
                ld a,(SC+0)
                call verb_find
                call kill_verb
                ld a,(SC+4)
                ld c,a
                ld a,(SC+0)
                call verb_find
                call verb_ix
                ld (ix+V_SAVE),0
                call vd_draw            ; fase 7: drawVerb
                jr sr_next
sr_del:         ld a,(SC+4)             ; 3: borrar el guardado
                ld c,a
                ld a,(SC+0)
                call verb_find
                call kill_verb
sr_next:        ld a,(SC+0)
                ld hl,SC+2
                cp (hl)
                jr z,sr_done
                ld hl,SC+0
                inc (hl)
                jr sr_loop
sr_done:        ret

; ---------------------------------------------------------------- actorOps
; El actor y la lista de subopcodes (convertTable de GF_SMALL_HEADER, act_conv del residente: el subopcode traducido queda en OPC con
; sus bits de variable). Cada subopcode empieza con IX = el registro del actor (se vuelve a calcular: lo que llama a start_anim,
; put_actor... puede cambiar IX y DE; DE se guarda en SPTR). SC+0 = numero del actor.
b_actorOps:     call rd_vb1
                ld a,c
                ld (SC+0),a
                call chk_actor          ; E_BADACTOR; IX
ao_l:           ld a,(de)
                inc de
                cp $FF
                jr z,ao_end
                ld c,a
                and $1F
                jp z,err_badsub
                cp 21
                jp nc,err_badsub
                ld l,a
                ld h,0
                push bc
                ld bc,act_conv-1
                add hl,bc
                pop bc
                ld a,c
                and $E0
                or (hl)
                ld (OPC),a
                ld a,(SC+0)
                call actor_ix
                ld a,(OPC)
                and $1F
                add a,a
                ld l,a
                ld h,0
                ld bc,ao_tab
                add hl,bc
                ld c,(hl)
                inc hl
                ld b,(hl)
                push bc
                ret
ao_end:         ld (SPTR),de
                ret
ao_cont:        ld de,(SPTR)
                jp ao_l

ao_tab:         defw ao_k0,ao_k1,ao_k2,ao_b3,ao_b4,ao_k5,ao_b6,ao_k7,ao_k8,ao_k9,ao_k10
                defw ao_k11,ao_b12,ao_k13,ao_b14,err_badsub,ao_b16,ao_k17,err_badsub,err_badsub,ao_k20

ao_k0:          call rd_vb1             ; (se lee y se descarta)
                jp ao_l
ao_k17:         call rd_vb1
                call rd_vb2
                jp ao_l
ao_k7:          call rd_vb1
                call rd_vb2
                call rd_vb3
                jp ao_l
ao_k11:         call rd_vb1             ; paleta: el indice tiene que estar en 0..31
                push bc
                call rd_vb2
                pop bc
                ld a,b
                or a
                jp nz,err_range
                ld a,c
                cp 32
                jp nc,err_range
                jp ao_l

; un campo de un byte de A_*: A = desplazamiento
ao_b1:          push af
                call rd_vb1
                pop af
                push ix
                pop hl
                add a,l
                ld l,a
                jr nc,ab_n
                inc h
ab_n:           ld (hl),c
                jp ao_l
ao_b3:          ld a,A_SND0
                jr ao_b1
ao_b4:          ld a,A_WALK
                jr ao_b1
ao_b6:          ld a,A_STAND
                jr ao_b1
ao_b12:         ld a,A_TALKC
                jr ao_b1
ao_b14:         ld a,A_INIT
                jr ao_b1
ao_b16:         ld a,A_WIDTH
                jr ao_b1
ao_k5:          call rd_vb1
                ld (ix+A_TSTART),c
                call rd_vb2
                ld (ix+A_TSTOP),c
                jp ao_l

ao_k1:          call rd_vb1             ; setActorCostume: si esta visible se oculta, se cambia el traje y se vuelve a mostrar
                ld (SPTR),de
                set 1,(ix+A_FLAGS)
                ld a,(ix+A_VIS)
                or a
                jr z,k1_set
                push bc
                call hide_actor
                pop bc
                ld (ix+A_COST),c
                ld (ix+A_COST+1),b
                call show_actor
                jp ao_cont
k1_set:         ld (ix+A_COST),c
                ld (ix+A_COST+1),b
                jp ao_cont

ao_k2:          call rd_vb1             ; velocidad de caminata: si cambia con el actor en movimiento hace falta calcMovementFactor (fase 6)
                push bc
                call rd_vb2
                pop hl
                ld a,(ix+A_SPEEDX)
                cp l
                jr nz,k2_ch
                ld a,(ix+A_SPEEDY)
                cp c
                jp z,ao_l
k2_ch:          ld (ix+A_SPEEDX),l
                ld (ix+A_SPEEDY),c
                ld a,(ix+A_MOVING)
                or a
                jp z,ao_l
                push de                 ; el puntero del script
                ld hl,OVD_CALCMF        ; calcMovementFactor(_walkdata.next) (overlay D)
                call call_ovd
                pop de
                jp ao_l

ao_k8:          xor a                   ; initActor(0)
                ld (ix+A_ELEV),a
                ld (ix+A_ELEV+1),a
                ld (ix+A_LVX),a
                ld (ix+A_LVX+1),a
                ld (ix+A_LVY),a
                ld (ix+A_LVY+1),a
                ld (ix+A_SND0),a
                ld (ix+A_IGNB),a
                ld (ix+A_ANSPD),a
                ld (ix+A_MOVING),a
                res 2,(ix+A_FLAGS)
                ld (ix+A_WIDTH),24
                ld (ix+A_TALKC),15
                ld a,(ix+A_FACING)
                ld (ix+A_TFACE),a
                ld a,(ix+A_FACING+1)
                ld (ix+A_TFACE+1),a
                ld (ix+A_INIT),1
                ld (ix+A_WALK),2
                ld (ix+A_STAND),3
                ld (ix+A_TSTART),4
                ld (ix+A_TSTOP),5
                ld (ix+A_SPEEDX),8
                ld (ix+A_SPEEDY),2
                ld a,(SC+0)             ; classes[actor] = 0
                ld l,a
                ld h,0
                ld c,a
                ld b,h
                add hl,hl
                add hl,bc
                ld bc,WINDOW
                add hl,bc
                call cls_open
                xor a
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                call cls_close
                jp ao_l

ao_k9:          call rd_vw1             ; elevacion
                ld a,(ix+A_ELEV)
                cp c
                jr nz,k9_ch
                ld a,(ix+A_ELEV+1)
                cp b
                jp z,ao_l
k9_ch:          ld (ix+A_ELEV),c
                ld (ix+A_ELEV+1),b
                set 0,(ix+A_FLAGS)
                jp ao_l

ao_k10:         ld (ix+A_INIT),1        ; los fotogramas de siempre
                ld (ix+A_WALK),2
                ld (ix+A_STAND),3
                ld (ix+A_TSTART),4
                ld (ix+A_TSTOP),5
                jp ao_l

ao_k13:         ld a,(SC+0)             ; nombre: pagina y direccion del texto en el script (ACTNAMES)
                ld l,a
                ld h,0
                ld c,a
                ld b,0
                add hl,hl
                add hl,bc
                ld bc,ACTNAMES
                add hl,bc
                push ix
                ld ix,(CURSLOT)
                ld a,(ix+SL_PAGE)
                pop ix
                ld (hl),a
                inc hl
                ld (hl),e
                inc hl
                ld (hl),d
                call scan_len
                jp ao_l

ao_k20:         ld (ix+A_IGNB),1        ; ignoreBoxes; si esta en la sala se vuelve a poner (putActor)
                call in_room
                jp nz,ao_l
                ld (SPTR),de
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                ld c,(ix+A_ROOM)
                call put_actor
                jp ao_cont

; saveLoadVars: b (1 = guardar) y una lista de subopcodes hasta 0: 1 (dos posiciones de resultado), 2 (cadenas a..b), 3 (un nombre de
; fichero), 4 o $1F (fin). H [guardar, a, b, ...]. Al cargar (salvo 9, 9) las cadenas a..b que existen quedan con el primer byte a 0
b_saveLoadVars: ld a,(OPC)
                ld (TOPOP),a
                ld a,(de)
                inc de
                sub 1                   ; guardar = (b == 1)
                ld a,0
                jr nz,sv_n1
                inc a
sv_n1:          ld (SC+0),a
                ld hl,ARGS
                ld (ARGP),hl
                ld c,a
                ld b,0
                call emit
sv_l:           ld a,(de)
                inc de
                ld (OPC),a
                or a
                jr z,sv_done
                and $1F
                cp 1
                jr z,sv_1
                cp 2
                jr z,sv_2
                cp 3
                jr z,sv_3
                cp 4
                jr z,sv_done
                cp $1F
                jr nz,sv_l
sv_done:        ld (SPTR),de
                ld a,(ARGP)
                sub ARGS AND 255
                rrca
                ld (ARGN),a
                jp host_call
sv_1:           call rd_res
                call rd_res
                jr sv_l
sv_3:           call scan_len
                jr sv_l
sv_2:           call rd_vb1
                push bc
                call rd_vb2
                ld (SC+6),bc
                pop bc
                ld (SC+4),bc
                call emit
                ld bc,(SC+6)
                call emit
                ld a,(SC+0)
                or a
                jp nz,sv_l              ; al guardar no se toca nada
                call sv_reset
                jp sv_l

; sv_reset: las cadenas a..b (SC+4, SC+6; con signo, limitadas a 0..NSTR-1) que existen quedan con el primer byte a 0; (9, 9): nada. Conserva DE
sv_reset:       push de
                ld hl,(SC+4)
                ld de,(SC+6)
                ld a,l
                cp 9
                jr nz,svr_go
                ld a,h
                or a
                jr nz,svr_go
                ld a,e
                cp 9
                jr nz,svr_go
                ld a,d
                or a
                jr z,svr_end
svr_go:         bit 7,d                 ; b < 0: nada
                jr nz,svr_end
                bit 7,h                 ; a < 0: desde 0
                jr z,svr_a
                ld hl,0
svr_a:          ld a,h
                or a
                jr nz,svr_end           ; a > 31: nada
                ld a,l
                cp NSTR
                jr nc,svr_end
                ld a,d
                or a
                jr nz,svr_b31
                ld a,e
                cp NSTR
                jr c,svr_bok
svr_b31:        ld e,NSTR-1
svr_bok:        ld a,e
                cp l
                jr c,svr_end            ; b < a: nada
                ld a,e
                ld (SC+8),a
                ld a,l
svr_s:          ld (SC+9),a
                ld e,a
                ld d,0
                ld hl,STRLEN
                add hl,de
                ld a,(hl)
                or a
                jr z,svr_nx
                ld a,(SC+9)
                IF PROGRAM
                ld hl,OVC_NAME1         ; fase 9: el nombre de la partida (overlay C; SC+4 = el primer id del rango)
                call call_ovc
                ELSE
                call str_ptr
                ld (hl),0
                ENDIF
svr_nx:         ld a,(SC+9)
                ld hl,SC+8
                cp (hl)
                jr nc,svr_end
                inc a
                jr svr_s
svr_end:        pop de
                ret
