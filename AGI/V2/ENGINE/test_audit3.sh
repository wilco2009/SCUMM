#!/bin/sh
# Casos de prueba de AUDITORIA3 (seccion 6) que se pueden automatizar: sh test_audit3.sh [filtro]
# Cada caso: el modelo (agi_vm.py --show) tiene que dar el valor esperado segun ScummVM y el Z80 tiene que coincidir con el modelo (test_vm.sh).
# El codigo de prueba se inyecta al arrancar la logica 0 con AGI_BOOT (agi_read.testboot): cmd=orden:args, if=cond&cond>orden;orden, vN=valor, room=N.
cd "$(dirname "$0")"
FAIL=0
t() {  # nombre juego ciclos boot guion lista esperado
    case "$1" in *$FILTRO*) ;; *) return;; esac
    got=$(AGI_BOOT="$4" python -I ../TOOLS/agi_vm.py ../$2 --quiet --cycles $3 --script "$5" --show "$6" | grep '^show:')
    if [ "$got" != "show: $7" ]; then echo "FALLO $1: modelo '$got', esperado 'show: $7'"; FAIL=1; return; fi
    z=$(AGI_BOOT="$4" sh test_vm.sh $2 $3 "$5" 2>&1 | tail -1)
    if [ "$z" != "OK" ]; then echo "FALLO $1: Z80 != modelo ($z)"; FAIL=1; return; fi
    echo "ok $1"
}
FILTRO=$1
t T-10 Larry1 12 "cmd=set.string:12:1,if=compare.strings:12:12>assignn:100:7" "" v100 v100=7
[ $FAIL = 0 ] && echo "AUDIT3: todos OK" || echo "AUDIT3: HAY FALLOS"
