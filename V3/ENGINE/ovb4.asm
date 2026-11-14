; =====================================================================
;  ovb4.asm - manejadores de la fase 4a en el overlay B (se incluye desde ovlb.asm): sonido, objetos, camara y actores sin caminar.
;  Semantica: ScummVM tal como la transcribe V3/TOOLS/vmmodel3.py + vmgame3.py. Entran por ovb_op con DE = puntero tras el opcode,
;  leen sus operandos con los lectores del residente (rd_vb1, rd_vw2, rd_res...) y dejan SPTR antes de hacer nada que pueda correr
;  otro script. Lo que dependa de una sala cargada (objetos de la sala, cajas) esta marcado con FASE5 / FASE6: hasta entonces no
;  hay objetos de sala (obj_index no encuentra ninguno) ni cajas (NBOXES = 0).
;  Las variables temporales (SC+n) no sobreviven a un script anidado: lo que cruce una llamada a run_script va en la pila.
; =====================================================================

; ---------------------------------------------------------------- utilidades
sless:          ld a,h                  ; HL < DE con signo: carry si es menor, Z si igual (destruye H y D)
                xor $80
                ld h,a
                ld a,d
                xor $80
                ld d,a
                or a
                sbc hl,de
                ret

abs_diff:       or a                    ; HL = |HL - DE| (16 bits sin signo: la diferencia de dos s16 cabe)
                sbc hl,de
                ld a,h
                jp pe,ad_v
                rla
                ret nc
                jr ad_neg
ad_v:           rla
                ret c
ad_neg:         xor a
                sub l
                ld l,a
                sbc a,a
                sub h
                ld h,a
                ret

; ---------------------------------------------------------------- actores
actor_ix:       ld h,a                  ; A = actor (0..NACT-1) -> IX = su registro (usa HL, BC)
                ld l,0
                srl h
                rr l
                srl h
                rr l
                ld bc,ACTORS
                add hl,bc
                push hl
                pop ix
                ret

chk_actor:      ld a,b                  ; derefActor: BC = valor de script -> IX; E_BADACTOR si no esta en 0..NACT-1
                or a
                jp nz,err_badactor
                ld a,c
                cp NACT
                jp nc,err_badactor
                jr actor_ix

actor_num:      push ix                 ; IX = actor -> A = su numero (usa HL, BC)
                pop hl
                ld bc,-ACTORS
                add hl,bc
                add hl,hl
                add hl,hl
                ld a,h
                ret

in_room:        ld a,(CURROOM)          ; Z si el actor IX esta en la sala en uso
                cp (ix+A_ROOM)
                ret

is_act13:       ld a,b                  ; A = 1 si BC es un numero de actor valido (0..NACT-1), si no 0
                or a
                jr nz,ia_n
                ld a,c
                cp NACT
                jr nc,ia_n
                ld a,1
                ret
ia_n:           xor a
                ret

old_dir:        ld a,c                  ; oldDirToNewDir(C & 3) -> HL = 270, 90, 180, 0
                and 3
                add a,a
                ld e,a
                ld d,0
                ld hl,old_dir_tbl
                add hl,de
                ld e,(hl)
                inc hl
                ld d,(hl)
                ex de,hl
                ret
old_dir_tbl:    defw 270,90,180,0

n2o:            ld de,110               ; newDirToOldDir: HL = angulo -> A = 0 izquierda, 1 derecha, 2 abajo, 3 arriba
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,n2o_b
                ld de,71
                or a
                sbc hl,de
                jr c,n2o_3
                ld a,1                  ; 71..109
                ret
n2o_b:          ld de,252
                push hl
                or a
                sbc hl,de
                pop hl
                jr nc,n2o_c
                ld a,2                  ; 110..251
                ret
n2o_c:          ld de,290
                or a
                sbc hl,de
                jr nc,n2o_3
                xor a                   ; 252..289
                ret
n2o_3:          ld a,3
                ret

; startAnimActor (version < 7): IX = actor, BC = fotograma pedido (16 bits). 0x38-0x3C son el fotograma de inicio, caminar, parado,
; hablar y dejar de hablar del actor (A_INIT... en ese orden); 0x3D es un error. Solo cambia el fotograma si esta en la sala y tiene traje
start_anim:     ld a,b
                or a
                jr nz,sa_chk
                ld a,c
                cp $38
                jr c,sa_chk
                cp $3D
                jp z,err_range
                jr nc,sa_chk
                sub $38
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld de,A_INIT
                add hl,de
                ld c,(hl)
