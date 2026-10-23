; =====================================================================
;  scumm.asm - el interprete SCUMM v2 para el ZX81 con SD81 Booster: nucleo + carga de datos + video + texto +
;  actores. Diseno: claude/planning/scumm_etapa2.md.
;
;  Cargar: SCUMM.BIN en $4200 (LOAD FAST "SCUMM.BIN" CODE 16896) y RAND USR 28672 ($7000).
;  Ensamblar: pasmo scumm.asm scumm.bin scumm.sym   (compila_scumm.bat)
;
;  Memoria: $2000-$37FF ventana de datos (paginas de 6 KB)   $3800-$3FFF tabla de 256 caracteres (I = $38)
;           $4200-      nucleo (vm.asm y lo que incluye), mcu.asm, loader.asm
;           $7000-$87FF  este programa           $8800-$BDFF el .GFX de la sala
;           $C000-$C7FF tabla de color           $C800-$CB18 pantalla (DFILE)       $CC00-  variables
;           $E000-$FFFF estado del nucleo
; =====================================================================

ENTRY_POINT     equ scumm_main
                include "ovl_entries.inc"
                include "ovl_vars.inc"          ; la primera instruccion del binario salta aqui: RAND USR 16914
                include "vm_core.asm"
                include "mcu.asm"
                include "loader.asm"

DIAG            equ 0                   ; 1: letras de progreso (A..) en la fila de abajo, para depurar el arranque
DEMO            equ 0                   ; 1: modo de prueba (sala y actor elegidos con las teclas); 0: el script de arranque del juego

SET_FAST        equ $02E7
SLOW_FAST       equ $0207
MAP_PORT        equ $E7

DFILE           equ $C800
GFXBUF          equ $8800               ; el codigo del programa llega hasta aqui; el .GFX mas grande mide 12,9 KB
DFILE_TMP       equ $A800               ; pantalla provisional mientras arranca: tras OVERLAY_IMAGE (hasta 8 KB desde $8600) y antes de que se cargue ningun .GFX
GFXMAX          equ $3600               ; lo que cabe (hasta $BDFF)
TILES           equ $3800
COLORS          equ $C000
FONT_I          equ $38
GLYPH0          equ 210                 ; codigos 210-255: la fuente (46 glifos); el 210 es el espacio y el tile en blanco
NGLYPH          equ 46
BLANK           equ GLYPH0
SV              equ $CC00               ; variables del programa
BACKBUF         equ $DA00               ; bufer trasero de las 16 filas de la sala (528 bytes)
STACK           equ $CFF0               ; la pila ocupa $CF00-$CFEF
TXT_ROW         equ 20                  ; filas 20-23: el texto de los mensajes (tapa al inventario mientras esta en pantalla)
TXT_ROWS        equ 4
CMD_64C         equ $1C
CMD_256C        equ $41

; ---- variables
sv_sp           equ SV+0
sv_i            equ SV+2
gf_room         equ SV+3
gf_cam          equ SV+4                ; palabra: columna de la camara
gf_fine         equ SV+6                ; scroll fino 0-7
gf_cols         equ SV+7                ; palabra
gf_npos         equ SV+9
gf_ninst        equ SV+11
gf_mapp         equ SV+13
gf_rstp         equ SV+15
gf_instp        equ SV+17
gf_lstp         equ SV+19
gf_llp          equ SV+21
gf_srcp         equ SV+23
gf_have         equ SV+25               ; 1 si hay un .GFX cargado
tx_col          equ SV+26
tx_row          equ SV+27
tx_on           equ SV+28               ; hay texto en pantalla
tx_sp           equ SV+47               ; el ultimo caracter fue un espacio (o es el principio): la siguiente palabra puede saltar de fila
tx_cont         equ SV+29               ; el ultimo trozo acabo con "mantener": el siguiente sigue a continuacion
ac_used         equ SV+30               ; grupos de sprites usados en el fotograma anterior
ac_owner        equ SV+31               ; 8 grupos: actor + 1 (0 = libre), y su color
ac_color        equ SV+39               ; 8 colores
gf_name         equ SV+48               ; "/SCUMM/ROOMnn.GFX" + 0
gf_objsec       equ SV+70               ; palabra: seccion de objetos del .GFX (0: no hay)
gf_objtab       equ SV+72               ; palabra: tabla de desplazamientos de las celdas de cada objeto
gf_size         equ SV+74               ; palabra: tamano del .GFX
glp_src         equ SV+76
glp_off         equ SV+78
gc_i            equ SV+80
gc_x8           equ SV+81
gc_y8           equ SV+82
gc_w            equ SV+83
gc_h            equ SV+84
gc_r            equ SV+85
gc_c            equ SV+86
gc_rowp         equ SV+90
gc_cp           equ SV+92

