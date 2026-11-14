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

                org $4200
                include "vm_core.asm"
map_page_x:     add a,128               ; arnes: la pagina de datos v esta en la pagina fisica 128 + v (en la placa: dp_cache.inc)
                jp map_phys
code_end:
                IF $ > $8000
                defb CODIGO_POR_ENCIMA_DE_8000
                ENDIF
                org $8000
                include "tables3.inc"
tables_end:
