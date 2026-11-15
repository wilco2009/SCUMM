; loader.asm (v3) - carga de DATA.BIN (SCUMM/V3/TOOLS/pack_data3.py, version 3) en las tablas del nucleo, en las paginas frias y en las paginas de datos
;
; load_data: abre DATA/DATA.BIN y copia SCRDIR, OBJOWN, OBJST y BIGDIR a sus sitios del bloque 7, OBJCLS a la pagina fria CLS_PG, ROOMDIR, ODIR, OBJROOM, COSTDIR y
; COSTDIR2 a la pagina fria TABPG (cada una por la ventana de datos; hace falta FULLPAGING), el perfil a PROF y la tabla de banderas de los sonidos a SNDF. Las paginas
; de datos se leen por demanda (dp_cache.inc). Carry si falla. El orden de los datos en el fichero es el de pack_data3.OFFSETS.

data_name:      defb "DATA/DATA.BIN",0          ; relativo a la carpeta actual: la del juego (SCUMM/V3/INDY3...)
ld_hdr:         defs 16
ld_h:           defb 0

ld_rd:          ld a,(ld_h)                     ; HL = destino, BC = bytes
                jp f_read_n

load_data:      call dp_close
                ld hl,data_name
                call f_open
                cp $FF
                jp z,ld_nofile
                ld (ld_h),a
                ld hl,ld_hdr
                ld bc,16
                call ld_rd
                ld hl,ld_hdr                    ; "SDAT", version 3
                ld a,(hl)
                cp 'S'
                jp nz,ld_bad
                inc hl
                ld a,(hl)
                cp 'D'
                jp nz,ld_bad
                ld a,(ld_hdr+4)
                cp 3
                jp nz,ld_bad
                ld hl,SCRDIR
                ld bc,600
                call ld_rd
                ld hl,OBJOWN
                ld bc,1000
                call ld_rd
                ld hl,OBJST
                ld bc,1000
                call ld_rd
                ld a,CLS_PG                     ; OBJCLS: 3 bytes por objeto, desde el principio de su pagina
                call map_phys
                ld hl,WINDOW
                ld bc,3000
                call ld_rd
                ld a,TABPG                      ; las tablas frias (nucleo, COLD_*): OBJROOM, ROOMDIR, ODIR, COSTDIR, COSTDIR2
                call map_phys
                ld hl,WINDOW+COLD_OBJROOM
                ld bc,1000
                call ld_rd
                ld hl,WINDOW+COLD_ROOMDIR
                ld bc,3200
                call ld_rd
                ld hl,WINDOW+COLD_ODIR
                ld bc,3000
                call ld_rd
                ld hl,WINDOW+COLD_COSTDIR
                ld bc,387
                call ld_rd
                ld hl,WINDOW+COLD_COSTDIR2
                ld bc,387
                call ld_rd
                ld hl,BIGDIR
                ld bc,32
                call ld_rd
                ld hl,PROF                      ; el perfil del juego (V3/TOOLS/pack_data3.py + V2/TOOLS/gameprofile.py)
                ld bc,256
                call ld_rd
                ld a,62
                call map_phys                   ; (una pagina de la cache, aun vacia: el relleno no puede ir a la pagina fria)
                ld hl,(ld_hdr+13)               ; el relleno hasta el final de la zona de tablas (TABLES): a la ventana
                ld de,16+600+1000+1000+3000+1000+3200+3000+387+387+32+256
                or a
                sbc hl,de
                ld b,h
                ld c,l
                ld hl,WINDOW
                call ld_rd
                ld a,1
                call map_phys                   ; la ventana vuelve a su pagina de arranque
                ld hl,dp_clr                    ; la cache de paginas empieza vacia
                ld de,dp_clr+1
                ld bc,DP_CLRLEN-1
                ld (hl),0
                ldir
                ld a,(ld_hdr+6)
                ld (dp_first),a
                ld hl,(ld_hdr+13)
                ld (dp_tab),hl
                ld a,(ld_h)
                ld (dp_h),a                     ; el fichero se queda abierto
                ld a,1
                ld (dp_on),a
                ld a,(ld_hdr+5)
                ld (dp_n),a
                ld hl,SNDF                      ; banderas de los 256 sonidos (la tabla de sonidos esta en una pagina de datos: +1 de cada entrada de 4 bytes)
                ld de,SNDF+1
                ld bc,255
                ld (hl),0
                ldir
                ld a,(ld_hdr+10)
                or a
                jr z,ld_nosnd
                call map_page                   ; (por la cache: conserva HL y DE)
                ld hl,(ld_hdr+11)
                inc hl
                ld de,SNDF
                ld b,0
ld_sf:          ld a,(hl)
                ld (de),a
                inc de
                inc hl
                inc hl
                inc hl
                inc hl
                djnz ld_sf
                ld a,1
                call map_phys
ld_nosnd:       or a
                ret
ld_bad:         ld a,(ld_h)
                call f_close
ld_fail:        scf
                ret
ld_nofile:      scf
                ret

                include "dp_cache.inc"
