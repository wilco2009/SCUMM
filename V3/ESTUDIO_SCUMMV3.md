# Estudio de viabilidad: SCUMM v3 en el SD81 Booster

Fecha: 2026-11-08. Solo medidas: no se ha escrito intérprete. Sin commit.
Carpeta: `SCUMM/V3/`, la que el README ya reserva para SCUMM v3. Herramientas en `V3/TOOLS/` y medidas en `V3/medidas/`.

## 0. Veredicto

**Viable extendiendo el intérprete v2.** No hace falta otra arquitectura, como sí hacía con SCI0. v3 conserva lo caro de v2:
- el formato de los trajes (0x58),
- el reproductor de sonido (`Player_V2`, PCjr y altavoz),
- salas de 128 líneas a 16 colores, que pasan al HiRes 8x1 con la misma pérdida que Zak,
- un número de variables que cabe en 256.

Lo que cambia es el núcleo de la VM y la caminata, y el código ya no cabe en el sitio que deja el v2.

- **CPU: no es problema.** Con el mismo método de medida (VM en Python que copia ScummVM, recorrido por las salas con el ego andando):

  | | Indy3 | Zak (v2) | Maniac (v2) |
  |---|---:|---:|---:|
  | Bytecodes por fotograma, mediana por sala | 4,4 | 12,8 | 2,4 |
  | Bytecodes por fotograma, p99 | 117 | 49 | 40 |
  | Bytecodes, peor fotograma | 607 | 248 | 1.097 |

  - Con 200-500 T por bytecode, el p99 de Indy3 son unos 58.000 T, el 18 % de una vuelta. Indy3 pide `delta` 6: 10 vueltas por segundo, 325.000 T por vuelta a 3,25 MHz.
  - SCI0 movía 500 bytecodes por ciclo de mediana: cien veces más.
- **Memoria: cabe.** Cada sala necesita unos 34 KB de mediana y 80 KB como máximo, entre imagen HiRes, código, scripts globales, trajes y sonidos. Sobra sitio en los 512 KB paginados.
  - Indy3 solo usa las variables 0-253 (como v2), las locales 0-15 y 1.000 objetos.
- **Código Z80: es el punto débil.** El v2 tiene el código residente lleno: `$4215-$7FAF`, quedan unos 80 bytes antes de `$8000`. El overlay usa 5,9 KB de sus 8 KB.
  - Calculo que v3 añade **unos 5-8 KB netos de código Z80**: decodificador de operandos de 16 bits, 17 manejadores que cambian, 20 nuevos y la caminata de v3.
  - Eso obliga a un **segundo overlay** y a un `SCUMM.BIN` propio para v3, del que salgan los manejadores que solo usa v2.
  - El reparto en overlays es el mismo que ya usa AGI.
- **Gráficos y sonido: se reutilizan.**
  - Imágenes: pierden el 4 % de los píxeles al pasar a 2 colores por franja de 8x1, igual que Zak.
  - Personajes: son más pequeños que en v2 (44 px de alto frente a 64) y necesitan 18 sprites a 3/4 frente a 28. A cambio salen más a la vez: 4 o más en el 9 % de los fotogramas, y entonces no bastan los 64 sprites.
  - Sonido: los 73 sonidos con bloque PCjr se convierten con el `sound2vgm.py` del v2 sin cambios.

**Lista de lo que hay que hacer, con su tamaño, en el §6.**

## 1. Juegos y variantes (ScummVM `detection_tables.h`, `scumm-md5.h`, `metaengine.cpp`)

| Juego | Versión | Clase de ScummVM | Formato | ¿En disco? |
|---|---|---|---|---|
| Indiana Jones and the Last Crusade EGA (DOS, Amiga, Atari ST, Mac) | 3 | `ScummEngine_v3old` (`GF_OLD_BUNDLE`, `GF_16COLOR`) | `00.LFL` + `NN.LFL`, XOR 0xFF, cabeceras de 4 bytes | **Sí**: `V3/Indy Last Crusade` (EN, md5 `6b3ec67d…`) y `… Spanish` |
| Loom EGA (DOS, Amiga, Atari ST, Mac, demo) | 3 | `ScummEngine_v3old` | el mismo | No |
| Indy3 VGA, Indy3 Steam, Indy3 FM-Towns | 3 | `ScummEngine_v3` (`GF_OLD256`, `GF_FEW_LOCALS` salvo Loom) | bloques de cabecera pequeña, 256 colores | No |
| Zak, Loom FM-Towns; Loom PC-Engine | 3 | `ScummEngine_v3` (`GF_OLD256`, pistas de CD) | el mismo de 256 colores | No |
| Loom VGA (CD) | 4 | `ScummEngine_v4` | — | No |

