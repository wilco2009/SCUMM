NOCACHE        equ 0                   ; 1: sin cache (para comparar sprites con y sin ella)
actors_update:  call ac_track
                ld a,(gf_have)
                or a
                ret z
                call gf_campx
                ld (ac_cam),hl
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
                or a
                ret z
                ld a,XD_MARK
                ld (ac_xd),a
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
                jr z,act_n
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
                jr c,act_n              ; parado, hablar: no cambian el overlay
act_s:          ld (hl),a
                jr act_n
act_0:          ld a,(hl)               ; caminar / inicio: el overlay queda pendiente de quitar (bit 7); ac_draw lo quita salvo que el traje diga que no lo toca
                or a
                jr z,act_n
                or $80
                ld (hl),a
act_n:          inc b
                ld a,b
                cp NACTORS
                jr c,act_l
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
                ld a,(HAVEMSG)          ; hablando: tambien avanza (la boca)
                or a
                jr z,acc_ok
                ld a,(ac_id)
                ld b,a
                ld a,(VAR_TALK_ACTOR)
                cp b
                jr z,acc_miss
acc_ok:         push hl
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
                ld a,(hl)               ; cuantos sprites usa
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
                ret
acc_miss:       ld a,(ac_n)
                ld (ac_n0),a
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
ac_mkpal:       ld a,(ac_id)
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
                push de
                push hl
                ld e,a
                and 15
                ld c,a
                ld b,0
                ld hl,ac_pm
                add hl,bc
                ld d,(hl)               ; D = papel nuevo
                ld a,e
                rrca
                rrca
                rrca
                rrca
                and 15
                ld c,a
                ld hl,ac_pm
                add hl,bc
                ld a,(hl)
                rlca
                rlca
                rlca
                rlca
                and $F0
                or d
                pop hl
                pop de
                pop bc
                ret

ac_hash:        ld hl,(ac_cam)
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
                ld a,(ix+45)
                srl a
                srl a
                srl a
                call ach
                ld a,(HAVEMSG)
                call ach
                ld a,(VAR_TALK_ACTOR)
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
                xor a
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
ach:            ld d,h                  ; HL = HL * 31 + A
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
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_blob),de
                ld (ac_cpage),a
                call map_page
                ld l,(ix+6)
                ld h,(ix+7)
                call ac_olddir
                ld c,a                  ; C = direccion
                ld a,(ac_id)            ; un fotograma de overlay puesto y el actor parado: su pose, si el traje la tiene (animacion 4 * fotograma + direccion)
                ld e,a
                ld d,0
                ld hl,AC_OVF
                add hl,de
                ld a,(hl)
                or a
                jr nz,acd_ovs
                ld b,a                  ; sin overlay y caminando: sus poses de caminar (clave = direccion) de las paginas del traje, salvo que este hablando (acd_wov)
                ld a,(ix+10)
                or a
                jp nz,acd_noov
                ld a,(HAVEMSG)
                or a
                jp z,acd_wov
                ld a,(ac_id)
                ld e,a
                ld a,(VAR_TALK_ACTOR)
                cp e
                jp z,acd_noov
                jp acd_wov
acd_ovs:        and $7F
                ld b,a
                ld a,(ix+10)
                or a
                jp z,acd_wov            ; caminando con overlay: sus poses de caminar con el overlay puesto (acd_wov)
                ld a,b
                add a,a
                add a,a
                add a,c
                ld b,a
                ld hl,(ac_blob)
                cp (hl)
                jp nc,acd_noov
                inc hl
                inc hl
                inc hl
                ld e,b
                ld d,0
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                jp z,acd_noov
                ld a,(ac_id)            ; overlay pendiente de quitar (caminar / inicio)? sigue solo si su lista lleva el bit 7 (no lo tocan esos miembros)
                ld e,a
                ld d,0
                ld hl,AC_OVF
                add hl,de
                bit 7,(hl)
                jr z,acd_ovk
                push hl
                ld hl,(ac_blob)
                inc hl
                inc hl
                inc hl
                ld e,b
                ld d,0
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,(ac_blob)
                add hl,de
                ld a,(hl)               ; pasos | bit 7
                pop hl
                rla
                jr c,acd_keep
                ld (hl),0               ; el overlay se pierde
                jp acd_noov
acd_keep:       res 7,(hl)
acd_ovk:        ld c,b
                xor a
                ld (ix+45),a
                jp acd_anim
acd_wov:        ld hl,(ac_blob)         ; B = fotograma de overlay (0: ninguno), C = direccion. Tras las listas de animaciones del traje: pagina y direccion de su directorio de poses de caminar
                push hl                 ; con overlay (TOOLS/costume2.py, walk_overlay_blob; pagina 0: no hay): u8 n y n x (4 * fotograma + direccion, pagina, direccion); cada una es un traje con
                ld hl,(ac_cpage-1)      ; esa direccion (animacion = direccion) con las poses de caminar con ese fotograma puesto. Si algo falla se vuelve al traje de siempre
                push hl
                ld hl,(ac_blob)
                ld e,(hl)
                ld d,0
                inc hl
                inc hl
                inc hl
                add hl,de
                add hl,de
                ld a,(hl)
                or a
                jr z,acd_wn
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                push bc
                push de
                call map_page
                pop hl
                pop bc
                ld a,(hl)
                inc hl
                or a
                jr z,acd_wf
                ld e,a
                ld a,b                  ; clave: 4 * fotograma + direccion
                add a,a
                add a,a
                add a,c
                ld d,a
