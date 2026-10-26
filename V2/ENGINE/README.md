# SCUMM v2 en el Z80 del SD81 Booster: nucleo del interprete

Diseno y estado: `claude/planning/scumm_interprete.md` y `claude/planning/scumm_plan.md`.

| Fichero | Que es |
|---|---|
| `vm.asm` | Nucleo residente: despachador guiado por tabla, ranuras, variables, estados de objeto, scripts |
| `game.asm` | Capa de juego: sonido, mensajes, actores, cambio de sala (se incluye desde `vm.asm`; incluye a su vez `geom.asm` y `walk.asm`) |
| `geom.asm` | Aritmetica de 32 bits con signo y geometria de las cajas de caminar (`adjustXYToBeInBox`, punto mas cercano de una recta o de una caja) |
| `walk.asm` | Movimiento de los actores: giro, caminata por fotograma, rutas por la matriz de cajas, `walkActorTo` y companeros, consultores |
| `mcu.asm`, `loader.asm` | Handshake con el MCU y ficheros de la SD; carga de `DATA.BIN` (ver `claude/planning/scumm_etapa2.md`) |
| `scumm.asm` | El programa para el ZX81: núcleo + carga + arranque + texto de los mensajes + bucle principal. `compila_scumm.bat` lo copia a la SD del emulador |
| `hr.asm` | Vídeo HiRes 8x1 de 16 colores: la sala en páginas de la RAM extendida, composición de columnas con objetos, scroll fino y motor de scroll por hardware, redibujado de objetos |
| `hrui.asm`, `dark.asm`, `actors.asm`, `ui.asm`, `cam.asm`, `snd.asm`, `save.asm` | El **overlay** (`overlay.asm`, una página en el bloque 0): interfaz de 40 columnas de 6 píxeles (`hr_ui`), oscuridad con los atributos, sprites de los actores (con caché), verbos, cámara, sonido, guardar/cargar |
| `tables.inc` | Tabla de despacho. **Generada** por `../TOOLS/gen_vmtables.py`; no editar |
| `test/` | Arnes de PC: el Z80 de EightyOne con el paginado real, contra un modelo en Python |

## En la SD

`compila_scumm.bat` deja el programa y los datos con un nivel por version de SCUMM (la V3 irá en `SCUMM\V3\`):
`SCUMM\V2\SCUMM.BIN` (común a los juegos de la V2), `SCUMM\V2\<JUEGO>\<JUEGO>.B81` (el BASIC que lo carga con `../SCUMM.BIN`) y
`SCUMM\V2\<JUEGO>\DATA\` (`DATA.BIN`, `ROOMnn.GFX`, `SND\`). Los guardados (`SAVEnn.SAV`) van en la carpeta del juego.
(El visor de salas `VIEWER/` es de la época de los tiles y sigue leyendo `/SCUMM/ROOMnn.GFX`: no vale con los `.GFX` HiRes.)

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

Pruebas del vídeo HiRes (arnés `test_scumm`, que simula la FPGA: sombra de toda la memoria, motor de scroll por el puerto `$3FEF`, paginado):

```
python TOOLS/lfl2hr.py "V2/Zak McKracken" all --cfg games/zak_rooms.cfg -o preview_zak_hr ; cp preview_zak/DATA.BIN preview_zak_hr/
python test/check_hr.py volcado.bin scumm.sym preview_zak_hr     # la pantalla (sombra) = la sala en la camara del hardware, con los objetos que se dibujan
```

Variables de entorno de `test_scumm.exe`: `TS_POKE=fotograma:dir:valor,...` (escribe un byte), `TS_WATCH=lo-hi[,desde]` (imprime las escrituras),
`TS_CALL=fotograma:dir,...` (llama a una rutina y vuelve a `main_loop`: p. ej. `ho_saveload` para probar guardar/cargar), `TS_PROF=desde-hasta` con `TS_OSYM=overlay.sym`
(perfil por rutina y las vueltas más pesadas), `TS_BP`/`TS_TRACE`, `ZX81_ROM` (la ROM del ZX81; ya no hace falta para la fuente). `render_screen.py` dibuja el volcado.
Las dos versiones de `scumm.bin` de una comparación no dan volcados idénticos fotograma a fotograma si cambian los tiempos (el motor del arnés acaba por instrucciones):
compara solo cuando el estado (`hv_cam`, `hv_fine`, sala) coincide.

`build_test.sh` escribe en `test/build/` (ignorado por git, lleva datos derivados del juego).

## Modelo de referencia

`../TOOLS/vmmodel.py` (nucleo) y `../TOOLS/vmgame.py` (capa de juego) transcriben la semantica de
ScummVM. `../TOOLS/vmsynth.py` tiene los scripts sinteticos. El Z80 y el modelo se comparan en la
traza: llamadas al anfitrion (`H`), sucesos del back-end (`E`), y un resumen tras cada orden y
fotograma (`D`).