- **"v3 old" y v3 son dos formatos distintos.** v3old (`GF_OLD_BUNDLE`) es el de las versiones EGA: índice y salas casi iguales que v2, con 16 colores.
  Las versiones de 256 colores (`GF_OLD256`) usan el formato de bloques de v4 y otra compresión de imagen, que no se ha medido.
- **El objetivo natural es la versión EGA** de Indy3 y Loom. Con 16 colores encaja con el modo HiRes de 16 colores y con el lector de v2. Las de 256 colores perderían más color en el 8x1 y piden otro lector.
- Todo lo medido es de Indy3 EGA en inglés. **Loom EGA usa el mismo formato pero otra interfaz**: notas en el bastón en vez de verbos. Hace falta para confirmar que los scripts de su interfaz no cambian las cifras.

## 2. Formato y recursos

### 2.1 Diferencias de formato con v2 (ScummVM `resource_v3.cpp`, `room.cpp`, `object.cpp`, `gfx.cpp`, `boxes.cpp`)

| | v2 (Zak, Maniac) | v3old (Indy3 EGA) |
|---|---|---|
| Índice `00.LFL` | 1 byte por objeto (dueño y estado) | 4 bytes por objeto: **24 bits de clases** más dueño y estado |
| Cabecera de sala | 28 bytes, cajas en u8 | 29 bytes, cajas en u16. Tras los ids de sonidos y scripts va la **lista de scripts locales** (id ≥ 200, offset u16) |
| Scripts de sala | entrada, salida y verbos de objeto | lo mismo más **scripts locales** (hasta 14 por sala) |
| Objeto (OBCD) | punto de acercamiento en u8×8, verbos en pares | punto de acercamiento en u16, verbos en ternas (verbo y offset u16) desde +17 |
| Imagen | columnas con RLE propio (`GdiV2`) | **franjas de 8 px** con el RLE de `drawStripEGA` y una máscara (`decompressMaskImg`). `_numZBuffer` = 2, igual que v2 |
| Cajas | trapecios de 8 bytes; matriz n×n | **cuadriláteros de 18 bytes** (4 esquinas en s16); matriz en listas de ternas (desde, hasta, siguiente) |
| Trajes | formato 0x58 | **el mismo** (`ClassicCostumeLoader` con `GF_OLD_BUNDLE`) |
| Sonido | `Player_V2` (PCjr y altavoz) | **el mismo** (`scumm.cpp`: PCSPK y PCjr de v3 y v4 usan `Player_V2`). Solo cambia de dónde sale `VAR_MUSIC_TIMER` |
| Compresión | ninguna, salvo el RLE de imagen | ninguna, salvo el RLE de imagen |

`V3/TOOLS/scumm3res.py` lee las 89 salas sin errores.
Las imágenes y máscaras decodificadas se han comprobado a ojo en PNG: el pasillo de Barnett College y Venecia salen bien.
Los ficheros 98 y 99.LFL son los juegos de caracteres (`loadCharset` abre `99 - n`).

### 2.2 Tamaños (`V3/medidas/recursos.json`)

| | Indy3 EGA | Zak v2 | Maniac v2 |
|---|---:|---:|---:|
| Salas | 89 | 58 | 54 |
| Recurso de sala (media / máx.) | 13,4 / 40,8 KB | 13,2 / 30,5 KB | 8,7 / 23,0 KB |
| Imagen y máscara (media) | 9,0 KB | 9,2 KB | 6,9 KB |
| Código de sala (media / máx.) | 1,1 / 5,8 KB | 1,1 / 3,4 KB | 0,5 / 2,0 KB |
| Ancho de sala (mediana / máx.) | 320 / 1.280 | 640 / 960 | 480 / 3.360 |
| Scripts globales (total / mayor) | 73 KB / **6,7 KB** | 51 KB / 1,8 KB | 32 KB / 2,7 KB |
| Trajes (total / mediana / mayor) | **432 KB** / 4,2 KB / 15,8 KB | 64 KB / 1,4 KB / 5,0 KB | 50 KB / 2,3 KB / 3,1 KB |
| Sonidos (total) | 33 KB | 33 KB | 24 KB |
| Todo el juego | 1,8 MB | — | — |

