# Estudio de viabilidad: SCI0 en el SD81 Booster

Fecha: 2026-11-08. Solo medidas: no se ha escrito intérprete Z80 ni se ha tocado el firmware. Sin commit.

## 0. Veredicto

**No viable con el firmware tal como está** (revisado el 2026-11-08, cuando se supo que al STM32 le quedan menos de 40 KB de RAM).
- **La vía del STM32 solo se recupera con dos cambios al firmware:**
  - darle al heap SCI la CCM RAM, de 64 KB, que hoy ocupa el depurador;
  - liberar flash, sacando la EEPROM emulada del último sector de 128 KB (§5).
- **En el Z80 solo** es posible sobre el papel, pero es el proyecto más grande del SD81 y quedaría justo. No lo recomiendo.

- **CPU:** con SQ3 completo (79 salas, el ego andando) salen **488 bytecodes por ciclo en la sala mediana** y 1.558 en la peor.
  En el Z80, con mi modelo de coste (estimado, ±30 %), son **unos 135.000 T por ciclo en la sala mediana**, la mitad del presupuesto (270.833 T a 12 ciclos por segundo). 72 de las 79 salas entran por la media.
  Las 7 salas con mucha gente (Monolith Burger, 120, 50 y la intro) se pasan de 1,1 a 1,8 veces: irían a 6-8 ciclos por segundo.
- **Lo que pesa no es el movimiento:** las clases de movimiento y ciclado son solo el 10 % de los bytecodes y el 6 % del tiempo.
  El 48 % es bytecode general de la biblioteca de clases y el **27 % son los `send`**: la búsqueda lineal del selector. Esto último se puede bajar mucho con tablas preparadas en el PC.
- **Memoria:** cada sala necesita **40 KB de heap de mediana y 46 KB como máximo** (25 KB de código de scripts y 15-19 KB de datos), más 2,3 KB de pila y 50-250 KB de recursos.
  El juego entero son unos 2 MB, así que **hay que cargar de la SD por sala**: los overlays de disco son obligatorios, y en eso tienes razón.
  Pero el problema de verdad es el mapa de 64 KB del Z80. Hay 40-60 KB de intérprete (SCIV.EXE ocupa 75 KB), 15-19 KB de datos SCI con punteros planos, una ventana de código y el vídeo.
  Solo cabe con overlays del intérprete, una MMU por software para el heap (un 10 % más lento), los scripts convertidos en el PC y el **vídeo a 4 bpp**. El 8 bpp con 256 colores mezclados no deja sitio.
- **Gráficos:**
  - El undithering a 160x200 funciona bien: 12 colores mezclados por imagen de mediana (25 como máximo) y un 9 % de celdas de 2x1 con detalle perdido.
  - Con el formato B de 4 bpp las vistas pasan sin perder color.
  - El texto pasa de unos 50 caracteres a 40 columnas, y las ventanas se rehacen solas porque las mide el kernel (`TextSize`).
- **STM32:**
  - **CPU:** le sobra; un ciclo le cuesta menos de 1 ms.
  - **Sitio:** no lo hay. La VM pide unos 60-70 KB de RAM y 60-100 KB de flash. Al firmware le quedan menos de 40 KB de RAM y unos 46 KB de flash.
  - **Los 512 KB de la SRAM no sirven de memoria extra:** el STM32 solo llega a ella con el Z80 en reset, a 13 µs por acceso.
  - **Hay salida:**
    - El heap (46 KB en SQ3) cabe en la CCM, de 64 KB. Eso deja al depurador sin símbolos ni traza mientras corre SCI.
    - La EEPROM emulada (128 B) puede pasar a la SRAM de respaldo del RTC, que tiene batería. Eso libera 128 KB de flash.
    - Con los dos cambios entra, y el Z80 queda como visor de 6-10 KB. Son unas 8.000-12.000 líneas de C, más esos dos cambios.

## 1. Cómo se ha medido

- **Juego:** Space Quest III completo (`SCUMM/SCI/SQ3`, SCI0 tardío 0.000.453: 113 scripts, 115 imágenes, 186 vistas y 86 sonidos).
  También se han usado los demos oficiales de Sierra que publica scummvm.org (SQ3, KQ4, LSL2, LSL3, PQ2, QfG1, Iceman y Camelot), pero solo para los gráficos y para validar el modelo. Son demos no interactivos.
- **Referencia: ScummVM `engines/sci`.** Compilar ScummVM con contadores lo bloqueó el control de permisos, así que se reprodujo en Python lo necesario, copiando su semántica:
  - `TOOLS/sci0res.py`: recursos (mapa, LZW de SCI0, Huffman, bloques de script).
  - `TOOLS/sci0pic.py`: imágenes vectoriales (líneas, rellenos, patrones, tramado EGA, capas de prioridad y control), vistas, fuentes y la duración de los sonidos (MIDI de SCI0).
    Las imágenes se han validado a ojo: los PNG coinciden con el juego.
  - `TOOLS/sci0vm.py`: la PMachine (los 128 opcodes de `vm.cpp`, send/self/super con los selectores de variable y de método, `&rest`, call/callb/calle/callk) y unos 100 kernels de SCI0.
    Los que pesan están copiados línea a línea de ScummVM: `Animate` (invoke, fill, update, drawCels, updateScreen y restoreAndDelete), `CanBeHere`, `InitBresen`, `DoBresen`, `BaseSetter`, `SetNowSeen`, `DirLoop`, las listas y `DoSound` (estado y fin de canción).
    Texto, ventanas y menús solo devuelven medidas: no pintan.
  - **Memoria:** el modelo usa el del intérprete original, un heap plano de 64 KB con punteros de 16 bits. Ahí van los scripts enteros (código, objetos, locales, cadenas), los clones, las listas, los nodos, las ventanas y la pila de 4 KB.
    Los recursos (vistas, imágenes, sonidos, fuentes, textos) van en el "hunk", aparte. Así la ocupación del heap del modelo es directamente la que tendría un intérprete que copie el diseño de Sierra.
