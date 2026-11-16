; vm.asm: el nucleo de la VM v3 con sus tablas, para el arnes del PC (test/test_vm.cpp, test/build_test.sh).
; Mismo mapa que el programa de la placa: codigo desde $4200 (tiene que acabar antes de $8000), tablas desde $8000 (son datos;
; por encima de $8000 la ULA del ZX81 mete NOPs en la captura de instrucciones) y el estado de la VM en el bloque 7.
; El overlay B (ovlb.asm) se monta despues con vm.sym y el arnes lo pone en la pagina fisica 49.
; Ensamblar: pasmo vm.asm vm.bin vm.sym   (antes: python ../TOOLS/gen_vmtables3.py, que escribe tables3.inc y vars_v3.inc)

ENTRY_POINT     equ vm_init             ; (en la placa, el arranque del programa)
OVLA_PG         equ 0                   ; lo que hay en el bloque 0 fuera del overlay B (en la placa, el overlay A: pagina 50)
OVB_EXPR        equ 0                   ; entradas del overlay B (ovlb.asm)
OVB_OP          equ 3
OVB_DD          equ 6                   ; displayDialog
OVB_STOPTALK    equ 9                   ; fase 5: entradas de B para C (ovlb.asm)
OVB_HIDE        equ 12
OVB_SHOWACT     equ 15
OVB_FOLLOW      equ 18
OVB_PUTACT      equ 21
OVB_VNAME       equ 24                  ; fase 7
OVC_OP          equ 0                   ; entradas del overlay C (ovlc.asm)
OVC_SENT        equ 3                   ; checkAndRunSentenceScript
OVC_START       equ 6                   ; startScene (C = sala)
OVC_ROOM        equ 9                   ; load_room_state (C = sala, B = 1: con cajas)
OVC_SENTADD     equ 12                  ; doSentence desde fuera (APIVERB, APIN, APIA)
OVC_MOVECAM     equ 15                  ; moveCamera (fase 5b)
OVD_WALK        equ 0                   ; entradas del overlay D (ovld.asm; fase 6): walkActors
OVD_ADJUST      equ 3                   ; adjustXYToBeInBox(IX; WKX, WKY) -> WKX, WKY, WKBOX
OVD_STARTWALK   equ 6                   ; startWalkActor(IX; WKX, WKY, WKDIR)
OVD_CALCMF      equ 9                   ; calcMovementFactor(_walkdata.next)
OVD_ACTORS      equ 12                  ; actores (fase 8: ovd_act.asm, solo en el programa)
PROGRAM         equ 0                   ; 1 en el programa de la placa (scumm.asm): lo mira ovld.asm

                org $4200
                include "vm_core.asm"
snd_tick:       ret                     ; el modelo en modo nucleo ("mock") no mueve VAR_MUSIC_TIMER; el programa (scumm.asm) lo simula
map_page_x:     add a,128               ; arnes: la pagina de datos v esta en la pagina fisica 128 + v (en la placa: dp_cache.inc)
                jp map_phys
code_end:
                IF $ > $8000
                defb CODIGO_POR_ENCIMA_DE_8000
                ENDIF
                org $8000
                include "tables3.inc"
tables_end:
