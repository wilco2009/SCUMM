; vm.asm: el nucleo con sus tablas (para las pruebas del PC). El programa de la placa (scumm.asm) incluye vm_core.asm y pone
; las tablas por encima de $8000: son datos, y el codigo no puede pasar de $7FFF (ver SCUMM/planning/scumm_etapa2.md).
ENTRY_POINT     equ $4215
                include "vm_core.asm"
                include "tables.inc"
                include "progdata.inc"

code_end:
