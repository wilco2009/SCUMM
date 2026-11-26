NOCACHE        equ 0                   ; 1: sin cache (para comparar sprites con y sin ella)
actors_update:  call ac_track
                ld a,(gf_have)
                or a
                ret z
                call gf_campx
                ld (ac_cam),hl
                ld de,(ac_pcam)         ; lo que se ha movido la camara: una entrada de la cache que sigue valiendo solo corrige la X de sus sprites (acc_ok)
                ld (ac_pcam),hl
                or a
                sbc hl,de
                ld (ac_dlt),hl
                ld hl,(ac_stamp)
                inc hl
                ld (ac_stamp),hl
                xor a
                ld (ac_n),a
                ld a,(ac_hold)          ; sala nueva: los sprites siguen apagados hasta saber donde van
                or a
                jr z,au_run
                dec a
                ld (ac_hold),a
                jr au_hide
au_run:         xor a                   ; la lista AL esta ordenada de arriba a abajo (como processActors de ScummVM) y se recorre al reves: el primero que se
                                        ; dibuja (el de mas abajo, que va delante) recibe las ranuras de mas prioridad (ver ac_slot)
                ld (ac_cnt),a
                ld b,1
ao_l:           ld a,b
                call actor_addr
                ld a,(CURROOM)
                cp (ix+0)
                jr nz,ao_next
                ld a,(ix+9)             ; visible
                or a
                jr z,ao_next
                ld d,(ix+3)             ; D = y (los personajes caben en 0-255)
                ld a,(ac_cnt)
                ld c,a                  ; C = lugares ocupados
ao_ins:         ld a,c
                or a
                jr z,ao_put
                dec a
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                ld a,(hl)               ; la clave del anterior
                cp d
                jr c,ao_put
                jr z,ao_put
                ld a,(hl)               ; si es mayor se desplaza un lugar
                inc hl
                ld e,(hl)
                inc hl
                ld (hl),a
                inc hl
                ld (hl),e
                dec c
                jr ao_ins
ao_put:         ld a,c
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
                ld (hl),d
                inc hl
                ld (hl),b
                ld hl,ac_cnt
                inc (hl)
ao_next:        inc b
                ld a,b
                cp NACTORS
                jr c,ao_l
                ld a,(ac_cnt)
                or a
                jr z,au_hide
                ld b,a
                dec a
                add a,a
                add a,AL mod 256
                ld l,a
                ld h,AL / 256
ad_l:           push bc
                push hl
                inc hl
                ld a,(hl)
                ld (ac_id),a
                call actor_addr
                call ac_cdraw
                pop hl
                dec hl
                dec hl
                pop bc
                djnz ad_l
au_hide:        ld a,(ac_n)             ; los sprites que sobran del fotograma anterior se apagan
                ld b,a
                ld a,(ac_used)
                ld c,a
                ld a,b
                ld (ac_used),a
ac_off:         ld a,b
                cp c
                jr nc,ac_ext
                push bc
                ld a,b
                call ac_slot
                xor a
                ld (hl),a               ; activo = 0 (normal) y Y = 0 (extra: sin bit de activo, Y = 0 no se ve)
                inc hl
                inc hl
                inc hl
                ld (hl),a
                pop bc
                inc b
                jr ac_off
ac_ext:         ld a,(ac_n)             ; POKE 2131: los extra en uso (la entrada 1 va aparte: ver ac_slot)
                sub 63
                jr nc,ace_1
                xor a
                jr ace_2
ace_1:          cp 2
                jr c,ace_2
                inc a
ace_2:          ld (2131),a
                ret

; Las ranuras de sprite, de mayor a menor prioridad: 0-62 son los sprites 62-0 de la placa (el 63 es el cursor); 63-77 son los extra (POKE 2131), cuya
; entrada de 32 bytes esta en SPRX + 32 * j (bloque 2 de POKE 2129): menos prioridad que todos los normales y, entre ellos, gana el numero mas bajo.
; La entrada 1 ($4020-$403F) lleva CDFLAG ($403B) del ZX81: no se usa (la ranura 64 es la entrada 2).
; A = ranura -> HL = ventana de campos (la de POKE 2101 si es un normal, que queda seleccionado; la entrada si es un extra)
ac_slot:        cp 63
                jr nc,acs_x
                ld c,a
                ld a,62
                sub c
                ld (2100),a
                ld hl,2101
                ret
acs_x:          sub 63
                cp 1
                jr c,acs_0
                inc a
acs_0:          ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,h
                add a,SPRX / 256
                ld h,a
                ret

; A = ranura (0-77) -> A = su pagina en la hoja del bloque 0 (libres: 16-62, 67-95, 224-239; PLAN_TRAJES4.md)
ac_shp:         cp 47
                jr nc,ash_1
                add a,16
                ret
ash_1:          cp 76
                jr nc,ash_2
                add a,20
                ret
ash_2:          add a,148
                ret

; DE = (ac_wb) + A: la direccion de un campo de la ventana del sprite que se escribe
ac_wbo:         ld de,(ac_wb)
                add a,e
                ld e,a
                ret nc
                inc d
                ret


; Fotogramas de overlay: animateActor con un fotograma que no es caminar (0), parado (1), inicio (2) ni hablar (4, 5) deja puestos los miembros que
; nombra encima de la pose de reposo (ScummVM: cada animacion solo cambia sus miembros). El motor solo guarda el ultimo fotograma (ix+10); aqui se
; recuerda el ultimo de overlay: el 3 y los de 6 en adelante lo ponen; el inicio (2), caminar (0) y cambiar de traje lo quitan.
ac_track:       ld b,1
act_l:          ld a,b
                call actor_addr
                call act_one
                inc b
                ld a,b
                cp NACTORS
                jr c,act_l
                ret

