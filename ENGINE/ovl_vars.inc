; GENERADO A MANO: variables del overlay y de la interfaz (RAM; el overlay esta en una pagina de solo lectura)
OVL_VARS        equ $CE30
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
UI_DIRTY        equ $CD00               ; bit 0 verbos, bit 1 frase, bit 2 inventario
UI_IFACE        equ $CD01               ; bits 5-7 del estado de usuario: frase, inventario, verbos
UI_CURSOR       equ $CD02               ; 1: el cursor esta activo
UI_PREV         equ $CD04               ; copia de VAR_SENTENCE_VERB, OBJECT1, OBJECT2 y PREPOSITION (4 palabras)
UI_NAME         equ $CD0C               ; nombre de objeto convertido (hasta 31 + 0)
UI_PEGO         equ $CD2D               ; protagonista cuyo inventario esta dibujado
UI_INVO         equ $CD2E               ; primer objeto del inventario que se ve (de 2 en 2)
UI_TMP          equ $CD2F
UI_LIM          equ $CD30
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
sdx_left         equ AV+12               ; fotogramas que le quedan al que suena (65535: sin fin)                ; desplazamiento en pixeles de la celda dentro de su tira
ac_id           equ OVL_VARS+30         ; numero del actor que se dibuja
UI_SIF           equ OVL_VARS+27         ; interfaz, cursor y VAR_CURSORSTATE guardados por cutscene()
UI_SCUR          equ OVL_VARS+28
UI_SV21          equ OVL_VARS+29
NAMEOV          equ $CE60               ; nombres de objeto cambiados por setObjectName: NNAMES entradas de NM_SIZE bytes (objeto, texto + 0)
NNAMES          equ 8
NM_SIZE         equ 26
ACTNAME         equ NAMEOV+NNAMES*NM_SIZE ; nombre de cada actor (actorOps 3): pagina del script (0: sin nombre) y direccion de la cadena en el
                                          ; script, que sigue en su pagina; NACTORS x 3