sa_chk:         call in_room
                ret nz
                ld a,(ix+A_COST)
                or (ix+A_COST+1)
                ret z
                set 0,(ix+A_FLAGS)
                ld (ix+A_FRAME),c
                ret

turn_to_dir:    bit 2,(ix+A_FLAGS)      ; turnToDirection(HL = angulo): sin giro si ignoreTurns
                ret nz
                ld (ix+A_TFACE),l
                ld (ix+A_TFACE+1),h
                ld (ix+A_MOVING),4      ; MF_TURN
                ret

; adjustXYToBeInBox(IX = actor, HL = x, DE = y) -> HL, DE, A = caja. Con ignoreBoxes: el punto tal cual y caja invalida; sin cajas: las
; ultimas coordenadas validas. FASE6: con cajas (NBOXES != 0) falta la geometria
adjust_xy:      ld a,(ix+A_IGNB)
                or a
                jr z,ax_b
                ld a,$FF
                ret
ax_b:           ld a,(NBOXES)
                or a
                jp nz,err_badop
                ld l,(ix+A_LVX)
                ld h,(ix+A_LVX+1)
                ld e,(ix+A_LVY)
                ld d,(ix+A_LVY+1)
                ld a,$FF
                ret

adjust_actor_pos:                       ; IX = actor
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                call adjust_xy
                ld (ix+A_X),l
                ld (ix+A_X+1),h
                ld (ix+A_Y),e
                ld (ix+A_Y+1),d
                ld (ix+A_DBOX),a
                ld (ix+A_WBOX),a
                ld (ix+A_DESTX),$FF
                ld (ix+A_DESTX+1),$FF
                ld (ix+A_MOVING),0
                cp $FF
                ret z
                jp err_badop            ; FASE6: walkbox con banderas (turnToDirection del actor)

hide_actor:     ld a,(ix+A_VIS)         ; IX = actor
                or a
                ret z
                ld a,(ix+A_MOVING)
                or a
                jr z,ha_1
                ld (ix+A_MOVING),0
                ld b,0
                ld c,(ix+A_STAND)
                call start_anim
ha_1:           ld (ix+A_VIS),0
                res 0,(ix+A_FLAGS)
                ret

show_actor:     ld a,(CURROOM)          ; IX = actor
                or a
                ret z
                ld a,(ix+A_VIS)
                or a
                ret nz
                call adjust_actor_pos
                bit 1,(ix+A_FLAGS)
                jr z,sh_1
                ld b,0
                ld c,(ix+A_INIT)
                call start_anim
                res 1,(ix+A_FLAGS)
sh_1:           ld (ix+A_MOVING),0
                ld (ix+A_VIS),1
                set 0,(ix+A_FLAGS)
                ret

run_talk_script:                        ; runActorTalkScript: IX = actor, C = fotograma
                ld hl,(VAR_TALK_ACTOR)
                ld a,h
                or l
                ret z
                ld a,(CURROOM)
                cp (ix+A_ROOM)
                ret nz
                ld a,(ix+A_FRAME)
                cp c
                ret z
                ld b,0
                jp start_anim

stop_talk:      xor a                   ; stopTalk
                ld (HAVEMSG),a
                ld hl,0
                ld (TALKDLY),hl
                ld hl,(VAR_TALK_ACTOR)
                ld a,h
                or l
                jr z,stk_e
                ld a,h
                or a
                jr nz,stk_e
                ld a,l
                cp $80
                jr nc,stk_e
                ld b,h
                ld c,l
                call chk_actor
                call in_room
                jr nz,stk_s
                ld a,(USETALK)
                or a
                jr z,stk_s
                ld c,(ix+A_TSTOP)
                call run_talk_script
                xor a
                ld (USETALK),a
stk_s:          ld hl,$FF
                ld (VAR_TALK_ACTOR),hl
stk_e:          xor a
                ld (KEEPTXT),a