- Las salas se parecen mucho a las de Zak.
- **Lo que crece son los trajes**: llevan 59-90 animaciones cada uno, frente a 23-31 en v2. Pero en el Z80 no se usan tal cual: el v2 los convierte en el PC a fotogramas de sprites (§5.2).
- Ojo: **el script 95 mide 6.711 bytes** y no cabe en la ventana de datos de 6 KB del v2 (`PAGE_USABLE = 0x1800`). Es el único; el siguiente mide 4,9 KB. Hay que partirlo en el conversor o abrir la ventana a dos páginas.

## 3. Bytecode

### 3.1 Tabla de opcodes

En ScummVM v3 no tiene tabla propia. Es la de `ScummEngine_v5::setupOpcodes`, con lo que cambia `ScummEngine_v4` y tres opcodes de `ScummEngine_v3`:
- `ScummEngine_v4`: `drawObject` en x, y; `pickupObject`; `oldRoomEffect`; `ifState`/`ifNotState`; `saveLoadVars`/`saveLoadGame`.
- `ScummEngine_v3`: `setBoxFlags` 0x30/0xB0, `waitForActor` 0x3B/0xBB y `waitForSentence` 0x4C.

v2 tiene una tabla aparte (`script_v2.cpp`). Diferencias de fondo:
- **Operandos**: las variables son palabras de 16 bits con tres modos. Con 0x8000 es un bit dentro de una variable normal; con 0x4000, una variable local de la ranura; con 0x2000, lleva un índice indirecto con otra palabra.
  En v2 una variable es un byte y los bits tienen opcodes propios.
- **Listas variables**: `startScript`, `chainScript`, `startObject` y `cutscene` llevan listas de argumentos que van a las variables locales del script nuevo.
- **Bucles de subopcodes** en `actorOps`, `verbOps`, `roomOps`, `cursorCommand`, `print`, `expression`, `setClass`, `ifClassOfIs` y `stringOps`.
- Indy3 tiene casos propios que trae ScummVM:
  - `wait` no lleva subopcode;
  - `getActorX`/`getActorY` leen un byte;
  - `roomOps` lee los parámetros antes del subopcode;
  - `actorOps` traduce el subopcode con `convertTable`.

`V3/TOOLS/scumm3dis.py` copia todo esto. Se ha comparado con descumm `-3` en los 1.003 scripts:
- **841 coinciden instrucción a instrucción.**
- Los otros 162 se separan siempre en uno de esos casos de Indy3 (`wait`, `waitForActor`, `getActorX`/`getActorY`), que descumm no conoce y ScummVM sí.
- Solo hay un bloque que no se decodifica: código muerto de la entrada de la sala 69, tras un salto.

### 3.2 Frecuencia estática y clasificación frente a v2 (`V3/medidas/bytecode.json`)

| | Indy3 | Zak | Maniac |
|---|---:|---:|---:|
| Bytes de código | 149.744 | 99.016 | 45.974 |
| Instrucciones | 20.219 | 19.139 | 8.578 |
| Bytes por instrucción | 7,4 | 5,2 | 5,4 |
| Opcodes distintos | 96 | 101 | 89 |

Cada opcode de Indy3, frente al manejador de v2 que hace lo mismo:

| Clase | Opcodes | % de las instrucciones | Ejemplos |
|---|---:|---:|---|
| **Misma semántica, solo cambia la lectura de operandos** | 59 | 68 % | saltos y comparaciones, `move`, aritmética, `breakHere`, `delay`, `animateActor`, sonidos, `putActor`, consultas de actor, cámara, `walkActorTo` (la orden; la caminata cambia), `setBoxFlags`, `lights` |
| **Existe pero cambia** (manejador nuevo) | 17 | 28 % | `startScript`/`chainScript`/`cutscene` (argumentos), `print`/`printEgo` (`decodeParseString` de v5), `actorOps` (10 subopcodes usados), `verbOps` (11), `roomOps` (5), `cursorCommand` (11), `resourceRoutines` (11), `ifClassOfIs`, `doSentence`, `loadRoomWithEgo`, `drawObject`, `pickupObject`, `setState`/`ifState`/`ifNotState` (estado de 8 bits; en v2, bits) |
| **Nuevo** | 20 | 4 % | `expression` (pila con opcodes anidados), `stringOps`, `setClass`, `startObject`, `stopObjectScript`, `freezeScripts`, `drawBox`, `saveRestoreVerbs`, `oldRoomEffect`, `systemOps`, `saveLoadVars` (puntos IQ), `multiply`, `divide`, `and`, `or`, `findInventory`, `getVerbEntrypoint`, `getActorWidth`, `getInventoryCount`, `isActorInBox` |

