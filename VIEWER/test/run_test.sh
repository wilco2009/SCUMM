#!/bin/sh
# Ensambla el visor, compila el arnes y comprueba unas cuantas salas con caminatas de camara.
# Uso: run_test.sh [carpeta de los .LFL] [carpeta de los .GFX]
cd "$(dirname "$0")" || exit 1
LFL="${1:-../../V2/ManiacMansionDOS}"
GFX="${2:-../../preview/gfx}"
Z80SRC="${Z80SRC:-/c/ClaudeCode/Eightyone2/src}"
B=build
mkdir -p $B
(cd .. && pasmo roomview.asm test/$B/roomview.bin test/$B/roomview.sym) || exit 1
gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80.c" -o $B/z80.o || exit 1
gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80_ops.c" -o $B/z80_ops.o || exit 1
g++ -std=gnu++17 -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" test_view.cpp $B/z80.o $B/z80_ops.o -o $B/test_view.exe || exit 1
fail=0
run() {   # sala, guion
  ./$B/test_view.exe $B/roomview.bin "$GFX" $B/dump.bin "$1" "$2" || { fail=1; return; }
  GFX_DIR="$GFX" python -I check_view.py $B/dump.bin "$LFL" "$2" || fail=1
}
run 2 "-:3"
run 2 "P:100"
run 1 "P:500,O:130"
run 4 "P:20,O:3"
run 19 "P:400"
run 5 "-:3,P:600,O:90"
run 3 "P:333,O:111,P:20,O:7"
run 2 "N:5,-:3,P:40"
run 1 "B:5,-:3,P:30,O:5"
run 55 "N:5"
run 43 "P:50"
exit $fail
