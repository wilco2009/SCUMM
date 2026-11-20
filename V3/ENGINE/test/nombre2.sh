#!/bin/sh
# 10g: como nombre.sh pero sin recompilar (para lanzar varias a la vez): nombre2.sh eventos fotogramas salida.png
cd "$(dirname "$0")" || exit 1
EV="$1"; N="$2"; OUT="$3"
B=build; SD=$B/sdboot
export TS_POKE="$(python -I mk_events.py "$EV" prog/scumm.sym)"
TS_NOSTOP=1 TS_MODELDELTA=1 $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD "$N" $B/dump_$$.bin | tail -1
python -I render_hr.py $B/dump_$$.bin "$OUT" 3
rm -f $B/dump_$$.bin
