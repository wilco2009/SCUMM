#!/bin/sh
# Comprobacion de la ruta grafica 160w contra la referencia de ScummVM (TOOLS/refcheck.py + refscummvm.py). Pasarla tras cada parche, junto a runall.sh.
#   sh refcheck.sh [JUEGO ...]        (por defecto los 5; ~3-6 min; en paralelo, un proceso por juego)
# Sale con 1 si algun juego da DIFER. No usa el Z80: modelo == referencia (aqui) y Z80 == modelo (runall.sh).
cd "$(dirname "$0")/../TOOLS"
G="${*:-SQ2 SQ1 KQ1 KQ2 PQ1}"
for g in $G; do
  python refcheck.py $g --step 32 --hw > ../dump/refcheck_$g.txt 2>&1 &
done
wait
RC=0
for g in $G; do
  echo "== $g: $(tail -1 ../dump/refcheck_$g.txt)"
  grep -q "^DIFER" ../dump/refcheck_$g.txt && { grep "^DIFER" ../dump/refcheck_$g.txt | head -5; RC=1; }
done
exit $RC
