; vm_ops.asm - manejadores NATIVOS del nucleo de la VM v3 (vmmodel3.CORE_OPS): control, variables, scripts, retardos,
; cutscene/override y freeze. Entran con DE = puntero tras el opcode, leen sus operandos (vm_core.asm: rd_var, rd_vb1...) y dejan
; SPTR tras ellos antes de hacer nada que pueda correr otro script. expression esta en el overlay B (ovlb.asm).
; Semantica: script_v5.cpp de ScummVM, como la transcribe V3/TOOLS/vmmodel3.py.

; ---- control
h3_stopObjectCode:
                ld (SPTR),de
                jp stop_object_code
h3_breakHere:   ld (SPTR),de
                jp break_here

h3_delay:       ld a,(de)               ; 24 bits: el retardo tal cual (en v2 era 0xFFFFFF - valor)
                ld c,a
                inc de
                ld a,(de)
                ld b,a
                inc de
                ld a,(de)
                inc de
                ld (SPTR),de
                ld hl,(CURSLOT)
                ld de,SL_DELAY
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),b
                inc hl
                ld (hl),a
                inc hl
                ld (hl),0
hd_pause:       ld hl,(CURSLOT)
                ld (hl),SS_PAUSED
                jp break_here
h3_delayVariable:
                call rd_var
                ld (SPTR),de
                ld hl,(CURSLOT)
                ld de,SL_DELAY
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),b
                inc hl
                ld a,b
                rla
                sbc a,a                 ; extension de signo
                ld (hl),a
                inc hl
                ld (hl),a
                jr hd_pause

h3_wait:        ld hl,(VAR_HAVE_MSG)    ; Indy3: espera al mensaje (sin subopcode)
                ld a,h
                or l
                jr z,hw_go
                dec de                  ; se repite la instruccion
                ld (SPTR),de
                jp break_here
hw_go:          ld (SPTR),de
                ret

h3_jumpRelative:
                jp do_jump
h3_equalZero:   call rd_var
                ld a,b
                or c
                jp z,no_jump
                jp do_jump
h3_notEqualZero:
                call rd_var
                ld a,b
                or c
                jp nz,no_jump
                jp do_jump

; comparaciones (con signo): a = getVar, b = getVarOrDirectWord; la condicion verdadera no salta
cmp_ab:         call rd_var             ; -> HL = a, BC = b, flags de a - b con signo (scmp)
                push bc
                call rd_vw1
                pop hl
                jp scmp
h3_isEqual:     call cmp_ab             ; b == a
                jp z,no_jump
                jp do_jump
h3_isNotEqual:  call cmp_ab             ; b != a
                jp nz,no_jump
                jp do_jump
h3_isGreater:   call cmp_ab             ; b > a  <=>  a < b
                jp c,no_jump
                jp do_jump
h3_isGreaterEqual:
                call cmp_ab             ; b >= a  <=>  a <= b
                jp c,no_jump
                jp z,no_jump
                jp do_jump
h3_isLess:      call cmp_ab             ; b < a  <=>  a > b
                jp c,do_jump
                jp z,do_jump
                jp no_jump
h3_isLessEqual: call cmp_ab             ; b <= a  <=>  a >= b
                jp nc,no_jump
                jp do_jump

h3_debug:       call rd_vw1
                ld (SPTR),de
                ret

; ---- variables
h3_move:        call rd_res
                call rd_vw1
                ld (SPTR),de
                jp set_res

ar_get:         call rd_res             ; _arith: RESV, BC = getVarOrDirectWord, HL = valor de la variable RESV
                call rd_vw1
                ld (SPTR),de
                ld hl,(RESV)
                push bc
                call var_rd
                pop hl
                ret                     ; HL = a, BC = r
h3_add:         call ar_get
                add hl,bc
ar_put:         ld b,h
                ld c,l
                jp set_res
h3_subtract:    call ar_get
                ld d,h
                ld e,l
                ld h,b
                ld l,c
                or a
                sbc hl,de               ; r - a
                jr ar_put
h3_and:         call ar_get
                ld a,h
                and b
                ld h,a
                ld a,l
                and c
                ld l,a
                jr ar_put
h3_or:          call ar_get
                ld a,h
                or b
                ld h,a
                ld a,l
                or c
                ld l,a
                jr ar_put
h3_multiply:    call ar_get             ; r * a, 16 bits bajos
                ld d,h
                ld e,l
                ld hl,0
                ld a,16
hm_l:           add hl,hl
                rl c
                rl b
                jr nc,hm_n
                add hl,de
hm_n:           dec a
                jr nz,hm_l
                jr ar_put
