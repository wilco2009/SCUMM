; =====================================================================
;  ROOMVIEW.ASM - visor de salas SCUMM convertidas (ROOMnn.GFX) para el SD81 Booster.
;
;  Prueba la fase 3 del plan (claude/planning/scumm_plan.md): Superfast texto de 32 columnas con
;  256 caracteres definibles (256C), color Chroma modo 0 (un par de colores por scanline de cada
;  codigo), pantalla alternativa en $8000, scroll fino por hardware (POKE 2090) y recarga de los
;  tiles que entran por los bordes al mover la camara.
;
;  Teclas:   O / P    desplazar 1 pixel a la izquierda / derecha
;            B / N    sala anterior / siguiente
;            ESPACIO  salir a BASIC
;
;  Datos:    /SCUMM/ROOMnn.GFX en la SD (los genera SCUMM/V2/TOOLS/lfl2gfx.py; ver README.md)
;
;  Memoria:  $6000-      este programa
;            $7F00-      variables
;            $8000-$8318 pantalla (1 + 24 filas de 33 bytes)
;            $8400-      el fichero .GFX entero (hasta 14 KB)
;            $3800-$3FFF tabla de 256 caracteres (I = $38)
;            $C000-$C7FF tabla de color del modo 0 (los bloques 6 y 7 se mapean a sus propias paginas)
;
;  Codigos de caracter: 0-189 los slots de tiles de la sala; 192-255 el juego de caracteres de la ROM
;  (para el texto de la linea de estado; el 192 es el espacio y sirve de tile en blanco).
;  Los codigos >= 128 salen invertidos por el hardware: el conversor ya guarda esas formas al reves, y
;  las letras de la ROM se invierten aqui al copiarlas.
;
;  Ensamblar: pasmo roomview.asm roomview.bin roomview.sym   (compila.bat)
; =====================================================================

SET_FAST    equ 02E7h           ; ROM: apaga el video si estaba en SLOW
SLOW_FAST   equ 0207h           ; ROM: vuelve al modo que pide CDFLAG

DataPort    equ 0A7h
ClkPort     equ 0AFh
CMD_64C     equ 1Ch
CMD_256C    equ 41h
CMD_FOPEN   equ 53
CMD_FREAD   equ 55
CMD_FCLOSE  equ 57
CMD_FSTAT   equ 59
MAP_PORT    equ 0E7h
CHUNK       equ 512

CHROMA_P    equ 07FEFh
CHROMA_ON   equ 020h            ; color, modo 0, borde negro
CHROMA_OFF  equ 00Ch

DFILE       equ 8000h
GFXBUF      equ 8400h
TILES       equ 3800h
COLORS      equ 0C000h
FONT_I      equ 38h
BLANK       equ 216             ; tile en blanco = el primer glifo de la fuente (el espacio)
GLYPH0      equ 216             ; codigos de la fuente: 216-255 (40 glifos)
NGLYPH      equ 40
STAT_ROW    equ 17

; --- variables
V           equ 7F00h
room        equ V+0
cam         equ V+1             ; palabra
fine        equ V+3
cols        equ V+4             ; palabra
npos        equ V+6
ninst       equ V+8
mapp        equ V+10
rstp        equ V+12
instp       equ V+14
lstp        equ V+16
llp         equ V+18
handle      equ V+20
fsize       equ V+21            ; 4 bytes
srcp        equ V+25
sv_sp       equ V+27
sv_i        equ V+29
dirn        equ V+30            ; sentido de la busqueda de sala (+1 / -1)
errc        equ V+31
gofs        equ V+52            ; desplazamiento de los codigos de texto (0: ROM nativa, 192 tras init_font)
name_buf    equ V+32            ; 20 bytes
NAME_LEN    equ 17

            org  24576