scumm_main:     di
                ld (sv_sp),sp
                ld sp,STACK
                ld a,i
                ld (sv_i),a
                call SET_FAST
                xor a
                ld (tx_on),a
                ld (tx_cont),a
                ld (gf_have),a
                ld (ac_used),a
                call sc_clear_owner
                ; pantalla provisional (DFILE_TMP) (RAM normal) para poder ver marcas de progreso (A..) en blanco y negro
                ld hl,DFILE_TMP
                ld (mk_base),hl
                ld (scr_base),hl
                xor a
                call fill_screen        ; codigos nativos del ZX81 (espacio)
                ld hl,DFILE_TMP
                ld (2096),hl
                ld a,170
                ld (2098),a
                ld (2045),a             ; Superfast texto
                ld hl,DFILE_TMP+1+23*33
                ld (mk_p),hl
                ld a,'A'
                call sc_mark            ; A: Superfast
                ld a,CMD_FULLPAGING
                call mcu_send
                ld a,'B'
                call sc_mark            ; B: paginacion completa
                ld b,6                  ; bloques 6 y 7 a sus paginas (el $C000 es la tabla de color)
                ld a,6
                call sc_map
                ld b,7
                ld a,7
                call sc_map
                ld a,85
                ld (2058),a             ; WRX apagado
                ld a,'C'
                call sc_mark            ; C: bloques 6 y 7
                ld a,CMD_256C
                call mcu_send
                ld a,'D'
                call sc_mark            ; D: 256C
                ld a,FONT_I
                ld i,a
                call init_font
                call ov_install         ; (la ROM ya no se necesita) el overlay (interfaz, camara y personajes) a su pagina y al bloque 0
                call OVL_OV_INIT
                call OVL_UI_INIT
                ld a,1
                ld (font_ready),a
                ld hl,COLORS+38*8       ; las marcas (glifos 38-47 de la ROM) en blanco sobre negro cuando haya color
                ld (hl),$0F
                ld de,COLORS+38*8+1
                ld bc,10*8-1
                ldir
                ld a,BLANK
                ld hl,DFILE
                ld (scr_base),hl
                call fill_screen        ; la pantalla definitiva ($C800)
                ld hl,DFILE
                ld (2096),hl
                ld hl,DFILE+1+23*33
                ld (mk_p),hl
                ld a,'E'
                call sc_mark            ; E: fuente y pantalla definitiva (esta marca ya sale en blanco: codigo 42 = glifo de la ROM)
                ld bc,$7FEF
                ld a,$20                ; Chroma, modo 0
                out (c),a
                ld a,255                ; las filas 0-15 se desplazan; la 16-23 se quedan quietas
                ld (2091),a
                ld (2092),a
                xor a
                ld (2093),a
                ld (2090),a
                IF DEMO = 0
                call cursor_init
                call cursor_draw
                ENDIF
                call vm_init
                ld hl,ev_handler
                ld (EVVEC),hl
                ld hl,OVL_HOST_OPS
                ld (HOSTVEC),hl
                call load_data
                jr nc,sm_ok1
                ld hl,tx_nodata
                call sc_fatal
sm_ok1:         ld a,'J'
                call sc_mark            ; J: datos cargados
                IF DEMO
                ld a,1
                ld (dm_dir),a
                ld a,0
                ld (dm_room),a
                push bc
                call dm_next_room
                pop bc
                ELSE
                ld hl,1                 ; el script de arranque
                ld (APIN),hl
                call vm_run_script
                ENDIF
                ld a,(ERR)
                or a
                jr nz,sm_err

main_loop:      ld a,(mk_first)
                or a
                jr nz,ml_go
                inc a
                ld (mk_first),a
                ld a,'O'
                call sc_mark            ; O: primer fotograma
ml_go:          call wait_vs
                ld (DELTA),a
                call vm_frame
                ld a,(ERR)
                or a
                jr nz,sm_err
                call OVL_CAM_UPDATE
                call gd_update
                call text_update
                call OVL_UI_UPDATE
                call OVL_ACTORS_UPDATE
                call keys
                ld a,(rs_flag)          ; restart(): se vuelve a empezar como si se hubiera arrancado
                or a
                jr z,main_loop
                xor a
                ld (rs_flag),a
                call sc_hide_sprites
                ld b,0                  ; el bloque 0 vuelve a la ROM (SET_FAST)
                xor a
                call sc_map
                ld sp,(sv_sp)
                jp scumm_main
rs_flag:        defb 0
sm_err:         call sc_hide_sprites
                ld a,(ERR)
                ld l,a
                ld h,0
                ld de,DFILE+1+21*33+1
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

sc_quit:        call sc_hide_sprites
                xor a
                ld (ov_done),a          ; la proxima vez se vuelve a copiar el overlay
                ld b,0                  ; el bloque 0 vuelve a la ROM (la usa SLOW_FAST)
                xor a
                call sc_map
                ld a,85
                ld (2045),a
                ld (2098),a
                ld (2090),a
                ld a,255
                ld (2093),a
                ld bc,$7FEF
                ld a,$0C
                out (c),a
                ld a,CMD_64C
                call mcu_send
                ld a,(sv_i)
                ld i,a
                call SLOW_FAST
                ld sp,(sv_sp)
                ld bc,0
                ret

mk_p:           defw 0
ld_trace:
sc_mark:
                IF DIAG = 0
                ret
                ENDIF
                push hl                 ; A = letra ASCII: una marca de progreso en la fila 23 (y en la historia)
                push de
                push af
                ld a,(mk_n)
                cp 24                   ; la historia es de 32 y la fila de 32: no pasar de 24 marcas
                jr c,scm_ok
                pop af
                pop de
                pop hl
                ret
scm_ok:
                ld de,mk_hist
                ld hl,(mk_n)
                ld h,0
                add hl,de
                ld (hl),a
                ld hl,mk_n
                inc (hl)
                pop af
                call mk_code
                ld hl,(mk_p)
                ld (hl),a
                inc hl
                ld (mk_p),hl
                pop de
                pop hl
                ret
; A = letra -> codigo de pantalla: nativo del ZX81 hasta que hay 256C, y luego el de la fuente
mk_code:        ld c,a
                ld a,(font_ready)
                or a
                ld a,c
                jr nz,mkc1
                sub 'A'-38
                ret
mkc1:           call ascii_glyph
                add a,GLYPH0
                ret
font_ready:     defb 0
; vuelve a dibujar todas las marcas (la sala borra la pantalla)
mk_redraw:      ld a,(mk_n)
                or a
                ret z
                ld b,a
                ld hl,mk_hist
                ld de,DFILE+1+23*33
mkr1:           ld a,(hl)
                push hl
                push bc
                call mk_code
                pop bc
                pop hl
                ld (de),a
                inc hl
                inc de
                djnz mkr1
                ld (mk_p),de
                ret
mk_n:           defb 0
mk_first:       defb 0
mk_hist:        defs 32


; mensaje fatal en la fila 21 y espera una tecla
sc_fatal:       ld de,DFILE+1+21*33+1
                call put_str
                call sc_wait_key
                jp sc_quit

sc_wait_key:    call sc_scan
                or a
                jr nz,sc_wait_key       ; primero que suelte la que tuviera
