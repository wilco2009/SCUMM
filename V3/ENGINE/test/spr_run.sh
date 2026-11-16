#!/bin/sh
# Fase 8: sprites de los actores. El programa completo en el arnes de PC (sin comparar con el modelo: el delta es el del arnes) con volcados en los fotogramas
# dados y check_spr.py (sprites3.py) en cada uno. Uso: spr_run.sh fotogramas "f1,f2,..." [fichero de sucesos de entrada] ; TS_POKE se respeta (poner actores a mano)
cd "$(dirname "$0")" || exit 1
N="${1:-800}"
DUMPS="$2"
. ./spr_prep.inc
rm -f $B/spr_dump.bin.*
[ -n "$3" ] && export TS_POKE="$(python -I mk_events.py "$3" prog/scumm.sym)${TS_POKE:+,$TS_POKE}"
TS_NOSTOP=1 TS_DUMPS="$DUMPS" $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD "$N" $B/spr_dump.bin | tail -3
bad=0
for f in $(echo "$DUMPS" | tr ',' ' '); do
  python -I check_spr.py $B/spr_dump.bin.$f prog/scumm.sym $SD/DATA/DATA.BIN | tail -8 || bad=1
done
exit $bad
