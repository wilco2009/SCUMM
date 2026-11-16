; =====================================================================
;  ovld.asm - overlay D del interprete v3 (fase 6): pagina fisica 46, mapeada en el bloque 0 (solo lectura) mientras corre una de sus
;  entradas (call_ovd, vm_core.asm). Lleva la geometria de las cajas (geom.asm) y la caminata (walk.asm). Como el B y el C: se ensambla aparte
;  (org $0000) con los simbolos del residente (vm.sym); sus variables estan en el bloque 7 (GW). No tiene despacho por opcode: los cuatro
;  opcodes de caminata (walkActorTo, walkActorToActor, walkActorToObject, waitForActor) leen sus operandos en el overlay C (ovc6.asm) y
;  entran aqui por OVD_STARTWALK / OVD_ADJUST. IX = actor en todas las entradas (se conserva).
; =====================================================================
                include "vm.sym"
                org $0000
                jp ovd_walk             ; OVD_WALK (+0): walkActors (cada fotograma con algun actor de la sala en movimiento)
                jp adjust_xy            ; OVD_ADJUST (+3): adjustXYToBeInBox(IX; WKX, WKY) -> WKX, WKY, WKBOX
                jp start_walk           ; OVD_STARTWALK (+6): startWalkActor(IX; WKX, WKY, WKDIR)
                jp ovd_calcmf           ; OVD_CALCMF (+9): calcMovementFactor(_walkdata.next) (actorOps 2 con el actor en movimiento)
                jp actors_run           ; OVD_ACTORS (+12): los sprites de los actores (fase 8; solo en el programa)

                include "geom.asm"
                include "walk.asm"
                IF PROGRAM
                include "ovd_act.asm"
                ELSE
actors_run:     ret
                ENDIF
ovd_end:
                IF $ > $2000
                defb EL_OVERLAY_D_NO_CABE_EN_8_KB
                ENDIF