start:      ld   (sv_sp),sp
            ld   a,i
            ld   (sv_i),a
            call SET_FAST
            ld   a,6                ; bloques 6 y 7 a sus paginas: el $C000 es la tabla de color
            ld   e,6
            call mcu_map
            ld   a,7
            ld   e,7
            call mcu_map
            xor  a
            ld   (gofs),a           ; de momento se escribe con los codigos nativos del ZX81
            call fill_screen
            ld   hl,DFILE
            ld   (2096),hl          ; pantalla alternativa
            ld   a,170
            ld   (2098),a
            ld   (2045),a           ; Superfast texto (sin color ni 256C todavia: se ve en blanco y negro)
            ld   hl,tx_title
            ld   de,DFILE+1
            call put_str
            ld   a,85
            ld   (2058),a           ; WRX apagado: $2000-$3FFF no es la zona de caracteres
            ld   a,CMD_256C
            call mcu_send
            ld   hl,tx_256
            ld   de,DFILE+1+33
            call put_str
            ld   a,FONT_I
            ld   i,a
            call init_font
            ld   a,GLYPH0
            ld   (gofs),a
            call clear_screen
            ld   bc,CHROMA_P
            ld   a,CHROMA_ON
            out  (c),a
            ld   a,255              ; las filas 0-15 se desplazan; la 16-23 se quedan quietas
            ld   (2091),a
            ld   (2092),a
            xor  a
            ld   (2093),a
            ld   (2090),a
            ld   a,1
            ld   (room),a
            ld   (dirn),a
            call enter_room
            jr   nc,main
            call draw_fail          ; no hay ningun .GFX: se dice y se espera
fl_w:       call scan
            or   a
            jr   z,fl_w
            jp   quit

tx_title:   defb "ROOMVIEW",0
tx_256:     defb "256C OK",0
tx_fail:    defb "CANNOT READ",0

main:       call wait_vs
            call scan
            bit  4,a
            jp   nz,quit
            bit  2,a
            jr   nz,next_room
            bit  3,a
            jr   nz,prev_room
            bit  0,a
            jr   nz,go_left
            bit  1,a
            jr   z,main
            call move_right
            jr   main
go_left:    call move_left
            jr   main
next_room:  ld   a,1
            jr   change_room
prev_room:  ld   a,0FFh
change_room: ld  (dirn),a
            call step_room
            call enter_room
cr_rel:     call scan               ; esperar a soltar
            or   a
            jr   nz,cr_rel
            jr   main

quit:       ld   a,85
            ld   (2045),a
            ld   (2098),a
            ld   (2090),a
            ld   a,255
            ld   (2093),a
            ld   bc,CHROMA_P
            ld   a,CHROMA_OFF
            out  (c),a
            ld   a,CMD_64C
            call mcu_send
            ld   a,(sv_i)
            ld   i,a
            call SLOW_FAST
            ld   sp,(sv_sp)
            ld   bc,0
            ret

; ---------------------------------------------------------------------
;  Teclado: A = bits 0 O, 1 P, 2 N, 3 B, 4 ESPACIO (a 1 si esta pulsada)
; ---------------------------------------------------------------------
scan:       ld   c,0
            ld   a,0DFh             ; P O I U Y
            in   a,(0FEh)
            bit  1,a
            jr   nz,sc1
            set  0,c
sc1:        bit  0,a
            jr   nz,sc2
            set  1,c
sc2:        ld   a,07Fh             ; ESPACIO . M N B
            in   a,(0FEh)
            bit  3,a
            jr   nz,sc3
            set  2,c
sc3:        bit  4,a
            jr   nz,sc4
            set  3,c
sc4:        bit  0,a
            jr   nz,sc5
            set  4,c
sc5:        ld   a,c
            ret

; espera al siguiente VSYNC (el contador de los bits 6-1 se pone a cero al leerlo). Con un limite
; de unos dos fotogramas: si el contador no avanza, el programa sigue igualmente.
wait_vs:    in   a,(ClkPort)
            ld   bc,2000
wv1:        in   a,(ClkPort)
            and  07Eh
            ret  nz
            dec  bc
            ld   a,b
            or   c
            jr   nz,wv1
            ret

