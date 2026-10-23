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
                include "game_layout.inc"
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
ac_tk           equ AV+2                ; contador de la boca del personaje que habla
ac_sh           equ AV+1                ; desplazamiento en pixeles de la celda dentro de su tira
ac_id           equ OVL_VARS+30         ; numero del actor que se dibuja
UI_SIF           equ OVL_VARS+27         ; interfaz, cursor y VAR_CURSORSTATE guardados por cutscene()
UI_SCUR          equ OVL_VARS+28
UI_SV21          equ OVL_VARS+29
NAMEOV          equ $CE60               ; nombres de objeto cambiados por setObjectName: NNAMES entradas de NM_SIZE bytes (objeto, texto + 0)
NNAMES          equ 8
NM_SIZE         equ 26
ACTNAME         equ NAMEOV+NNAMES*NM_SIZE ; nombre de cada actor (actorOps 3): pagina del script (0: sin nombre) y direccion de la cadena en el
                                          ; script, que sigue en su pagina; NACTORS x 3
