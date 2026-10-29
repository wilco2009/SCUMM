; =====================================================================
;  agid.asm - overlay D: ficheros de save.game / restore.game (SAV/GAMEnn.SAV, nn = 01-12). Pagina PG_OVD, en el bloque 1 solo mientras se ejecuta (call_d).
;  Los datos de las 12 ranuras (si existen, descripciones de 32 bytes y la descripcion que se guarda) estan en la pagina PG_SAV, que aqui se mapea en la
;  ventana ($8000) mientras hace falta; el overlay B (la lista) las lee de ahi. El nucleo orquesta: lista, descripcion, confirmacion y esto.
;  Fichero: 32 bytes de descripcion y los bloques de sf_tab (direccion, largo).
; =====================================================================

                org $2000
                include "agires.inc"

                jp t_read               ; OVD_READ: las ranuras (existencia y descripcion) a la pagina PG_SAV
                jp t_prep               ; OVD_PREP: INBUF = descripcion previa de la ranura mn_res
                jp t_conf               ; OVD_CONF: la ventana de confirmacion en TMPM (guardar: MSGBUF pasa a ser la descripcion)
                jp t_do                 ; OVD_DO: guarda o carga la ranura mn_res (sv_ok = 1 si se ha cargado)

TXT             equ TMPM
CMD_FWRITE      equ 56
CMD_FCREATE     equ 71

; A = ranura (1-12) -> sf_nm
d_nm:           ld b,'0'
                cp 10
                jr c,dn_1
                sub 10
                inc b
dn_1:           add a,'0'
                ld (sf_nm+9),a
                ld a,b
                ld (sf_nm+8),a
                ret

; A = ranura (1-12) -> HL = SAV_DESC + 32 * (A - 1)
d_ptr:          dec a
                ld l,a
                ld h,0
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                add hl,hl
                ld de,SAV_DESC
                add hl,de
                ret

t_read:         ld a,PG_SAV
                call map_page
                ld a,1
                ld (d_i),a
dr_l:           ld a,(d_i)
                call d_nm
                ld hl,sf_nm
                call f_open
                cp $FF
                jr z,dr_no
                ld (sf_h),a
                ld a,(d_i)
                call d_ptr
                ld bc,32
                ld a,(sf_h)
                call f_read_n
                ld a,(sf_h)
                call f_close
                ld a,1
                jr dr_s
dr_no:          ld a,(d_i)
                call d_ptr
                ld (hl),0
                xor a
dr_s:           push af
                ld a,(d_i)
                dec a
                ld e,a
                ld d,0
                ld hl,SAV_EX
                add hl,de
                pop af
                ld (hl),a
                ld hl,d_i
                inc (hl)
                ld a,(hl)
                cp 13
                jr c,dr_l
                jp unmap_win

t_prep:         ld a,PG_SAV
                call map_page
                ld a,(mn_res)
                call d_ptr
                ld de,INBUF
                ld bc,31
                ldir
                xor a
                ld (INBUF+30),a
                ld hl,INBUF
                ld b,0
dp_l:           ld a,(hl)
                or a
                jr z,dp_e
                inc hl
                inc b
                jr dp_l
dp_e:           ld a,b
                ld (il_n),a
                jp unmap_win

t_conf:         ld a,PG_SAV
                call map_page
                ld a,(mn_res)
                call d_nm
                ld a,(sf_mode)
                or a
                jr nz,tc_ld
                ld hl,SAV_NEW           ; la descripcion escrita (30 caracteres como mucho) a la pagina
                ld de,SAV_NEW+1
                ld bc,31
                ld (hl),0
                ldir
                ld hl,MSGBUF
                ld de,SAV_NEW
                ld b,30
tc_c:           ld a,(hl)
                or a
                jr z,tc_d
                ld (de),a
                inc hl
                inc de
                djnz tc_c
tc_d:           ld hl,SAV_NEW
                ld (tc_dp),hl
                ld hl,s_sv1
                ld bc,s_sv2
                jr tc_b
tc_ld:          ld a,(mn_res)
                call d_ptr
                ld (tc_dp),hl
                ld hl,s_ld1
                ld bc,s_ld2
tc_b:           push bc
                ld de,TXT
                call tc_s
                ld hl,(tc_dp)
                call tc_s
                pop hl
                call tc_s
                ld hl,sf_nm+4
                call tc_s
                ld hl,s_end
                call tc_s
                xor a
                ld (de),a
                jp unmap_win
tc_s:           ld a,(hl)
                or a
                ret z
                ld (de),a
                inc hl
                inc de
                jr tc_s