- **Entrada:** el modelo pulsa ENTER cuando un diálogo espera una tecla y mueve a Roger con flechas al azar cada 15-60 ciclos, así que el ego anda, choca y cambia de sala por sí mismo.
  Para cubrir el juego, `TOOLS/recorrido.sh` arranca el juego de cero por tandas y lleva al ego por las 83 salas (todos los scripts con un objeto `Rm`), 250 ciclos cada una, cambiando `newRoomNum` (global 13) como hace `Rm:newRoom:`.
  No se usa el parser: no se teclean órdenes.
- **Ciclo de juego:** cada llamada a `Animate` con el reparto (`Game:doit`). SQ3 llama a `Wait 5`: 12 ciclos por segundo, que a 3,25 MHz son **270.833 T por ciclo**.
- **Coste en Z80:** `TOOLS/analiza.py` multiplica lo medido (cada opcode, cada send con las comparaciones de la búsqueda lineal de selectores, cada llamada al kernel y su trabajo: píxeles de control mirados, objetos del reparto...) por un coste en T-estados contado a mano sobre un diseño concreto (§2.3).
  **No es una medida en el Z80:** es una estimación con un margen de ±30 %.

Reproducir: `python TOOLS/analiza.py ../SQ3 nombre CICLOS andar`, `sh TOOLS/recorrido.sh ../SQ3 sq3t 83 6`, `python TOOLS/combinar.py sq3t ../medidas/sq3_andar.json` y `python TOOLS/graficos.py ../SQ3 nombre [carpeta_png]`.
Los resultados quedan en `SCUMM/SCI/medidas/` (JSON y logs).

## 2. CPU

### 2.1 Bytecodes por ciclo (SQ3, 79 salas con 20 ciclos o más)

| | Media | Mediana | Máximo |
|---|---:|---:|---:|
| Bytecodes por ciclo (media de cada sala) | 564 | 488 | 1.558 (sala 120) |
| Bytecodes en el peor ciclo de una sala | — | — | 10.940 (sala 900, intro) |
| Sends por ciclo | — | 22-27 | 78 (sala 120) |
| Comparaciones de selector por ciclo (búsqueda lineal como la de SCIV) | — | ~600-900 | 3.619 (sala 120) |
| Profundidad de llamadas / pila de la PMachine | | | 16 marcos / 2.300 B |

- **Dónde se van los bytecodes** (partida andando, 8.000 ciclos):
  - Fuera de `Animate` va el **71 %**: `Game:doit`, `User`, la sala y las regiones, sonidos y temporizadores.
  - Los `doit` que lanza `Animate` se llevan el 29 %. De ese 29 %, las clases de **ciclado son el 6,3 %** y las de **movimiento el 3,9 %**.
  - Es decir, **movimiento y ciclado son solo el 10 % de los bytecodes**. Lo caro es el coste fijo de la biblioteca de clases en cada ciclo.
- **Sala típica (2):** 4 `FirstNode`, 3 `IsObject`, 2 `NextNode` y `NodeValue`, 2 `GetTime`, 1 `Clone`/`DisposeClone` (el objeto evento), 1 `BaseSetter`, 1 `Animate`, `GetEvent` y `Wait`.
- **Sala cargada (120, el ego andando con otros actores):**
  - Llamadas al kernel por ciclo: 8,6 `IsObject`, 4 `NumCels`, 2 `BaseSetter`, 1,6 `GetAngle` y `DirLoop`, 1,5 `GetDistance`, 1 `CanBeHere` (330 píxeles de control mirados) y 1 `DoBresen`.
  - Bytecodes por ciclo: 242 de movimiento y 159 de ciclado.
- **Opcodes más frecuentes:** `bnt` 12,7 %, `pushi` 7,7 %, `ldi`, `push0` y `push1` 5,8 % cada uno, `pTos` 5,7 %, `callk` y `send` 5,1 % cada uno, `ret` 4,8 %, `pToa` 4,7 %, `lag` 3,7 %.
  - Por ciclo se tocan unas 34 variables globales o locales, 63 propiedades y 52 temporales o parámetros.

### 2.2 T-estados del Z80 por ciclo (estimación)

Presupuesto: SQ3 usa `Wait 5`, que son 12 ciclos por segundo y **270.833 T por ciclo** a 3,25 MHz. Con velocidad 6 serían 325.000 T.

| | Media | Mediana | Máximo |
|---|---:|---:|---:|
| T por ciclo (media de cada sala) | 160.428 | 135.252 | 490.374 (sala 120) |
| T por ciclo (p90 de cada sala) | 181.817 | 145.394 | 609.910 (sala 900) |

- **Salas dentro del presupuesto a velocidad 5:** 72 de 79 por la media y 66 de 79 por el p90.
- **Salas que se pasan:** son las de mucha gente o mucho script. La 120 (1,8 veces el presupuesto), las 91, 92, 93 y 95 de Monolith Burger (1,1-1,7 veces, con 8-24 objetos en el reparto), la 50 (1,3 veces) y la intro (900). En ellas el juego iría a 6-8 ciclos por segundo en lugar de 12.
- **Reparto del tiempo del Z80** (suma de todas las salas):

| Parte | % |
|---|---:|
| Bytecodes que no son de movimiento ni de ciclado | 47,6 |
| `send` (marco y búsqueda lineal del selector) | 27,1 |
| `Animate` nativo | 10,0 |
| Resto del kernel | 8,7 |
| Clases de ciclado | 3,8 |
| Clases de movimiento | 2,4 |
| `CanBeHere` | 0,4 |

