; GENERADO A MANO: entradas del overlay (tabla de saltos al principio de la pagina mapeada en el bloque 0)
OVL2_PAGE       equ 51                  ; pagina fisica del overlay 2 (snd.asm y save.asm; overlay2.asm): solo se mapea en el bloque 0 mientras se ejecuta; la 50 vuelve al salir
OV2_COPY        equ $0C00               ; bytes del overlay 2 que copia ov_init a su pagina (tope del tamano de overlay2.bin)
SV_FIN          equ $9797               ; 1: una carga de partida acabo bien y falta restaurar la sala y el script (ho_saveload, overlay.asm)
SV_PON          equ $9796               ; hv_pon leido de la partida: gf_load_room lo pone a 0, ho_saveload (overlay 1) lo devuelve
OVL_PAGE        equ 50                  ; pagina fisica del overlay (la 63 es del depurador: no usar)
OVL_UI_INIT     equ 0
OVL_UI_UPDATE   equ 3
OVL_UI_CLICK    equ 6
OVL_CAM_UPDATE  equ 9
OVL_ACTORS_UPDATE equ 12
OVL_HOST_OPS    equ 15
OVL_OV_INIT     equ 18
OVL_SND_EVENT   equ 21
OVL_SND_TICK    equ 24
OVL_DARK        equ 27
OVL_HRUI        equ 30
OVL_DKMASK      equ 33
OVL_MOUSE       equ 36                  ; raton Bluetooth (mouse.asm): A = bit 4 boton izquierdo, bit 5 derecho (0 si no hay raton)
OVL_ERR        equ 39                  ; error fatal (ov_err): se escribe y espera una tecla
OVL_DRAWOBJ    equ 42                  ; drawObject (ov_drawobj, overlay.asm)
OVL_CMNAME     equ 45                  ; codigos de texto 5 y 6 (ui_cmname, ui.asm)
OVL_NOSTART    equ 48                  ; startScript: Z si el perfil prohibe arrancar el script E en esta sala (ui_nostart)
OVL_AFPX      equ 51                  ; getActorFromPos: carry si la franja x (DE, en unidades de 8 px) cae en las que dibuja el actor IX / C (ov_afpx, overlay.asm)
OVL_SETFRAME   equ 54                  ; start_anim: guarda el fotograma C del actor IX y anota su overlay (ac_setfr, actors.asm)
TXSPD          equ $9798               ; velocidad del texto (A9, teclas + y -): 0-9 de ScummVM (_defaultTextSpeed) con XOR 6, asi 0 = 6 (valor por omision, y el de las partidas antiguas)
