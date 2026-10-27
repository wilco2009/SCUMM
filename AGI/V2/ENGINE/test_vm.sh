#!/bin/sh
# Compara el nucleo Z80 (agivm.asm) con el modelo de Python (TOOLS/agi_vm.py) en el arnes de PC de SCUMM:
#   sh test_vm.sh [JUEGO] [CICLOS] ["guion de eventos"]       (por defecto SQ1 y 100; necesita V2/ENGINE/test/build/test_scumm.exe en SCUMM)
set -e
cd "$(dirname "$0")"
G=${1:-SQ1}
N=${2:-100}
SCRIPT=${3:-}
E=../../../V2/ENGINE/test
[ -d ../$G ] || { echo "sin datos de $G: prueba omitida"; exit 0; }
python ../TOOLS/gen_agitab.py agivm.asm agiobj.asm agiin.asm agitab.inc
pasmo agivm.asm agivm.bin agivm.sym
mkdir -p ../dump/$G
python ../TOOLS/agi2log.py ../$G ../dump/$G/log > /dev/null
python ../TOOLS/mkevents.py ../dump/$G/log/EVENTS.BIN $N "$SCRIPT"
$E/build/test_scumm.exe agivm.bin agivm.sym ../dump/$G/log $N ../dump/test_vm.bin
AGI_NOPIC=1 python cmp_vm.py ../dump/test_vm.bin agivm.sym ../$G $N "$SCRIPT"
