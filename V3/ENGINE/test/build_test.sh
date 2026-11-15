#!/bin/sh
# Fase 3 (SCUMM/V3/PLAN.md): monta el nucleo v3 (vm.asm + ovlb.asm), compila el arnes (Z80 de EightyOne), genera DATA.BIN y los
# escenarios del nucleo con el modelo (vmmodel3.py scenarios-core: CoreVM), ejecuta el Z80 y compara las trazas.
# Uso: build_test.sh [carpeta de los .LFL] [semillas] [salas, p. ej. 1,15,20,28]     TS_VM=1: T por instruccion de script
cd "$(dirname "$0")" || exit 1
GAME="${1:-../../Indy Last Crusade}"
SEEDS="${2:-1}"
ROOMS="$3"
Z80SRC="${Z80SRC:-/c/ClaudeCode/Eightyone2/src}"
TOOLS=../../TOOLS
B=build
mkdir -p $B
python -I $TOOLS/gen_vmtables3.py > /dev/null || exit 1
rm -f $B/vm.bin $B/ovlb.bin $B/ovlc.bin $B/ovld.bin     # (si el ensamblado falla no se debe usar un binario viejo)
(cd .. && pasmo vm.asm test/$B/vm.bin test/$B/vm.sym) 2>&1 | grep -v WARNING
[ -s $B/vm.bin ] || exit 1
(cd .. && pasmo -I test/$B ovlb.asm test/$B/ovlb.bin test/$B/ovlb.sym) 2>&1 | grep -v WARNING
[ -s $B/ovlb.bin ] || exit 1
(cd .. && pasmo -I test/$B ovlc.asm test/$B/ovlc.bin test/$B/ovlc.sym) 2>&1 | grep -v WARNING
[ -s $B/ovlc.bin ] || exit 1
(cd .. && pasmo -I test/$B ovld.asm test/$B/ovld.bin test/$B/ovld.sym) 2>&1 | grep -v WARNING
[ -s $B/ovld.bin ] || exit 1
echo "residente (codigo): $(grep -i '^vm_init' $B/vm.sym | awk '{print $3}') - $(grep -i '^code_end' $B/vm.sym | awk '{print $3}');  tablas: hasta $(grep -i '^tables_end' $B/vm.sym | awk '{print $3}');  overlay B: $(stat -c %s $B/ovlb.bin) bytes (codigo hasta $(grep -i '^ovb_code_end' $B/ovlb.sym | awk '{print $3}'));  overlay C: $(stat -c %s $B/ovlc.bin) bytes (codigo hasta $(grep -i '^ovc_code_end' $B/ovlc.sym | awk '{print $3}'));  overlay D: $(stat -c %s $B/ovld.bin) bytes"
if [ ! -f $B/z80.o ]; then
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80.c" -o $B/z80.o || exit 1
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80_ops.c" -o $B/z80_ops.o || exit 1
fi
g++ -std=gnu++17 -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" test_vm.cpp $B/z80.o $B/z80_ops.o -o $B/test_vm.exe || exit 1
python -I $TOOLS/pack_data3.py "$GAME" $B/DATA.BIN > /dev/null || exit 1
python -I $TOOLS/vmmodel3.py "$GAME" scenarios-core $B "$SEEDS" $ROOMS || exit 1
./$B/test_vm.exe $B/vm.bin $B/vm.sym $B/ovlb.bin $B/DATA.BIN $B/scenarios.txt $B/actual.txt $B/ovlc.bin $B/ovld.bin || exit 1
python -I compare_traces.py $B/expected.txt $B/actual.txt 10
