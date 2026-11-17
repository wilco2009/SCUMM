; =====================================================================
;  ovlb.asm - overlay B del interprete v3 (D4 de SCUMM/V3/PLAN.md): pagina fisica 49, mapeada en el bloque 0 (solo lectura)
;  mientras corre uno de sus manejadores. Lleva los manejadores con subopcodes, expression, stringOps y la frase; en la fase 3,
;  expression. Se entra por call_ovb (vm_core.asm), que deja en el bloque 0 lo que hubiera al volver.
;  Se ensambla aparte (org $0000) con los simbolos del residente: aqui vm.sym (montaje de pruebas, test/build_test.sh);
;  el programa de la placa (fase 9) lo montara con scumm.sym como hace v2 con overlay.asm.
;  Las variables van en la RAM del nucleo (la pagina es de solo lectura).
; =====================================================================
                include "vm.sym"
                org $0000
                jp ovb_expr             ; OVB_EXPR (+0)
                jp ovb_op               ; OVB_OP (+3): el manejador de OPC en la tabla ovb_lo/ovb_hi (ovbtab.inc, generada)
                jp ovb_dd               ; OVB_DD (+6): displayDialog (cada fotograma, desde talk_frame)
                jp ovb_stoptalk         ; OVB_STOPTALK (+9)   fase 5: entradas para el overlay C
                jp ovb_hide             ; OVB_HIDE (+12)      IX = actor
                jp ovb_showact          ; OVB_SHOWACT (+15)   showActors
                jp ovb_follow           ; OVB_FOLLOW (+18)    IX = actor: setCameraFollows
                jp ovb_putact           ; OVB_PUTACT (+21)    IX = actor, C = sala, x en SC+0, y en SC+2
                jp ovb_vname            ; OVB_VNAME (+24)     fase 7: IX = verbo -> UIBUF = su nombre, A = bytes

; Despacho por opcode de los manejadores de B (TOOLS/gen_vmtables3.py: OVB_HANDLERS). Entra con DE = puntero tras el opcode, como un
; manejador nativo del residente; el ret del manejador vuelve a call_ovb.
ovb_op:         ld a,(OPC)
                ld l,a
                ld h,ovb_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                push bc
                ret

; ---- expression (o5_expression): pila de 32 bits ESTK (MAXESTK elementos), como el int de ScummVM
ovb_expr:       call rd_res
                ld hl,(RESV)
                push hl                 ; el destino (las instrucciones anidadas cambian RESV)
                xor a
                ld (ESP),a
ex_l:           ld a,(de)
                inc de
                cp $FF
                jp z,ex_end
                ld (OPC),a
                and $1F
                cp 1
                jr z,ex_val
                cp 6
                jp z,ex_op
                jp nc,err_badsub
                cp 2
                jp c,err_badsub
                push af                 ; 2 suma, 3 resta, 4 producto, 5 cociente: i = pop(); j = pop(); j op i
                ld hl,N2
                call ex_pop
                pop af
                push af
                cp 5
                jr nz,ex_nz
                ld hl,(N2)              ; i == 0: division por cero
                ld a,h
                or l
                ld hl,(N2+2)
                or h
                or l
                jp z,err_range
ex_nz:          ld hl,N1
                call ex_pop
                pop af
                push de
                cp 2
                jr z,ex_add
                cp 3
                jr z,ex_sub
                cp 4
                jr z,ex_mul
                call div32s
                jr ex_res
ex_mul:         call mul32
                jr ex_res
ex_add:         ld hl,(N1)
                ld de,(N2)
                add hl,de
                ld (NR),hl
                ld hl,(N1+2)
                ld de,(N2+2)
                adc hl,de
                ld (NR+2),hl
                jr ex_res
ex_sub:         ld hl,(N1)
                ld de,(N2)
                or a
                sbc hl,de
                ld (NR),hl
                ld hl,(N1+2)
                ld de,(N2+2)
                sbc hl,de
                ld (NR+2),hl
ex_res:         pop de
                call ex_push
                jp ex_l
ex_val:         call rd_vw1             ; 1: un valor
                ld h,b
                ld l,c
                call ex_sx
                call ex_push
                jp ex_l
ex_op:          call exec_one           ; 6: una instruccion; luego se apila la variable 0
                ld de,(SPTR)
                ld hl,(VARS)
                call ex_sx
                call ex_push
                jp ex_l
ex_end:         ld (SPTR),de
                pop hl
                ld (RESV),hl
                ld hl,NR
                call ex_pop
                ld bc,(NR)
                jp set_res

ex_sx:          ld (NR),hl              ; NR = HL con extension de signo
                ld a,h
                rla
                sbc a,a
                ld (NR+2),a
                ld (NR+3),a
                ret

ex_push:        ld a,(ESP)              ; NR -> pila (conserva DE). Fase 10d: sin ldir (ESTK no cruza un limite de 256 bytes)
                cp MAXESTK
                jp nc,err_range
                inc a
                ld (ESP),a
                add a,a
                add a,a
                add a,ESTK mod 256 - 4
                ld l,a
                ld h,ESTK / 256
                ld bc,(NR)
                ld (hl),c
                inc l
                ld (hl),b
                inc l
                ld bc,(NR+2)
                ld (hl),c
                inc l
                ld (hl),b
                ret

ex_pop:         ld a,(ESP)              ; pila -> (HL) (4 bytes; conserva DE); vacia: E_RANGE
                or a
                jp z,err_range
                dec a
                ld (ESP),a
                push de
                ex de,hl
                add a,a
                add a,a
                add a,ESTK mod 256
                ld l,a
                ld h,ESTK / 256
                ld bc,4
                ldir
                pop de
                ret
                IF (ESTK mod 256) + 4 * MAXESTK > 256
                defb ESTK_CRUZA_UN_LIMITE_DE_256
                ENDIF

                include "ovb4.asm"
                include "ovb4b.asm"
                include "ovb4c.asm"
ovb_code_end:
                include "ovbtab.inc"
ovb_end:
                IF $ > $2000
                defb EL_OVERLAY_B_NO_CABE_EN_8_KB
                ENDIF
