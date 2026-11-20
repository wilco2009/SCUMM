# Fase 3: mapa de memoria y nucleo de la VM v3 en el Z80 (resultado, 2026-11-12)

Plan: `PLAN.md`, fase 3. Todo esta en `V3/ENGINE/` (copia de `V2/ENGINE`, D1) y en `V3/TOOLS/`. Sin commit.

```
cd SCUMM/V3/ENGINE/test
sh build_test.sh                                   # todas las salas, 1 semilla (~5 min)
sh build_test.sh "../../Indy Last Crusade" 2 1,15  # 2 semillas, salas 1 y 15
TS_VM=1 build/test_vm.exe build/vm.bin build/vm.sym build/ovlb.bin build/DATA.BIN build/scenarios.txt build/actual.txt   # T por instruccion
```

## Que hay

| Fichero | Que es |
|---|---|
| `ENGINE/vm_core.asm` | Nucleo residente nuevo: entradas, despachador, lectura de operandos de 16 bits, variables (normales, bits, locales, indirectas), ranuras, pila de ranuras, `runScript`, `stopScript`, `freeze`, cutscenes, decodificador generico, anfitrion. Mapa de memoria del bloque 7 |
| `ENGINE/vm_ops.asm` | Manejadores nativos del nucleo (36 opcodes, `vmmodel3.CORE_OPS`) |
| `ENGINE/ovb4.asm`, `ovb4b.asm`, `ovb4c.asm` | Manejadores del overlay B de las fases 4a (sonido, objetos, camara, actores), 4b-1 (estados, clases, cadenas, verbos, `actorOps`, sala) y 4b-2 (`print`, `printEgo`, mensajes); se incluyen desde `ovlb.asm` |
| `ENGINE/ovlc.asm`, `ovc1.asm`, `ovctab.inc` | **Overlay C** (pagina fisica 48; abierto tras la fase 4b-2): `roomOps`, `resourceRoutines`, `lights`, `systemOps` y `saveLoadGame` salieron de B; la fase 5 pone aqui lo suyo. `ovctab.inc` (generada) es su despacho por opcode |
| `ENGINE/ovc5.asm` | **Fase 5** (overlay C): `startScene`, `load_room_state`, objetos de la sala (`findObject`, `drawObject`, `pickupObject`, `startObject`, `getVerbEntrypoint`), cajas (`isActorInBox`, `setBoxFlags`), pseudosalas y la cola de frases (`doSentence`, `waitForSentence`, `checkAndRunSentenceScript`) |
| `ENGINE/ovld.asm`, `geom.asm`, `walk.asm` | **Overlay D** (pagina fisica 46; fase 6): geometria de las cajas y caminata de v3 (`geom.asm` y `walk.asm` ya no son la copia de v2). Ver "Fase 6" |
| `ENGINE/ovc6.asm` | **Fase 6** (overlay C): `walkActorTo`, `walkActorToActor`, `walkActorToObject`, `waitForActor` (leen sus operandos y entran en D) |
| `ENGINE/arith32.asm` | Aritmetica de 32 bits (copiada de `geom.asm` de v2: la usa `expression` y, en el overlay D, `mul32` y `neg32`) |
| `ENGINE/ovlb.asm` | Overlay B (D4, pagina 49): de momento `expression`, con pila de 32 bits |
| `ENGINE/vm.asm` | Montaje de pruebas: codigo desde `$4200`, tablas desde `$8000`, como el programa de la placa |
| `ENGINE/tables3.inc`, `ENGINE/vars_v3.inc` | **Generados** por `TOOLS/gen_vmtables3.py` (no editar) |
| `ENGINE/test/test_vm.cpp`, `build_test.sh` | Arnes v3: el mundo es `DATA.BIN`; compara con `vmmodel3.py scenarios-core` |
| `TOOLS/gen_vmtables3.py` | Tabla de despacho de 256 opcodes + especificaciones + `vars_v3.inc`, desde `scumm3dis.py` |
| `TOOLS/scumm3dis.py` | Nuevo: `SPEC` (lectura de operandos como datos), `run_spec` y la orden `spec` (la comprueba contra el `Decoder`) |
| `TOOLS/vmmodel3.py` | Nuevo: `CoreVM` (modo nucleo), `run_scenario_core`, `make_scenarios_core`, orden `scenarios-core`; base de cada ranura en la traza |
| `TOOLS/vmcommon3.py` | Limites del Z80 en el modelo: 256 variables, 16 locales, 24 ranuras, 32 argumentos, pila de 32 |
| `TOOLS/pack_data3.py` | D5: paginas solapadas para los scripts grandes |

Los demas `.asm` de `V3/ENGINE` son la copia de v2 sin tocar (`scumm.asm`, `game.asm`, `input.asm`, `hr.asm`, el overlay A...; `walk.asm` y `geom.asm` son de v3 desde la fase 6 y van en el overlay D: `scumm.asm` no debe incluirlos):
las fases 4-9 los pasan a v3. **`scumm.asm` de v3 todavia no ensambla** con el nucleo nuevo (usa la capa de juego de v2); lo arregla la fase 5.

## Resultado

- **Trazas:** `build_test.sh` con todas las salas y 1 semilla: ****1.485 escenarios, 1.485 iguales, 0 distintos** (88 salas, 232 scripts locales, los verbos de los objetos, 129 scripts globales y 3 de D5; 40.009 fotogramas, 271.887 instrucciones de script; 8 acaban en un error que el Z80 da igual, y 3 sin presupuesto se descartan)**.
- **Residente:** el nucleo ocupa **`$4200-$512F` (3.887 B)**; tablas `$8000-$869F` (1.695 B); overlay B 286 B.
- **Despachador:** ****164 T** desde `es_loop` hasta la primera instruccion del manejador, **194 T** con lo minimo de vuelta (`ld (SPTR),de` + `ret`); v2: 600-700** (ver "Medidas").
- **D5:** resuelta (abajo), probada con los escenarios `cbig095.*` (el script 95 llega al offset 5.935 y cruza la frontera de 4 KB en los dos sentidos).
- **v2 sin regresiones:** `V2/ENGINE/test/build_test.sh` con Maniac (por omision): 2.912 escenarios iguales. Con Zak (`build_test.sh "../../Zak McKracken"`) el modelo de Python de v2 se para con `ValueError: operando J en el anfitrion` (`V2/TOOLS/vmmodel.py`, `host_op`): es **anterior a esta fase** (no hay ningun cambio en `V2/TOOLS`, y en `V2/ENGINE` solo los de la fase 0 en `README.md` y `test_scumm.cpp`, que `build_test.sh` no usa).

## Mapa de memoria de v3

Espacio del Z80 (bloques de 8 KB; el puerto `$E7` pone una pagina fisica en un bloque):

| Direcciones | Que hay |
|---|---|
| `$0000-$1FFF` (bloque 0, solo lectura) | Overlay A (pagina 50) casi siempre; overlay B (pagina 49) mientras corre uno de sus manejadores (`call_ovb`); la pagina fria `TABPG` (15) un momento en `cold_rd` |
| `$2000-$37FF` (bloque 1) | Ventana de datos: la pagina de `DATA.BIN` del script en curso (6 KB). `$3800-$3FFF`: tabla de caracteres (copia en cada pagina) |
| `$4000-$41FF` | Sistema del ZX81 |
| `$4200-$7FFF` | **Residente (codigo)**: 15.872 B. Nucleo de la fase 3: `$4200-$512F` |
| `$8000-$9FFF` (bloque 4) | Tablas del nucleo (`tables3.inc`: `$8000-$869F`) y variables del programa como en v2 (`SV`, interfaz, pila `$8A00-$8AEF`, `BACKBUF`, mensajes, glifos). `ODIRBUF` de v2 (`$8B00-$9484`, 2.436 B) desaparece: el ODIR de v3 va en la pagina fria. **Fase 4a:** actores (13 x 64 B) en `$8B00-$8E3F` y nombres nuevos de `setObjectName` en `$8E40` (250 B): quedan ~1,4 KB de ese hueco. **Fase 4b-1:** nombres de actor `ACTNAMES` (`$8F3A`, 13 x 3 B), verbos `VERBS` (`$8F61`, 36 x 18 B) y el monton de cadenas `STRHEAP` (`$91E9`, 480 B): **quedan 187 B** (`$93C9-$9483`) |
| `$A000-$BFFF` (bloque 5) | Bitmap HiRes y bufers de `hr.asm`, como en v2 |
| `$C000-$DFFF` (bloque 6) | Atributos HiRes, cache de sprites (`ACSIG`), como en v2 |
| `$E000-$FFFF` (bloque 7) | **Estado de la VM** (abajo) |

Bloque 7 (fijado en la fase 3; las direcciones estan en `vm_core.asm`):

| Direccion | Bytes | Que |
|---|---:|---|
| `$E000` VARS | 512 | 256 variables de 16 bits. Tiene que estar en `$E000` (`rd_var`: `ld h,$70 / add hl,hl`) |
| `$E200` OBJST | 1.000 | estado de cada objeto |
| `$E5E8` OBJOWN | 1.000 | dueno |
| `$E9D0` RBLOB | 1.536 | **fase 5:** copia del blob de la sala en uso (cajas, matriz de cajas y objetos, tal cual `pack_data3.room_blob`). Sustituye a OBJCLS (ver "Fase 5") |
| `$EFD0` SENTN, SENTQ | 43 | **fase 5:** cola de frases: cuantas hay y 6 x 7 B (verbo, a, b, preposicion, congelada) |
| `$EFFB` RESMAP | 128 | **fase 5:** `_resourceMapper` (pseudoRoom): sala de cada clave 0x80-0xFF (0 = sin asignar) |
| `$F07B` RMV | 11 | **fase 5:** `OBJP`, `OBJEND`, `NROBJ`, `MATP`, `CLSSV`, `ODTMP` (variables de la sala). Hasta `$F085` |
| `$F086` WKX... | 294 | **fase 6:** `WKX`, `WKY`, `WKDIR`, `WKBOX` (argumentos de las entradas del overlay D), `ROOMRES`, `P3Y` (13 palabras: `walkdata.point3.y`) y `GW` (260 B de trabajo de `geom.asm` y `walk.asm`). Hasta `$F1AB`; **`$F1AC-$F587` libres (987 B)** |
| `$F588` SCRDIR | 600 | scripts globales: pagina, direccion (pagina 255 = grande, la direccion es el indice en BIGDIR) |
| `$F7E0` BIGDIR | 32 | scripts grandes (D5) |
| `$F800` SLOTS | 384 | 24 ranuras de 16 bytes |
| `$F980` LOCALS | 768 | 16 locales por ranura |
| `$FC80` NEST | 60 | pila de ranuras (15) |
| `$FCC0` CUTDATA, CUTPTR, CUTSCR, CUTPG | 30 | pila de cutscenes (5): dato, puntero de override (con su pagina), ranura |
| `$FD00` ARGS | 64 | argumentos del decodificador generico (32) |
| `$FD40` VARARG | 32 | `getWordVararg` (16) |
| `$FD60` ESTK | 128 | pila de `expression` (32 x 32 bits) |
| `$FDE0` VMV | 99 | variables del nucleo (CUR, SPTR, OPC, RESV, CURRD: la entrada de ROOMDIR de la sala...) |
| `$FE43` | 193 | **fase 4a:** sucesos (`EVID`, `EVARGS`, `EVVEC`), camara, `_screenStartStrip`, estado del mensaje, `last_sound`, `NBOXES`, inventario (`INVSL`, 80 x 2) y 24 B de temporales de B (`SC`) |
| `$FF1C` | 106 | **fase 4b-1:** `USERPUT`, `CURSTATE`, `MAINTOP`, `MAINH` (palabras), `STRLEN` (32 B), `STRPOS` (32 palabras) y `STREND` |
| `$FF86` | 62 | **fase 4b-2:** `STRSL` (4 x 11: valores por omision de las ranuras de texto de `print`), `WRK` (11: copia de trabajo), `MSGPTR`, `MSGCNT`, `MSGEND` (palabras) y `CHARCOL` |
| `$FFC4-$FFFF` | 60 | **libre** |

Pagina fria `TABPG` = pagina fisica 15 (8 KB, la carga el cargador; `cold_rd` la lee por el bloque 0): ROOMDIR (100 x 32) en +0, ODIR (1.000 x 3) en +3.200,
OBJROOM (1.000) en +6.200, COSTDIR y COSTDIR2 (129 x 3) en +7.200 y +7.587 (7.974 B). Son las tablas que se leen al cambiar de sala, arrancar un script de objeto, recoger o
cambiar de traje; las de cada instruccion (estado, dueno, clases, SCRDIR) estan en el bloque 7.

Ranura (16 bytes): `+0` estado (bit 7 congelada), `+1` donde, `+2` numero, `+4` pagina, `+5` puntero, `+7` retardo (32 bits con signo), `+11` banderas (bit 5 freezeResistant,
bit 6 recursive, como en el opcode de `startScript`), `+12` freezeCount, `+13` cutsceneOverride, `+14` grande (indice + 1 en BIGDIR), `+15` didexec.

Paginas fisicas: 0-7 la memoria base; 8-14 la sala (`hr.asm`; la 79 pide 7); **15 tablas frias**; 16-62 cache de paginas de datos (`dp_cache.inc`) **menos la 46 (overlay D, fase 6), la 47 (OBJCLS, fase 5), la 48
(overlay C), la 49 (overlay B) y la 50 (overlay A)**: la fase 9 tiene que quitar la 46, la 47, la 48 y la 49 de la cache (`DP_OVLIDX`); 63 depurador.

### Lo que queda por colocar (fases 4-8)

(Actualizado en la fase 4b-1: los verbos, las cadenas y los nombres de actor ya estan colocados, ver arriba; en el hueco quedan 187 B y en el bloque 7, 122 B. Lo que falta de la tabla de abajo sigue pendiente: la fase 5 tendra que mover OBJCLS a una pagina fria.)

v2 tenia en el bloque 7 los actores (`$EF00`), ROOMDIR, el bufer de mensajes, `GSCR`, el blob de sala, la cola de frases y COSTDIR. En v3 ROOMDIR y COSTDIR van a la pagina
fria y el resto tiene que ir al hueco de `ODIRBUF` del bloque 4 (2.436 B) y a lo libre del bloque 7 (445 B):

| Que | v2 | v3 (estimado) |
|---|---:|---:|
| actores (13) | 1.200 (25 x 48) | ~830 (13 x 64) |
| blob de sala (cajas, matriz, objetos) | 1.024 | 1.536 (el mayor de Indy3 mide 1.496) |
| bufer de mensajes | 320 | 320 |
| `GSCR` (geometria) | 192 | 192 |
| cola de frases, `GD_*`, `CO_*` | ~100 | ~100 |
| inventario (80 objetos; el codigo es el OBCD del ODIR, sin copia) | 96 | 160 |
| verbos (`verbOps`), cadenas (`stringOps`), nombres nuevos | ~280 (v2: nombres) | ~900 |
| **total** | | **~4.000** frente a ~2.880 libres |

No cabe todo: si al pasar la capa de juego falta sitio, lo siguiente que va a una pagina fria es OBJCLS (3.000 B; `setClass` e `ifClassOfIs` son ~2 % de las instrucciones;
`findObject` mira la clase de cada objeto de la sala). Pagina candidata: la 48 (se quita de la cache). Lo decide la fase 5.

### Residente (codigo): sitio para las fases 4-8

Nucleo de la fase 3 por partes (bytes): entradas y API 319, bucle y D5 184, operandos y variables 354, errores y paginas 101, ranuras/scripts/freeze/cutscene 1.124,
decodificador generico 508, anfitrion 54, aritmetica de 32 bits 279, manejadores nativos 935. Total 3.887.

| Pieza (de v2) | v2 | Destino en v3 |
|---|---:|---|
| nucleo | 2.502 | residente: 3.887 (hecho) |
| `mcu.asm` | 172 | residente |
| `loader.asm` + `dp_cache.inc` | 861 | residente (+ tablas nuevas y la pagina fria) |
| `scumm.asm` (arranque, bucle, texto) | 1.899 | residente |
| `hr.asm` | 1.749 | residente (+ alto variable de la sala) |
| `game.asm` (mensajes, sonido, cambio de sala) | 1.940 | residente |
| `input.asm` (entrada, frases, verbos, inventario) | 2.347 | **overlay B** (frase) y overlay A (interfaz) |
| `geom.asm` + `walk.asm` | 4.334 | residente lo de cada fotograma; la busqueda de rutas puede ir a B |

Libre tras el nucleo: **11.985 B** (`$5130-$7FFF`). Lo de arriba sin `input.asm` suma ~11.000 B: queda ~1 KB de margen, asi que la regla para las fases 4-8 es: **todo
manejador nuevo va al overlay B** salvo que sea de cada instruccion o de cada fotograma. Overlay B: 286 B usados de 8.192 (fase 3); **fase 4b-1: residente hasta `$51ED` (11.795 B libres), overlay B 6.656 B (1.536 libres)**. Overlay A (v2): 5.939 de 8.192.
**Fase 4b-2: residente hasta `$5392` (11.374 B libres: +421 B, de ellos 320 son `MSGBUF`) y overlay B casi lleno: el codigo acaba en `$1D08` y la tabla `ovb_lo`/`ovb_hi` (alineada a 256) ocupa `$1E00-$1FFF`; quedan 248 B. La fase 5 necesita otro sitio para sus manejadores (otro overlay, o mover a una pagina fria lo que se pueda): se avisa en `PLAN.md`.**

## Decisiones

- **Despachador:** `es_loop` (vm_core.asm) coge el opcode y salta por `disp_lo`/`disp_hi` (dos tablas de 256 alineadas: `ld l,a / ld h,disp_lo/256 / ld c,(hl) / inc h /
  ld b,(hl)`). El manejador lee sus propios operandos (los nativos) o llama a `decode` (los demas). Ya no se interpreta una especificacion en cada instruccion: eso era lo caro de v2.
- **Errores:** `vm_err` vuelve con la pila de la entrada de la API (`TOPSP`): un error es fatal y no hace falta mirar `ERR` en cada instruccion.
- **Operandos:** `DE` es el puntero del script mientras se leen; los lectores devuelven en `BC`. `rd_var`: si el byte alto de la palabra es 0 (variable 0-255 sin banderas) son
  ~90 T; si no, `rv_index` (0x2000: otra palabra, que puede ser a su vez una variable), bit de una variable (0x8000), local (0x4000, 0-15) o error (`E_RANGE`).
  `rd_res`/`set_res` para el resultado (RESV, con su indireccion). `rd_vararg` para las listas.
- **Locales:** 16 por ranura, en `LOCALS` (no en el registro de la ranura). `start_slot` copia los `VACNT` valores de `VARARG` y pone el resto a 0 (regla: quien arranca una
  ranura deja `VACNT`; `start_slot` lo vuelve a 0).
- **didexec** se pone al cargar la ranura (`load_slot`), no en cada instruccion: es equivalente (una ranura cargada ejecuta al menos una instruccion).
- **Decodificador generico:** `decode` interpreta la especificacion de `scumm3dis.SPEC` (fichas en `tables3.inc`, incluidas las listas de subopcodes de `actorOps`, `verbOps`,
  `roomOps`, `print`...). Lo usan los manejadores del anfitrion ahora y lo pueden usar los de las fases 4a/4b que prefieran `ARGS` (como en v2).
- **Limites (el modelo usa los mismos, `vmcommon3.py`):** 256 variables (ScummVM 800; Indy3 usa hasta la 253), 16 locales (Indy3 usa hasta la 15 y listas de 7), 24 ranuras
  (ScummVM 80; maximo medido 17), 32 argumentos de anfitrion (maximo de Indy3: 22), pila de `expression` de 32. Fuera de ellos, error.
- **Palabra de variable en 16 bits:** el indice de 0x2000 se suma en 16 bits (el modelo hace `& 0xFFFF`); ScummVM suma en 32 y solo difiere en casos sin sentido.
- **Overlay B** en la pagina 49 (D4): `call_ovb` lo mapea en el bloque 0 y al volver deja lo que hubiera (se puede anidar: `expression` -> instruccion -> otro manejador de B).
  `exec_one` ejecuta una instruccion suelta (el caso 6 de `expression`).

### D5: scripts de mas de 6 KB (el 95, 6.707 B)

- `vm_core` lee los bytes del script en linea (`ld a,(de) / inc de` en los lectores), asi que comprobar el final de la ventana en cada byte saldria caro.
- **Solucion:** paginas solapadas. `pack_data3.py` pone la pagina k de un script grande con los bytes `[k * 4096, k * 4096 + 6144)` (el 95: paginas 24 y 25). Una instruccion
  que empieza en `[k * 4096, (k + 1) * 4096)` tiene todos sus bytes en la pagina k (la mayor de Indy3 mide 205 B; el solape es de 2 KB).
- `es_loop` comprueba, al empezar cada instruccion, que el puntero esta en la franja de su pagina con dos instrucciones (`sub $20 / cp limite / jr nc`, 21 T): el limite es `$18`
  (toda la ventana) y `$10` en una pagina de un script grande que no es la ultima. Fuera de la franja, `es_cross` calcula el desplazamiento logico `k * 4096 + (puntero - $2000)`,
  elige la pagina y sigue. En un script normal, salirse de la ventana es un error (antes no se notaba).
- Los saltos no necesitan nada: el destino se comprueba al empezar la instruccion siguiente. `beginOverride` guarda la pagina con el puntero.

## El modelo en modo nucleo (`vmmodel3.CoreVM`)

`CoreVM` es el modelo de la fase 1 con la frontera del Z80 de la fase 3: los opcodes de `CORE_OPS` (36) van como en `VM`; los demas salen al anfitrion como `H oo [args]`,
leidos con `scumm3dis.run_spec` (la misma especificacion que `decode`): argumentos en orden de lectura (subopcodes incluidos; R da el numero de variable resuelto; una cadena da
`str_value` de sus bytes en bruto; J no da argumento). Resultado simulado `s = mock_hash(opcode, args, fotograma)`: si la especificacion empieza por R, la variable recibe `s & 0xFF`;
si lleva J, salta cuando el bit 8 de `s` es 0.
Fotograma: temporizadores, `decreaseScriptDelay` y `runAllScripts`. Resumen: `D f= V=crc(variables) L=crc(locales) K=cut_sp,crc(pila de cutscenes) S=ranuras`, con el offset
de cada ranura desde el inicio de su bloque (script, script local, ENCD/EXCD u OBCD: lo que el Z80 tiene aparte).

Escenarios (`make_scenarios_core`): cada sala (`ROOM`, `ENTRY`, fotogramas, `ABORT`, `EXIT`), cada script local, cada verbo de cada objeto (`OBJ` con el OBCD del indice), cada
script global con argumentos al azar (y `ABORT`), y `cbig095.*` para D5. Parten de las variables del arranque (`boot_snapshot`, solo `SETVAR`).

## Formato del mundo del arnes

**El mundo es `DATA.BIN`** de `pack_data3.py` (el mismo fichero que lee la placa); `vmmodel3.py pack` y `world3.bin` ya no existen. El arnes pone las tablas calientes en el
bloque 7, las frias en la pagina 15, la pagina de datos v en la pagina fisica 128 + v (`vm.asm`: `map_page_x`) y `ovlb.bin` en la 49. Ordenes que entiende: `INIT`, `OPT` (se
ignora), `SETVAR`, `ROOM`, `SCRIPT n [args]`, `ENTRY`, `EXIT`, `OBJ`, `ABORT`, `FRAMES`, y tambien `OWNER`, `STATE` y `CLASS` (escriben las tablas). **Pendiente** (fases 5 y
7, cuando el Z80 tenga esas estructuras): `LOADROOM`, `PSEUDO`, `STRING`, `ACTOR`, `CLICK`, `RCLICK`, `KEY`, `ESC`, `SENTENCE`, `INPUT` (el arnes da `ERR 98`).