acd_ws:         ld a,(hl)
                cp d
                jr z,acd_wy
                inc hl
                inc hl
                inc hl
                inc hl
                dec e
                jr nz,acd_ws
                jr acd_wf
acd_wy:         inc hl
                ld a,(hl)
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld (ac_blob),de
                ld (ac_cpage),a
                push bc
                call map_page
                pop bc
                ld hl,(ac_blob)
                inc hl
                inc hl
                inc hl
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                jr z,acd_wf
                pop hl                  ; vale: sus poses de caminar. Como en ScummVM (_animSpeed 0 en v2) cada fotograma avanza una pose: acd_anim divide el contador
                pop hl                  ; entre 8, asi que aqui suma 7 y acd_walk 1 mas
                ld a,(ix+45)
                add a,7
                ld (ix+45),a
                jp acd_walk
acd_wf:         pop hl
                ld a,h
                ld (ac_cpage),a
                pop hl
                ld (ac_blob),hl
                push bc
                call map_page
                pop bc
acd_wn2:        ld a,b                  ; no hay esas poses: si llevaba un overlay que no se conserva al caminar, la caminata sola; si no, la pose de siempre
                or a
                jp z,acd_noov
                ld b,0
                jp acd_wov
acd_wn:         pop hl
                pop hl
                jr acd_wn2
acd_noov:       ld a,(HAVEMSG)          ; hablando: la animacion 4 + direccion (la boca), si el traje la tiene
                or a
                jr z,acd_nt
                ld a,(ac_id)
                ld b,a
                ld a,(VAR_TALK_ACTOR)          ; VAR_TALK_ACTOR
                cp b
                jr nz,acd_nt
                ld a,c
                add a,4
                ld c,a
                ld hl,(ac_blob)
                cp (hl)
                jr nc,acd_tno
                inc hl
                inc hl
                inc hl                  ; tras el numero de animaciones y el offset del fondo de celdas
                ld e,c
                ld d,0
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                jr z,acd_tno
                inc (ix+45)             ; la animacion de hablar tiene dos poses (boca abierta y cerrada): cambian cada 8 fotogramas
                jr acd_anim
acd_tno:        ld a,c
                sub 4
                ld c,a
acd_nt:         ld a,(ix+10)            ; fotograma: 0 caminar; el resto, quieto
                or a
                jr z,acd_walk
                xor a                   ; quieto: la primera pose de caminar
                ld (ix+45),a
                jr acd_anim
acd_walk:       inc (ix+45)             ; contador de fotogramas de caminata
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
acd_md:         add a,a
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
                ld a,(ac_n)             ; si no caben todos sus sprites (AC_MAX ranuras) no se dibuja a medias
                add a,b
                cp AC_MAX+1
                ret nc
                ld a,(ac_mk)
                or a
                jr z,acd_nd
                push bc
                call ac_mkdec           ; la mascara de la sala bajo el personaje (puede quitar ac_mk)
                pop bc
acd_nd:         push iy
                pop hl
                ld de,5
                add hl,de
acd_cell:       ld a,b
                or a
                ret z
                ld a,(hl)               ; referencia: cx | cy << 4 y el indice de la celda en el fondo de celdas del traje (TOOLS/costume2.py)
                ld (ac_pos),a
                inc hl
                ld a,(hl)
                inc hl
                ld (ac_nx),hl           ; la siguiente referencia
                ld l,a
                ld h,0
                add hl,hl
                ex de,hl                ; DE = 2 * indice
                ld hl,(ac_blob)
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a                  ; HL = offset de la tabla de celdas
                add hl,de
                ld de,(ac_blob)
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a                  ; HL = offset de la celda (banderas, forma, mascara, color)
                add hl,de
                dec hl                  ; el codigo de abajo cuenta con un byte antes de las banderas
                ld (ac_cp),hl
                inc hl
                ld a,(hl)               ; banderas: bit 0 mascara completa, bit 1 color uniforme
                ld (ac_fl),a
                push bc
                ld a,(ac_pos)
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
                jp nz,acd_skip
                ld (ac_cx),hl
                ld de,319
                or a
                sbc hl,de
                jp nc,acd_skip
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
                inc hl
                ld a,(ac_cy)
                ld (hl),a
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
                jr acd_skip
acd_c1m:        ld b,8
acd_c1l:        ld a,(hl)
                call acd_pmap
                ld (de),a
                inc hl
                inc de
                djnz acd_c1l
acd_skip:       ld hl,(ac_nx)
                pop bc
                dec b
                jp acd_cell

                include "mask_px.inc"
