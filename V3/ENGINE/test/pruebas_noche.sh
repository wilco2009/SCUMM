#!/bin/sh
# Prueba larga de SCUMM v3: UNA VEZ AL DIA, POR LA NOCHE (regla del usuario, 2026-11-16).
# Durante el dia solo se pasan pruebas especificas del cambio que se haga (ver "Reglas" en V3/PLAN.md).
# Deja el resumen en build/noche/AAAA-MM-DD.txt (lineas de resultado y minutos de cada prueba) y los registros completos en build/noche/AAAA-MM-DD/.
# Uso: sh pruebas_noche.sh            (la tarea programada de Windows "SCUMM v3 pruebas noche" lo lanza a las 02:00)
export PATH="/c/msys64/ucrt64/bin:/c/Mingw64/bin:/c/Users/aleja/Nextcloud/retro/Tools/pasmo-0.5.4:/usr/bin:/mingw64/bin:$PATH"
cd "$(dirname "$0")" || exit 1
D=$(date +%Y-%m-%d)
mkdir -p build/noche/$D
R=build/noche/$D.txt
G="../../Indy Last Crusade"
echo "Prueba nocturna de SCUMM v3, $D (empieza $(date +%H:%M))" > $R
echo "repo SCUMM: $(git -C ../../.. log --oneline -1)" >> $R
[ -n "$(git -C ../../.. status --short -- V3 V2 COMMON | grep -v '^??')" ] && echo "ojo: hay cambios sin commit en V2/V3/COMMON" >> $R

paso() {   # paso nombre "patron de las lineas de resultado" orden...
  n=$1; pat=$2; shift 2
  t0=$(date +%s)
  "$@" > build/noche/$D/$n.log 2>&1
  rc=$?
  m=$(( ($(date +%s) - t0 + 30) / 60 ))
  echo "" >> $R
  echo "== $n ($m min, salida $rc)" >> $R
  grep -E "$pat" build/noche/$D/$n.log | tail -8 >> $R
}

paso nucleo     "escenarios:|distintos|Error|error" sh build_test.sh
paso arranque   "iguales|distint|DISTINT|ordenes|Error|error" sh build_boot.sh 1500
paso arranque_hr "distint|iguales|Error|error" python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx
paso barnett    "iguales|distint|DISTINT|ordenes|Error|error" sh build_boot.sh 1750 "$G" ev_barnett.txt
paso barnett_hr "distint|iguales|Error|error" python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx
paso guardar    "^==|iguales|distint|DISTINT|Error|error" sh savetest.sh
paso actores    "semilla|Error|error" sh actall.sh "1 2" "1 15 20 28" 12
paso objetos    "fotograma|distint|Error|error" sh objflip.sh 20
paso mutaciones "mutaciones:|sin detectar" python -I mutaciones.py 1,15,20
paso v2_maniac  "escenarios:|distintos|Error|error" sh ../../../V2/ENGINE/test/build_test.sh
paso v2_zak     "escenarios:|distintos|Error|error" sh ../../../V2/ENGINE/test/build_test.sh "../../Zak McKracken"

echo "" >> $R
echo "Acaba $(date +%H:%M)" >> $R
