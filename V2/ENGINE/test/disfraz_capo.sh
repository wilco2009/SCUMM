#!/bin/sh
# Zak, sala secreta (16): el caponiano (actor 7, traje 28) se pone el sombrero y las gafas (fotograma de overlay 6, miembro 7) y habla justo despues (printEgo): el overlay no se pierde
# (AC_OVF del actor 7 acaba en 06 tras ponerselo, en el fotograma ~425; antes del arreglo de start_anim -> ac_setfr se quedaba en 00 hasta que volvia a la sala 4).
# Necesita un DATA.BIN de este empaquetador en una copia de la SD de pruebas (con los .GFX y SND de test/build/sdzak):
#   python test/pack_disfraz.py "../Zak McKracken" $D/DATA.BIN --game ../games/zak.cfg --sounds ../preview_zak_hr/snd --debug-room 4     (desde SCUMM/V2)
# Uso: sh test/disfraz_capo.sh DIRECTORIO_SD
cd "$(dirname "$0")/.." || exit 1
D=${1:?directorio de la SD}
V=$(grep -i "^AC_OVF" scumm.sym | sed 's/.*EQU 0*\([0-9A-F]*\)H/\1/'); V=$(printf '%X' $((0x$V + 7)))
O=$(TS_WATCH=$V-$V,400 test/build/test_scumm.exe scumm.bin scumm.sym $D 560 /tmp/disfraz.bin "-:20" 2>&1 | grep "^W f=" | tail -1)
echo "$O"
case "$O" in *"]=06") echo OK;; *) echo "FALLO: el disfraz se pierde"; exit 1;; esac
