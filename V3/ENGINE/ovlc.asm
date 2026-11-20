; =====================================================================
;  ovlc.asm - overlay C del interprete v3: pagina fisica 48, mapeada en el bloque 0 (solo lectura) mientras corre uno de sus manejadores
;  (call_ovc, vm_core.asm). Como el B (ovlb.asm): se ensambla aparte (org $0000) con los simbolos del residente (vm.sym) y las variables van en
;  la RAM del nucleo. Su despacho por opcode es ovc_lo/ovc_hi (ovctab.inc, generada por gen_vmtables3.py desde OVC_HANDLERS).
; =====================================================================
                include "vm.sym"
                org $0000
                jp ovc_op               ; OVC_OP (+0): el manejador de OPC en la tabla ovc_lo/ovc_hi
                jp ovc_sent             ; OVC_SENT (+3): checkAndRunSentenceScript (cada fotograma con frases en cola)
                jp ovc_start            ; OVC_START (+6): startScene (C = sala)
                jp ovc_room             ; OVC_ROOM (+9): load_room_state (C = sala, B = 1: con cajas)
                jp ovc_sentadd          ; OVC_SENTADD (+12): doSentence desde fuera (APIVERB, APIN = a, APIA = b)
                jp ovc_movecam          ; OVC_MOVECAM (+15): moveCamera (fase 5b; cada fotograma con la sala en uso)
                IF PROGRAM
                jp sl_entry             ; OVC_SLOAD (+18): guardar / cargar desde fuera de un script (C = el byte a del opcode; el bucle principal con DBG_SAVE; fase 9)
                jp sl_name1             ; OVC_NAME1 (+21): saveLoadVars 2: el nombre de una partida en una cadena (SC+9 = id; SC+4 = el primero del rango; fase 9)
                jp dbg_room             ; OVC_DBGROOM (+24): ir a la sala APIN (DBG_ROOM del bucle principal; 10g)
                ELSE
                ret                     ; (el nucleo de pruebas no guarda: el resultado del opcode es el del modelo sin partidas)
                nop
                nop
                ret
                nop
                nop
                ret
                nop
                nop
                ENDIF

ovc_op:         ld a,(OPC)
                ld l,a
                ld h,ovc_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                push bc
                ret

                include "ovc1.asm"
                include "ovc5.asm"
                include "ovc6.asm"
                include "ovc7.asm"
                IF PROGRAM
                include "ovc9.asm"      ; fase 9: guardar y cargar
                ENDIF
ovc_code_end:
                include "ovctab.inc"
ovc_end:
                IF $ > $2000
                defb EL_OVERLAY_C_NO_CABE_EN_8_KB
                ENDIF
