#!/bin/sh
# Prueba larga de SCUMM v3: UNA VEZ AL DIA, POR LA NOCHE (regla del usuario, 2026-11-16).
# LIMITES (usuario, 2026-11-17): la noche entera <= 3-4 h (la tarea de Windows la corta a las 4 h);
# de dia, ninguna prueba > 30 min. Cada paso lleva su tope (timeout); si lo pasa sale "salida 124".
# Presupuesto (min): nucleo 10, arranque 10, Barnett 15, guardar 25, actores 20, objetos 10,
# mutaciones del nucleo 75, mutaciones de actores + guardar (10e) 30 entre las dos, v2 50 (una sola).
# v2 solo si V2/ o COMMON/ han cambiado desde la ultima noche que lo paso, y un juego por noche (Maniac/Zak alternos).
# Deja el resumen en build/noche/AAAA-MM-DD.txt y los registros completos en build/noche/AAAA-MM-DD/.
# Uso: sh pruebas_noche.sh            (la tarea programada de Windows "SCUMM v3 pruebas noche" lo lanza a las 02:00)
export PATH="/c/msys64/ucrt64/bin:/c/Mingw64/bin:/c/Users/aleja/Nextcloud/retro/Tools/pasmo-0.5.4:/usr/bin:/mingw64/bin:$PATH"
cd "$(dirname "$0")" || exit 1
D=$(date +%Y-%m-%d)
mkdir -p build/noche/$D
R=build/noche/$D.txt
G="../../Indy Last Crusade"
T0=$(date +%s)
echo "Prueba nocturna de SCUMM v3, $D (empieza $(date +%H:%M))" > $R
echo "repo SCUMM: $(git -C ../../.. log --oneline -1)" >> $R
[ -n "$(git -C ../../.. status --short -- V3 V2 COMMON | grep -v '^??')" ] && echo "ojo: hay cambios sin commit en V2/V3/COMMON" >> $R

paso() {   # paso nombre tope_en_minutos "patron de las lineas de resultado" orden...
  n=$1; tope=$2; pat=$3; shift 3
  t0=$(date +%s)
  timeout -k 60 $((tope * 60)) "$@" > build/noche/$D/$n.log 2>&1
  rc=$?
  m=$(( ($(date +%s) - t0 + 30) / 60 ))
  echo "" >> $R
  if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
    echo "== $n ($m min, CORTADA: paso de $tope min)" >> $R
  else
    echo "== $n ($m min, salida $rc)" >> $R
  fi
  grep -E "$pat" build/noche/$D/$n.log | tail -8 >> $R
}

paso nucleo     10 "escenarios:|distintos|Error|error" sh build_test.sh
paso arranque   10 "iguales|distint|DISTINT|ordenes|Error|error" sh build_boot.sh 1500
paso arranque_hr 5 "distint|iguales|Error|error" python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx
paso barnett    15 "iguales|distint|DISTINT|ordenes|Error|error" sh build_boot.sh 1750 "$G" ev_barnett.txt
paso barnett_hr  5 "distint|iguales|Error|error" python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx
paso guardar    25 "^==|iguales|distint|DISTINT|Error|error" sh savetest.sh
paso actores    20 "semilla|Error|error" sh actall.sh "1 2" "1 15 20 28" 12
paso objetos    10 "fotograma|distint|Error|error" sh objflip.sh 20
paso mutaciones 75 "mutaciones:|sin detectar|NO DA" python -I mutaciones.py 1,15,20
# 10e: las dos juntas <= 30 min (la sesion 10e las deja dentro; los topes son la red)
paso mut_actores 20 "mutaciones de la fase 8|SIN DETECTAR|SIN MUTAR" python -I mut_fase8.py
paso mut_guardar 15 "mutaciones de ovc9|sin detectar|NO DA|SIN MUTAR" python -I mut_fase9.py

# v2: solo si V2/ o COMMON/ han cambiado (commit o sin commit) desde la ultima noche que lo paso; un juego por noche.
E=build/noche/v2_estado
v2now=$( (git -C ../../.. log -1 --format=%H -- V2 COMMON; git -C ../../.. diff -- V2 COMMON) | md5sum | cut -c1-32)
if [ "$v2now" != "$(cat $E 2>/dev/null)" ]; then
  if [ $(( $(date +%j | sed 's/^0*//') % 2 )) -eq 0 ]; then
    paso v2_maniac 50 "escenarios:|distintos|Error|error" sh ../../../V2/ENGINE/test/build_test.sh
  else
    paso v2_zak    50 "escenarios:|distintos|Error|error" sh ../../../V2/ENGINE/test/build_test.sh "../../Zak McKracken"
  fi
  # se da por pasado solo si salio bien; si no, la noche siguiente lo repite (con el otro juego)
  [ $rc -eq 0 ] && echo "$v2now" > $E
else
  echo "" >> $R; echo "== v2: sin cambios en V2/COMMON desde la ultima vez, no se pasa" >> $R
fi

echo "" >> $R
echo "Acaba $(date +%H:%M) ($(( ($(date +%s) - T0 + 30) / 60 )) min en total)" >> $R
