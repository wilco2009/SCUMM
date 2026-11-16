; aq_vars.inc - variables de los actores (fase 8; las usa ovd_act.asm, que las lee de scumm.sym). ACV (vm_input.asm) = bloque 7, detras de IN_END
; ---- memoria (bloque 7, tras IN_END; las pone a 0 scumm.asm: aq_init)
AL              equ ACV                 ; 13 x 2: (y, actor) ordenado por y
ACSIG           equ ACV+26              ; 13 x 6: firma (2), primer sprite, cuantos, marca (2)
ACCNT           equ ACV+104             ; 13 x 2: ultimo fotograma pedido, contador de poses
ACVV            equ ACV+130
aq_cam          equ ACVV+0              ; palabra: camara del hardware en pixeles (la de los sprites)
aq_n            equ ACVV+2              ; sprites usados hasta ahora
aq_cnt          equ ACVV+3
aq_id           equ ACVV+4
aq_stamp        equ ACVV+5              ; palabra
aq_ent          equ ACVV+7              ; palabra
aq_sg           equ ACVV+9              ; palabra
aq_n0           equ ACVV+11
aq_used         equ ACVV+12             ; sprites usados el fotograma anterior
aq_hold         equ ACVV+13             ; fotogramas que los actores siguen ocultos tras cambiar de sala
aq_cost         equ ACVV+14
aq_dir          equ ACVV+15
aq_anim         equ ACVV+16             ; palabra
aq_cpage        equ ACVV+18
aq_blob         equ ACVV+19             ; palabra
aq_x            equ ACVV+21             ; palabra: x de pantalla del origen del fotograma
aq_ry           equ ACVV+23             ; palabra: fila de la SALA de su primera linea
aq_cx           equ ACVV+25             ; palabra
aq_cy           equ ACVV+27
aq_nx           equ ACVV+28             ; palabra
aq_cp           equ ACVV+30             ; palabra
aq_fl           equ ACVV+62
aq_pos          equ ACVV+32
aq_fr           equ ACVV+33             ; palabra: el fotograma (direccion en la ventana)
aq_mk           equ ACVV+35             ; 1: se aplica la mascara de la sala
aq_mpg          equ ACVV+36
aq_mbl          equ ACVV+37             ; palabra
aq_s0           equ ACVV+39             ; primera tira de la sala (8 pixeles) de la ventana
aq_rh           equ ACVV+40             ; filas de la ventana (alto en celdas * 8)
aq_ns           equ ACVV+41             ; tiras decodificadas (ancho en celdas + 2)
aq_sh           equ ACVV+42             ; pixeles de desplazamiento (x & 7)
aq_ce           equ ACVV+43             ; 3 bytes: entrada de COSTDIR
aq_dp           equ ACVV+46             ; palabra: puntero de los tramos
aq_dd           equ ACVV+48             ; palabra: destino (tira k de MKBUF)
aq_dr           equ ACVV+50             ; palabra: fila (con signo) de la ventana por la que va el decodificador
aq_dv           equ ACVV+52             ; valor del tramo
aq_mt           equ ACVV+53             ; 8 bytes: la mascara de la celda
aq_k            equ ACVV+61             ; tira que se decodifica
MKBUF           equ ACVV+64             ; 8 tiras de 64 filas
AC_ACTOR_END    equ MKBUF+512
AC_MAXSPR       equ 63                  ; el sprite 63 es el cursor
AC_YMIN         equ HR_TOP              ; lineas de pantalla en las que se ve la sala: [16, 144)
AC_YMAX         equ HR_TOP+128
; fase 8 (sprites extra): detras de MKBUF. ASEL: por actor de la lista (indice 0 = el de mas atras) lo que eligio aq_sel: fotograma (2), pagina del traje, sprites, modo (0 normales,
; 1 extra, 2 no se dibuja); las variables (AC2V, 16 B) las pone a 0 aq_init
AC2             equ MKBUF+512
ASEL            equ AC2                 ; 13 x 8: fotograma (2), blob (2), pagina, sprites, modo (+6), 1 libre
AC2V            equ AC2+104
aq_xn           equ AC2V+0              ; sprites extra usados este fotograma (= POKE 2131)
aq_xm           equ AC2V+1              ; 1: lo que se dibuja ahora va a los extra
aq_sp           equ AC2V+2              ; palabra: donde van la forma, la mascara y los colores del sprite que se escribe (los registros 2113, 2121 y 2105, o su entrada extra)
aq_sm           equ AC2V+4
aq_sc           equ AC2V+6
aq_tot          equ AC2V+8              ; sprites normales y extra repartidos en la pasada 1
aq_tx           equ AC2V+9
aq_li           equ AC2V+10             ; indice en la lista
aq_ovf          equ AC2V+11             ; 1: ya hubo un actor que no cabio en los normales: los que van mas atras van a los extra
AC2_END         equ AC2V+16
AC_XMAX         equ 32                  ; sprites extra como mucho: con 64 normales, 32 extra y 12 sprites de formato A cargados por linea, los pasos de la FPGA (2 + 64 + 32 + 6 * 12 = 170) caben en el limite de 174
                IF AC2_END > ROOMPAL
                defb LAS_VARIABLES_DE_LOS_ACTORES_PISAN_LA_PALETA
                ENDIF