## Medidas

Con `TS_VM=1` sobre los 1.485 escenarios (T-estados del Z80; cada instruccion desde la comprobacion de `CUR` en `es_loop` hasta que el manejador vuelve, sin las anidadas):

- **Coste fijo del despachador: 164 T** hasta el manejador (`es_loop` 22 + `es_go`...`ret` 142: puntero, franja de D5, opcode, tabla partida, `push`/`ret`) y **194 T** con la
  vuelta minima. El objetivo era <= 400; v2 gastaba 600-700 (prologo, tabla de 4 bytes y la especificacion interpretada en cada instruccion).
- Por instruccion, v3 frente a v2 (fase 0, Zak): `jumpRelative` **245** (686), `breakHere` **350** (678), `stopObjectCode` 346, `wait` 271, `move` **614** (1.213), `isEqual`
  **797** (~1.360), `increment` **837** (957), `getRandomNr` **933** (1.567), `equalZero` 526, `notEqualZero` 454, `delay` 509, `isLess` 731, `add` 1.008, `subtract` 1.044.
- Caros: `startScript` 7.552 exclusivos (recorre las 24 ranuras en `stop_script` y las vuelve a recorrer al buscar una libre; copia los locales, `run_nested` y la vuelta al
  padre), `cutscene` 7.527, `expression` 7.963 (overlay B, con las instrucciones anidadas y la aritmetica de 32 bits). Es lo primero que mirar en la fase 10.
- Media de todas: 1.130 T, mediana 1.008, p90 1.082, p99 7.285. La mediana no vale como cifra tipica: el 75 % de las instrucciones son tres bucles de espera (`isEqual`,
  `add`, `subtract` sobre locales) de escenarios con resultados simulados del anfitrion. Con el coste fijo de 194 T, una instruccion de una variable y una palabra
  (`isEqual`, `move`) queda en 600-800 T: ~2 veces menos que v2.
- El arnes: 260 instrucciones del Z80 por instruccion de script de media.

## Fase 4b-2: mensajes (`print`, `printEgo`)

Todo en `ENGINE/ovb4c.asm` (overlay B) salvo `talk_frame` y el bufer, que van en el residente (`vm_core.asm`). Semantica: `vmgame3.py` (`convert_message_to_string`, `actor_talk`,
`display_dialog`, `print_string`) y `vmmodel3.py` (`decode_parse_string`).

- **Donde corre displayDialog:** el residente solo tiene `talk_frame` (llamada desde `vm_frame` tras `decrease_delay`, ~45 B): resta el `delta` a `talk_delay` (palabra con signo, minimo 0) y,
  si hay mensaje (`HAVEMSG` <> 0) y no queda espera, entra en el overlay B por `OVB_DD` (+6 de la tabla de entradas de B; `call_ovb`). Sin mensaje cuesta **75 T** (133 con `talk_delay`), con
  mensaje esperando 198 T de media; `displayDialog` entero (escribir una linea) hasta ~4.000 T. Despues `vm_frame` copia `HAVEMSG` a `VAR_HAVE_MSG` (el `update_scumm_vars` del modelo).
  El programa de la placa (fase 5) tiene que llamar a `talk_frame` con A = delta (tope 15) en su bucle, antes de `runAllScripts`, y copiar `HAVEMSG` a `VAR_HAVE_MSG`.
- **MSGBUF** (el mensaje convertido): 320 B en el residente (`MSGBUF: defs MSG_MAX` al final de `vm_core.asm`, `$524D-$538C`), no en una direccion fija: va con el codigo y cuenta en sus 32 KB.
  Lo mas largo de Indy3 son 205 B de instruccion, y la conversion expande poco. La pila del arnes baja desde `$7FF0`, el stub del anfitrion esta en `$4100` y la trampa en `$7FFC`: no se tocan.
  El estado de `print` (valores por omision de las 4 ranuras de texto, copia de trabajo, `MSGPTR`, `MSGCNT`, `MSGEND`, `CHARCOL`) esta en el bloque 7 (`$FF86-$FFC3`).
- **Limites del Z80 que el modelo hace suyos** (`vmcommon3.py`): `MSG_MAX` = 320 (el contenido convertido mide < 320; mas: `E_RANGE`), `MSG_DEPTH` = 4 (verbo, nombre o cadena dentro de otro; mas: `E_RANGE`),
  una variable de mensaje con 0x2000 da `E_RANGE` (ScummVM leeria el indice del script), el color de `print` y de las ranuras es de un byte, `talk_delay` de 16 bits con signo, una fuente
  (cadena, nombre) se lee con ceros mas alla de su final y el bufer del mensaje tambien (un `$FF 10` que salta mas alla del final acaba el mensaje en vez de leer basura).
- **Conversion** (`convert_all`, `cm_run`, `emit_a`): recursiva (`cm_nest`), escribe byte a byte en `MSGBUF` (`CM_LEN` es el contador; ya sin puntero de destino) o, con la ranura 1 (texto
  suelto, que no debe pisar el mensaje que se esta escribiendo), solo suma bytes y longitud (`CM_MODE` = 1). Las fuentes anidadas: el nombre de un verbo, de un actor o de un objeto con nombre
  nuevo estan en la pagina del script que los puso (`cm_nest` pone esa pagina en la ventana de datos y la devuelve; se vuelve a la pagina de la ranura en curso por `map_page`, no por el numero
  fisico: asi vale con la cache de paginas); las cadenas, en `STRHEAP` con su longitud como limite (`CM_REM`).
  **FASE5:** el nombre de un objeto que no es un actor ni tiene nombre nuevo (`FF 6`, OBCD del inventario o de la sala) sale vacio (`CoreVM.get_obj_or_actor_name`, igual en los dos).
- **Ranuras de texto:** `print` lee sus subopcodes (0, 1, 2, 4, 6, 7, 15, `$FF`; el resto `E_BADSUB`) sobre `WRK`, copia de los valores por omision de la ranura; la 0 es `actor_talk`, la 1 un
  suceso `E 5 [1, x, y, color, center | overhead * 2, valor]`, la 2 y la 3 no hacen nada. El resumen del modelo (`M=`, y `X=` nuevo con `use_talk_anims`, `msg_count`, la posicion en el bufer,
  `charset_color`, el crc del bufer y el de los valores por omision) lo calcula igual el arnes.

### Overlay C (abierto el 2026-11-14)

B se quedo con 248 B libres tras la 4b-2, asi que se abrio un segundo overlay para lo que viene (fase 5). **Pagina fisica 48** (D4 reservaba 49 y 50; la 48 era la candidata a pagina fria de `OBJCLS`: si
hace falta, va a la 47). **La fase 9 tiene que quitar tambien la 48 de la cache de paginas** (`DP_OVLIDX`, como la 49).
- Mecanica: `call_ovc` (residente, copia de `call_ovb` con `OVC_PAGE`) y `h3_ovc` (`ld hl,OVC_OP / jp call_ovc`); `ovlc.asm` tiene un solo punto de entrada (`jp ovc_op` en +0) que reparte por el opcode con
  `ovc_lo`/`ovc_hi`. `gen_vmtables3.py`: `OVC_HANDLERS` (etiquetas `b_<nombre>` en `ovc1.asm`); los de esa lista dejan de ser de B (`OVB` los excluye) y su entrada en `disp_lo/hi` es `h3_ovc`.
- **Un overlay no puede llamar a rutinas de otro** (solo uno esta en el bloque 0): lo que C necesite de B va por `call_ovb` con la direccion de B (`ovlb.sym`), o se copia (`ovc1.asm` lleva su `sless`), o sube al
  residente. Ejecutar un manejador de C desde B (o al reves) si se puede anidar, como `expression`.
- Salieron de B a C: `roomOps`, `resourceRoutines`, `lights`, `systemOps`, `saveLoadGame` (`saveLoadVars` se queda en B: usa `scan_len` y `str_ptr`). Resultado: **B 7.680 B, con ~680 libres; C 1.024 B (casi todo vacio)**;
  residente `$4200-$53A8` (+22 B: `call_ovc` y `h3_ovc`; 11.352 B libres).
- Arnes: `test_vm.exe` admite `ovlc.bin` como 7.o argumento (pagina `OVC_PAGE`); `build_test.sh` y `mutaciones.py` lo ensamblan.

## Fase 5: salas, objetos y frases (2026-11-14)

Todo en `ENGINE/ovc5.asm` (overlay C, incluido desde `ovlc.asm`) salvo lo del residente (`vm_core.asm`) y unos retoques de B. Semantica: `vmgame3.py` (`start_scene`, `find_object`, `do_sentence`,
`check_and_run_sentence_script`...) y `vmmodel3.CoreVM` (los 12 opcodes en `CORE_OPS`; `o_loadRoom`, `o_loadRoomWithEgo`, `o_doSentence`, `o_drawObject`, `o_pseudoRoom`, `o_findObject` propios de
`CoreVM`).

### Decision de colocacion: OBJCLS a la pagina fria 47
- El blob de la sala (el mayor de Indy3 mide 1.496 B) no cabia en el hueco de `ODIRBUF` (187 B) ni en el bloque 7 (60 B). Se movio **OBJCLS (3.000 B)** a la **pagina fisica 47** (3 bytes por objeto desde
  el principio de la pagina; el arnes la llena desde `DATA.BIN` y la fase 9 tiene que cargarla y quitar la 47 de la cache; como todas las paginas de datos, lleva la copia de la tabla de caracteres en
  `$3800-$3FFF` de la pagina). En su sitio (bloque 7, `$E9D0-$F085`): `RBLOB` (1.536 B), `SENTN/SENTQ` (43 B), `RESMAP` (128 B) y `RMV` (11 B); **quedan 1.282 B libres** (`$F086-$F587`).
- **Acceso:** las clases se tocan por el bloque 1 (la ventana de datos): `cls_open` guarda la pagina que hay (`CLSSV`) y mapea la 47; `cls_ptr` da `$2000 + 3 * objeto`; `cls_close` devuelve la
  pagina. Entre `cls_open` y `cls_close` no se lee el script ni se mapea otra pagina de datos (si se pueden llamar overlays: solo mueven el bloque 0). Cuesta ~170 T por acceso; `setClass`,
  `ifClassOfIs` y `getClass`/`putClass` de B, `actorFromPos`, `findObject` (una sola apertura para todo el bucle) y `pickupObject` lo usan.
- **Lo que gano el residente (~360 B, `$421E-$550E`; 10.994 B libres hasta `$8000`):** las rutinas que ahora usan B y C a la vez salieron de B: `cls_*`, `obj_index`, `inv_find`, `wio`, `odir`
  (`BC` = objeto -> pagina y direccion del OBCD en `ODIR`), `run_inv0/run_inv`, `restore_win` (devuelve la ventana a la pagina del script en curso), `actor_ix`, `chk_actor`, `actor_num`, `in_room`, `is_act13`.
  Mas la API (`vm_load_room` en +24 y `vm_sentence` en +27: el arnes) y la cola de frases en `freeze_scripts`/`unfreeze_scripts`/`vm_frame`.
- **Overlay C:** 3.840 B de 8.192 (4.352 libres). **B:** 7.680 B (512 libres; los helpers que salieron compensan los cinco puntos de entrada nuevos). Entradas fijas de C (`vm.asm`): `OVC_OP` (+0), `OVC_SENT` (+3,
  `checkAndRunSentenceScript`), `OVC_START` (+6, `startScene`, C = sala), `OVC_ROOM` (+9, `load_room_state`, C = sala, B = 1 con cajas) y `OVC_SENTADD` (+12). Entradas fijas de B para C: `OVB_STOPTALK` (+9),
  `OVB_HIDE` (+12, IX = actor), `OVB_SHOWACT` (+15), `OVB_FOLLOW` (+18, IX = actor, `setCameraFollows`) y `OVB_PUTACT` (+21, IX = actor, C = sala, x en `SC+0`, y en `SC+2`).

### Estado de la sala y objetos
- `load_room_state` (C): `CURRD` = su entrada de `ROOMDIR` (ceros si no existe), `RBLOB` = su blob (`ldir`; ~31.000 T con el blob mas grande), `OBJP`/`OBJEND`/`NROBJ` (los registros de objetos de 14 B: id, x/8, y/8,
  ancho/8, alto/8, padre, estado del padre, x e y de acercamiento (s16), direccion, banderas), `MATP` (la matriz de cajas, para la fase 6) y `NBOXES`. `obj_index` recorre de arriba abajo (getObjectIndex).
  `ROOM n [1]` del arnes (`vm_set_room`) carga solo esto (con cajas si hay un 1); `startScene` lo carga siempre con cajas.
- **El inventario no copia el OBCD:** el codigo de un objeto del inventario es su bloque de `ODIR`, igual que el de uno de sala (en Indy3 ningun objeto esta en dos salas: `pack_data3` lo comprueba). El modelo
  (`CoreVM.obcd_of`, `add_object_to_inventory`) hace lo mismo. Un objeto en `INVSL` sin OBCD en `ODIR` da E_BADOBJ en `getVerbEntrypoint`/`startObject` (modelo y Z80).
- **Nombres de objeto** (`FF 6`): `cm_name` (`ovb4c.asm`) mira primero los nombres nuevos de `setObjectName` y despues el del OBCD (inventario o sala): `ODIR` + el byte `+16` del bloque. Los nombres de Indy3 no
  llevan codigos `FF`; el unico con caracteres de control es el del objeto 403 (`IndyWear\x10\x11 by Lucasfilm`).
- **`startScene`** (`ovc_start`), en el orden del modelo: recurso (`RESMAP` si la sala es >= $80), E_BADROOM si no existe, `stop_talk` (B), el script en curso se abandona si es de sala, local o de FLObject,
  `runExitScript` (VAR_EXIT_SCRIPT, `EXCD`, VAR_EXIT_SCRIPT2), `killScriptsAndResources` (las ranuras de sala/local/FLObject mueren **conservando su numero**, como en el modelo, y se borran los nombres nuevos de objetos
  de la sala o sin dueno), actores 1..12 ocultos, VAR_ROOM/CURROOM/VAR_ROOM_RESOURCE, `load_room_state`, suceso `E 6 [sala]`, camara (VAR_CAMERA_MIN_X/MAX_X, modo normal, cur = dest = 160), `showActors` (B),
  `EGOPOS = 0` y `runEntryScript`. Con el recurso 0 acaba tras cargar (sin suceso, camara ni entrada). Todo lo que corre scripts guarda sus datos en la pila (`SC` no sobrevive).
- **`loadRoomWithEgo`:** la pila durante `startScene` es ego, direccion antigua, y, x, objeto; el `put_actor` y el `setCameraFollows` van por B (`OVB_PUTACT`, `OVB_FOLLOW`). `actorFollowCamera` con un actor
  fuera de la sala ya hace `startScene` (el salto al anfitrion de la fase 4a desaparece).

### Frases
- `SENTQ`: 6 entradas de 7 B (verbo, a, b, preposicion = b <> 0, congelada). `doSentence` (verbo $FE: vacia la cola y para el script de frases), `waitForSentence` y `checkAndRunSentenceScript` (en `vm_frame`, justo
  despues de `run_all`; si la cola esta vacia solo cuesta ~30 T). Los argumentos del script de frases son locales 0-2 (verbo, a, b). `freezeScripts` suma 1 a `freeze` de cada frase y `unfreezeScripts` lo resta.
  El estado en el resumen (`Q=` cuenta y crc de la cola) lo calcula igual el arnes.

### Prueba
- Modelo: `set_room_core` (`ROOM n [1]`), ordenes `LOADROOM n`, `SENTENCE v a b`, `PSEUDO k v` y `ACTORSET n sala x y traje visible ign`; resumen `Q=` y `R=` (cajas, objetos, `ego_positioned`, `RESMAP`).
  El arnes (`test_vm.cpp`) carga OBJCLS en la pagina 47, lee el ENCD de la sala en uso de `CURRD` y los scripts locales de su tabla.
- Escenarios nuevos: `clrm<sala>` (startScene desde otra sala, con actores que ignoran cajas), `csnt<sala>` (1-3 frases con objetos de la sala y el script de frases real de Indy3), `cfnd<sala>` (findObject sobre el centro de los objetos con estados al azar), `cbox<sala>.<k>` (isActorInBox con todas las cajas y el actor en puntos de interes), scripts globales y locales con la
  sala en uso (con o sin cajas) y `vmsynth3.gen_room5` (los 12 opcodes con operandos al azar y por variable, objetos de la sala, cajas reales y erroneas, salas validas, pseudosalas y erroneas).
  Aparte, `ENGINE/test/ibx_test.py`: 600 escenarios de `isActorInBox` con un punto al azar (dentro, cerca, lejos y con coordenadas extremas s16) y cajas de seis salas: iguales (la geometria usa productos de 32 bits con signo y modulo). `ENGINE/test/escenario.py NOMBRE` depura un escenario suelto.
- **T medidos** (`TS_VM=1`, 2.851 escenarios; media exclusiva con el despachador; entre parentesis, con los scripts que arrancan): `doSentence` 2.745, `startObject` 7.620 (36.291), `getVerbEntrypoint` 3.205,
  `drawObject` 8.628 (recorre los objetos de la sala dos veces), `pickupObject` 6.558 (89.693: el script de inventario), `findObject` 8.869, `isActorInBox` 3.215 (geometria de 32 bits: 4 aristas x 2 productos),
  `loadRoom` 49.052 (408.816: salida y entrada de la sala; casi todo es la copia del blob y los scripts), `loadRoomWithEgo` 71.496, `pseudoRoom` 881, `setBoxFlags` 940, `waitForSentence` 1.912
  (recorre las 24 ranuras). `checkAndRunSentenceScript` con la cola vacia cuesta ~30 T por fotograma (el `ld a,(SENTN) / or a / ret z` de `vm_frame`). Lo primero que mirar en la fase 10: `drawObject` y
  `findObject` (recorren todos los objetos de la sala con `rec_addr`, ~200 T por objeto) y la copia del blob de `loadRoom` (`ldir` de hasta 1.496 B = 31.000 T).
- **Limites del Z80 que el modelo hace suyos** (`E_RANGE`): ver `PLAN.md` (fase 5).
- **Fase 6 (hecha):** `adjust_xy`/`adjust_actor_pos` y `startWalkActor` ya no dan E_BADOP: ver "Fase 6" abajo.

## Fase 6: caminata (2026-11-14)

Modelo: `TOOLS/vmgame3.py` (la caminata de `GameMixin`, ya sin las versiones recortadas de `CoreVM`) y `vmmodel3.py` (`CORE_OPS` + `walkActorTo`, `walkActorToActor`,
`walkActorToObject`, `waitForActor`; `walkActors` al final del fotograma). Z80: **overlay D** nuevo (`ENGINE/ovld.asm` = `geom.asm` + `walk.asm`), los cuatro opcodes en el
overlay C (`ovc6.asm`) y lo de cada fotograma en el residente (`walk_frame`).

### Revision del modelo contra ScummVM (`actor.cpp`, `boxes.cpp`, `script_v5.cpp`, `script_v3.cpp`, `common/rect.h`)
Las funciones estaban transcritas pero sin revisar. Se han leido una a una contra ScummVM y esto es lo que cambio:
- **Aritmetica de C en la geometria.** `closestPtOnLine` y `compareSlope` trabajan con `int` de 32 bits que desbordan: el modelo usaba enteros de Python en parte de las
  cuentas. Ahora todo pasa por `m32`/`d32` (producto y division de `int`, con `wrap32`), y el resultado se guarda en un `Common::Point` (int16) antes de recortarlo al segmento.
- **`Common::Point::sqrDist`** (lo usa `getClosestPtOnBox`): si la diferencia en x o en y llega a 0x1000 devuelve 0xFFFFFF. El modelo sumaba los cuadrados sin tope.
- **Tipos de la caminata:** `xfrac`, `yfrac`, `xAdd`, `yAdd` son `uint16` y la posicion `int16`: las sumas de `actorWalkStep` dan la vuelta en 16 bits.
- **`Actor::setDirection`:** si la direccion no cambia no hace nada; si cambia y el actor tiene traje y esta en la sala, marca `_needRedraw` (el modelo solo ponia `_facing`).
  Afecta tambien a `animateActor` con "cambiar de direccion" (overlay B, `an_dir`).
- **`getNextBox`:** el WORKAROUND de la sala 46 mira el recurso de la sala (`_roomResource`), no `_currentRoom` (difieren con pseudosalas).
- **`startWalkActor`:** `abr.x`/`abr.y` son int16 (el destino se trunca antes de comparar) y `_facing` es uint16.
- Lo demas (`walkActor`, `calcMovementFactor` con `_facingXYratio` = 3 y el arreglo #1052, `actorWalkStep`, `remapDirection`/`updateActorDirection`, `findPathTowardsOld`, `getGates`,
  `adjustXYToBeInBox` con `_lastValidX/Y`, `checkXYInBoxBounds`, `inBoxQuickReject`, `walkActorToActor`, `o3_waitForActor`) coincidia con ScummVM.
- **No hay un ScummVM ejecutable con el que comparar posiciones**: la comprobacion es la lectura del codigo y que el Z80, escrito aparte desde ScummVM y el modelo, da las mismas
  trazas. Queda como riesgo para la placa (comparar a ojo con ScummVM en el pasillo y el castillo).
- **Lo que ScummVM deja sin definir se fija igual en el modelo y en el Z80:** division por cero en `closestPtOnLine` y velocidad 0 en `calcMovementFactor` (ScummVM se cuelga) =
  `E_RANGE`; `_stepX` mayor de 255 (velocidad y 255) = `E_RANGE`; `closest[]` de `getGates` sin candidato (C lo deja sin inicializar) = 0; la terna de la matriz de cajas no se lee
  mas alla del final de la matriz (ScummVM leeria lo que haya detras); `_targetFacing` fuera de 0..359 = `E_RANGE` (no pasa: sale siempre de `oldDirToNewDir`); una caja que no
  existe (`walkbox` de otra sala) = `E_RANGE` (ScummVM: `assert`). En v3 no hay `followBoxes` (la tabla de `actorOps` acaba en 20 = `ignoreBoxes`): un actor solo vuelve a seguir
  las cajas con `initActor` (`actorOps` 8).

### Overlay D (pagina fisica 46)
- B tenia 512 B libres, C 4.352 y el residente esta contado para lo que falta (`scumm.asm`, `hr.asm`, `game.asm`...): la caminata (4,4 KB) va en un overlay propio, **pagina
  fisica 46** (`OVD_PAGE`; **la fase 9 tiene que quitarla de la cache de paginas**, como la 47, la 48 y la 49). `call_ovd` (residente) es la copia de `call_ovc`.
- No tiene despacho por opcode. Entradas fijas (`vm.asm`): `OVD_WALK` (+0, `walkActors`), `OVD_ADJUST` (+3, `adjustXYToBeInBox`), `OVD_STARTWALK` (+6, `startWalkActor`) y
  `OVD_CALCMF` (+9, `calcMovementFactor(_walkdata.next)`). **Los argumentos y los resultados van en memoria** (`call_ovX` usa HL y A): actor en IX (D lo conserva), `WKX`, `WKY`
  (entrada y salida), `WKDIR` (direccion final; -1 = ninguna) y `WKBOX` (caja que devuelve `adjust_xy`).