**Efecto en el intérprete Z80:**
- El despachador del v2 lee los operandos por una cadena de códigos (R, v, B1-B3, W1-W3...) y llama al manejador. **Ese esquema sirve.** Cambian los códigos R, v, B y W (variables de 16 bits con bits, locales e indirectas) y entra uno nuevo para las listas.
- Las locales piden 16 palabras por ranura: 768 B con 24 ranuras.

## 4. Memoria

Por sala, lo que tiene que estar en la RAM paginada mientras se juega en ella (`V3/medidas/analisis.json` y `indy3_tabla.md`):
- la imagen en el formato `.GFX` HiRes del v2 (estimada: columnas por alto por 2, más imágenes de objetos);
- el código de la sala;
- los scripts globales que corren en ella, los trajes visibles y los sonidos que suenan.

| Por sala (84 salas) | Media | Mediana | Máximo |
|---|---:|---:|---:|
| `.GFX` HiRes | 20,7 KB | 16,7 KB | 51,3 KB (sala 79, 1.280×136) |
| Código de la sala | 1,1 KB | 0,8 KB | 5,8 KB |
| Scripts globales que corren | 3,0 KB | 1,8 KB | 9,8 KB |
| Trajes visibles (recurso original) | 10,4 KB (2 trajes) | 8,4 KB | 31,9 KB (5 trajes) |
| Sonidos | 0,7 KB | 0 | 4,2 KB |
| **Total** | **35,9 KB** | **33,7 KB** | **80,3 KB** |

Comparación: los `.GFX` reales de Zak (`V2/preview_zak_hr/gfx`) miden 22 KB de mediana y 44,5 KB como máximo, y `DATA.BIN` de Zak 276 KB.

- **Cabe con holgura** en los 512 KB paginados. Solo la sala 79 pasa de las 6 páginas (48 KB) que el v2 reserva para la sala: hace falta una séptima.
- **El juego entero no cabe en RAM** (1,8 MB), pero tampoco cabía Zak. El v2 ya carga de la SD por sala (`ROOMnn.GFX`) y pagina `DATA.BIN`.
  Para Indy3, `DATA.BIN` con scripts, código de salas y trajes convertidos rondaría 300-400 KB. Los trajes convertidos ocupan mucho menos que el original (§5.2).
- **Tablas del v2 que se quedan cortas:**
  - objetos: 780, e Indy3 tiene 1.000; con las clases son 3 bytes más por objeto, 3 KB;
  - `ROOMDIR`: 64 salas, e Indy3 numera hasta la 99;
  - `COSTDIR`: 64 trajes, e Indy3 numera hasta el 128.
  - Son cambios de tamaño, no de diseño.
- **Variables:** Indy3 usa solo las 0-253 (178 distintas). Los 59 bits viven dentro de 10 de ellas. Caben en las 256 del v2.
- **VM:** como máximo 32 ranuras ocupadas en el recorrido (el v2 usa 24: hay que medirlo en el juego real) y 5 niveles de anidamiento.
- **Código Z80:**
  - El residente del v2 ocupa `$4215-$7FAF` (15,8 KB): vm_core 2,5 KB, juego 1,9, geometría 1,6, caminata 2,7, entrada 2,3, programa y HiRes 3,6.
  - Las tablas ocupan `$8000-$864C` y el overlay 5,9 KB de los 8 KB de su página.
  - **El código no puede pasar de `$8000` y no queda sitio**: lo que añade v3 tiene que ir a overlays (§6).

## 5. Gráficos y sonido

### 5.1 Pantalla

- **Salas:** 58 de las 84 miden 128 líneas, como en v2.
  - Indy3 llama casi siempre a `SetScreen(16,144)` (28 veces): 16 líneas de mensajes arriba, 128 de sala y 56 de interfaz abajo.
  - Las escenas a pantalla completa (`SetScreen(0,200)`, `(8,200)`, `(16,200)`) usan salas de 184, 192 o 200 líneas: 26 salas.