restore_bg:     ld hl,$FF               ; restoreCharsetBg: E 5 [255,0,0,0,0,0]
                ld (EVARGS),hl
                ld hl,0
                ld (EVARGS+2),hl
                ld (EVARGS+4),hl
                ld (EVARGS+6),hl
                ld (EVARGS+8),hl
                ld (EVARGS+10),hl
                ld a,EV_TEXT
                jp ev_emit

; Actor::putActor(IX = actor, HL = x, DE = y, C = sala)
put_actor:      push hl
                push de
                push bc
                ld a,(ix+A_VIS)
                or a
                jr z,pa_s
                ld a,(CURROOM)
                cp c
                jr z,pa_s
                call actor_num
                ld e,a
                ld d,0
                ld hl,(VAR_TALK_ACTOR)
                or a
                sbc hl,de
                jr nz,pa_s
                push ix
                call stop_talk
                pop ix
pa_s:           pop bc
                pop de
                pop hl
                ld (ix+A_X),l
                ld (ix+A_X+1),h
                ld (ix+A_Y),e
                ld (ix+A_Y+1),d
                ld (ix+A_ROOM),c
                set 0,(ix+A_FLAGS)
                call actor_num
                ld e,a
                ld d,0
                ld hl,(VAR_EGO)
                or a
                sbc hl,de
                jr nz,pa_e
                ld a,1
                ld (EGOPOS),a
pa_e:           ld a,(ix+A_VIS)
                or a
                jr z,pa_hid
                call in_room
                jp nz,hide_actor
                ld a,(ix+A_MOVING)
                or a
                jr z,pa_adj
                ld (ix+A_MOVING),0
                ld b,0
                ld c,(ix+A_STAND)
                call start_anim
pa_adj:         jp adjust_actor_pos
pa_hid:         call in_room
                ret nz
                jp show_actor

; ---------------------------------------------------------------- objetos
chk_obj_hl:     ld de,NOBJ              ; HL = objeto: E_BADOBJ si no esta en 0..NOBJ-1 (conserva HL)
                or a
                sbc hl,de
                jp nc,err_badobj
                add hl,de
                ret

inv_find:       ld hl,INVSL             ; BC = objeto: Z y HL = el byte alto de su ranura de INVSL si esta en el inventario; si no, NZ
                ld d,NINV
if_l:           ld a,(hl)
                inc hl
                cp c
                jr nz,if_n
                ld a,(hl)
                cp b
                jr z,if_y
if_n:           inc hl
                dec d
                jr nz,if_l
                ld a,1
                or a
                ret
if_y:           xor a
                ret

obj_index:      ld a,1                  ; getObjectIndex: Z si el objeto esta en la sala. FASE5: aun no hay objetos de sala (los pone
                or a                    ; startScene): nunca esta
                ret

; whereIsObject: BC = objeto -> A = $FF no esta, 0 inventario, 1 sala (conserva BC)
wio:            ld h,b
                ld l,c
                ld de,NOBJ
                or a
                sbc hl,de
                jr nc,wio_nf
                ld a,b
                or c
                jr z,wio_nf
                ld hl,OBJOWN
                add hl,bc
                ld a,(hl)
                cp OWNER_ROOM
                jr z,wio_room
                call inv_find
                jr nz,wio_nf
                xor a
                ret
wio_room:       call obj_index
                jr nz,wio_nf
                ld a,1
                ret
wio_nf:         ld a,$FF
                ret

; getObjectOrActorXY: BC = objeto o actor -> HL = x, DE = y; carry si no esta. Cambia IX. FASE5: un objeto de sala (getObjectXYPos) da E_BADOBJ
goa_xy:         bit 7,b
                jr nz,gx_none
                ld a,b
                or a
                jr nz,gx_obj
                ld a,c
                cp NACT
                jr nc,gx_obj
                call actor_ix
                call in_room
                jr nz,gx_none
gx_get:         ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                or a
                ret
gx_obj:         call wio
                or a
                jr z,gx_inv
                cp $FF
                jr z,gx_none
                jp err_badobj
gx_inv:         ld hl,OBJOWN
                add hl,bc
                ld a,(hl)
                cp NACT
                jr nc,gx_none
                call actor_ix
                call in_room
                jr z,gx_get
gx_none:        scf
                ret