swk1:           call sc_scan
                or a
                jr z,swk1
                ret

; el overlay (OVERLAY_IMAGE, hasta 8 KB) se copia a su pagina fisica a traves del bloque 1 y se mapea en el bloque 0 (solo lectura)
ov_install:     ld a,(ov_done)          ; tras un restart el overlay ya esta en su pagina (la imagen de aqui la pisa el .GFX de la sala)
                or a
                jr nz,oi_map
                ld b,OVL_PAGE
                ld a,1
                call sc_map
                ld hl,OVERLAY_IMAGE
                ld de,$2000
                ld bc,OVERLAY_END-OVERLAY_IMAGE
                ldir
                ld b,1                  ; el bloque 1 vuelve a su pagina
                ld a,1
                call sc_map
                ld a,1
                ld (ov_done),a
oi_map:         ld b,OVL_PAGE
                xor a
                jp sc_map
ov_done:        defb 0

; bloque A, pagina B (paginacion completa)
sc_map:         ld c,MAP_PORT
                out (c),a
                ret

; ---------------------------------------------------------------------
;  Teclado: A = bits 0 O, 1 P, 2 N, 3 B, 4 ESPACIO
; ---------------------------------------------------------------------
sc_scan:        ld c,0
                ld a,$DF
                in a,(254)
                bit 1,a
                jr nz,ss1
                set 0,c
ss1:            bit 0,a
                jr nz,ss2
                set 1,c
ss2:            ld a,$7F
                in a,(254)
                bit 3,a
                jr nz,ss3
                set 2,c
ss3:            bit 4,a
                jr nz,ss4
                set 3,c
ss4:            bit 0,a
                jr nz,ss5
                set 4,c
ss5:            ld a,$FB                ; Q W E R T
                in a,(254)
                bit 4,a
                jr nz,ss6
                set 5,c
ss6:            ld a,$FB
                in a,(254)
                bit 0,a
                jr nz,ss7
                set 6,c                 ; Q
ss7:            ld a,$FD
                in a,(254)
                bit 0,a
                jr nz,ss8
                set 7,c                 ; A
ss8:            ld a,c
                ret

                IF DEMO = 0
; modo real: Q A O P mueven el cursor, ESPACIO o M hacen clic, X sale
keys:           ld a,$FE                ; SHIFT Z X C V
                in a,(254)
                bit 2,a
                jr nz,kr_go
                pop hl                  ; X: sale de main_loop
                jp sc_quit
kr_go:          ld a,$F7                ; tecla 4 = ESC de los PC: salta la cutscene si el script hizo beginOverride
                in a,(254)
                bit 3,a
                call z,vm_abort_cutscene
kr_nsk:         call sc_scan
                ld c,a
                ld a,$7F                ; M tambien hace clic (SPACE . M N B)
                in a,(254)
                bit 2,a
                jr nz,kr_nm
                set 4,c
kr_nm:          ld hl,(cur_x)           ; H = y, L = x
                bit 0,c                 ; O: izquierda
                jr z,kr_p
                ld a,l
                sub 3
                jr nc,kr_ok1
                xor a
kr_ok1:         ld l,a
kr_p:           bit 1,c                 ; P: derecha
                jr z,kr_q
                ld a,l
                add a,3
                jr c,kr_q
                cp 249
                jr nc,kr_q
                ld l,a
kr_q:           bit 6,c                 ; Q: arriba
                jr z,kr_a
                ld a,h
                sub 3
                jr nc,kr_ok2
                xor a
kr_ok2:         ld h,a
kr_a:           bit 7,c                 ; A: abajo
                jr z,kr_set
                ld a,h
                add a,3
                cp 185
                jr nc,kr_set
                ld h,a
kr_set:         ld (cur_x),hl
                call cursor_draw
                call gf_campx           ; HL = camara en pixeles
                ld a,(cur_x)
                ld e,a
                ld d,0
                add hl,de
                srl h                   ; / 8: VAR_VIRT_MOUSE_X
                rr l
                srl h
                rr l
                srl h
                rr l
                ld (VARS+60),hl
                ld a,(cur_y)
                srl a                   ; / 2: VAR_VIRT_MOUSE_Y
                ld l,a
                ld h,0
                ld (VARS+62),hl
                ld a,(k_prev)           ; clic: ESPACIO recien pulsado
                cpl
                and c
                bit 4,a
                jr z,kr_end
                ld a,(cur_y)
                cp 128
                jr c,kr_scene
                call OVL_UI_CLICK           ; por debajo de la sala: la frase y los verbos
                jr kr_end
kr_scene:       ld a,(UI_CURSOR)
                or a
                jr z,kr_end
                ld a,1
                ld (INP_FLAG),a
                ld a,2                  ; zona de la escena
                ld (INP_AREA),a
                ld hl,0
                ld (INP_VAL),hl
kr_end:         call kr_digits
                ld a,c
                ld (k_prev),a
                ret

; teclas 1-3 recien pulsadas -> entrada de zona 4 (tecla) con el valor 1-3: el script 4 cambia de personaje (VAR_KEYPRESS)
kr_digits:      ld a,$F7
                in a,(254)
                cpl
                and 7
                ld b,a
                ld a,(k_prev2)
                cpl
                and b
                ld d,a
                ld a,b
                ld (k_prev2),a
                ld a,d
                or a
                ret z
                ld hl,1                 ; el script 4 espera VAR_KEYPRESS = 1, 2 o 3 (no el ASCII)
                srl a
                jr c,kd_go
                inc l
                srl a
                jr c,kd_go
                inc l
kd_go:          ld (INP_VAL),hl
                ld a,1
                ld (INP_FLAG),a
                ld a,4                  ; zona 4: tecla
                ld (INP_AREA),a
                ret
k_prev2:        defb 0
cur_x:          defb 124
cur_y:          defb 64

; el cursor es el sprite 63: una flecha blanca con borde negro
cursor_init:    ld a,63
                ld (2100),a
                ld hl,2105
                ld b,8
cin_c:          ld (hl),$F0             ; tinta blanca, papel negro
                inc hl
                djnz cin_c
                ld de,cur_pix
                ld b,8
cin_p:          ld a,(de)
                ld (hl),a
                inc hl
                inc de
                djnz cin_p
                ld de,cur_pix
                ld b,8
cin_m:          ld a,(de)               ; mascara = forma + un borde
                ld c,a
                srl a
                or c
                ld (hl),a
                inc hl
                inc de
                djnz cin_m
                ld a,1
                ld (2101),a
                ret

cursor_draw:    ld a,63
                ld (2100),a
                ld a,(UI_CURSOR)
                ld (2101),a
                ld a,(cur_x)
                add a,32
                ld l,a
                ld a,0
                adc a,0
                ld h,a
                ld (2102),hl
                ld a,(cur_y)
                add a,32
                ld (2104),a
                ret
                ELSE
keys:           call sc_scan
                bit 4,a
                jr z,k_go
                pop hl                  ; ESPACIO: sale de main_loop
                jp sc_quit
k_go:
                IF DEMO
                ld c,a
                ld a,(k_prev)
                ld b,a
                ld a,c
                ld (k_prev),a
                ld a,(k_rep)
                inc a
                ld (k_rep),a
                ld a,b
                cpl
                and c                   ; teclas recien pulsadas
                ld b,a
                bit 0,c                 ; O y P se repiten mientras se mantienen
                jr nz,k_h
                bit 1,c
                jr nz,k_h
                bit 6,c
                jr nz,k_h
                bit 7,c
                jr z,k_t
k_h:            ld a,(k_rep)
                and 7
                jr nz,k_t
                ld a,b
                or c
                and $C3
                or b
                ld b,a
k_t:            bit 0,b
                jr z,k_1
                ld a,-6
                ld e,0
                push bc
                call dm_walk
                pop bc
k_1:            bit 1,b
                jr z,k_2
                ld a,6
                ld e,0
                push bc
                call dm_walk
                pop bc
k_2:            bit 2,b
                jr z,k_3
                ld a,1
                ld (dm_dir),a
                push bc
                call dm_next_room
                pop bc
k_3:            bit 3,b
                jr z,k_4
                ld a,-1
                ld (dm_dir),a
                push bc
                call dm_next_room
                pop bc
k_4:            bit 5,b
                call nz,dm_talk
                bit 6,b                 ; Q: arriba
                jr z,k_5
                xor a
                ld e,-3
                push bc
                call dm_walk
                pop bc
k_5:            bit 7,b                 ; A: abajo
                jr z,k_6
                xor a
                ld e,3
                push bc
                call dm_walk
                pop bc
k_6:
                ENDIF
                ret
                ENDIF

k_prev:         defb 0
k_rep:          defb 0

                IF DEMO
dm_room:        defb 0
dm_dir:         defb 1

; sala siguiente (segun dm_dir) con imagen: la carga y pone al actor 1 en el suelo
dm_next_room:   ld b,60
dnr1:           push bc
                ld a,(dm_dir)
                ld hl,dm_room
                add a,(hl)
                jr z,dnr_wrap
                cp 64
                jr c,dnr_ok
dnr_wrap:       ld a,(dm_dir)
                bit 7,a
                ld a,1
                jr z,dnr_ok
                ld a,63
dnr_ok:         ld (dm_room),a
                ld l,a                  ; ancho de la sala != 0 = existe
                ld h,0
                call room_entry
                ld de,6
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                pop bc
                jr nz,dnr_found
                djnz dnr1
                ret
dnr_found:      ld a,(dm_room)
                ld l,a
                ld h,0
                ld (APIN),hl
                call vm_load_room
                ld a,(ERR)
                or a
                ret nz
                ld ix,ACTORS+ASIZE      ; actor 1, el jugador
                ld (ix+5),1             ; traje 1 (que haya alguno)
                ld (ix+11),15
                ld hl,1
                ld (VARS),hl            ; VAR_EGO
                ld hl,20                ; por omision, hacia el centro de la sala
                ld de,60
                ld a,(NBOXES)
                or a
                jr z,dnf1
                ld a,(ROOMBLOB+1)       ; primera caja: uy, ly, ulx, urx, llx, lrx
                ld e,a
                ld a,(ROOMBLOB+2)
                add a,e
                srl a
                ld e,a
                ld d,0                  ; y = (uy + ly) / 2
                ld a,(ROOMBLOB+3)
                ld l,a
                ld a,(ROOMBLOB+4)
                add a,l
                srl a
                ld l,a
                ld h,0                  ; x = (ulx + urx) / 2
dnf1:           ld (PA_X),hl
                ld (PA_Y),de
                ld a,(dm_room)
                ld (PA_ROOM),a
                ld ix,ACTORS+ASIZE
                jp put_actor

; A = desplazamiento en x, E = en y (con signo): el actor 1 camina hacia alli
dm_walk:        ld ix,ACTORS+ASIZE
                ld c,a
                rla
                sbc a,a
                ld b,a                  ; BC = desplazamiento en x con signo
                ld l,(ix+1)
                ld h,(ix+2)
                add hl,bc
                ld (WK_X),hl
                ld a,e                  ; desplazamiento en y con signo
                ld c,a
                rla
                sbc a,a
                ld b,a
                ld l,(ix+3)
                ld h,(ix+4)
                add hl,bc
                ld (WK_Y),hl
                ld hl,$FFFF
                ld (WK_DIR),hl
                jp start_walk_actor

; el actor 1 dice algo
dm_talk:        ld hl,dm_str
                ld (STRP),hl
                ld hl,1
                jp actor_talk
dm_str:         defb "Hello! I am Dave, and this is room ",0
                ENDIF

; espera al siguiente VSYNC; A = cuantos han pasado (>= 1)
wait_vs:        ld a,(vs_extra)         ; un redibujado ya ha esperado el VSYNC de este fotograma
                or a
                jr z,wv_n
                push af
                xor a
                ld (vs_extra),a
                pop af
                ret
