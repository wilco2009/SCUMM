#!/bin/sh
# Mascaras de profundidad de los objetos (mask_px.inc, mk_objs) de Zak, sala 11: carga la sala en el arnes (test_scumm), llama a ac_mkdec con una ventana y una lista de
# objetos dibujados a mano (HR_DLIST) y compara BACKBUF con lo que calcula ScummVM (mask_obj_test.py). Hace falta: scumm.bin/scumm.sym/overlay.sym (build_scumm.sh) y
# test/build/sdzak con los datos de Zak (ver README). Uso: sh test/mask_obj.sh   (desde SCUMM/V2/ENGINE)
cd "$(dirname "$0")/.." || exit 1
O="$(mktemp -d)"; command -v cygpath >/dev/null 2>&1 && O="$(cygpath -m "$O")"
A=$(grep -i "^ac_mkdec" overlay.sym | sed 's/.*EQU *0*\([0-9A-F]*\)H.*/\1/')      # direccion de ac_mkdec en el overlay (4 cifras)
A=$(printf '%04X' "0x$A"); LO=${A#??}; HI=${A%??}
SC=$(grep -i "^sc_fatal" scumm.sym | sed 's/.*EQU *0*\([0-9A-F]*\)H.*/\1/'); SS=$(grep -i "^start_scene" scumm.sym | sed 's/.*EQU *0*\([0-9A-F]*\)H.*/\1/')
SSL=$(printf '%04X' "0x$SS"); SSLO=${SSL#??}; SSHI=${SSL%??}
pk() { # direccion bytes...: pokes en el fotograma $F
  a=$1; shift; for b in "$@"; do P="$P,$F:$(printf '%X' "$a"):$b"; a=$((a+1)); done; }
fail=0
# la pagina y la direccion de la mascara de la sala 11 en DATA.BIN: ROOMDIR + 13 (en $F400 + 16 * sala) tras cargar la sala
P=""; F=319; pk $((0x$SC)) 21 0B 00 CD "$SSLO" "$SSHI" C9
TS_POKE="${P#,}" TS_CALL="320:$SC" test/build/test_scumm.exe scumm.bin scumm.sym test/build/sdzak 340 "$O/r.bin" "9:20,-:24,9:60,-:64" >/dev/null 2>&1
set -- $(python -I -c "
d=open(r'$O/r.bin','rb').read()[65536:131072]; e=d[0xF400+16*11+13:0xF400+16*11+16]
a=(e[1]|e[2]<<8)+2
print('%X %X %X' % (e[0], a&255, a>>8))")
MPG=$1; MBL_LO=$2; MBL_HI=$3
run() { # x_pixeles y0 "lista de objetos" celdas_de_ancho [celdas_de_alto: 8 por omision]
  x=$1; y=$2; dl=$3; wc=$4; P=""; F=319
  pk $((0x$SC)) 21 0B 00 CD "$SSLO" "$SSHI" C9                                  # ld hl,11; call start_scene; ret
  F=641; B=$((0x$SC + 32))
  pk $B FD 21 F0 F7 CD "$LO" "$HI" 21 00 95 11 00 B9 01 00 01 ED B0 C9      # ld iy,$F7F0; call ac_mkdec; copia BACKBUF (256 bytes) a $B900
  n=0; for o in $dl; do P="$P,641:$(printf '%X' $((0xBE00+n))):$(printf '%X' "$o")"; n=$((n+1)); done
  P="$P,641:8768:$(printf '%X' $n),641:F7F2:$(printf '%X' "$wc"),641:F7F3:$(printf "%X" "${5:-8}"),641:8A7B:$MPG,641:895E:$MBL_LO,641:895F:$MBL_HI"                # ac_mpg/ac_mbl: sala 11 en DATA.BIN (ROOMDIR+13)
  P="$P,641:893C:$(printf '%X' $((x&255))),641:893D:$(printf '%X' $((x>>8))),641:8939:00,641:893A:00,641:893E:$(printf '%X' "$y"),641:893F:00,641:8955:01"
  TS_POKE="${P#,}" TS_CALL="320:$SC,641:$(printf '%X' $((0x$SC + 32)))" test/build/test_scumm.exe scumm.bin scumm.sym test/build/sdzak 643 "$O/w.bin" "9:20,-:24,9:60,-:64" >/dev/null 2>&1
  r=$(MASK_BASE=0xB900 python -I test/mask_obj_test.py "$O/w.bin" "../Zak McKracken" 11 $((x/8)) "$y" $((wc+2)) $((8*${5:-8})) 2>&1 | tail -2)
  echo "$r"
  case "$r" in *"Z80: 0") ;; *) fail=1 ;; esac
}
run 96 40 "9" 2             # la puerta del aseo (246), abierta, en el centro de la ventana
run 104 20 "9 26 9" 2       # las dos puertas
run 88 0 "26 9" 2           # la ventana empieza antes que el objeto
run 488 56 "21 31" 2        # el asiento (21) recortado por la derecha; el 31 queda fuera
run 496 30 "21" 2
run 96 40 "9" 1 9           # un fotograma de 9 celdas de alto (la azafata, traje 11): tiras de 72 filas
run 496 20 "21" 1 9
run 88 30 "26 9" 1 6
rm -rf "$O"
[ $fail = 0 ] && echo "mask_obj: OK" || echo "mask_obj: FALLO"
exit $fail
