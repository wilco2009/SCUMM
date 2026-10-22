#!/bin/sh
# Compila el nucleo (pasmo), el arnes (g++ con el Z80 de EightyOne), genera el mundo y los escenarios con el
# modelo de Python, ejecuta el Z80 y compara las trazas. Uso: build_test.sh [carpeta de los .LFL] [semillas]
cd "$(dirname "$0")" || exit 1
GAME="${1:-../../V2/ManiacMansionDOS}"
SEEDS="${2:-2}"
Z80SRC="${Z80SRC:-/c/ClaudeCode/Eightyone2/src}"
TOOLS=../../TOOLS
B=build
mkdir -p $B
python -I $TOOLS/gen_vmtables.py > /dev/null || exit 1
(cd .. && pasmo vm.asm test/$B/vm.bin test/$B/vm.sym) || exit 1
echo "nucleo: $(stat -c %s $B/vm.bin) bytes"
gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80.c" -o $B/z80.o || exit 1
gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80_ops.c" -o $B/z80_ops.o || exit 1
g++ -std=gnu++17 -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" test_vm.cpp $B/z80.o $B/z80_ops.o -o $B/test_vm.exe || exit 1
python -I $TOOLS/vmmodel.py "$GAME" pack $B || exit 1
python -I $TOOLS/vmmodel.py "$GAME" scenarios $B "$SEEDS" || exit 1
./$B/test_vm.exe $B/vm.bin $B/vm.sym $B/world.bin $B/scenarios.txt $B/actual.txt || exit 1
python -I compare_traces.py $B/expected.txt $B/actual.txt 10
