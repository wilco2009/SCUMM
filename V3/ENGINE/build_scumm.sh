#!/bin/sh
# Montaje en tres pasos (el overlay necesita las direcciones del programa y el programa incluye el overlay al final):
#   1. scumm.asm (con el overlay.bin anterior o vacio)  2. overlay.asm (usa scumm.sym)  3. scumm.asm otra vez
cd "$(dirname "$0")" || exit 1
[ -f overlay.bin ] || : > overlay.bin
pasmo scumm.asm scumm.bin scumm.sym || exit 1
pasmo overlay.asm overlay.bin overlay.sym || exit 1
pasmo scumm.asm scumm.bin scumm.sym || exit 1
cp scumm.bin test/build/scumm.bin; cp scumm.sym test/build/scumm.sym
echo "programa hasta: $(grep -i '^ac_sp' scumm.sym)   overlay: $(stat -c %s overlay.bin) bytes"
