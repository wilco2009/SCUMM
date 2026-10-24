; ---------------------------------------------------------------------------------------------------------------------------
;  Cache por demanda de las paginas de datos. Las tablas del juego guardan paginas VIRTUALES (dp_first + n de DATA.BIN, cada una de 6 KB
;  en el fichero desde LD_TABLES); la RAM extendida tiene 47 paginas fisicas para ellas (16-62 menos la 50, la del overlay; el indice
;  de la cache es la pagina fisica - 16). map_page_x trae una pagina a la RAM cuando no esta y desaloja con el algoritmo del reloj
;  (un bit de uso por pagina). Asi el juego puede ser mayor que la RAM y el arranque no lee el fichero entero.
; ---------------------------------------------------------------------------------------------------------------------------
DP_PHYS0        equ 16                  ; primera pagina fisica de la cache
DP_OVLIDX       equ OVL_PAGE-DP_PHYS0   ; el indice de la pagina del overlay: no se usa
DP_NIDX         equ 47                  ; indices 0-46: paginas fisicas 16-62
CMD_FSEEK       equ 54

dp_first:       defb 0
dp_n:           defb 0                  ; 0: aun no hay DATA.BIN: map_page es la pagina fisica tal cual
dp_h:           defb 0
dp_on:          defb 0
dp_v:           defb 0
dp_clr:                                 ; lo que se pone a cero al cargar
PMAP:           defs 256                ; pagina virtual -> fisica (0: no esta)
PSLOT:          defs DP_NIDX            ; indice de la cache -> pagina virtual que tiene (0: libre)
PREF:           defs DP_NIDX            ; bit de uso del reloj
dp_hand:        defb 0
DP_CLRLEN       equ $-dp_clr

dp_close:       ld a,(dp_on)            ; cierra el DATA.BIN abierto (restart y salida)
                or a
                ret z
                xor a
                ld (dp_on),a
                ld (dp_n),a
                ld a,(dp_h)
                jp f_close

; A = pagina de datos -> la ventana de datos; conserva HL y DE
map_page_x:     push hl
                push de
                ld e,a                  ; E = pagina virtual
                ld a,(dp_n)
                or a
                jr z,mpx_raw            ; sin DATA.BIN todavia
                ld a,(dp_first)
                ld d,a
                ld a,e
                sub d                   ; A = numero de pagina dentro del fichero
                jr c,mpx_raw
                ld hl,dp_n
                cp (hl)
                jr nc,mpx_raw
                ld d,0
                ld hl,PMAP
                add hl,de
                ld a,(hl)
                or a
                jr z,mpx_miss
                ld c,a                  ; esta: se marca como usada y se mapea
                sub DP_PHYS0
                ld e,a
                ld hl,PREF
                add hl,de
                ld (hl),1
                ld a,c
                pop de
                pop hl
                jp map_phys
mpx_raw:        ld a,e
                pop de
                pop hl
                jp map_phys

mpx_miss:       ld a,e
                ld (dp_v),a
mpx_ck:         ld a,(dp_hand)          ; el reloj: la primera pagina sin bit de uso (a las usadas se les quita)
                cp DP_OVLIDX
                jr nz,mpx_c1
                inc a
mpx_c1:         cp DP_NIDX
                jr c,mpx_c2
                xor a
mpx_c2:         ld c,a                  ; C = indice
                inc a
                ld (dp_hand),a
                ld b,0
                ld hl,PREF
                add hl,bc
                ld a,(hl)
                or a
                jr z,mpx_use
                ld (hl),0
                jr mpx_ck
mpx_use:        ld (hl),1
                ld hl,PSLOT
                add hl,bc
                ld a,(hl)               ; la pagina virtual que sale (0: libre)
                or a
                jr z,mpx_free
                ld e,a
                ld d,0
                ld hl,PMAP
                add hl,de
                ld (hl),0
mpx_free:       ld a,(dp_v)
                ld e,a
                ld d,0
                ld hl,PSLOT
                add hl,bc
                ld (hl),a
                ld a,c
                add a,DP_PHYS0
                cp OVL_PAGE
                jr c,mpx_ph
                inc a                   ; despues de la 50 los indices se desplazan una pagina
mpx_ph:         ld c,a                  ; C = pagina fisica
                ld hl,PMAP
                add hl,de
                ld (hl),c
                ld a,c
                call map_phys           ; la ventana en la pagina que se va a llenar
                ld a,(dp_v)             ; desplazamiento en el fichero = LD_TABLES + 6144 * n = LD_TABLES + ((3 * n) << 11)
                ld hl,dp_first
                sub (hl)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de               ; HL = 3 * n
                ld a,l
                and 31
                rlca
                rlca
                rlca
                ld d,a                  ; parte baja: (3n & 31) << 11 = D << 8
                ld b,5
mpx_sh:         srl h
                rr l
                djnz mpx_sh             ; HL = 3n >> 5: la parte alta
                ex de,hl                ; DE = parte alta, H = D de antes
                ld l,0                  ; HL = parte baja
                push de
                ld de,LD_TABLES
                add hl,de
                pop de
                jr nc,mpx_nc
                inc de
mpx_nc:         push de
                push hl
                ld a,CMD_FSEEK
                call mcu_send
                ld a,(dp_h)
                call mcu_send
                pop hl
                ld a,l
                call mcu_send
                ld a,h
                call mcu_send
                pop hl
                ld a,l
                call mcu_send
                ld a,h
                call mcu_send
                call mcu_recv           ; estado
                ld a,(dp_h)
                ld hl,WINDOW
                ld bc,$1800
                call f_read_n
                pop de
                pop hl
                ret