; ---------------------------------------------------------------------
;  Video
; ---------------------------------------------------------------------
; los 40 glifos de la fuente (espacio, cifras, letras, / : .) de la ROM a los codigos 216-255, en blanco sobre negro
init_font:  ld   hl,font_src
            ld   de,TILES+GLYPH0*8
            ld   b,NGLYPH
if_g:       push bc
            push hl
            ld   l,(hl)             ; caracter de la ROM
            ld   h,0
            add  hl,hl
            add  hl,hl
            add  hl,hl
            ld   bc,1E00h
            add  hl,bc
            ld   b,8
if_b:       ld   a,(hl)
            cpl                     ; el bit 7 del codigo invierte el video
            ld   (de),a
            inc  hl
            inc  de
            djnz if_b
            pop  hl
            inc  hl
            pop  bc
            djnz if_g
            ld   hl,COLORS+GLYPH0*8
            ld   (hl),0Fh           ; papel negro, tinta blanca brillante
            ld   de,COLORS+GLYPH0*8+1
            ld   bc,NGLYPH*8-1
            ldir
            ret

; codigos de la ROM del ZX81 de cada glifo: espacio, 0-9, A-Z, /, :, .
font_src:   defb 0
            defb 28,29,30,31,32,33,34,35,36,37
            defb 38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
            defb 24,14,27

clear_screen:
            ld   a,BLANK
fill_screen:                        ; A = codigo con el que se llena toda la pantalla
            ld   hl,DFILE
            ld   (hl),a
            ld   de,DFILE+1
            ld   bc,24*33
            ldir
            ld   a,076h
            ld   (DFILE),a
            ret

draw_fail:  ld   hl,tx_fail
            ld   de,DFILE+1+3*33+1
            call put_str
            ld   hl,name_buf
            ld   de,DFILE+1+4*33+1
            jp   put_str

; copia a la pantalla las 32 columnas visibles desde la camara y, en la posicion 32 de cada fila, la
; columna siguiente, que es la que asoma al hacer scroll fino (el .GFX se ha convertido con ventanas de
; 33 columnas, asi que sus tiles estan cargados). En la ultima posicion de camara (cam = npos) ya no hay
; columna 33 y se pone un tile en blanco.
draw_window:
            ld   hl,(mapp)
            ld   de,(cam)
            add  hl,de
            ld   (srcp),hl
            ld   de,DFILE+1
            ld   b,16
dw1:        push bc
            ld   hl,(srcp)
            ld   bc,33
            ldir
            ld   hl,(cam)           ; ultima posicion: la columna 33 no existe
            ld   bc,(npos)
            or   a
            sbc  hl,bc
            jr   c,dw2
            dec  de
            ld   a,BLANK
            ld   (de),a
            inc  de
dw2:        ld   hl,(srcp)
            ld   bc,(cols)
            add  hl,bc
            ld   (srcp),hl
            pop  bc
            djnz dw1
            ret

; ---------------------------------------------------------------------
;  Camara
; ---------------------------------------------------------------------
; HL = direccion de rstp/lstp + 2 * cam -> DE = primer indice, BC = ultimo + 1
get_range:  ld   de,(cam)
            ex   de,hl
            add  hl,hl
            ex   de,hl              ; DE = 2 * cam
            add  hl,de              ; HL = tabla + 2 * cam
            ld   e,(hl)
            inc  hl
            ld   d,(hl)
            inc  hl
            ld   c,(hl)
            inc  hl
            ld   b,(hl)
            ret

load_right: ld   hl,(rstp)          ; instancias que entran por la derecha en la posicion cam
            call get_range
lr1:        ld   a,d                ; DE = k, BC = fin
            xor  b
            jr   nz,lr2
            ld   a,e
            xor  c
            ret  z
lr2:        push bc
            push de
            ld   b,d
            ld   c,e
            call load_inst
            pop  de
            pop  bc
            inc  de
            jr   lr1

load_left:  ld   hl,(lstp)          ; instancias que entran por la izquierda
            call get_range
ll1:        ld   a,d
            xor  b
            jr   nz,ll2
            ld   a,e
            xor  c
            ret  z