t_do:           xor a
                ld (sv_ok),a
                ld a,PG_SAV
                call map_page
                ld a,(mn_res)
                call d_nm
                ld a,(sf_mode)
                or a
                jr nz,sf_load
                ld hl,sf_nm
                call f_create
                cp $FF
                jp z,unmap_win
                ld (sf_h),a
                xor a
                ld (wf_err),a
                ld a,(sf_h)
                ld hl,SAV_NEW
                ld bc,32
                call f_write_n
                ld hl,sf_tab
sw_l:           ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,d
                or e
                jr z,sw_d
                push hl
                ex de,hl
                ld a,(sf_h)
                call f_write_n
                pop hl
                jr sw_l
sw_d:           ld a,PG_OVL             ; y los add.to.pic, que estan en la pagina del A1
                call map_page
                ld a,(sf_h)
                ld hl,LWIN+ST_FIX-$2000
                ld bc,ST_LEN
                call f_write_n
                ld a,(sf_h)
                call f_close
                jp unmap_win

sf_load:        ld hl,sf_nm
                call f_open
                cp $FF
                jp z,unmap_win
                ld (sf_h),a
                call h_stop_sound       ; el sonido que suene se para (antes de cambiar las banderas)
                ld a,(sf_h)
                ld hl,SAV_NEW
                ld bc,32
                call f_read_n
                ld hl,sf_tab
sl_l:           ld e,(hl)
                inc hl
                ld d,(hl)
                inc hl
                ld c,(hl)
                inc hl
                ld b,(hl)
                inc hl
                ld a,d
                or e
                jr z,sl_d
                push hl
                ex de,hl
                ld a,(sf_h)
                call f_read_n
                pop hl
                jr sl_l
sl_d:           ld a,PG_OVL
                call map_page
                ld a,(sf_h)
                ld hl,LWIN+ST_FIX-$2000
                ld bc,ST_LEN
                call f_read_n
                ld a,(sf_h)
                call f_close
                ld a,1
                ld (FLAGS+6),a          ; restore.game acaba de ejecutarse
                ld (rs_keep),a
                ld (sv_ok),a
                xor a
                ld (st_valid),a         ; la barra de estado se redibuja
                jp unmap_win

; HL = nombre acabado en 0 -> A = manejador ($FF si no se puede crear): crea el fichero o lo vacia
f_create:       ld b,0
                push hl
fcr_l:          ld a,(hl)
                or a
                jr z,fcr_e
                inc hl
                inc b
                jr fcr_l
fcr_e:          pop hl
                ld a,CMD_FCREATE
                call mcu_send
                ld a,b
                call mcu_send
                inc b
                jr fcr_t
fcr_s:          ld a,(hl)
                inc hl
                call mcu_send
fcr_t:          djnz fcr_s
                jp mcu_recv

; A = manejador, HL = origen, BC = cuantos: en trozos de CHUNK
f_write_n:      ld (wf_h),a
                ld (wf_src),hl
                ld (wf_cnt),bc
fwn_l:          ld bc,(wf_cnt)
                ld a,b
                or c
                ret z
                ld hl,CHUNK
                or a
                sbc hl,bc
                jr c,fwn_full
                ld d,b
                ld e,c
                jr fwn_go
fwn_full:       ld de,CHUNK
fwn_go:         push de
                ld a,CMD_FWRITE
                call mcu_send
                ld a,(wf_h)
                call mcu_send
                ld a,e
                call mcu_send
                ld a,d
                call mcu_send
                ld hl,(wf_src)
fwn_b:          ld a,(hl)
                inc hl
                call mcu_send
                dec de
                ld a,d
                or e
                jr nz,fwn_b
                ld (wf_src),hl
                call mcu_recv
                ld hl,wf_err
                or (hl)
                ld (hl),a
                pop de
                ld hl,(wf_cnt)
                or a
                sbc hl,de
                ld (wf_cnt),hl
                jr fwn_l

sf_nm:          defb "SAV/GAME00.SAV",0
s_sv1:          defb "About to save the game",10,"described as:",10,0
s_ld1:          defb "About to restore the game",10,"described as:",10,0
s_sv2:          defb 10,"in file:",10,0
s_ld2:          defb 10,"from file:",10,0
s_end:          defb 10,10,"Press ENTER to continue.",10,"Press ESC to cancel.",0
sf_tab:         defw VARS,256, FLAGS,256, INV,256, KEYMAP,256, OBJ,1024, STRS,492
                defw horizon,1, blk,5, pctl,1, lastpic,2, mg_n,1+4*MG_MAX, st_on,1, tfg,2, accin,1, ticks,1
                defw 0
d_i:           defb 0
sf_h:           defb 0
tc_dp:          defw 0
wf_h:           defb 0
wf_err:         defb 0
wf_src:         defw 0
wf_cnt:         defw 0