- **En el HiRes de 192 líneas:**
  - Las salas normales caben con 16 líneas de mensajes, 128 de sala y 48 de interfaz (6 filas: la frase, los verbos y el inventario, con la fuente de 6 px del v2).
  - Las escenas de 200 líneas necesitan el scroll vertical por hardware (fase 3, ya sintetizado) o recortar 8 líneas.
- **Color:** 16 colores EGA. Al pasar al HiRes 8x1 (2 colores por franja, con `row_spec` de `lfl2gfx.py`):

  | | Indy3 | Zak | Maniac |
  |---|---:|---:|---:|
  | Píxeles que cambian (media / máx.) | 4 % / 14,8 % | 4 % / 14,4 % | 4 % / 12,4 % |
  | Franjas de 8x1 con más de 2 colores | 18 % | 19 % | 18 % |

  Es la misma pérdida que ya se acepta en Zak. Las versiones de 256 colores (FM-Towns, VGA) perderían bastante más.
- **Scroll:** 31 de las 89 salas son más anchas que 320 (hasta 1.280). Sirve el mismo motor de scroll horizontal del v2.
- **Objetos animados:** 15 de las 83 salas redibujan objetos en cada ciclo.
  - Las peores son interiores del castillo, las salas 28 y 20: unos 2 objetos y 10.000-11.600 píxeles por fotograma (antorchas y fuegos).
  - En el v2 eso es recomponer columnas del `.GFX`. Calculo unos 60.000 T por vuelta en esas salas, sin medir.

### 5.2 Personajes (`V3/medidas/trajes.json`)

Postura quieta y de andar, con la misma escala de 3/4 en sprites de 8x8 que el v2:

| | Indy3 | Zak | Maniac |
|---|---:|---:|---:|
| Alto (mediana / máx.) | **44** / 99 px | 64 / 98 px | 74 / 85 px |
| Sprites de 8x8 a 3/4 (mediana / p90 / máx.) | **18** / 25 / 80 | 28 / 32 / 40 | 32 / 36 / 36 |
| Píxeles de celda por postura (mediana) | 800 | 1.177 | 1.590 |
| Miembros por postura | 1-2 | 5 | 5 |

- **Los personajes de Indy3 son más pequeños y más sencillos.** Suelen ser un cuerpo entero y la cabeza, frente a los 5 miembros de v2.
- **Cuántos salen a la vez** (recorrido): 1 en el 64 % de los fotogramas, 2 en el 20 %, 3 en el 7 % y **4-6 en el 9 %** (salas 32, 35, 36, 41, 43, 46, 66, 70, 72, 76 y 82).
  Con 18 sprites por personaje, 4 ya son 72: más que los 64 sprites.
  Hacen falta los sprites extra de la FPGA (`POKE 2131`, hasta 127) o bajar la escala en esas salas, como ya permite `escala_N` en el perfil del juego.
- **El conversor del v2 (`costume_blob`) vale con un cambio**: los números de fotograma.
  - v3 usa inicio 1, andar 2, quieto 3 y hablar 4/5 (`Actor::initActor`, versión ≥ 3); v2 usa 2/0/1 y 4/5.
  - Con la numeración de v2 sale un blob de 557 B de mediana; no es válido, porque toma otros fotogramas.
  - Por tamaño (18 sprites frente a 28) debería quedar por debajo de los de Zak (2 KB de mediana, 5,9 KB como máximo).
- **Las posturas especiales son lo que más cambia respecto a v2.**
  - El blob del v2 solo guarda andar, quieto y hablar.
  - En v3, `animateActor` recibe el fotograma tal cual: 252-255 para, 248-251 cambia de dirección, 244-247 gira; cualquier otro valor es el fotograma (`Actor::animateActor` y `startAnimActor`).
  - Con número fijo, los scripts de Indy3 piden **316 veces fotogramas especiales (del 6 al 30, 25 distintos)** y 177 veces los de inicio, andar, quieto y hablar (1-5). Hay otros 29 `animateActor` con variable y 343 órdenes de dirección o de parar.
  - Zak pide unas 40 veces fotogramas especiales (6-9 y 17-19), y el v2 ya los pierde. En Indy3 son peleas, gestos y objetos en la mano, y se notarían.
  - **Hace falta ampliar el blob con las posturas que use cada traje.** Es trabajo de conversor en el PC; el Z80 solo tiene que elegir el fotograma.
    El blob crecerá, pero cada postura de Indy3 ocupa unos 18 sprites, frente a 28 en Zak.

