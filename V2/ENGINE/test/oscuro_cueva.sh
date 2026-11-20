#!/bin/sh
# Zak, sala 13 (cueva): oscuridad al entrar, al salir y al volver a entrar; hv_dark y pantalla (render_screen.py).
# Hace falta build_scumm.sh y test/build/sdzak. Uso: sh test/oscuro_cueva.sh [limite]  (desde SCUMM/V2/ENGINE). Escribe $T/oc_N.png (N = fotograma final)
cd "$(dirname "$0")/.." || exit 1
T="${OC_DIR:-$(mktemp -d)}"; command -v cygpath >/dev/null 2>&1 && T="$(cygpath -m "$T")"
g() { grep -i "^$1[[:space:]]" scumm.sym | sed 's/.*EQU *0*\([0-9A-F]*\)H.*/\1/'; }
SC=$(g sc_fatal); SS=$(g start_scene); D=$(g hv_dark)
SSL=$(printf '%04X' "0x$SS"); LO=${SSL#??}; HI=${SSL%??}
P=""; pk() { a=$1; shift; for b in "$@"; do P="$P,$F:$(printf '%X' "$a"):$b"; a=$((a+1)); done; }
F=319; pk $((0x$SC)) 21 0D 00 CD "$LO" "$HI" C9        # entrar en la sala 13
F=500; pk $((0x$SC)) 21 04 00 CD "$LO" "$HI" C9        # salir a la sala 4
F=700; pk $((0x$SC)) 21 0D 00 CD "$LO" "$HI" C9        # volver a entrar
fail=0
for N in 400 600 800; do
  TS_POKE="${P#,}" TS_CALL="320:$SC,501:$SC,701:$SC" test/build/test_scumm.exe scumm.bin scumm.sym test/build/sdzak $N "$T/oc_$N.bin" "9:20,-:24,9:60,-:64" >/dev/null 2>&1
  python test/render_screen.py "$T/oc_$N.bin" "$T/oc_$N.png" 1 >/dev/null
  n=$(python -I -c "
d=open(r'$T/oc_$N.bin','rb').read(); print(sum(1 for x in d[0xC000:0xC000+4096] if x))")
  case $N in 600) [ "$n" -gt 1000 ] || { echo "FALLO a $N: la sala 4 sigue a oscuras ($n)"; fail=1; };; *) [ "$n" -eq 0 ] || { echo "FALLO a $N: la cueva no esta oscura ($n atributos)"; fail=1; };; esac
done
[ $fail = 0 ] && echo OK
exit $fail
