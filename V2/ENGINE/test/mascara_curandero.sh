#!/bin/sh
# Zak, sala 151 (pseudo-sala de la 38): el curandero (traje 21) lleva la mascara como fotograma de overlay 6 (miembro 7 y la cabeza, miembro 3, la misma
# que la de inicio) y debe seguir llevandola tras andar hacia la izquierda o la derecha (antes se perdia: el inicio nombra el miembro 3 y se daba por quitada).
# Se le pone el traje 21 a Zak (actor 1) mirando a la derecha, con el overlay 6; anda y se para: AC_OVF del actor 1 debe acabar en 06 (00 = perdida).
# Necesita un DATA.BIN de depuracion en la sala 38: python ../TOOLS/pack_data.py "../Zak McKracken" $D/DATA.BIN --game ../games/zak.cfg --sounds ../preview_zak_hr/snd --debug-room 38
# Uso: sh test/mascara_curandero.sh DIRECTORIO_SD (con ese DATA.BIN, los .GFX y SND)
cd "$(dirname "$0")/.." || exit 1
D=${1:?directorio de la SD}
V=$(grep -i "^AC_OVF" scumm.sym | sed 's/.*EQU 0*\([0-9A-F]*\)H/\1/'); V=$(printf '%X' $((0x$V + 1)))
O=$(TS_WATCH=$V-$V,100 TS_POKE=100:EF31:64,100:EF35:15,100:EF36:5A,100:EF37:00,100:EF3A:06,110:EF3A:00,130:EF3A:01 test/build/test_scumm.exe scumm.bin scumm.sym $D 220 /tmp/mascara.bin "-:150" 2>&1 | grep "^W f=" | tail -1)
echo "$O"
case "$O" in *"]=06") echo OK;; *) echo "FALLO: la mascara se pierde al andar"; exit 1;; esac