- Quien entra: `walk_frame` (residente, al final de `vm_frame`: si hay sala en uso y algun actor de la sala tiene `_moving` distinto de 0, `OVD_WALK`; si no, ~940 T);
  `adjust_xy` del overlay B (`put_actor`, `show_actor`: ahora es solo la llamada a D) y `actorOps` 2 con el actor en movimiento (`OVD_CALCMF`); en el overlay C, `loadRoomWithEgo` con
  x distinto de -1 y los cuatro opcodes de `ovc6.asm` (`b_walkActorTo`, `b_walkActorToObject`, `b_walkActorToActor`, `b_waitForActor`: leen sus operandos en C).
- `box_addr` salio de C al residente (lo usan B, C y D). `adjust_actor_pos` (B) ya gira al actor en las cajas con direccion fija (`banderas & 7`).
- **El programa de la placa (fase 9)** tiene que: cargar `ovld.bin` en la pagina 46, repetir los `OVD_*` de `vm.asm`, y llamar a `walk_frame` despues de
  `checkAndRunSentenceScript` (ya esta dentro de `vm_frame`). `moveCamera` y `updateObjectStates`, que en ScummVM van justo despues de `walkActors`, siguen sin estar en el nucleo.

### Memoria (bloque 7, tras `RMV`: `$F086-$F1AB`, 294 B; **quedan 987 B libres**, `$F1AC-$F587`)
`WKX`, `WKY`, `WKDIR` (palabras), `WKBOX`, `ROOMRES` (recurso de la sala cargada, lo pone `load_room_state`: el WORKAROUND de la sala 46), `P3Y` (13 palabras:
`walkdata.point3.y` de cada actor, que no cabe en su registro de 64 B; `point3.x` si esta, en `A_P3X`) y `GW` (260 B de trabajo de `geom.asm` y `walk.asm`: nada sobrevive a otra
entrada en D). `vm_init` los pone a 0. El registro del actor no cambia (`Actor.pack()`).

### Geometria (`geom.asm`)
- `cplin` (`closestPtOnLine`): trabaja siempre con el eje mayor `u` (x si |lx| > |ly|; si no, y, cambiando x por y en los tres puntos: las formulas de C son simetricas porque el
  producto de `int` es conmutativo) y el menor `v`: con `lv` = 0 (segmento vertical u horizontal) `ru = pu`, `rv = sv`; si no, la formula general sobre **una pila de valores de
  32 bits** (`gpush16/32`, `gpop32`, `gadd`, `gsub`, `gmul`, `gdiv`), y despues el recorte al segmento a lo largo de `u`.
- `smul`: signo aparte y `mul16u` si los dos caben en 16 bits (8 vueltas si uno cabe en un byte), si no `mul32` del residente. `sdiv`: signo aparte y tres casos: divisor de
  16 bits (dos divisiones 32/16 de 16 vueltas en registros), divisor de 17 a 31 bits (el cociente cabe en 16 bits: 16 vueltas) y divisor 2^31. No usa `div32s` (12.000 T).
- `cslope` (`compareSlope`): diferencias con signo y modulo (`sdiff`), producto con `mul16u` y comparacion de los dos productos de 32 bits con signo.
- `cxb` (`checkXYInBoxBounds`, punto en `BP`, caja en IY), `cxb_num` (con el numero de caja: `$FF` = no; sin cajas, `E_RANGE`), `qrej` (`inBoxQuickReject`, con la suma saturada),
  `cpb` (`getClosestPtOnBox`: distancia de 32 bits, devuelta saturada a 16), `gates` (`getGates`), `fpo` (`findPathTowardsOld`), `gnb` (`getNextBox`: carry = sin camino) y
  `adjust_xy`. El overlay C conserva su `check_xy_box` de la fase 5 para `isActorInBox`.
- Las clases del actor (jugador, volteo en x y en y: bits 6, 2 y 1 del tercer byte) se leen con `actor_cls` (`cls_open`/`cls_close`).

### Caminata (`walk.asm`)
`start_walk`, `walk_actor`, `cmf` (`calcMovementFactor`: divisiones de 16/8 bits; `|dy| * 3 > |dx|` se hace como `|dy| > |dx| / 3`), `walk_step` (`actorWalkStep`; los ejes x
e y comparten rutina porque en el registro del actor los campos de y estan 2 bytes despues de los de x), `upd_dir` (`remapDirection` + `updateActorDirection`), `w_set_dir`,
`w_turn_to`, `w_start_anim` (copia de la de B) y `ovd_walk`.

### Prueba
- **Escenarios nuevos** (`make_scenarios_core`): `cwlk<sala>.<k>` en todas las salas con cajas (3 por sala; 12 en el pasillo (1), Venecia (15) y el castillo (20 y 28)). Dos de cada
  tres son de **clics**: el ego se coloca en la sala y recibe de 3 a 7 `walkActorTo` (lo que hace el script de verbos con un clic en la sala) a puntos dentro de las cajas, cerca de
  sus esquinas o fuera, unos antes de llegar y alguno repetido, con todos los fotogramas en la traza. El tercero mezcla hasta 3 actores con `walkActorToActor`,
  `walkActorToObject`, `waitForActor`, `putActor`, `putActorInRoom`, `actorOps` (traje, velocidad, `ignoreBoxes`, `initActor`, fotogramas), `setBoxFlags` (cajas invisibles,
  cerradas, con direccion fija o volteadas), `setClass` (jugador, volteos) y `animateActor`. `vmsynth3.gen_walk` mete lo mismo en los sinteticos, con coordenadas s16 extremas.
- **El resumen lleva `G=`**: `n:x,y,caja,moving` de cada actor de la sala en uso (la traza de posiciones; el arnes la saca de `ACTORS`).
- En el modelo, 183 de 200 escenarios de clics acaban con el ego en su destino; los 17 que no, piden una caja que la matriz no conecta (p. ej. las dos zonas de la sala 20).
- Arnes: `test_vm.exe` carga `ovld.bin` (8.o argumento, o el que este junto a `ovlc.bin`); con `TS_VM=1` mide `walk_frame` por clases y con `TS_PD=1` saca el perfil del overlay D por
  etiqueta. `mutaciones.py` ensambla tambien el D y sus salas por omision son `1,15,20` (**borrar `build/mut/expected.txt` si cambia el modelo**: no se regenera solo).

### Cifras (2026-11-14)
- **Trazas: 3.492/3.492 iguales** (`build_test.sh`, 88 salas, 1 semilla: los de la fase 5 mas 300 escenarios `cwlk` y `gen_walk` en los 1.200 sinteticos). Aparte, `ENGINE/test/wlk_test.py`:
  600 escenarios de caminata con coordenadas extremas (s16, 4095/4096, +-6.000) iguales, e `ibx_test.py` de la fase 5 sigue igual.
- **Mutaciones** (`mutaciones.py`, salas `1,15,20`): **120 de 126 detectadas**; de las 49 de la caminata, 48. Sin detectar: las 5 de las fases anteriores y `getGates: |d0 - d1| < 2`
  (con las cajas de Indy3 de esas salas, las distancias entre los puntos de una puerta son iguales o difieren en mas de 3: el umbral 4 no se distingue de 2).
- **Tamanos:** residente `$421E-$5578` (**10.888 B libres** hasta `$8000`; +106 B: `call_ovd`, `box_addr`, `walk_frame`); overlay B 7.680 B (codigo hasta `$1BCB`; 512 libres tras la
  tabla); overlay C 4.096 B (codigo hasta `$0D1E`; **4.096 libres**); **overlay D 4.392 B de 8.192 (3.800 libres)**; bloque 7: **987 B libres**.
- **T** (`TS_VM=1`, todos los escenarios): `walk_frame` sin nadie en movimiento **942 T**; **un paso de caminata** (un actor dentro de su tramo: `updateActorDirection`, ajuste al
  punto, fracciones y, si esta cambiando de caja, `checkXYInBoxBounds`) **8.329 T de media, 21.598 de maximo**; un fotograma en que un actor arranca, cambia de tramo (busqueda
  de la puerta entre dos cajas: `getGates` = 8 `getClosestPtOnBox`), gira o llega: **134.670 T de media y 1.467.429 de maximo**. Opcodes (media exclusiva con el despachador):
  `walkActorTo` 50.922 (con `adjustXYToBeInBox` si el destino no esta en la caja de destino de antes), `walkActorToActor` 19.909, `walkActorToObject` 15.655, `waitForActor` 1.108.
- **Para la fase 10:** el cambio de tramo es lo caro (hasta 0,45 s a 3,25 MHz en el peor caso de los escenarios). Ya se quito lo mas facil (division de 32 bits por casos:
  antes 260.000 T de media y 3,1 M de maximo). El perfil del overlay D (`TS_PD=1`) es plano: division 12 %, `mul16u` 14 %, la pila de 32 bits de `cplin` 22 %, contar esquinas
  (`axis_cnt`) 5 %. Lo siguiente seria no calcular las 8 esquinas de `getGates` cuando las cajas comparten un lado, guardar la puerta de cada par de cajas, o saltarse las cajas
  lejanas en la tercera pasada de `adjustXYToBeInBox` (hoy recorre todas con `getClosestPtOnBox` si el punto esta a mas de 80 px de cualquier caja). `walk_frame` recorre los 12
  actores dos veces (residente y D): un contador de actores en movimiento lo dejaria en ~100 T.

## Para las fases 4a y 4b

Ver `PLAN.md` (fase 4): que manejadores, donde van y como se prueban.

## Fase 5b: programa completo hasta el pasillo (2026-11-15)

Lo que la fase 5 dejo sin hacer: `scumm.asm` de v3 seguia siendo la copia de v2 (no ensamblaba con el nucleo). Ahora es el **programa completo** (sin texto, interfaz, actores ni sonido
real: fases 7 y 8) y el arnes de PC lo arranca (script 1) hasta el pasillo (sala 1) con la imagen correcta y las trazas iguales a las del modelo.

```
sh test/build_boot.sh [fotogramas]   # scumm.asm + overlays -> test/prog/; DATA.BIN; arnes test_scumm; compara el resumen D de cada fotograma con vmmodel3.py boot-core
```

### Ficheros (todos en `ENGINE/`, salvo el modelo)
| Fichero | Que es |
|---|---|
| `scumm.asm` | Programa: `scumm_main` (paginacion, HiRes, `vm_init`, overlays, `load_data`, `vm_run_script` con el script 1), `main_loop` (delta como v2, `hr_frame`, depuracion `DBG_START`/`DBG_ROOM`, proteccion anticopia, `vm_frame`, `cam_update`, `gd_update`, `keys`, `hr_end`), `ev_handler`, `ov_load_all`, sonido simulado, `cam_update`, `obj_drawn`. Entrada `RAND USR 16917` (`$4215`, `ENTRY_POINT` de `vm_core.asm`, +21). Sale con X o error de la VM (`PRINT USR` da el codigo) |
| `loader.asm`, `dp_cache.inc` | Cargador de `DATA.BIN` **v3** (tablas calientes al bloque 7, `OBJCLS` a la pagina 47, tablas frias a la 15, perfil, banderas de sonido) y cache de paginas de datos sin las paginas 46-50 (42 paginas: 16-45 y 51-62) |
| `hr.asm` | Pantalla **D3** (abajo) |
| `ovc7.asm` | Overlay C: `moveCamera` y `camera_moved` (entrada `OVC_MOVECAM` = +15) |
| `build_scumm.sh`, `test/build_boot.sh`, `test/test_scumm.cpp`, `test/check_hr.py`, `test/compare_boot.py`, `test/mk_digest_boot.py` | Montaje y prueba. `digest_boot.inc` se **genera** de `test_vm.cpp` (mismo `digest()` que el arnes del nucleo) |
| `TOOLS/vmmodel3.py` | Orden de escenario `BOOT n`, `OPT sonido timed`, `OPT proteccion`, comando `boot-core` y, en `CoreVM.step_frame`, `update_music_timer`, `VAR_CAMERA_POS_X` y `move_camera` |
| `TOOLS/pack_data3.py`, `games/indy3.cfg` | Tabla de sonidos siempre presente (bit 3 = cancion) y `PROF+255` = saltar la proteccion (`[juego] proteccion = 0`) |

### Pantalla D3 (`hr.asm`)
- 192 lineas: **16 de mensajes arriba (filas 0-1), 128 de sala (filas 2-17, `HR_TOP` = 16) y 48 de interfaz (filas 18-23)**. Los bufers de entrada del scroll (`HR_RBM`, `HR_LBM`, `HR_RATT`, `HR_LATT`) llevan la sala desde la linea 16. Filas que se desplazan: `2091 = $FC`, `2092 = $FF`, `2093 = $03` (las 0-1 y 18-23 se quedan quietas).
- `.GFX` **version 2**: alto de `+8`, columnas por pagina de `+12`; la columna k esta en `256 + (k / cpp) * 8192 + (k % cpp) * 2 * lineas` (`hr_coloff`). `ROOMMAX` pasa a **7 paginas** (la sala 79 mide 50.602 B y esta en el arranque).
- **Salas de mas de 128 lineas: recortadas** (no hay prueba del scroll vertical en la placa): se ven `[hv_ytop, hv_ytop + 128)`, con `hv_ytop` = **16 si la sala tiene 144 lineas o mas** (la pantalla principal de v3 mide 144: se pierden las 16 de arriba, que es cielo o techo; D3 decia "las 8 de arriba" para la ventana de 192) y 0 si no. Los objetos se recortan igual (`hm_clip`). Una sala de menos de 128 lineas se rellena de ceros. Comprobado con `check_hr.py` en las salas 1, 76, 79, 8 (200 lineas), 12 (192) y 20 (184); las salas 8, 12 y 20 se cargan con `DBG_ROOM` (`TS_POKE`).
- Pendiente (fase 8): las coordenadas y de los sprites y de la mascara de profundidad tienen que restar `hv_ytop` y sumar 16.
- **Camara** (`cam_update`): la posicion logica sale de `CAMCUR` (`izquierda = cur - 160`, acotada a la sala); el hardware la sigue (`hr_frame` / `hr_end`, como v2: hasta 8 px por fotograma). Un salto grande de camara se ve como un scroll de varios fotogramas.
- **Objetos** (`obj_drawn`, sustituye al de v2): `drawRoomObject` de ScummVM (`object.cpp`): se dibuja si su estado no es 0 y, mientras tiene padre, el estado del padre (`& $F`) es el que pide. El `.GFX` lleva **una sola imagen por objeto**: los objetos con varias imagenes (un estado por imagen) se ven con la primera.
- No se pinta texto, ni interfaz, ni actores: `hr_clear` borra toda la pantalla al cambiar de sala.

### Lo que hubo que anadir al nucleo para llegar al pasillo
- **`moveCamera`** (overlay C, `ovc7.asm`) y **`VAR_CAMERA_POS_X`** en `vm_frame`, en el modelo (`CoreVM.step_frame`) y en el Z80: la sala 79 (los creditos) hace `panCameraTo` y el script espera a que la camara llegue; sin `moveCamera` el arranque se quedaba ahi para siempre. Orden de `scummLoop`: `update_scumm_vars`, `update_music_timer`, `runAllScripts`, frases, `walkActors`, `moveCamera`. Emite el suceso `EV_CAMERA` (10) [cur] como el modelo.
- **Sonido simulado** (`snd_tick`, `snd_*` en `scumm.asm`): el modo `timed` del modelo en el Z80: cada sonido dura 60 jiffies, 3.600 si es una cancion (bit 3 de la tabla de banderas `SNDF`, que sale de `DATA.BIN`: el recurso pasa de 1.000 B), y `VAR_MUSIC_TIMER` avanza como `Player_V2Base` (236 Hz). `isSoundRunning` lo contesta el programa (`EV_SOUND_QUERY` -> `HRES`). Maximo 8 sonidos a la vez. `snd_tick` se llama desde `vm_frame` justo antes de `runAllScripts` (en `vm.asm`, el arnes del nucleo, es un `ret`). La fase 8 lo sustituye por el reproductor real.
- **Proteccion anticopia** (D2): `protection_hook` en el bucle principal: en la sala 92, a los 30 fotogramas `Var[57] = 1` si `PROF+255` = 1 (el perfil `games/indy3.cfg` lo pone).
- Los overlays B, C y D los lee el programa de la SD al arrancar (`DATA/OVLB.BIN`, `OVLC.BIN` y `OVLD.BIN`, a las paginas 49, 48 y 46); `DATA.BIN` lleva `OBJCLS` (pagina 47) y las tablas frias (pagina 15). **La fase 9** decide la ruta definitiva de esos ficheros, hace `compila_scumm.bat` y el cargador BASIC (la entrada ahora es `$4215`, no `$4212` como en v2).

### Fallos que salieron al montarlo (los del arnes del nucleo no los veian)
- **`map_page` tiene que conservar BC.** Los overlays (p. ej. `ovc_room`: `ld bc,size / call map_page / ... ldir`) cuentan con ello porque en el arnes del nucleo `map_page_x` solo cambia la pagina; la cache de paginas (`dp_cache.inc`) usa BC. Ahora `map_page_x` guarda BC. Sin esto, `loadRoom` copiaba 64 KB a partir de `RBLOB`.
- El cargador leia el relleno del final de las tablas con la **pagina fria 15 aun en la ventana** y pisaba las primeras salas del ROOMDIR (las salas 1-6): ahora lo lee con una pagina de la cache.

### Resultado (2026-11-15)
- **Arranque: 1.501 de 1.501 fotogramas con el mismo resumen D** que el modelo (`boot-core`, 1.500 fotogramas con `delta = max(1, VAR_TIMER_NEXT)`): sala 76 (logo) en el fotograma 0, 79 (creditos) en el 148, 6 en el 627, **1 (pasillo) en el 694**, 92 (proteccion, saltada) en el 1.108 y 73 en el 1.212. Es el mismo recorrido que el modelo completo (`vmmodel3.py boot`), sin clics.
- **Pantalla:** `check_hr.py` sobre los volcados de los fotogramas 100 (sala 76), 400 (79, camara 40 de 128), 760 y 1.000 (pasillo, camara 67 de 120): 6.400 bytes comprobados por volcado, 0 distintos, 0 bytes no cero fuera de la ventana de la sala. Imagen del pasillo (fotograma 760): `test/build/room1_f760.png`.
- **Tamanos:** residente `$4200-$65B9` (**6.727 B libres hasta `$8000`**; la fase 6 dejaba 10.888: el nucleo con los cambios de 5b acaba en `$5590` y el programa (`hr.asm`, cargador y cache, bucle, sonido simulado, camara) suma 4.137 B), tablas hasta `$8493`, overlay B 7.680 B (512 libres), **C 4.608 B (3.584 libres)**, D 4.392 B (3.800 libres). Nada de codigo por encima de `$8000`.
- **Regresion:** `build_test.sh` (todas las salas): **3.492/3.492 iguales**, 0 distintos (con `moveCamera`, `VAR_CAMERA_POS_X` y `snd_tick`).
- **Mutaciones** (`mutaciones.py 1,15,20`): **120 de 126** las de antes (sin perder ninguna; las 6 sin detectar son las de siempre) y **9 de 13** las nuevas de `moveCamera` / `camera_moved` / `VAR_CAMERA_POS_X`: **129 de 139**. Sin detectar (los escenarios de las salas 1, 15 y 20 no los recorren): `cur` fuera del minimo (avanza 7, o se acota el destino al minimo), `cur` fuera del maximo sin retroceder, y `CAM_LEFT` 10 -> 9
- **T** (`TS_PROF=700-760`, el pasillo con scroll de camara): media 255.117 T por vuelta, mediana 121.878, p90 999.544, maximo 1.057.475. Casi todo es el scroll de la sala (`hs_l`, `hfc2`) y recomponer columnas (`hm_o`, 11 %): la vuelta no cabe en el presupuesto de la fase 10 (325.000 T) cuando la camara se mueve; `obj_drawn` pesa 1,3 % y `moveCamera` es despreciable. Para la fase 10.

### Lo que queda (apuntado, no es de 5b)
- **Fase 7:** texto (los mensajes no se pintan: `print` llena `MSGBUF` y `display_dialog` corre, pero nadie lo escribe en las filas 0-1), interfaz y verbos en las filas 18-23, raton y teclas, `runInputScript` / `checkExecVerbs`. El arranque no los necesitaba (el modelo llega al pasillo sin clics).
- **Fase 8:** actores (sprites con `hv_ytop` y `HR_TOP`), sonido real, objetos de varias imagenes, `updateObjectStates` (el Z80 mira `OBJST` vivo).
- **Fase 9:** ruta de los `OVL*.BIN` en la SD, `compila_scumm.bat`, cargador BASIC, guardar y cargar, probar en la placa (el scroll con las filas `$FC / $FF / $03`, el recorte de salas altas, `HR_TOP`).

## Fase 7: interfaz, mensajes, raton y teclado (2026-11-15)

Modelo: `TOOLS/vmgame3.py` (`draw_verb`, `find_verb_at_pos`, `process_input`, `check_exec_verbs`, `run_input_script`) y `TOOLS/vmmodel3.py` (`CoreVM.step_frame`, ordenes `CLICK`/`MOVE`/`RCLICK`/`KEY`/`ESC`/`INPUT`/`USERPUT`,
`AT`, `screen_to_scumm`). Z80: `ENGINE/vm_input.asm` (el nucleo: la entrada), `ENGINE/ui3.asm` (programa: pantalla de texto, verbos, mensajes, cursor, teclado y raton), `vd_draw`/`ovb_vname` en `ovb4b.asm`
(overlay B) y `ev_handler`, `restart`, `do_pause` en `scumm.asm`.

```
sh test/build_test.sh                                              # nucleo: todas las salas, con los escenarios de entrada cinp<sala>.<k>
sh test/build_boot.sh 1500 "../../Indy Last Crusade" eventos.txt   # programa completo: el arranque con sucesos de entrada (lineas "fotograma tipo [a b]"; abajo)
python -I test/check_hr.py test/build/boot_dump.bin test/prog/scumm.sym ../preview_hr/gfx    # ahora tambien comprueba las filas de la interfaz
python -I test/render_hr.py test/build/boot_dump.bin pantalla.png 3                          # la pantalla HiRes (256 x 192) del volcado a PNG
```

### Decision confirmada por el usuario (2026-11-15): la frase va en la fila de arriba
D3 decia "6 filas de interfaz: frase, verbos e inventario", pero Indy3 usa **7 filas de 8 lineas desde la 144**: la frase (y = 144), tres filas de verbos (152-168) y tres de inventario (176-192, con las flechas).
No caben en 48 lineas. Solucion tomada (cambiarla es tocar `ui_verb`, `in_conv` y `screen_to_scumm`): la pantalla de texto `UIVB` tiene 8 filas de 40 columnas de 6 pixeles y la fila de UIVB de un verbo es
**(y - 144) / 8 + 1**: la frase (fila 1) cae en la segunda de las 2 filas de mensajes de arriba (lineas 8-15) y las seis de verbos e inventario (filas 2-7) en las 48 lineas de abajo. **Mientras hay un mensaje en pantalla
la frase no se ve** (el original la deja a la vista; se pierde una linea de texto durante los dialogos). La columna es x / 8 (las x de Indy3 son multiplos de 8: 0, 48, 104, 176, 256 y 152, 168; 40 columnas x 6 px = 240 px).
Alternativas: una fila de 7 lineas (49 > 48: no), o una sola fila de mensajes de 8 lineas (la 4.a fila de interfaz a costa de los dialogos de 2 lineas).

