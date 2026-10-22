# SCUMM v2 en el Z80 del SD81 Booster: nucleo del interprete

Diseno y estado: `claude/planning/scumm_interprete.md` y `claude/planning/scumm_plan.md`.

| Fichero | Que es |
|---|---|
| `vm.asm` | Nucleo residente: despachador guiado por tabla, ranuras, variables, estados de objeto, scripts |
| `game.asm` | Capa de juego: sonido, mensajes, actores, cambio de sala (se incluye desde `vm.asm`; incluye a su vez `geom.asm` y `walk.asm`) |
| `geom.asm` | Aritmetica de 32 bits con signo y geometria de las cajas de caminar (`adjustXYToBeInBox`, punto mas cercano de una recta o de una caja) |
| `walk.asm` | Movimiento de los actores: giro, caminata por fotograma, rutas por la matriz de cajas, `walkActorTo` y companeros, consultores |
| `mcu.asm`, `loader.asm` | Handshake con el MCU y ficheros de la SD; carga de `DATA.BIN` (ver `claude/planning/scumm_etapa2.md`) |
| `scumm.asm` | El programa para el ZX81: núcleo + carga + vídeo + texto + actores. `compila_scumm.bat` lo copia a la SD del emulador |
| `tables.inc` | Tabla de despacho. **Generada** por `../TOOLS/gen_vmtables.py`; no editar |
| `test/` | Arnes de PC: el Z80 de EightyOne con el paginado real, contra un modelo en Python |

## Probar

Necesita `pasmo`, `g++`/`gcc` y el nucleo Z80 de EightyOne (`Z80SRC`, por defecto
`/c/ClaudeCode/Eightyone2/src`), mas los `.LFL` de Maniac Mansion DOS v2 en `SCUMM/V2/ManiacMansionDOS`.

```
sh test/build_test.sh              # ensambla, genera el mundo y los escenarios, ejecuta y compara
python test/mutaciones.py          # estropea el Z80 a proposito y mira si las pruebas lo notan
sh test/test_loader.sh             # los mismos escenarios con los datos cargados por el Z80 desde DATA.BIN
# programa completo en el arnes (dibuja lo que veria la FPGA):
#   test/build/test_scumm.exe scumm.bin scumm.sym test/build/sd 60 volcado.bin "N:5,-:8"  y  python test/render_screen.py volcado.bin pantalla.png
```

`build_test.sh` escribe en `test/build/` (ignorado por git, lleva datos derivados del juego).

## Modelo de referencia

`../TOOLS/vmmodel.py` (nucleo) y `../TOOLS/vmgame.py` (capa de juego) transcriben la semantica de
ScummVM. `../TOOLS/vmsynth.py` tiene los scripts sinteticos. El Z80 y el modelo se comparan en la
traza: llamadas al anfitrion (`H`), sucesos del back-end (`E`), y un resumen tras cada orden y
fotograma (`D`).