; getObjectOrActorWidth: BC = objeto o actor -> A. Cambia IX. FASE5: la anchura de un objeto de sala (objs[].width)
goa_width:      bit 7,b
                jr nz,gw_0
                ld a,b
                or a
                jr nz,gw_o
                ld a,c
                cp NACT
                jr nc,gw_o
                call actor_ix
                call in_room
                jr nz,gw_0
                ld a,(ix+A_WIDTH)
                ret
gw_o:           call wio
                or a
                jr nz,gw_0
                ld hl,OBJOWN
                add hl,bc
                ld a,(hl)
                cp NACT
                jr nc,gw_0
                call actor_ix
                call in_room
                jr nz,gw_0
                ld a,(ix+A_WIDTH)
                ret
gw_0:           xor a
                ret

; runInventoryScript(i): C = i
run_inv0:       ld c,0
run_inv:        ld hl,(VAR_INVENTORY_SCRIPT)
                ld a,h
                or l
                ret z
                ld a,c
                ld (VARARG),a
                xor a
                ld (VARARG+1),a
                inc a
                ld (VACNT),a
                xor a
                jp run_script

; ---------------------------------------------------------------- sonido
b_startSound:   call rd_vb1
                ld (SPTR),de
                ld hl,0
                ld (VAR_MUSIC_TIMER),hl
                jr snd_go
b_startMusic:   call rd_vb1
                ld (SPTR),de
snd_go:         ld (VAR_LAST_SOUND),bc
                ld (LASTSND),bc
                ld (EVARGS),bc
                ld a,EV_SOUND_START
                jp ev_emit
b_stopSound:    call rd_vb1
                ld (SPTR),de
                ld (EVARGS),bc
                ld a,EV_SOUND_STOP
                jp ev_emit
b_stopMusic:    ld (SPTR),de
                ld hl,0
                ld (LASTSND),hl
                ld a,EV_SOUND_STOPALL
                jp ev_emit
b_isSoundRunning:
                call rd_res
                call rd_vb1
                ld (SPTR),de
                ld a,b
                or c
                jr z,isr_set
                ld (EVARGS),bc
                ld a,EV_SOUND_QUERY
                call ev_emit
                ld bc,(HRES)
isr_set:        jp set_res

; ---------------------------------------------------------------- objetos: dueno y nombre
b_getObjectOwner:
                call rd_res
                call rd_vw1
                ld (SPTR),de
                ld h,b
                ld l,c
                call chk_obj_hl
                ld hl,OBJOWN
                add hl,bc
                ld c,(hl)
                ld b,0
                jp set_res

; clearOwnerOf(HL = objeto): para sus scripts y, si no es de la sala, lo saca del inventario
clear_owner_of: push hl
                call stop_object_script
                pop hl
                call chk_obj_hl
                ld b,h
                ld c,l
                ld de,OBJOWN
                add hl,de
                ld a,(hl)
                cp OWNER_ROOM
                ret z
                call inv_find
                ret nz
                xor a
                ld (hl),a
                dec hl
                ld (hl),a
                ret

b_setOwnerOf:   call rd_vw1
                push bc
                call rd_vb2
                ld (SPTR),de
                pop hl                  ; HL = objeto, BC = dueno
                bit 7,h
                jp nz,err_badobj
                ld a,h
                or l
                jp z,err_badobj
                push bc                 ; dueno
                push hl                 ; objeto
                ld a,b
                or c
                jr nz,so_put
                call clear_owner_of     ; dueno 0 (HL = objeto)
                ld a,(CUR)              ; "Odd setOwnerOf case": el script en curso es del inventario y es ese objeto
                inc a
                jr z,so_put
                ld ix,(CURSLOT)
                ld a,(ix+SL_WHERE)
                or a
                jr nz,so_put
                ld e,(ix+SL_NUM)
                ld d,(ix+SL_NUM+1)
                pop hl
                push hl
                or a
                sbc hl,de
                jp z,err_range
                ld a,d
                or a
                jr nz,so_put
                ld a,e
                cp NINV
                jr nc,so_put
                ld hl,INVSL
                add hl,de
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                pop de
                push de
                or a
                sbc hl,de
                jp z,err_range