; ac_setfr (puerta OVL_SETFRAME, la llama start_anim del residente): guarda el fotograma C del actor IX y lo anota ya: si no, un fotograma de overlay que
; se pone y otro que se pone en el mismo fotograma del motor (hablar, que lo hace el mismo script o el que arranca: el sombrero de quien dice "Mi sombrero"
; justo despues de ponerselo) llega a ac_track pisado y el overlay no se entera
ac_setfr:       ld (ix+45),0            ; la animacion empieza de nuevo: una misma animacion repetida (las notas del baile) vuelve a hacerse
                ld (ix+10),c
                ld a,c
                cp 3
                jr z,asf_go
                cp 6
                ret c                   ; solo los fotogramas que ponen un overlay (3 y de 6 en adelante); los demas los ve ac_track como siempre
asf_go:         ld a,(ix+15)
                or a
                ret z
                cp NACTORS
                ret nc
                push bc
                push de
                push hl
                ld b,a
                call act_one
                pop hl
                pop de
                pop bc
                ret

; B = actor, IX = su direccion: anota su fotograma de overlay (AC_OVF) si ha cambiado desde la ultima vez
act_one:
                ld e,b
                ld d,0
                ld hl,AC_LC
                add hl,de
                ld a,(ix+5)
                cp (hl)
                jr z,act_c
                ld (hl),a               ; traje nuevo: sin overlay y se vuelve a mirar el fotograma
                ld hl,AC_OVF
                add hl,de
                ld (hl),0
                ld hl,AC_LF
                add hl,de
                ld (hl),$FF
act_c:          ld hl,AC_LF
                add hl,de
                ld a,(ix+10)
                cp (hl)
                jr z,act_r
                ld (hl),a
                ld hl,AC_OVF
                add hl,de
                or a
                jr z,act_0              ; caminar: quita el overlay
                cp INIT_FRAME
                jr z,act_0              ; inicio: tambien
                cp 3
                jr z,act_s
                cp 6
                jr c,act_r              ; parado, hablar: no cambian el overlay
act_s:          push bc                 ; complementos que se suman (las gafas y el sombrero: ScummVM cambia solo los miembros que nombra cada animacion):
                push hl                 ; el estado nuevo sale de la tabla del traje (TOOLS/costume2.py overlay_combos)
                ld c,a
                ld a,(hl)
                and $7F
                ld b,a
                call ac_trans
                pop hl
                pop bc
                ld (hl),a
                ld (ix+45),0            ; el overlay nuevo empieza su animacion
                jr act_r
act_0:          ld a,(hl)               ; caminar / inicio: el overlay queda pendiente de quitar (bit 7); ac_draw lo quita salvo que el traje diga que no lo toca
                or a
                jr z,act_r
                or $80
                ld (hl),a
act_r:          ret

; B = overlay puesto, C = fotograma nuevo, IX = actor -> A = overlay que queda: el de la tabla de transiciones del traje (detras de los fondos en su
; directorio: u8 n y n x (actual, fotograma, nuevo)) o C si no esta. Deja en la ventana de datos la pagina del script en curso
ac_trans:       ld a,(ix+5)
                cp 64
                jr nc,atr_no
                ld e,a
                ld d,0
                ld hl,COSTDIR
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                jr z,atr_no
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                push bc
                call map_page
                pop bc
                ex de,hl                ; HL = directorio
                call atr_skip           ; las animaciones
                call atr_skip           ; los fondos
                ld a,(hl)
                inc hl
                or a
                jr z,atr_nf
                ld d,a
atr_l:          ld a,b
                cp (hl)
                inc hl
                jr nz,atr_2
                ld a,c
                cp (hl)
                inc hl
                jr nz,atr_1
                ld a,(hl)
                jr atr_f
atr_2:          inc hl
atr_1:          inc hl
                dec d
                jr nz,atr_l
atr_nf:         ld a,c
atr_f:          push af
                call restore_win
                pop af
                ret
atr_no:         ld a,c
                ret
atr_skip:       ld e,(hl)               ; HL = u8 n y n x 3 bytes -> HL detras
                ld d,0
                inc hl
                add hl,de
                add hl,de
                add hl,de
                ret

; ---------------------------------------------------------------------------------------------------------------------------------
;  Cache de sprites: si un actor tiene la misma firma (posicion, traje, pose, direccion, camara, quien habla) y los mismos sprites que en el
;  fotograma anterior, sus sprites ya estan bien y no se vuelven a escribir (ac_draw cuesta mas de la mitad de lo que tarda una vuelta).
;  Una entrada vale solo si su marca es la del fotograma anterior: los actores que no se dibujan un fotograma pierden la entrada.
; ---------------------------------------------------------------------------------------------------------------------------------
ac_cdraw:       call ac_hash
                ld (ac_sg),de
                ld a,(ac_id)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                add hl,hl               ; 6 * actor
                ld de,ACSIG
                add hl,de
                ld (ac_ent),hl
                IF NOCACHE
                jr acc_miss
                ENDIF
                ld a,(ix+10)            ; caminando: ac_draw avanza el contador de la animacion, no se puede saltar
                or a
                jr z,acc_miss
