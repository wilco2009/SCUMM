#!/bin/sh
# Compila descumm (el desensamblador de scripts de SCUMM de scummvm-tools, GPL) para comparar nuestro
# volcado. Baja los fuentes de GitHub y los compila con unas cabeceras minimas (shim/common/*.h)
# que sustituyen a las de ScummVM. Uso: build.sh CARPETA_DE_TRABAJO
set -e
W="${1:?indica una carpeta de trabajo nueva}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$W"
for f in descumm-common.cpp descumm-tool.cpp descumm.cpp descumm.h descumm6.cpp; do
    curl -sfL -o "$W/$f" "https://raw.githubusercontent.com/scummvm/scummvm-tools/master/engines/scumm/$f"
done
g++ -O1 -w -I"$HERE/shim" -o "$W/descumm" "$W/descumm-tool.cpp" "$W/descumm.cpp" "$W/descumm6.cpp" "$W/descumm-common.cpp"
echo "listo: $W/descumm"
