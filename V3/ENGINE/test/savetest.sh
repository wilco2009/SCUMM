#!/bin/sh
# Fase 9: guardar y cargar en el programa completo (scumm.asm) contra el modelo (vmmodel3.py boot-core con "OPT guardar 1"). Cada prueba es un build_boot.sh con su fichero de sucesos:
#   ev_save.txt   guardar en el 300 y cargar en el 500 (DBG_SAVE: entre fotogramas)                         build_boot.sh 700
#   ev_save2.txt  guardar en el 400 y cargar en el 700 (cruza salas; check_hr.py despues)                   build_boot.sh 900
#   ev_save3.txt  el script sintetico 199 (synth_save.hex: guardar, cambiar una variable, cargar) con el opcode saveLoadGame dentro de un script (SCUMM_SYNTH)   build_boot.sh 400
#   ev_f5.txt     guardar en el 1100 y abrir el dialogo de Indy3 con la tecla 319 (F5): la sala 14, los nombres de las partidas (saveLoadVars 2)   build_boot.sh 1500
#   ev_f5hw.txt   la tecla F5 con SHIFT + S por la matriz del teclado (ZX81_MATRIX, EVF_NOPOKE=1)           build_boot.sh 1350
cd "$(dirname "$0")" || exit 1
G="../../Indy Last Crusade"
F="grep -v ^residente"
echo "== guardar 300 / cargar 500";  rm -f build/sdboot/SAVE*.SAV; sh build_boot.sh 700 "$G" ev_save.txt | $F | tail -3
echo "== cruzando salas (400 / 700)"; sh build_boot.sh 900 "$G" ev_save2.txt | $F | tail -3; python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx | tail -1
echo "== opcode en un script (sintetico 199)"; SCUMM_SYNTH="$(pwd)/synth_save.hex" sh build_boot.sh 400 "$G" ev_save3.txt | $F | tail -3
echo "== dialogo F5 con una partida guardada"; rm -f build/sdboot/SAVE*.SAV; sh build_boot.sh 1500 "$G" ev_f5.txt | $F | tail -3; python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx | tail -1
echo "== SHIFT + S por la matriz"; EVF_NOPOKE=1 ZX81_MATRIX="1300:SHIFT+S,1310:" sh build_boot.sh 1350 "$G" ev_f5hw.txt | $F | tail -3
echo "== cargar con el OK del dialogo (10a: SAVE, nombre, OK; LOAD, fila, OK)"; rm -f build/sdboot/SAVE*.SAV; sh build_boot.sh 2600 "$G" ev_f5j.txt | $F | tail -3