wv_n:           in a,(ClkPort)
                ld bc,2000
wv1:            in a,(ClkPort)
                and $7E
                jr nz,wv_ok
                dec bc
                ld a,b
                or c
                jr nz,wv1
                ld a,2
wv_ok:          rrca
                ret

; ---------------------------------------------------------------------
;  Fuente: 46 glifos de la ROM (y tres propios) en los codigos 210-255, blanco sobre negro
; ---------------------------------------------------------------------
init_font:      ld hl,font_src
                ld de,TILES+GLYPH0*8
                ld b,NGLYPH
if_g:           push bc
                push hl
                ld a,(hl)
                cp $80
                jr nc,if_cus
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,$1E00
                add hl,bc
                jr if_cp
if_cus:         sub $80
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld bc,font_cus
                add hl,bc
if_cp:          ld b,8
if_b:           ld a,(hl)
                cpl                     ; el bit 7 del codigo invierte el video
                ld (de),a
                inc hl
                inc de
                djnz if_b
                pop hl
                inc hl
                pop bc
                djnz if_g
                ld hl,COLORS+GLYPH0*8
                ld (hl),$0F             ; papel negro, tinta blanca brillante
                ld de,COLORS+GLYPH0*8+1
                ld bc,NGLYPH*8-1
                ldir
                ret

; espacio, 0-9, A-Z, / : . , ? - " y dos propios (! ')

fill_screen:    ld hl,(scr_base)        ; A = codigo
                ld (hl),a
                ld d,h
                ld e,l
                inc de
                ld bc,24*33
                ldir
                ld hl,(scr_base)
                ld (hl),$76
                ret
scr_base:       defw 0
mk_base:        defw 0

; A = ASCII -> A = indice de glifo
ascii_glyph:    cp ' '
                jr z,ag_sp
                cp '0'
                jr c,ag_pun
                cp '9'+1
                jr c,ag_dig
                cp 'A'
                jr c,ag_pun
                cp 'Z'+1
                jr c,ag_up
                cp 'a'
                jr c,ag_pun
                cp 'z'+1
                jr nc,ag_pun
                sub 'a'-11
                ret
ag_up:          sub 'A'-11
                ret
ag_dig:         sub '0'-1
                ret
ag_pun:         cp '/'
                jr z,ag_sl
                cp ':'
                jr z,ag_co
                cp '.'
                jr z,ag_do
                cp ','
                jr z,ag_cm
                cp '?'
                jr z,ag_qu
                cp '-'
                jr z,ag_mi
                cp '"'
                jr z,ag_dq
                cp '!'
                jr z,ag_ex
                cp 39
                jr z,ag_ap
ag_sp:          xor a
                ret
ag_sl:          ld a,37
                ret
ag_co:          ld a,38
                ret
ag_do:          ld a,39
                ret
ag_cm:          ld a,40
                ret
ag_qu:          ld a,41
                ret
ag_mi:          ld a,42
                ret
ag_dq:          ld a,43
                ret
ag_ex:          ld a,44
                ret
ag_ap:          ld a,45
                ret

; A = ASCII -> codigo de pantalla en (DE), DE avanza
put_chr:        call ascii_glyph
                add a,GLYPH0
                ld (de),a
                inc de
                ret

put_str:        ld a,(hl)               ; HL = cadena acabada en 0, DE = destino
                or a
                ret z
                inc hl
                push hl
                call put_chr
                pop hl
                jr put_str

; HL = valor, B = cifras (2 o 3) -> DE avanza
put_num:        ld a,b
                cp 3
                jr c,pn2
                ld bc,100
                call pn_dig
pn2:            ld bc,10
                call pn_dig
                ld a,l
                add a,'0'
                jr put_chr
pn_dig:         ld a,'0'-1
pn_l:           inc a
                or a
                sbc hl,bc
                jr nc,pn_l
                add hl,bc
                jr put_chr

; ---------------------------------------------------------------------
;  Sucesos del nucleo (puerto $F2 / EVVEC): A = suceso
; ---------------------------------------------------------------------
ev_handler:     push af
                push bc
                push de
                push hl
                push ix
                push iy
                cp EV_TEXT
                jr z,evh_text
                cp EV_ROOM_LOAD
                jr z,evh_room
                cp EV_OBJSTATE
                jr nz,evh_end
                ld a,1                  ; cambia el estado de un objeto: la sala se vuelve a componer (una vez por fotograma, gd_update)
                ld (gd_pending),a
                ld a,(UI_DIRTY)         ; y puede haber cambiado el inventario
                or 4
                ld (UI_DIRTY),a
                jr evh_end
evh_room:       call gf_load_room
                jr evh_end
evh_text:       call ev_text
evh_end:        pop iy
                pop ix
                pop hl
                pop de
                pop bc
                pop af
                ret

; ---------------------------------------------------------------------
;  Texto: filas TXT_ROW.. de la pantalla (no hacen scroll)
; ---------------------------------------------------------------------
tx_clear:       ld a,(UI_DIRTY)         ; el texto tapa el inventario: se vuelve a dibujar
                or 4
                ld (UI_DIRTY),a
                ld a,1
                ld (tx_sp),a
                ld hl,DFILE+1+TXT_ROW*33
                ld de,DFILE+2+TXT_ROW*33
                ld bc,TXT_ROWS*33-1
                ld (hl),BLANK
                ldir
                xor a
                ld (tx_col),a
                ld (tx_row),a
                ld (tx_on),a
                ret

; lo que el nucleo acaba de escribir: de TXTSTART a MSGPTR
ev_text:        ld a,(tx_cont)
                or a
                call z,tx_clear
                xor a
                ld (tx_cont),a
                ld a,1
                ld (tx_on),a
