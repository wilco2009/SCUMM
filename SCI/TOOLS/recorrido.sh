#!/bin/sh
# Recorre las salas de un juego por tandas (cada tanda arranca el juego de cero).
# Uso: sh recorrido.sh CARPETA NOMBRE TOTAL_SALAS [TANDA]
J=$1; N=$2; T=$3; K=${4:-6}
d=0
while [ $d -lt $T ]; do
  TOUR_DESDE=$d TOUR_N=$K TOUR_CICLOS=250 timeout 900 python -I -u analiza.py "$J" "${N}_$d" 0 andar+salas > ../medidas/${N}_$d.log 2>&1
  grep "ciclos, " ../medidas/${N}_$d.log | grep -o "error.*" | cut -c1-160
  d=$((d+K))
done
