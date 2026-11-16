#!/bin/sh
# fase 8: dos objetos de la sala cambian de estado por fotograma (salas 20 y 28) y la sala se vuelve a componer: check_hr.py en varios fotogramas y T por vuelta.
# Uso: objflip.sh sala
cd "$(dirname "$0")" || exit 1
R="${1:-20}"
. ./spr_prep.inc
rm -f $B/spr_dump.bin.*
export TS_POKE="$(python -I objflip.py prog/scumm.sym $SD/DATA/DATA.BIN $R 30 150 1)"
TS_NOSTOP=1 TS_DUMPS="40,70,100,130,160" TS_T=1 TS_PROF=30-150 $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD 160 $B/spr_dump.bin | grep -v "^SND\|^  \|^las 8" | tail -6
for f in 40 70 100 130 160; do echo "fotograma $f:"; python -I check_hr.py $B/spr_dump.bin.$f prog/scumm.sym ../../preview_hr/gfx | tail -2; done
