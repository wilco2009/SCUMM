; =====================================================================
;  agicel.asm - lo que comparten los overlays A1 (agia.asm) y A2 (agie.asm): la celda abierta de un objeto (cv_*) y el pixel HiRes de uno de AGI
; =====================================================================

O_SDR           equ 23                  ; bit 0: esta puesto en el bitmap (rotulos por software)
O_SVW           equ 24                  ; vista, bucle, celda, x, y, prioridad y huella con los que se puso
O_SLP           equ 25
O_SCL           equ 26
O_SX            equ 27
O_SY            equ 28
O_SPR           equ 29
O_SHL           equ 30
O_SHH           equ 31

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

; A = pagina del bucle del objeto IX (ya buscada) -> NC con ella mapeada y cv_* puestos (celdas, ancho, alto, banderas, huella, mosaicos), o C si no hay celda (sin mapear)
cel_rd:         call map_page
                ld a,(LWIN+1)           ; mosaicos que reserva un objeto de este bucle
                ld (cv_mt),a
                ld a,(LWIN)             ; numero de celdas del bucle
                ld b,a
                ld a,(ix+O_CEL)
                cp b
                jr nc,co_bad            ; la celda no existe
                ld l,a
                ld h,0
                add hl,hl
                ld de,LWIN+2
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,LWIN
                add hl,de               ; registro de la celda
                ld a,(hl)
                ld (cv_n),a
                inc hl
                ld a,(hl)
                ld (cv_w),a
                inc hl
                ld a,(hl)
                ld (cv_h),a
                inc hl
                ld a,(hl)
                ld (cv_fl),a
                inc hl
                ld a,(hl)
                ld (cv_hl),a
                inc hl
                ld a,(hl)
                ld (cv_hh),a
                inc hl
                ld (cv_p),hl
                bit 2,(ix+O_F2)         ; objeto fijo (add.to.pic): se pinta contra el fondo, como un rotulo
                jr z,co_ns
                ld hl,cv_fl
                set 0,(hl)
co_ns:          or a
                ret
co_bad:         call unmap_win
co_no:          scf
                ret
cv_n:           defb 0
cv_mt:          defb 0
cv_w:           defb 0
cv_h:           defb 0
cv_fl:          defb 0
cv_hl:          defb 0
cv_hh:          defb 0
cv_p:           defw 0

; Prioridad frente al fondo (la usan los sprites, en A1, y los rotulos por software, en A2): PROW = la prioridad de los pixeles de AGI de una fila de la imagen
PROW            equ MSGBUF
hw_pri:         defb 0
hw_plim:        defb 0

; HL = x HiRes del primer pixel -> A = pixeles visibles (bit 7 = el primero) segun PROW y hw_pri
hg_okb:         ld b,8
                ld c,0
hk_l:           sla c
                ld a,h
                or a
                jr nz,hk_v              ; x >= 256: fuera de la pantalla
                push hl
                ld d,0
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de               ; 5 * x
                srl h
                rr l
                srl h
                rr l
                srl h
                rr l
                ld de,PROW
                add hl,de
                ld a,(hl)
                ld hl,hw_pri
                cp (hl)
                pop hl
                jr c,hk_v
                jr nz,hk_n              ; la del fondo es mayor
hk_v:           inc c
hk_n:           inc hl
                djnz hk_l
                ld a,c
                ret

; A = fila de la imagen, PG_PRI2 en el bloque 7 -> PROW (prioridad de los pixeles de AGI hasta hw_plim)
pd_row:         ld l,a
                ld h,0
                add hl,hl
                ld de,$E000
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,$E000+336
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
                ld a,(hw_plim)
                ld c,a
                ld a,e
                cp c
                jr c,pd_l
                ret


SP_MAX          equ 8