acc_ok:         push hl                 ; (hablando: la firma lleva la pose de la boca que toca; si no cambia, la cache vale y solo avanza el contador)
                ld de,4
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)               ; marca de la entrada
                ld hl,(ac_stamp)
                dec hl
                or a
                sbc hl,de
                pop hl
                jr nz,acc_miss
                ld e,(hl)
                inc hl
                ld d,(hl)               ; firma de la entrada
                inc hl
                push hl
                ld hl,(ac_sg)
                or a
                sbc hl,de
                pop hl
                jr nz,acc_miss
                ld a,(ac_n)
                cp (hl)                 ; el mismo primer sprite
                jr nz,acc_miss
                inc hl
                ld c,(hl)               ; cuantos sprites usa (bit 7: alguna celda quedo fuera por la X; con la camara movida hay que dibujarlo)
                ld hl,(ac_dlt)
                ld a,h
                or l
                jr z,acc_nd
                bit 7,c
                jr nz,acc_miss
                call ac_mvx
                jr c,acc_miss
acc_nd:         ld a,c
                and $7F
                ld hl,ac_n
                add a,(hl)
                ld (hl),a
                ld hl,(ac_ent)
                ld de,4
                add hl,de
                ld de,(ac_stamp)
                ld (hl),e
                inc hl
                ld (hl),d
                call ac_tk
                ret nc
                ld hl,(ac_dlt)          ; con la camara en movimiento la boca no se mueve
                ld a,h
                or l
                ret nz
                inc (ix+45)             ; el que habla: el contador de la boca avanza como si se hubiera dibujado (acd_noov)
                ret
acc_miss:       ld a,(ac_n)
                ld (ac_n0),a
                xor a
                ld (ac_xs),a
                call ac_draw
                ld hl,(ac_ent)
                ld de,(ac_sg)
                ld (hl),e
                inc hl
                ld (hl),d
                inc hl
                ld a,(ac_n0)
                ld (hl),a
                inc hl
                ld c,a
                ld a,(ac_n)
                sub c
                ld c,a
                ld a,(ac_xs)
                rrca
                or c
                ld (hl),a
                inc hl
                ld de,(ac_stamp)
                ld (hl),e
                inc hl
                ld (hl),d
                ret

; DE = firma del actor IX: lo que ac_draw lee de el, de la camara y de quien habla
; la paleta del actor ac_id (ACTPAL + 8 * actor; nibble i = i XOR _palette[i]) -> ac_pm: codigo Chroma del color EGA i del traje -> codigo Chroma de _palette[i].
; ac_pf = 0 si es la identidad. El indice 12 no se cambia (ScummVM: _palette[12] = 12 en v2). Conserva IX.
ac_mkpal:       ld a,(VAR_CURRENT_LIGHTS)
                and 8
                jr nz,amk_n
                ld hl,ac_pm             ; sin el bit 8 (actor_use_colors): todo a gris 8 y el 12 a negro (costume.cpp:813)
                ld de,ac_pm+1
                ld bc,15
                ld (hl),8
                ldir
                ld hl,ac_pm+10          ; Chroma del EGA 12
                ld (hl),0
                inc a
                ld (ac_pf),a
                jr amk_t
amk_n:          ld a,(ac_id)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,ACTPAL
                add hl,de
                push hl
                xor a
                ld b,8
ampk_c:         or (hl)
                inc hl
                djnz ampk_c
                pop hl
                ld (ac_pf),a
                ret z
                ld c,0                  ; C = indice
ampk_l:         ld a,c
                srl a
                ld e,a
                ld d,0
                push hl
                add hl,de
                ld a,(hl)
                pop hl
                bit 0,c
                jr z,ampk_n
                rrca
                rrca
                rrca
                rrca
ampk_n:         and 15
                xor c                   ; A = _palette[C]
                ld b,a
                ld a,c
                cp 12
                jr nz,ampk_v
                ld b,12
ampk_v:         push hl
                ld hl,ega2chroma
                ld e,b
                add hl,de
                ld b,(hl)               ; B = Chroma del color nuevo
                ld hl,ega2chroma
                ld e,c
                add hl,de
                ld e,(hl)               ; E = Chroma del color del traje
                ld hl,ac_pm
                add hl,de
                ld (hl),b
                pop hl
                inc c
                ld a,c
                cp 16
                jr nz,ampk_l
amk_t:          call ac_pt
                ld c,0                  ; ac_ptr = el primer codigo que la paleta no da (color transparente de las celdas de 4 bpp)
amt_l:          ld hl,ac_pm
                ld b,16
amt_s:          ld a,(hl)
                cp c
                jr z,amt_n
                inc hl
                djnz amt_s
                ld a,c
                ld (ac_ptr),a
                ret
amt_n:          inc c
                ld a,c
                cp 16
                jr c,amt_l
                xor a
                ld (ac_ptr),a
                ret

; A = byte de color de una celda (tinta en el nibble alto, papel en el bajo) -> A remapeado con ac_pm si el actor tiene paleta propia. Conserva todo lo demas
acd_pmap:       push af
                ld a,(ac_pf)
                or a
                jr nz,apm_go
                pop af
                ret
apm_go:         pop af
                push bc
                ld b,PALT/256
                ld c,a
                ld a,(bc)
                pop bc
                ret

; PALT = ac_pm aplicado a los dos nibbles de cada byte; se rehace solo si ac_pm no es el de la ultima vez (PALK)
ac_pt:          ld hl,ac_pm
                ld de,PALK
                ld b,16
