; =====================================================================
;  vm_input.asm - fase 7: la entrada del nucleo (se incluye desde vm_core.asm). Semantica: vmgame3.process_input, process_escape, find_verb_at_pos,
;  check_exec_verbs y run_input_script (scumm.cpp scummLoop, input.cpp processInput, verbs.cpp checkExecVerbs, script.cpp runInputScript).
;
;  El nucleo no sabe de teclado ni de raton: el programa (o el arnes) deja un suceso por fotograma en INEV y vm_frame lo consume.
;    INEV+0   tipo: 0 nada, 1 clic izquierdo, 2 clic derecho, 3 tecla, 4 ESC, 5 solo mover el raton (el modelo: 'click', 'rclick', 'key', 'esc', 'mouse')
;    INEV+1   x (palabra, coordenadas de SCUMM: 0-319)     INEV+3  y (palabra, 0-199)     INEV+5  tecla (palabra, ASCII)
;  Los clics y mover llevan x, y; las demas no (el raton se queda donde estaba). El programa traduce la pantalla del ZX81 a coordenadas de SCUMM.
; =====================================================================
INEV            equ GW_END              ; $F1B0: 7 bytes el suceso
MOUSEX          equ INEV+7              ; palabra: _mouse (recortado a 0-319 y 0-199)
MOUSEY          equ INEV+9
VMOUSEX         equ INEV+11             ; palabra: _virtualMouse (x + el borde izquierdo de la camara; y desde lo alto de la pantalla principal, -1 fuera de ella)
VMOUSEY         equ INEV+13
MKSTAT          equ INEV+15             ; palabra: _mouseAndKeyboardStat ($8000 clic izquierdo, $4000 derecho, o una tecla)
IN_END          equ INEV+17
ACV             equ IN_END              ; fase 8: variables de los actores (ovd_act.asm: lista, cache de firma, contadores de poses, tiras de la mascara); las pone a 0 scumm.asm
AC_ZERO         equ 194                 ; bytes que se ponen a 0 (hasta ac_mt); detras vienen las tiras de la mascara (512 B), que no hace falta borrar
MBS_LEFT        equ $8000

; HL < DE con signo: carry si es menor. Conserva HL, DE y BC (destruye A)
sl16:           ld a,h
                xor d
                jp p,sl_same
                ld a,h                  ; signos distintos: es menor el negativo
                rla
                ret
sl_same:        push hl
                or a
                sbc hl,de
                pop hl
                ret

; HL = valor (con signo) acotado a 0..DE
clip16:         bit 7,h
                jr z,cl_p
                ld hl,0
                ret
cl_p:           push hl
                or a
                sbc hl,de
                pop hl
                ret c
                ret z
                ex de,hl
                ret

; processInput (modelo: vmgame3.process_input): consume INEV, deja MOUSEX/Y, VMOUSEX/Y y MKSTAT; ESC (o el clic derecho) hace abortCutscene
vm_input:       ld hl,0
                ld (MKSTAT),hl
                ld a,(INEV)
                ld c,a                  ; C = tipo
                xor a
                ld (INEV),a             ; consumido
                ld a,c
                cp 1
                jr nz,vi_nc
                ld hl,MBS_LEFT
                ld (MKSTAT),hl
                jr vi_mv
vi_nc:          cp 5
                jr nz,vi_clip
vi_mv:          ld hl,(INEV+1)
                ld (MOUSEX),hl
                ld hl,(INEV+3)
                ld (MOUSEY),hl
vi_clip:        push bc
                ld hl,(MOUSEX)
                ld de,319
                call clip16
                ld (MOUSEX),hl
                ld hl,(MOUSEY)
                ld de,199
                call clip16
                ld (MOUSEY),hl
                ld de,(MAINTOP)         ; vy = y - main_top; -1 si es negativo o llega al alto (main_h - main_top)
                or a
                sbc hl,de
                bit 7,h
                jr nz,vi_vneg
                push hl
                ld hl,(MAINH)
                ld bc,(MAINTOP)
                or a
                sbc hl,bc
                ex de,hl                ; DE = alto
                pop hl                  ; HL = vy
                push hl
                call sl16
                pop hl
                jr c,vi_vy
vi_vneg:        ld hl,-1
vi_vy:          ld (VMOUSEY),hl
                ld hl,(SSTRIP)          ; x virtual = x + (_screenStartStrip * 8 si es > 0)
                bit 7,h
                jr nz,vi_x0
                ld a,h
                or l
                jr z,vi_x0
                add hl,hl
                add hl,hl
                add hl,hl
                jr vi_xs
vi_x0:          ld hl,0
vi_xs:          ld de,(MOUSEX)
                add hl,de
                ld (VMOUSEX),hl
                pop bc
                ld a,c
                cp 2                    ; clic derecho y ESC: la tecla de salir de la escena cortada
                jr z,vi_esc
                cp 4
                jr z,vi_esc
                cp 3
                ret nz
                ld hl,(INEV+5)          ; una tecla
                ld a,h
                or a
                jr nz,vi_kmk
                ld a,l
                cp 27
                jr z,vi_esc
                cp '.'
                jr z,vi_dot
                cp ' '
                ret z                   ; ESPACIO: la pausa es del anfitrion
vi_kmk:         ld (MKSTAT),hl
                ld a,h
                or a
                ret nz
                ld a,l
                cp 13                   ; Intro hace de clic izquierdo si el cursor esta activo (CURSTATE > 0)
                ret nz
                ld hl,(CURSTATE)
                bit 7,h
                ret nz
                ld a,h
                or l
                ret z
                ld hl,MBS_LEFT
                ld (MKSTAT),hl
                ret
