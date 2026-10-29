; =====================================================================
;  agie.asm - overlay A2: rotulos anchos al bitmap (agisw.asm), con la prioridad de la imagen por pixel. Pagina PG_OVE.
;  Lo mapea el nucleo en el bloque 1 en lugar del A1 (call_e) solo mientras dura el dibujo; el A1 (teclado, sprites) no esta
;  mapeado entonces, asi que el teclado se lee con kp_a2 (nucleo) y el orden de los objetos se copia de la pagina del A1 (sw_run).
; =====================================================================

                org $2000
                include "agires.inc"
HQ_FIX          equ $2040

                jp t_bgsave             ; OVE_BGSAVE
                jp sw_run               ; OVE_RUN

; Tras t_sort (A1): el orden de los objetos (hq_cnt, ORD) se copia de la pagina del A1, que se asoma por el bloque 7; despues se arma el dibujo por software
sw_run:         ld a,PG_OVL
                call map7
                ld hl,$E000+HQ_FIX-$2000
                ld de,hq_cnt
                ld bc,1+NOBJ+NOBJ
                ldir
                call map7_back
                call sw_scan
                call sw_close
                jp sw_comp

hw_end:         jp unmap_win

; IX = objeto -> NC con la pagina de su bucle mapeada y cv_* puestos (cel_rd), o C si no hay celda: la pagina la dejo buscada el A1 (VPG)
cel_open:       ld a,(ix+O_X)
                cp 160
                jp nc,co_no
                push ix
                pop hl
                ld a,l
                rlca
                rlca
                rlca
                and 7
                ld l,a
                ld a,h
                sub OBJ>>8
                rlca
                rlca
                rlca
                or l
                ld e,a
                ld d,0
                ld hl,VPG
                add hl,de
                ld a,(hl)
                cp $FF
                jp z,co_no
                jp cel_rd

                include "agicel.asm"
                include "agisw.asm"

hq_cnt:         defb 0
ORD:            defs NOBJ
VPG:            defs NOBJ
