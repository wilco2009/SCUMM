; =====================================================================
;  agispr.asm - sprites del interprete AGI (se incluye desde agivm.asm)
;
;  Cada ciclo, tras update_objects, `render` restaura de la copia limpia de la imagen (paginas PG_BGB / PG_BGA) los rectangulos
;  que dibujo la vez anterior y vuelve a dibujar todos los objetos con anim y drawn, de menor a mayor prioridad (a igual
;  prioridad, por numero). Lo mismo que Interp.render() del modelo (TOOLS/agi_vm.py).
;
;  Las vistas se leen de VIEWnnn.GFX (u16 tamano + el recurso de AGI tal cual, TOOLS/agi2log.py) y se guardan enteras en una de
;  las 8 paginas de cache PG_VC0.. (se sustituye por turnos). Un pixel de AGI (160 de ancho) son 1 o 2 del HiRes (256): el
;  pixel a empieza en (8a+4)/5. Un pixel del sprite se dibuja si su prioridad >= la del plano PG_PRI2 (la de la imagen con las
;  lineas de control sustituidas, TOOLS/agi2hr.py sprite_priority). Cada celda de 8 pixeles tiene solo dos colores: un color
;  nuevo que no esta sustituye a papel o tinta (el mas cercano segun sdist_tab; si el papel y la tinta son iguales, a la tinta).
;
;  Memoria de trabajo: PROW (MSGBUF) = prioridad de la fila, CROW (TMPM) = colores de la fila de la celda.
; =====================================================================

PG_PRI2         equ 30
PG_BGB          equ 31
PG_BGA          equ 32
PG_VC0          equ 33
NVSLOT          equ 8
PROW            equ MSGBUF
CROW            equ TMPM

spr_init:       ld hl,vslot
                ld de,vslot+1
                ld bc,NVSLOT-1
                ld (hl),$FF
                ldir
                xor a
                ld (vnext),a
                ret

; Guarda la imagen que acaba de dibujarse como fondo limpio y olvida lo dibujado encima
spr_bg:         ld a,PG_BGB
                call map_page
                ld hl,HR_BM+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                ld a,PG_BGA
                call map_page
                ld hl,HR_ATT+256
                ld de,LWIN
                ld bc,PLANEB
                ldir
                ld hl,RECT
                ld de,RECT+1
                ld bc,4*NOBJ-1
                ld (hl),$FF
                ldir
                jp unmap_win

; ---------------------------------------------------------------------
;  Vistas: A = numero -> A = pagina donde esta el recurso, o $FF si no hay VIEWnnn.GFX
; ---------------------------------------------------------------------
vc_get:         cp $FF
                ret z
                ld c,a
                ld hl,vslot
                ld b,NVSLOT
vg_l:           ld a,(hl)
                cp c
                jr z,vg_hit
                inc hl
                djnz vg_l
                ld a,c
                ld (vwant),a
                ld a,(vnext)
                ld e,a
                inc a
                and NVSLOT-1
                ld (vnext),a
                ld a,e
                ld (vtry),a
                ld d,0
                ld hl,vslot
                add hl,de
                ld (hl),$FF
                ld a,(vwant)
                call mk_nmv
                ld hl,nmv
                call f_open
                cp $FF
                ret z
                ld (fh),a
                ld hl,vlen
                ld bc,2
                call f_read_n
                ld a,(vtry)
                add a,PG_VC0
                call map_page
                ld a,(fh)
                ld hl,LWIN
                ld bc,(vlen)
                call f_read_n
                ld a,(fh)
                call f_close
                call unmap_win
                ld a,(vtry)
                ld e,a
                ld d,0
                ld hl,vslot
                add hl,de
                ld a,(vwant)
                ld (hl),a
                ld a,(vtry)
                add a,PG_VC0
                ret
vg_hit:         ld a,NVSLOT
                sub b
                add a,PG_VC0
                ret

; A = numero -> "VIEW000.GFX" en nmv
mk_nmv:         ld hl,nmv+4
                jp mk_dig

