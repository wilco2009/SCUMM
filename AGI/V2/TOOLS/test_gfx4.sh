#!/bin/sh
# Fase 1 de AGI/PLAN160W.md: convierte las imagenes de cada juego a 4 bpp (agi2hr.py --gfx4 relee cada fichero y exige 0 pixeles distintos de la imagen de Python)
# y ejecuta el modelo en modo GFX4 sacando un PNG de 160x168 (sprites por software con prioridad, objetos fijos). Uso: sh TOOLS/test_gfx4.sh [JUEGO ...]   (desde AGI/V2)
cd "$(dirname "$0")/.."
for G in ${@:-SQ1 KQ1 KQ2 PQ1 SQ2 Larry1}; do
  [ -d $G ] || { echo "sin datos de $G: omitido"; continue; }
  mkdir -p dump/$G
  python -I TOOLS/agi2hr.py $G dump/$G/hr4 --gfx4 | tail -1
  AGI_GFX4=1 python -I TOOLS/agi_vm.py $G --quiet --cycles 300 --png4 dump/$G/screen4.png | head -1
done
