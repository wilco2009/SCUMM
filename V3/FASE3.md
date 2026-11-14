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
| `ENGINE/arith32.asm` | Aritmetica de 32 bits (copiada de `geom.asm`: la usa `expression`; la fase 6 la comparte con la geometria) |
| `ENGINE/ovlb.asm` | Overlay B (D4, pagina 49): de momento `expression`, con pila de 32 bits |
| `ENGINE/vm.asm` | Montaje de pruebas: codigo desde `$4200`, tablas desde `$8000`, como el programa de la placa |
| `ENGINE/tables3.inc`, `ENGINE/vars_v3.inc` | **Generados** por `TOOLS/gen_vmtables3.py` (no editar) |
| `ENGINE/test/test_vm.cpp`, `build_test.sh` | Arnes v3: el mundo es `DATA.BIN`; compara con `vmmodel3.py scenarios-core` |
| `TOOLS/gen_vmtables3.py` | Tabla de despacho de 256 opcodes + especificaciones + `vars_v3.inc`, desde `scumm3dis.py` |
| `TOOLS/scumm3dis.py` | Nuevo: `SPEC` (lectura de operandos como datos), `run_spec` y la orden `spec` (la comprueba contra el `Decoder`) |
| `TOOLS/vmmodel3.py` | Nuevo: `CoreVM` (modo nucleo), `run_scenario_core`, `make_scenarios_core`, orden `scenarios-core`; base de cada ranura en la traza |
| `TOOLS/vmcommon3.py` | Limites del Z80 en el modelo: 256 variables, 16 locales, 24 ranuras, 32 argumentos, pila de 32 |
| `TOOLS/pack_data3.py` | D5: paginas solapadas para los scripts grandes |

Los demas `.asm` de `V3/ENGINE` son la copia de v2 sin tocar (`scumm.asm`, `game.asm`, `walk.asm`, `geom.asm`, `input.asm`, `hr.asm`, el overlay A...):
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
| `$E9D0` OBJCLS | 3.000 | clases, 24 bits |
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

Paginas fisicas: 0-7 la memoria base; 8-14 la sala (`hr.asm`; la 79 pide 7); **15 tablas frias**; 16-62 cache de paginas de datos (`dp_cache.inc`) **menos la 49 (overlay B) y
la 50 (overlay A)**: la fase 9 tiene que quitar la 49 de la cache (`DP_OVLIDX`); 63 depurador.

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

## Para las fases 4a y 4b

Ver `PLAN.md` (fase 4): que manejadores, donde van y como se prueban.
