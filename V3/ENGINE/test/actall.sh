#!/bin/sh
# fase 8: escenas de actores al azar, cada sala en su propia ejecucion (las transiciones entre salas a lo bruto dan E_BADROOM en los scripts, ajeno a los actores)
# Uso: actall.sh semillas "salas" escenas_por_sala
cd "$(dirname "$0")" || exit 1
SEEDS="${1:-1 2}"; ROOMS="${2:-1 15 20 28}"; PER="${3:-12}"
tot=0; bad=0
for s in $SEEDS; do for r in $ROOMS; do
  out=$(sh actscen.sh $s $r $PER 2>&1)
  line=$(echo "$out" | grep "^escenas")
  echo "semilla $s sala $r: $line"
  case "$line" in *"diferencias 0") ;; *) bad=$((bad+1)); echo "$out" | head -30;; esac
done; done
[ $bad -eq 0 ]
