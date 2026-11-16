#!/bin/sh
# Fase 5b: el PROGRAMA COMPLETO (scumm.asm) en el arnes de PC (test_scumm.cpp) arranca el juego (script 1) y se compara, fotograma a fotograma, el resumen D de CoreVM
# (vmmodel3.py boot-core: INIT, proteccion saltada, sonido "timed", SCRIPT 1 y BOOT n) con el del Z80. Ademas deja el volcado de la pantalla para check_hr.py.
# Uso: build_boot.sh [fotogramas] [carpeta de los .LFL] [fichero de sucesos de entrada (fase 7): lineas "fotograma tipo [a b]"; ver mk_events.py]
cd "$(dirname "$0")" || exit 1
N="${1:-1500}"
GAME="${2:-../../Indy Last Crusade}"
EVF="$3"
Z80SRC="${Z80SRC:-/c/ClaudeCode/Eightyone2/src}"
B=build
SD=$B/sdboot
mkdir -p $SD/DATA
sh ../build_scumm.sh || exit 1
python mk_digest_boot.py > /dev/null || exit 1
if [ ! -f $B/z80.o ]; then
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80.c" -o $B/z80.o || exit 1
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80_ops.c" -o $B/z80_ops.o || exit 1
fi
g++ -std=gnu++17 -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" test_scumm.cpp $B/z80.o $B/z80_ops.o -o $B/test_scumm.exe || exit 1
python -I ../../TOOLS/pack_data3.py "$GAME" $SD/DATA/DATA.BIN --game ../../games/indy3.cfg --costumes ../../preview_hr --sounds ../../preview_hr/snd > /dev/null || exit 1
[ -f $SD/DATA/ROOM01.GFX ] || cp ../../preview_hr/gfx/*.GFX $SD/DATA/
cp prog/ovlb.bin $SD/DATA/OVLB.BIN; cp prog/ovlc.bin $SD/DATA/OVLC.BIN; cp prog/ovld.bin $SD/DATA/OVLD.BIN
python -I ../../TOOLS/vmmodel3.py "$GAME" boot-core $B "$N" $EVF || exit 1
[ -n "$EVF" ] && [ -z "$EVF_NOPOKE" ] && export TS_POKE="$(python -I mk_events.py "$EVF" prog/scumm.sym)"
TS_NOSTOP=1 TS_MODELDELTA=1 TS_DIGEST=$B/boot_actual.txt $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD "$N" $B/boot_dump.bin > $B/boot_out.txt || exit 1
grep -v "^SND " $B/boot_out.txt | tail -4
grep "^SND " $B/boot_out.txt > $B/boot_snd_actual.txt
python -I compare_boot.py $B/boot_expected.txt $B/boot_actual.txt 3
# fase 8: las ordenes de sonido al MCU (STOP, LOOP, PLAY con el fotograma): iguales a las del modelo
tr -d "\015" < $B/boot_snd_expected.txt > $B/boot_snd_e.txt; tr -d "\015" < $B/boot_snd_actual.txt > $B/boot_snd_a.txt
if diff -q $B/boot_snd_e.txt $B/boot_snd_a.txt > /dev/null; then echo "ordenes de sonido al MCU: $(wc -l < $B/boot_snd_actual.txt) iguales"; else echo "ordenes de sonido al MCU: DISTINTAS"; diff $B/boot_snd_e.txt $B/boot_snd_a.txt | head -10; fi