### Coordenadas
- La pantalla del ZX81 es de 256 x 192 y la de SCUMM de 320 x 200: el programa pasa el cursor (pixeles; `cur_x` 0-248, `cur_y` 0-184) a coordenadas de SCUMM en `in_conv` (modelo: `vmmodel3.screen_to_scumm`):
  en la sala y en las 2 filas de arriba, tal cual (la x virtual suma el borde izquierdo de la camara en `vm_input`); en la interfaz (y >= 144), **x = (x / 6) * 8, y = y + 8**.
- El rectangulo de un verbo es `[left, left + 8 * V_LEN) x [top, top + 8)`: `V_LEN` (columnas del nombre ya convertido, tope 40) se fija **al dibujar el verbo**, como `drawVerb` de ScummVM fija `curRect.right`
  (al final de `verbOps` y al restaurar con `saveRestoreVerbs`: `vd_draw`, modelo `draw_verb`); un verbo nunca dibujado o con imagen no tiene rectangulo. **`VSZ` pasa de 18 a 19** (campo `V_LEN`; `verb_ix` multiplica
  por 19) y el CRC de los verbos (`W=`) lo incluye.
- **Correccion del modelo:** la pantalla principal mide `main_h - main_top` (`initScreens(b, h)`: altura h - b) y no `main_h`: el modelo usaba 144 de alto desde la 16 (Indy3 llama a `SetScreen(16, 144)`: son 128).
  El Z80 (`MAINTOP`, `MAINH`) guarda los dos valores de `roomOps` 3 tal cual, sin cambios.

### El nucleo (`vm_input.asm`; residente, ~560 B)
El nucleo no sabe de teclado ni de raton: el programa deja **un suceso por fotograma** en `INEV` (tipo 1 clic, 2 clic derecho, 3 tecla, 4 ESC, 5 mover; x, y de SCUMM; tecla) y `vm_frame` lo consume (`vm_input` tras
`talk_frame`, como `processInput` tras `displayDialog` en v3). `vm_input`: recorta el raton a 0-319 / 0-199, calcula el raton virtual (`VMOUSEX/Y`; y = -1 fuera de la pantalla principal) y `MKSTAT`
(`_mouseAndKeyboardStat`: $8000 clic izquierdo, $4000 derecho, o la tecla); ESC o el clic derecho (la tecla de salir de la escena cortada en v0-v3) llaman a `abortCutscene` y dejan `VAR_CUTSCENEEXIT_KEY` como tecla
si la variable no es 0; `.` pone `talk_delay` a 0; ESPACIO (la pausa) no llega a los scripts; **Intro es un clic izquierdo si el cursor esta activo** (`_cursor.state` > 0). `in_vars` escribe `VAR_VIRT_MOUSE_X/Y` y
`VAR_MOUSE_X/Y`. `check_exec_verbs` (tras `run_all`, antes de `checkAndRunSentenceScript`, como en `scummLoop`): con `_userPut` > 0 y algo pulsado, la tecla de un verbo (`V_KEY`, modo 1) llama a
`runInputScript(1, verbo, 1)`, otra tecla a `(4, tecla, 1)`, un clic sobre un verbo a `(1, verbo, 0)` y un clic en la pantalla principal a `(2, 0, 0)` (fuera de ella, `(1, 0, 0)`). `rin` pone los tres argumentos en los
locales 0-2 de `VAR_VERB_SCRIPT` como `checkAndRunSentenceScript`. API nueva `vm_inpscr` (+30: zona en `APIVERB`, valor en `APIN`, modo en `APIA`: orden `INPUT` del arnes).
Variables en el bloque 7 (`$F1AC-$F1BC`, 17 B tras `GW_END`): `INEV` (7), `MOUSEX/Y`, `VMOUSEX/Y`, `MKSTAT`; `vm_init` las pone a 0.

### Pantalla de texto, verbos y mensajes (`ui3.asm`, residente)
- `UIVB` (`$9900`, 8 x 40 codigos de glifo), `UIBUF` (`$9A40`, el nombre de un verbo), variables `UIV` (`$9A80-$9ABF`), `FAKESL` (`$9AB0`), `PGBUF` (`$9AC0`, la pagina de mensaje). Fuente `font_tiles` (384 B en el
  residente; `TOOLS/gen_font3.py` la genera desde `ENGINE/font6.bin`: flechas 208-209 y 46 glifos 210-255; solo mayusculas; los codigos 1-4 de los nombres de verbo de Indy3 son las flechas del inventario).
- `hr_ui` (copia de `hrui.asm` de v2): pinta solo los grupos de 4 caracteres que cambian (`HRUI_PREV`, en el bloque de atributos); la fila r de UIVB va a la fila de pantalla r (r < 2) o r + 16. Blanco brillante sobre
  negro; con un mensaje, las filas 0-1 con el color del que habla. `check_hr.py` comprueba el bitmap de esas filas contra UIVB.
- **Verbos:** `EV_VERB` marca `ui_dirty`; `ui_redraw` (una vez por fotograma si hace falta) limpia las filas de UIVB y escribe cada verbo visible (id, curmode <> 0, saveid = 0, de texto) en su celda con el nombre que da
  el overlay B (`ovb_vname`, entrada +24: convierte el nombre, con los codigos `$FF`, a `UIBUF`; en `emit_a` es el modo 2). El nombre de un verbo apunta al texto de un script: fuera de un script `ovb_vname` pone una ranura
  falsa en `CURSLOT` (`FAKESL`) para que `cm_nest` devuelva la ventana a la pagina del nombre (sin ella se leia basura despues de un nombre anidado: la frase). El valor de vuelta va en HL: `call_ovb` pisa A. Un verbo
  atenuado (curmode 2: Talk y Travel en el gimnasio) se pinta como uno normal (no hay color por verbo).
- **Mensajes:** `EV_TEXT` ([255]: borrar las 2 filas de arriba; [0, ...]: una pagina): `display_dialog` (B) deja los caracteres de la pagina en `PGBUF` (`dg_sum`) y `ui_text_ev` los escribe en las filas 0-1 con el color del
  actor (`ega2chroma`), sin partir por palabras (se parte a las 40 columnas; lo que pasa de 2 filas se pierde). El tiempo del mensaje es el de `displayDialog` (`talk_delay`, igual al modelo). El texto suelto de `print`
  (ranura 1) no se pinta.
- **Cursor:** el sprite 63 (la flecha de v2), visible si `_cursor.state` > 0.

### Teclado y raton (`in_poll`; una vez por fotograma, antes de `vm_frame`)
Letras y cifras = la tecla de SCUMM (minuscula: los verbos de Indy3 usan q a z w s x e d c r f v t g b y u h j n m o l); **Intro** = clic izquierdo; **ESPACIO** = pausa (otra vez, sigue; "GAME PAUSED" arriba);
**SHIFT + 5 6 7 8** = mover el cursor (izquierda, abajo, arriba, derecha: 3 px por fotograma); **SHIFT + ESPACIO** = ESC; **SHIFT + X** = salir al BASIC (la X sola es el verbo Look: antes salia); **SHIFT + R** = reiniciar
(`restart`: como el arranque, sin volver a leer los overlays). Con raton Bluetooth (`mouse.asm`) mueve el cursor y los botones son los clics (izquierdo; derecho = ESC). Un suceso por fotograma (clic derecho/ESC > clic >
tecla > mover). Para probar sin teclado ni raton, `IT_KIND`/`IT_X`/`IT_Y`/`IT_KEY` (`ui3.asm`) sustituyen a `in_poll` (el arnes los escribe con `TS_POKE`; `IT_KIND` 6 = reiniciar).

### Resultado (2026-11-15)
- **`build_test.sh` (todas las salas): 3.687 de 3.687 trazas iguales** (los 3.492 de antes mas 195 de entrada: `cinp<sala>.<k>`, `cinpboot` (ESC y boton derecho en las escenas cortadas del arranque), `cinpverb` (un clic en el borde derecho de cada verbo) y `cinpdot` (`.` con un mensaje)).
- **Arranque con la interfaz: 1.501 de 1.501 fotogramas iguales** (sala 1 en el 694, como antes); `check_hr.py` **0 distintos** en las salas 76, 79, 1, 8, 12 y 20, y las filas de la interfaz iguales a UIVB. Cargando una sala con `DBG_ROOM` (`room n` en el fichero de sucesos) las trazas tambien son iguales (8, 12, 20).
- **Partida en Barnett College** (`test/ev_barnett.txt`, 14 sucesos entre los fotogramas 1.290 y 1.700: Look, clic en la puerta, Walk to, clics en la escena, teclas `e` y `z`, boton derecho, Intro, ESC, el script 3 con su mensaje): **1.751 de 1.751 iguales**, `check_hr.py` 0 distintos. El teclado de la matriz del arnes (`ZX81_MATRIX`, `EVF_NOPOKE=1`: la tecla X = Look) da el mismo suceso que el modelo. Mensaje "THAT DOESN'T SEEM TO WORK." en amarillo (color de Indy) arriba. Reiniciar (`restart`, SHIFT + R) probado sin comparar (el modelo no reinicia): vuelve al logo y a los creditos sin errores.
- **Mutaciones** (`mutaciones.py 1,15,20`; `test/mut_fase7.py` las 24 nuevas): **20 de 24 de la fase 7 detectadas**. Sin detectar (Indy3 no las recorre): el verbo centrado (ninguno lo usa), el clic derecho en `check_exec_verbs` (codigo que no se alcanza en v3: el boton derecho es siempre ESC), y dos de `drawVerb` con verbos guardados (el rectangulo solo cambiaria si el nombre cambia entre guardar y restaurar). **Total 148 de 162** (las 138 de antes, sin perder ninguna: 129 de 139 contando `update_scumm_vars`, mas las 24 nuevas; las 14 sin detectar son las 10 de siempre y 4 de la fase 7). La del texto de `restaurar verbos deja el saveid` se adapto al codigo nuevo.
- **Tamanos:** residente (programa) `$4200-$7064` (**3.996 B libres** hasta `$8000`; la 5b dejaba 6.727: +2.7 KB = `vm_input` 560 B, `ui3.asm` ~1.8 KB incl. la fuente de 384 B y `mouse.asm`, `in_poll`/pausa/reinicio); en el nucleo de pruebas (`vm.asm`) `$4221-$57EE`. Overlay B 7.936 B (codigo hasta `$1C93`; **365 B libres** antes de la tabla en `$1E00`), C 4.608 B (3.584 libres), D 4.392 B (3.800 libres). Bloque 7: 970 B libres. Hueco del bloque 4: `STRHEAP` acaba en `$93ED` (36 B menos de margen por `VSZ` = 19).
- **T:** fotograma tranquilo del gimnasio (`TS_PROF=1280-1310`, 30 vueltas): **50.337 T por vuelta de media** (78.372 antes de `ui_chg`); `hr_ui` ya no aparece (21.040 T cuando se ejecuta), `kbd_scan` ~1.700 T por vuelta (`ks_key` 3,3 %), `ui_redraw` solo cuando cambia un verbo (una conversion por verbo visible por el overlay B). Con scroll el pasillo sigue en ~1.000.000 T (fase 10).

### Pendiente / apuntado
- El texto de los mensajes no se parte por palabras (40 columnas, 2 filas); `print` suelto (ranura 1) no se pinta; verbos atenuados sin color; sin colores por verbo (hover); solo mayusculas.
- `compila_scumm.bat`, la ruta de los `OVL*.BIN` y probar el cursor / raton / teclas en la placa son de la fase 9. El mapeo de teclas (SHIFT + 5-8, SHIFT + ESPACIO, SHIFT + X, SHIFT + R) se puede cambiar en `in_poll`.
- `hr_ui` solo se ejecuta cuando UIVB cambia (`ui_chg`): sin eso costaba ~21.000 T por fotograma (`hu_cmp` 27 % de la vuelta en un fotograma tranquilo).

### Pruebas
- **Escenarios de entrada** (`make_scenarios_core`, `cinp<sala>.<k>`: 6 en las salas 1, 15, 20 y 28, 2 en las demas con cajas): la sala, el script 96 (que pone los verbos de Indy3), `USERPUT` (activo, apagado, negativo...) y
  de 6 a 14 sucesos al azar (clics en verbos, en objetos de la sala, en el inventario, arriba, fuera de la pantalla; teclas de verbo, Intro, ESC, `.`, ESPACIO; boton derecho; `INPUT`) con fotogramas entre ellos.
- **Arranque con sucesos de entrada:** `build_boot.sh N juego eventos.txt` (`mk_events.py` -> `TS_POKE`; `vmmodel3.py ... boot-core DIR N eventos.txt`: ordenes `AT`). Tipos: `click px py`, `move px py`, `rclick`,
  `key k`, `esc`, `script n` (px, py: pixeles de la pantalla del ZX81). Ej. (el gimnasio, sala 73, desde el fotograma 1.264): `1290 click 38 162` (Look) y `1300 click 125 90` (el hueco de la puerta, objeto 834):
  la frase pasa a "LOOK LOCKER ROOM", con las trazas iguales fotograma a fotograma (`test/build/ev2.txt`, `ui_ev2.png`).

## Fase 8: actores y sonido (2026-11-15)

Modelo: `TOOLS/vmgame3.py` (sonido, modo `real`: `real_start`, `real_stop`, `snd_chain`, `update_music_timer`, `music_var`), `TOOLS/sprites3.py` (referencia de los sprites) y `TOOLS/sprbudget3.py` (D6).
Z80: `ENGINE/ovd_act.asm` (actores, overlay D, entrada `OVD_ACTORS` = +12; variables en `ENGINE/ac_vars.inc`) y `ENGINE/snd3.asm` (sonido, residente). Sin commit.

```
sh test/build_boot.sh 1500                      # arranque: resumen D por fotograma y las ordenes al MCU (STOP, LOOP, PLAY) contra el modelo
sh test/build_boot.sh 700 "../../Indy Last Crusade" ev_snd.txt   # ademas ~85 sucesos de sonido al azar (empezar, parar, parar todo): lineas "fotograma snd operacion sonido"
sh test/actall.sh "1 2" "1 15 20 28" 12         # actores al azar (mk_actscen.py: trajes, direcciones, fotogramas, cajas) en cada sala; check_spr.py contra sprites3.py
sh test/objflip.sh 20                           # objetos animados: 2 objetos de la sala cambian de estado por fotograma; check_hr.py y T por vuelta
python -I TOOLS/sprbudget3.py "Indy Last Crusade" DATA.BIN estatico 32,35,36,41,43,46,66,70,72,76,82   # D6
python test/mut_fase8.py                        # mutaciones de actores y sonido (MUT_WORKERS=4: copias en V3/ENGINE_m8_<n>, se borran al acabar)
```

### Actores (`ovd_act.asm`, overlay D)
Elegido el **overlay D** (6.308 B tras la fase; 1.884 libres) y no el C: el dibujo es de cada fotograma y D no tenia despacho por opcode. El residente solo gana `aq_init` y la llamada.
`OVD_ACTORS` solo existe en el programa (`PROGRAM equ 1` en `scumm.asm`; `vm.asm` pone 0 y `ovld.asm` monta un `ret`): el nucleo de pruebas no tiene pantalla.
Las variables (lista ordenada, cache de firma, contadores de poses, las 8 tiras de la mascara y, para los extra, `ASEL` (lo que elige cada actor) y `AC2V`: **826 B**) estan en el bloque 7 detras de `IN_END` (`$F1BD-$F4F6`; **quedan 145 B** hasta `SCRDIR`); `aq_init` pone a 0 las 194 primeras.
Reglas (las mismas en Z80 y en `sprites3.py`; ver tambien la cabecera de `ovd_act.asm`):
- Actores 1-12 de la sala, visibles y con traje, ordenados por la `y` (byte bajo; empate: menor numero primero, como `processActors`); reciben los sprites 0, 1, 2... (a mas indice, mas al frente). El 63 es el cursor.
- Animacion = `fotograma * 4 + newDirToOldDir(direccion)` (el de ScummVM, `util.cpp`: 71-109 derecha, 109-251 de frente, 251-289 izquierda, el resto de espaldas) en el blob principal (`COSTDIR`) y, si su lista esta vacia, en el extra (`COSTDIR2`: los 24 trajes de dos paginas). Si el
  fotograma pedido no esta en el traje se usa el de quieto (`A_STAND`); sin ninguno, el actor no se dibuja. El fotograma es `A_FRAME`, que ya fijan `animateActor` (fotogramas 6-30: las 316 peticiones), `actorOps` y el habla (`startAnimActor`): el Z80 no interpreta nada mas.
- Postura = `((contador * pasos) >> 3) mod pasos`, con un contador por actor (`ACCNT`: ultimo fotograma, contador) que vuelve a 0 cuando cambia `A_FRAME` y suma 1 por fotograma dibujado. Es una aproximacion de la velocidad de las poses (el original avanza un paso de la animacion por fotograma y los
  blobs llevan 1-4 pasos repartidos); el contador es estado del Z80 y `check_spr.py` lo lee de la memoria: **la velocidad de las poses hay que juzgarla a ojo en la placa**.
- Posicion: `x - camara + dx` (camara del hardware, `gf_campx`), `y - elevacion + dy + HR_TOP - hv_ytop` (D3: la sala empieza en la linea 16 y se recorta con `hv_ytop`), sprite = pantalla + 32. Las lineas de un sprite fuera de [16, 144) se apagan en su mascara (ni los mensajes ni la interfaz se tapan).
- **Mascara de profundidad por pixel** de la sala (`CURRD+15`; solo si la caja del actor tiene mascara, el fotograma mide <= 6 x 8 celdas y la columna de su borde izquierdo no es negativa): `aq_mkdec` decodifica en `MKBUF` la ventana que cubre el fotograma (`ancho + 2` tiras de 8 pixeles x 64 filas) con aritmetica
  de filas con signo (v3: salas de 128 a 200 lineas; v2 suponia 128) y cada celda toma sus 8 columnas de dos tiras, desplazadas `x & 7`. **Sin hacer:** mascaras de objeto (212 objetos de 34 salas las llevan; no estan en `DATA.BIN`) y las clases `NeverClip`/`ForceClip`.
- Cache de firma como v2 (camara, sala, x, y, elevacion, caja, direccion del fotograma elegido, pagina del traje, `ytop`): un actor con la misma firma y el mismo primer sprite que el fotograma anterior no se reescribe.
- `scumm.asm`: `call_ovd` con `OVD_ACTORS` tras `gd_update`, `aq_init` en el arranque y en `restart`, y `aq_hold` = 2 fotogramas en `EV_ROOM_LOAD` (los sprites siguen apagados mientras el hardware llega a su sitio).

**D6 (mas de 64 sprites): sprites extra de la FPGA como desbordamiento (`POKE 2131`).** Primero se midio (`sprbudget3.py`): con los trajes que vio el recorrido del estudio en cada sala (`estatico`: cada uno en su postura mas grande, todos a la vez) las salas 32, 35, 36, 41, 43, 46, 66, 72, 76 y 82 piden 4-63 sprites (la 82, 5 actores, justo 63) y la 70 pide **66**;
mirando fotograma a fotograma (`medidas/indy3_salas.json`, que lleva los trajes visibles de cada fotograma del recorrido) solo se pasan de 63 la 70 (250 fotogramas, si se cuentan las posturas de pelea de los trajes 90 y 91) y la 83 (53 de 102, 93 sprites en su postura mas grande de 3 actores).
Es un peor caso (no se sabe que postura tiene cada uno en cada fotograma: eso lo dan los scripts), asi que no basta con "nunca pasa": **el actor que no cabe ya no se pierde**. Reparto (`actors_run`, pasada 1 de delante a atras): los actores que caben en los 63 sprites normales (el 63 es el cursor); el primero que no cabe y todos los que van mas atras, a los **extra**
(hasta `AC_XMAX` = 32 sprites; si ni asi cabe, no se dibuja). Los extra tienen **menos prioridad que todos los normales** (la FPGA los mira despues del normal 0), asi que los que van detras son los que se mandan alli y el orden de fondo se conserva; entre los extra gana el de numero mas bajo, por eso se escriben de delante atras.
- **Donde viven (no hace falta tocar la FPGA):** la entrada del extra j son los 32 bytes `{POKE 2129, j, campo}` de la **sombra** (la copia de 64 KB que la FPGA hace de todo lo que escribe la CPU; el motor lee de ahi, no de la RAM). Con `POKE 2129 = 0` (la hoja en el bloque 0) caen en `$0000-$03FF`, que el programa no usa (la ROM esta ahi: la CPU no puede escribirlo, pero la FPGA captura la escritura igual que las de `POKE 2100`); `POKE 2131 = numero de extra` en uso, cada fotograma.
  Campos: `+1/+2` x (9 bits), `+3` y (0 = no se ve), `+4` colores, `+12` forma, `+20` mascara, `+29` formato (0 = A). Al salir se vuelve a `2129 = 2` y `2131 = 0`.
- **Limite de la FPGA (no se ha podido probar en la placa):** 12 sprites por linea y un presupuesto de pasos por linea (174 en la temporizacion de 32 columnas: 2 + 64 + M + 6 por cada sprite A cargado). `AC_XMAX` = 32 deja 2 + 64 + 32 + 72 = 170 <= 174. Los extra ayudan con el total, **no con muchos personajes lado a lado en la misma linea**.
- Arnes: `test_scumm.cpp` captura las escrituras a `$0000-$03FF` y los POKE 2129/2131 y los pone al final del volcado; `sprites3.py` calcula el mismo reparto y compara los extra. Escenas "multitud" de `mk_actscen.py` (6 actores con las posturas mas grandes de los 10 trajes mas grandes): 63 normales + 32 y 14 extra en las dos primeras pruebas; **0 distintos**.
- Si el reparto no basta en alguna sala, caso por caso: dar prioridad al ego o `escala_N` del traje.

### Sonido (`snd3.asm`, residente; sustituye al simulado de la 5b)
Player_V2 de ScummVM (`player_v2.cpp`: `startSound`, `stopSound`, `getSoundStatus`; `player_v2base.cpp`: `chainSound`, `chainNextSound`, `nextTick`) en el modelo (`real`) y en el Z80: un sonido suena y otro espera si el desplazado es reiniciable y su prioridad lo permite; manda la tabla de sonidos de DATA.BIN (prioridad, banderas, duracion en fotogramas); cada
cambio de sonido son 3 ordenes al MCU como en v2 (`STOP_VGM`, `LOOP_VGM`, `PLAY_VGM` con `DATA/SND/SOUNDnnn.VGM`, nombre sacado de la plantilla del perfil), que el arnes imprime (`SND f=N ...`) y el modelo reproduce (`snd_log`).
- `VAR_MUSIC_TIMER` (`Player_V2Base::nextTick` + `Sound::updateMusicTimer`): 236 ticks por segundo, es decir `DELTA * 236 / 50` por fotograma de 50 Hz (la 5b usaba 60: corria un 17 % lenta); +1 cada 126 ticks desde que un sonido con la bandera 4 (los 12 que fijan el tempo, siempre en el tick 0) lo activa (antes, 65535: nunca); `chainSound` lo pone a 0
  sin tocar el contador de ticks; `VAR = t - ((t * 14438 + 2^20 - 1) >> 20)` = `floor(t * 1034138 / 2^20)` (= `t * 236,7052 / 240` exacto hasta t = 2.047). Multiplicacion de 16 x 16 bits en `sd_mul16`.
