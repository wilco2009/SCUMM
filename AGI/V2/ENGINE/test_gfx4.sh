#!/bin/sh
# Fase 4 de AGI/PLAN160W.md: el texto en el plano de la FPGA (160w). Casos de texto (display, print, menus, text.screen, clear.lines...) con el Z80 en GFX4=1 contra el modelo:
#   sh test_gfx4.sh [filtro]
cd "$(dirname "$0")"
FAIL=0
t() {  # nombre juego ciclos boot guion
    case "$1" in *$FILTRO*) ;; *) return;; esac
    out=$(AGI_BOOT="$4" GFX4=1 sh test_vm.sh $2 $3 "$5" 2>&1 | grep -a "pantalla 4\|texto 40\|resumen\|traza\|^OK\|DIFER")
    if echo "$out" | grep -q "DIFER"; then echo "FALLO $1"; echo "$out"; FAIL=1; else echo "ok $1 ($(echo "$out" | grep -a 'texto 40' | sed 's/.*; //'))"; fi
}
FILTRO=$1
t D-display SQ1 3 "all,if=equaln:9:1>assignn:100:7,cmd=display:5:5:10" "1:text:xyzzy"
t D-print SQ1 14 "cyc=3,cmd=print:10" "9:key:13"
t D-print-win SQ1 8 "cyc=3,cmd=print:10" ""
t D-menus SQ1 40 "cyc=10,cmd=set:14,cmd=menu.input,if=controller:2>assignn:100:2,if=controller:21>assignn:100:21,cmd=menu.input,if=controller:7>assignn:101:7" "11:dir:5 12:dir:0 13:dir:3 14:dir:0 15:dir:5 16:dir:0 17:dir:5 18:dir:0 19:dir:5 20:dir:0 21:dir:7 22:dir:0 23:key:13 24:dir:3 25:dir:0 26:key:13"
t D-textscreen SQ1 12 "cyc=3,cmd=text.screen,cyc=7,cmd=graphics" ""
t D-clear SQ1 8 "cyc=3,cmd=display:5:5:10,cmd=clear.lines:5:6:15,cmd=clear.text.rect:2:3:4:10:1" ""
t D-menu-open SQ1 16 "cyc=10,cmd=set:14,cmd=menu.input,if=controller:2>assignn:100:2,if=controller:21>assignn:100:21,cmd=menu.input,if=controller:7>assignn:101:7" "11:dir:5 12:dir:0 13:dir:3 14:dir:0 15:dir:5"
t D-restore SQ1 16 "cyc=3,cmd=display:5:5:10,cyc=4,cmd=print:10" "9:key:13"
t D-showobj SQ1 8 "cyc=3,cmd=show.obj:216" ""
t D-showobj2 SQ1 8 "cyc=3,cmd=show.obj:186" ""
t D-addpic SQ1 3 "all,cmd=add.to.pic:1:0:0:80:100:4:3,cmd=add.to.pic:1:0:0:40:120:0:2" ""
t D-room6 SQ1 40 "room=6" ""
t D-kq1 KQ1 60 "" ""
t D-intro SQ1 26 "" ""
t D-menu-kq1 KQ1 25 "cyc=10,cmd=set:14,cmd=menu.input,if=controller:2>assignn:100:2,if=controller:21>assignn:100:21,cmd=menu.input,if=controller:7>assignn:101:7" "11:dir:3 12:dir:0 13:dir:3 14:dir:0 15:dir:3 16:dir:0 17:dir:3 18:dir:0 19:dir:3 20:dir:0 21:dir:3 22:dir:0 23:dir:5 24:dir:0"
t D-menu-larry Larry1 25 "cyc=10,cmd=set:14,cmd=menu.input,if=controller:2>assignn:100:2,if=controller:21>assignn:100:21,cmd=menu.input,if=controller:7>assignn:101:7" "11:dir:3 12:dir:0 13:dir:3 14:dir:0 15:dir:3 16:dir:0 17:dir:3 18:dir:0 19:dir:3 20:dir:0 21:dir:3 22:dir:0 23:dir:5 24:dir:0"
t D-menu-pq1 PQ1 25 "cyc=10,cmd=set:14,cmd=menu.input,if=controller:2>assignn:100:2,if=controller:21>assignn:100:21,cmd=menu.input,if=controller:7>assignn:101:7" "11:dir:3 12:dir:0 13:dir:3 14:dir:0 15:dir:3 16:dir:0 17:dir:3 18:dir:0 19:dir:3 20:dir:0 21:dir:3 22:dir:0 23:dir:5 24:dir:0"
exit $FAIL