evt_l:          ld hl,(TXTSTART)
                ld de,(MSGPTR)
                or a
                sbc hl,de
                ret nc
                ld hl,(TXTSTART)
                ld a,(hl)
                inc hl
                ld (TXTSTART),hl
                or a
                ret z
                cp $FF
                jr z,evt_esc
                cp $FE
                jr z,evt_esc
                call tx_wrap            ; salto de linea antes de una palabra que no cabe
                jr z,evt_l              ; (un espacio al principio de una linea no se escribe)
                push af
                call tx_put
                pop af
                cp ' '
                ld a,0
                jr nz,evt_sp1
                inc a
evt_sp1:        ld (tx_sp),a
                jr evt_l
evt_esc:        ld hl,(TXTSTART)
                ld a,(hl)
                inc hl
                ld (TXTSTART),hl
                cp 1
                jr z,evt_nl
                cp 2
                jr nz,evt_l
                ld a,1
                ld (tx_cont),a          ; mantener: el siguiente trozo va detras
                jr evt_l
evt_nl:         call tx_newline
                jr evt_l

; A = caracter: antes de escribirlo, si empieza palabra y no cabe en la fila, pasa a la siguiente.
; Z si no hay que escribirlo (un espacio en la columna 0 de una fila que no es la primera)
tx_wrap:        cp ' '
                jr nz,txw_word
                ld c,a
                ld a,(tx_col)
                or a
                ld a,c
                ret nz                  ; espacio en medio de una fila: se escribe
                ld a,(tx_row)
                or a
                ld a,' '
                ret z                   ; primera fila: se escribe
                cp a                    ; Z: no se escribe
                ret
txw_word:       ld c,a
                ld a,(tx_sp)
                or a
                ld a,c
                jr z,txw_ok             ; no es el principio de una palabra
                push af
                ld hl,(TXTSTART)        ; apunta detras del caracter actual
                ld b,1
txw_l:          ld a,(hl)
                or a
                jr z,txw_e
                cp ' '
                jr z,txw_e
                cp $FF
                jr z,txw_e
                cp $FE
                jr z,txw_e
                inc hl
                inc b
                jr txw_l
txw_e:          ld a,(tx_col)
                or a
                jr z,txw_n              ; ya al principio de la fila
                add a,b
                cp 33
                jr c,txw_n
                call tx_newline
txw_n:          pop af
txw_ok:         or 1                    ; NZ: se escribe
                ld a,c
                ret
tx_newline:     xor a
                ld (tx_col),a
                ld a,(tx_row)
                inc a
                cp TXT_ROWS
                jr c,txn1
                dec a
txn1:           ld (tx_row),a
                ret

; A = ASCII: lo pone en el cursor del texto
tx_put:         push af
                ld a,(tx_col)
                cp 32
                call nc,tx_newline
                ld a,(tx_row)
                ld l,a
                ld h,0
                ld e,l
                ld d,h
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl               ; * 32
                add hl,de               ; * 33
                ld de,DFILE+1+TXT_ROW*33
                add hl,de
                ld a,(tx_col)
                ld e,a
                ld d,0
                add hl,de
                ex de,hl
                pop af
                call put_chr
                ld hl,tx_col
                inc (hl)
                ret

; cada fotograma: cuando el nucleo da el mensaje por terminado, se borra
text_update:    ld a,(tx_on)
                or a
                ret z
                ld a,(HAVEMSG)
                or a
                ret nz
                ld a,(KEEPTXT)
                or a
                ret nz
                ld a,(tx_cont)
                or a
                ret nz
                jp tx_clear

; ---------------------------------------------------------------------
;  Salas: .GFX (SCUMM/TOOLS/lfl2gfx.py, ver SCUMM/TOOLS/LFL2GFX.md)
; ---------------------------------------------------------------------
gf_load_room:   ld a,(EVARGS)
                ld (gf_room),a
                ld hl,160               ; camara: seguir al protagonista, desde el centro
                ld (cam_cx),hl
                ld a,2
                ld (cam_mode),a
                ld a,$FF
                ld (cam_fol),a
                ld a,1
                ld (cam_new),a
                ld a,4                  ; los personajes no vuelven a aparecer hasta saber donde van (y la camara ya esta en su sitio)
                ld (ac_hold),a
                call sc_hide_sprites
                ld hl,0
                ld (gf_objsec),hl
                xor a
                ld (gf_have),a
                ld (gf_fine),a
                ld (2090),a
                ld h,a
                ld l,a
                ld (gf_cam),hl
                ld a,BLANK
                call fill_screen
                ld a,(UI_DIRTY)         ; la pantalla se ha borrado entera: la interfaz se vuelve a dibujar
                or 7
                ld (UI_DIRTY),a
                ld a,'K'
                call sc_mark            ; K: empieza a cargar una sala
                call mk_redraw
                ld a,(gf_room)
                or a
                ret z                   ; sala 0: no hay imagen
                call gf_read
                ret c
                ld a,'L'
                call sc_mark            ; L: leido el .GFX
                call gf_parse
                call gf_load_pool
                call gf_load_right
                call gf_draw_window
                ld a,'M'
                call sc_mark            ; M: dibujada la sala
                ld a,1
                ld (gf_have),a
                ret

; "/SCUMM/ROOMnn.GFX"
gf_make_name:   ld hl,gf_tpl
                ld de,gf_name
                ld bc,18
                ldir
                ld a,(gf_room)
                ld b,'0'-1
gmn1:           inc b
                sub 10
                jr nc,gmn1
                add a,10+'0'
                ld hl,gf_name+11
                ld (hl),b
                inc hl
                ld (hl),a
                ret

gf_read:        call gf_make_name
                ld hl,gf_name
                call f_open
                cp $FF
                jr nz,gfr1
                scf
                ret
gfr1:           ld (ld_h),a
                ld hl,ld_stat           ; fstat: 4 bytes de tamano, 4 de fecha y el estado
                ld a,CMD_FSTAT
                call mcu_send
                ld a,(ld_h)
                call mcu_send
                ld b,4
gfr2:           call mcu_recv
                ld (hl),a
                inc hl
                djnz gfr2
                ld b,5