### 5.3 Sonido

- **Indy3 EGA trae para PCjr y altavoz el mismo formato que Zak y Maniac.** ScummVM usa `Player_V2`, con cabecera de 4 bytes por `GF_OLD_BUNDLE`, para PCSPK y PCjr en v3 y v4.
- `V2/TOOLS/sound2vgm.py`, que es lo que ya alimenta el AY en el v2, **convierte los 73 sonidos de Indy3 con bloque PCjr sin un fallo**. Las 11 entradas restantes del índice no tienen ese bloque.
- **Lo único distinto es `VAR_MUSIC_TIMER`:** en v3 lo lleva el reproductor aparte (`_music_timer`, `Player_V2Base::getMusicTimer`), no el canal 0. Las esperas de la música del intro dependen de él.
- La AdLib de Indy3 EGA (`Player_AD`) es otro formato. No hace falta, porque el AY imita mejor el PCjr (3 voces más ruido).

## 6. Qué hay que hacer y cuánto ocupa

Estimación de código Z80. No es una medida: margen de ±40 %.

| Trabajo | Dónde | Código Z80 |
|---|---|---:|
| Decodificador de operandos de 16 bits (bits, locales, indirectas), resultado con indirección, listas de argumentos, locales por ranura | vm_core | +0,5 a +0,8 KB |
| 17 manejadores que cambian (los bucles de `actorOps`, `verbOps`, `roomOps`, `cursorCommand`, `print`, `resourceRoutines`; `startScript` con argumentos; estado de 8 bits) | overlay | +1,5 a +2,5 KB |
| 20 manejadores nuevos (`expression`, `stringOps` y sus cadenas, clases de 24 bits, `startObject`, `freezeScripts`...) | overlay | +1,0 a +1,5 KB |
| Scripts locales de sala e inventario v3 (copias del OBCD) | vm_core / juego | +0,3 KB |
| Caminata de v3: cajas de 4 esquinas en s16, matriz por listas, `findPathTowardsOld` con puertas, `Actor_v3::walkActor` y `actorWalkStep` | walk / geom | +1,5 a +2,5 KB (sustituye parte de los 4,3 KB actuales) |
| Interfaz: verbos colocados por el script (`verbOps` con posición y nombre), frase, inventario y mensajes arriba en 2 líneas | ui | +0,5 a +1,0 KB |
| Lo que solo usa v2 y sale de un `SCUMM.BIN` propio para v3 (estado por bits, decodificadores de `actorOps`/`verbOps` de v2, preposiciones...) | — | −1,0 a −1,5 KB |
| **Neto** | | **+5 a +8 KB** |

En el PC (Python, sin coste en el Z80):
- **Lector v3old:** ya está (`scumm3res.py`, `scumm3dis.py`).
- **Imagen:** de franjas EGA a `.GFX` HiRes. `lfl2hr.py` recibe la imagen ya decodificada, así que solo cambia el decodificador.
- **Trajes:** con la numeración de v3 y las poses especiales por sala.
- **`DATA.BIN`:** con tablas más grandes, el script 95 partido y la tabla de sonidos.

Reparto de memoria propuesto, sin cambiar el del v2:
- **Residente (`$4200-$7FFF`):** el núcleo de la VM con el decodificador nuevo, la caminata y el HiRes.
- **Overlays de 8 KB en el bloque 0:** dos, como en AGI. Uno con la interfaz, la cámara, los actores y el sonido (el de hoy). Otro con los manejadores con subopcodes, `expression` y `stringOps`.
  Se cambian con un `POKE` de página, nunca leyendo la SD en mitad de una vuelta.
- **Bloques 4-7:** igual que en v2. Las variables crecen con las locales (768 B) y las clases (3 KB), que pueden ir a una página aparte de `DATA.BIN`.

## 7. Cómo se ha medido

