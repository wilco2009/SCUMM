#!/bin/sh
# Zak, sala 4: el vendedor (actor 7) camina y se para; el sombrero (miembro 7, fotograma de overlay 6) debe seguir puesto (AC_OVF del actor 7 = 06).
# Hay que haber compilado (build_scumm.sh) y empaquetado test/build/sdzak/DATA.BIN. Uso: sh test/sombrero_vendedor.sh
cd "$(dirname "$0")/.." || exit 1
A=$(grep -i "^vm_load_room" scumm.sym | sed 's/.*EQU 0*\([0-9A-F]*\)H/\1/')
V=$(grep -i "^AC_OVF" scumm.sym | sed 's/.*EQU 0*\([0-9A-F]*\)H/\1/'); V=$(printf '%X' $((0x$V + 7)))
O=$(TS_WATCH=$V-$V,300 TS_POKE=319:EF30:4,319:EB11:4,319:EB12:0,319:EF31:15,319:EF33:3A,340:F05A:0,380:F05A:1 TS_CALL=320:$A \
    test/build/test_scumm.exe scumm.bin scumm.sym test/build/sdzak 420 /tmp/sombrero.bin "9:20,-:24,9:60,-:64" 2>&1 | grep "^W f=" | tail -1)
echo "$O"
case "$O" in *"]=06") echo OK;; *) echo FALLO: el sombrero se pierde; exit 1;; esac