- Un sonido sin bloque PCjr (11 de los 84) no existe para la tabla y no suena. Los de bucle duran 65535 (hasta que se paren); los demas, `ceil(ticks * 50 / 236)` fotogramas (tope 65534). Los sucesos se tratan por fotograma entero (el original encadena en el tick exacto): diferencia de hasta un fotograma.
- La ventana de datos (bloque 1) cambia al leer la tabla: `sd_end` hace `restore_win` al acabar cada suceso (llegan en mitad de un script).
- **El intro va ahora al ritmo de la musica** (modelo y Z80 iguales): el arranque llega a la sala 79 en el fotograma **129** (antes 148), a la 6 en el 515 (627), al pasillo (1) en el **582** (694), a la 92 en el 996 (1.108) y a la 73 (Barnett) en el 1.100 (1.212). Solo suena el sonido 35 (la musica del logo: tempo en el tick 0, 13.906 ticks = 2.940 fotogramas). Con la musica real
  en la placa (el MCU a 236 Hz de verdad) el ritmo es el de ScummVM; **a comprobar en la placa** que el VGM y el temporizador del Z80 no se separan.
- Depuracion: `DBG_SND` (`SV+198`; byte alto = operacion 1 empezar / 2 parar / 3 parar todo, bajo = sonido) y el suceso `N snd operacion sonido` de `mk_events.py` / `AT` del modelo (`test/ev_snd.txt`).

### Objetos animados (salas 20 y 28)
No ha hecho falta codigo nuevo: v3 no tiene imagenes por estado en el OBIM (la animacion son objetos que se muestran y se ocultan por el estado del padre, que `obj_drawn` ya sigue desde la 5b) y `gd_update`/`hr_objupd` recomponen solo las columnas de los objetos que cambian. Se ha comprobado con `objflip.sh`: **2 objetos cambian de estado en cada fotograma** (`TS_POKE`
de `OBJST` + `gd_pending`, lo que haria el suceso `EV_OBJSTATE`) durante 120 fotogramas y `check_hr.py` da **0 distintos** en 5 fotogramas de cada sala (la sala 20 pasa de 4 a 8 objetos dibujados, la 28 de 7 a 10). El coste es lo que preocupa: **334.176 T por vuelta de media en la sala 20 (maximo 1.208.886) y 451.235 en la 28 (maximo 1.471.874)** con ese cambio
forzado de 2 objetos por fotograma, frente a los 325.000 del presupuesto de `delta` 6: es la recomposicion de columnas (`hm_o`, `hr_makecol`); para la fase 10. El coste de `actors_run` no se ha medido por separado (la cache de firma evita reescribir sprites).

### Pruebas (2026-11-15)
- Punto de partida (antes de tocar nada): `build_test.sh` 3.687/3.687, arranque 1.501/1.501, Barnett 1.751/1.751, `check_hr.py` 0 distintos: **todo igual**.
- Al acabar: `build_test.sh` **3.687/3.687**; arranque **1.501/1.501** con las ordenes al MCU iguales y `check_hr.py` 0 distintos; Barnett **1.751/1.751**, `check_hr.py` 0 distintos; arranque con ~85 sucesos de sonido al azar **701/701** y **92 ordenes al MCU iguales**.
- **Sprites:** `check_spr.py` (`sprites3.py`) sobre los volcados del arranque (sala 73: 25 sprites; sala 1: 20) y **96 escenas al azar** (`actall.sh`: 2 semillas x salas 1, 15, 20 y 28 x 12 escenas con 1-6 actores de trajes, direcciones, fotogramas, cajas y elevaciones al azar): **0 distintos**. Las cuatro salas tienen mascara de profundidad.
  Ojo: las escenas se hacen cada sala en su ejecucion; pasar de la 20 a la 28 en la misma da `E_BADROOM` en los scripts de las salas (carga de salas con el estado forzado a mano, sin relacion con los actores).
- Fallos que salieron al montarlo: dos variables solapadas (`aq_fl` con `aq_cp`) hacian leer celdas basura; los nombres `ac_*` chocaban con `geom.asm` (ahora `aq_*`).
- **Mutaciones de la fase 8** (`test/mut_fase8.py`, 4 hilos): **sonido 17 de 17 detectadas**; **actores 28 de 43** (la 44.a, "no busca en el blob extra", no se pudo aplicar: el texto no coincide). Sin detectar: las de la **cache de firma** (5: la cache es una optimizacion, el resultado de un volcado no cambia aunque la firma sea mala; haria falta comparar volcados de fotogramas seguidos),
  `dibuja a los que no tienen traje`, `la postura no usa los pasos`, `x sin la camara`, `el sprite 63 se usa`, `un actor que no cabe se dibuja a medias`, `celda a la izquierda de la pantalla`, `sin recorte por arriba` y 3 de la mascara (`ignora la mascara de la caja`, `un tramo de valor 0 se rellena`, `el fin del tramo no se acota`): las escenas al azar no las recorren
  (camara siempre cerca del origen, pocas escenas con mas de 63 sprites, actores casi nunca por encima de la linea 16). **Pendiente de la fase 10 / de quien la lea: escenas que las recorran.**
- Esas mutaciones se pasaron **antes** de los sprites extra, de `hr_pal16` y de los `roomOps` de paleta; no se han vuelto a pasar con el codigo final (las de actores usan escenas que ahora tambien recorren los extra).
- **`mutaciones.py` (las 162 del nucleo) NO se ha repetido en esta fase** (tarda horas). Los cambios en el nucleo son solo equates en `vm_input.asm` (`ACV`, `AC_ZERO`), `PROGRAM` y `OVD_ACTORS` en `vm.asm` y la entrada nueva de `ovld.asm`; `build_test.sh` (3.687/3.687) los ejercita, pero no hay prueba de que `mutaciones.py` siga en 148/162.

### Paleta (2026-11-15; lo que dijo el usuario: "no aprovechas la paleta")
- **Arreglado:** `hr_pal16` (`hr.asm`) programa la paleta de 16 de la FPGA (`POKE 2063/2064/2066/2067`) con los 16 colores del EGA. El EGA y el Chroma coinciden indice a indice (IRGB) salvo el **marron (6)**: el amarillo oscuro de Chroma no es el marron del EGA (170, 85, 0), y `lfl2gfx.chroma_rgb` ya cuenta con que el motor lo
  redefine. El v2 lo hacia (`ov_pal16` de `V2/ENGINE/overlay.asm`) y **el programa de v3 lo habia perdido**: en la placa el marron salia como el amarillo oscuro. Tabla copiada de v2 (`pal16_tab`). No se puede ver en el arnes (no simula la paleta): comprobar en la placa.
- **Hecho: `roomOps` 2 y 4** (65 y 67 usos en los scripts de Indy3). ScummVM (`script_v5.cpp`, `gfx.cpp`, `palette.cpp`): `roomOps 2` es `_roomPalette[b] = a` (el pixel `b` de la imagen de la sala se pinta con el color `a`; fuerza un redibujo completo) y `roomOps 4` es `_shadowPalette[b] = a` (el color `b` de la pantalla sale
  como el `a`); las dos tablas empiezan en identidad (al arrancar, no al cambiar de sala: persisten entre salas hasta que un script las cambia) y el color final de un pixel `p` de la sala es `EGA[shadow[room[p]]]`.
  - **Modelo:** `room_pal` y `shadow_pal` (16 entradas, `vmgame3.py`); `roomOps` 2 y 4 las escriben (a y b > 15 = `E_RANGE`: la pantalla tiene 16 colores; ScummVM escribe en una tabla de 256), emiten el suceso nuevo **`EV_PALETTE` (13, sin operandos)** y siguen saliendo al anfitrion como antes; el resumen lleva `Y=` (crc de las dos tablas).
  - **Z80:** `ROOMPAL` y `SHADOWPAL` (bloque 7, `$F520-$F53F`; `vm_init` las pone en identidad), escritas en `ro_24` (`ovc1.asm`, overlay C), que emite `EV_PALETTE`. El programa (`ev_handler` -> `hr_pal_apply`, `hr.asm`) reprograma la paleta de 16 de la FPGA **sin redibujar la sala**: la entrada `k` pasa a ser el color `SHADOWPAL[ROOMPAL[k]]` del EGA. Las imagenes y los trajes
    siguen en codigos de Chroma (el mapa EGA -> Chroma es la identidad). `hr_pal16` (arranque) deja la identidad (con el marron del EGA).
  - **Limite:** los trajes usan los mismos 16 codigos, asi que un color que la sala remapea sale remapeado tambien en los personajes que lo llevan (en ScummVM los trajes no pasan por `_roomPalette`, solo por la paleta de la pantalla). Se ve solo si una sala remapea un color que llevan los personajes.
  - **Pruebas:** `build_test.sh` **3.687/3.687** con el resumen nuevo (`Y=`; los escenarios de sala ejecutan los `roomOps` de sus scripts de entrada) y los 3 sucesos nuevos iguales; `build_boot.sh` cargando las salas 4, 7 y 13 con `DBG_ROOM`: 121/121 fotogramas iguales y `check_spr.py` comprueba ademas la **paleta de 16 que programo el Z80** (capturada en el volcado: `POKE 2063/2064/2066/2067`)
    contra `ROOMPAL`/`SHADOWPAL` y `pal16_tab`: igual (la sala 13 deja `_shadowPalette[10] = 3` y `[11] = 1`). El efecto visual no se ha visto (el arnes no pinta la paleta): **comprobar en la placa**.
- **No es de paleta: `oldRoomEffect`** (25 usos). ScummVM (`script_v4.cpp`, `o4_oldRoomEffect`) solo guarda el efecto de transicion de la proxima sala (`_switchRoomEffect`) o hace `fadeIn(_newEffect)`: son barridos y disolvencias de la pantalla, no cambios de paleta. No esta hecho (el cambio de sala es un corte); si se quiere, es un efecto de pantalla aparte.

### Tiempos de la regresion (medidos, 2026-11-15, con 4 hilos libres en la maquina)
`build_test.sh` 3.687 escenarios: **4 min** (237 s); arranque de 1.500 fotogramas con `check_hr` y sprites: **6 min** (377 s); Barnett (1.750): **8 min** (498 s); sonido con sucesos al azar (700): **1 min**; actores, 18 ejecuciones de sala x 12 escenas: **37 min** (2.250 s, unos 2 min por sala). Total **57 min** en serie.
Por niveles (ver la respuesta al usuario): por cambio, lo que cubre el fichero tocado (`actscen.sh` una sala 2 min; `snd3.asm`: arranque con sonidos 1-4 min; `build_test.sh` solo si se toca el nucleo); al cerrar un bloque de trabajo, todo; las mutaciones aparte.

## Fase 9: montaje, SD, guardar y cargar (2026-11-16)

Sin commit. Lo que hay en la placa sin ver: ver `PRUEBAS_PLACA.md` (la lista para el usuario).

```
ENGINE\compila_scumm.bat [X:\ | nocopia]     monta y deja la carpeta lista en V3\SDOUT\SCUMM\V3\ (y la copia a la SD del emulador o a X:\)
sh test/savetest.sh                            las 5 pruebas de guardar y cargar de abajo, una detras de otra (~15 min)
```

### Montaje y SD
- `compila_scumm.bat`: gen_vmtables3 y gen_font3, `pasmo scumm.asm` y los overlays B, C y D (contra `vm.sym` = el `scumm.sym` del programa), `pack_data3.py` (siempre; con `games/indy3.cfg`, `preview_hr` para trajes y sonidos). Deja `SCUMM.BIN`, `INDY3\INDY3.B81` y `INDY3\DATA\` (`DATA.BIN`, `OVLB.BIN`, `OVLC.BIN`, `OVLD.BIN`, 88 `ROOMnn.GFX`, `SND\SOUNDnnn.VGM`): **92 ficheros en `DATA` y 73 sonidos, ningun nombre con "_"**. Comprobado el montaje (`nocopia`, 3 s); la SD no se ha probado.
- `SCUMM.B81` (el BASIC): la entrada es `RAND USR 16917` (`$4215`), no 16914 como en v2.
- La cache de paginas ya va sin las 46-50 (5b), `ov_load_all` carga B, C y D desde `DATA/` y las entradas `OVB_*`, `OVC_*`, `OVD_*` y las de la API (`vm_load_room`, `vm_sentence`) estan en `scumm.asm` (hecho en 5b y 8; no habia nada que repetir).

### Guardar y cargar
Semantica de ScummVM (`o4_saveLoadGame`, `saveState`, `loadState`, `loadVars`): `a` = ranura (5 bits bajos) y orden (3 altos): `$00` ranuras (100), `$20` unidad (3), `$40` cargar (3 / 5), `$80` guardar (0 / 2), `$C0` existe (6 / 7). En v3 la ranura va de 1 y **el nombre de la partida es la cadena 9 + ranura** (el script del dialogo de Indy3, sala 14, la llena); al guardar se copian 31 caracteres. El dialogo es el script 9 (lo arranca el 8 con la tecla 319 = F5); guarda con `saveLoadGame` (variable 53 = orden + ranura) y lista los nombres con `saveLoadVars` 2 (cadenas 10..24 = partidas 1..15; ranura = id - a + 1; los caracteres fuera de 32-122 y el 64 salen como "_").
- **Modelo** (`vmmodel3.CoreVM`): `real_saves` (orden `OPT guardar 1`; en `scenarios-core` sigue el resultado simulado de antes), `save_game` / `load_game` (copia profunda del estado salvo lo que no es de la partida, `SAVE_SKIP`: fotograma, sucesos de entrada y raton, `res`, pila de `expression`, ordenes de sonido), `save_load_game`, `load_save_names`. `save_game` hace `update_script_ptr` (el script sigue justo despues del opcode al cargar); `load_game` pone el resultado 3 en la variable del cargar (como `setResult` tras `loadState`), para el sonido y vuelve a empezar el que sonaba (ordenes `STOP`, `STOP`, `LOOP`, `PLAY`). Ordenes de escenario `AT n save k` / `AT n load k`.
- **Z80** (`ovc9.asm`, overlay C, solo en el programa; el nucleo de pruebas no guarda): entrada fija `OVC_SLOAD` (+18; el bucle principal con `DBG_SAVE` = `SV+200`: byte alto 1 guardar / 2 cargar, bajo la ranura) y `OVC_NAME1` (+21; B la llama desde `sv_reset` para los nombres). `b_saveLoadGame` (`ovc1.asm`) llama a `sl_main` y escribe el resultado. Fichero de **14.943 B**: cabecera (18: `ld_hdr` y la direccion de `ev_handler`), nombre (32), OBJCLS (pagina 47, 3.000), el hueco del bloque 4 (actores, nombres, 52 verbos), el monton de cadenas (1.248), el reproductor de sonido (24), `MSGBUF` (320) y el bloque 7 entero (8.192). Al cargar se comprueba el tamaño y la cabecera **antes de tocar nada**; lo que no es de la partida (`DELTA`, `RESV`, `TOPOP`, `TOPSP` y `DS_SP`, `WINPG`, `OVLCUR` y `HOSTVEC`, `RAI`, `SC`, `INEV`...: `sl_live`) se guarda aparte y se repone tras leer el bloque 7; luego `aq_init`, `EV_ROOM_LOAD` (repinta la sala con `gf_load_room`), paleta, texto, verbos, objetos, sonido y `load_slot(CUR)`. Variables en `$9740-$97E8`. Overlay C: 5.376 B (2.816 libres).
- **Tecla:** **SHIFT + S = F5** (`ip_f5` en `ui3.asm`): sin ella la placa no tenia forma de abrir el dialogo.
- **El monton de cadenas era de 480 B y el dialogo pide ~1.155** (15 nombres de 51 B...): el modelo y el Z80 daban `E_RANGE` ("monton de cadenas lleno") al abrirlo con F5. **Ahora 1.248 B en `$9B20-$9FFF`** (`STRHEAP`, `STRMAX`, `vmcommon3.STR_HEAP`); `build_test.sh` sigue en 3.687/3.687. Margen: 93 B sobre lo que pide el dialogo.

### Pruebas (en el programa completo contra el modelo; `test/savetest.sh`)
- Guardar en el 300 y cargar en el 500: **701/701** iguales, 7 ordenes de sonido iguales; fichero de 14.943 B.
- Guardar en el 400 y cargar en el 700 (cruza salas: vuelve a la 79 y sigue hasta la sala 1): **901/901**, `check_hr.py` 0 distintos.
- El opcode **dentro de un script** (`SCUMM_SYNTH=test/synth_save.hex`: un script global 199 que Indy3 no usa; pone la variable 61 a 100, guarda, la pone a 200, cede el turno y carga): **401/401**; el modelo acaba con var60 = 3, var61 = 100 y el script terminado.
- El dialogo de Indy3 (guardar en el 1100, **F5 en el 1300**: sala 14, los nombres de las partidas): **1501/1501**, `check_hr.py` 0 distintos. Con SHIFT + S por la matriz del teclado: **1351/1351**.
- Autoconsistencia del modelo (guardar, seguir N fotogramas, cargar, repetir los N: iguales) en ocho puntos del arranque; solo difiere `in92` (contador de la proteccion, que no se guarda).
- Regresion con el codigo final: `build_test.sh` **3.687/3.687**, arranque **1.501/1.501**, Barnett **1.751/1.751**.
- Mutaciones: **no se han pasado** para `ovc9.asm` (tardan horas); el codigo nuevo lo cubren las pruebas de arriba, no `mutaciones.py`.

### COMMON (D1)
`SCUMM/COMMON/` lleva `mcu.asm`, `mouse.asm` y `font6.bin` (identicos en v2 y v3; los `include` de los dos son `../../COMMON/...`). **No se mueve el resto**: `loader.asm`, `dp_cache.inc`, `hr.asm` y `geom.asm` ya difieren (171, 342, 2.139 y 2.273 lineas de diff), `snd.asm` solo lo usa v2 (v3 tiene `snd3.asm`) y `walk.asm` y `arith32.asm` son de v3. Comprobado: el programa y el overlay de v2 salen **byte a byte iguales** antes y despues de mover, y `scumm.bin` de v3 tambien. Las pruebas de v2 tras mover: `build_test.sh` Maniac **2.917/2.917** y Zak **3.672/3.672** iguales (con los cambios sin commit de otras sesiones en `V2/ENGINE`).

### Limites del Z80 y pendiente
- Los puntos IQ de Indy3 (`saveLoadVars` 1 y 2 con las cadenas 7 y 9): sin fichero (como en la 4b). Si hay que guardarlos: `IQ.DAT` de 73 bytes en la carpeta del juego, desde y hacia la cadena 7.
- El sonido no se guarda: tras cargar vuelve a empezar el que sonaba desde el principio.
- Cargar dentro de un script anidado (`startScript` dentro de `startScript`) no esta probado (Indy3 carga desde el script del dialogo, de primer nivel).
- Una partida de otra version del programa o de otro `DATA.BIN` se rechaza (resultado 5).

### Corregido tras la primera prueba en la placa (2026-11-16): `R = 3` al entrar en el vestuario
El usuario pincha en la puerta del vestuario (sala 73) y, en la animacion que sigue, el programa sale al BASIC con `R = 3` (`E_RANGE`). Reproducido con el modelo (`AT 1300 click 125 90`): **"demasiados verbos"** en el fotograma 1.374: la escena llega a **38 verbos vivos** y `NUM_VERBS` era 36 (el arranque llega a 30). **`NVERB` y `NUM_VERBS` pasan a 52** (el hueco del monton viejo, `$920D-$93ED`, da para ellos: `VERBS` acaba en `$933D` < `PROF` `$9400`); la partida pasa a **14.943 B**. Con eso: `build_test.sh` **3.687/3.687**, la escena del vestuario **1.901/1.901** iguales (modelo y Z80), y el modelo sigue 9.000 fotogramas sin otro error (se queda en la sala 73). **Los limites del puerto (`vmcommon3.py`) son lo primero a mirar cuando la placa da `R = 3`**: antes de subirlos conviene medir el pico con el modelo (como arriba).

### El dialogo de guardar de Indy3 en la placa (2026-11-16, tras la 2.a prueba del usuario: "no hace nada pinche donde pinche")
El dialogo (sala 14) necesita cosas que el puerto no tenia. Hecho (probado en el arnes con capturas `render_hr.py`, sin placa):
- **Texto suelto y cajas** (`ENGINE/txtlayer.asm`): `print` en una posicion (EV_TEXT tipo 1; en el programa `print_free` convierte a `UIBUF`) y `drawBox` (el programa tiene `prog_host` en `HOSTVEC`) van a una capa (16 textos de 26 caracteres en `$8800`, 8 cajas en `$9600`) que `hr_makecol` compone encima de la sala (`ov_apply`); fuente de 6 px solo mayusculas, un `_` subrayado; una caja borra los textos que cubre entera; todo se borra al cambiar de sala. La caja se redondea a celdas de 8 px.
- **Ventana movil:** la pantalla ensena 256 de los 320 px de SCUMM y los botones del dialogo estan en x = 208-312. **El cursor a la derecha del todo (x >= 232) corre la ventana 64 px; con el cursor a la izquierda de x = 100 la devuelve** (antes 24: la lista de partidas se quedaba fuera de pantalla) (`pan_update`, `cam_update`, `in_conv` suma `pan_px`). Vale en todas las salas. El modelo lo replica para los sucesos con coordenadas de pantalla (`screen_event`, `pan_event`, `update_pan_px`).
- **`getStringWidth` estaba mal en modelo y Z80** (contaba todos los bytes que no eran 0 ni $FF, aunque vinieran detras del 0 final: el nombre vacio de una partida medio 392 y el dialogo rechazaba cada tecla). Ahora es el de ScummVM (hasta el primer 0, sin '@' ni codigos).
- **Limites:** `NUM_STRINGS` 32 -> 40 (el dialogo usa hasta la 33), `NUM_VERBS` 36 -> 52, montón de cadenas 1.248 B. **Bug:** `OVC_NAME1` recibia el id en `A` y `call_ovc` lo pisa: ahora lo lee de `SC+9`.
- **Como se usa:** SHIFT + S abre el dialogo. Botones (pantalla, con la ventana corrida salvo SAVE): **SAVE** = el de abajo a la izquierda del panel de la derecha (x 208-255, y 120-136); **OK / PLAY** = el de arriba a la derecha (x 264-312, y 96-112: hay que llevar el cursor al borde derecho y el clic cae 64 px mas a la derecha); **LOAD**: no localizado, probablemente el de abajo a la derecha (x 264-312, y 120-136) o la franja de x 208-312, y 96-112. Pasos: SAVE, clic en una fila de la lista, escribir el nombre, Intro, OK (sale "THE GAME WAS SAVED."). **Probado en el arnes:** abrir, SAVE, elegir fila, escribir ABC, Intro, OK: se crea `SAVE03.SAV` (14.943 B); LOAD y elegir la fila: pide "SELECT GAME TO LOAD, THEN SELECT OK." y la fila muestra ABC. **Sin probar:** el OK de la carga (cargar de verdad desde el dialogo), colores en la placa, rendimiento (cada cambio recompone la sala entera) y la regresion completa (`build_test.sh` 3.687/3.687 y la partida en el dialogo si, arranque y Barnett no se han repetido con la capa).

### Tras la 3.a prueba del usuario (2026-11-16; sin arnes: lo prueba el)
Visto en la placa: aparecen los botones (arreglado el orden de dibujo de `drawObject`), pero (1) la partida grabada no sale en la lista, (2) escribir es muy lento, (3) no se puede borrar, (4) los botones solo responden en su borde izquierdo. Cambios (sin probar):
- (1) Causa mas probable: con la ventana corrida (al pulsar OK/PLAY el cursor esta a la derecha) la lista queda fuera de pantalla (sus textos empiezan en x = 12). Ahora la ventana vuelve sola con el cursor a la izquierda de x = 100.
- (3) **SHIFT + 0 (RUBOUT) = borrar** (tecla 8), `ip_bs` en `ui3.asm`.
- (4) `in_conv` suma a la x de la escena lo que la ventana esta corrida DE VERDAD (camara del hardware menos la de SCUMM), no lo logico: el scroll tarda varios fotogramas y se pinchaba mas a la derecha de lo que se veia. Solo si la ventana esta corrida o volviendo; sin ella la x es la de siempre (las trazas del arnes no cambian).
- (2) Sin arreglar: la causa probable es el tiempo por fotograma en el dialogo (recomponer la sala y, sobre todo, el pitido de cada tecla: `startSound` pide al MCU abrir un VGM) y que el teclado se mira una vez por fotograma (una pulsacion corta entre dos miradas se pierde). Para arreglarlo hay que medir en la placa.

### Tras la 4.a prueba del usuario (2026-11-16; sin probar)
- **La cuadricula perdia sus bordes verticales** (solo quedaban en la mitad de abajo): el dialogo borra cada fila con `drawBox(12, y, 198, y + 7, 0)` y las cajas se redondeaban a celdas de 8 px, asi que se llevaban los bordes de x = 8 y x = 200. **Ahora las cajas son exactas en x** (`ov_box_col`: las celdas de los extremos se rellenan solo en los pixeles que cubre la caja; si el color de la caja es el papel de la celda se ponen a 0, si es la tinta a 1).
- Al abrir el dialogo la lista sale vacia: **es lo que hace el original** (la captura del usuario del dialogo de Indy3 la muestra vacia hasta pulsar SAVE o LOAD). Si se quiere ver ya, es una desviacion a pedir.
- **Texto en la lista:** el texto a la izquierda (x = 12) compartia celda de 8 px con el borde de la cuadricula (x = 8) y se lo llevaba: ahora empieza en la celda siguiente (x redondeada hacia arriba a multiplo de 8; el centrado no se toca). El sonido (efectos por el AY de la placa y musica por VGM) lo trata otra sesion.

### Tras la 5.a prueba del usuario (2026-11-16; sin probar)
- **El cursor "_" del nombre no avanzaba:** el script pinta el nombre y luego `_` con otro `print` sin `at`, y en ScummVM (`drawString`: `_string[a].xpos = _charset->_str.right`) la x de la ranura queda al final del texto. **Cambio en el nucleo (modelo `vmgame3.print_string` y Z80 `print_free`): despues de un `print` suelto, xpos += 8 por byte del texto convertido (centrado: la mitad).** Igual en los dos, pero **no se ha pasado `build_test.sh` con el cambio** (la sesion no tenia permiso para lanzarlo): hay que pasarlo antes de fiarse de las trazas.
- **Texto de la capa a 8 px por caracter** (como el original: glifo de 6 px y 2 de hueco), cada caracter es una celda: rasterizado mucho mas simple y rapido, y la posicion del cursor cuadra con el avance de xpos. El texto empieza en la celda de 8 px mas cercana.
- **Escribir mas rapido:** la capa ya no recompone la sala entera: marca solo las columnas que cambian (`ov_mark`, `ov_merge` en `hr_objupd`).
- **Izquierda / derecha al editar el nombre:** el dialogo original no los tiene (el script 200 solo trata caracteres, borrar (8) e Intro); SHIFT + 5 / SHIFT + 8 son las teclas que mueven el cursor del raton.

## Fase 10a: fallos de la placa (2026-11-16)

Regla de la fase 10: solo se ensambla; las pruebas (`build_test.sh`, arranque, Barnett, guardar/cargar) se pasan al final con permiso del usuario. Estado de cada fallo:

### 1. Sprites encendidos sobre el fondo borrado al cambiar de sala — ARREGLADO (sin probar en placa)
- **Causa:** `evh_room` (`scumm.asm`, suceso `EV_ROOM_LOAD`) llamaba a `gf_load_room`, que borra el bitmap (`hr_clear`) y lee `ROOMnn.GFX` de la SD (lo que tarda), y los sprites de los actores no se apagaban hasta el `actors_run` del fotograma siguiente (`aq_hold` -> `au_hide`).
- **Arreglo:** `evh_room` apaga antes los sprites 0-62 (`sh1` con B = 63; el 63, el cursor, se queda), pone `POKE 2131 = 0` (extras) y `aq_used = 0`. Las firmas de la caché caducan solas (los 2 fotogramas de `aq_hold` suben `aq_stamp`). Solo Z80 (el modelo no tiene sprites; el estado final de cada fotograma no cambia).

### 2. Indy por delante de la puerta del gimnasio (sala 73) — ARREGLADO (sin probar)
- **Causa:** la puerta de la izquierda (objeto 830, x 16-64) está tapada por la máscara de la sala (x 0-36, y 48-126) y la caja 6 (x 7-59, y 104) tiene máscara, pero `aq_mkdec` (`ovd_act.asm`) y `sprites3.py` **quitaban la máscara entera si la columna del borde izquierdo del fotograma era negativa** (`X0 = x + dx < 0`: Indy con x < ~12, justo al final del camino hacia la sala de al lado). No eran las máscaras de objeto (la de la 830 cae dentro de la de la sala).
- **Arreglo:** la tira inicial `aq_s0` admite -8..-1 (byte >= `$F8`; división con signo) y `mk_strip` trata las tiras negativas como vacías; en `sprites3.py`, `-64 <= X0`. Igual en modelo y Z80 (`check_spr.py` lo compara).
- Siguen sin hacer: máscaras de objeto y clases `NeverClip`/`ForceClip` (fase 8).

### 3. La caja del clic de un verbo solo respondía en su mitad izquierda — ARREGLADO (sin probar)
- **Causa:** no era el ancho del verbo (`V_LEN` = letras, rectángulo `[left, left + 8 * V_LEN)`, igual que `curRect` de `drawVerb` de ScummVM con la fuente de 8 px; `findVerbAtPos` es el de ScummVM). Era la conversión de pantalla a SCUMM: `hr_ui` pinta las 40 columnas de 6 px **centradas, con un byte (8 px) de margen** (columna c en el píxel 8 + 6c) y `in_conv` (`ui3.asm`) y `screen_to_scumm` (modelo) hacían `x / 6` sin restar el margen: la caja quedaba 8 px a la izquierda de la palabra (en "Use", 18 px, respondían los 10 de la izquierda).
- **Arreglo:** columna = `(x - 8) / 6` (x < 8: columna 0) en `in_conv` y en `vmmodel3.screen_to_scumm`. `test/ev_barnett.txt`: los dos clics en verbos pasan de x = 38 y 80 a **46 y 88** (siguen cayendo en Look y Walk to: las trazas esperadas de Barnett no cambian).
- v2 (`V2/ENGINE/ui.asm`, `ui_xcol`) resta 4, no 8: no se ha tocado (apuntado para quien lleve v2).

### 4. LOAD de una partida desde el diálogo se quedaba colgado — ARREGLADO en modelo y Z80 (sin pasar el arnés)
- **No era la SD ni el MCU:** se reproduce en el **modelo de Python** con `test/ev_f5j.txt` (F5, SAVE, fila, "ABC", Intro, OK; luego LOAD, fila, OK): `ERR 9` (`E_BUDGET`, un script sin ceder el turno) en el fotograma 2.161; en la placa no hay presupuesto y es un cuelgue. Las pruebas de la fase 9 cargaban con `DBG_SAVE` (entre fotogramas) o con un script sintético; **el OK de la carga del diálogo no se había ejecutado nunca**.
- **Causa:** al cargar, modelo y Z80 seguían el script en marcha **por donde lo dejó el guardado** (`save_game` hace `update_script_ptr` y `load_game` / `sl_load` hacían `load_slot(CUR)` con ese puntero). ScummVM no: `o4_saveLoadGame` acaba con `setResult; updateScriptPtr(); getScriptBaseAddress(); resetScriptPointer();` y `loadState` no toca `_scriptPointer`, así que la ranura `_currentScript` restaurada recibe el puntero **de ahora** y el script sigue **después del opcode de cargar**. En Indy3 el script 9 guarda en el desplazamiento 341 y carga en el 435: siguiendo por el 341 con resultado 3 el diálogo entraba en un bucle (`wait` + `jumpRelative` del script 203).
- **Arreglo:** modelo (`vmmodel3.load_game`): si hay script en marcha al cargar, `slots[cur].offs = ptr` de ahora antes de `load(cur)`. Z80 (`ovc9.asm`, `sl_load`): antes de tocar el estado guarda `CUR` (`sl_ccur`) y la página, `SL_BIG` y `SPTR` de la ranura en curso (`sl_cpos`, `$97DB-$97DF`) y, tras restaurar, los escribe en la ranura `CUR` restaurada antes de `load_slot`. Cargando desde el bucle principal (`DBG_SAVE`, `CUR = $FF`) todo sigue como antes (las pruebas `ev_save*.txt` no cambian). Con el arreglo el modelo sale del diálogo y vuelve al gimnasio (sala 73) sin errores hasta el fotograma 2.600.
- **Diferencia consentida:** si la ranura restaurada no es el mismo script que el que carga (no pasa en Indy3: guarda y carga el script 9), ScummVM sigue en el script restaurado con el desplazamiento de ahora y el Z80 en la página del que cargaba.
- `test/savetest.sh` lleva una sexta prueba (`ev_f5j.txt`, 2.600 fotogramas): **no se ha pasado**.
- **Ojo en la placa:** las partidas guardadas con el programa anterior se rechazan (la cabecera lleva la dirección de `ev_handler`, que ha cambiado): hay que guardar de nuevo.

### Estado al cerrar la sesión (2026-11-16)
- Montaje con `compila_scumm.bat nocopia`: bien. Residente `$4200-$795C` (**1.700 B libres** hasta `$8000`), overlay B código hasta `$1D00`, C hasta `$1322` (5.632 B el fichero), D hasta `$18B8` (6.328 B).
- **Sin pasar (falta el permiso del usuario):** `build_test.sh` (3.687), arranque (1.501), Barnett (1.751, con `ev_barnett.txt` retocado), `savetest.sh` (5 + la nueva) y `check_spr.py` (el cambio de la máscara). Tampoco está validado con `build_test.sh` el commit `07aca58` ni el cambio de `xpos` de `print` de la 5.ª prueba.
- Sin commit.

### Tras la prueba del usuario en el emulador (2026-11-16): fallos 1 y 4 bien, el 2 seguía y "TALK y TRAVEL no se pueden seleccionar"
- **Fallo 2, causa de verdad (la de arriba no lo era; el arreglo de las columnas negativas se queda, hace falta al final del camino):** al pinchar en la puerta de la izquierda (objeto 830) el script pone a Indy en **`ignoreBoxes`** y lo lleva de x = 65 a x = 10 con **caja 255** (`kOldInvalidBox`; visto en el modelo: fotogramas 1.316-1.323). En v3 `getMaskFromBox(255)` de ScummVM **devuelve 1** (WORKAROUND de los bugs #791 y #897: el intérprete original lo hacía así), o sea, el actor sin caja va **con máscara**. `aq_mkdec` y `sprites3.py` exigían `caja < NBOXES` y lo dejaban sin ella. **Arreglo:** caja 255 = con máscara (`mk_box` en `ovd_act.asm`; `wbox == 255` en `sprites3.py`). Ensamblado; sin probar. Vale para cualquier actor que ignore las cajas en cualquier sala (puede cambiar cómo se ven otras escenas: es lo que hace ScummVM).
- **TALK y TRAVEL:** no es un fallo del clic. En el gimnasio el juego los tiene **atenuados** (`curmode` = 2; el modelo en el fotograma 1.290: verbos 13 y 14) y `findVerbAtPos` de ScummVM solo acepta `curmode == 1`. Lo que falta es **pintarlos atenuados** (pendiente de la fase 7: "verbos atenuados sin color"), para que se vea que no están disponibles. Forma barata si se quiere: atributo por grupo de 4 columnas en `hr_ui` (en Indy3 ningún grupo de 24 px lleva dos verbos) con el color apagado para `curmode` 2, forzando el repintado del grupo cuando cambia el modo. **Hecho el 2026-11-16 (lo pidió el usuario), ver abajo.**
- Montado con `compila_scumm.bat` (copiado a la SD del emulador). Overlay D hasta `$18BC`; residente igual (`$795C`).

### Verbos atenuados (2026-11-16, pedido por el usuario; ensamblado, sin probar)
- `ui_verb` (`ui3.asm`): un verbo con `curmode` 2 escribe sus letras en UIVB con el **código - 128** (80-127; los normales siguen en 208-255) y deja en `ui_dimc` el atributo `ega2chroma[V_DIM]` (Indy3: `dimcolor` 8, gris oscuro; 0 -> 8). `hu_group` pinta el mismo glifo y, si el grupo de 4 columnas (24 px) lleva alguna letra atenuada, `hu_clr` da `ui_dimc` en vez de `$0F`. Como el código de UIVB cambia, `hr_ui` repinta el grupo solo cuando el verbo pasa de activo a atenuado o al revés. Variables `ui_dimf`, `ui_dimc`, `hu_dim` (`UIV+35..37`).
- **Límite:** el atributo es por grupo de 4 columnas: si un verbo atenuado y uno activo compartieran grupo, los dos saldrían atenuados (en Indy3 no pasa: columnas 0, 6, 13, 22 y 32). Sigue sin hacer el color por verbo (`color`, `hicolor` al pasar el ratón).
- `test/check_hr.py` entiende los códigos 80-127 (mismo glifo). El modelo no cambia (UIVB es solo del Z80).
- Residente `$4200-$79A6` (**1.626 B libres** hasta `$8000`). Copiado a la SD del emulador con `compila_scumm.bat`.

## Fase 10b: velocidad del scroll del pasillo (2026-11-16; solo ensamblado, sin pasar las pruebas)

**Medida** (`test/`, tras `sh ../build_scumm.sh` y copiar `prog/ovl?.bin` a `build/sdboot/DATA/`): arranque con `TS_NOSTOP=1 TS_MODELDELTA=1 TS_T=1 TS_PROF=582-760 build/test_scumm.exe prog/scumm.bin prog/scumm.sym build/sdboot 760 x.bin` (el pasillo, sala 1, desde el fotograma 582, con la camara siguiendo a Indy). Herramientas nuevas del arnes (`test_scumm.cpp`): `TS_LOOPS=n` (una linea `V vuelta T rutinas...` por vuelta, las n rutinas que mas pesan), `TS_WATCH=simbolo` (imprime el fotograma, `hv_c0/c1/ch`, `ov_dc0/1` y los registros cada vez que el PC pasa por ahi) y los simbolos de los overlays B, C y D (bloque 0) en el perfil (`B:`, `C:`, `D:`; antes salian como `?`, el 25 %).

| | media | mediana | p90 | maxima | sin las 2 vueltas que leen de la SD: media / maxima / vueltas > 325.000 |
|---|---|---|---|---|---|
| antes | 362.787 | 174.288 | 1.100.705 | 3.728.793 | 334.497 / 1.306.870 / 38 de 176 |
| despues | **192.782** | 161.025 | **271.147** | 3.728.793 | **167.050 / 404.736 / 4 de 176** |

(Las vueltas 583 y 705 son lecturas de la SD, `frd_l`/`mcu_rw`: 3,7 M la carga de la sala y 1,2 M la 705; no son del scroll.)

**Causa de los picos de ~1,2 M (cada 3-4 vueltas):** no era el scroll (cruzar de columna cuesta una columna, ~30.000 T), sino `hr_objupd`: en el pasillo cambian de estado objetos pequenos casi cada fotograma (columnas 45-49, 71-76, 101-114) y se recomponia **un solo rango del minimo al maximo** (p. ej. 71..112): casi las 34 columnas (`hs_l` 409.000 T y `hfc2` 202.000 en una vuelta).

**Cambios** (lo que se ve no cambia: se recomponen las mismas columnas que han cambiado, con el mismo codigo):
1. `hr.asm`: **columnas sucias en un mapa de bits** (`HR_DIRTY` = `HR_ATT+$1980`, 32 bytes, un bit por columna del mundo; en el bufer de abajo del scroll vertical, que no se usa). `hr_objupd` marca las columnas de cada objeto que cambia (`hr_omark`) y solo recompone las de pantalla y bufers marcadas; `ov_merge` (`txtlayer.asm`) marca las de la capa de texto (`hr_dmark`); `gf_draw_window` borra el mapa. Diferencia con lo de antes, solo en un caso raro: un objeto que un `drawObject` sube de orden sin cambiar su "se dibuja" ya no se redibuja por casualidad cuando queda entre dos objetos que si cambian (antes tampoco se redibujaba si no habia otro cambio).
2. `hr.asm`: `hr_stride` desenrollado (8 bytes por vuelta, `inc l`): 33 T por byte en vez de 48.
3. `hr.asm`: `hr_mkdl` marca en `HR_ZFL` (`HR_ATT+$1A60`, 84 bytes) los objetos de `OV_ZL` en vez de buscar cada objeto en la lista (`ov_inzl`, 1,1 M); para indices de 84 o mas sigue buscando.
4. `ovc5.asm` (`drawObject`, `do_state`): recorre los registros con un puntero (-14) en vez de `rec_addr` por objeto; `SC+6` acaba en 0 como antes.
5. `scumm.asm` (`obj_drawn`): aprovecha el registro del objeto para mirar el padre (antes `od_rec` dos veces).

Tamanos: residente `$4200-$7A2A` (**1.494 B libres** hasta `$8000`), overlay C igual (5.632 B).

**Lo que queda pesando** (despues): las 4 vueltas de 330.000-405.000 T mezclan columnas recompuestas, `drawObject` (`C:dr_l`), actores (`D:acd_cell`) y la interfaz (`hg_l`, `hu_cmp`: la 698). Sin un punto caliente claro: `hou_l` (comparar banderas por objeto, 0,8 M), `hd_l`/`hr_mkdl` (los dos `ldir` de 84 bytes por llamada), `obj_drawn`/`od_rec` (multiplicar por 14). La recomposicion de objetos de las salas 20/28 es la 10c.

6. `txtlayer.asm` (tras las pruebas): el texto y la caja que se pierden por turnos (16 textos y 8 cajas llenos: `ov_rr2`, `ov_rr`) marcan sus columnas como sucias. Antes no lo hacian y el rango minimo-maximo lo tapaba a veces. Residente hasta `$7A57` (**1.449 B libres**).

**Pruebas (2026-11-16, con permiso del usuario):** `build_test.sh` **3.687/3.687**; pasillo hasta el fotograma 760 (scroll) **761/761** y `check_hr` 0 distintos; arranque **1.501/1.501**, `check_hr` 0; Barnett **1.751/1.751**, `check_hr` 0; `objflip.sh` en las salas 20 y 28 (objetos que cambian en cada fotograma) `check_hr` 0 distintos en los 8 volcados; `savetest.sh` (repetido despues del cambio 6): **701, 901, 401, 1.501, 1.351 y 2.601 iguales**; `check_hr` 0 en "cruzando salas". En el dialogo F5 (sala 14) `check_hr` da **8 distintos**, y son correctos: el glifo "0" del texto de la capa en x = 216, y = 21 (encima de la caja 1 del dialogo), que esta en `OV_TXT`; `check_hr.py` no modela la capa de texto. En la fase 9 dio 0 porque ese texto no caia en la parte visible; la 10a cambio la `x` de `print` y esta prueba no se habia vuelto a pasar.

r
**Falta:** la placa. Sin commit.
## Fase 10c: recomposicion de objetos en las salas 20 y 28 (2026-11-16; solo arnes, sin placa)

**Medida** (`test/objflip.sh 20` y `objflip.sh 28`: 2 objetos al azar cambian de estado en cada fotograma, `TS_PROF=30-150`; para ver las rutinas por vuelta, el mismo `test_scumm.exe` con `TS_LOOPS=n`):

| | media | mediana | p90 | maxima |
|---|---|---|---|---|
| sala 20 antes (tras la 10b) | 336.409 | 268.268 | 595.654 | 773.808 |
| sala 20 despues | **296.946** | 268.285 | **396.272** | **612.902** |
| sala 28 antes (tras la 10b) | 450.177 | 324.728 | 864.143 | 1.511.340 |
| sala 28 despues | **375.332** | 317.120 | **519.463** | **849.790** |
| pasillo (`TS_PROF=582-760`, sin las 2 vueltas de la SD) antes | 167.050 | | | 404.736 (4 vueltas > 325.000) |
| pasillo despues | **150.609** | | | **351.130** (2 vueltas > 325.000) |

(Pasillo con las vueltas de la SD: media 192.782 -> 176.293, p90 271.147 -> 220.968.)

**La sala 20 ya cabe de media en los 325.000; la 28 no, pero no por los objetos:** una vuelta de la sala 28 en la que no cambia nada ya cuesta **~310.000 T** (scripts y actores: `loc_addr` 19.125 por vuelta, `D:mk_strip`, `es_hi`, `vr_x`, `D:mp_*`, `B:ex_push/pop`...). Lo que queda de recomponer son unos 65.000 T por vuelta de media con 2 objetos cambiando en cada fotograma (una prueba de esfuerzo: el juego cambia mucho menos), y es copia de datos de verdad (`hs_l`, `hfc2`). La vuelta mas cara (849.790, la 58) es un calculo de camino de la caminata (`D:mu_l`, `D:cpb_l`, `D:cplin`, `D:sqd`: ~200.000 T): para la 10d. Lo siguiente que pesa en las actualizaciones es comparar banderas y rehacer la lista (`obj_drawn`, `od_rec`, `hou_l`, `hd_l`, `hr_mkdl`: ~25.000 T por actualizacion).

**Por que pesaba:** se recomponian las **128 lineas** de cada columna de un objeto que cambiaba (en la 28 los objetos son de 24-32 columnas; el 3 y el 13, en las lineas 152-184, ni se ven y se recomponian sus 32 columnas), y en cada columna se recorria **toda** la lista de objetos (`hm_o`), `ov_apply` borraba 128 bytes de `OV_FLG` (2.700 T por columna) y los dos estados de una animacion (6/16, 7/17...: mismo sitio) se recomponian dos veces.

**Cambios** (`hr.asm`, `txtlayer.asm`; lo que se ve no cambia):
1. `hr_orect` sustituye a `hr_omark`: de cada objeto que cambia se recompone ya su **rectangulo**: sus columnas en pantalla o en los bufers y solo sus lineas (`hv_y0` / `hv_y1`, redondeadas a 8). `hr_makecol` copia el fondo solo de esas lineas (`hv_wlo` / `hv_whi`, y `hm_clip` recorta a ellas) y `hr_put` escribe solo esas (`hp_s`, `hp_n`; `hs_l` entra con C = grupos de 8). Las columnas sucias de la capa de texto siguen enteras: `ov_merge` va ahora antes y `hr_orc` se salta esas columnas. Por defecto (0 y 0) son las 128 lineas: el scroll, la oscuridad y `gf_draw_window` no cambian.
2. `hr_ofilt`: lista de los objetos de `HR_DLIST` que tocan el rectangulo, en su orden, en `HR_DLIST+128` (`hv_dlo` = 128, `hv_ndl` = final; `hv_ndls` guarda el de antes). Si un objeto tapa el rectangulo entero (son opacos), la lista empieza por el y no se copia el fondo (`hv_nobg`).
3. `hr_rdup`: un rectangulo dentro de otro ya recompuesto en este `hr_objupd` no se repite (`HR_RECTS` = `HR_BM+$1900`, hasta 32, en el bufer de abajo del scroll vertical; `hv_nr` = `SV+242`).
4. `hm_o`: `hm_clip` antes de multiplicar (los objetos que no caen en las lineas no multiplican).
5. `txtlayer.asm`: `ov_apply` solo borra `OV_FLG` si un texto lo ha marcado (`ov_fok` = `SV+215`, el byte alto de `ov_xx`, que no se usaba).

Variables: `hv_y0`/`hv_y1` = `HV+32/33` (eran `hv_c0`/`hv_c1`, sin uso desde la 10b), `hv_wlo`, `hv_whi`, `hv_dlo`, `hv_ndls`, `hv_nobg` = `HV+45..49` (hasta `SV+149`). **Residente hasta `$7C6F`: 913 B libres** (eran 1.449; +536 B). Overlays igual.

**Pruebas (especificas, 2026-11-16):** `objflip.sh 20` y `objflip.sh 28`: `check_hr` **0 distintos** en los 10 volcados; `build_boot.sh 760` (pasillo con scroll) **761/761** iguales, 3 ordenes de sonido iguales y `check_hr` 0 distintos. `check_hr.py` no modela la capa de texto: el cambio 5 es igual por construccion (`OV_FLG` solo lo escribe `ov_text_col`, que pone `ov_fok` a 0); en la noche, `check_hr` del dialogo F5 tiene que seguir dando los mismos 8 distintos del texto.

**Falta:** la placa y la prueba de la noche. Sin commit.

## Fase 10d: caminata, scripts y actores (2026-11-17; solo arnes, sin placa)

**Prueba de la noche:** `ENGINE/test/build/noche/2026-11-17.txt` no existe: la tarea de Windows "SCUMM v3 pruebas noche" **no se ha ejecutado nunca** (`LastTaskResult` 267011, "aun no se ha ejecutado"; la proxima, el 18/11 a las 02:00). Nada que contar de ella.

### Caminata (overlay D; `geom.asm`, `walk.asm`; medidas con `TS_VM=1 build_test.sh "..." 1 "1,15,20,28,43,47"`, 1.609 escenarios)

| | antes | despues |
|---|---|---|
| `walk_frame` que arranca, cambia de tramo o llega: media / maxima | 148.198 / 1.428.728 | **19.158 / 79.454** |
| `walk_frame` con varios actores: maxima | 1.353.490 | **98.933** |
| `walkActorTo` (1E): media / maxima | 70.230 / 3.877.573 | **37.687 / 1.110.937** |
| `walkActorToObject` (36): media / maxima | 20.091 / 628.035 | **12.383 / 289.677** |
| `walkActorToActor` (0D): maxima | 391.216 | **257.176** |

(Las cifras de la fase 6, 134.670 / 1.467.429, eran de las 88 salas; estas son de las 6 de caminata.)

**Por que costaba:** cada cambio de tramo llama a `getGates` (8 `getClosestPtOnBox` = 32 `closestPtOnLine`) y, si el actor llega al punto de la puerta en el mismo fotograma, otra vez con la caja siguiente (como `Actor_v3::walkActor` de ScummVM: el `do ... while` sigue de caja en caja). La vuelta de 1,43 M eran 2 `getGates` con 36 `closestPtOnLine` "generales" (aristas inclinadas) de ~38.000 T cada una (pila de 32 bits y `mul32`). `walkActorTo` llama a `adjustXYToBeInBox`, que con un clic a mas de 80 px de todas las cajas hace `getClosestPtOnBox` en TODAS (54 cajas en la sala 43, 37 en la 47).

**Cambios** (mismo resultado que ScummVM, que lo calcula todo en el mismo fotograma; no se reparte entre vueltas):
1. **Tabla de puertas** (`pack_data3.gate_table`): `getGates` solo depende de las dos cajas, y en v3 las coordenadas de las cajas no cambian (`o5_matrixOps` de v3 solo cambia banderas). El empaquetador calcula, con `vmgame3.get_gates` (el modelo), las puertas de cada par (caja, siguiente) que puede dar `getNextBox` (las ternas de la matriz, mas el WORKAROUND de la sala 46): 1.094 pares en Indy3, 12.408 B en `DATA.BIN`; la mayor, la sala 43 (112 pares, 1.233 B). Entrada de 11 B: caja 1, caja 2, lineas de gateA y gateB (como `set_gate`: linea < 4, esquina de la caja 1 y el punto; si no, el punto y la esquina de la caja 2) y los dos puntos. `ROOMDIR +22`: pagina, direccion y bytes. `gt_load` (`ovc5.asm`, overlay C) la copia al cargar la sala (`ovc_room`) **y al cargar una partida** (`ovc9.asm`) a la pagina `CLS_PG` (47) desde `GT_OFF` = `$0C00` (tras OBJCLS, 3.000 B; hasta `GT_MAX` = 2.048), por la ventana y de 256 en 256 por `GW`, con la sala (`ROOMRES`) en el primer byte. `gates` (`geom.asm`) la busca con `cls_open`; si la sala no coincide o el par no esta, calcula como antes. Coste de un cambio de tramo con tabla: ~5.000 T de busqueda.
2. **`closestPtOnLine` general reescrita** (`cpl_gen`): el mismo calculo de C (int de 32 bits que desborda, division truncada) por valores absolutos con signo aparte: `|lu|`, `|lv|`, `|su|`, `|pu|` caben en 16 bits; `a` cabe en 16 (`|lv| <= |lu|`); `t*lv*lu = |t| * (|lv|*|lu|)` modulo 2^32 (`mul_lo`); divisiones de 32/16 (`ud3216`). Sin pila de 32 bits (`gpush`/`gpop`/`gmul`/`gdiv`/`smul` fuera). Comprobada antes en Python contra `vmgame3.closest_pt_on_line` con 200.000 casos (la mitad con coordenadas s16 extremas): 0 distintos.
3. **`adjustXYToBeInBox`**: (a) `checkXYInBoxBounds` solo en la primera pasada (si se llega a la segunda, el punto no esta en ninguna caja: las que la primera no miro estan a mas de 30 px de sus 4 esquinas en x o en y, y `checkXYInBoxBounds` las descarta por lo mismo); (b) `inBoxQuickReject(umbral)` es "distancia al rectangulo envolvente > umbral" (`ax_bd`, minimo y maximo de las esquinas), calculada una vez por caja en la primera pasada y guardada para la segunda (`ADB`, hasta 125 cajas); (c) `getClosestPtOnBox` con poda por arista (`cpb_t`): `closestPtOnLine` deja siempre la coordenada del eje mayor de la arista dentro del segmento, asi que `d * d` (d = distancia del punto a ese intervalo) es una cota inferior exacta; una arista con cota >= min(mejor de la caja, `AXBEST`) no se calcula (la caja solo cuenta si da menos que `AXBEST`; la primera arista con la menor distancia nunca se poda, asi que el punto es el mismo). `getGates` sigue usando `cpb` sin poda (necesita el punto aunque pase de 65.535).

**Lo que queda:** `walkActorTo` llega a 1,1 M en un clic de la sala 47 con y = 151 (fuera de los 128 px de la sala: no lo da el raton) y a ~0,4-0,6 M en clics lejos de las cajas en salas de muchas cajas: son `closestPtOnLine` generales de verdad (~15-25.000 T cada una: multiplicaciones y divisiones de 16 vueltas). Lo siguiente seria multiplicar con tabla de cuartos de cuadrado (1 KB) o desenrollar `mul16u`/`dv16`.

### Scripts de la sala 28 y los demas (residente, overlays B y C)

Perfil de la sala 28 parada (`TS_POKE="2:<DBG_ROOM>:1C,2:<DBG_ROOM+1>:0" TS_T=1 TS_PROF=30-150 TS_LOOPS=14 TS_VM=1`): 95 instrucciones de script por vuelta, el **58 %** de la vuelta: `expression` (10 por vuelta, 3.818 T), `isActorInBox` (10, 2.913), `getObjectState` (12, 1.224), `startScript` (2, 8.214), `drawObject` (2, 3.831)...; ademas `loc_addr` (125 llamadas por vuelta: 19.125 T) y un actor animado (~40.000 T de sprites). En la sala 70, un script divide 5 veces por vuelta en `expression`: `div32s` eran **43.000 T por vuelta**.

**Cambios:**
4. `div32s` (`arith32.asm`, residente): con divisor de 16 bits, una o dos divisiones de 16 vueltas (`d32_16`) en vez de 32 vueltas lentas. Mismo cociente (sin signo y con el signo despues, como antes; INT_MIN igual).
5. `loc_addr` (residente): 153 -> 115 T (sin `push`/`pop de`; las comprobaciones en el mismo orden).
6. `ex_push`/`ex_pop` (`ovlb.asm`, `expression`): sin `ldir` en el push (ESTK no cruza un limite de 256 B: comprobado al ensamblar).
7. `isActorInBox` (`ovc5.asm`, `axis_rej`): fuera de [menor, mayor] de las 4 esquinas con minimo y maximo por registros, en vez de contar esquinas con `sless` y variables.

En la sala 28 parada: `expression` 10 por vuelta, `isActorInBox` 10, `getObjectState` 12; con los cambios 4-7 y los de los actores (abajo) la vuelta baja
de ~283.000 a ~255.000 T. La vuelta de 574.314 de HEAD era un calculo de camino (cambio de tramo): ahora no pasa de 291.638.

### Actores (overlay D, `ovd_act.asm`)

8. `aq_mask_px` (mascara de la sala por pixel): una variante del bucle de 8 filas por desplazamiento (0-7), con `sla c / rla` desenrollado y la tira siguiente en IY; antes, un bucle de desplazamientos por fila con pilas (`mp_s` + `mp_r` + `mp_a` = 184.000 T en una vuelta de la sala 15 con 6 actores).
9. `ldir` de 8 bytes (forma, mascara, color, mascara al sprite) -> 8 `ldi`.
10. `acd_cell`: x + 32 y la fila + `HR_TOP` + 32 - `hv_ytop` se calculan una vez por actor (`aq_x32`, `aq_y32` = `AC2V+12/14`, que estaban libres); `8 * cy` = `(pos >> 1) & $78`.

**Segunda tanda (2026-11-17, tarde, pedida por el usuario: "sprites aqui"):**
11. **Camino directo de la mascara**: si el actor no tiene mascara de la sala (`aq_mk` = 0) y las 8 filas de la celda caen en `[AC_YMIN, AC_YMAX)`, `aq_mask_px`
    no se llama y `aq_clip` no cambia nada, asi que la mascara de la celda (o 8 x `$FF`) va directa a los registros del sprite (`aq_sm`) sin pasar por `aq_mt`
    ni `acd_mput` (`aq_drc` = 1). Si no, el camino de siempre.
12. La tabla de celdas del traje se calcula una vez por actor (`aq_ctab`; `aq_ctab` y `aq_drc` en `AC2_END..+2`, en los 41 B libres hasta `ROOMPAL`); el
    puntero de la celda va en la pila y su posicion en C; los rellenos de 8 bytes (mascara completa, color uniforme) desenrollados (`acd_ff`/`acd_fa`).
13. `aq_slot`: `sl_ok` no reescribe los 3 punteros si ya son los de los sprites normales; `sl_xok` calcula la entrada `32 * j` y sus campos con sumas de 8 bits
    (no cruzan un limite de 256 B) en vez de `push`/`pop` y sumas de 16.
14. Mascara: `mk_strip` borra solo las `aq_rh` filas de cada tira (las celdas salen de la rejilla del fotograma, `costume3.py`, y nunca leen mas abajo);
    las variantes de desplazamiento 5, 6 y 7 desplazan `tira:siguiente` a la derecha 3, 2 y 1 veces (`srl a / rr c`: el mismo byte).

### Cifras de las vueltas (programa completo, `test_scumm.exe`; `test/loops_nosd.py` quita las vueltas que leen de la SD)

Misma prueba con HEAD (dcea8c3, montada aparte) y con la 10d. Sala 28 parada: `TS_POKE` a `DBG_ROOM` = 28, `TS_PROF=30-150`. Salas 70, 20 y 15:
`mk_actscen.py` (semillas 1, 2 y 2; 24 escenas de 1 a 6 actores al azar que cambian cada 4 fotogramas; una de cada cuatro con 6 de los trajes
mas grandes, que no caben en 63 sprites): es una prueba de esfuerzo (todos los actores se redibujan a la vez). Guion: `medir4.sh` (en el
scratchpad de la sesion; son las ordenes de abajo).

| vueltas sin las de la SD | media | p90 | maxima | > 325.000 |
|---|---|---|---|---|
| sala 28 parada, HEAD | 282.914 | 281.601 | 574.314 | 3 de 120 |
| sala 28 parada, 10d | **245.834** | 247.468 | **283.246** | **0** |
| sala 70, HEAD | 234.488 | 322.916 | 368.853 | 14 de 145 |
| sala 70, 10d | **185.694** | 253.402 | **290.568** | **0** |
| sala 20 (1-6 actores), HEAD | 250.182 | 352.523 | 486.898 | 26 de 143 |
| sala 20 (1-6 actores), 10d | **227.774** | 308.676 | **352.151** | **7** |
| sala 15 (1-6 actores, mascara), HEAD | 169.073 | 241.235 | 583.134 | 16 de 209 |
| sala 15 (1-6 actores, mascara), 10d | **161.086** | 232.654 | **442.710** | **9** |

Ordenes: `TS_POKE="2:<DBG_ROOM>:1C,2:<DBG_ROOM+1>:0" TS_NOSTOP=1 TS_T=1 TS_PROF=30-150 TS_LOOPS=14 build/test_scumm.exe prog/scumm.bin prog/scumm.sym build/sdboot 160 x.bin`;
para las escenas, `python -I mk_actscen.py prog/scumm.sym build/sdboot/DATA/DATA.BIN 2 "20" 24`, su linea 1 en `TS_POKE` y `TS_PROF=18-<linea 3>`; luego
`python -I loops_nosd.py salida.txt`. Con `TS_VM=1` sale ademas el reparto por opcode.

### Pruebas (especificas)
- Nucleo (`build_test.sh` con salas): `1,15,20,28,43,47` **1.609/1.609**, `41,44,46,60` **1.404/1.404** (la 46 es la del WORKAROUND y la matriz truncada),
  `28,70` **1.400/1.400**, `70` **1.355/1.355** (tras el ultimo cambio de B).
- `wlk_test.py` (600 caminatas con coordenadas extremas y desbordamientos de 32 bits): **600/600**. `ibx_test.py` (`isActorInBox`): **600/600**.
  `exp_test.py` (nuevo, 600 `expression` con divisiones): **600/600**.
- `cpl_gen` en Python contra `vmgame3.closest_pt_on_line`: 200.000 casos, 0 distintos (antes de pasarlo al Z80).
- `pack_data3.py ... check`: la tabla de puertas se lee de vuelta; cada entrada se descodifica y se compara con `get_gates` al empaquetar.
- Programa: `build_boot.sh 760` (pasillo) **761/761**, 3 ordenes de sonido iguales, `check_hr` 0 distintos; `savetest.sh` **701, 901, 401, 1.501, 1.351 y
  2.601 iguales** (en el dialogo F5, los 8 de `check_hr` de la capa de texto de siempre).
- Sprites (con la segunda tanda; ojo: no pasar dos `actscen.sh` a la vez, comparten `build/spr_dump.bin.*`): `actscen.sh 1 "15,20,70" 8`: 24 escenas, las 16 de las salas 15 y 20 sin diferencias; las 8 de la sala 70 con **2 sprites distintos cada una,
  exactamente igual que HEAD** (comprobado montando HEAD aparte: las mismas lineas). No es de esta fase: los actores 8 y 10 los mueven los scripts de la
  sala y `check_spr.py` avisa de que su contador de poses "no vale"; la prueba de la noche no mira la sala 70.
- No se ha pasado la bateria ni `mutaciones.py` (regla del 2026-11-16): esta noche.

### Tamanos
Residente hasta **`$7CAD`: 851 B libres** (eran 913: +64 B de `div32s`/`d32_16`, -2 de `loc_addr`). Programa: overlay B 7.936 B (codigo hasta `$1CFF`:
**queda 1 byte** antes de que su tabla salte a `$1E00` y B se llene), C 5.632 B (codigo hasta `$1396`), **D 7.163 B** (eran 6.332; 1.029 libres). Nucleo de
pruebas: D 4.897 B. Pagina 47 (`CLS_PG`): OBJCLS 3.000 B + tabla de puertas en `$0C00-$13FF`. Bloque 7: sin cambios de sitio (`CBT`/`CBTH` en `GW+229`,
que era `AXD`, sin uso; `aq_x32`/`aq_y32` en `AC2V+12..15` y `aq_ctab`/`aq_drc` en `AC2_END..+2`, libres): las partidas guardadas siguen valiendo. `DATA.BIN` cambia (`ROOMDIR +22`):
`compila_scumm.bat` lo regenera siempre; un OVLD nuevo con un `DATA.BIN` viejo funciona (0 entradas: calcula como antes).

### Herramientas nuevas del arnes
- `test_vm.cpp`: `TS_WKD=n` (una linea por `walk_frame` de mas de n T con las llamadas a `gates`, `fpo`, `cplin`, `cpl_gen`, `cpb`, `adjust_xy`, `cxb`...), `TS_BIG=n` (una linea por instruccion de script de mas de n T: escenario, opcode y esas llamadas), maximo por opcode en la tabla de `TS_VM`.
- `test_scumm.cpp`: `TS_VM=1` vuelve a funcionar con el nucleo de v3 (`es_go`): instrucciones de script por vuelta y T por opcode.
- `test/loops_nosd.py`: resumen de las lineas `V` de `TS_LOOPS` sin las vueltas que leen de la SD.
- `test/exp_test.py`: 600 `expression` al azar con divisiones (dividendos de 32 bits, divisores de 16 y 32, con signo) contra el modelo.

### Falta
- **La placa** (todo lo de arriba es arnes) y la prueba de la noche (la primera sera la del 18/11).
- **Salas con 4-6 actores redibujados a la vez** (prueba de esfuerzo): la 20 pasa de 325.000 en 7 de 143 vueltas (max. 352.151; eran 26) y la 15, con
  mascara de profundidad, en 9 de 209 (max. 442.710; eran 16). Sin mascara, una celda cuesta ya ~900 T (90 celdas en la peor vuelta de la 20, y ~200.000
  T de scripts de la sala). En la 15 manda la mascara de la sala: descodificarla (`mk_strip`/`mk_run`, ~45.000 T en la peor vuelta) y aplicarla por
  celda (`aq_mask_px` y sus variantes, ~90.000). Bajarlo mas pide otro diseno, no recortes: conservar la mascara descodificada de un actor que no cambia
  de tira ni de fila (`MKBUF` es una sola para todos), o reescribir solo las posiciones de un actor que solo se mueve. En el juego, 6 actores que cambian
  de postura en el mismo fotograma son raros.
  **PENDIENTE (usuario, 2026-11-17): conservar la mascara descodificada por actor** (no volver a descodificar `MKBUF` si el actor no cambia de tira ni de
  fila; hoy hay una sola para todos) para bajar las 9 vueltas de la sala 15. Apuntado; no se ha empezado.
- `walkActorTo` con clics lejos de las cajas en salas de muchas cajas (0,4-0,6 M; 1,1 M con y fuera de la sala): `closestPtOnLine` general (~15-25.000 T).
- El resto de los scripts de la sala 28 (~150.000 T por vuelta) es interpretacion de 95 instrucciones; lo que mas pesa ahora: `es_hi`, `vr_x`, `map_blk0`,
  `actor_ix`, `slot_addr` (nucleo).
- `check_spr.py` en la sala 70 (los 2 sprites de los actores 8 y 10, de antes). **Resuelto en la 10e** (era la prueba).

Sin commit.

## Fase 10e: huecos de las pruebas (2026-11-17; solo arnes)

**Prueba de la noche:** `ENGINE/test/build/noche/` no existe todavia (la primera es la del 18/11). Nada que contar de ella.

### Cifras (detectadas de las que se pasan; las equivalentes, aparte)

| Grupo | Antes | Despues |
|---|---|---|
| Nucleo, grupo pedido (`mutaciones.py 1,15,20` con filtro: las 4 de siempre, `moveCamera`/`camera_moved`, fase 7 y las 6 que la 10d habia dejado sin patron) | **33 de 46** | **43 de 43** + 4 equivalentes (47 en total: se anade la de "no acota el destino al minimo" de verdad, ver abajo) |
| Actores (`mut_fase8.py "actores,mascara,cache"`: 44) | **30 de 44** | **41 de 41** + 3 equivalentes |
| Guardar y cargar (`mut_fase9.py`, nuevo: 43 de `ovc9.asm`) | nunca pasadas | **pendiente de la validacion final** (pasada a medias, parada a peticion del usuario: abajo) |

- Antes de nada, **15 patrones ya no se aplicaban** tras la 10d (6 del nucleo: `loc_addr`, `getStringWidth`, `isActorInBox` 3 esquinas, `closestPtOnLine` pv, `getClosestPtOnBox` 3 aristas, `adjustXY` invisibles; 9 de actores: blob extra, ytop, celda izquierda y derecha, mascara FF, color uniforme, desplazamiento, tira de la sala, tira siguiente): adaptados al codigo nuevo con el mismo sentido. Las 6 del nucleo se detectan.
- `mutaciones.py`: (1) **rehace `build/mut/expected.txt`** si el modelo (`vmmodel3`, `vmgame3`, `vmcommon3`, `pack_data3`) o las salas son mas nuevos (antes reusaba el del 15/11 aunque el modelo hubiera cambiado); (2) **pasada de control sin mutar** (tiene que dar 0; si no, para); (3) **`EQUIV`**: las equivalentes con su motivo, que no se pasan salvo con `MUT_EQUIV=1`. `mut_fase8.py` y `mut_fase9.py` igual (`EQUIV8`, `EQUIV9`, control sin mutar en la copia).

### Nucleo: escenarios nuevos (`vmmodel3.make_scenarios_core`, sin azar y al final: no cambian los demas)
- **`cgapidx`**: indice constante de `0x2000` >= `0x800` (escribe y lee el bit `0x8C80 + 0x805`: variable 72, bit 5). En Indy3 solo los hay en el codigo muerto de la entrada de la sala 69.
- **`cgapdiv`**: `divide` con los dos negativos (-7 / -2) y con uno.
- **`cgapnest`**: `stopScript` de un anidado. En ScummVM `runScriptNested` solo vuelve al padre si su ranura sigue con el mismo numero, viva y sin congelar, asi que limpiar `vm.nest` solo se nota si el script parado **vuelve a arrancar en la misma ranura** antes de volver: el 199 arranca el 198, que arranca el 199 (no recursivo: mata al de fuera); el nuevo 199 cede el turno y el padre no debe seguir. Ordenes nuevas del arnes (modelo y `test_vm.cpp`): **`CODER <hex>`** (como `CODE`, pero `startScript(199)` lo vuelve a arrancar) y **`SYNTH n <hex>`** (el global n pasa a ser ese bytecode en ese escenario; `SCRDIR[n]` apunta a una pagina libre y `slot_base_off` lo sabe; `digest_boot.inc` lo copia).
- **`cgapcam`** (sala 1): `setCameraAt(100)` (destino bajo el minimo), `roomOps 1 (400, 500)` (camara bajo el minimo: +8 por fotograma), `(160, 200)` (por encima del maximo: -8) y `actorFollowCamera` con el actor en t = 9 (`_leftTrigger` = 10).
- **`cgapverb`**: un verbo centrado (`verbOps 19`) y un clic 4 px a la izquierda de su `left`; un verbo con el nombre "A" + `$FF 4` (variable 250) que se guarda, cambia la variable y se restaura (`drawVerb` le rehace el rectangulo: de 2 a 6 columnas).
- **`cgapibx<sala>`**: `isActorInBox` junto a la 4.a esquina de las cajas en que esa esquina es la unica extrema en x o en y (suelos en trapecio). Con el rechazo rapido por minimo y maximo de la 10d, quitar la 4.a esquina ya no es equivalente (lo era con el de la fase 5).
- Nucleo sin mutar con todo eso: sala 1 **1.395/1.395**; salas 1, 15 y 20 **1.521/1.521**.

**Equivalentes del nucleo** (`EQUIV` de `mutaciones.py`):
- `cadena: $FF 8 lleva bytes`: `scan_str` solo cambia con `$FF 8` o `$FF 9`, y ninguna cadena de los 1.003 scripts de Indy3 los lleva (solo `$FF 1`-`7`; recorridos con `scumm3dis`).
- `fase 7 checkExecVerbs: el clic derecho no cuenta`: `MKSTAT` solo vale 0, `$8000`, una tecla (<= 319) o `VAR_CUTSCENEEXIT_KEY`, e Indy3 solo escribe 27 en esa variable (el boton derecho es ESC en v3).
- `fase 7 drawVerb: un verbo guardado se dibuja`: `vd_draw` solo se llama al final de `verbOps` (ranura con saveid 0 o nueva) y al restaurar, despues de poner saveid a 0.
- `moveCamera: tras acotar al minimo no mira el maximo` (la que se llamaba "no acota el destino al minimo": su cambio era saltarse el acotado al maximo): a `mc_4` solo se llega con MIN <= cur <= MAX, asi que MIN <= MAX y tras `dest = MIN` nunca se cumple `MAX < dest`, con cualquier dato. Se anade la mutacion que el nombre pedia (`jr nc,mc_5` -> `jr mc_5`): detectada (41 escenarios).

### Actores: escenas fijas (`mk_actscen.py`, al final de cada sala, sin azar; `ACT_FIXED=0` las quita)
- X0-X2: un actor visible **sin traje** y luego con traje y el mismo fotograma (`aq_sel` toca el contador de poses antes de mirar el traje: no es equivalente); el **angulo 70** (de espaldas; con `cp 70` seria derecha); **empate de y**; una animacion que **solo esta en el blob extra** (con `A_STAND` = su fotograma).
- X3: actores de un solo paso con **64 celdas**: el de mas atras va a los extra (con `AC_MAXSPR` = 64 cabria).
- La **camara** en otro sitio en las salas anchas (x - camara).
- X4-X10: la **cache de firma**: cambia solo la x, solo la camara, solo el fotograma, cambia el primer sprite, y el actor vuelve tras ocultarse (marca de la entrada).
- X11-X12: **mascara** con un fotograma de 6 celdas sobre un tramo que acaba 80 filas por debajo de su borde (sin acotar el fin del tramo, la tira 8 se sale de `MKBUF` y pisa la entrada de `ASEL` del actor de delante) y el mismo actor en una caja sin mascara.
- X13: un actor que asoma mas de 16 lineas por encima de la sala (`acl_neg`).
- Sin mutar: salas 7, 77, 12 y 28 (las de `mut_fase8.py`) **22, 22, 19 y 19 escenas sin diferencias**; 1 y 15 **24 y 24**.

**Equivalentes de actores** (`EQUIV8` de `mut_fase8.py`):
- `un actor que no cabe se dibuja a medias`: la pasada 1 ya reparte (normales <= 63), asi que en la pasada 2 `aq_n + celdas <= aq_tot <= 63` siempre.
- `celda a la izquierda de la pantalla`: una x negativa es >= 319 sin signo y la salta la comprobacion siguiente.
- `mascara: un tramo de valor 0 se rellena`: `mk_strip` ya deja a cero las `aq_rh` filas y el relleno no sale de ellas.

### Sala 70: lo que salia distinto era la prueba
Las 8 escenas "con diferencias" de `actscen.sh 1 70 8` no tenian **ningun sprite distinto**: los "2 distintos" eran la comprobacion previa de `EXPECT_PC` (el contador de poses de cada actor visible tiene que haber vuelto a 0 en la escena), aplicada a los actores 8 y 10, que **la escena no pone**: los scripts locales de la sala (el 201 los mete en la sala con `putActorInRoom`/`putActor`/`animateActor`; 204, 205, 207 y 209 los mueven en bucle) los vuelven a mostrar en cuanto la escena los oculta. Es lo que hace ScummVM (`Actor::putActor` muestra al actor si esta en la sala en curso), y el estado de los actores ya lo comparan con el modelo las trazas del nucleo. **Arreglo en la prueba**: `mk_actscen.py` saca una 4.a linea con los actores que pone cada escena, `actscen.sh` se la pasa a `check_spr.py` (`EXPECT_ACT`) y `sprites3.py` solo mira el contador de esos. `actscen.sh 1 70 8`: **8 de 8 escenas sin diferencias** (los mismos volcados).

### Guardar y cargar (`mut_fase9.py`, nuevo)
Guarda en `build/m9/` lo esperado de las 6 pruebas de `savetest.sh` (resumen del modelo, ordenes de sonido, `DATA.BIN` (la del script sintetico es otra), sucesos y la linea de `check_hr`), una vez y sin mutar (tienen que dar todo igual). Cada mutacion de `ovc9.asm` vuelve a montar **solo el overlay C** en una copia (`V3/ENGINE_m9_<n>`): `scumm.sym` no cambia, asi que lo esperado vale para todas; borra las `SAVE*.SAV` antes de cada prueba. `MUT9_NOBASE=1` reusa lo esperado.
Ademas de lo de `savetest.sh`, cada prueba **compara los `SAVE*.SAV`** (nombres y bytes) con los de la pasada sin mutar (sin eso no se veian ni el nombre del fichero ni la cabecera). Pruebas nuevas:
- **`cargarfuera`** (`ev_save4.txt`): el script sintetico guarda y se carga desde el bucle principal (DBG_SAVE): la ranura sigue justo detras del opcode de guardar (`update_ptr`).
- **`nombrevacio`** (`ev_save6.txt` = `ev_f5j.txt` + guardar en la ranura 5, cuyo nombre esta vacio): el nombre que se leyo antes no puede quedar en el fichero.
- **`sdllena`**: el script sintetico con la SD que rechaza las escrituras: **`TS_WRFAIL=1`** en `test_scumm.cpp` (FWRITE responde 255 y no escribe) y en el modelo (`saveLoadGame $80` devuelve 2 y no guarda): guardar da 2 y cargar despues, 5.
- **Arreglo del arnes:** `slot_base_off` (y con el `digest_boot.inc` del programa) trataba siempre el script 199 como el `CODE` del nucleo (base `$2000`); con `SCUMM_SYNTH` el 199 del programa viene de `DATA.BIN` y su posicion salia mal en cuanto seguia vivo en el resumen (`cargarfuera`). Ahora solo si una orden `CODE`/`CODER`/`SYNTH` lo marca.
- **Pasada a medias** (solo con las 6 pruebas de `savetest.sh`, antes de anadir las 3 nuevas y la comparacion de ficheros; parada a peticion del usuario): de las 14 primeras, detectadas 7 (unidad, nombre de la cadena siguiente, bloque 7 sin el ultimo byte, OBJCLS, monton de cadenas, reproductor, MSGBUF); sin detectar 7: numero de ranuras y 30 caracteres (equivalentes, en `EQUIV9`), y unidades del nombre del fichero, cabecera sin `ev_handler`, nombre sin borrar, `update_ptr` y error de escritura, para las que se hicieron la comparacion de ficheros y las pruebas `cargarfuera`, `nombrevacio` y `sdllena` (validadas sin mutar: 401/401 y 401/401; la de `nombrevacio`, sin pasar). **Las 43 con todo eso no se han pasado: quedan para la validacion final** (`python mut_fase9.py`, ~1,5-2 h; la prueba de la noche la incluye).
- **Hallazgo, sin resolver (no es de la 10e):** `ev_dialogo2.txt` (el dialogo: un nombre de 33 letras en la ranura 3; despues, otra vez F5 y otra partida en la 4) da **351 fotogramas distintos del modelo desde el 2.250**: en el segundo dialogo, con una partida ya guardada, el clic de (230, 128) acaba en el script del objeto 168 en el modelo y del 167 en el Z80, y cambian distintos estados de objetos (`O=`). Hasta el 2.249 todo igual. Hay que mirar quien tiene razon contra ScummVM (`findObject` con dos objetos solapados que se activan cuando hay partidas, o la lista de nombres). Ademas: **el dialogo corta el nombre a 22 letras** (guarda "ABCDEFGHIJKLMNOPQRSTUV").

### Pruebas pasadas (especificas, de dia)
- Nucleo: sala 1 1.395/1.395; salas 1, 15 y 20 1.521/1.521. `mutaciones.py` solo con el filtro del grupo.
- `actscen.sh`: salas 7, 77, 12, 28, 1, 15 y 70 sin diferencias (con las escenas fijas).
- `build_boot.sh 700` con `ev_save.txt` 701/701 y las 6 de `savetest.sh` sin mutar (dentro de `mut_fase9.py`): todo igual; `check_hr` como siempre (8 de la capa de texto en el dialogo F5).
- No se ha pasado la bateria completa ni `mutaciones.py` entero (de noche).

### Prueba de la noche
`pruebas_noche.sh` pasa ademas `mut_fase8.py` (todas, tambien las de sonido) y `mut_fase9.py`.

### Lo que falta
- **Sala 20 con 12 escenas (semilla 1): `ERR=6` en el fotograma 55** (`startScene` a una sala que no existe, desde un script de la sala con el estado de los actores forzado a mano). Pasa igual sin las escenas fijas y con el Z80 de HEAD (la 10d solo paso la sala 20 con 8 escenas). La prueba de la noche (`actall.sh "1 2" "1 15 20 28" 12`) la va a dar como fallo. Sin investigar.
- Las equivalentes no se han pasado (`MUT_EQUIV=1`): son por razonamiento sobre el codigo y los datos.

Sin commit.

## Fase 10f: los dos fallos de la 10e y repaso contra ScummVM (2026-11-17; solo arnes y modelo, el Z80 no cambia)

### Fallo A: `actscen.sh 1 20 12`, `ERR=6` en el fotograma 55 (arreglado, era del arnes)
- `ERR=6` = `E_BADROOM`: el script 60 (`loadRoom $84`) llega a una sala sin asignar. Causa doble: (1) el arnes salta el arranque y **`RESMAP` (pseudoRoom) estaba a cero**; ScummVM (`room.cpp`, `ensureResourceLoaded`) tambien manda `$84` a `_resourceMapper[4]`, asi que el Z80 y el modelo hacen lo que toca; (2) la sala 20 lanza al entrar una **cutscene** (script 77 -> 58: el guardia camina hasta Indy, 64 -> 60 = la prision, sala 132). Con la caminata de la 10d (mas rapida) el guardia llega a tiempo dentro de las 12 escenas; antes no llegaba.
- Arreglo (`mk_actscen.py`): se ponen los `PSEUDO` que deja el arranque (`boot_snapshot`) y, en la sala 20, se matan las 24 ranuras de scripts al acabar la carga. `actscen.sh` ahora cuenta aparte las escenas "no validas" por cambio de sala (la sala del volcado no es ninguna de las pedidas) en vez de dar diferencias falsas.
- Resultado: `actscen.sh 1 20 12`: 23 escenas, 0 diferencias.

### Fallo B: `ev_dialogo2.txt` se separa desde el fotograma 2.250 (arreglado, era del arnes)
- No era `findObject`: los dos clics eran el mismo (230, 128), pero el modelo lo resolvia en x = 294 (objeto 168) y el Z80 en x = 230 (167). Causa: **`in_poll` copia `IT_X/IT_Y` a `cur_x/cur_y` con cualquier suceso de prueba**, y `mk_events.py` ponia (0, 0) a las teclas: el F5 del fotograma 2.100 llevaba el cursor a x = 0, `pan_update` (cursor < 100) apagaba la ventana movil y el clic caia en x = 230. El modelo (como el raton real) no mueve el cursor con una tecla y seguia con la ventana corrida +64 desde el `move 240` del 1.900.
- Arreglo: `mk_events.py` da a las teclas la ultima posicion del raton. Ademas el modelo apaga la ventana movil al cambiar de sala (`VM.start_scene` -> `pan_on = False`), como hace `ov_clear` (`evh_room`) del Z80 (diferencia real, aunque aqui no era la causa).
- Resultado: `build_boot.sh 2400 "" ev_dialogo2.txt` **2.401/2.401** y 63 ordenes de sonido iguales; `ev_save.txt` 701/701. Hay que **borrar `build/sdboot/SAVE*.SAV` antes** de cada prueba con guardado (una partida vieja en la SD cambia el primer dialogo).
- **"El dialogo corta el nombre a 22 letras"**: resuelto en la 10g (28).

### Diferencias que quedan con ScummVM en lo que usa Indy3 (sin arreglar)
1. **`oldRoomEffect`** (25 usos): el cambio de sala es un corte; ScummVM hace barridos/disolvencias (`_switchRoomEffect`, `fadeIn`).
2. **Puntos IQ** (`saveLoadVars` 1 y 2, cadenas 7 y 9): sin fichero; harian falta `IQ.DAT` (73 B).
3. **El sonido no se guarda**: tras cargar, la musica vuelve a empezar.
4. **Estado de los padres en `findObject`**: el modelo y el Z80 leen el estado vivo; ScummVM usa la copia `objs[].state` que refresca una vez por fotograma (solo difiere si cambia el estado y se llama en el mismo fotograma).
5. **Escala de los actores y sprites extra (D6)**: reparto aproximado de sprites (hasta 63 + extra de la FPGA), postura por contador (no por el reloj de ScummVM), sin escala por caja.
6. **Variable indexada de 16 bits** (ScummVM suma en 32; solo difiere en casos sin sentido) y `getNextBox` de la sala 46 con pseudosalas.
7. **Ventana movil** (256 de 320 px): no existe en ScummVM; las coordenadas del raton se corrigen con `pan_px`.
8. **Cargar dentro de un script anidado** sin probar; el dialogo de guardar cortaba el nombre a 22 letras (resuelto en la 10g: 28).
9. **Mutaciones de guardar (`mut_fase9.py`)** pendientes de la validacion final.

### Lo que faltaria para Loom EGA (no hay ficheros: lista de riesgos)
- **Interfaz de notas/bastón** en vez de verbos: los scripts de su interfaz usan `drawObject`/`verbOps` de otra forma; hay que medir verbos vivos, objetos dibujados y sprites antes de dar nada por bueno.
- **Reproduccion de "drafts"**: sonido de las notas (AdLib/Roland, no el PC speaker de Indy3) y tabla de sonidos distinta; `sound3vgm.py` solo cubre los de Indy3.
- **Charset propio** (fuente y anchos) y `printString` con codigos que Indy3 no usa.
- **Pseudosalas, `oldRoomEffect` y `cursorCommand`** con mas peso (Loom usa mucho los efectos de sala); el corte seco se veria.
- **Limites del Z80** medidos solo con Indy3 (ranuras 24, verbos 52, objetos locales, 63 sprites): repetir `sprbudget3.py` y `medir_recursos.py` con los datos de Loom.
- **Workarounds de ScummVM especificos de Loom** (p. ej. `o5_loadRoom` sala 29) que no se han copiado.

## Fase 10g: el nombre del dialogo de guardar (2026-11-18)
Peticion: quitar el recorte a 22 letras, que el nombre pueda ser algo mas largo, y arreglar el cursor (con el nombre lleno borraba la linea vertical de la derecha y, al borrar una letra, el cursor se quedaba).
- **Causa del limite:** el script local 200 de la sala 14 solo deja escribir mientras `getStringWidth(nombre) <= 175`, y modelo y Z80 median 8 pixeles por caracter (el original usa 8): 22 letras. Pero la capa de texto (`txtlayer.asm`) dibuja con la fuente de 6 pixeles en celdas de 8, asi que sobraba sitio.
- **Cambio (6 pixeles de verdad):** (1) la capa compone cada caracter a 6 pixeles (`ov_text_col` calcula, para cada columna de 8, los dos caracteres que caen en ella con su desplazamiento; `ov_row` ya admitia desplazamientos con signo); (2) `print` avanza `xpos` 6 pixeles por byte (centrado, 3): el cursor `_` se pone detras del nombre sin el hueco de 2 px; (3) `getStringWidth` = **6 * caracteres + 8** (6 del cursor y 2 de margen) en modelo (`vmmodel3.o_getStringWidth`, `vmgame3.print_string`) y Z80 (`mul6hl` y `gsw_scale` en `vm_core.asm`, residente; el overlay B no cambia de tamano). Con el limite 175 del script salen **28 letras** y el cursor queda como mucho en la celda 23, sin tocar el borde derecho del cuadro (celda 24).
- **Textos de mas de 24 caracteres:** la capa tiene entradas de 26; `ov_text_add` parte un texto largo en trozos de 24 (144 px = 18 celdas: cada trozo empieza alineado), hasta 48 (`UIBUF`).
- **Fondo:** una fila de un texto sin pixeles ya no toca la celda (antes la dejaba en blanco y con el cursor en la celda del borde se llevaba la linea vertical).
- Una caja borra un texto si lo cubre entero con su ancho real (6 por caracter, antes 8).
- Residente hasta `$7D44` (quedan 700 B hasta `$8000`); overlay B sin cambios.
- **Pruebas:** nucleo sala 1 1.395/1.395; `ev_dialogo2.txt` (nombre de 33 letras: ahora acepta 28) 2.401/2.401 con 45 ordenes de sonido iguales; `ev_save.txt` 701/701. Capturas con `nombre.sh` / `nombre2.sh` (`ev_nombre30.txt`: 30 teclas; `ev_nombre30b.txt`: 30 y borrar): 28 letras + cursor con el borde derecho intacto; al borrar el cursor retrocede y no queda el viejo. **Sin probar en la placa.** No se ha pasado `mut_fase9.py` ni la bateria completa.
- Efecto de usuario (manual): el nombre de una partida puede tener hasta 28 letras (antes 22).
- **Correccion (mismo dia):** el inicio del texto seguia redondeado a la celda de 8 (`+ 4` y `and $F8`), y el cursor (x = x del nombre + 6 por letra) quedaba corrido hasta 4 px. Ahora la x es exacta (`+ 4`, sin redondear) y `ov_text_col` admite un inicio cualquiera dentro de la celda (de uno a tres caracteres por columna). Captura: el cursor queda pegado a la ultima letra y el borde izquierdo y derecho siguen. `ev_dialogo2.txt` 2.401/2.401 y nucleo 1.395/1.395 otra vez. Residente hasta `$7D8D`.

## Fase 10h - interfaz sin margen, 42 columnas y mensajes partidos por palabras

- hr_ui pinta desde el byte 0 (antes 1). UIVB pasa a 8x42 ($98F0), HRUI_PREV a $DEB0; el grupo 10 de cada fila tiene 2 caracteres (252 px). Tope de verbos y clics a 42/41.
- ut_wrap: los mensajes de las filas 0-1 saltan de linea antes de una palabra que no cabe.
- Regresion: Barnett 1751/1751, check_hr 0 distintos. Sin probar en placa.

## Fase 10i - personajes a tamano real (3/4 solo en las salas que no caben) y DBG_ROOM

- Los trajes se convierten a tamano real (costume3.py: C2.SCALE (1,1); COST_SMALL=1 los saca a 3/4 en preview_hr\cost34). v2 sigue a 3/4.
- Salas cuyos actores no caben en los 63 sprites a tamano real (sprbudget3.py estatico): 31, 35, 39, 42, 46, 70, 72, 80, 82, 83 (pack_data3.SMALL_ROOMS). Sus trajes son los de cost34: ROOMDIR +27 = 1 y tablas COSTDIR3/COSTDIR4 (tras PROFILE en DATA.BIN; el loader las carga en CLS_PG +5120, SM_COSTDIR). No se pierden posturas.
- ovd_act.asm: actors_run lee ROOMDIR +27 (aq_small) y aq_find busca en COSTDIR/2 o en COSTDIR3/4. sprites3.py (Blobs.find/Ref.small) y sprbudget3.py lo copian. DATA.BIN pasa de ~653 KB a ~1,12 MB.
- Depuracion: escribir la sala (palabra) en $87C4 (DBG_ROOM; DBG_START $87C2, DBG_SND $87C6) carga esa sala sin recolocar a Indy.
- Regresion: Barnett 1751/1751, check_hr 0 distintos. Sin probar en placa.

## Fase 10g, fallo 1: `DBG_ROOM` (2026-11-20)
- **Causa:** `DBG_ROOM` hacia solo `startScene` (`vm_load_room`): el ego se quedaba en la sala de antes y no salia. En el arnes no habia cuelgue (Z80 = modelo). El intento anterior (script sintetico 199 en `DATA.BIN` con `dbg_room.hex`, `CUTSP` a 1 y un segundo `loadRoom` fuera del script) se ha quitado: era el candidato del cuelgue en la placa.
- **Ahora (ScummVM, `ScummDebugger::Cmd_Room`):** la sala del ego = la nueva, `stopAllSounds` y `startScene`. Ademas, si los scripts de entrada no colocan al ego (`_egoPositioned`), `putActor(ego, x, y, sala)` como el final de `startScene` con `loadRoomWithEgo` (`adjustActorPos` lo mete en una caja). Z80: `vm_dbg_room` (`scumm.asm`) -> `OVC_DBGROOM` (+24) -> `dbg_room` (`ovc9.asm`); modelo: suceso `room` de `BOOT` (`vmmodel3.py`). `compila_scumm.bat` ya no mete el 199 en `DATA.BIN`.
- **Uso:** con el juego ya en marcha (despues de la intro), escribir la sala como palabra en `$87C4` (`DBG_ROOM`). Arnes: linea `fotograma room n` en el fichero de sucesos (`ev_dbgroom20/70/15.txt`).
- **El cuelgue (fallo de la 10i, no de `DBG_ROOM`):** en las salas a 3/4 (`SMALL_ROOMS`: 31, 35, 39, 42, 46, 70, 72, 80, 82, 83) `aq_find` (`ovd_act.asm`, `aq_cs`) mapeaba `CLS_PG` en el **bloque 0, donde corre el propio overlay D**: el Z80 ejecutaba basura y acababa por encima de `$8000` (sala 70, al segundo fotograma). Ahora lee `COSTDIR3/4` por la ventana (`cls_open` / `cls_close`). Tambien pasaba entrando en esas salas jugando. Ademas `sprites3.py` habia perdido `lst = []` en la 10i (`check_spr` fallaba en todas las escenas).
- **Pruebas** (`build_boot.sh 1500`, salto en el fotograma 1.300 desde Barnett): sala 20 **1.501/1.501** (4 ordenes de sonido iguales), sala 70 **1.501/1.501** (37 iguales; antes del arreglo de `aq_cs`, codigo por encima de `$8000` en el 1.302), sala 15 (Venecia, con clic y tecla despues) **1.501/1.501** (7 iguales). `actscen.sh 1 "70,20" 4`: **30 escenas, 0 distintas**. Modelo: Indy visible en las tres y el juego responde (la 70 es una escena que pasa sola a la 71). Sin probar en la placa ni en EightyOne.
- **Memoria:** residente hasta `$7E17` (+18 B; **488 B libres** hasta `$8000`); overlay C +60 B de codigo (sigue en 5.632 B); D 7.225 B (-3); B sin cambios.
