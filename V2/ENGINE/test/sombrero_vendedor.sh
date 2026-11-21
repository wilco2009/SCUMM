#!/bin/sh
# Zak, sala 4: el vendedor (actor 7) lleva el sombrero (fotograma de overlay 6, miembro 7 del traje 28), camina y se para: el sombrero debe seguir (AC_OVF del actor 7 = 06).
# Necesita un DATA.BIN de depuracion en la sala 4 (con los .GFX y SND de test/build/sdzak): python ../TOOLS/pack_data.py "../Zak McKracken" $D/DATA.BIN --game ../games/zak.cfg --sounds ../preview_zak_hr/snd --debug-room 4
# Uso: sh test/sombrero_vendedor.sh DIRECTORIO_SD
cd "$(dirname "$0")/.." || exit 1
D=${1:?directorio de la SD}
V=$(grep -i "^AC_OVF" scumm.sym | sed 's/.*EQU 0*\([0-9A-F]*\)H/\1/'); V=$(printf '%X' $((0x$V + 7)))
O=$(TS_WATCH=$V-$V,100 TS_POKE=150:F05A:6,170:F05A:0,200:F05A:1 test/build/test_scumm.exe scumm.bin scumm.sym $D 260 /tmp/sombrero.bin "-:20" 2>&1 | grep "^W f=" | tail -1)
echo "$O"
case "$O" in *"]=06") echo OK;; *) echo FALLO: el sombrero se pierde; exit 1;; esac
