; =====================================================================
;  agie.asm - overlay A2: rotulos anchos al bitmap (agisw.asm), con la prioridad de la imagen por pixel. Pagina PG_OVE.
;  Lo mapea el nucleo en el bloque 1 en lugar del A1 (call_e) solo mientras dura el dibujo; el A1 (teclado, sprites) no esta
;  mapeado entonces, asi que el teclado se lee con kp_a2 (nucleo) y el orden de los objetos se copia de la pagina del A1 (sw_run).
; =====================================================================

                org $2000
                include "agires.inc"
HQ_FIX          equ $2040
SPN_FIX         equ HQ_FIX+1+NOBJ+NOBJ
SPH_FIX         equ SPN_FIX+1

                jp t_bgsave             ; OVE_BGSAVE
                jp sw_run               ; OVE_RUN
                jp t_bake               ; OVE_BAKE

; Tras t_sort (A1): el orden de los objetos (hq_cnt, ORD) se copia de la pagina del A1, que se asoma por el bloque 7; despues se arma el dibujo por software
sw_run:
                IF GFX4
                ret
                ELSE
                ld a,PG_OVL
                call map7
                ld hl,$E000+HQ_FIX-$2000
                ld de,hq_cnt
                ld bc,1+NOBJ+NOBJ
                ldir
                call map7_back
                call sw_scan
                call sw_close
                jp sw_comp
                ENDIF

                IF GFX4=0
hw_end:         jp unmap_win

; IX = objeto -> NC con la pagina de su bucle mapeada y cv_* puestos (cel_rd), o C si no hay celda: la pagina la dejo buscada el A1 (VPG)
cel_open:       ld a,(ix+O_X)
                cp 160
                jp nc,co_no
                ld a,(bk_on)            ; add.to.pic (t_bake): la pagina del bucle la busco el A1
                or a
                jr z,co_vp
                ld a,(bk_pg)
                jp cel_rd
co_vp:          push ix
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
                ELSE
t_bake:         ret                     ; 160w: los rotulos por software y add.to.pic se pintaran en 4 bpp (fase 3b)
; La imagen que acaba de dibujarse (4 bpp, 13.440 bytes) pasa a las paginas de fondo
t_bgsave:       ld a,PG_BGB
                call map_page
                ld hl,HR_BM
                ld de,LWIN
                ld bc,8192
                ldir
                ld a,PG_BGA
                call map_page
                ld hl,HR_BM+8192
                ld de,LWIN
                ld bc,PLANE4-8192
                ldir
                jp unmap_win
                ENDIF

hq_cnt:         defb 0
ORD:            defs NOBJ
VPG:            defs NOBJ