ll2:        push bc
            push de
            ld   hl,(llp)           ; k = llist[j]
            add  hl,de
            add  hl,de
            ld   c,(hl)
            inc  hl
            ld   b,(hl)
            call load_inst
            pop  de
            pop  bc
            inc  de
            jr   ll1

; BC = indice de instancia: 8 bytes de forma a TILES + 8 * codigo y 8 de color a COLORS + 8 * codigo
load_inst:  ld   h,b
            ld   l,c
            add  hl,hl
            add  hl,hl
            add  hl,hl
            add  hl,hl
            add  hl,bc              ; 17 * k
            ld   de,(instp)
            add  hl,de
            ld   a,(hl)             ; codigo
            inc  hl
            push hl                 ; la forma
            ld   l,a
            ld   h,0
            add  hl,hl
            add  hl,hl
            add  hl,hl              ; 8 * codigo
            push hl
            ld   de,TILES
            add  hl,de
            ex   de,hl              ; DE = destino de la forma
            pop  bc                 ; BC = 8 * codigo
            pop  hl                 ; HL = forma
            push bc
            ld   bc,8
            ldir                    ; HL = color
            pop  de                 ; DE = 8 * codigo
            push hl
            ld   hl,COLORS
            add  hl,de
            ex   de,hl              ; DE = destino del color
            pop  hl
            ld   bc,8
            ldir
            ret

apply_fine: ld   a,(fine)
            ld   (2090),a
            ret

move_right: ld   hl,(cam)
            ld   de,(npos)
            or   a
            sbc  hl,de
            ret  nc                 ; ya en la ultima posicion (cam = npos)
            ld   a,(fine)
            inc  a
            cp   8
            jr   c,mr_set
            ld   hl,(cam)
            inc  hl
            ld   (cam),hl
            ld   de,(npos)
            or   a
            sbc  hl,de
            call c,load_right       ; en cam = npos no entra nada
            call draw_window
            call draw_status
            xor  a
mr_set:     ld   (fine),a
            jr   apply_fine

move_left:  ld   a,(fine)
            or   a
            jr   z,ml_cam
            dec  a
            ld   (fine),a
            jr   apply_fine
ml_cam:     ld   hl,(cam)
            ld   a,h
            or   l
            ret  z
            dec  hl
            ld   (cam),hl
            call load_left
            call draw_window
            call draw_status
            ld   a,7
            ld   (fine),a
            jr   apply_fine

; ---------------------------------------------------------------------
;  Sala
; ---------------------------------------------------------------------
; carga la sala `room`; si no existe el fichero prueba la siguiente en el sentido de dirn
enter_room: ld   b,60
er_try:     push bc
            call load_file
            pop  bc
            jr   nc,er_ok
            call step_room
            djnz er_try
            scf                     ; no hay ninguna
            ret

; room = room + dirn, dando la vuelta entre 1 y 99
step_room:  ld   a,(dirn)
            ld   hl,room
            add  a,(hl)
            jr   z,sr_wrap
            cp   100
            jr   c,sr_set
sr_wrap:    ld   a,(dirn)
            or   a
            ld   a,1
            jp   p,sr_set
            ld   a,99
sr_set:     ld   (room),a
            ret
er_ok:      call parse_header
            ld   hl,0
            ld   (cam),hl
            xor  a
            ld   (fine),a
            call apply_fine
            call clear_screen
            call load_right
            call draw_window
            jp   draw_status

; "/SCUMM/ROOMnn.GFX" en name_buf
make_name:  ld   hl,nm_tpl
            ld   de,name_buf
            ld   bc,NAME_LEN
            ldir
            ld   a,(room)
            ld   b,'0'-1
mn1:        inc  b
            sub  10
            jr   nc,mn1
            add  a,10+'0'
            ld   hl,name_buf+11
            ld   (hl),b
            inc  hl
            ld   (hl),a
            xor  a
            ld   (name_buf+NAME_LEN),a
            ret
nm_tpl:     defb "/SCUMM/ROOM00.GFX"

