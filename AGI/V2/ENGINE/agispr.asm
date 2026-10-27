; =====================================================================
;  agispr.asm - sprites del interprete AGI (se incluye desde agivm.asm)
;
;  Los objetos se dibujan con los 64 sprites por hardware del SD81 Booster (como los actores de SCUMM): cada celda de una vista se convierte
;  fuera de linea (TOOLS/agi2spr.py) en mosaicos de 8x8 con mascara y color por fila, y el Z80 solo reparte los mosaicos entre los sprites y
;  les pone posicion. El codigo esta en el overlay de texto (agitxt.asm / agihws.asm, bloque 1); aqui solo queda cargarlo y el punto de entrada.
; =====================================================================

PG_PRI2         equ 30
PG_VC0          equ 33
NVSLOT          equ 8

render:         jp OVL_RENDER

; El overlay (TEXT.OVL) a su pagina, que se queda mapeada en el bloque 1 ($2000)
ov_load:        ld hl,nmo
                call f_open
                cp $FF
                jr nz,ol_o
                ld a,14
                jp fatal
ol_o:           ld (fh),a
                ld hl,vlen
                ld bc,2
                call f_read_n
                ld b,PG_OVL
                ld c,MAP_PORT
                ld a,1
                out (c),a
                ld a,(fh)
                ld hl,$2000
                ld bc,(vlen)
                call f_read_n
                ld a,(fh)
                call f_close
                jp OVL_SPRINIT
nmo:            defb "TEXT.OVL",0
vlen:           defw 0