- **La búsqueda de selectores es el gran gasto evitable.** SCIV recorre las listas de propiedades y métodos de la clase y de sus superclases: de 600 a 3.600 comparaciones por ciclo.
  Si el conversor del PC prepara para cada clase una tabla de selector a hueco (o hash), ese 27 % baja a la tercera parte, y la sala media quedaría en unos **105.000 T**.

### 2.3 El modelo de coste (lo que se ha supuesto)

- **Diseño supuesto:** PC del SCI en DE sobre una ventana de código paginada, acumulador en BC, pila SCI en RAM fija, despacho por tabla de 256 entradas (unos 50 T) y los datos del heap leídos sin traducción.
- **Costes por opcode** (con el despacho):
  - `push0`: 90 T. `pToa`: 125 T. `lal`: 135 T. `bnt`: 105 T. `eq`: 145 T.
  - `send`: 350 T, más 150 T por cada selector de variable o 450 T por cada selector de método, más 32 T por cada comparación de la búsqueda.
  - `callk`: 310 T más el kernel.
- **Kernel:**
  - `Animate`: 2.500 T fijos, más unos 3.700 T por objeto del reparto (34 selectores leídos con tabla por clase, a 90 T) y 1.500 T por objeto que se mueve (registros de sprites).
  - `CanBeHere`: 22 T por píxel del mapa de control en nibbles, más 480 T por cada objeto del reparto con el que se compara.
  - El resto: 60-6.000 T por llamada, según la función (tabla en `TOOLS/analiza.py`).
- **No incluye:**
  - **La traducción de direcciones** si el heap de datos no cabe fijo en el mapa (§3.3). Serían unos 350 accesos al heap por ciclo (propiedades y variables, objetos de los send, selectores del kernel) a unos 45 T cada uno: **unos +16.000 T, un 10 % más**.
  - La lectura de la SD al cambiar de sala.
  - El sonido, que lo hace el STM32.
- **Margen:** ±30 %. Es el mismo tipo de estimación que el estudio de 160x168 de AGI. Para afinarlo habría que escribir el núcleo del bucle y medirlo con `perf160.sh`.

## 3. Memoria

### 3.1 Heap por sala (el del diseño de Sierra: scripts enteros, clones, listas y pila)

| | Media | Mediana | Máximo |
|---|---:|---:|---:|
| Heap ocupado (pico de la sala) | 40.251 B | 40.236 B | 46.220 B |
| ...de ello, **código** de los scripts cargados | 24.534 B | 24.560 B | 30.000 B |
| ...de ello, **datos** (objetos, locales, cadenas, said, clones, listas, nodos, ventanas) | 15.717 B | 15.436 B | 19.156 B |
| Pila de la PMachine | | | 2.300 B |

- **Lo fijo:** solo con los scripts del sistema (0, 255, 994-999 y 992 Motion/Cycle) ya hay 34,7 KB, de ellos 20,7 KB de código. Cada sala añade de 4 a 12 KB.
- **Tamaño de los scripts de SQ3:** 113 scripts, 353 KB (243 KB de código). La mediana es de 2,5 KB y el mayor tiene 10 KB.
  **El código de cada script cabe siempre en 8 KB**: el mayor, el 421, tiene 8.134 B de código. Una ventana de 8 KB por script, por tanto, basta.

### 3.2 Recursos (hunk)

- **Todo el juego:** vistas 726 KB, imágenes 472 KB, sonidos 319 KB, textos 106 KB y vocabulario y fuentes 34 KB. Más los 353 KB de scripts, son **unos 2 MB**: no caben en los 512 KB de RAM paginada.
- **Por sala:** el modelo carga lo que piden los scripts (`Load`) más lo que usan `DrawPic`, `Animate` y `DoSound`, y no purga nada.
  Con eso llega a una media de 112 KB y un máximo de 253 KB (sala 95: 153 KB de vistas y 67 KB de sonido). Es una cota alta: SCIV purga el hunk cuando le falta.
- **Ya convertidos a 160:**
  - Las vistas a 4 bpp ocupan la mitad (780 KB todas).
  - La imagen en RLE ocupa unos 8 KB, más 0,7 KB de control y 1,6 KB de prioridad (§4.1).
  - El juego convertido rondaría 1,1-1,3 MB.

**Conclusión de memoria: hay que cargar de la SD por sala, como hacía SCIV desde el disquete** (son tus "overlays de disco"). El conjunto de trabajo de una sala (40-46 KB de heap más 50-150 KB de recursos) cabe holgado en los 512 KB paginados. Lo que no cabe es el juego entero.

### 3.3 El problema real: el mapa de 64 KB del Z80

Datos que lo condicionan:
- **Código del intérprete:** SCIV.EXE de SQ3 ocupa **74,8 KB desempaquetado** (EXEPACK; código y datos de 8086, sin los drivers).
  Aunque las imágenes vengan convertidas del PC (el Z80 no dibuja vectores), quedan la VM, unos 85 kernels, ventanas, controles, menús y el parser con `Said`. Mi estimación es de **40-60 KB de código Z80**. El intérprete AGI actual es un núcleo de 11 KB más overlays de unos 25 KB.
- **Datos del heap:** 15-19 KB que el código SCI direcciona con punteros de 16 bits planos, todos juntos.
- **Código SCI:** 22-30 KB por sala, en 8 KB por script como mucho.
- **Vídeo:** 16 KB en 4 bpp o 32 KB en 8 bpp.

Un reparto posible, con código del Z80 por debajo de $8000:

| Zona | Uso |
|---|---|
| `$0000-$1FFF` | ROM y sombra (hojas de sprites, como AGI) |
| `$2000-$3FFF` | Ventana de overlays del intérprete. Se cargan de la SD a la RAM paginada al arrancar y se cambian con un `POKE` de página, nunca desde la SD en mitad de un ciclo. |
| `$4000-$7FFF` | Núcleo: VM, MMU por software, kernel frecuente y tablas (16 KB) |
| `$8000-$9FFF` | Ventana del código del script en curso (una página de 8 KB por script) |
| `$A000-$DFFF` | Vídeo 160x190 a 4 bpp (15.200 B) y plano de texto |
| `$E000-$FFFF` | Ventana de datos del heap (MMU por software: 3 páginas para 15-19 KB) |

- Con **8 bpp (undithering con 256 colores) no hay sitio**: el vídeo se come toda la mitad alta. Solo valdría si la FPGA puede barrer páginas físicas que no estén mapeadas en el Z80 (no lo he comprobado).
  Con 4 bpp hay que elegir 16 colores por imagen (el 81 % de las de SQ3 salen exactas) y compartirlos con los sprites.
- **Los punteros del SCI son direcciones del heap de 64 KB.** Para paginar el código hay que convertir los scripts en el PC, separando código y datos y resolviendo los `lofsa`/`lofss`, que en SCI0 son relativos al PC, a direcciones del heap de datos.
  Es factible: se sabe todo en el momento de convertir, igual que hoy con `agi2log.py`.

## 4. Gráficos y texto

### 4.1 Imágenes a 160x200 con los tramados mezclados

SCI0 dibuja a 320x190 con 16 colores EGA y con tramado en damero: cada píxel de la imagen es una **pareja** de colores (c1, c2) antes de tramar.
El "undithering" de ScummVM (`GfxScreen::dither` y `GfxPalette::setEGA`) pinta cada pareja como un color mezclado, (c1 + c2) / 2 por canal.
En 160 de ancho, cada píxel nuevo es una pareja de 2x1 píxeles de SCI, y en una zona tramada los dos llevan la misma pareja: el tramado de 320 se convierte sin pérdida en un color de 160.
Datos de `graficos.py`, con las imágenes dibujadas por el modelo:

| | SQ3 completo (115 imágenes) | 8 demos (94 imágenes) |
|---|---|---|
| Colores mezclados distintos por imagen | mediana 12, máximo 25 | media 9-18 según el juego, máximo 29 |
| Imágenes con 16 colores mezclados o menos | 93 de 115 (81 %) | — |
| Píxeles tramados (c1 ≠ c2) | mediana 12 %, máximo 54 % | media 7-43 % (Camelot el que más) |
| Celdas de 2x1 con dos colores distintos (lo que se pierde al pasar a 160) | mediana 9,3 %, p90 15 %, máximo 18,8 % | media 5,7-14,2 %, máximo 25,9 % |
| Visual a 160x190 comprimida con RLE por filas | media 7,9 KB, máximo 16,3 KB | — |
| Plano de control a 320x190 con RLE | media 0,7 KB, máximo 2,5 KB | — |
| Plano de prioridad a 320x190 con RLE | media 1,6 KB, máximo 9,6 KB | — |

- **Paleta:** con el modo de 8 bpp caben de sobra todas las mezclas (136 parejas posibles más los 16 EGA) en la paleta de 256. En 4 bpp con `pal16` solo valen tal cual el 81 % de las imágenes de SQ3, y además los sprites comparten `pal16`.
- **Pérdida:** lo que se pierde de verdad son las líneas verticales de 1 píxel y los bordes (un 9 % de las celdas en la imagen mediana). La imagen con más detalle fino de SQ3 (la 11, 18,8 %) se ve bien a 160 (PNG en el scratchpad de la sesión, `png_sq3/sq3full_pic011_*.png`).
- **Vertical:** es 1:1. La imagen de SCI son 190 líneas más 10 de la barra de menú: 200.
- **Las imágenes se convierten en el PC**, como en AGI (`agi2hr.py`). El Z80 no dibuja vectores: lee la visual (RLE), el plano de control (para `CanBeHere` y `OnControl`, que trabajan a 320 de ancho) y el de prioridad (para tapar los sprites).
- **Memoria:** 8 bpp a 160x200 son 32.000 B, cuatro bloques de 8 KB: toda la mitad alta del mapa del Z80. En 4 bpp son 16.000 B (dos bloques). Esto choca con el heap (§3.3).

### 4.2 Sprites (formato B, 8x8 a 4 bpp)

Con el formato B (16 colores de `pal16`, máscara y color transparente por sprite) las vistas EGA de SCI0 pasan **sin perder color**: son exactamente 16 colores.
Lo que queda es el tamaño. Las celdas a 160 de ancho ocupan 7,2 mosaicos de 8x8 de media (27.273 mosaicos en las 3.769 celdas de SQ3) y 81 como máximo.
En el recorrido, el reparto visible de cada ciclo ocupa:

- **Mosaicos del reparto visible:** mediana de 16 y máximo de 287 (la intro). 15 de las 79 salas pasan de 64 en algún ciclo (salas 14, 40, 90, 91, 95, 900...).
- **Mosaicos en una sola línea:** mediana de 3 y máximo de 25. 13 salas pasan de 12.
- Ojo: son cotas altas, porque se cuentan los rectángulos enteros y también los objetos parados.

Los objetos parados (`stopUpdate`, que SCI ya trata como fondo) se pueden pintar en la imagen en lugar de ir como sprites, igual que hace AGI con los rótulos anchos por software.

### 4.3 Texto

