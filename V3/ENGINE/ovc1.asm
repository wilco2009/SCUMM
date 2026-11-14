; =====================================================================
;  ovc1.asm - overlay C (pagina fisica 48, mapeada en el bloque 0 por call_ovc): manejadores de sala, recursos y sistema que salieron del
;  overlay B (llena tras la fase 4b-2) y los que vengan con la fase 5. Se incluye desde ovlc.asm. Mismas convenciones que ovb4b.asm
;  (entran por ovc_op con DE = puntero tras el opcode, SPTR, temporales SC+n). Un overlay no puede llamar a las rutinas de otro: lo que
;  C necesite de B tiene que ir por call_ovb, o estar en el residente.
; =====================================================================

; sless (copia de la de ovb4.asm: un overlay no llama a las rutinas de otro): HL < DE con signo: carry si es menor, Z si igual (destruye H y D)
sless:          ld a,h
                xor $80
                ld h,a
                ld a,d
                xor $80
                ld d,a
                or a
                sbc hl,de
                ret

; ---------------------------------------------------------------- sala, recursos y sistema (en el modelo completo: sobre todo del anfitrion)
; roomOps: decode da ARGS = [a, b, k, operandos...]; la traza del modelo es [k, a, b] para k = 1..6 y [k, operandos...] para k >= 7.
; k = 1 (limites de la camara) escribe las variables; k = 3 guarda main_top y main_h; k = 2 y 4: a tiene que ser 0..256; k = 16: 1..16.
b_roomOps:      call decode
                ld (SPTR),de
                ld hl,(ARGS+4)          ; k
                ld a,l
                cp 13
                jp z,err_badsub         ; los nombres de fichero no estan soportados (como en el modelo)
                cp 14
                jp z,err_badsub
                cp 1
                jp z,ro_1
                cp 2
                jp z,ro_24
                cp 4
                jp z,ro_24
                cp 3
                jp z,ro_3
                cp 16
                jp z,ro_16
ro_fix:         cp 7                    ; la traza: k <= 6: [k, a, b]; k >= 7: [k, operandos]
                jr nc,ro_big
                ld bc,(ARGS)
                ld de,(ARGS+2)
                ld hl,(ARGS+4)
                ld (ARGS),hl
                ld (ARGS+2),bc
                ld (ARGS+4),de
                jp host_call
ro_big:         ld hl,(ARGS+4)          ; k
                ld (SC+18),hl
                ld hl,ARGS+6
                ld de,ARGS+2
                ld a,(ARGN)
                sub 3
                add a,a
                jr z,rb_0
                ld c,a
                ld b,0
                ldir
rb_0:           ld a,(ARGN)
                sub 2
                ld (ARGN),a
                ld hl,(SC+18)
                ld (ARGS),hl
                jp host_call
ro_24:          ld hl,(ARGS)            ; 0..256
                ld de,257
                or a
                sbc hl,de
                jp nc,err_range
                ld a,(ARGS+4)
                jp ro_fix
ro_3:           ld hl,(ARGS)
                ld (MAINTOP),hl
                ld hl,(ARGS+2)
                ld (MAINH),hl
                ld a,3
                jp ro_fix
ro_16:          ld hl,(ARGS+6)          ; 1..16
                ld a,h
                or a
                jp nz,err_range
                ld a,l
                or a
                jp z,err_range
                cp 17
                jp nc,err_range
                ld a,16
                jp ro_fix
ro_1:           ld hl,(CURRD+6)         ; setCameraMinMax: a y b a (160 .. ancho - 160); sin sala (o ancho 0): 320
                ld a,h
                or l
                jr nz,r1_w
                ld hl,320
r1_w:           ld de,-160
                add hl,de
                ld (SC+16),hl
                ld hl,(ARGS)
                call ro_clamp
                ld (VAR_CAMERA_MIN_X),hl
                ld hl,(ARGS+2)
                call ro_clamp
                ld (VAR_CAMERA_MAX_X),hl
                ld a,1
                jp ro_fix

; ro_clamp: HL = valor -> min(max(valor, 160), SC+16) (con signo)
ro_clamp:       ld (SC+14),hl
                ld de,160
                call sless
                jr nc,rc_1
                ld hl,160
                jr rc_2
rc_1:           ld hl,(SC+14)
rc_2:           ld (SC+14),hl
                ld de,(SC+16)
                call sless              ; valor < tope: se queda
                jr c,rc_3
                ld hl,(SC+16)
                ret
rc_3:           ld hl,(SC+14)
                ret

; lights: B1 b b; con c == 0, VAR_CURRENT_LIGHTS = a
b_lights:       call decode
                ld (SPTR),de
                ld hl,(ARGS+4)
                ld a,h
                or l
                jp nz,host_call
                ld hl,(ARGS)
                ld (VAR_CURRENT_LIGHTS),hl
                jp host_call

; resourceRoutines: subopcode (con sus bits de variable), el recurso (no en el 17) -> H [k, recurso]; k = 1..19
b_resourceRoutines:
                ld a,(OPC)
                ld (TOPOP),a
                ld a,(de)
                inc de
                ld (OPC),a
                ld (SC+0),a
                ld bc,0
                cp 17
                jr z,rr_nr
                call rd_vb1
rr_nr:          ld (SPTR),de
                ld (ARGS+2),bc
                ld a,(SC+0)
                bit 5,a
                jp nz,err_badsub
                and $1F
                jp z,err_badsub
                cp 20
                jp nc,err_badsub
                ld l,a
                ld h,0
                ld (ARGS),hl
                ld a,2
                ld (ARGN),a
                jp host_call

; systemOps: 1 (reinicio) y 3 (salir): E_HALT; 2 (pausa): nada
b_systemOps:    ld a,(de)
                inc de
                ld (SPTR),de
                cp 2
                ret z
                cp 1
                jr z,sy_halt
                cp 3
                jp nz,err_badsub
sy_halt:        ld a,E_HALT
                jp vm_err

; saveLoadGame: R B1 -> H [a] y el resultado fijo segun a & $E0 (0: 100, $20: 3, $40: 5, $80: 0, $C0: 7)
b_saveLoadGame: ld a,(OPC)
                ld (TOPOP),a
                call rd_res
                call rd_vb1
                ld (SPTR),de
                ld (ARGS),bc
                ld a,c
                and $E0
                ld hl,100
                jr z,sg_ok
                cp $20
                ld l,3
                jr z,sg_ok
                cp $40
                ld l,5
                jr z,sg_ok
                cp $80
                ld l,0
                jr z,sg_ok
                cp $C0
                ld l,7
                jp nz,err_badsub
sg_ok:          ld (SC+0),hl
                ld a,1
                ld (ARGN),a
                call host_call
                ld bc,(SC+0)
                jp set_res