so_put:         pop hl                  ; objeto
                pop bc                  ; dueno
                push hl
                call chk_obj_hl
                ld a,b                  ; putOwner: 0..255
                or a
                jp nz,err_range
                ld de,OBJOWN
                add hl,de
                ld (hl),c
                call run_inv0
                pop hl                  ; el estado se lee despues del script de inventario
                ld (EVARGS),hl
                ld de,OBJST
                add hl,de
                ld a,(hl)
                ld (EVARGS+2),a
                xor a
                ld (EVARGS+3),a
                ld a,EV_OBJSTATE
                jp ev_emit

; setObjectName: busca el objeto (y libera su nombre) y lo apunta en la primera entrada libre; la cadena se queda en el codigo del script
b_setObjectName:
                call rd_vw1
                push bc
                push de
                call scan_str           ; DE tras la cadena
                ld (SPTR),de
                pop hl                  ; HL = inicio de la cadena
                pop bc                  ; BC = objeto
                bit 7,b                 ; objIsActor: error
                jp nz,err_range
                ld a,b
                or a
                jr nz,son_ok
                ld a,c
                cp NACT
                jp c,err_range
son_ok:         push hl
                push bc
                ld hl,NEWNAMES
                ld d,NNAMES
son_f:          ld a,(hl)
                inc hl
                cp c
                jr nz,son_n
                ld a,(hl)
                cp b
                jr z,son_clr
son_n:          inc hl
                dec d
                jr nz,son_f
                jr son_free
son_clr:        xor a
                ld (hl),a
                dec hl
                ld (hl),a
son_free:       ld hl,NEWNAMES
                ld e,0
son_l:          ld a,(hl)
                inc hl
                or (hl)
                jr z,son_set
                inc hl
                inc e
                ld a,e
                cp NNAMES
                jr c,son_l
                jp err_range            ; la tabla de nombres nuevos se desborda
son_set:        dec hl
                pop bc
                ld (hl),c
                inc hl
                ld (hl),b
                ld l,e
                ld h,0
                ld d,h
                add hl,hl
                add hl,de
                ld de,NEWNAMES+2*NNAMES
                add hl,de
                ld ix,(CURSLOT)
                ld a,(ix+SL_PAGE)
                ld (hl),a
                inc hl
                pop de                  ; inicio de la cadena
                ld (hl),e
                inc hl
                ld (hl),d
                jp run_inv0

; ---------------------------------------------------------------- camara
; setCameraAt(BC = x) sin tocar el modo: cur solo cambia si no sigue a un actor o si esta a mas de media pantalla
set_camera_at:  ld a,(CAMMODE)
                cp CAM_FOLLOW
                jr nz,sca_set
                ld hl,(CAMCUR)
                ld d,b
                ld e,c
                call abs_diff
                ld de,160
                or a
                sbc hl,de
                jr z,sca_skip
                jr c,sca_skip
sca_set:        ld (CAMCUR),bc
sca_skip:       ld (CAMDEST),bc
                ld hl,(CAMCUR)
                ld de,(VAR_CAMERA_MIN_X)
                call sless
                jr nc,sca_1
                ld hl,(VAR_CAMERA_MIN_X)
                ld (CAMCUR),hl
sca_1:          ld hl,(VAR_CAMERA_MAX_X)
                ld de,(CAMCUR)
                call sless
                ret nc
                ld hl,(VAR_CAMERA_MAX_X)
                ld (CAMCUR),hl
                ret

b_setCameraAt:  call rd_vw1
                ld (SPTR),de
                ld a,CAM_NORMAL
                ld (CAMMODE),a
                ld (CAMCUR),bc
                call set_camera_at
                xor a
                ld (CAMMOV),a
                ret

b_panCameraTo:  call rd_vw1
                ld (SPTR),de
                ld (CAMDEST),bc
                ld a,CAM_PANNING
                ld (CAMMODE),a
                xor a
                ld (CAMMOV),a
                ret

; actorFollowCamera: mientras no haya startScene (fase 5), el actor que no esta en la sala sale al anfitrion como H oo [actor]
b_actorFollowCamera:
                call rd_vb1
                ld (SPTR),de
                ld (ARGS),bc
                call chk_actor
                call in_room
                jr z,afc_go
                ld a,1                  ; fuera de la sala: startScene es de la fase 5
                ld (ARGN),a
                ld a,(OPC)
                ld (TOPOP),a
                jp host_call