apt_c:          ld a,(de)
                cp (hl)
                jr nz,apt_go
                inc hl
                inc de
                djnz apt_c
                ret
apt_go:         ld hl,ac_pm
                ld de,PALK
                ld bc,16
                ldir
                ld hl,PALT
                ld de,ac_pm             ; (ac_pm no cruza pagina: basta inc e)
apt_h:          ld a,(de)               ; nibble alto: ac_pm[L >> 4]
                rlca
                rlca
                rlca
                rlca
                ld c,a
                push de
                ld de,ac_pm
apt_l:          ld a,(de)               ; nibble bajo: ac_pm[L & 15]
                or c
                ld (hl),a
                inc e
                inc l
                ld a,l
                and 15
                jr nz,apt_l
                pop de
                inc e
                ld a,l
                or a
                jr nz,apt_h
                ret

ac_hash:        ld hl,0                 ; (sin la camara: si solo se mueve ella, acc_ok mueve los sprites)
                ld a,(ix+1)
                call ach
                ld a,(ix+2)
                call ach
                ld a,(ix+3)
                call ach
                ld a,(ix+4)
                call ach
                ld a,(ix+5)
                call ach
                ld a,(ix+6)
                call ach
                ld a,(ix+7)
                call ach
                ld a,(ix+9)
                call ach
                ld a,(ix+10)
                call ach
                ld a,(ix+16)
                call ach
                ld a,(ix+17)
                call ach
                call ac_tk              ; hablar solo cambia el dibujo del que habla: los demas conservan la cache al salir o quitarse un mensaje
                sbc a,a
                push af
                and 1                   ; el que habla: la pose que dibujara ac_draw (que avanza antes el contador)
                add a,(ix+45)
                srl a
                srl a
                srl a
                call ach
                pop af
                call ach
                push bc                 ; la paleta del actor (SO_PALETTE) cambia el dibujo
                push hl
                ld a,(ac_id)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,ACTPAL
                add hl,bc
                ld b,8
                ld a,(VAR_CURRENT_LIGHTS)       ; el bit 8 de las luces (paleta gris) tambien cambia el dibujo
                and 8
ach_p:          add a,(hl)
                rlca
                inc hl
                djnz ach_p
                pop hl
                pop bc
                call ach
                ld a,(ac_id)
                ld e,a
                ld d,0
                push hl
                ld hl,AC_OVF
                add hl,de
                ld a,(hl)
                pop hl
                call ach
                ex de,hl
                ret
; Z si la pagina de la hoja de la ranura ac_n - 1 ya tiene la celda ac_cp (del fondo ac_ppg) con la paleta de ahora; anota la nueva clave. Conserva HL
; Clave de paleta: 0 sin paleta, $FF gris (luces), actor + 1 con su paleta. Si una paleta de actor ha cambiado (PALEP), se olvida todo
ac_shc:         push hl
                ld a,(PALEP)
                ld hl,PALES
                cp (hl)
                jr z,ash_k
                ld (hl),a
                ld hl,SHKA
                ld de,SHKA+1
                ld bc,2*AC_MAX-1
                ld (hl),0
                ldir
ash_k:          ld a,(ac_pf)
                or a
                jr z,ash_p
                ld a,(VAR_CURRENT_LIGHTS)
                and 8
                ld a,$FF
                jr z,ash_p
                ld a,(ac_id)
                inc a
ash_p:          ld b,a
                ld a,(ac_ppg)
                ld c,a
                ld de,(ac_cp)
                ld a,(ac_n)
                dec a
                add a,a
                add a,SHKA mod 256
                ld l,a
                ld h,SHKA/256
                ld a,(hl)
                xor e
                ld (hl),e
                inc l
                ld e,a
                ld a,(hl)
                xor d
                ld (hl),d
                or e
                ld e,a
                ld h,SHKB/256
                ld a,(hl)
                xor b
                ld (hl),b
                dec l
                or e
                ld e,a
                ld a,(hl)
                xor c
                ld (hl),c
                or e
                pop hl
                ret

acd_xsk:        ld a,1                  ; celda fuera por la X: no gasta ranura, pero el actor no puede moverse con la camara sin dibujarse
                ld (ac_xs),a
                jp acd_skip

; A = campo 2 que se acaba de escribir en la ranura ac_n - 1: se guarda con el campo 1 (ac_cx) en SX. Conserva HL, DE y BC
ac_sxs:         push hl
                push af
                ld a,(ac_n)
                dec a
                add a,a
                add a,SX mod 256
                ld l,a
                ld h,SX/256
                ld a,(ac_cx)
                ld (hl),a
                inc l
                pop af
                ld (hl),a
                pop hl
                ret

; la camara se ha movido ac_dlt pixeles: C (bit 7 fuera) sprites del actor desde la ranura ac_n pasan a X - ac_dlt (SX y la ventana). Carry si alguno no
; cabe en los 9 bits de la X: entonces se dibuja entero (acc_miss vuelve a escribir todas sus ranuras). Conserva C
ac_mvx:         ld a,c
                and $7F
                ret z
                ld b,a
                ld a,(ac_n)
