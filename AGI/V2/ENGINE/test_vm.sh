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
python ../TOOLS/gen_agitab.py agivm.asm agiobj.asm agiin.asm agipic.asm agitab.inc
python ../TOOLS/gen_sprtab.py sprtab.inc
pasmo agivm.asm agivm.bin agivm.sym
[ $(wc -c < agivm.bin) -le 11008 ] || { echo "agivm.bin pasa de VARS (\$6D00): $(wc -c < agivm.bin) bytes, maximo 11008"; exit 1; }
python ../TOOLS/gen_font.py font6.inc
cp agivm.sym agires.inc
pasmo agia.asm agia.bin agia.sym
pasmo agib.asm agib.bin agib.sym
pasmo agic.asm agic.bin agic.sym
pasmo agid.asm agid.bin agid.sym
pasmo agie.asm agie.bin agie.sym
[ $(wc -c < agie.bin) -le 4096 ] || { echo "agie.bin pasa de SPP (\$3000)"; exit 1; }
mkdir -p ../dump/$G
rm -rf ../dump/$G/log
python ../TOOLS/agi2log.py ../$G ../dump/$G/log > /dev/null
python ../TOOLS/agi_vm.py ../$G --quiet --cycles $N --script "$SCRIPT" --listpics ../dump/$G/pics.txt > /dev/null
python ../TOOLS/agi2hr.py ../$G ../dump/$G/log $(cat ../dump/$G/pics.txt) > /dev/null
python ../TOOLS/agi2spr.py ../$G ../dump/$G/log > /dev/null
python ../TOOLS/mkovl.py agia.bin ../dump/$G/log/DATA/OVERA.OVL
python ../TOOLS/mkovl.py agib.bin ../dump/$G/log/DATA/OVERB.OVL
python ../TOOLS/mkovl.py agic.bin ../dump/$G/log/DATA/OVERC.OVL
python ../TOOLS/mkovl.py agid.bin ../dump/$G/log/DATA/OVERD.OVL
python ../TOOLS/mkovl.py agie.bin ../dump/$G/log/DATA/OVERE.OVL
# con ZX81_MATRIX (teclas del ZX81 para el arnes) el Z80 no recibe eventos del guion: los genera su teclado; el modelo si
EVS="$SCRIPT"; [ -z "$ZX81_MATRIX" ] || EVS=""
python ../TOOLS/mkevents.py ../dump/$G/log/DATA/EVENTS.BIN $N "$EVS"
$E/build/test_scumm.exe agivm.bin agivm.sym ../dump/$G/log $N ../dump/test_vm.bin
python cmp_vm.py ../dump/test_vm.bin agivm.sym ../$G $N "$SCRIPT"