afc_go:         ld a,(CAMFOL)
                push af                 ; el actor al que seguia
                call actor_num
                push af
                ld a,CAM_FOLLOW         ; setCameraFollows
                ld (CAMMODE),a
                pop af
                ld (CAMFOL),a
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                sra h
                rr l
                sra h
                rr l
                sra h
                rr l                    ; x // 8
                ld de,(SSTRIP)
                or a
                sbc hl,de               ; t
                ld de,CAM_LEFT
                push hl
                call sless              ; t < left
                pop hl
                jr c,afc_at
                ld de,CAM_RIGHT+1
                call sless              ; t < right + 1: no se pasa
                jr c,afc_nat
afc_at:         ld c,(ix+A_X)
                ld b,(ix+A_X+1)
                call set_camera_at
afc_nat:        ld a,1                  ; los actores de la sala se redibujan
afc_rd:         push af
                call actor_ix
                call in_room
                jr nz,afc_n
                set 0,(ix+A_FLAGS)
afc_n:          pop af
                inc a
                cp NACT
                jr c,afc_rd
                call run_inv0
                pop af                  ; si ha cambiado de actor: otra vez
                ld hl,CAMFOL
                cp (hl)
                jr z,afc_e
                call run_inv0
afc_e:          xor a
                ld (CAMMOV),a
                ret

; ---------------------------------------------------------------- actores: lectura
get_prep:       call rd_res             ; resultado y actor (derefActor) -> IX
                call rd_vb1
                ld (SPTR),de
                jp chk_actor

b_getActorRoom: call rd_res
                call rd_vb1
                ld (SPTR),de
                call is_act13
                or a
                jr z,gar_0
                ld a,c                  ; (is_act13 deja en A el 1, no el actor)
                call actor_ix
                ld c,(ix+A_ROOM)
                ld b,0
                jp set_res
gar_0:          ld bc,0
                jp set_res

b_getActorElevation:
                call get_prep
                ld c,(ix+A_ELEV)
                ld b,(ix+A_ELEV+1)
                jp set_res
b_getActorMoving:
                call get_prep
                ld c,(ix+A_MOVING)
                ld b,0
                jp set_res
b_getActorFacing:
                call get_prep
                ld l,(ix+A_FACING)
                ld h,(ix+A_FACING+1)
                call n2o
                ld c,a
                ld b,0
                jp set_res
b_getActorCostume:
                call get_prep
                ld c,(ix+A_COST)
                ld b,(ix+A_COST+1)
                jp set_res
b_getActorWalkBox:
                call get_prep
                ld c,(ix+A_WBOX)
                ld b,0
                jp set_res

; getActorX / getActorY: un actor (1..) da su x, y; un objeto, getObjectOrActorXY o -1; obj < 1 da 0
b_getActorX:    ld a,A_X
                jr gxy
b_getActorY:    ld a,A_Y
gxy:            ld (SC+0),a
                call rd_res
                call rd_vb1
                ld (SPTR),de
                ld a,b
                or c
                jr z,gxy_0
                bit 7,b
                jr nz,gxy_0
                ld a,b
                or a
                jr nz,gxy_o
                ld a,c
                cp NACT
                jr nc,gxy_o
                call actor_ix
                ld a,(SC+0)
                ld e,a
                ld d,0
                push ix
                pop hl
                add hl,de
                ld c,(hl)
                inc hl
                ld b,(hl)
                jp set_res
gxy_o:          call wio
                inc a
                jr z,gxy_m1
                call goa_xy
                jr c,gxy_m1
                ld a,(SC+0)
                cp A_X
                jr z,gxy_x
                ex de,hl
gxy_x:          ld b,h
                ld c,l
                jp set_res
gxy_m1:         ld bc,$FFFF
                jp set_res
gxy_0:          ld bc,0
                jp set_res

; ---------------------------------------------------------------- actores: cambios
b_putActor:     call rd_vb1
                call chk_actor
                call rd_vw2
                push bc
                call rd_vw3
                ld (SPTR),de
                ld d,b
                ld e,c
                pop hl
                ld c,(ix+A_ROOM)
                jp put_actor