amx_l:          push bc
                push af
                add a,a
                add a,SX mod 256
                ld l,a
                ld h,SX/256
                ld e,(hl)
                inc l
                ld a,(hl)
                push af
                and 1
                ld d,a                  ; DE = X
                push hl
                ex de,hl
                ld bc,(ac_dlt)
                or a
                sbc hl,bc
                ex de,hl
                pop hl
                ld a,d
                cp 2
                jr nc,amx_out           ; por debajo de 0 o desde 512
                pop af
                and $FE
                or d
                ld (hl),a
                dec l
                ld (hl),e
                ld d,a                  ; D = campo 2, E = campo 1
                pop af
                push af
                push de
                call ac_slot
                pop de
                inc hl
                ld (hl),e
                inc hl
                ld (hl),d
                pop af
                pop bc
                inc a
                djnz amx_l
                or a
                ret
amx_out:        pop af
                pop af
                pop bc
                scf
                ret

; carry si hay mensaje y lo dice el actor ac_id (VAR_TALK_ACTOR). Conserva BC, DE y HL
ac_tk:          ld a,(HAVEMSG)
                or a
                ret z
                push hl
                ld hl,(VAR_TALK_ACTOR)
                ld a,(ac_id)
                cp l
                pop hl
                scf
                ret z
                ccf
                ret

ach:            ld d,h                 ; HL = HL * 31 + A
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                or a
                sbc hl,de
                add a,l
                ld l,a
                ret nc
                inc h
                ret

; HL = angulo (0, 90, 180, 270) -> A = direccion de v2: 0 izquierda, 1 derecha, 2 de frente, 3 de espaldas
ac_olddir:      ld a,h
                or a
                jr nz,aod_hi
                ld a,l
                cp 45
                jr c,aod_up
                cp 135
                jr c,aod_r
                cp 225
                jr c,aod_dn
                xor a
                ret
aod_hi:         ld a,l
                cp 59                   ; 315 - 256
                jr nc,aod_up
                xor a
                ret
aod_up:         ld a,3
                ret
aod_r:          ld a,1
                ret
aod_dn:         ld a,2
                ret

; IX = actor: sus sprites segun los fotogramas de su traje (TOOLS/costume2.py)
ac_bptr:        ld a,(ac_id)            ; HL = la entrada del actor en ACB (input.asm: el rectangulo que dibuja, para actorFromPos); carry si no tiene
                cp ACB_N+1
                ccf
                ret c
                dec a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,ACB
                add hl,de
                ret

ac_draw:        call ac_mkpal
                call ac_bptr            ; sin rectangulo hasta que se sepa cual es
                xor a
                jr c,acd_nb0
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
                inc hl
                ld (hl),a
acd_nb0:        xor a                   ; mascara de profundidad: solo si la sala la tiene y la caja del personaje tiene mascara
                ld (ac_mk),a
                ld a,(SS_REAL)          ; los datos de la sala cargada (la real si la actual es pseudo)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,ROOMDIR+13
                add hl,de
                ld a,(hl)
                or a
                jr z,acd_nomk
                ld (ac_mpg),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc de                  ; la mascara de la sala va detras de la palabra con el desplazamiento de la tabla de objetos
                inc de
                ld (ac_mbl),de
                ld a,(ix+16)
                ld hl,NBOXES
                cp (hl)
                jr nc,acd_nomk
                call box_rec
                jr c,acd_nomk
                ld de,6
                add hl,de
                ld a,(hl)
                or a
                jr z,acd_nomk
                ld a,1
                ld (ac_mk),a
acd_nomk:       ld a,(ix+5)             ; traje
                or a
                ret z
                cp 64
                ret nc
                ld e,a
                ld d,0
                ld hl,COSTDIR
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                ret z                   ; sin datos: no se dibuja
                ld (ac_dpg),a           ; COSTDIR -> el directorio del traje (TOOLS/pack_data.py): u8 na y na x (pagina, direccion) del sub-bloque de cada animacion
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_dir),de
                ld l,(ix+6)
                ld h,(ix+7)
                call ac_olddir
                ld c,a                  ; C = direccion
                ld a,(ac_id)            ; B = fotograma de overlay puesto (AC_OVF, sin el bit de pendiente de quitar)
                ld e,a
                ld d,0
                ld hl,AC_OVF
                add hl,de
                ld a,(hl)
                and $7F
                jr z,acd_noov
                ld b,a
                add a,a
                add a,a
                add a,c
                ld e,a                  ; E = 4 * fotograma + direccion
                ld a,(ix+10)
                or a
                jr nz,acd_ost
                ld a,e                  ; caminando con el overlay: sus poses (clave WALK_OVL + 4 * f + dir), si el traje las tiene (el overlay se conserva al caminar)
                add a,WALK_OVL
                push bc
                ld c,a
                call ac_key
                ld a,c
                pop bc
                jr c,acd_noov           ; no las tiene: la caminata sola (el overlay queda pendiente; al pararse se ve si se conserva)
                ld c,a
                jp acd_walk
acd_ost:        push bc                 ; parado con el overlay: su pose (clave 4 * f + dir)
                ld c,e
                call ac_key
                ld a,c
                pop bc
                jr c,acd_noov
                ld c,a
                ld a,(ac_id)            ; pendiente de quitar (caminar / inicio)? sigue solo si su lista lleva el bit 7 (no lo tocan esos miembros)
                ld e,a
                ld d,0
                ld hl,AC_OVF
                add hl,de
                bit 7,(hl)
                jr z,acd_ovk
                push hl
                call ac_list
                ld a,(hl)               ; pasos | bit 7
                pop hl
                rla
                jr c,acd_keep
                ld (hl),0               ; el overlay se pierde
                ld a,c
                and 3
                ld c,a
                jr acd_noov