- La fuente 0 de SQ3 tiene 8 px de alto y 6,4 px de ancho medio con el texto real del juego (2.646 cadenas, 45 caracteres de media), así que caben **unos 50 caracteres en 320 px**. Las demás fuentes de los demos rondan los 4,6-6,6 px (48-70 caracteres).
- El plano de texto de 40x25 de la FPGA (`POKE 2069`, el que usa AGI 160w) tiene celdas de 8 px de ancho sobre 320. Como las ventanas de `Print` y de los diálogos las dimensiona el script con `TextSize`, que es un kernel, basta con que el intérprete mida con 8 px por carácter: las ventanas saldrán **un 25 % más anchas** y algunas líneas se partirán antes. Las de 300 px pasan de 50 a 40 columnas.
- Los menús, la barra de estado (`DrawStatus`) y los botones (`DrawControl`) son del kernel y se pintan en ese mismo plano.

## 5. La otra vía: la VM en el STM32F407

**Reparto:** el STM32 ejecuta la PMachine, el kernel, la lógica de Animate, los movimientos y el parser, con los recursos sacados de la SD. El Z80 solo dibuja (imagen, sprites, texto) y lee el teclado.

| | Necesita | Comentario |
|---|---|---|
| Heap SCI | **hasta 64 KB; medido en SQ3 46 KB como máximo (40 KB de mediana)**, más 4 KB de pila | No cabe en la SRAM principal. Entra justo en la **CCM RAM** (64 KB, solo datos y sin DMA, que el heap no necesita). Hoy la CCM la llena el depurador: 40 KB de símbolos y 20 KB de traza (`DEBUGGER.cpp`). Mientras corre SCI, el depurador se quedaría sin símbolos ni traza. |
| Pila PMachine | 2,3 KB medidos (se reserva 4 KB) | En la CCM, con el heap. |
| Recursos | vistas: solo las cabeceras (anchos, altos, desplazamientos, para `CanBeHere`, `BaseSetter` y `Animate`); control y prioridad de la sala, unos 30 KB a 320x190 en nibbles o 2-12 KB en RLE; textos y vocabulario, a la carta | Las imágenes no hace falta tenerlas en el STM32: van ya convertidas a la SD y las lee el Z80. |
| Total de RAM | **unos 50 KB en la CCM y 10-20 KB en la SRAM principal** (estado de la VM, control de la sala en RLE, cabeceras de vistas y búferes de texto y vocabulario) | Al firmware le quedan **menos de 40 KB** libres en la SRAM principal (dato del usuario, 2026-11-08). De ahí sale también la pila del firmware. Sin la CCM no cabe; con ella, entra con poco margen. |
| Flash | 60-100 KB de código de la VM en C | `firmware.bin` ocupa 296 KB y empieza en `0x0800C000`. La EEPROM emulada de STM32duino ocupa el último sector (el 7, `0x08060000`, de 128 KB). Así que **quedan unos 46 KB antes de chocar con ella**, y el enlazador no avisa (`maximum_size` es 512 KB). La EEPROM son solo los 128 bytes de `SETBYTE` 128-255 (`COMMANDS.cpp`). El RTC es el interno del STM32 y tiene batería, así que podrían ir a la SRAM de respaldo (4 KB) o a los registros de respaldo del RTC. Eso libera el sector 7 y deja unos 168 KB. |
| La SRAM de 512 KB | — | No sirve como memoria de la VM. El STM32 la toca con sus propias líneas (`MEM.cpp`) solo mientras el Z80 está en reset, a 13 µs por acceso. |
| CPU | 550 bytecodes por ciclo de media y menos de 10.000 de pico | Un Cortex-M4 a 168 MHz con una VM en C hace varios millones de bytecodes por segundo: un ciclo de SCI le cuesta menos de 1 ms. No es problema. |
| Enlace con el Z80 | por ciclo: posiciones y celdas de los sprites que cambian, texto y eventos, unos 100-300 B | A unos 21 T/B (la estimación que usa AGI para `f_read_n`, sin medir en placa), unos 6.000 T por ciclo. La imagen se lee una vez por sala: unos 8 KB en RLE, de 0,1 a 0,2 s. |
| Sonido | SCI0 trae en cada canción el canal de PCjr/Tandy (3 voces y ruido) | Encaja con el AY que ya emula el STM32. |

**Esfuerzo:** hay que portar a C, para STM32duino, la parte SCI0 de `engines/sci`: la VM (`vm.cpp`, unas 1.400 líneas), el gestor de objetos y scripts, unos 85 kernels (listas, cadenas, matemáticas, `Animate` sin dibujo, movimiento, `CanBeHere`, `Format`, eventos, `DoSound`) y el parser (`said.cpp` y vocabulario).
Calculo **8.000-12.000 líneas de C**. Del lado Z80 basta un visor: imagen, sprites, plano de texto y teclado, al estilo de lo que ya hay para AGI 160w, de unos 6-10 KB.
**Licencia:** ScummVM es GPLv3, como el repo SCUMM. Copiar su código al firmware solo vale si el firmware se publica con licencia compatible: en la raíz de SD81-Booster no he visto ningún fichero LICENSE.