b_putActorInRoom:
                call rd_vb1
                call chk_actor
                call rd_vb2
                ld (SPTR),de
                push bc
                ld a,(ix+A_VIS)
                or a
                jr z,pir_1
                ld a,(CURROOM)
                ld h,0
                ld l,a
                or a
                sbc hl,bc
                jr z,pir_1
                call actor_num
                ld e,a
                ld d,0
                ld hl,(VAR_TALK_ACTOR)
                or a
                sbc hl,de
                jr nz,pir_1
                push ix
                call stop_talk
                pop ix
pir_1:          pop bc
                ld (ix+A_ROOM),c
                ld a,b
                or c
                ret nz
                ld hl,0
                ld d,h
                ld e,l
                ld c,0
                jp put_actor

b_putActorAtObject:
                call rd_vb1
                call chk_actor
                call rd_vw2
                ld (SPTR),de
                call wio
                inc a
                jr z,pao_def
                jp err_badobj           ; FASE5: getObjectXYPos
pao_def:        ld hl,240
                ld de,120
                ld c,(ix+A_ROOM)
                jp put_actor

b_animateActor: call rd_vb1
                push bc
                call rd_vb2
                ld (SPTR),de
                pop hl                  ; HL = actor, BC = animacion
                ld a,h
                or a
                ret nz
                ld a,l
                cp NACT
                ret nc
                push bc
                ld a,l
                call actor_ix
                pop bc
                ld a,b
                or a
                jr nz,an_gen
                ld a,c
                cp 244                  ; (anim >> 2) = 61, 62 o 63: girar, cambiar de direccion, parar
                jr c,an_gen
                cp 252
                jr nc,an_stop
                cp 248
                jr nc,an_dir
                call old_dir            ; girar
                call in_room
                ret nz
                jp turn_to_dir
an_stop:        call in_room
                ret nz
                ld b,0
                ld c,(ix+A_STAND)
                call start_anim
                ld (ix+A_MOVING),0
                ret
an_dir:         call old_dir
                call in_room
                jr nz,an_d1
                res 2,(ix+A_MOVING)
an_d1:          ld (ix+A_FACING),l
                ld (ix+A_FACING+1),h
                ret
an_gen:         jp start_anim

b_faceActor:    call rd_vb1
                push bc
                call rd_vw2
                ld (SPTR),de
                pop hl                  ; HL = actor, BC = objeto
                ld a,h
                or a
                ret nz
                ld a,l
                cp NACT
                ret nc
                push bc
                ld a,l
                call actor_ix
                pop bc
                call in_room
                ret nz
                push ix
                push bc
                call goa_xy             ; HL = x2, DE = y2
                pop bc
                pop ix
                ret c
                ld (SC+0),hl
                ld (SC+2),de
                push ix
                call goa_width
                pop ix
                srl a                   ; width // 2
                ld (SC+4),a
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,(SC+0)
                call sless              ; a.x < x2 -> d = 1
                ld a,0
                adc a,0
                ld (SC+5),a
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,(SC+0)
                call abs_diff
                ld a,(SC+4)
                ld e,a
                ld d,0
                or a
                sbc hl,de
                jr nc,fa_turn           ; |a.x - x2| >= width // 2
                ld hl,(SC+2)
                ld e,(ix+A_Y)
                ld d,(ix+A_Y+1)
                call sless              ; y2 < a.y -> d = 3, si no 2
                ld a,2
                adc a,0
                ld (SC+5),a
fa_turn:        ld a,(SC+5)
                ld c,a
                call old_dir
                jp turn_to_dir

; ---------------------------------------------------------------- distancias
; getObjActToObjActDist: BC = a, DE = b -> HL = distancia (sin signo; $FF si alguno no esta)
dist:           ld (SC+0),bc
                ld (SC+2),de
                call is_act13
                ld (SC+4),a
                ld bc,(SC+2)
                call is_act13
                ld (SC+5),a
                ld hl,(SC+4)
                ld a,l
                and h
                jr z,ds_noz
                ld a,(SC+0)             ; los dos son actores de una misma sala distinta de la actual: 0
                call actor_ix
                ld a,(ix+A_ROOM)
                ld (SC+6),a
                ld a,(SC+2)
                call actor_ix
                ld a,(ix+A_ROOM)
                ld hl,SC+6
                cp (hl)
                jr nz,ds_noz
                or a
                jr z,ds_noz
                ld a,(SC+0)
                call actor_ix
                call in_room
                jr z,ds_noz
                ld hl,0
                ret
