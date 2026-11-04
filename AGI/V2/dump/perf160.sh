#!/bin/sh
# Perfil de la build de produccion 160w (GFX4=1, TESTS=0, ncyc=0 = modo real) en el arnes:
#   sh perf160.sh JUEGO SALA X Y [TECLAS] [DESDE-HASTA] [CICLOS]    p. ej. sh perf160.sh SQ2 53 10 120 "12:8" 20-70 75
# Coloca al ego en (X,Y) en la sala y pulsa TECLAS (formato ZX81_MATRIX: 8 derecha, 5 izquierda, 6 abajo, 7 arriba; la misma tecla para). PERF_NOBUILD=1: no regenera datos.
# Salida: T-estados por ciclo (un ciclo = 5 tramas con v10=2; PERF_DIV=3 con v10=1, PQ1) y reparto por grupos (perf160.py). El arnes no modela la pantalla ni la memoria. La espera de pace lee el teclado: lo de "kbd" no es trabajo real.
cd "$(dirname "$0")/../ENGINE"
G=$1; R=$2; X=$3; Y=$4; K=${5:-}; P=${6:-20-70}; N=${7:-75}
export AGI_BOOT="room=$R,cyc=3,cmd=position:0:$X:$Y${PERF_BOOT:+,$PERF_BOOT}"
export GFX4=1 AGI_GFX4=1
if [ -z "$PERF_NOBUILD" ]; then
  sh test_vm.sh $G 6 "" > /dev/null 2>&1
fi
printf 'GFX4            equ 1\n' > gfx4.inc
printf 'TESTS           equ 0\n' > tests.inc
trap 'printf "GFX4            equ 0\n" > gfx4.inc; printf "TESTS           equ 0\n" > tests.inc' EXIT
pasmo agivm.asm agivm.bin agivm.sym
cp agivm.sym agires.inc
for o in a b c d e f; do pasmo agi$o.asm agi$o.bin agi$o.sym; O=$(echo $o | tr a-f A-F); python ../TOOLS/mkovl.py agi$o.bin ../dump/$G/log/DATA/OVER$O.OVL; done
python ../TOOLS/mkevents.py ../dump/$G/log/DATA/EVENTS.BIN 0 ""
ZX81_MATRIX="$K" TS_T=1 TS_PROF=$P TS_TOP=1000 TS_NOSTOP=1 ${PERF_EXE:-../../../V2/ENGINE/test/build/test_scumm.exe} agivm.bin agivm.sym ../dump/$G/log $N ../dump/perf160.bin 2>&1 > ../dump/perf160.out
python ../dump/perf160.py ../dump/perf160.out $(python -c "a,b='$P'.split('-');print((int(b)-int(a))/${PERF_DIV:-5})")