; ---------------------------------------------------------------------
;  Restaurar y dibujar
; ---------------------------------------------------------------------
render:         ld a,(picvalid)
                or a
                ret z
                call spr_restore
                xor a
                ld (rpri),a
rn_p:           ld ix,OBJ
                xor a
                ld (rn),a
rn_o:           ld a,(ix+O_F1)
                and 3
                cp 3
                jr nz,rn_n
                ld a,(rpri)
                cp (ix+O_PRI)
                call z,spr_draw
rn_n:           ld de,32
                add ix,de
                ld hl,rn
                inc (hl)
                ld a,(hl)
                cp NOBJ
                jr c,rn_o
                ld hl,rpri
                inc (hl)
                ld a,(hl)
                cp 16
                jr c,rn_p
                ret

spr_restore:    ld hl,RECT
                ld b,NOBJ
sr_l:           push bc
                push hl
                ld a,(hl)
                cp $FF
                call nz,restore_rect
                pop hl
                ld (hl),$FF
                ld de,4
                add hl,de
                pop bc
                djnz sr_l
                ret

; HL = rectangulo (celda inicial, bytes por fila, fila inicial, fila final)
restore_rect:   ld a,(hl)
                ld (rcx),a
                inc hl
                ld a,(hl)
                ld (rnb),a
                inc hl
                ld a,(hl)
                ld (ry0),a
                inc hl
                ld a,(hl)
                ld (ry1),a
                ld a,PG_BGB
                ld de,HR_BM+256
                call rr_plane
                ld a,PG_BGA
                ld de,HR_ATT+256
                call rr_plane
                jp unmap_win

; A = pagina de la copia, DE = principio del plano en pantalla
rr_plane:       push de
                call map_page
                ld a,(ry0)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(rcx)
                ld e,a
                ld d,0
                add hl,de
                ld d,h
                ld e,l
                ld hl,LWIN
                add hl,de               ; HL = origen
                ex de,hl                ; DE = origen, HL = desplazamiento
                pop bc
                add hl,bc               ; HL = destino
                ex de,hl                ; HL = origen, DE = destino
                ld a,(ry1)
                ld b,a
                ld a,(ry0)
                ld c,a
                ld a,b
                sub c
                inc a
                ld (rrows),a
rp_r:           push hl
                push de
                ld a,(rnb)
                ld c,a
                ld b,0
                ldir
                pop de
                pop hl
                ld bc,32
                add hl,bc
                ex de,hl
                add hl,bc
                ex de,hl
                ld a,(rrows)
                dec a
                ld (rrows),a
                jr nz,rp_r
                ret

; A = pixel de AGI (0-160) -> HL = primer pixel HiRes de ese pixel: 8*(a/5) + (0,2,4,5,7)[a%5]
lo16:           ld b,5
                call div8
                ld e,a
                ld d,0
                ld hl,lo_t1
                add hl,de
                ld e,(hl)
                ld l,c
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de
                ret
lo_t1:          defb 0,2,4,5,7
lo_cnt:         defb 2,2,1,2,1
masks:          defb 128,64,32,16,8,4,2,1

; IX = objeto (anim y drawn), rn = su indice
spr_draw:       ld a,(ix+O_X)
                cp 160
                ret nc
                ld (sx),a
                ld a,(ix+O_VIEW)
                call vc_get
                cp $FF
                ret z
                ld (vpg),a
                call map_page
                ld a,(LWIN+2)
                cp (ix+O_LOOP)
                jp z,sd_no
                jp c,sd_no
                ld l,(ix+O_LOOP)
                ld h,0
                add hl,hl
                ld de,LWIN+5
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,LWIN
                add hl,de               ; HL = bucle
                ld a,(hl)
                cp (ix+O_CEL)
                jp z,sd_no
                jp c,sd_no
                ld b,h
                ld c,l                  ; BC = bucle
                ld e,(ix+O_CEL)
                ld d,0
                ex de,hl
                add hl,hl
                add hl,de
                inc hl
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                add hl,bc               ; HL = celda
                ld a,(hl)
                ld (spw),a
                inc hl
                ld a,(hl)
                ld (sph),a
                inc hl
                ld a,(hl)
                ld c,a
                and 15
                ld (strn),a
                xor a
                ld (smir),a
                bit 7,c
                jr z,sd_nm
                ld a,c
                rrca
                rrca
                rrca
                rrca
                and 7
                cp (ix+O_LOOP)
                jr z,sd_nm
                ld a,1
                ld (smir),a
