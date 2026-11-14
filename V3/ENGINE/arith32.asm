; arith32.asm - aritmetica de 32 bits con signo (copiada de geom.asm de v2): la usan expression (overlay B) y, en la fase 6, la
; geometria de las cajas. N1, N2, NR, DR y DSGN estan en las variables del nucleo (vm_core.asm).

sx32_n1:                                ; N1 = HL con extension de signo
                ld (N1),hl
                ld a,h
                rla
                sbc a,a
                ld (N1+2),a
                ld (N1+3),a
                ret
sx32_n2:
                ld (N2),hl
                ld a,h
                rla
                sbc a,a
                ld (N2+2),a
                ld (N2+3),a
                ret

neg32:                                  ; HL = direccion de un valor de 32 bits: se cambia de signo
                xor a
                sub (hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                inc hl
                ld a,0
                sbc a,(hl)
                ld (hl),a
                ret

mul32:                                  ; NR = N1 * N2 (32 bits bajos); destruye N1 y N2
                ld hl,0
                ld (NR),hl
                ld (NR+2),hl
m32_l:
                ld hl,(N2)
                ld a,h
                or l
                ld hl,(N2+2)
                or h
                or l
                ret z                   ; N2 = 0: terminado
                ld a,(N2)
                and 1
                jr z,m32_s
                ld hl,(NR)
                ld de,(N1)
                add hl,de
                ld (NR),hl
                ld hl,(NR+2)
                ld de,(N1+2)
                adc hl,de
                ld (NR+2),hl
m32_s:
                ld hl,(N1)
                add hl,hl
                ld (N1),hl
                ld hl,(N1+2)
                adc hl,hl
                ld (N1+2),hl
                ld hl,(N2+2)
                srl h
                rr l
                ld (N2+2),hl
                ld hl,(N2)
                rr h
                rr l
                ld (N2),hl
                jr m32_l

div32s:                                 ; NR = N1 / N2 con signo y truncado hacia cero (N2 != 0)
                ld a,(N1+3)
                ld b,a
                ld a,(N2+3)
                xor b
                ld (DSGN),a             ; bit 7: los signos son distintos
                ld a,(N1+3)
                rla
                jr nc,d32_a
                ld hl,N1
                call neg32
d32_a:
                ld a,(N2+3)
                rla
                jr nc,d32_b
                ld hl,N2
                call neg32
d32_b:
                ld hl,0
                ld (DR),hl
                ld (DR+2),hl
                ld b,32
d32_l:
                push bc
                ld hl,(N1)              ; N1 <<= 1, el bit sale en carry
                add hl,hl
                ld (N1),hl
                ld hl,(N1+2)
                adc hl,hl
                ld (N1+2),hl
                ld hl,(DR)              ; DR = DR * 2 + carry
                adc hl,hl
                ld (DR),hl
                ld hl,(DR+2)
                adc hl,hl
                ld (DR+2),hl
                ; DR >= N2 ?
                ld hl,(DR)
                ld de,(N2)
                or a
                sbc hl,de
                ld (NR),hl              ; DR - N2 provisional
                ld hl,(DR+2)
                ld de,(N2+2)
                sbc hl,de
                jr c,d32_n
                ld (NR+2),hl
                ld hl,(NR)              ; DR = DR - N2
                ld (DR),hl
                ld hl,(NR+2)
                ld (DR+2),hl
                ld hl,N1
                inc (hl)                ; el bit 0 de N1 es 0 tras el desplazamiento
d32_n:
                pop bc
                djnz d32_l
                ld hl,(N1)
                ld (NR),hl
                ld hl,(N1+2)
                ld (NR+2),hl
                ld a,(DSGN)
                rla
                ret nc
                ld hl,NR
                jp neg32
