#!/bin/sh
# Prueba del modelo de referencia: SQ1 debe pasar por las salas 67 (intro), 69 (nombre) y 2, y entender "look at closet".
cd "$(dirname "$0")" || exit 1
[ -d ../SQ1 ] || { echo "sin datos de SQ1: prueba omitida"; exit 0; }
python agi_vm.py ../SQ1 --cycles 700 --script "299:str:Roger 300:key:13 480:text:look at closet" 2>&1 > /tmp/agi_vm.log
for k in "sala 67" "sala 69" "sala 2 " "palabras \[2, 253\]"; do
    grep -q "$k" /tmp/agi_vm.log || { echo "FALLA: no aparece '$k'"; exit 1; }
done
echo "OK: SQ1 67 -> 69 -> 2 y el parser entiende 'look at closet'"