; lee el fichero a GFXBUF; carry si falla
load_file:  call make_name
            ld   a,CMD_FOPEN
            call mcu_send
            ld   a,NAME_LEN
            call mcu_send
            ld   hl,name_buf
            ld   b,NAME_LEN
lf1:        ld   a,(hl)
            inc  hl
            call mcu_send
            djnz lf1
            call mcu_recv
            cp   0FFh
            jr   nz,lf2
            scf
            ret
lf2:        ld   (handle),a
            call f_stat
            ld   hl,(fsize+2)
            ld   a,h
            or   l
            jr   nz,lf_bad
            ld   hl,(fsize)
            ld   de,16384-1024      ; no cabe en el buffer
            or   a
            sbc  hl,de
            jr   nc,lf_bad
            ld   hl,GFXBUF
lf_chunk:   ld   de,(fsize)
            ld   a,d
            or   e
            jr   z,lf_done
            ld   bc,CHUNK
            ex   de,hl
            or   a
            sbc  hl,bc              ; quedan menos de CHUNK?
            ex   de,hl
            jr   nc,lf3
            ld   bc,(fsize)         ; el ultimo trozo
lf3:        push bc
            ld   de,(fsize)         ; fsize -= BC
            ex   de,hl
            or   a
            sbc  hl,bc
            ex   de,hl
            ld   (fsize),de
            pop  de                 ; DE = cuantos
            ld   a,(handle)
            call f_read             ; HL = destino, avanza
            jr   lf_chunk
lf_done:    ld   a,(handle)
            call f_close
            or   a
            ret
lf_bad:     ld   a,(handle)
            call f_close
            scf
            ret

; A = handle -> fsize (4 bytes)
f_stat:     ld   c,a
            ld   a,CMD_FSTAT
            call mcu_send
            ld   a,c
            call mcu_send
            ld   hl,fsize
            ld   b,4
fst1:       call mcu_recv
            ld   (hl),a
            inc  hl
            djnz fst1
            ld   b,4
fst2:       call mcu_recv
            djnz fst2
            jp   mcu_recv

; A = handle, DE = cuantos (<= CHUNK), HL = destino -> HL avanza
f_read:     ld   c,a
            ld   a,CMD_FREAD
            call mcu_send
            ld   a,c
            call mcu_send
            ld   a,e
            call mcu_send
            ld   a,d
            call mcu_send
fr1:        call mcu_recv
            ld   (hl),a
            inc  hl
            dec  de
            ld   a,d
            or   e
            jr   nz,fr1
            jp   mcu_recv

f_close:    ld   c,a
            ld   a,CMD_FCLOSE
            call mcu_send
            ld   a,c
            call mcu_send
            jp   mcu_recv

; ---------------------------------------------------------------------
;  Cabecera del .GFX: "SGFX", version, nslots, cols(2), rows, view, npos(2), n(2), codebase(2)
; ---------------------------------------------------------------------
parse_header:
            ld   hl,(GFXBUF+6)
            ld   (cols),hl
            ld   hl,(GFXBUF+10)
            ld   (npos),hl
            ld   hl,(GFXBUF+12)
            ld   (ninst),hl
            ld   hl,GFXBUF+16
            ld   (mapp),hl
            ld   hl,(cols)          ; mapa: cols * 16 filas
            add  hl,hl
            add  hl,hl
            add  hl,hl
            add  hl,hl
            ld   de,GFXBUF+16
            add  hl,de
            ld   (rstp),hl
            ld   de,(npos)          ; (npos + 1) * 2
            inc  de
            ex   de,hl
            add  hl,hl
            ex   de,hl
            add  hl,de
            ld   (instp),hl
            ld   hl,(ninst)         ; n * 17
            ld   d,h
            ld   e,l
            add  hl,hl
            add  hl,hl
            add  hl,hl
            add  hl,hl
            add  hl,de
            ld   de,(instp)
            add  hl,de
            ld   (lstp),hl
            ld   de,(npos)
            inc  de
            ex   de,hl
            add  hl,hl
            ex   de,hl
            add  hl,de
            ld   (llp),hl
            ret

