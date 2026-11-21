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
| `hrui.asm`, `dark.asm`, `actors.asm`, `ui.asm`, `cam.asm` | El **overlay 1** (`overlay.asm`, una página en el bloque 0): interfaz de 40 columnas de 6 píxeles (`hr_ui`), oscuridad con los atributos, sprites de los actores (con caché), verbos, cámara |
| `snd.asm`, `save.asm` | El **overlay 2** (`overlay2.asm`, otra página, `OVL2_PAGE` = 51): sonido y guardar/cargar. Solo se mapea en el bloque 0 mientras se ejecuta, por las puertas `ovg_*` del overlay 1 (un `OUT`; no cuesta nada en el residente). Dentro no se puede llamar al overlay 1 ni a rutinas del residente que lo llamen (`OVL_xxx`). Ver `PROGRESO_OVERLAY.md` |
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

### Depuración: arrancar Zak directamente en una sala

`compila_scumm.bat zak 23` deja Zak en la sala 23 (sin intro, con Zak y la interfaz activos); `compila_scumm.bat zak 23 40 30` fija además la posición X Y de Zak (unidades de `putActor`: x en 8 px, y en 2 px; por omisión, el centro de la primera caja pisable, o (20,56) si la sala no tiene cajas, p.ej. la 45).
Solo cambia el script 1 de `DATA.BIN` (`pack_data.py --debug-room N[,X,Y]`: la preparación del script 1 + la inicialización del script 108 + «Zak en la sala N»); no toca el Z80. Sin el segundo argumento los datos son idénticos byte a byte a los normales. En el arnés: `pack_data.py ... --debug-room 23` y `test_scumm.exe scumm.bin scumm.sym <sd> 300 v.bin ""`.

### Medir el programa completo de Zak (perfil y T por instrucción de script)

Desde `SCUMM/V2/ENGINE` (el arnés se recompila con `g++ ... test_scumm.cpp test/build/z80.o test/build/z80_ops.o`, ver `build_test.sh`). Hay que ensamblar antes `scumm.bin`, `scumm.sym` y `overlay.sym` (los tres pasos de `compila_scumm.bat`, o `build_scumm.sh`).

```
# 1. datos de Zak en una carpeta de SD del arnés (DATA.BIN version 2 + .GFX HiRes + sonidos); si no, el programa se queda en sc_fatal esperando una tecla
python ../TOOLS/lfl2hr.py "../Zak McKracken" all --cfg ../games/zak_rooms.cfg -o ../preview_zak_hr      # solo si no existe preview_zak_hr/gfx
python ../TOOLS/sound2vgm.py "../Zak McKracken" ../preview_zak_hr/snd                                   # solo si no existe preview_zak_hr/snd
mkdir -p test/build/sdzak/SND
python ../TOOLS/pack_data.py "../Zak McKracken" test/build/sdzak/DATA.BIN --game ../games/zak.cfg --sounds ../preview_zak_hr/snd
cp ../preview_zak_hr/gfx/*.GFX test/build/sdzak/ ; cp ../preview_zak_hr/snd/*.VGM test/build/sdzak/SND/
# 2. perfil: TS_VM=1 añade las instrucciones de script (T por instruccion, por opcode, por vuelta); TS_T=1 mide en T-estados y no en instrucciones del Z80
TS_VM=1 TS_T=1 TS_PROF=100-400 TS_OSYM=overlay.sym TS_TOP=40 test/build/test_scumm.exe scumm.bin scumm.sym test/build/sdzak 400 volcado.bin "N:5,-:8"
```

