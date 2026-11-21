#!/bin/sh
# Zak, sala 28 (base de Marte): Melissa (traje 3, escala 1/1) con el fotograma de overlay 8 (el casco: script 150) puesto debe llevar el casco tambien
# PARADA (el traje no lo lleva en su lista: no cabe en la pagina, va en las paginas de poses de caminar); antes solo lo llevaba al andar.
# Necesita un DATA.BIN de depuracion en la sala 28: python ../TOOLS/pack_data.py "../Zak McKracken" $D/DATA.BIN --game ../games/zak.cfg --sounds ../preview_zak_hr/snd --debug-room 28
# Uso: sh test/casco_melissa.sh DIRECTORIO_SD (con ese DATA.BIN, los .GFX y SND)
cd "$(dirname "$0")/.." || exit 1
D=${1:?directorio de la SD}
P=100:EF35:03,100:E838:00,100:E839:20,100:E83A:60,100:E83B:00,100:E83C:20,100:E83D:20,100:EF36:B4,100:EF37:00
run() { TS_POKE=$P,$1 timeout 300 test/build/test_scumm.exe scumm.bin scumm.sym $D $2 /tmp/casco_$3.bin "-:150" >/dev/null 2>&1; }
run 100:EF3A:01 220 nu        # parada, sin overlay
run 100:EF3A:08,110:EF3A:01 220 pa   # overlay 8 puesto y despues parada
python -I - /tmp/casco_nu.bin /tmp/casco_pa.bin <<'P'
import sys
a, b = (open(f, 'rb').read()[131072:131072 + 2048] for f in sys.argv[1:3])
print('parada sin casco / con casco: sprites distintos' if a != b else 'FALLO: parada con el overlay 8 se dibuja igual que sin el')
sys.exit(0 if a != b else 1)
P