vi_dot:         ld hl,0                 ; '.' : talk_delay = 0
                ld (TALKDLY),hl
                ret
vi_esc:         ld hl,(VAR_CUTSCENEEXIT_KEY)
                ld a,h
                or l
                ret z
                push hl
                call abort_cutscene
                pop hl
                ld (MKSTAT),hl          ; (VAR_CUTSCENEEXIT_KEY & $FFFF)
                ret

; update_scumm_vars: el raton
in_vars:        ld hl,(VMOUSEX)
                ld (VAR_VIRT_MOUSE_X),hl
                ld hl,(VMOUSEY)
                ld (VAR_VIRT_MOUSE_Y),hl
                ld hl,(MOUSEX)
                ld (VAR_MOUSE_X),hl
                ld hl,(MOUSEY)
                ld (VAR_MOUSE_Y),hl
                ret

; runInputScript: A = zona (1 verbo, 2 escena, 3 inventario, 4 tecla), HL = valor, DE = modo; VAR_VERB_SCRIPT con 3 argumentos
rin:            ld (VARARG+2),hl
                ld (VARARG+4),de
                ld l,a
                ld h,0
                ld (VARARG),hl
                ld a,3
                ld (VACNT),a
                ld a,$FF
                ld (CUR),a
                ld hl,(VAR_VERB_SCRIPT)
                ld a,h
                or l
                jr z,rin_no
                xor a
                jp run_script
rin_no:         ld (VACNT),a
                ret

; checkExecVerbs (despues de runAllScripts): la tecla de un verbo o una tecla cualquiera (zona 4), o un clic: sobre un verbo (zona 1), en la escena (2) o fuera de ella (1)
check_exec_verbs:
                ld hl,(USERPUT)
                bit 7,h
                ret nz
                ld a,h
                or l
                ret z
                ld hl,(MKSTAT)
                ld a,h
                or l
                ret z
                ld a,h
                cp 2
                jr nc,cev_mouse
                or a
                jr nz,cev_gen           ; una tecla >= 256 no es la de ningun verbo
                ld c,l
                ld ix,VERBS+VSZ
                ld b,NVERB-1
                ld de,VSZ
cev_l:          ld a,(ix+V_ID)
                or a
                jr z,cev_n
                ld a,(ix+V_SAVE)
                or a
                jr nz,cev_n
                ld a,(ix+V_MODE)
                cp 1
                jr nz,cev_n
                ld a,(ix+V_KEY)
                cp c
                jr nz,cev_n
                ld l,(ix+V_ID)          ; como si se hubiera hecho clic en el verbo (modo 1)
                ld h,0
                ld de,1
                ld a,1
                jp rin
cev_n:          add ix,de
                djnz cev_l
cev_gen:        ld hl,(MKSTAT)
                ld de,1
                ld a,4
                jp rin
cev_mouse:      ld a,h
                and $C0
                ret z                   ; ni clic izquierdo ni derecho
                call find_verb
                jr nc,cev_scene
                ld l,(ix+V_ID)
                ld h,0
                ld de,0
                ld a,1
                jp rin
cev_scene:      ld hl,(MOUSEY)          ; en la pantalla principal (main_top <= y < main_h): zona 2; fuera: zona 1
                ld de,(MAINTOP)
                call sl16
                jr c,cev_v
                ld hl,(MOUSEY)
                ld de,(MAINH)
                call sl16
                jr nc,cev_v
                ld a,2
                jr cev_r
cev_v:          ld a,1
cev_r:          ld hl,0
                ld de,0
                jp rin

; findVerbAtPos con el rectangulo [left, left + 8 * V_LEN) x [top, top + 8) del ultimo dibujo (verb_draw, overlay B): carry si hay, IX = el verbo
find_verb:      ld ix,VERBS+(NVERB-1)*VSZ
                ld b,NVERB-1
fv_l:           ld a,(ix+V_MODE)
                cp 1
                jr nz,fv_n
                ld a,(ix+V_ID)
                or a
                jr z,fv_n
                ld a,(ix+V_SAVE)
                or a
                jr nz,fv_n
                ld hl,(MOUSEY)
                ld e,(ix+V_TOP)
                ld d,(ix+V_TOP+1)
                call sl16
                jr c,fv_n               ; y < top
                ld hl,8
                add hl,de
                ex de,hl                ; DE = top + 8
                ld hl,(MOUSEY)
                call sl16
                jr nc,fv_n              ; y >= top + 8
                ld l,(ix+V_LEN)
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                ld e,(ix+V_LEFT)
                ld d,(ix+V_LEFT+1)
                add hl,de               ; HL = right
                push hl
                bit 0,(ix+V_FLG)
                jr z,fv_nc
                ex de,hl                ; centrado: x < -(right - 2 * left) no vale
                add hl,hl
                or a
                sbc hl,de
                ex de,hl                ; DE = 2 * left - right
                jr fv_x
fv_nc:                                  ; DE = left
fv_x:           ld hl,(MOUSEX)
                call sl16
                jr c,fv_nx              ; x < izquierda
                pop de                  ; DE = right
                ld hl,(MOUSEX)
                call sl16
                jr nc,fv_n              ; x >= right
                scf
                ret
fv_nx:          pop hl
fv_n:           ld de,-VSZ
                add ix,de
                djnz fv_l
                or a
                ret