El último argumento son pares `teclas:fotograma` (la tecla vale desde ese fotograma; `-` suelta todas): `O P Q A` mueven el cursor 3 px por fotograma, `S` es el clic, `9` salta la cutscene, `8` es F5. Con `9:20,-:24,9:60,-:64` Zak sale de la cutscene del despacho (sala 46) y queda en su piso (sala 1) hacia el fotograma 300.
Recorrido de la medida B (Zak camina por la sala 1 y la cámara hace scroll): `TS_PROF=300-1000`, 1000 fotogramas y
`"9:20,-:24,9:60,-:64,PA:350,P:364,-:375,S:377,-:379,O:480,-:520,S:522,-:524,P:640,-:700,S:702,-:704,O:800,-:850,S:852,-:854"`.
Medida C (5 actores, sintética): lo mismo con `TS_PROF=700-1000` y, en `TS_POKE=650:dir:valor,...`, para cada actor `a` en (2, 3, 4, 7) y `b = $EF00 + 48*a`: sala (+0) = 1, x (+1) y y (+3), traje (+5) y visible (+9) = 1 (los trajes 2, 1, 2, 28; x = 12, 16, 26, 30; y = 50, 54, 52, 56; fotograma (+10) = 17).
`python test/render_screen.py volcado.bin pantalla.png` dibuja el resultado para comprobar que pasa lo que se cree.

Que imprime `TS_VM`: instrucciones de script ejecutadas, T por instrucción (media, mediana, p90, p99, máximo; decodificación + manejador, sin las ejecuciones anidadas que lanza, con el prólogo de `exec_script`), instrucciones por vuelta y una tabla por opcode (n, T medios exclusivos y con anidadas). Una instrucción va desde que `es_loop` (`vm_core.asm`) coge el opcode hasta que el manejador vuelve a `es_loop`. Resultados de 2026-11-11 y cómo leerlos: `SCUMM/V3/PLAN.md`, fase 0.

`build_test.sh` escribe en `test/build/` (ignorado por git, lleva datos derivados del juego).

## Modelo de referencia

`../TOOLS/vmmodel.py` (nucleo) y `../TOOLS/vmgame.py` (capa de juego) transcriben la semantica de
ScummVM. `../TOOLS/vmsynth.py` tiene los scripts sinteticos. El Z80 y el modelo se comparan en la
traza: llamadas al anfitrion (`H`), sucesos del back-end (`E`), y un resumen tras cada orden y
fotograma (`D`).

### Partidas guardadas (`save.asm`) y cuando caducan

La cabecera de `SAVEnn.SAV` (8 bytes) lleva: la **marca del programa** (`savestamp.inc`, la genera `TOOLS/savestamp.py` en cada compilacion a partir de `scumm.sym`: nombre y direccion de cada simbolo de datos de las zonas volcadas `$E000-$FFFF`, `UI_DIRTY`+`SV_LEN_O` e `INVSL`..`$9500`, mas `NACTORS`, `NSLOT`, `ASIZE` y los `SV_LEN_*`), la **marca de los scripts** (`DATA.BIN` +13..+15, la calcula `pack_data.py` con `SCRDIR`, `ODIR` y el codigo de entrada y salida de cada sala) y la version de `DATA.BIN`. Recompilar o mover codigo no la cambia; las partidas caducan solo si se mueve, anade, quita o renombra una variable de las zonas guardadas, se cambia su tamano, o cambia la posicion de algun script en `DATA.BIN` (otro juego; cambios en los scripts o en lo que se empaqueta antes que ellos: las mascaras de profundidad van entre los codigos de entrada de las salas). Cambiar graficos, paleta, trajes o sonidos no las invalida. `savestamp.inc` esta ignorado por git y lo regeneran `build_scumm.sh` y `compila_scumm.bat`.

### Sprites de los actores (`actors.asm`)

