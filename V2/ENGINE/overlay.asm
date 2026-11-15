; =====================================================================
;  overlay.asm - el codigo del programa que no cabe por debajo de $8000: interfaz (ui.asm), camara (cam.asm) y personajes (actors.asm).
;  Se ensambla aparte (org $0000) y en el arranque scumm.asm lo copia a una pagina de la RAM extendida y la mapea en el bloque 0
;  (solo lectura, sin ROM: los sprites y los POKE siguen activos). Las variables estan en RAM (ovl_vars.inc).
;  Montaje en tres pasos (compila_scumm.bat): pasmo scumm.asm; pasmo overlay.asm (usa scumm.sym); pasmo scumm.asm otra vez (incluye overlay.bin).
; =====================================================================
                include "scumm.sym"
                org $0000
                jp ui_init
                jp ui_update
                jp ui_click
                jp cam_update
                jp actors_update
                jp host_ops
                jp ov_init
                jp snd_event
                jp snd_tick
                jp dk_entry
                jp hr_ui
                jp dk_mask
                jp ms_poll
                jp ov_err

ov_init:        call sdx_ini
                ld hl,NAMEOV            ; sin nombres cambiados
                ld de,NAMEOV+1
                ld bc,NNAMES*NM_SIZE+NACTORS*3-1
                ld (hl),0
                ldir
                ld hl,160               ; camara: seguir al protagonista, centrada
                ld (cam_cx),hl
                ld a,2
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
                ld a,1
                ld (cam_new),a
                ld hl,0
                ld (cam_dest),hl
                xor a
                ld (ac_n),a
                ret

; error fatal: ERROR n A<primer operando> O<opcode> S<script>, y espera una tecla (lo llama sm_err de scumm.asm)
ov_err:         call sc_hide_sprites
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
sme_k:          call sc_wait_key
                ret

                include "ui.asm"
                include "hrui.asm"
                include "cam.asm"
                include "actors.asm"
                include "snd.asm"
                include "dark.asm"
                include "save.asm"
                include "mouse.asm"
                IF $ > $2000
                defb EL_OVERLAY_NO_CABE_EN_8_KB
                ENDIF
