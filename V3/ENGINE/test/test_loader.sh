#!/bin/sh
# Comprueba loader.asm: genera DATA.BIN con el mismo reparto en paginas que world.bin, deja que el Z80 lo cargue
# desde un MCU simulado y ejecuta los escenarios del nucleo con los datos cargados por el. Despues de build_test.sh.
cd "$(dirname "$0")" || exit 1
GAME="${1:-../../ManiacMansionDOS}"
B=build
TOOLS=../../TOOLS
python -I $TOOLS/pack_data.py "$GAME" $B/DATA.BIN --game ../../games/maniac.cfg --first-page 8 --all || exit 1
(cd .. && pasmo loadtest.asm test/$B/loadtest.bin test/$B/loadtest.sym) || exit 1
./$B/test_vm.exe $B/loadtest.bin $B/loadtest.sym $B/world.bin $B/scenarios.txt $B/actual_data.txt --data $B/DATA.BIN | head -3
python -I compare_traces.py $B/expected.txt $B/actual_data.txt 10
