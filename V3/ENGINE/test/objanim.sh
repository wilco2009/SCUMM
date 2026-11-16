#!/bin/sh
# fase 8: objetos animados (salas 20 y 28 del castillo: el fondo es negro y se compone de objetos que cambian de estado). Carga la sala (DBG_ROOM), deja correr sus scripts y
# comprueba con check_hr.py (la sala con la lista de objetos que se dibujan) varios fotogramas; ademas el modelo y el Z80 tienen que dar el mismo resumen D.
# Uso: objanim.sh sala fotogramas "f1,f2,..."
cd "$(dirname "$0")" || exit 1
R="${1:-20}"; N="${2:-200}"; D="${3:-60,120,180}"
printf '5 room %s\n' "$R" > build/f8/ev_room.txt
export TS_DUMPS="$D"
sh build_boot.sh "$N" "../../Indy Last Crusade" build/f8/ev_room.txt | tail -4
for f in $(echo "$D" | tr ',' ' '); do
  echo "fotograma $f:"; python -I check_hr.py build/boot_dump.bin.$f prog/scumm.sym ../../preview_hr/gfx | tail -2
done
