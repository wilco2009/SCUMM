; =====================================================================
;  agispr.asm - sprites del interprete AGI (se incluye desde agivm.asm)
;
;  Los objetos se dibujan con los 64 sprites por hardware del SD81 Booster (como los actores de SCUMM): cada celda de una vista se convierte
;  fuera de linea (TOOLS/agi2spr.py) en mosaicos de 8x8 con mascara y color por fila, y el Z80 solo reparte los mosaicos entre los sprites y
;  les pone posicion. El codigo esta en el overlay de texto (agitxt.asm / agihws.asm, bloque 1); aqui solo queda cargarlo y el punto de entrada.
; =====================================================================

PG_PRI2         equ 30
PG_OVB          equ 42
PG_PMX          equ 43
PG_BGB          equ 31
PG_BGA          equ 32
PG_VC0          equ 33
NVSLOT          equ 8

render:         jp OVL_RENDER

; Los overlays: A (OVERA.OVL: teclado, sprites, rotulos) a su pagina, mapeada siempre en el bloque 1 ($2000); B (OVERB.OVL: texto), que call_b mapea solo
; mientras corre
ov_load:        ld hl,nmo
                ld b,PG_OVL
                call ov_one
                ld hl,nmob
                ld b,PG_OVB
                call ov_one
                ld b,PG_OVL
                ld c,MAP_PORT
                ld a,1
                out (c),a
                ld hl,(ncyc)            ; modo real: doble buffer por hardware (el bitmap se muestra de golpe en cada VSYNC; los atributos van en vivo)
                ld a,h
                or l
                jr nz,ol_nb
                ld a,168+4              ; POKE 2057, 168 + bloque delantero (el 4; el HFILE esta en el 5)
                ld (2057),a
ol_nb:          jp OVL_SPRINIT
ov_one:         ld a,b
                ld (ov_pg),a
                call f_open
                cp $FF
                jr nz,ol_o
                ld a,14
                pop hl                  ; sin overlay no hay nada que hacer
                jp fatal
ol_o:           ld (fh),a
                ld hl,vlen
                ld bc,2
                call f_read_n
                ld a,(ov_pg)
                ld b,a
                ld c,MAP_PORT
                ld a,1
                out (c),a
                ld a,(fh)
                ld hl,$2000
                ld bc,(vlen)
                call f_read_n
                ld a,(fh)
                jp f_close
nmo:            defb "OVERA.OVL",0
nmob:           defb "OVERB.OVL",0
vlen:           defw 0
ov_pg:          defb 0

; HL = entrada del overlay B (OVB_*): se mapea en el bloque 1, se llama y se vuelve a poner el A
call_b:         ld b,PG_OVB
                ld c,MAP_PORT
                ld a,1
                out (c),a
                ld de,cb_ret
                push de
                jp (hl)
cb_ret:         ld b,PG_OVL
                ld c,MAP_PORT
                ld a,1
                out (c),a
                ret

; Ritmo de AGI (solo en modo real): cada ciclo dura v10 * 2,5 tramas (v10 son 1/20 s), con al menos un VSYNC, y los sprites se escriben justo despues,
; sin que el haz de video pille estados a medias. Mientras espera lee el teclado.
pace:           ld hl,(ncyc)
                ld a,h
                or l
                ret nz
                in a,(ClkPort)          ; tramas que ha tardado el ciclo (desde main_loop; las lecturas de la SD las pierden)
                and $7E
                rrca
                ld c,a
                ld a,(VARS+10)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                inc hl
                srl h
                rr l                    ; (5 * v10 + 1) / 2
                ld a,h
                or a
                jr z,pc_a
                ld l,60
pc_a:           ld a,l
                cp 61
                jr c,pc_b
                ld a,60
pc_b:           sub c                   ; las que faltan
                jr c,pc_1
                jr nz,pc_n
pc_1:           ld a,1
pc_n:           ld b,a
pc_f:           push bc
                call wait_frame
                pop bc
                djnz pc_f
                ret
wait_frame:     in a,(ClkPort)          ; descarta lo anterior y espera al siguiente VSYNC
                ld bc,700
wf_l:           push bc
                call OVL_KPOLL
                pop bc
                in a,(ClkPort)
                and $7E
                ret nz
                dec bc
                ld a,b
                or c
                jr nz,wf_l
                ret

; La linea de entrada solo se dibuja en modo real (ncyc = 0), cuando cambia lo escrito o accept.input
kb_prompt:      ld hl,(ncyc)
                ld a,h
                or l
                ret nz
                ld a,(accin)
                ld hl,kb_lacc
                cp (hl)
                jr z,kbp_ch
                ld (hl),a
                ld a,1
                ld (kb_dirty),a
kbp_ch:         ld a,(kb_dirty)
                or a
                ret z
                xor a
                ld (kb_dirty),a
                ld hl,OVB_PROMPT
                jp call_b

; A = pagina -> bloque 7 ($E000); map7_back lo devuelve a su pagina
map7:           ld b,a
                ld c,MAP_PORT
                ld a,7
                out (c),a
                ret
map7_back:      ld a,7
                jr map7

; A = pixel HiRes (0-255), sch = color, srow = direccion del bitmap de la fila
plot:           ld b,a
                and 7
                ld e,a
                ld d,0
                ld hl,masks
                add hl,de
                ld a,(hl)
                ld (pmk),a
                ld a,b
                rrca
                rrca
                rrca
                and 31
                ld e,a
                ld d,0
                ld hl,(sarow)
                add hl,de
                push hl                 ; byte de atributos
                ld hl,(srow)
                add hl,de
                ex de,hl                ; DE = byte del bitmap
                pop hl                  ; HL = byte de atributos
                ld a,(hl)
                ld b,a
                and 15
                ld (pk),a
                ld a,b
                rrca
                rrca
                rrca
                rrca
                and 15
                ld (pp),a
                ld a,(sch)
                ld b,a                  ; B = color nuevo
                ld a,(pk)
                ld c,a
                ld a,(pp)
                cp c
                jr nz,pl_two
                ld a,c                  ; celda de un solo color: sus bits estan a 0 y se quedan asi si el color es el mismo
                cp b
                jr z,pl_clr
                jr pl_ri
pl_two:         ld a,(pk)
                cp b
                jr z,pl_set
                ld a,(pp)
                cp b
                jr z,pl_clr
                push hl
                push de
                ld a,b
                rlca
                rlca
                rlca
                rlca
                ld e,a
                ld d,0
                ld hl,sdist_tab
                add hl,de
                push hl
                ld a,(pp)
                ld e,a
                add hl,de
                ld c,(hl)               ; distancia al papel
                pop hl
                ld a,(pk)
                ld e,a
                add hl,de
                ld a,(hl)               ; distancia a la tinta
                cp c
                pop de
                pop hl
                jr z,pl_ri
                jr c,pl_ri
                ld a,b                  ; el papel esta mas lejos que la tinta: sustituye al papel
                rlca
                rlca
                rlca
                rlca
                ld c,a
                ld a,(pk)
                or c
                ld (hl),a
                jr pl_clr
pl_ri:          ld a,(pp)
                rlca
                rlca
                rlca
                rlca
                or b
                ld (hl),a
pl_set:         ld a,(pmk)
                ld c,a
                ld a,(de)
                or c
                ld (de),a
                ret
pl_clr:         ld a,(pmk)
                cpl
                ld c,a
                ld a,(de)
                and c
                ld (de),a
                ret

masks:          defb 128,64,32,16,8,4,2,1
sch:            defb 0
srow:           defw 0
sarow:          defw 0
pk:             defb 0
pp:             defb 0
pmk:            defb 0
sw_force:       defb 0
kb_dirty:       defb 0
kb_lacc:        defb 0
accin:          defb 1
il_n:           defb 0
INBUF:          defs 41

                include "sprtab.inc"