- **Ranuras:** 78 en total. Las 0-62 son los sprites 62-0 de la placa (el 63 es el cursor); las 63-77 son los **sprites extra** de la FPGA (`POKE 2131` = M; entrada `j` = 32 bytes en `$4000 + 32*j`, bloque 2 de `POKE 2129`), que tienen menos prioridad que los normales. La entrada 1 no se usa (`$403B` es `CDFLAG` del ZX81). Los extra pisan las variables del sistema del ZX81: al salir de SCUMM tras usarlos (`ac_xd`) el ordenador se reinicia. Con 62 sprites o menos, `POKE 2131` vale 0 y no cuesta tiempo de línea.
- **Orden:** la lista de actores (por y) se recorre de delante hacia atrás; el primero que se dibuja recibe las ranuras de más prioridad. Un actor que no cabe entero no se dibuja.
- **Escala:** `escala = 1/1,7/8,3/4` en `[trajes]` del perfil: cada traje usa la primera en la que caben en su página (6100 B, 256 celdas) sus fotogramas de overlay imprescindibles.
- **Fotogramas de overlay:** `animateActor` con un fotograma que no es caminar (0), parado (1), inicio (2) ni hablar (4, 5) deja puestos los miembros que nombra (en ScummVM cada animación solo cambia los suyos). `ac_track` recuerda el último (3 o ≥ 6; el inicio y caminar lo quitan) y `costume2.py` guarda esas poses en la animación `4 * fotograma + dirección`. Ejemplo: el pelo y el sombrero del vendedor de la Phone Company son el miembro 7 del fotograma 6, que el script 150 pone al entrar en la sala. Solo con el actor parado; caminando se usa la caminata normal. Aproximación: un solo overlay a la vez, no un estado por miembro.
- **Probar en el arnés:** salto a la sala 4 con `TS_POKE=319:EF30:4,319:EB11:4,319:EB12:0,319:EF31:15,319:EF33:3A TS_CALL=320:5399 test_scumm.exe scumm.bin scumm.sym test/build/sdzak 520 v.bin "9:20,-:24,9:60,-:64"`; `render_screen.py` imprime los sprites normales y extra y el máximo por línea.
- **Mascara de profundidad de los objetos:** en v2 cada objeto lleva su mascara tras los pixeles de su OBIM y, al dibujarse (estado con el bit 8), **sustituye** (ceros incluidos) a la de la sala en sus tiras y filas (`GdiV2::prepareDrawBitmap`). `TOOLS/lfl2gfx.py mask_blob_objs` la empaqueta en `DATA.BIN` tras la mascara de la sala (una palabra delante con el desplazamiento de la tabla de objetos) y `mask_px.inc` (`mk_objs`) la aplica sobre la ventana de BACKBUF al decodificar la mascara de un personaje, en el orden de `HR_DLIST` (los objetos que se dibujan, del ultimo al primero). Una sala cuya mascara con la de sus objetos pase de 6000 bytes pierde las mascaras de objeto mas grandes (`pack_data.MASK_MAX`; en Zak, la sala 38). Prueba: `sh test/mask_obj.sh` (Zak, sala 11: BACKBUF contra ScummVM con distintas ventanas y listas de objetos).
- **Pinchar sobre un actor (`actorFromPos`):** el rectángulo es el que ha dibujado el actor (`ACB` = `$F3B0`, 4 bytes con signo por actor 1-18: izquierda, derecha, arriba y abajo respecto de x*8 e y*2; lo escribe `ac_draw`), como `_top`/`_bottom` de ScummVM. Sin dato (actor sin dibujar, número > 18, o pruebas sin overlay) vale el de 16 x 32 alrededor de los pies de antes.

### Colores de la botonera (A9)

- Los verbos llevan su color en `UIAT` (`ui.asm`, $9A40: un byte por caracter de las filas 1-3 de la zona de abajo; valor XOR $0F del atributo de Chroma). `hrui.asm` (`hg_u`) saca el atributo de cada celda de 8 pixeles como OR de los dos caracteres de 6 pixeles que toca, asi que en la frontera entre dos verbos pegados manda el de valor mas alto (atenuado > resaltado > normal).
- Normal = blanco brillante `$0F` (sin cambios); el verbo bajo el cursor (`ui_hover`, `UI_HOV`, solo si esta en modo 1 como en `checkV2MouseOver`) sale en amarillo `$0E` (hicolor 14 de ScummVM); un verbo en modo 2 (`verbOps` 0xFF) sale gris `$08` (dimcolor 8). Los colores del interprete de ScummVM (color 2 verde, frase 13) no se copian: se mantiene el blanco de siempre.
- No se guarda en las partidas (UIAT y UI_HOV estan fuera de las zonas volcadas) ni cambia DATA.BIN. No hay resaltado del renglon de la frase ni del inventario.
