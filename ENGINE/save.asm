; =====================================================================
;  save.asm - o4_saveLoadGame (overlay). El guardar/cargar es el del propio juego (script 163 en Maniac Mansion: sala 50 con sus verbos); el
;  opcode solo hace lo que ScummVM: a = ranura + 32 * orden: 0 numero de ranuras (100), 1 unidad (3), 2 cargar (3 bien, 5 mal),
;  4 guardar (0 bien, 2 mal), 6 comprobar si existe (6 si, 7 no). Los ficheros SAVEnn.SAV van en la carpeta actual (la del juego).
;  Un fichero guarda el estado del nucleo ($E000-$FFFF: variables, ranuras de scripts, actores, objetos...), las variables del overlay
;  ($CD00-$CF8F: interfaz, verbos, nombres, camara) y el inventario, con la cabecera de DATA.BIN (ld_hdr) para reconocer el juego.
;  Al cargar el script en marcha sigue por su ranura restaurada (como ScummVM: updateScriptPtr / resetScriptPointer) y la sala se pinta.
; =====================================================================
CMD_FWRITE      equ 56
CMD_FCREATE     equ 71
SV_NAME         equ $9740               ; el nombre del fichero (12 bytes)
SV_HDR          equ $9750               ; la cabecera: la de DATA.BIN (ld_hdr, 16 bytes) y la direccion de ev_handler (identifica la version del programa)
SV_TMP          equ $9770               ; cabecera leida (18 bytes)
SV_LIVE         equ $9800               ; el estado vivo del interprete mientras se carga: $EB00-$EB3F, los dos primeros bytes de ARGS y los vectores EVVEC / HOSTVEC (73 bytes)
sv_h            equ $9790               ; variables (el overlay esta en una pagina de solo lectura)
wr_err          equ $9791
wr_h            equ $9792
wr_src          equ $9793
wr_cnt          equ $9795
SV_LEN_E        equ $2000
SV_LEN_O        equ $0290
SV_LEN_I        equ $9500-INVSL

ho_saveload:    ld a,(ARGS+2)
                and $E0
                ld hl,100               ; 0: numero de ranuras
                jp z,sl_res
                ld hl,3                 ; 1: unidad
                cp $20
                jp z,sl_res
                cp $40
                jp z,sl_load
                cp $80
                jp z,sl_save
                cp $C0
                jp z,sl_test
                ld hl,0
sl_res:         ld (HRES),hl
                ret

; SAVEnn.SAV con nn = ranura + 1
sl_name:        ld hl,sl_tpl
                ld de,SV_NAME
                ld bc,11
                ldir
                ld a,(ARGS+2)
                and $1F
                inc a
                ld b,'0'-1
sln_t:          inc b
                sub 10
                jr nc,sln_t
                add a,10+'0'
                ld hl,SV_NAME+4
                ld (hl),b
                inc hl
                ld (hl),a
                ret
sl_tpl:         defb "SAVE00.SAV",0

sl_hdr:         ld hl,ld_hdr
                ld de,SV_HDR
                ld bc,16
                ldir
                ld hl,ev_handler
                ld (SV_HDR+16),hl
                ret

sl_test:        call sl_name
                ld hl,SV_NAME
                call f_open
                cp $FF
                ld hl,7
                jp z,sl_res
                call f_close
                ld hl,6
                jp sl_res

sl_save:        call update_ptr         ; el puntero del script en marcha va a su ranura: al cargar sigue justo despues de este opcode
                call sl_name
                ld hl,SV_NAME
                call f_create
                cp $FF
                ld hl,2
                jp z,sl_res
                ld (sv_h),a
                xor a
                ld (wr_err),a
                call sl_hdr
                ld a,(sv_h)
                ld hl,SV_HDR
                ld bc,18
                call f_write_n
                ld a,(sv_h)
                ld hl,$E000
                ld bc,SV_LEN_E
                call f_write_n
                ld a,(sv_h)
                ld hl,UI_DIRTY
                ld bc,SV_LEN_O
                call f_write_n
                ld a,(sv_h)
                ld hl,INVSL
                ld bc,SV_LEN_I
                call f_write_n
                ld a,(sv_h)
                call f_close
                ld hl,0
                ld a,(wr_err)
                or a
                jp z,sl_res
                ld hl,2
                jp sl_res

sl_load:        call sl_name
                ld hl,SV_NAME
                call f_open
                cp $FF
                ld hl,5
                jp z,sl_res
                ld (sv_h),a
                call sl_hdr             ; la cabecera tiene que ser la de este DATA.BIN y de este programa
                ld a,(sv_h)
                ld hl,SV_TMP
                ld bc,18
                call f_read_n
                ld hl,SV_TMP
                ld de,SV_HDR
                ld b,18
sll_c:          ld a,(de)
                cp (hl)
                jp nz,sll_bad
                inc hl
                inc de
                djnz sll_c
                ld hl,$EB00             ; lo que no se restaura: el estado del interprete en este instante
                ld de,SV_LIVE
                ld bc,64
                ldir
                ld hl,(ARGS)
                ld (SV_LIVE+64),hl
                ld hl,EVVEC
                ld de,SV_LIVE+66
                ld bc,7
                ldir
                ld a,(sv_h)
                ld hl,$E000
                ld bc,SV_LEN_E
                call f_read_n
                ld a,(sv_h)
                ld hl,UI_DIRTY
                ld bc,SV_LEN_O
                call f_read_n
                ld a,(sv_h)
                ld hl,INVSL
                ld bc,SV_LEN_I
                call f_read_n
                ld a,(sv_h)
                call f_close
                ld hl,SV_LIVE
                ld de,$EB00
                ld bc,64
                ldir
                ld hl,(SV_LIVE+64)
                ld (ARGS),hl            ; la variable del resultado de este opcode
                ld hl,SV_LIVE+66
                ld de,EVVEC
                ld bc,7
                ldir
                ld a,(UI_DIRTY)
                or 7
                ld (UI_DIRTY),a
                call sdx_stopvgm        ; sin sonido: el estado de la musica no se guarda
                xor a
                ld (sdx_cur),a
                ld (sdx_next),a
                ld a,(CURROOM)
                ld (EVARGS),a
                call gf_load_room       ; la imagen de la sala restaurada
                ld a,(CUR)
                call load_slot          ; el script sigue por donde dice su ranura restaurada
                ld hl,3
                jp sl_res
sll_bad:        ld a,(sv_h)
                call f_close
                ld hl,5
                jp sl_res


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

; A = manejador, HL = origen, BC = cuantos (cualquier cantidad): en trozos de CHUNK; wr_err pasa a distinto de 0 si el MCU rechaza alguno
f_write_n:      ld (wr_h),a
                ld (wr_src),hl
                ld (wr_cnt),bc
fwn_l:          ld bc,(wr_cnt)
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
                ld a,(wr_h)
                call mcu_send
                ld a,e
                call mcu_send
                ld a,d
                call mcu_send
                ld hl,(wr_src)
fwn_b:          ld a,(hl)
                inc hl
                call mcu_send
                dec de
                ld a,d
                or e
                jr nz,fwn_b
                ld (wr_src),hl
                call mcu_recv
                ld hl,wr_err
                or (hl)
                ld (hl),a
                pop de
                ld hl,(wr_cnt)
                or a
                sbc hl,de
                ld (wr_cnt),hl
                jr fwn_l
