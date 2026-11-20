#!/bin/sh
# 10g: captura del dialogo de guardar con el nombre a medio escribir (ev_nombre.txt: N teclas); uso: nombre.sh fotogramas salida.png (sin modelo: solo el Z80 y render_hr)
cd "$(dirname "$0")" || exit 1
N="${1:-1780}"; OUT="${2:-build/nombre.png}"
. ./spr_prep.inc
rm -f $SD/SAVE*.SAV $SD/DATA/SAVE*.SAV
export TS_POKE="$(python -I mk_events.py "${EV:-ev_nombre.txt}" prog/scumm.sym)"
TS_NOSTOP=1 TS_MODELDELTA=1 $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD "$N" $B/nombre_dump.bin | tail -1
python -I render_hr.py $B/nombre_dump.bin "$OUT" 3