sd_nm:          inc hl
                ld (srp),hl
                call unmap_win
                ld a,(spw)
                or a
                ret z
                cp 193
                ret nc
                ld a,(sph)
                or a
                ret z
                ; ancho que cabe en pantalla
                ld a,(sx)
                ld b,a
                ld a,160
                sub b
                ld b,a
                ld a,(spw)
                cp b
                jr c,sd_w
                ld a,b
sd_w:           ld (swcl),a
                ld c,a
                ld a,(sx)
                add a,c
                ld (plim),a
                ; fila superior: y - h + 1 (con signo)
                ld l,(ix+O_Y)
                ld h,0
                ld a,(sph)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                inc hl
                ld (spy16),hl
                bit 7,h
                jr nz,sd_y0
                ld a,h
                or a
                ret nz
                ld a,l
                cp 168
                ret nc
                jr sd_y1
sd_y0:          xor a
sd_y1:          ld (ry0),a
                ld a,(ix+O_Y)
                cp 168
                jr c,sd_y2
                ld a,167
sd_y2:          ld (ry1),a
                ; celdas HiRes que toca
                ld a,(sx)
                call lo16
                ld a,l
                ld (shx0),a
                rrca
                rrca
                rrca
                and 31
                ld (rcx),a
                ld a,(plim)
                call lo16
                dec hl
                ld a,l
                rrca
                rrca
                rrca
                and 31
                ld hl,rcx
                sub (hl)
                inc a
                ld (rnb),a
                ld a,(rn)
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                ld de,RECT
                add hl,de
                ld a,(rcx)
                ld (hl),a
                inc hl
                ld a,(rnb)
                ld (hl),a
                inc hl
                ld a,(ry0)
                ld (hl),a
                inc hl
                ld a,(ry1)
                ld (hl),a
                ld a,(sx)
                ld b,5
                call div8
                ld (sj0),a
                ld a,(sph)
                ld (srem),a
sd_row:         ld a,(vpg)
                call map_page
                ld hl,(srp)
                call decode_row
                ld (srp),hl
                call unmap_win
                ld a,(smir)
                or a
                call nz,mirror
                ld hl,(spy16)
                bit 7,h
                jr nz,sd_nx
                ld a,h
                or a
                ret nz                  ; ya por debajo de la pantalla
                ld a,l
                cp 168
                ret nc
                call row_plot
sd_nx:          ld hl,(spy16)
                inc hl
                ld (spy16),hl
                ld hl,srem
                dec (hl)
                jr nz,sd_row
                ret
sd_no:          jp unmap_win

; HL = origen (RLE de una fila de la celda) -> CROW con swidth colores (rellena con la transparencia); HL queda tras el 0 final
decode_row:     ld de,CROW
                ld a,(spw)
                ld c,a
dr_l:           ld a,(hl)
                inc hl
                or a
                jr z,dr_pad
                ld b,a
                rrca
                rrca
                rrca
                rrca
                and 15
                ld (drcol),a
                ld a,b
                and 15
                jr z,dr_l
                ld b,a
dr_in:          ld a,c
                or a
                jr z,dr_l
                dec c
                ld a,(drcol)
                ld (de),a
                inc de
                djnz dr_in
                jr dr_l
dr_pad:         ld a,c
                or a
                ret z
                ld b,a
                ld a,(strn)
dr_p:           ld (de),a
                inc de
                djnz dr_p
                ret

mirror:         ld a,(spw)
                ld c,a
                ld b,0
                ld hl,CROW
                add hl,bc
                dec hl
                ld de,CROW
                srl a
                ret z
                ld b,a
mi_l:           ld a,(de)
                ld c,(hl)
                ld (hl),a
                ld a,c
                ld (de),a
                inc de
                dec hl
                djnz mi_l
                ret