; ---------------------------------------------------------------------
;  Linea de estado (fila 17): "SALA nn  CAMARA ccc/mmm"
; ---------------------------------------------------------------------
draw_status:
            ld   de,DFILE+1+STAT_ROW*33+1
            ld   hl,st_room
            call put_str
            ld   a,(room)
            ld   l,a
            ld   h,0
            ld   b,2
            call put_num
            ld   hl,st_cam
            call put_str
            ld   hl,(cam)
            ld   b,3
            call put_num
            ld   a,'/'
            call put_chr
            ld   hl,(npos)
            ld   b,3
            call put_num
            ld   hl,st_keys
            ld   de,DFILE+1+(STAT_ROW+2)*33+1
            jp   put_str

st_room:    defb "ROOM ",0
st_cam:     defb "  CAM ",0
st_keys:    defb "O P: SCROLL  B N: ROOM  SPACE: EXIT",0

; HL = cadena ASCII acabada en 0 -> DE avanza
put_str:    ld   a,(hl)
            or   a
            ret  z
            inc  hl
            push hl
            call put_chr
            pop  hl
            jr   put_str

; A = ASCII -> glifo (indice 0-39) -> codigo en (DE). Antes de activar 256C (gofs = 0) se escribe con el codigo
; nativo de la ROM; despues, con GLYPH0 + indice.
put_chr:    cp   ' '
            jr   z,pc_sp
            cp   '/'
            jr   z,pc_sl
            cp   ':'
            jr   z,pc_co
            cp   '.'
            jr   z,pc_dot
            cp   '0'
            jr   c,pc_sp
            cp   '9'+1
            jr   c,pc_dig
            cp   'A'
            jr   c,pc_sp
            cp   'Z'+1
            jr   nc,pc_sp
            sub  'A'-11
            jr   pc_out
pc_dig:     sub  '0'-1
            jr   pc_out
pc_sl:      ld   a,37
            jr   pc_out
pc_co:      ld   a,38
            jr   pc_out
pc_dot:     ld   a,39
            jr   pc_out
pc_sp:      xor  a
pc_out:     ld   b,a
            ld   a,(gofs)
            or   a
            ld   a,b
            jr   nz,pc_new
            ld   hl,font_src
            ld   c,b
            ld   b,0
            add  hl,bc
            ld   a,(hl)
            jr   pc_put
pc_new:     add  a,GLYPH0
pc_put:     ld   (de),a
            inc  de
            ret

; HL = valor, B = cifras -> DE avanza
put_num:    ld   a,b
            cp   3
            jr   c,pn2
            ld   bc,100
            call pn_dig
pn2:        ld   bc,10
            call pn_dig
            ld   a,l
            add  a,'0'
            jr   put_chr
pn_dig:     ld   a,'0'-1
pn_l:       inc  a
            or   a
            sbc  hl,bc
            jr   nc,pn_l
            add  hl,bc
            jr   put_chr

; ---------------------------------------------------------------------
;  MCU
; ---------------------------------------------------------------------
; handshake: cada llamada mira el reloj; BC, DE y HL se conservan (A no sobrevive a mcu_send)
mcu_send:   push bc
            ld   b,a
            in   a,(ClkPort)
            ld   c,a
            ld   a,b
            out  (DataPort),a
msw:        in   a,(ClkPort)
            xor  c
            jp   p,msw
            pop  bc
            ret

mcu_recv:   push bc
            in   a,(ClkPort)
            ld   c,a
            in   a,(DataPort)
            ld   b,a
mrw:        in   a,(ClkPort)
            xor  c
            jp   p,mrw
            ld   a,b
            pop  bc
            ret

; A = bloque, E = pagina (paginacion simple: la pagina en los bits 7-3 del dato; completa: en B)
mcu_map:    push bc
            and  7
            ld   c,a
            ld   a,e
            and  31
            rlca
            rlca
            rlca
            or   c
            ld   b,e
            ld   c,MAP_PORT
            out  (c),a
            pop  bc
            ret