gfr3:           call mcu_recv
                djnz gfr3
                ld hl,(ld_stat+2)
                ld a,h
                or l
                jr nz,gfr_bad
                ld hl,(ld_stat)
                ld (gf_size),hl
                ld de,GFXMAX
                or a
                sbc hl,de
                jr nc,gfr_bad
                ld a,(ld_h)
                ld hl,GFXBUF
                ld bc,(ld_stat)
                call f_read_n
                ld a,(ld_h)
                call f_close
                or a
                ret
gfr_bad:        ld a,(ld_h)
                call f_close
                scf
                ret
ld_stat:        defs 4

; cabecera del .GFX: "SGFX", version, nslots, cols(2), rows, view, npos(2), n(2), codebase(2); luego mapa, ...
gf_parse:       ld hl,(GFXBUF+6)
                ld (gf_cols),hl
                ld hl,(GFXBUF+10)
                ld (gf_npos),hl
                ld hl,(GFXBUF+12)
                ld (gf_ninst),hl
                ld hl,GFXBUF+16
                ld (gf_mapp),hl
                ld hl,(gf_cols)
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,GFXBUF+16
                add hl,de
                ld (gf_rstp),hl
                ld de,(gf_npos)
                inc de
                ex de,hl
                add hl,hl
                ex de,hl
                add hl,de
                ld (gf_instp),hl
                ld hl,(gf_ninst)
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de
                ld de,(gf_instp)
                add hl,de
                ld (gf_lstp),hl
                ld de,(gf_npos)
                inc de
                ex de,hl
                add hl,hl
                ex de,hl
                add hl,de
                ld (gf_llp),hl
                ld hl,0                 ; seccion de objetos (version 2 del .GFX): sus dos ultimos bytes dicen donde empieza
                ld (gf_objsec),hl
                ld a,(GFXBUF+4)
                cp 2
                ret c
                ld hl,(gf_size)
                ld de,GFXBUF-2
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld hl,GFXBUF
                add hl,de
                ld (gf_objsec),hl
                ld a,(hl)               ; tabla = seccion + 4 + 16 * P
                ld e,a
                ld d,0
                ex de,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,4
                add hl,de
                ex de,hl
                ld hl,(gf_objsec)
                add hl,de
                ld (gf_objtab),hl
                ret

; copia las 32 columnas visibles y la 33 (la que asoma con el scroll fino)
; Se pinta la sala en un bufer trasero (BACKBUF) y se copia de golpe a la pantalla justo despues de un VSYNC: asi no se ve el fondo
; sin los objetos ni a medio dibujar (parpadeo al hacer scroll).
gf_draw_window: call gf_draw_back
gf_flip:        ld a,(gd_sync)
                or a
                jr z,gfl1
                call wait_vs
                ld (vs_extra),a         ; el VSYNC ya ha pasado: el bucle principal no espera otro
gfl1:           ld hl,BACKBUF+1
                ld de,DFILE+1
                ld bc,16*33
                ldir
                xor a
                ld (gd_pending),a
                ret
gd_sync:        defb 1                  ; 0: sin esperar al VSYNC (el salto de camara de golpe)
gd_pending:     defb 0                  ; hay que volver a dibujar la sala
vs_extra:       defb 0
; los eventos del nucleo piden el redibujado; se hace una sola vez por fotograma
gd_update:      ld a,(gd_pending)
                or a
                ret z
                ld a,(gf_have)
                or a
                ret z
                jp gf_draw_window

gf_draw_back:   ld hl,(gf_mapp)
                ld de,(gf_cam)
                add hl,de
                ld (gf_srcp),hl
                ld de,BACKBUF+1
                ld b,16
gdw1:           push bc
                ld hl,(gf_srcp)
                ld bc,33
                ldir
                ld hl,(gf_cam)          ; ultima posicion: la columna 33 no existe
                ld bc,(gf_npos)
                or a
                sbc hl,bc
                jr c,gdw2
                dec de
                ld a,BLANK
                ld (de),a
                inc de
gdw2:           ld hl,(gf_srcp)
                ld bc,(gf_cols)
                add hl,bc
                ld (gf_srcp),hl
                pop bc
                djnz gdw1
                jp gf_compose           ; y encima, los objetos que se dibujan

; los tiles de la reserva de objetos a sus codigos (seccion de objetos: P, codigo del primero, 16 bytes por tile)
gf_load_pool:   ld hl,(gf_objsec)
                ld a,h
                or l
                ret z
                ld a,(hl)
                or a
                ret z
                ld b,a
                inc hl
                ld c,(hl)
                inc hl
                inc hl
                inc hl
                ld (glp_src),hl
glp_l:          push bc
                ld l,c
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld (glp_off),hl
                ld de,TILES
                add hl,de
                ex de,hl
                ld hl,(glp_src)
                ld bc,8
                ldir
                push hl
                ld hl,(glp_off)
                ld de,COLORS
                add hl,de
                ex de,hl
                pop hl
                ld bc,8
                ldir
                ld (glp_src),hl
                pop bc
                inc c
                djnz glp_l
                ret

; pone sobre la pantalla las imagenes de los objetos que se dibujan, del ultimo al primero (el primero queda encima)
gf_compose:     ld hl,(gf_objsec)
                ld a,h
                or l
                ret z
                ld a,(NOBJS)
                or a
                ret z
                ld (gc_i),a
gc_loop:        ld a,(gc_i)
                dec a
                ld (gc_i),a
                call obj_drawn
                jp nc,gc_next
                ld hl,(gf_objtab)       ; donde estan sus celdas
                ld a,(gc_i)
                ld e,a
                ld d,0
                add hl,de
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ld a,d
                and e
                inc a
                jp z,gc_next            ; $FFFF: no tiene imagen
                ld hl,(gf_objsec)
                add hl,de
                ld (gc_cp),hl
                ld a,(gc_i)
                call fo_rec
                ld a,(ix+5)
                ld (gc_x8),a
                ld a,(ix+6)
                ld (gc_y8),a
                ld a,(ix+7)
                ld (gc_w),a
                ld a,(ix+8)
                ld (gc_h),a
                xor a
                ld (gc_r),a
