; GENERADO A MANO: variables del overlay y de la interfaz (RAM; el overlay esta en una pagina de solo lectura)
OVL_VARS        equ $8930
DBG_START       equ $971C               ; palabra de depuracion (la escribe el usuario desde el emulador): numero de script a arrancar; el motor la pone a 0
cam_cx          equ OVL_VARS+0
cam_mode        equ OVL_VARS+2
cam_dest        equ OVL_VARS+3
cam_fol         equ OVL_VARS+5
cam_new         equ OVL_VARS+6
cu_t            equ OVL_VARS+7
ac_cam          equ OVL_VARS+9
ac_n            equ OVL_VARS+11
ac_x            equ OVL_VARS+12
ac_y            equ OVL_VARS+14
ac_blob         equ OVL_VARS+16
ac_cx           equ OVL_VARS+18
ac_cy           equ OVL_VARS+20
ac_cp           equ OVL_VARS+21
ac_nx           equ OVL_VARS+23
ac_fl           equ OVL_VARS+25
ac_hold         equ OVL_VARS+26         ; fotogramas que los personajes siguen ocultos tras cambiar de sala
UI_DIRTY        equ $8800               ; bit 0 verbos, bit 1 frase, bit 2 inventario
UI_IFACE        equ $8801               ; bits 5-7 del estado de usuario: frase, inventario, verbos
UI_CURSOR       equ $8802               ; 1: el cursor esta activo
UI_PREV         equ $8804               ; copia de VAR_SENTENCE_VERB, OBJECT1, OBJECT2 y PREPOSITION (4 palabras)
UI_NAME         equ $880C               ; nombre de objeto convertido (hasta 31 + 0)
UI_PEGO         equ $882D               ; protagonista cuyo inventario esta dibujado
UI_INVO         equ $882E               ; primer objeto del inventario que se ve (de 2 en 2)
UI_TMP          equ $882F
UI_LIM          equ $8830
PF_IROW         equ PROF+1              ; perfil del juego (TOOLS/gameprofile.py): fila del inventario, de los verbos y de la frase
PF_VROW         equ PROF+2
PF_SROW         equ PROF+3
PF_COLMUL       equ PROF+4              ; columna de un verbo = (x * PF_COLMUL + PF_COLADD) >> PF_COLSHIFT; fila = y - PF_ROWSUB
PF_COLADD       equ PROF+5
PF_COLSHIFT     equ PROF+6
PF_ROWSUB       equ PROF+7
PF_TPLPOS       equ PROF+8              ; donde van las dos cifras de la sala en el nombre del fichero
PF_SHORT        equ PROF+9              ; desplazamientos (desde PROF) de las etiquetas de verbos, las preposiciones y el nombre de los ficheros
PF_PREPS        equ PROF+11
PF_TPL          equ PROF+13
PF_SNDTPL       equ PROF+15             ; desplazamiento del nombre de los ficheros de sonido y posicion de sus tres cifras
PF_SNDPOS       equ PROF+17
PF_KEYS         equ PROF+20             ; 10 palabras: valor de VAR_KEYPRESS de las teclas 1 2 3 4 5 6 7 8 9 0
ac_mk           equ OVL_VARS+31         ; 1: el personaje que se dibuja va detras de la mascara de la sala (su caja tiene mascara)
ac_s0           equ OVL_VARS+32         ; primera tira (8 pixeles) de la sala que cubre el personaje
ac_y0           equ OVL_VARS+33         ; palabra: fila de la sala de su primera fila de pixeles
ac_rh           equ OVL_VARS+35         ; filas de la ventana de mascara (alto del fotograma * 8)
ac_ns           equ OVL_VARS+36         ; tiras decodificadas
ac_cpage        equ OVL_VARS+37         ; pagina del traje que se dibuja
ac_mt           equ OVL_VARS+38         ; 8 bytes: la mascara de la celda (y, mientras se decodifica, las variables del bucle)
ac_mbl          equ OVL_VARS+46         ; palabra: direccion de la mascara de la sala en su pagina
AV              equ ACTNAME+NACTORS*3   ; mas variables del overlay (hasta $CFEF)
ac_mpg          equ AV                  ; pagina de la mascara de la sala
ac_sh           equ AV+1
sdx_cur          equ AV+2                ; sonido: el que suena (0: ninguno), su prioridad, si es reiniciable, el que esta en cola y su prioridad
sdx_cprio        equ AV+3
sdx_crest        equ AV+4
sdx_next         equ AV+5
sdx_nprio        equ AV+6
sdx_nn           equ AV+7                ; el que se esta arrancando: numero, prioridad, banderas y duracion
sdx_np           equ AV+8
sdx_nf           equ AV+9
sdx_nd           equ AV+10
sdx_tstep        equ AV+14               ; VAR_MUSIC_TIMER: 1/8 de fotograma entre dos incrementos (0: el sonido no lo usa) y lo que falta
sdx_tctr         equ AV+16
sdx_qn           equ $97F0               ; cola de startSound (Sound::_soundQueue): cuantos hay y los numeros (10 como mucho; 0: anulado por stopSound); fuera de lo que guarda save.asm
sdx_q            equ $97F1
ac_cnt           equ AV+18               ; personajes a dibujar este fotograma y su lista (clave = y, numero), ordenada por y: el de mas abajo se dibuja el ultimo
fl_xs            equ AV+19               ; linterna: celdas de ancho y de alto (lights a, b, 1); 0: sin linterna
fl_ys            equ AV+20
dk_ok            equ $97A0               ; ventana de la linterna: hay, primera columna y fila, y las de la ultima vez que se pinto
dk_c0            equ $97A1
dk_r0            equ $97A2
dk_pc            equ $97A3
dk_pr            equ $97A4
dk_row           equ $97A5
dk_src           equ $97A6
dk_dst           equ $97A8
ACSIG           equ $DE00               ; cache de sprites de los actores (en el bloque de atributos: sitio libre): por actor 6 bytes (firma, primer sprite, cuantos, fotograma), luego las variables
ac_stamp        equ ACSIG+150           ; palabra: numero de fotograma
ac_ent          equ ACSIG+152           ; palabra
ac_sg           equ ACSIG+154           ; palabra
ac_n0           equ ACSIG+156
AL               equ $97B0               ; hasta 2 x NACTORS bytes
sdx_left         equ AV+12               ; fotogramas que le quedan al que suena (65535: sin fin)                ; desplazamiento en pixeles de la celda dentro de su tira
ac_id           equ OVL_VARS+30         ; numero del actor que se dibuja
ac_pos           equ AV+24               ; posicion (cx | cy << 4) de la celda que se dibuja
UI_SIF           equ OVL_VARS+27         ; interfaz, cursor y VAR_CURSORSTATE guardados por cutscene()
UI_SCUR          equ OVL_VARS+28
UI_SV21          equ AV+22               ; palabra (no puede ir en OVL_VARS+29: pisaba ac_id)
NAMEOV          equ $8960               ; nombres de objeto cambiados por setObjectName: NNAMES entradas de NM_SIZE bytes (objeto, texto + 0)
NNAMES          equ 8
NM_SIZE         equ 26
ACTNAME         equ NAMEOV+NNAMES*NM_SIZE ; nombre de cada actor (actorOps 3): pagina del script (0: sin nombre) y direccion de la cadena en el
                                          ; script, que sigue en su pagina; NACTORS x 3
