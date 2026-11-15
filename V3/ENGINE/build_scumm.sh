#!/bin/sh
# Monta el programa completo de v3 (fase 5b): scumm.asm (con las tablas de tables3.inc) y los overlays B, C y D (que se ensamblan contra los simbolos del programa: los
# overlays hacen `include "vm.sym"`, asi que aqui vm.sym es el scumm.sym del programa). Salida en test/prog/: scumm.bin, scumm.sym, ovlb.bin, ovlc.bin, ovld.bin.
cd "$(dirname "$0")" || exit 1
B=test/prog
mkdir -p $B
python -I ../TOOLS/gen_vmtables3.py > /dev/null || exit 1
python -I ../TOOLS/gen_font3.py > /dev/null || exit 1
rm -f $B/scumm.bin $B/ovlb.bin $B/ovlc.bin $B/ovld.bin
pasmo scumm.asm $B/scumm.bin $B/scumm.sym 2>&1 | grep -v WARNING
[ -s $B/scumm.bin ] || exit 1
cp $B/scumm.sym $B/vm.sym
for o in b c d; do
  pasmo -I $B ovl$o.asm $B/ovl$o.bin $B/ovl$o.sym 2>&1 | grep -v WARNING
  [ -s $B/ovl$o.bin ] || exit 1
done
S=$B/scumm.sym
echo "residente (codigo): \$4200 - $(grep -i '^code_end' $S | awk '{print $3}');  tablas: hasta $(grep -i '^tables_end' $S | awk '{print $3}');  overlay B: $(stat -c %s $B/ovlb.bin) B (codigo hasta $(grep -i '^ovb_code_end' $B/ovlb.sym | awk '{print $3}'));  overlay C: $(stat -c %s $B/ovlc.bin) B (codigo hasta $(grep -i '^ovc_code_end' $B/ovlc.sym | awk '{print $3}'));  overlay D: $(stat -c %s $B/ovld.bin) B"