ds_noz:         ld bc,(SC+0)
                call goa_xy
                jr c,ds_ff
                ld (SC+8),hl
                ld (SC+10),de
                ld bc,(SC+2)
                call goa_xy
                jr c,ds_ff
                ld a,(SC+4)             ; un actor y un objeto: el punto del objeto se ajusta a las cajas del actor
                or a
                jr z,ds_calc
                ld a,(SC+5)
                or a
                jr nz,ds_calc
                push hl
                push de
                ld a,(SC+0)
                call actor_ix
                pop de
                pop hl
                call adjust_xy
ds_calc:        ld (SC+12),hl
                ld (SC+14),de
                ld hl,(SC+10)
                call abs_diff           ; DE = y2
                push hl
                ld hl,(SC+8)
                ld de,(SC+12)
                call abs_diff
                pop de                  ; DE = |dy|, HL = |dx|
                push hl
                or a
                sbc hl,de
                pop hl
                ret nc
                ex de,hl
                ret
ds_ff:          ld hl,$FF
                ret

b_getDist:      call rd_res
                call rd_vw1
                push bc
                call rd_vw2
                ld (SPTR),de
                ld d,b
                ld e,c
                pop bc
                call dist
                ld b,h
                ld c,l
                jp set_res

b_getClosestObjActor:
                call rd_res
                call rd_vw1
                ld (SPTR),de
                ld (SC+16),bc
                ld hl,(VAR_ACTOR_RANGE_MAX)
                ld (SC+18),hl
                ld hl,$FF
                ld (SC+20),hl
                ld (SC+22),hl
gc_l:           ld bc,(SC+16)
                ld de,(SC+18)
                call dist
                ld de,(SC+22)
                or a
                sbc hl,de
                jr nc,gc_n
                add hl,de
                ld (SC+22),hl
                ld hl,(SC+18)
                ld (SC+20),hl
gc_n:           ld hl,(SC+18)
                dec hl
                ld (SC+18),hl
                ld de,(VAR_ACTOR_RANGE_MIN)
                call sless
                jr nc,gc_l
                ld bc,(SC+20)
                jp set_res

b_actorFromPos: call rd_res
                call rd_vw1
                push bc
                call rd_vw2
                ld (SPTR),de
                ld (SC+2),bc
                pop bc
                ld (SC+0),bc
                ld a,1
afp_l:          ld (SC+4),a
                call actor_ix
                call in_room
                jr nz,afp_n
                ld a,(ix+A_VIS)
                or a
                jr z,afp_n
                ld l,(ix+A_X)           ; x0 <= x < x1 (un rectangulo fijo alrededor del actor, hasta la fase 8)
                ld h,(ix+A_X+1)
                ld de,12
                or a
                sbc hl,de
                ex de,hl
                ld hl,(SC+0)
                call sless
                jr c,afp_n
                ld l,(ix+A_X)
                ld h,(ix+A_X+1)
                ld de,12
                add hl,de
                ex de,hl
                ld hl,(SC+0)
                call sless
                jr nc,afp_n
                ld a,(SC+4)             ; sin la clase UNTOUCHABLE (bit 23 de los 24 bits de clases)
                ld l,a
                ld h,0
                ld d,h
                ld e,l
                add hl,hl
                add hl,de
                ld de,OBJCLS+2
                add hl,de
                bit 7,(hl)
                jr nz,afp_n
                ld l,(ix+A_Y)           ; y1 <= y <= y2
                ld h,(ix+A_Y+1)
                ld de,60
                or a
                sbc hl,de
                ld e,(ix+A_ELEV)
                ld d,(ix+A_ELEV+1)
                or a
                sbc hl,de
                ex de,hl
                ld hl,(SC+2)
                call sless
                jr c,afp_n
                ld l,(ix+A_Y)
                ld h,(ix+A_Y+1)
                ld de,(SC+2)
                call sless              ; y2 < y: fuera
                jr c,afp_n
                ld a,(SC+4)
                ld c,a
                ld b,0
                jp set_res
afp_n:          ld a,(SC+4)
                inc a
                cp NACT
                jp c,afp_l
                ld bc,0
                jp set_res
