; =====================================================================
;  overlay2.asm - el segundo overlay: el sonido (snd.asm) y guardar/cargar (save.asm), codigo frio que no tiene que estar en el overlay 1 (overlay.asm).
;  Vive en su propia pagina (OVL2_PAGE) y solo se mapea en el bloque 0 mientras se ejecuta, entrando por las puertas ovg_* de overlay.asm y saliendo por ov2_exit.
;  Reglas: aqui dentro no se puede llamar a nada del overlay 1 ni a rutinas del residente que lo llamen (OVL_xxx): el bloque 0 es este overlay. Los datos son de RAM.
;  Se ensambla despues de overlay.asm (usa overlay.sym: el programa y el overlay 1); el programa incluye overlay2.bin al principio de la zona de imagenes.
; =====================================================================
                include "overlay.sym"
                org $0000
                defs ovg_tick           ; (los primeros bytes de la pagina no se usan: las puertas del overlay 1 estan en $0036)
                org ovg_tick
                jp ov2_ev               ; continuacion de ovg_ev (la direccion siguiente a su OUT)
                org ovg_sv
                jp ov2_tick             ; continuacion de ovg_tick
                org ovg_sv+7
                jp ov2_sv               ; continuacion de ovg_sv
                org ovg_er+7
                jp ov2_err              ; continuacion de ovg_er
                org ovg_ho+7
                jp ov2_ho               ; continuacion de ovg_ho
                org ovg_ret-6
ov2_exit:       ld bc,OVL_PAGE*256+MAP_PORT     ; el overlay 1 vuelve al bloque 0 y la instruccion siguiente (ovg_ret) es su RET
                xor a
                out (c),a
                IF $ - ovg_ret
                defb OV2_EXIT_NO_CUADRA_CON_OVG_RET
                ENDIF
                org ovg_ret+1

ov2_ev:         ld a,d
                call snd_event
                jp ov2_exit
ov2_tick:       call snd_tick
                jp ov2_exit
ov2_sv:         call sv_saveload
                jp ov2_exit

ov2_err:        call sc_hide_sprites     ; el mensaje de los errores fatales (ov_err, overlay.asm, espera la tecla); solo llama al residente
                xor a
                ld (tx_on),a
                ld a,(ERR)
                ld l,a
                ld h,0
                ld de,ERRPOS
                ld b,2
                push hl
                ld hl,tx_err
                call put_str
                pop hl
                call put_num
                ld a,' '                ; que fallo: A = primer operando, O = opcode (decimal), S = script de la ranura en curso
                call put_chr
                ld a,'A'
                call put_chr
                ld hl,(ARGS)
                ld b,3
                call put_num
                ld a,' '
                call put_chr
                ld a,'O'
                call put_chr
                ld a,(OPC)
                ld l,a
                ld h,0
                ld b,3
                call put_num
                ld a,(CUR)
                cp $FF
                jr z,sme_k
                push af
                ld a,' '
                call put_chr
                ld a,'S'
                call put_chr
                pop af
                call slot_addr
                inc hl
                inc hl
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ld b,3
                call put_num
sme_k:          jp ov2_exit

                include "ovl2_ops.asm"
                include "snd.asm"
                include "save.asm"
                IF $ > OV2_COPY
                defb EL_OVERLAY2_NO_CABE_EN_OV2_COPY
                ENDIF
