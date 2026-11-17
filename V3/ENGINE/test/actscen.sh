#!/bin/sh
# Fase 8: actores al azar en las salas dadas (mk_actscen.py): carga cada sala, pone de 1 a 6 actores con trajes, direcciones y fotogramas al azar y comprueba los
# sprites (check_spr.py) en cada escena. Uso: actscen.sh semilla "1,15,20,28" escenas_por_sala
cd "$(dirname "$0")" || exit 1
SEED="${1:-1}"; ROOMS="${2:-1,15,20,28}"; PER="${3:-6}"
. ./spr_prep.inc
rm -f $B/spr_dump.bin.*
python -I mk_actscen.py prog/scumm.sym $SD/DATA/DATA.BIN $SEED "$ROOMS" $PER > $B/scen.txt || exit 1
export TS_POKE="$(sed -n 1p $B/scen.txt)"
[ -z "${EXPECT_PC+x}" ] && export EXPECT_PC=1
DUMPS="$(sed -n 2p $B/scen.txt)"
N="$(sed -n 3p $B/scen.txt)"
TS_NOSTOP=1 TS_DUMPS="$DUMPS" $B/test_scumm.exe prog/scumm.bin prog/scumm.sym $SD "$N" $B/spr_dump.bin | tail -3
bad=0; tot=0; badn=0; skip=0
ACTS="$(sed -n 4p $B/scen.txt)"     # 10e: los actores que pone cada escena (los demas los mueven los scripts de la sala: sala 70, actores 8 y 10)
for f in $(echo "$DUMPS" | tr ',' ' '); do
  EA="$(echo "$ACTS" | cut -d';' -f$((tot+1)) | tr '.' ',')"
  r=$(EXPECT_ACT="$EA" python -I check_spr.py $B/spr_dump.bin.$f prog/scumm.sym $SD/DATA/DATA.BIN 2>&1)
  tot=$((tot+1))
  RR="$(echo "$r" | sed -n 's/^sala \([0-9]*\), camara.*/\1/p' | tail -1)"
  case ",$ROOMS," in *",$RR,"*) RR=;; esac
  if [ -n "$RR" ]; then echo "--- volcado $f: la sala cambio sola a $RR (scripts del juego, p. ej. el guardia de la sala 20: loadRoom \$84); escena no valida, no cuenta"; skip=$((skip+1)); continue; fi
  case "$r" in *"distintos 0"*) ;; *) badn=$((badn+1)); echo "--- volcado $f"; echo "$r" | tail -7;; esac
done
echo "escenas $tot, con diferencias $badn, no validas por cambio de sala $skip"
[ $badn -eq 0 ]
