; vm.asm: el nucleo con sus tablas (para las pruebas del PC). El programa de la placa (scumm.asm) incluye vm_core.asm y pone
; las tablas por encima de $8000: son datos, y el codigo no puede pasar de $7FFF (ver SCUMM/planning/scumm_etapa2.md).
ENTRY_POINT     equ $4215
ACTNAME         equ $8A30               ; (en el programa completo lo define ovl_vars.inc) nombres de actor: 25 x 3 bytes
map_page_x      equ map_phys
OVL_CMNAME      equ vm_ret              ; sin interfaz en el nucleo de pruebas: los codigos de texto 5 y 6 no dan nombre y el perfil no prohibe scripts
OVL_NOSTART     equ vm_nostart
                include "vm_core.asm"
                include "tables.inc"
                include "progdata.inc"

vm_ret:        ret
vm_nostart:    or 1
                ret

code_end:
