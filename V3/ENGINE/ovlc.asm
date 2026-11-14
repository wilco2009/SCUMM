; =====================================================================
;  ovlc.asm - overlay C del interprete v3: pagina fisica 48, mapeada en el bloque 0 (solo lectura) mientras corre uno de sus manejadores
;  (call_ovc, vm_core.asm). Como el B (ovlb.asm): se ensambla aparte (org $0000) con los simbolos del residente (vm.sym) y las variables van en
;  la RAM del nucleo. Su despacho por opcode es ovc_lo/ovc_hi (ovctab.inc, generada por gen_vmtables3.py desde OVC_HANDLERS).
; =====================================================================
                include "vm.sym"
                org $0000
                jp ovc_op               ; OVC_OP (+0): el manejador de OPC en la tabla ovc_lo/ovc_hi

ovc_op:         ld a,(OPC)
                ld l,a
                ld h,ovc_lo/256
                ld c,(hl)
                inc h
                ld b,(hl)
                push bc
                ret

                include "ovc1.asm"
                include "ovctab.inc"
ovc_end:
                IF $ > $2000
                defb EL_OVERLAY_C_NO_CABE_EN_8_KB
                ENDIF