**Lo bueno:** no hay límite de CPU, el heap de 64 KB del diseño de Sierra entra entero en la CCM, los scripts se ejecutan tal cual (sin convertirlos en el PC) y valdrían igual los demás SCI0 (KQ4, LSL2/3, PQ2, Hero's Quest...) e incluso SCI01.
**Lo malo:** es firmware nuevo y grande en el STM32, que ya tiene mucho dentro. Exige quitarle la CCM al depurador mientras se juega y mover la EEPROM, y depende de que el STM32 pueda ejecutar la VM entre las peticiones del Z80 sin romper el resto de los servicios (AY, SD, WiFi).

## 6. Conclusión

- **Veredicto: no viable con el firmware de hoy.** La recomendación del primer informe (la VM en el STM32) daba por hecho que había sitio para sus 70-90 KB de RAM. Quedan menos de 40 KB en la SRAM principal y unos 46 KB de flash.
- **La vía del STM32 sigue siendo la mejor, si se aceptan dos cambios previos al firmware:**
  1. **La CCM para SCI:** el heap y la pila de la PMachine (unos 50 KB) van a la CCM. Mientras se juega, el depurador se queda sin símbolos ni traza, o con muchos menos.
  2. **La EEPROM fuera de la flash:** los 128 bytes persistentes pasan a la SRAM de respaldo del RTC. Así se libera el sector 7 y quedan unos 168 KB para la VM.
     Esto conviene hacerlo de todos modos: al firmware solo le quedan unos 46 KB antes de pisar ese sector, y nada lo comprueba al compilar.
  - Con eso, el reparto es el del §5 (la VM en el STM32 y el Z80 como visor), y antes de empezar habría que comprobar que la VM pueda correr entre las peticiones del Z80 sin parar el AY ni la SD.
- **Si aun así se quiere el Z80 solo,** el orden sería:
  1. Conversor en el PC: scripts partidos en código y datos, tablas de selectores por clase, imágenes a 160 en 4 bpp con control y prioridad en RLE, vistas al formato B.
  2. Núcleo de la VM y MMU, medidos con `perf160.sh` en las salas 2, 120 y 92 antes de seguir.
  3. Kernel por overlays.
  - Con el modelo de hoy, la sala típica cabe en la mitad del ciclo y las más pobladas irían a la mitad de velocidad.
- **Lo que no está medido:**
  - El parser: no se han tecleado órdenes. `Said` se ejecuta cuando hay frase, no en cada ciclo.
  - Los T-estados reales del Z80: son un modelo.
  - Los demás juegos SCI0 completos: de LSL2/3, PQ2, KQ4, Hero's Quest e Iceman solo hay demos. Sus imágenes y vistas dan cifras del mismo orden (§4).
  - Que la FPGA pueda mostrar vídeo desde páginas no mapeadas: si pudiera, cambiaría el §3.3.

## Apéndice: medidas por sala (SQ3)

Recorrido de `TOOLS/recorrido.sh` (250 ciclos por sala, con el ego andando con flechas al azar) más la partida normal de `sq3_andar` (sala 2 y siguientes). En las salas 20 y 50 Roger muere al poco de entrar: solo cuentan los ciclos de antes.
"Mosaicos / por línea" es el máximo de mosaicos de 8x8 (a 160 de ancho) del reparto visible y el máximo en una sola línea. Cuenta los rectángulos enteros, así que es una cota alta. La tabla también está en `medidas/sq3_tabla.md`.

| Sala | Ciclos | Bytecodes media / p90 / max | Mov.+cicl. (media) | Sends | Z80 T media / p90 | Heap max (código + datos) | Hunk max | Reparto | Mosaicos / por línea |
|---:|---:|---|---:|---:|---|---|---:|---:|---|
| 2 | 5914 | 570 / 641 / 1493 | 56 | 27 | 165184 / 187731 | 41740 (25690 + 15604) | 94579 | 3.0 | 0 / 0 |
| 3 | 373 | 453 / 528 / 1083 | 72 | 22 | 128322 / 153925 | 40530 (24560 + 15526) | 167894 | 1.0 | 12 / 3 |
| 4 | 250 | 538 / 589 / 1161 | 106 | 26 | 159607 / 177609 | 39502 (23630 + 15414) | 144085 | 2.0 | 18 / 5 |
| 5 | 1402 | 522 / 566 / 1107 | 58 | 25 | 148819 / 164205 | 38732 (23296 + 15032) | 94579 | 1.0 | 0 / 0 |
| 6 | 200 | 607 / 848 / 1368 | 45 | 30 | 173013 / 241820 | 41376 (25416 + 15484) | 167886 | 3.0 | 36 / 7 |
| 7 | 250 | 469 / 461 / 821 | 14 | 23 | 131227 / 129458 | 39456 (23878 + 15218) | 42259 | 1.0 | 10 / 2 |
| 8 | 250 | 522 / 575 / 1401 | 60 | 26 | 150189 / 170232 | 46220 (28964 + 16820) | 69794 | 2.0 | 19 / 3 |
| 9 | 250 | 276 / 267 / 620 | 0 | 13 | 69960 / 68088 | 42358 (26170 + 15864) | 99541 | 0.0 | 0 / 0 |
| 10 | 250 | 309 / 299 / 883 | 0 | 14 | 76774 / 74373 | 42254 (26010 + 15868) | 111707 | 0.0 | 8 / 4 |
| 11 | 250 | 458 / 468 / 1000 | 71 | 21 | 125792 / 132156 | 41480 (25810 + 15264) | 137806 | 1.0 | 21 / 3 |
| 12 | 748 | 464 / 468 / 1084 | 84 | 22 | 130335 / 132146 | 41182 (25508 + 15268) | 141824 | 1.0 | 21 / 3 |
| 14 | 458 | 371 / 402 / 1803 | 0 | 18 | 103302 / 115892 | 46066 (29006 + 16542) | 152276 | 3.3 | 214 / 19 |
| 15 | 250 | 778 / 743 / 48219 | 223 | 27 | 204910 / 207938 | 44744 (26738 + 17150) | 140980 | 2.4 | 89 / 10 |
| 16 | 42 | 337 / 323 / 955 | 0 | 17 | 83912 / 80220 | 40236 (24260 + 15508) | 152266 | 0.0 | 0 / 0 |
| 17 | 250 | 345 / 319 / 1693 | 0 | 16 | 90192 / 84811 | 43834 (26394 + 16886) | 166897 | 0.0 | 0 / 0 |
| 18 | 748 | 481 / 456 / 2753 | 0 | 25 | 145776 / 140101 | 45000 (27030 + 17370) | 194029 | 6.0 | 24 / 11 |
| 19 | 250 | 489 / 471 / 1097 | 0 | 25 | 134229 / 130726 | 40294 (24258 + 15648) | 63979 | 1.9 | 18 / 6 |
| 20 | 26 | 492 / 833 / 1097 | 109 | 24 | 137981 / 225411 | 35940 (21284 + 14204) | 73769 | 1.8 | 15 / 7 |
| 21 | 250 | 264 / 256 / 560 | 0 | 12 | 66909 / 65198 | 36344 (21858 + 14176) | 24019 | 0.0 | 0 / 0 |
| 25 | 250 | 362 / 352 / 980 | 0 | 17 | 98998 / 96460 | 37542 (22470 + 14726) | 41731 | 2.0 | 13 / 5 |
| 27 | 250 | 363 / 431 / 1263 | 38 | 17 | 101481 / 132036 | 36104 (21490 + 14196) | 58779 | 1.4 | 47 / 7 |
| 28 | 250 | 513 / 528 / 3840 | 15 | 26 | 147468 / 156043 | 43546 (26590 + 16230) | 89663 | 3.0 | 90 / 14 |
| 29 | 748 | 601 / 660 / 2709 | 38 | 30 | 181944 / 208625 | 42534 (25990 + 15918) | 112533 | 4.9 | 55 / 13 |
| 31 | 250 | 339 / 369 / 684 | 25 | 16 | 91924 / 103163 | 37468 (22376 + 14728) | 86744 | 1.0 | 24 / 6 |
| 40 | 250 | 441 / 411 / 2433 | 8 | 19 | 115035 / 106049 | 37896 (22338 + 15000) | 108412 | 2.2 | 274 / 19 |
| 41 | 250 | 386 / 374 / 781 | 14 | 18 | 102979 / 100248 | 39670 (24766 + 14544) | 127022 | 1.0 | 10 / 2 |
| 42 | 250 | 442 / 430 / 1159 | 14 | 22 | 122216 / 119278 | 40770 (25542 + 14858) | 139289 | 2.0 | 11 / 2 |
| 43 | 748 | 514 / 632 / 3281 | 72 | 24 | 152372 / 188998 | 44444 (27284 + 16484) | 162450 | 3.3 | 110 / 15 |
| 44 | 250 | 881 / 1060 / 2164 | 235 | 41 | 250623 / 306690 | 43208 (27382 + 15188) | 64518 | 3.0 | 24 / 4 |
| 45 | 250 | 517 / 502 / 1104 | 14 | 22 | 135252 / 131725 | 41402 (26274 + 14748) | 66400 | 2.0 | 11 / 2 |
| 46 | 250 | 574 / 562 / 1626 | 14 | 22 | 144090 / 141110 | 42900 (27640 + 14880) | 71768 | 2.0 | 11 / 2 |
| 47 | 250 | 937 / 1108 / 3405 | 256 | 39 | 256047 / 307314 | 46154 (30000 + 15414) | 76110 | 2.0 | 39 / 8 |
| 48 | 250 | 524 / 510 / 1112 | 14 | 22 | 136626 / 133409 | 41620 (26474 + 14756) | 79783 | 2.0 | 6 / 4 |
| 49 | 748 | 494 / 484 / 1016 | 14 | 22 | 135267 / 133030 | 40790 (25520 + 14880) | 91097 | 2.0 | 14 / 2 |
| 50 | 151 | 1351 / 1655 / 2293 | 204 | 48 | 361023 / 446298 | 44494 (28650 + 15206) | 68549 | 3.0 | 20 / 3 |
| 51 | 250 | 922 / 980 / 2183 | 251 | 41 | 256494 / 277962 | 44662 (28770 + 15254) | 68308 | 3.0 | 15 / 3 |
| 52 | 250 | 611 / 599 / 1651 | 65 | 27 | 172380 / 169837 | 43852 (28294 + 15140) | 81992 | 4.0 | 18 / 5 |
| 53 | 250 | 559 / 572 / 1733 | 67 | 26 | 153770 / 157904 | 40904 (25378 + 15068) | 102339 | 2.2 | 52 / 14 |
| 54 | 250 | 429 / 422 / 910 | 14 | 20 | 116659 / 114848 | 36002 (21452 + 14192) | 115888 | 2.0 | 12 / 2 |
| 60 | 748 | 426 / 410 / 899 | 5 | 21 | 115029 / 111101 | 38076 (22930 + 14744) | 131212 | 2.0 | 6 / 2 |
| 61 | 479 | 473 / 573 / 1151 | 78 | 24 | 134383 / 170740 | 37722 (22762 + 14518) | 82648 | 1.5 | 16 / 2 |
| 62 | 102 | 518 / 552 / 1180 | 77 | 24 | 140171 / 152338 | 38170 (23184 + 14582) | 51892 | 1.0 | 18 / 3 |
| 63 | 250 | 357 / 348 / 735 | 0 | 16 | 87574 / 85571 | 37334 (22584 + 14428) | 55160 | 0.0 | 0 / 0 |
| 64 | 71 | 509 / 476 / 1185 | 18 | 24 | 137994 / 127165 | 37956 (22872 + 14670) | 68279 | 1.9 | 11 / 2 |
| 66 | 879 | 544 / 594 / 1256 | 6 | 26 | 145156 / 155149 | 40886 (25298 + 15142) | 82652 | 2.7 | 66 / 12 |
| 67 | 81 | 459 / 540 / 1094 | 23 | 22 | 122100 / 150329 | 37600 (22768 + 14428) | 82648 | 1.0 | 10 / 2 |
| 68 | 250 | 404 / 392 / 825 | 0 | 18 | 102314 / 99586 | 37964 (22962 + 14670) | 42686 | 1.0 | 1 / 1 |
| 69 | 444 | 592 / 702 / 2033 | 78 | 29 | 173209 / 214663 | 41186 (25098 + 15616) | 77738 | 4.4 | 32 / 4 |
| 70 | 56 | 450 / 432 / 1069 | 17 | 21 | 118679 / 112930 | 37842 (22918 + 14504) | 77738 | 1.0 | 10 / 2 |
| 71 | 304 | 368 / 420 / 3027 | 3 | 17 | 94465 / 111680 | 37544 (22696 + 14444) | 105278 | 0.2 | 10 / 2 |
| 72 | 196 | 460 / 504 / 1087 | 52 | 23 | 129187 / 145394 | 37864 (22884 + 14576) | 105278 | 1.0 | 10 / 2 |
| 73 | 191 | 477 / 525 / 1063 | 75 | 24 | 133257 / 151206 | 37654 (22726 + 14524) | 119104 | 1.0 | 6 / 2 |
| 74 | 557 | 488 / 527 / 1241 | 61 | 24 | 134560 / 150494 | 38836 (23684 + 14748) | 119104 | 1.0 | 10 / 2 |
| 75 | 250 | 409 / 553 / 1564 | 56 | 20 | 118950 / 160438 | 40698 (24814 + 15480) | 63160 | 1.0 | 12 / 3 |
| 80 | 58 | 398 / 380 / 942 | 17 | 19 | 108946 / 103515 | 35786 (21432 + 13962) | 70722 | 1.0 | 10 / 2 |
| 81 | 442 | 602 / 723 / 1692 | 82 | 28 | 177231 / 222589 | 37502 (22234 + 14664) | 82485 | 4.8 | 31 / 9 |
| 85 | 250 | 475 / 484 / 1188 | 59 | 22 | 136853 / 141006 | 37638 (22730 + 14456) | 116383 | 3.0 | 32 / 6 |
| 86 | 748 | 465 / 483 / 1175 | 40 | 22 | 132656 / 139760 | 36058 (21674 + 14026) | 121413 | 2.0 | 22 / 6 |
| 90 | 202 | 917 / 1141 / 2773 | 148 | 42 | 265696 / 334314 | 42394 (26318 + 15506) | 152402 | 5.9 | 114 / 25 |
| 91 | 162 | 1144 / 1122 / 6289 | 75 | 57 | 401657 / 393259 | 45116 (26158 + 18258) | 152446 | 24.0 | 129 / 13 |
| 92 | 250 | 1428 / 1583 / 6061 | 142 | 69 | 462314 / 499725 | 45990 (27196 + 18086) | 160664 | 20.7 | 83 / 12 |
| 93 | 476 | 1390 / 1525 / 4552 | 304 | 65 | 420260 / 456180 | 45220 (26064 + 18168) | 190450 | 7.9 | 64 / 10 |
| 94 | 24 | 587 / 1019 / 1457 | 103 | 30 | 175731 / 280975 | 37736 (22326 + 14906) | 190446 | 2.9 | 38 / 6 |
| 95 | 748 | 972 / 1088 / 3745 | 110 | 46 | 289331 / 320062 | 42450 (25474 + 16286) | 252672 | 13.0 | 239 / 20 |
| 98 | 250 | 377 / 366 / 681 | 0 | 17 | 95143 / 92716 | 36102 (21498 + 14248) | 151964 | 1.0 | 0 / 0 |
| 99 | 250 | 815 / 958 / 1502 | 0 | 37 | 228954 / 272812 | 36644 (21678 + 14216) | 157402 | 4.0 | 10 / 8 |
| 115 | 250 | 412 / 406 / 721 | 0 | 18 | 97976 / 96530 | 35542 (21096 + 14064) | 161917 | 0.0 | 0 / 0 |
| 116 | 250 | 544 / 798 / 2300 | 130 | 26 | 163837 / 246850 | 39552 (23524 + 15400) | 192760 | 3.3 | 70 / 19 |
| 117 | 748 | 342 / 380 / 851 | 12 | 16 | 93267 / 112398 | 37304 (21962 + 14968) | 236504 | 1.9 | 24 / 6 |
| 120 | 250 | 1558 / 1939 / 3241 | 403 | 78 | 490374 / 584090 | 43784 (27556 + 15540) | 116344 | 9.0 | 108 / 21 |
| 121 | 250 | 560 / 846 / 2125 | 82 | 27 | 165607 / 262390 | 37074 (22102 + 14406) | 131697 | 3.9 | 24 / 6 |
| 280 | 250 | 257 / 251 / 581 | 0 | 13 | 67408 / 66192 | 37182 (22818 + 14054) | 205235 | 0.0 | 0 / 0 |
| 290 | 250 | 282 / 274 / 612 | 0 | 14 | 72264 / 70746 | 40010 (24712 + 14988) | 226754 | 0.0 | 0 / 0 |
| 420 | 748 | 371 / 363 / 703 | 14 | 18 | 101804 / 100118 | 37346 (22490 + 14508) | 228922 | 1.0 | 8 / 2 |
| 421 | 250 | 785 / 837 / 2442 | 110 | 38 | 235743 / 255496 | 44962 (28844 + 15618) | 66045 | 7.5 | 102 / 10 |
| 470 | 250 | 557 / 538 / 2514 | 51 | 30 | 174510 / 170111 | 42392 (25900 + 15904) | 114233 | 8.0 | 104 / 13 |
| 690 | 250 | 355 / 351 / 680 | 51 | 18 | 98384 / 98029 | 35548 (21206 + 13994) | 119016 | 1.0 | 8 / 2 |
| 777 | 400 | 410 / 424 / 733 | 88 | 20 | 116464 / 121953 | 35234 (20916 + 13926) | 19064 | 1.0 | 0 / 0 |
| 900 | 42 | 1129 / 1802 / 10940 | 28 | 61 | 355304 / 609910 | 44686 (25638 + 18348) | 124080 | 10.0 | 287 / 16 |