; A = fila de la imagen: dibuja los pixeles de CROW que pasan la prioridad
row_plot:       ld (spy),a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,HR_BM+256
                add hl,de
                ld (srow),hl
                ld a,(spy)
                call prow_decode
                ld hl,CROW
                ld (scp),hl
                ld a,(sx)
                ld e,a
                ld d,0
                ld hl,PROW
                add hl,de
                ld (spp),hl
                ld a,(sj0)
                ld (sj),a
                ld a,(shx0)
                ld (shx),a
                ld a,(swcl)
                ld (sn),a
rw_l:           ld hl,(scp)
                ld c,(hl)
                inc hl
                ld (scp),hl
                ld a,(strn)
                cp c
                jr z,rw_adv
                ld hl,(spp)
                ld a,(hl)
                cp (ix+O_PRI)
                jr z,rw_ok
                jr nc,rw_adv            ; la prioridad del fondo es mayor
rw_ok:          ld e,c
                ld d,0
                ld hl,ega2ch
                add hl,de
                ld a,(hl)
                ld (sch),a
                ld a,(sj)
                ld e,a
                ld d,0
                ld hl,lo_cnt
                add hl,de
                ld b,(hl)
                ld a,(shx)
rw_p:           push bc
                push af
                call plot
                pop af
                pop bc
                inc a
                djnz rw_p
rw_adv:         ld a,(sj)
                ld e,a
                ld d,0
                ld hl,lo_cnt
                add hl,de
                ld a,(shx)
                add a,(hl)
                ld (shx),a
                ld a,(sj)
                inc a
                cp 5
                jr c,rw_j
                xor a
rw_j:           ld (sj),a
                ld hl,(spp)
                inc hl
                ld (spp),hl
                ld hl,sn
                dec (hl)
                jr nz,rw_l
                ret

; A = fila -> PROW (prioridad de la fila hasta plim)
prow_decode:    ld l,a
                ld h,0
                add hl,hl
                ld a,PG_PRI2
                call map_page
                ld de,LWIN
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,PRI_RLE
                add hl,de
                ld de,PROW
pd_l:           ld a,(hl)
                inc hl
                ld b,a
                rrca
                rrca
                rrca
                rrca
                and 15
                ld c,a
                ld a,b
                and 15
                inc a
                ld b,a
                ld a,c
pd_f:           ld (de),a
                inc de
                djnz pd_f
                ld a,(plim)
                ld c,a
                ld a,e
                cp c
                jr c,pd_l
                jp unmap_win

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
                ld hl,(srow)
                add hl,de
                ex de,hl                ; DE = byte del bitmap
                ld a,d
                add a,$20               ; los atributos estan $2000 mas arriba
                ld h,a
                ld l,e                  ; HL = byte de atributos
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
                cp b
                jr z,pl_set
                ld a,(pp)
                cp b
                jr z,pl_clr
                ld a,(pk)
                ld c,a
                ld a,(pp)
                cp c
                jr z,pl_ri              ; papel = tinta: el color nuevo pasa a ser la tinta
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

                include "sprtab.inc"

nmv:            defb "VIEW000.GFX",0
vslot:          defs NVSLOT
vnext:          defb 0
vwant:          defb 0
vtry:           defb 0
vlen:           defw 0
vpg:            defb 0
rpri:           defb 0
rn:             defb 0
rcx:            defb 0
rnb:            defb 0
ry0:            defb 0
ry1:            defb 0
rrows:          defb 0
sx:             defb 0
spw:            defb 0
sph:            defb 0
strn:           defb 0
smir:           defb 0
swcl:           defb 0
plim:           defb 0
srp:            defw 0
spy16:          defw 0
srem:           defb 0
spy:            defb 0
srow:           defw 0
scp:            defw 0
spp:            defw 0
sj0:            defb 0
sj:             defb 0
shx0:           defb 0
shx:            defb 0
sn:             defb 0
sch:            defb 0
pk:             defb 0
pp:             defb 0
pmk:            defb 0
drcol:          defb 0
RECT:           defs 4*NOBJ