- **Juego:** Indy3 EGA en inglés, `V3/Indy Last Crusade`. Los datos de LucasArts están en `.gitignore`.
- **Referencia: ScummVM `engines/scumm`**, añadido al checkout parcial de `C:\ClaudeCode\scummvm_src`. No se ha compilado ScummVM: se ha copiado su semántica en Python, como en el estudio de SCI0.
- **Herramientas (`V3/TOOLS/`):**
  - `scumm3res.py`: índice, salas, imagen, máscara, objetos, cajas y scripts locales.
  - `scumm3dis.py`: decodificador de bytecode, comparado con descumm; histograma estático.
  - `compara_bytecode.py`: la clasificación del §3.2.
  - `medir_recursos.py`: tamaños y pérdida en HiRes 8x1, en v3 y en v2.
  - `medir_trajes.py`: personajes en v3 y en v2.
  - `scumm3vm.py`: **VM v3 mínima** con el orden de `scummLoop`:
    - `runScript` y anidados, locales, `cutscene`/`override`, `freeze`, frases, `startScene` (salida, matar scripts de sala, entrada), objetos, clases e inventario;
    - todos los opcodes con su lectura de operandos;
    - mensajes que duran 60 + `VAR_CHARINC` por carácter;
    - caminata por cajas con la matriz de v3.
  - `v2base.py`: el mismo método con el modelo de referencia del v2 (`V2/TOOLS/vmmodel.py` y `vmgame.py`).
  - `analiza.py`: la memoria por sala y la tabla.
- **Recorrido:** el juego arranca con el script 1 (logo, créditos, Barnett College) hasta el pasillo. Después salta a cada una de las 87 salas (todas menos la 0 y la 92) y juega 250 fotogramas en cada una, con clics al azar en las cajas cada 15-60 fotogramas.
  Los clics pasan por el script de verbos del juego (`runInputScript`), así que el ego anda por los scripts de verdad.
  También hay un arranque largo de 8.000 fotogramas que se queda en el pasillo (sala 1): 18,9 bytecodes por fotograma de media y 68 de p99.
- **Protección anticopia (sala 92):** ScummVM no se la salta en Indy3. Tras 30 fotogramas en ella, la VM pone `Var[57] = 1`, que es lo que hace el script local 204 al acertar los cuatro símbolos.
- **Coste en T:** no se ha medido en el Z80.
  - Para v2 se usa la estimación de 150-400 T por instrucción de `claude/planning/scumm_interprete.md`, que tampoco está medida.
  - Para v3 se usan 200-500 T, por las variables de 16 bits.
  - Se intentó perfilar el v2 con el arnés (`test_scumm.exe` con `TS_PROF`), pero se atasca al arrancar con los datos que hay hoy en `test/build/sd`.

## 8. Lo que no está medido

- **El arnés del Z80:** medir con él lo que cuesta de verdad una instrucción y una vuelta del v2 en Zak cambiaría los T, pero no el veredicto. Los scripts de Indy3 se quedan en el 2-20 % de la vuelta incluso con 500 T por bytecode.
- **Las secuencias guionizadas largas:** peleas, el zepelín, la persecución en moto. El recorrido entra en cada sala sin el estado de la partida, así que muchos guiones no se disparan. Las salas con más trabajo medidas son la 28, la 20 y la 70 (75-122 bytecodes por fotograma de media).
- **La caminata:** en la VM es aproximada (punto más cercano de la caja siguiente, no las puertas de `findPathTowardsOld`). Cambia la ruta, no el número de bytecodes.
- **Loom EGA y las versiones FM-Towns y VGA:** no hay ficheros en disco. Loom usa el mismo formato que Indy3; FM-Towns y VGA, el formato de 256 colores.
- **Los trajes con la numeración de v3 y sus poses especiales:** hace falta adaptar `costume_blob` para tener el tamaño real.

## Apéndice: medidas por sala

La tabla completa está en `V3/medidas/indy3_tabla.md`, con la memoria por sala, los bytecodes, los actores y los píxeles de celda. Las salas más cargadas del recorrido:

| Sala | Tamaño | Bytecodes media / p90 / máx. | Actores máx. | Objetos redibujados por fotograma |
|---:|---|---|---:|---|
| 28 | 320×184 (castillo) | 122 / 134 / 163 | 3 | 1,9 (11.600 px) |
| 20 | 320×184 (castillo) | 112 / 119 / 154 | 3 | 2,2 (10.100 px) |
| 70 | 320×184 (sin objetos, 10 scripts locales) | 75 / 109 / 133 | 4 | — |
| 44, 47, 49-55 | | 31-40 / 52-78 / 86-269 | 1-2 | — |
| Mediana de las 84 salas | | 4,4 | 1 | 0 |