MS_BUF          equ $8831               ; raton (mouse.asm): lectura del puerto de la FPGA (8 bytes: x, y, botones, rueda, rawx, rawy, seq, estado)
MS_LX           equ $8839               ; ultima posicion leida (el teclado puede mover el cursor mientras el raton esta quieto)
MS_LY           equ $883A
ac_wb           equ $DC80           ; palabra: ventana de campos del sprite que se escribe (2101 si es normal; la entrada si es extra)
ac_xd           equ SPRX+30           ; XD_MARK: se han usado sprites extra, que pisan las variables del sistema del ZX81 ($4000-$41FF); al salir, reset
XD_MARK         equ $5A
SPRX            equ $4000               ; entradas de los sprites extra (POKE 2129 = 2 -> bloque $4000; entrada j = SPRX + 32 * j)
ac_pm           equ $94EA               ; 16 bytes: la paleta del actor que se dibuja, de codigo Chroma a codigo Chroma (ac_mkpal); dentro de lo libre entre AC_LC y BACKBUF
ac_pf           equ $94FA               ; 0: el actor lleva la paleta de identidad (no hay que remapear los colores de sus celdas)
AC_MAX          equ 78                  ; ranuras de sprite de los personajes: 63 normales (el 63 es el cursor) y 15 extra (entradas 0 y 2-15)
AC_OVF          equ $9490           ; NACTORS bytes: el fotograma de overlay de cada actor (0: ninguno): el ultimo que no es caminar, parado, inicio ni hablar
AC_LF           equ $94B0           ; NACTORS bytes: el fotograma (ix+10) de cada actor la ultima vez que se miro
AC_LC           equ $94D0           ; NACTORS bytes: su traje la ultima vez
; ac_wb: $DC80, en el bloque de atributos (sitio libre tras HR_LATT = $DC00 + 128; hr_clear lo pone a cero en cada sala, no importa). AC_OVF, AC_LF y AC_LC:
; entre INVSL y BACKBUF ($9484-$94FF, libre): van dentro de lo que guarda save.asm (SV_LEN_I) y no los borra hr_clear. ac_xd: el byte +30 de la entrada 0 de los
; sprites extra (la FPGA no lo mira; no lo toca hr_clear)
