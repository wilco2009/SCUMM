#!/bin/sh
# Casos de prueba de AUDITORIA3 (seccion 6) que se pueden automatizar: sh test_audit3.sh [filtro]
# Cada caso: el modelo (agi_vm.py --show) tiene que dar el valor esperado segun ScummVM y el Z80 tiene que coincidir con el modelo (test_vm.sh).
# El codigo de prueba se inyecta al arrancar la logica 0 con AGI_BOOT (agi_read.testboot): cmd=orden:args, if=cond&cond>orden;orden, vN=valor, room=N.
cd "$(dirname "$0")"
FAIL=0
t() {  # nombre juego ciclos boot guion lista esperado
    case "$1" in *$FILTRO*) ;; *) return;; esac
    exp=$(echo "$7" | tr ',' ' ')
    got=$(AGI_BOOT="$4" python -I ../TOOLS/agi_vm.py ../$2 --quiet --cycles $3 --script "$5" --show "$6" | grep '^show:')
    if [ "$got" != "show: $exp" ]; then echo "FALLO $1: modelo '$got', esperado 'show: $7'"; FAIL=1; return; fi
    z=$(AGI_BOOT="$4" sh test_vm.sh $2 $3 "$5" 2>&1 | tail -1)
    if [ "$z" != "OK" ]; then echo "FALLO $1: Z80 != modelo ($z)"; FAIL=1; return; fi
    echo "ok $1"
}
FILTRO=$1
t T-10 Larry1 12 "cmd=set.string:12:1,if=compare.strings:12:12>assignn:100:7" "" v100 v100=7
# A3-13: parser y said (words.cpp, op_test.cpp:329). Palabras de SQ1: look=2, rock=37, anyword=1, the/a/i/at=0
S="1:text:look at the rock"
t T-13a SQ1 1 "all,if=!isset:2>assignn:100:7" "1:text:the" v100 v100=7
t T-13b SQ1 1 "all,cmd=reset:2,if=said:2>assignn:100:7" "1:text:look" v100 v100=0
t T-13c SQ1 1 "all,if=said:2>assignn:100:7" "1:text:look" v100 v100=7
t T-13d SQ1 1 "all,if=said:2:1>assignn:100:7,if=equaln:9:2>assignn:101:7" "1:text:look foo" v100,v101 v100=7,v101=7
t T-13e SQ1 1 "all,if=said:2:37>assignn:100:7" "1:text:look at the rock" v100 v100=7
t T-13f SQ1 1 "all,if=said:2:37>assignn:100:7" "1:text:LO'OK.rock" v100 v100=7
t T-13g SQ1 1 "all,if=equaln:9:2>assignn:100:7" "1:text:look zzz" v100 v100=7
t T-13h SQ1 1 "all,if=said:2:9999>assignn:100:7,if=said:2:1:1>assignn:101:7" "1:text:look foo bar" v100,v101 v100=7,v101=0
t T-13i SQ1 1 "all,if=said:2:37>assignn:100:7" "1:text:look a rock" v100 v100=7
# A3-04: el ENTER de una frase deja v19 = 13; A3-03: una tecla con controlador no pone v19
t T-04 SQ1 1 "all,if=equaln:19:13>assignn:100:7" "1:text:look" v100 v100=7
t T-03 Larry1 2 "all,cmd=set.key:27:0:5,if=equaln:19:27>assignn:100:7,if=controller:5>assignn:101:7" "2:key:27" v100,v101 v100=0,v101=7
t T-03b Larry1 1 "all,if=equaln:19:65>assignn:100:7" "1:key:65" v100 v100=7
# A3-08: cortocircuito de && y || (el said que no se evalua no pone f4)
t T-08a SQ1 1 "all,if=isset:200&said:2>assignn:100:7,if=!isset:4>assignn:101:7" "1:text:look" v100,v101 v100=0,v101=7
t T-08b SQ1 1 "all,if=|equaln:19:13&said:2>assignn:100:7,if=!isset:4>assignn:101:7" "1:text:look" v100,v101 v100=7,v101=7
t T-08c SQ1 1 "all,if=|isset:200&said:2>assignn:100:7,if=isset:4>assignn:101:7" "1:text:look" v100,v101 v100=7,v101=7
# A3-15: get.num modal (espera la linea; atoi modulo 256)
t T-15 SQ1 4 "all,if=equaln:100:0>get.num:1:100" "3:str:42" v100 v100=42
t T-15b SQ1 3 "all,if=equaln:100:0>get.num:1:100" "2:str:300x" v100 v100=44
# A3-11/A3-12: set.string guarda el texto sin formato; stringPrintf (%vN|W, %0 de relleno, recursion de %m, %s)
t T-11 SQ1 1 "v3=7,cmd=set.string:1:30,if=compare.strings:1:1>assignn:100:7" "" v100 v100=7
t T-12a SQ1 1 "all,if=equaln:9:1>assignn:100:7,cmd=display:5:5:10" "1:text:xyzzy" v100 v100=7
t T-12b SQ1 1 "all,cmd=set.string:1:2,cmd=display:5:5:15" "" v9 v9=0
python -I - <<'PY' || FAIL=1
import sys
sys.path.insert(0, '../TOOLS')
import agi_vm
it = agi_vm.Interp('../SQ1', True)
it.vars[3], it.vars[4], it.vars[5] = 5, 123, 0
it.strs[1] = 'a%v3b'
it.wtext = ['foo', 'bar']
ok = True
def chk(src, want):
    global ok
    got = it.fmt(src, 0)
    if got != want:
        print('FALLO fmt %r: %r, esperado %r' % (src, got, want)); ok = False
chk('%v3', '5'); chk('%v5', '0'); chk('%v3|3', '005'); chk('%v4|2', '23'); chk('%v4|5', '00123'); chk('%v3|0', '')
chk('%w1 %w2 %w3', 'foo bar '); chk('x%s1y', 'xa5by'); chk(chr(92) + '%v3', '%v3'); chk('%q12z', 'z'); chk('%v3%v4', '5123')
chk(it.logic(0)[1][9], 'I don' + chr(39) + 't understand ' + chr(34) + 'foo' + chr(34)); chk('%m8', "I don't understand ")
print('ok T-12 fmt' if ok else 'FALLO T-12 fmt')
sys.exit(0 if ok else 1)
PY
[ $FAIL = 0 ] && echo "AUDIT3: todos OK" || echo "AUDIT3: HAY FALLOS"