acd_keep:       res 7,(hl)
acd_ovk:        push bc                 ; el overlay parado recorre sus pasos una vez (el contador avanza 8 por fotograma, una pose por fotograma como al caminar)
                call ac_list            ; y se queda en la ultima (los indigenas que se agachan y se levantan: animacion de una sola vez; con un solo paso no cambia nada)
                ld a,(hl)
                and $7F
                ld b,a
                dec a
                add a,a
                add a,a
                add a,a
                or 7                    ; contador maximo: ultima pose * 8 + 7
                ld e,a
                ld a,(ix+45)
                add a,8
                jr c,aov_c
                cp e
                jr c,aov_s
                jr z,aov_s
aov_c:          ld a,e
aov_s:          ld (ix+45),a
                pop bc
                jp acd_anim
acd_noov:       call ac_tk              ; hablando: la animacion 4 + direccion (la boca), si el traje la tiene
                jr nc,acd_nt
                ld a,c
                push bc
                add a,4
                ld c,a
                call ac_key
                ld a,c
                pop bc
                jr c,acd_nt
                ld c,a
                inc (ix+45)             ; dos poses (boca abierta y cerrada): cambian cada 8 fotogramas
                jp acd_anim
acd_nt:         call ac_key             ; caminar / parado: clave = direccion
                ret c
                ld a,(ix+10)            ; fotograma: 0 caminar; el resto, quieto
                or a
                jr z,acd_walk
                xor a                   ; quieto: la primera pose de caminar
                ld (ix+45),a
                jp acd_anim

; C = clave (animacion) -> el sub-bloque del traje que la tiene, mapeado (ac_blob, ac_cpage); carry si el traje no la tiene. Conserva BC
ac_key:         push bc
                ld a,(ac_dpg)
                call map_page
                pop bc
                ld hl,(ac_dir)
                ld a,c
                cp (hl)
                ccf
                ret c                   ; clave >= na
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                scf
                ret z
                ld (ac_cpage),a
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_blob),de
                push bc
                call map_page
                pop bc
                or a
                ret

; C = clave del sub-bloque mapeado -> HL = su lista (u8 pasos | bit 7, offsets)
ac_list:        ld hl,(ac_blob)
                inc hl
                inc hl
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,(ac_blob)
                add hl,de
                ret

acd_walk:       ld a,(ix+45)            ; caminando: una pose por fotograma (ScummVM, _animSpeed 0 en v2): el contador avanza 8 (acd_anim lo divide entre 8)
                add a,8
                ld (ix+45),a
acd_anim:       ld hl,(ac_blob)
                ld a,c
                cp (hl)                 ; numero de animaciones
                ret nc
                inc hl
                inc hl
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                or e
                ret z
                ld hl,(ac_blob)
                add hl,de               ; HL = lista de la animacion: pasos y offsets de fotograma
                ld a,(hl)
                and $7F                 ; el bit 7 es de los overlay que se conservan
                ld b,a
                inc hl
                or a
                ret z
                ld a,(ix+45)            ; pose = (contador / 8) mod pasos
                srl a
                srl a
                srl a
acd_mod:        cp b
                jr c,acd_md
                sub b
                jr acd_mod
acd_md:         ld e,a                  ; el contador vuelve a pose * 8 (+ lo de debajo): asi no da la vuelta a 256 en medio de un ciclo de 12 pasos
                rlca
                rlca
                rlca
                ld d,a
                ld a,(ix+45)
                and 7
                or d
                ld (ix+45),a
                ld a,e
                add a,a
                ld e,a
                ld d,0
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                and e
                inc a
                ret z                   ; $FFFF: sin imagen
                ld hl,(ac_blob)
                add hl,de
                push hl
                pop iy                  ; IY = fotograma: dx, dy, cw, ch, n, celdas
                ld l,(ix+1)             ; x * 8 - camara + dx
                ld h,(ix+2)
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,(ac_cam)
                or a
                sbc hl,de
                ld e,(iy+0)
                ld d,0
                bit 7,e
                jr z,acd_dx
                dec d
acd_dx:         add hl,de
                ld (ac_x),hl
                ld l,(ix+3)             ; y * 2 + dy
                ld h,(ix+4)
                add hl,hl
                ld a,(ix+17)            ; elevacion (con signo): el personaje se dibuja elevacion lineas mas arriba
                ld e,a
                rla
                sbc a,a
                ld d,a
                ex de,hl
                add hl,hl
                ex de,hl
                or a
                sbc hl,de
                ld e,(iy+1)
                ld d,0
                bit 7,e
                jr z,acd_dy
                dec d
acd_dy:         add hl,de
                ld (ac_y),hl
                call ac_bptr            ; su rectangulo: izquierda, derecha, arriba y abajo respecto de x * 8 e y * 2 (con la elevacion), con signo
                jr c,acd_nb
                ld a,(iy+0)
                ld (hl),a
                inc hl
                ld a,(iy+2)
                add a,a
                add a,a
                add a,a
                add a,(iy+0)
                ld (hl),a
                inc hl
                ld a,(ix+17)
                add a,a
                neg
                add a,(iy+1)
                ld d,a
                ld (hl),a
                inc hl
                ld a,(iy+3)
                add a,a
                add a,a
                add a,a
                add a,d
                ld (hl),a