h3_divide:      call ar_get             ; r / a con signo, truncado hacia cero; a = 0: E_RANGE
                ld a,h
                or l
                jp z,err_range
                ld a,h
                xor b
                push af                 ; bit 7: el signo del cociente
                ex de,hl                ; DE = a
                bit 7,d
                jr z,hd_1
                xor a
                sub e
                ld e,a
                sbc a,a
                sub d
                ld d,a
hd_1:           bit 7,b
                jr z,hd_2
                xor a
                sub c
                ld c,a
                sbc a,a
                sub b
                ld b,a
hd_2:           ld hl,0                 ; BC / DE sin signo: cociente en BC
                ld a,16
hdv_l:          sla c
                rl b
                adc hl,hl
                or a
                sbc hl,de
                jr nc,hdv_1
                add hl,de
                jr hdv_n
hdv_1:          inc c
hdv_n:          dec a
                jr nz,hdv_l
                pop af
                rla
                jr nc,hdv_p
                xor a
                sub c
                ld c,a
                sbc a,a
                sub b
                ld b,a
hdv_p:          jp set_res
h3_increment:   call rd_res
                ld (SPTR),de
                ld hl,(RESV)
                call var_rd
                inc bc
                jp set_res
h3_decrement:   call rd_res
                ld (SPTR),de
                ld hl,(RESV)
                call var_rd
                dec bc
                jp set_res
h3_setVarRange: call rd_res             ; n valores (palabra si el bit 0x80 del opcode) en RESV, RESV+1...
                ld a,(de)
                inc de
                or a
                jp z,err_range
                ld b,a
hsv_l:          push bc
                ld a,(OPC)
                rla
                jr c,hsv_w
                call rd_b
                jr hsv_p
hsv_w:          call rd_w
hsv_p:          call set_res
                ld hl,(RESV)
                inc hl
                ld (RESV),hl
                pop bc
                djnz hsv_l
                ld (SPTR),de
                ret

h3_getRandomNr: call rd_res             ; rnd = rnd * 5 + 1; b = rnd >> 8; max >= 255: b; si no (b * (max + 1)) >> 8
                call rd_vb1
                ld (SPTR),de
                ld hl,(RNDST)
                ld d,h
                ld e,l
                add hl,hl
                add hl,hl
                add hl,de
                inc hl
                ld (RNDST),hl
                ld e,h                  ; E = b
                ld a,b                  ; BC = max (con signo)
                or a
                jr nz,hr_big
                ld a,c
                inc a
                jr z,hr_b               ; 255
                ld d,a                  ; (b * (max + 1)) >> 8, max + 1 = 1..255
                ld hl,0
                ld b,8
hr_m:           add hl,hl
                rl e
                jr nc,hr_n
                ld a,l
                add a,d
                ld l,a
                jr nc,hr_n
                inc h
hr_n:           djnz hr_m
                ld c,h
                ld b,0
                jp set_res
hr_b:           ld c,e
                ld b,0
                jp set_res
hr_big:         bit 7,b
                jr z,hr_b               ; max >= 256
                inc bc                  ; max < 0: m = max + 1 <= 0; resultado = floor(b * m / 256) (24 bits con signo)
                xor a                   ; |m| en BC
                sub c
                ld c,a
                sbc a,a
                sub b
                ld b,a
                ld hl,0                 ; AHL = b * |m| (24 bits)
                xor a
                ld d,8
hr_g:           add hl,hl
                rla
                rl e
                jr nc,hr_g2
                add hl,bc
                adc a,0
hr_g2:          dec d
                jr nz,hr_g
                ld e,a                  ; EHL = producto; se cambia de signo (24 bits) y se toma >> 8 (bytes 1 y 2)
                xor a
                sub l
                ld l,a
                ld a,0
                sbc a,h
                ld h,a
                ld a,0
                sbc a,e
                ld b,a
                ld c,h
                jp set_res

; ---- scripts
h3_startScript: ld a,(OPC)
                and $60                 ; 0x20 freezeResistant, 0x40 recursive
                push af
                call rd_vb1
                push bc
                call rd_vararg
                ld (SPTR),de
                pop hl
                pop af
                jp run_script
h3_chainScript: call rd_vb1
                push bc
                call rd_vararg
                ld (SPTR),de
                ld ix,(CURSLOT)
                ld a,(ix+SL_FLAGS)
                push af
                xor a
                ld (ix+SL_NUM),a
                ld (ix+SL_NUM+1),a
                ld (ix+SL_STAT),a
                dec a
                ld (CUR),a
                pop af
                pop hl
                jp run_script
