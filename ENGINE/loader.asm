; loader.asm - carga de DATA.BIN (SCUMM/TOOLS/pack_data.py) en las tablas del nucleo y en las paginas de datos
;
; load_data: abre /SCUMM/DATA.BIN, copia SCRDIR, OBJOWN, OBJST, ROOMDIR y ODIR a su sitio y las paginas a la
; RAM extendida (cada una por la ventana de datos, con map_page; hace falta FULLPAGING). Carry si falla.

LD_TABLES       equ 6400
COSTDIR         equ $FF40               ; 64 x 3: pagina y direccion de los fotogramas de cada traje (0 = sin datos)

data_name:      defb "/SCUMM/DATA.BIN",0
ld_hdr:         defs 16
ld_h:           defb 0
ld_pg:          defb 0
ld_left:        defb 0

load_data:      ld hl,data_name
                call f_open
                cp $FF
                jp z,ld_nofile
                ld (ld_h),a
                ld a,'F'
                call ld_trace           ; F: el fichero se ha abierto
                ld a,(ld_h)
                ld hl,ld_hdr
                ld bc,16
                call f_read_n
                ld a,'G'
                call ld_trace           ; G: leida la cabecera
                ld hl,ld_hdr            ; "SDAT", version 2
                ld a,(hl)
                cp 'S'
                jp nz,ld_bad
                inc hl
                ld a,(hl)
                cp 'D'
                jp nz,ld_bad
                ld a,(ld_hdr+4)
                cp 2
                jp nz,ld_bad
                ld a,(ld_h)
                ld hl,SCRDIR
                ld bc,768
                call f_read_n
                ld a,(ld_h)
                ld hl,OBJOWN
                ld bc,780
                call f_read_n
                ld a,(ld_h)
                ld hl,OBJST
                ld bc,780
                call f_read_n
                ld a,(ld_h)
                ld hl,ROOMDIR
                ld bc,1024
                call f_read_n
                ld a,(ld_h)
                ld hl,ODIRBUF
                ld bc,780*3
                call f_read_n
                ld a,(ld_h)
                ld hl,COSTDIR
                ld bc,64*3
                call f_read_n
                ld a,(ld_h)
                ld hl,PROF              ; el perfil del juego (TOOLS/gameprofile.py)
                ld bc,256
                call f_read_n
                ld a,(ld_h)
                ld hl,ODIRBUF+780*3     ; el relleno hasta el final de la zona de tablas
                ld bc,LD_TABLES-16-768-780-780-1024-780*3-64*3-256
                call f_read_n
                ld a,'H'
                call ld_trace           ; H: leidas las tablas
                ld a,(ld_hdr+5)
                ld (ld_left),a
                ld a,(ld_hdr+6)
                ld (ld_pg),a
ld_page:        ld a,(ld_left)
                or a
                jr z,ld_done
                ld a,(ld_pg)
                call map_page
                ld a,(ld_h)
                ld hl,WINDOW
                ld bc,$1800
                call f_read_n
                ld hl,ld_pg
                inc (hl)
                ld a,(hl)
                cp OVL_PAGE             ; la pagina del overlay no es de datos: se salta (el Packer de TOOLS/vmmodel.py hace lo mismo)
                jr nz,ld_nxt
                inc (hl)
ld_nxt:         ld hl,ld_left
                dec (hl)
                jr ld_page
ld_done:        ld a,(ld_h)
                call f_close
                ld a,'I'
                call ld_trace           ; I: leidas las paginas
                or a
                ret
ld_bad:         ld a,'X'
                call ld_trace           ; X: la cabecera no es la esperada
                ld a,(ld_h)
                call f_close
ld_fail:        scf
                ret
ld_nofile:      ld a,'N'
                call ld_trace           ; N: no se ha podido abrir
                scf
                ret