acd_nb:
                ld b,(iy+4)
                xor a
                ld (ac_red),a
                ld a,(ac_n)             ; si no caben todos sus sprites (AC_MAX ranuras) no se dibuja a medias
                add a,b
                cp AC_MAX+1
                jr c,acd_fits
                ld a,1                  ; no cabe: se mira si cabria sin las celdas de pocos pixeles (ac_red: 1 pasada de cuenta, 2 dibujo reducido)
                ld (ac_red),a
acd_fits:
                ld a,(ac_mk)
                or a
                jr z,acd_nd
                push bc
                call ac_mkdec           ; la mascara de la sala bajo el personaje (puede quitar ac_mk)
                pop bc
acd_nd:         push iy                 ; las referencias del fotograma (u8 cx | cy << 4, u8 fondo, u8 indice) a AC_RB: las celdas estan en los fondos del traje,
                pop hl                  ; en otras paginas (TOOLS/costume2.py costume4)
                ld de,5
                add hl,de
                ld a,b
                add a,a
                add a,b
                ld c,a
                push bc
                ld b,0
                ld de,AC_RB
                ldir
                pop bc
                ld a,(ac_red)
                or a
                jr z,acd_go
                ld a,MINOR_PX           ; umbral de pixeles de una celda "menor": 4, 8, 16 y 32 hasta que quepa
                ld (ac_thr),a
                push bc                 ; pasada de cuenta (una sola, no dibuja nada): los pixeles de cada celda a AC_PX (acd_minor)
                ld a,$FF
                ld (ac_lpool),a
                ld hl,AC_RB
                call acd_cell
                pop bc
acd_rp:         push bc                 ; E = cuantas celdas son menores con el umbral ac_thr
                ld hl,AC_PX
                ld a,(ac_thr)
                ld e,0
arp_l:          inc hl
                cp (hl)
                jr c,arp_n
                inc e
arp_n:          djnz arp_l
                pop bc
                ld a,(ac_n)
                add a,b
                sub e
                cp AC_MAX+1
                jr c,acd_rok
                ld a,(ac_thr)
                add a,a
                cp 33
                ret nc                  ; ni sin la mitad de las celdas pequenas cabe
                ld (ac_thr),a
                jr acd_rp
acd_rok:        ld a,2
                ld (ac_red),a
acd_go:         ld a,$FF
                ld (ac_lpool),a         ; ningun fondo mapeado
                ld hl,AC_RB
acd_cell:       ld a,b
                or a
                ret z
                ld a,(hl)               ; referencia: posicion, fondo e indice
                ld (ac_pos),a
                inc hl
                ld c,(hl)
                inc hl
                ld a,(hl)
                inc hl
                ld (ac_nx),hl           ; la siguiente referencia
                push bc
                push af
                ld a,(ac_lpool)
                cp c
                jr z,acd_pok
                ld a,c                  ; otro fondo: su pagina y direccion en el directorio (tras las animaciones: u8 fondos y fondos x (pagina, direccion))
                ld (ac_lpool),a
                ld a,(ac_dpg)
                call map_page
                ld hl,(ac_dir)
                ld e,(hl)
                ld d,0
                inc hl
                add hl,de
                add hl,de
                add hl,de
                inc hl                  ; HL = fondo 0
                ld a,(ac_lpool)         ; (map_page estropea BC)
                ld e,a
                add hl,de
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_pool),de
                ld (ac_ppg),a
                call map_page
acd_pok:        pop af
                pop bc
                ld l,a
                ld h,0
                add hl,hl
                ld de,(ac_pool)
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a                  ; offset de la celda desde el principio del fondo
                add hl,de
                dec hl                  ; el codigo de abajo cuenta con un byte antes de las banderas
                ld (ac_cp),hl
                inc hl
                ld a,(hl)               ; banderas: bit 2 celda de 4 bpp
                ld (ac_fl),a
                push bc
                ld a,(ac_red)
                or a
                jr z,acd_nr
                call acd_minor          ; C: celda de pocos pixeles
                ld a,(ac_red)
                dec a
                jp z,acd_skip           ; pasada de cuenta: no se dibuja nada (acd_minor ha guardado los pixeles)
acd_r2:         jp c,acd_skip           ; dibujo reducido: las de pocos pixeles no
acd_nr:         ld a,(ac_pos)
                ld c,a
                and $0F
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(ac_x)
                add hl,de
                ld de,32
                add hl,de
                bit 7,h
                jp nz,acd_xsk
                ld (ac_cx),hl
                ld de,319
                or a
                sbc hl,de
                jp nc,acd_xsk
                ld a,c
                srl a
                srl a
                srl a
                srl a
                add a,a
                add a,a
                add a,a
                ld e,a
                ld d,0
                ld hl,(ac_y)
                add hl,de
                ld de,32
                add hl,de
                bit 7,h
                jp nz,acd_skip
                ld a,h
                or a
                jp nz,acd_skip
                ld a,l
                ld (ac_cy),a
                ld e,8                  ; filas visibles de la celda: lo que queda por encima de la zona de abajo (la interfaz, desde la fila UI_R0); como
                sub 32                  ; ScummVM, que recorta el dibujo al rectangulo de la sala. Entera por debajo: no se dibuja ni gasta ranura
                jr c,acd_rw             ; (por encima de la pantalla: la FPGA la recorta)
                sub UI_R0*8
                jp nc,acd_skip
                neg
                cp 8
                jr nc,acd_rw
                ld e,a
