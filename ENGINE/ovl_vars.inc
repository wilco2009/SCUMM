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
INV_ROW0        equ 20                  ; filas 20-21: 4 objetos (2 columnas: 0 y 17) y las flechas (UP, DN) en la columna 15
VERB_ROW0       equ 17
SENT_ROW        equ 16