h3_stopScript:  call rd_vb1
                ld (SPTR),de
                ld a,b
                or c
                jp z,stop_object_code
                ld h,b
                ld l,c
                jp stop_script
h3_stopObjectScript:
                call rd_vw1
                ld (SPTR),de
                ld h,b
                ld l,c
                jp stop_object_script
h3_isScriptRunning:
                call rd_res
                call rd_vb1
                ld (SPTR),de
                ld h,b
                ld l,c
                call is_script_running
                ld c,a
                ld b,0
                jp set_res
h3_freezeScripts:
                call rd_vb1
                ld (SPTR),de
                ld a,b
                or c
                jp z,unfreeze_scripts
                jp freeze_scripts

; ---- cutscene / override
h3_cutscene:    call rd_vararg          ; beginCutscene(args)
                ld (SPTR),de
                ld ix,(CURSLOT)
                inc (ix+SL_CUTOV)
                ld a,(CUTSP)
                inc a
                ld (CUTSP),a
                cp MAXCUT
                jp nc,err_cutscene
                ld e,a
                ld d,0
                ld bc,0                 ; args[0] (0 si la lista esta vacia)
                ld a,(VACNT)
                or a
                jr z,hc_0
                ld bc,(VARARG)
hc_0:           ld hl,CUTDATA
                add hl,de
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),b
                ld hl,CUTPTR
                add hl,de
                add hl,de
                xor a
                ld (hl),a
                inc hl
                ld (hl),a
                ld hl,CUTSCR
                add hl,de
                ld (hl),a
                ld a,(CUR)
                ld (CUTIDX),a
                ld hl,(VAR_CUTSCENE_START_SCRIPT)
                ld a,h
                or l
                jr z,hc_e
                xor a
                call run_script         ; con los mismos argumentos (VARARG, VACNT)
hc_e:           ld a,$FF
                ld (CUTIDX),a
                xor a
                ld (VACNT),a
                ret

h3_endCutscene: ld (SPTR),de
                ld ix,(CURSLOT)
                ld a,(ix+SL_CUTOV)
                or a
                jr z,he_1
                dec (ix+SL_CUTOV)
he_1:           ld a,(CUTSP)            ; args = [cut_data[cut_sp]]
                ld e,a
                ld d,0
                ld hl,CUTDATA
                add hl,de
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                ld (VARARG),bc
                ld a,1
                ld (VACNT),a
                ld hl,0
                ld (VAR_OVERRIDE),hl
                ld hl,CUTPTR
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                or (hl)
                jr z,he_2
                ld a,(ix+SL_CUTOV)
                or a
                jr z,he_2
                dec (ix+SL_CUTOV)
he_2:           xor a
                ld (hl),a
                dec hl
                ld (hl),a
                ld hl,CUTSCR
                add hl,de
                ld (hl),a
                ld a,(CUTSP)
                or a
                jp z,err_cutscene
                dec a
                ld (CUTSP),a
                ld hl,(VAR_CUTSCENE_END_SCRIPT)
                ld a,h
                or l
                jr z,he_e
                xor a
                jp run_script
he_e:           ld (VACNT),a
                ret

h3_beginOverride:
                ld a,(de)               ; 1: beginOverride; 0: endOverride
                inc de
                ld (SPTR),de
                ld hl,(CUTSP)
                ld h,0
                ld b,h
                ld c,l                  ; BC = cut_sp
                add hl,hl
                push de
                ld de,CUTPTR
                add hl,de
                pop de
                or a
                jr z,hbo_end
                ld (hl),e               ; cut_ptr = el puntero de ahora (con su pagina), cut_script = la ranura
                inc hl
                ld (hl),d
                ld ix,(CURSLOT)
                ld a,(ix+SL_PAGE)
                ld hl,CUTPG
                add hl,bc
                ld (hl),a
                ld hl,CUTSCR
                add hl,bc
                ld a,(CUR)
                ld (hl),a
                inc de                  ; se salta el jumpRelative que sigue (fetchScriptByte + fetchScriptWord)
                inc de
                inc de
                ld (SPTR),de
                ret
hbo_end:        xor a
                ld (hl),a
                inc hl
                ld (hl),a
                ld hl,CUTSCR
                add hl,bc
                ld (hl),a
                ret

; ---- expression: en el overlay B
h3_expression:  ld hl,OVB_EXPR
                jp call_ovb

; ---- manejadores del overlay B repartidos por opcode (ovb_op: fase 4a en adelante)
h3_ovb:         ld hl,OVB_OP
                jp call_ovb

; ---- manejadores del overlay C (ovc_op: sala, recursos y sistema)
h3_ovc:         ld hl,OVC_OP
                jp call_ovc
