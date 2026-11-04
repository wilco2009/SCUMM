#!/bin/sh
# Compara DOS builds de produccion 160w (GFX4=1, TESTS=0, modo real) en el arnes, sala por sala y fotograma a fotograma: sprites encendidos
# (posicion, colores, pixeles, mascaras), variables, banderas, objetos, imagen y texto (TS_SPRLOG de test_scumm.cpp). Para optimizaciones que no deben cambiar nada;
# mas fuerte que runall.sh, que solo mira el estado final. Por sala: ego colocado, paseo con el teclado, "look" + ENTER.
#   sh simcmp160.sh [JUEGO ...]         por defecto los 5, en paralelo (15-25 min). Antes: HEAD; despues: la copia de trabajo de ENGINE.
#   SIM_ROOMS="53 56" sh simcmp160.sh SQ2
# Solo escribe en $SIM_DIR (por defecto dump/sim160). Necesita dump/JUEGO/log4 (compilavm4.bat) y test_scumm.exe compilado. DIFER = alguna sala distinta.
R=$(cd "$(dirname "$0")/.." && pwd)
GIT=$(cd "$R/../.." && pwd)
SIM=${SIM_DIR:-$R/dump/sim160}
EXE=${SIM_EXE:-$GIT/V2/ENGINE/test/build/test_scumm.exe}
G="${*:-SQ1 SQ2 KQ1 KQ2 PQ1}"

build() {   # build CARPETA: ensambla en CARPETA/AGI/V2/ENGINE
  (cd "$1/AGI/V2/ENGINE" || exit 1
   printf 'GFX4            equ 1\n' > gfx4.inc
   printf 'TESTS           equ 0\n' > tests.inc
   python ../TOOLS/gen_agitab.py agivm.asm agiobj.asm agiin.asm agipic.asm agitab.inc > /dev/null
   python ../TOOLS/gen_sprtab.py sprtab.inc > /dev/null
   pasmo agivm.asm agivm.bin agivm.sym 2> /dev/null
   python ../TOOLS/gen_font.py font6.inc
   cp agivm.sym agires.inc
   for o in a b c d e f; do pasmo agi$o.asm agi$o.bin agi$o.sym 2> /dev/null; python ../TOOLS/mkovl.py agi$o.bin OVER$(echo $o | tr a-f A-F).OVL; done)
}

game() {
  g=$1; W=$SIM/$g; rm -rf "$W"; mkdir -p "$W/tmp"; cp -r "$R/dump/$g/log4" "$W/log"
  python "$R/TOOLS/mkevents.py" "$W/log/DATA/EVENTS.BIN" 0 ""
  ROOMS=${SIM_ROOMS:-$(cd "$W/log/LOG"; ls LOG*.AGL | sed 's/LOG0*\([0-9]*\).AGL/\1/' | grep -v '^$')}
  ok=0; bad=0
  KEYS="20:8,70:,75:6,120:,125:5,190:,195:7,250:,255:8,300:,305:,310:L,314:,318:O,322:,326:O,330:,334:K,338:,342:ENTER,346:,380:ENTER,384:"
  for r in $ROOMS; do
    case $((r % 2)) in 0) P="60:130";; *) P="120:100";; esac
    AGI_BOOT="room=$r,cyc=3,cmd=position:0:${P%:*}:${P#*:}" python "$R/TOOLS/agi2log.py" "$R/$g" "$W/tmp" > /dev/null 2>&1
    cp "$W/tmp/LOG/LOG000.AGL" "$W/log/LOG/"
    for v in a b; do
      for o in A B C D E F; do cp "$SIM/$v/AGI/V2/ENGINE/OVER$o.OVL" "$W/log/DATA/"; done
      (cd "$SIM/$v/AGI/V2/ENGINE"; ZX81_MATRIX="$KEYS" TS_SPRLOG=$(cygpath -m "$W/$v.txt") TS_NOSTOP=1 timeout 60 "$EXE" agivm.bin agivm.sym "$(cygpath -m "$W/log")" 400 "$(cygpath -m "$W/d.bin")" > "$W/out.txt" 2>&1)
    done
    if cmp -s "$W/a.txt" "$W/b.txt"; then ok=$((ok+1)); else bad=$((bad+1)); echo "DIFER $g sala $r ($P): $(diff "$W/a.txt" "$W/b.txt" | sed -n 2p)"; fi
  done
  echo "$g: $ok iguales, $bad distintas"
}

rm -rf "$SIM/a" "$SIM/b"; mkdir -p "$SIM/a" "$SIM/b/AGI/V2" "$SIM/a/V2/ENGINE" "$SIM/b/V2/ENGINE"
(cd "$GIT" && git archive HEAD AGI/V2/ENGINE AGI/V2/TOOLS | tar -x -C "$SIM/a")
cp -r "$R/ENGINE" "$R/TOOLS" "$SIM/b/AGI/V2/"
cp "$GIT/V2/ENGINE/font6.bin" "$SIM/a/V2/ENGINE/"; cp "$GIT/V2/ENGINE/font6.bin" "$SIM/b/V2/ENGINE/"
build "$SIM/a"; build "$SIM/b"
for g in $G; do game $g > "$SIM/res_$g.txt" 2>&1 & done
wait
cat "$SIM"/res_*.txt
if grep -q "^DIFER" "$SIM"/res_*.txt; then echo DIFER; exit 1; fi