acd_rw:         ld a,e
                ld (ac_rows),a
                ld a,(ac_n)
                cp AC_MAX
                jp nc,acd_skip
                call ac_slot
                ld (ac_wb),hl
                ld a,(ac_n)
                inc a
                ld (ac_n),a
                ld (hl),1               ; activo (en un extra no hace nada)
                inc hl
                ld de,(ac_cx)
                ld (hl),e
                inc hl
                ld (hl),d               ; X bit 8 (el nibble alto, el color transparente, a 0: formato A)
                ld a,d
                call ac_sxs
                inc hl
                ld a,(ac_cy)
                ld (hl),a
                ld a,(ac_fl)
                bit 2,a
                jp nz,acd_b4            ; celda de 4 bpp (formato B)
                ld a,29
                call ac_wbo
                xor a
                ld (de),a               ; pagina 0: formato A
                ld a,12
                call ac_wbo             ; forma
                ld hl,(ac_cp)
                inc hl
                inc hl
                ld bc,8
                ldir
                ld a,(ac_fl)
                bit 0,a
                jr z,acd_m1
                push hl                 ; mascara completa
                ld hl,ac_mt
                ld b,8
acd_m0:         ld (hl),$FF
                inc hl
                djnz acd_m0
                pop hl
                call acd_mput
                jr acd_c0
acd_m1:         ld de,ac_mt
                ld bc,8
                ldir
                call acd_mput
acd_c0:         ld a,(ac_fl)
                bit 1,a
                jr z,acd_c1
                ld a,(hl)               ; color uniforme
                call acd_pmap
                ld c,a
                ld a,4
                call ac_wbo
                ex de,hl
                ld b,8
acd_c2:         ld (hl),c
                inc hl
                djnz acd_c2
                jp acd_skip
acd_c1:         ld a,4
                call ac_wbo
                ld a,(ac_pf)
                or a
                jr nz,acd_c1m
                ld bc,8
                ldir
                jp acd_skip
acd_c1m:        ld b,8
acd_c1l:        ld a,(hl)
                call acd_pmap
                ld (de),a
                inc hl
                inc de
                djnz acd_c1l
                jp acd_skip
acd_b4:         ld a,(ac_fl)            ; formato B (PLAN_TRAJES4.md): color transparente (nibble alto de las banderas; con paleta del actor, uno que esta no use)
                rrca
                rrca
                rrca
                rrca
                and 15
                ld b,a
                ld a,(ac_pf)
                or a
                jr z,ab4_t
                ld a,(ac_ptr)
                ld b,a
ab4_t:          ld a,b
                rlca
                rlca
                rlca
                rlca
                ld b,a
                ld a,2
                call ac_wbo
                ld a,(ac_cx+1)
                or b
                ld (de),a               ; X bit 8 y transparente
                call ac_sxs
                ld a,(ac_n)             ; la pagina de la hoja de esta ranura (bloque 0, POKE 2129 = 0)
                dec a
                call ac_shp
                push af
                ld a,29
                call ac_wbo
                pop af
                ld (de),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ex de,hl                ; DE = la celda en la hoja (solo llega a la sombra: el bloque 0 es de solo lectura)
                ld hl,(ac_cp)
                inc hl
                inc hl                  ; los 32 bytes de pixeles
                push de
                call ac_shc
                pop de
                jr nz,ab4_cp
                ld bc,32                ; la pagina de la ranura ya tiene esta celda con esta paleta: no se copia
                add hl,bc
                jr ab4_m
ab4_cp:         ld a,(ac_pf)
                or a
                jr nz,ab4_p
                ld bc,32
                ldir
                jr ab4_m
ab4_p:          ld b,PALT/256           ; con la paleta del actor: por la tabla PALT (DE = la celda en la hoja, alineada a 32)
ab4_pl:         ld c,(hl)
                ld a,(bc)
                ld (de),a
                inc hl
                inc de
                ld a,e
                and 31
                jr nz,ab4_pl
ab4_m:          ld de,ac_mt             ; la forma -> mascara (con la de profundidad)
                ld bc,8
                ldir
                call acd_mput
acd_skip:       ld hl,(ac_nx)
                pop bc
                dec b
                jp acd_cell

; C si la celda (ac_cp, ac_fl) es de 4 bpp y su forma tiene ac_thr pixeles o menos (solo se mira con ac_red != 0, cuando el actor no cabe)
; B = celdas que quedan (su indice en AC_PX). En la pasada de cuenta (ac_red 1) los pixeles se cuentan y se guardan ($FF: no es de 4 bpp, nunca es menor);
; en el dibujo reducido se leen de alli
acd_minor:      ld hl,AC_PX
                ld e,b
                ld d,0
                add hl,de
                ld a,(ac_red)
                dec a
                jr nz,amn_u
                push hl
                ld c,$FF
                ld a,(ac_fl)
                and 4
                jr z,amn_s
                ld hl,(ac_cp)
                ld de,34                ; tras las banderas, los 32 bytes de pixeles y luego los 8 de la forma
                add hl,de
                ld b,8
                ld c,0
amn_l:          ld a,(hl)
                inc hl
amn_b:          or a
                jr z,amn_n
                ld d,a
                dec a
                and d
                inc c
                jr amn_b
amn_n:          djnz amn_l
amn_s:          pop hl
                ld (hl),c
amn_u:          ld a,(ac_thr)
                inc a
                ld e,a
                ld a,(hl)
                cp e
                ret

                include "mask_px.inc"