gc_row:         ld a,(gc_r)
                ld hl,gc_h
                cp (hl)
                jp nc,gc_next
                ld hl,gc_y8
                add a,(hl)
                cp 16
                jr nc,gc_rown           ; por debajo de la sala
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,de               ; * 33
                ld de,BACKBUF+1
                add hl,de
                ld (gc_rowp),hl
                xor a
                ld (gc_c),a
gc_col:         ld a,(gc_c)
                ld hl,gc_w
                cp (hl)
                jr nc,gc_rown
                ld hl,gc_x8
                add a,(hl)
                ld e,a
                ld a,0
                adc a,0
                ld d,a                  ; DE = columna de la celda
                ld hl,(gf_cols)
                or a
                sbc hl,de
                jr z,gc_cn              ; fuera de la sala
                jr c,gc_cn
                ld hl,(gf_cam)
                ex de,hl                ; HL = columna, DE = camara
                or a
                sbc hl,de
                jr c,gc_cn              ; a la izquierda de la camara
                ld a,h
                or a
                jr nz,gc_cn
                ld a,l
                cp 33
                jr nc,gc_cn             ; a la derecha de la camara
                ld e,a
                ld d,0
                ld hl,(gc_rowp)
                add hl,de
                ex de,hl                ; DE = destino
                ld hl,(gc_cp)
                ld a,(gc_c)
                ld c,a
                ld b,0
                add hl,bc
                ld a,(hl)
                ld (de),a
gc_cn:          ld hl,gc_c
                inc (hl)
                jr gc_col
gc_rown:        ld a,(gc_w)             ; las celdas de la fila siguiente
                ld e,a
                ld d,0
                ld hl,(gc_cp)
                add hl,de
                ld (gc_cp),hl
                ld hl,gc_r
                inc (hl)
                jp gc_row
gc_next:        ld a,(gc_i)
                or a
                jp nz,gc_loop
                ret

; HL = tabla + 2 * cam -> DE = primer indice, BC = ultimo + 1
gf_range:       ld de,(gf_cam)
                ex de,hl
                add hl,hl
                ex de,hl
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                ret

gf_load_right:  ld hl,(gf_rstp)
                call gf_range
glr1:           ld a,d
                xor b
                jr nz,glr2
                ld a,e
                xor c
                ret z
glr2:           push bc
                push de
                ld b,d
                ld c,e
                call gf_inst
                pop de
                pop bc
                inc de
                jr glr1

gf_load_left:   ld hl,(gf_lstp)
                call gf_range
gll1:           ld a,d
                xor b
                jr nz,gll2
                ld a,e
                xor c
                ret z
gll2:           push bc
                push de
                ld hl,(gf_llp)
                add hl,de
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                call gf_inst
                pop de
                pop bc
                inc de
                jr gll1

; BC = indice de instancia: 8 bytes de forma a TILES + 8 * codigo y 8 de color a COLORS + 8 * codigo
gf_inst:        ld h,b
                ld l,c
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,bc               ; 17 * k
                ld de,(gf_instp)
                add hl,de
                ld a,(hl)
                inc hl
                push hl
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                push hl
                ld de,TILES
                add hl,de
                ex de,hl
                pop bc
                pop hl
                push bc
                ld bc,8
                ldir
                pop de
                push hl
                ld hl,COLORS
                add hl,de
                ex de,hl
                pop hl
                ld bc,8
                ldir
                ret

gf_move_right:  ld hl,(gf_cam)
                ld de,(gf_npos)
                or a
                sbc hl,de
                ret nc                  ; ya en la ultima posicion
                ld a,(gf_fine)
                inc a
                cp 8
                jr c,gmr_set
                ld hl,(gf_cam)
                inc hl
                ld (gf_cam),hl
                ld de,(gf_npos)
                or a
                sbc hl,de
                call c,gf_load_right    ; en cam = npos no entra nada
                call gf_draw_window
                xor a
gmr_set:        ld (gf_fine),a
                ld (2090),a
                ret

gf_move_left:   ld a,(gf_fine)
                or a
                jr z,gml_cam
                dec a
                ld (gf_fine),a
                ld (2090),a
                ret
gml_cam:        ld hl,(gf_cam)
                ld a,h
                or l
                ret z
                dec hl
                ld (gf_cam),hl
                call gf_load_left
                call gf_draw_window
                ld a,7
                ld (gf_fine),a
                ld (2090),a
                ret

; posicion de la camara en pixeles -> HL
gf_campx:       ld hl,(gf_cam)
                add hl,hl
                add hl,hl
                add hl,hl
                ld a,(gf_fine)
                ld e,a
                ld d,0
                add hl,de
                ret

; ---------------------------------------------------------------------
;  Actores: un rectangulo de 2 x 4 sprites (16 x 32) del color de su texto, hasta 8 actores
; ---------------------------------------------------------------------
sc_clear_owner: ld hl,ac_owner
                ld de,ac_owner+1
                ld bc,15
                ld (hl),0
                ldir
                ret

sc_hide_sprites:
                ld b,64
sh1:            ld a,b
                dec a
                ld (2100),a
                xor a
                ld (2101),a
                djnz sh1
                call sc_clear_owner
                xor a
                ld (ac_used),a
                ret

; EGA (color del texto del actor) -> Chroma

ac_sp:          defb 0           ; fin del programa (el resto del codigo esta en el overlay: overlay.asm)


; ---------------------------------------------------------------------------------------------------------------
;  El codigo tiene que acabar por debajo de $8000: por encima la ULA del ZX81 mete NOPs en la captura de instrucciones.
;  Las tablas del nucleo son solo datos y van aqui; el .GFX de la sala empieza en GFXBUF.
; ---------------------------------------------------------------------------------------------------------------
                IF $ > $8000
                defb CODIGO_POR_ENCIMA_DE_8000
                ENDIF
                org $8000
                include "tables.inc"
                include "progdata.inc"
OVERLAY_IMAGE:  incbin "overlay.bin"
OVERLAY_END:
