# PLAN_SPRITES4: AGI 160w con los sprites de 4 bits y hoja (formato B) — rama `agi-sprites4`

Rama `agi-sprites4`, creada el 6 de noviembre de 2026 desde `agi-mode160w` (8129a84) en la carpeta de siempre, `C:\ClaudeCode\SD81-Booster\SCUMM`. Lleva consigo los cambios sin commitear del usuario
(`AGI/V2/ENGINE/tests.inc` y `AGI/V3/`), que no son de este trabajo: no entran en ningún commit de sprites.

Reglas: responder en español; sin commit ni push salvo que el usuario lo pida (pie `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`); no compilar el firmware del STM32;
sin `_` en nombres de fichero del ZX81/SD; sin código por encima de `$8000`; ensamblador `pasmo`; sin regresiones (con `GFX4=0` los binarios salen idénticos y `dump/runall.sh` da 5 OK).

## 1. Hardware nuevo (repo SD81-Booster, rama `fpga-sprites-hoja`, commit 3a7c997, probada en placa con SPRDBUF)

Fuentes de verdad, solo lectura: `FPGA/SD81V2.1000/sprite_engine.v`, la cabecera de POKEs de sprites de `SD81.v`, `EXAMPLES/SPRDBUF/sprdbuf.asm` (ejemplo de uso) y `claude/planning/sprites_hoja_decisiones.md`.

- Sprite 8x8, **4 bits por píxel, índice 0 transparente**, color = `pal16[índice]`; 64 sprites, 12 por línea.
- `POKE 2100,n` elige sprite; 2101 activo; 2102/2103 X (+32); 2104 Y (+32); **2105 = página de la hoja**; **`POKE 2129,b`** = bloque de 8 KB (0-7) de la hoja, se aplica en el VSYNC.
- Celda = 32 B: 8 filas de 4 bytes, nibble alto = píxel de la izquierda. Dirección de la fila f: `(b<<13)|(página<<5)|(f<<2)|byte`.
- La FPGA lee las hojas de su **espejo de la RAM de sombra** (lo que **escribe** el Z80), no de la SRAM paginada: las celdas deben estar en direcciones del Z80 escritas por la CPU y que nada vuelva a pisar.
- Negro opaco: decisión del usuario = **índice 8** (gris oscuro) reprogramado a negro con la paleta de 16 activa; el azul no se toca. En 160w `pal16` ya está activa (por omisión, colores digitales de Chroma81; el índice es `to_chroma(ega)`).

## 2. Lo que hay hoy (leído)

- `ENGINE/agihws.asm`: `spr_put` (~líneas 1568-1700) escribe un mosaico de 24 B (8 de color de fila tinta*16+papel, 8 de píxel, 8 de máscara) con un `ldir` a `POKE 2105`, y la máscara recortada por prioridad
  (`hw_mask`, `hw_mkp`, `PROW`) con otro `ldir` a `2105+16`. Solo reescribe si cambia la etiqueta (vista/bucle/celda/mosaico) o la posición (tabla `SHD`). `t_sinit` y los apagados (`SPR_SEL`/`SPR_ON`) están en las líneas ~11-40, ~257 y ~765.
- `TOOLS/agi2spr.py` genera `Nvvvl.SPR`: mosaicos de 24 B y, con `GFX4`, un bloque por celda con los píxeles exactos de 16 colores (RLE de códigos de Chroma), que hoy solo usan add.to.pic, los rótulos anchos y show.obj.
- Modelo: `TOOLS/agi_vm.py` (`hw_sprites()`, `render4()`); arnés: `ENGINE/test_gfx4.sh`, `test_vm.sh`, `dump/runall.sh`.
- Mapa de memoria: núcleo `$4200-$6D00`, datos hasta `$7E60`, pila y ventana de lógica `$8000`, imagen `$A000-$D47F`, plano de texto `$D480-$D867`, glifos `$D800-$DFFF` (huecos: `$D868-$D8FF` y `$DC00-$DCFF`), bloque 7 paginado.
- La prioridad contra la imagen es una máscara por píxel que calcula el Z80; con el formato nuevo pasa a ser «poner a 0 los nibbles tapados» en la celda del sprite, así que **cada sprite necesita su propia celda**
  (64 celdas = 2 KB como máximo; SQ1 usa 14, KQ2 28).

## 3. Plan propuesto (crearlo como `AGI/PLAN_SPRITES4.md` y discutirlo con el usuario antes de tocar mucho código)

1. **Etapa 1, misma imagen que hoy:** `spr_put` convierte el mosaico antiguo en la celda de 32 B del sprite (píxel = máscara ? (bit ? tinta : papel) : 0), sin tocar `agi2spr.py`. Comprobar Z80 == `agi_vm.py` en SQ1, KQ2, PQ1, SQ2 y KQ1.
2. **Etapa 2, 16 colores exactos:** `agi2spr.py` emite la celda de 32 B con los colores exactos y el Z80 solo aplica la prioridad (AND con máscara de nibbles).
3. **Etapa 3:** simplificar `agisw4.asm` si procede y medir el tiempo por ciclo.

## 4. Decisiones del usuario (6 de noviembre de 2026)

1. **Color: rotación, se sacrifica el magenta claro en los sprites.** Solo con GFX4: índice 0 = magenta claro, índice 8 = negro, índice 11 = gris oscuro; los demás, como `to_chroma`. La imagen conserva los 16 colores;
   en los sprites hardware el magenta claro (EGA 13) sale magenta (EGA 5). Medido en vistas: 0,64-2,94 % de los píxeles según el juego, frente al 0,63-16,27 % del gris oscuro (86 % de las celdas de KQ1).
   Regresión aceptada expresamente. Se descarta elegir el color por juego: `agivm.bin` es común.
2. **Las celdas viven en la sombra del bloque 0** (`POKE 2129,0`): el Z80 escribe en direcciones de la ROM, la SRAM no cambia y la sombra sí, así que no gastan RAM del Z80. El sprite n usa la página n (`$0000-$07DF`), y el 63 usa la 67 (`$0860`).
   Páginas fijas desde `t_sinit`, sin gestor de celdas. Intocables: `$07E0-$085F` (POKEs), `$0C00-$0FFF` y `$1800-$1BFF` (tablas), `$1000-$17FF` (traza del depurador), `$1E00-$1FFF` (fuente).
   El Z80 no puede releer las celdas. Pendiente: probar en placa una hoja en el bloque 0 (nunca se ha hecho) y que `SD81Booster.cpp:734` de EightyOne copie a la sombra las escrituras al bloque 0 (hoy sale antes; lo hace la sesión del emulador).

## 4b. Estado (6 de noviembre de 2026): etapa 1 hecha, sin commit y sin probar en placa

- Rotación en `agi2hr.py` (`ROT`, `to_chroma_spr`), `pal_agi` en `t_sinit`, texto `$8F`, imagen negra `$88`. Solo con GFX4.
- Fuera de la ventana (filas 0 y 22-24) el 4 bpp saca `pal16[borde]`, es decir `pal16[0]`: ninguna celda del plano de texto puede ser transparente ahí (saldría magenta claro). `video_init` las deja en espacios y `cmp_vm.py` lo comprueba.
- `spr_put` → `hw_cell` convierte el mosaico en celda; `t_sbye` (`OVL_SPRBYE`) restaura la paleta y `POKE 2129` al volver a BASIC.
- Arnés: `test_scumm.cpp` copia a la sombra lo escrito en el bloque 0 y vuelca `POKE 2129` y `pal16`.
- Verificado: `GFX4=0` idéntico, `dump/runall.sh` 5 OK, `test_gfx4.sh` 17 ok.
- Velocidad (T-estados en 5 tramas, `perf160.sh`, HEAD → etapa 1): SQ2 sala 53 225.307 → 262.481 (+16,5 %), KQ2 sala 11 123.917 → 136.185 (+9,9 %), PQ1 sala 20 175.288 → 183.997 (+5,0 %). Toda la diferencia es `hw_cell`: unos 6.700 T por mosaico.
  Regresión no aceptada. La etapa 1 es un paso intermedio, no algo que se pueda publicar.

## 4c. Análisis de velocidad (6 de noviembre de 2026): el formato B no da velocidad apreciable

Medido en SQ2 53, KQ2 11 y PQ1 20 con el ego andando, registrando cada llamada a `spr_put` con una copia del arnés en el scratchpad (300 tramas). Son solo tres salas.

- La copia de mosaicos en HEAD (`hp_all` + `hp_mk`) ya era poco: 2.854 T de 225.307 en SQ2 (1,3 %), 1.422 de 123.917 en KQ2 (1,1 %) y 917 de 175.288 en PQ1 (0,5 %). Ese es el techo de lo que puede ahorrar la hoja. Caso peor teórico: 64 mosaicos × 504 T = 32.000 T; el máximo visto, 22 en un render.
- `t_render` ya no llama a `spr_put` si nada cambia. Medido en SQ2: 382 llamadas y ninguna inútil, así que la idea de la huella por sprite no sirve: queda descartada.
- La etapa 2 tal como estaba planteada (páginas fijas 1:1) copiaría 32 B en lugar de 24 (672 T frente a 504) y además aplicaría la prioridad con AND: sería más lenta que HEAD. Las páginas fijas renuncian al puntero, que es la única ventaja de velocidad de la hoja.
- Con caché de celdas, la hoja sí sirve: SQ2 hace 247 llamadas sin recorte con 38 celdas distintas. Un mosaico sin recorte solo necesitaría `POKE 2105`. Los recortados (135 de 382, 84 celdas distintas) siguen siendo celda propia. Estimación sin medir: 3.700 T por ciclo en SQ2 frente a 2.854 en HEAD, es decir, HEAD ± 1 %.
- Corrección de esa estimación: contando el coste real del recorte en el Z80, salen unos 5.900 T por render en SQ2 (+1,3 % del ciclo), no 3.700. Los recortados dominan.
- Variantes modeladas con el registro de `spr_put` (T por render en SQ2, frente a 3.209 de HEAD en el mismo modelo; caché de 108 celdas, búsqueda estimada en 200 T): etapa 1, 42.657; páginas fijas con celdas hechas, 7.638; caché con recorte en el Z80, 5.863; caché con conversión en el Z80 y dos colores por fila, 17.573; caché y **máscara de 8 bytes en la tabla del sprite (cambio de FPGA)**, 2.481. En KQ2 y PQ1 el arranque en frío (cada mosaico nuevo) deja la máscara en 1,3-1,6 veces HEAD, porque esos registros son cortos.
- El esquema de color no influye en la velocidad: una celda ocupa 32 B con dos colores por fila o con 16 colores. Lo que decide es dónde se aplica el recorte.
- La máscara por hardware: leer el campo `5 + fila` de la tabla (`POKE 2106-2113`) y anular nibbles al cargar el slot. Un paso más por sprite cargado (8 en lugar de 7, 12 pasos más en el caso peor, con ~20 de margen) y polaridad 1 = oculto, para que los programas que dejan esos campos a 0 sigan viendo el sprite entero. Sin diseñar, sintetizar ni simular.
- Propuesta del usuario, formato A con páginas (colores y máscara como antes): no necesita la rotación, ni convertir, ni tocar los `.SPR`, pero sí un motor de FPGA nuevo. La máscara también define la forma del mosaico, así que al cambiar de mosaico hay que escribirla igualmente: con la página de 16 B (color y forma) y la máscara en la tabla, 2.645 T por render en SQ2 (0,82 veces HEAD, 560 T menos, un 0,25 % del ciclo), con búsqueda de 200 T; con 60 T, 1.754. KQ2 1,05-1,30 veces y PQ1 0,88-1,09 veces (registros cortos, arranque en frío). Con página de 24 B y una segunda máscara de recorte, SQ2 baja a 2.127 T, con más hardware. Sin 4 bpp salvo que convivan los dos formatos.
- Otros juegos, contando instrucciones sin medir: en GALAXIAN cada aleteo reescribe 49 sprites (837 T cada uno, 41.000 T, el 63 % de una trama, una vez cada 16 tramas); con páginas, unos 4.900 T, y con dos hojas y `POKE 2129`, una sola escritura si cambian todos. PONG y SPORTS cargan los gráficos una vez: no ganan nada. SCUMM tiene máscara de profundidad como AGI y comparte su problema de recorte; sin medir. La hoja vale para juegos de muchos sprites sin prioridad por píxel, no para AGI.
- El gasto grande está en otro sitio: la prioridad (`pri`) es el 12,7 % en SQ2, y el intérprete de lógica, la mayor parte. El formato B no toca ninguno de los dos.
- Lo que sí da el formato B es color: 16 colores exactos por mosaico en lugar de dos por fila. Y "B sustituye a A": en la FPGA de `fpga-sprites-hoja` AGI no funciona con el formato antiguo.

## 4d. Convivencia de los formatos A y B en la FPGA (estudio de fuentes, 6 de noviembre de 2026; sin diseñar ni sintetizar)

Idea del usuario: si el programa no toca el puntero, el sprite funciona como en el formato A.

- Hoy no es compatible: `POKE 2105` es a la vez el color de la fila 0 (A) y la página (B), y el motor B ignora `POKE 2106-2128`.
- Propuesta: la página pasa a `POKE 2130` (campo 29 de la tabla; 2130 ya no se usa: `2130 & 31 = 18`, `18 - 21 = 29`). Página 0 = formato A, leyendo los campos 4+fila, 12+fila y 20+fila. Página distinta de 0 = hoja. Se elige por sprite.
- Pasos: B sigue en 7; A pasa a 6 (X bajo, X alto, página, color, forma, máscara). El caso peor no cambia. Los pasos reales del caso peor siguen siendo 2 + 64 + 7*12.
- Negro opaco: en A el índice 0 es visible, así que el motor necesita saber la visibilidad aparte. `hit` y `pix` ya son salidas separadas, y con `hit` a 1 y `pix` 0 sale el color 0, como en A (a confirmar en simulación).
- Área estimada, en dos variantes: flag por slot y selector A/B en cada slot, +160 LUTs y +15 FF; o expandir A a nibbles al cargar y guardar 8 bits de visibilidad por slot, +90 LUTs y +100 FF. Referencia medida: pasar de A a B costó +131 LUTs, +119 FF y solo +5 slices. Estimación: unos 4.300 LUTs (75 %) y 93-94 % de slices.
- Cambios: `sprite_engine.v`, `SD81.v` (ventana de `POKE 2130`) y sus bancos de prueba; ROM (`*SPRPAGE`, borrar el campo 29 en el arranque y recuperar `*SPRCOL`, `*SPRPIX` y `*SPRMASK`); `DEBUGGER.cpp` y web (campo 29); SPRDBUF; emulador; manual.
- Riesgo: el campo 29 no se borra por hardware (la sombra conserva la ROM tras el reset), así que FPGA y ROM deben actualizarse juntas.
- Consecuencia: GALAXIAN, SCUMM, AGI, PONG, SPORTS, SD81TEST, MODE160 y SCROLLM funcionarían sin convertirlos.

## 4e. Mix propuesto por el usuario: B con páginas, 16 colores y máscara aparte, manteniendo A (estudio de fuentes, sin diseñar ni sintetizar)

- Página 0: formato A. Página distinta de 0: celda de 4 bpp de la hoja, índice 0 transparente, y además la máscara de `POKE 2121-2128`, los mismos campos 20-27 de A, con 1 = visible. La máscara solo recorta; la forma la sigue dando el índice 0, así que en B solo se escribe al recortar.
- Pasos: B pasa de 7 a 8; A sigue en 6. Caso peor, +12 pasos. Sigue por debajo de `limit` según las notas (80 columnas: ~175 hoy, ~187 con esto, límite 195), pero queda solo un margen de ~8 pasos: hay que comprobarlo con `tb_sprite_engine` en modo `worst`.
- Máscara por defecto: la ROM sigue borrándola a 0 en el arranque, sin cambios. Aclaración del usuario: no hay programas para B, así que la regla es la misma que en A: todo programa B escribe la máscara de sus sprites al iniciarse (SPRDBUF, que es una prueba, necesitaría esa línea).
- Área estimada: unos +110 LUTs y +110 FF sobre el formato B actual, es decir, unos +15 LUTs más que la convivencia sin máscara (4.280 LUTs, 75 %; 93-94 % de slices).
- AGI con el mix (modelo sobre el registro de `spr_put`): SQ2 2.278 T frente a 3.208 de HEAD (0,71 veces), con búsqueda de 200 T; KQ2 1,57 veces y PQ1 1,23 veces, porque casi todas sus llamadas son fallos de caché en registros cortos (40 de 44 y 39 de 59). Falta medirlo con la caché ya llena.
- Se aprovecha la rotación de la etapa 1; `hw_cell` desaparece y hacen falta la etapa 2 y el gestor de caché. Siguen el magenta claro perdido en sprites y el riesgo de los `.SPR` (hasta 19 de 1.992 ficheros).

## 4f. Sin índice 0 transparente (7 de noviembre de 2026; sin diseñar ni sintetizar)

Observación del usuario: con máscara, el índice 0 transparente es redundante. Sin él sobran la rotación y la pérdida del magenta claro, y hay negro opaco en todos los modos sin reprogramar `pal16`. Esto corrige la sección 4e: la rotación de la etapa 1 tampoco se aprovecharía.

- Solo máscara (`visible = máscara`): lo más simple en hardware, pero la forma pasa a la máscara, que está en la tabla de cada sprite: hay que escribir 8 B en cada cambio de mosaico. Además habría que guardar 8 B más por mosaico en los `.SPR`. En GALAXIAN un aleteo costaría unos 14.700 T en lugar de 4.900, y `POKE 2129` ya no animaría todos los sprites si cambia la forma.
- Color transparente por sprite (`visible = máscara Y nibble != transparente`): el nibble alto de `POKE 2103` da el índice transparente. El motor ya lee ese byte y solo usa el bit 0 (`lx_h <= v_dout[0]`), así que no añade pasos, y al ser 0 por defecto el índice 0 sigue siendo el transparente. AGI ya tiene un color transparente por celda (`tm & 15`), que por construcción no aparece entre los píxeles visibles: siempre hay índice libre.
- Modelo en T por render, con búsqueda de 200 T (HEAD: SQ2 3.208, KQ2 2.464, PQ1 3.633): índice 0, 2.278 / 3.875 / 4.460; solo máscara, 2.947 / 4.622 / 5.342; color transparente, 2.533 / 4.053 / 4.680. Son registros cortos, con la caché en frío en KQ2 y PQ1.
- Área estimada: unos +120 LUTs con color transparente y unos +100 con solo máscara, sobre el B actual. `DEBUGGER.cpp` debe guardar el byte entero de `POKE 2103` (hoy `f[2] & 1`).

## 4g. Decisión y estado (7 de noviembre de 2026)

Decisión del usuario: AGI vuelve al formato A y la FPGA se restaura al commit anterior a B para añadir ahí el modo nuevo. La etapa 1 queda descartada (parche en el scratchpad de la sesión, `etapa1/etapa1.diff`). Esta rama vuelve a ser HEAD: `GFX4=0` idéntico, `dump/runall.sh` 5 OK, `test_gfx4.sh` igual que antes.

FPGA, sin commit, en la copia de trabajo de SD81-Booster (rama `fpga-sprites-hoja`): `sprite_engine.v`, `SD81.v` y los bancos de prueba. `mode160.v` y los sprites en 8 bpp se recuperaron de 3a7c997 a petición del usuario.

- Regla implementada: `POKE 2130` = página (campo 29), 0 = formato A. En B, celda de 4 bpp, máscara de `POKE 2121-2128` y color transparente en el nibble alto de `POKE 2103` (elegido por Claude, pendiente de confirmar). Pasos: 6 en A, 8 en B.
- Los slots guardan 8 píxeles resueltos (32 bits de color y 8 de visible). Sin color (`color_on` a 0) el formato A se carga con `F0`, y el bit 0 del color es el bit de píxel.
- Síntesis (XST+MAP+PAR, en una copia de la VM): 4.422 LUTs (77 %), 2.867 registros, 1.374 slices (96 %), temporización cumplida. Frente a master: +385 LUTs, +260 registros, +54 slices. La estimación de 4f se quedó corta.
- Simulación: `tb_sprite_engine` pasa en 32 y 80 columnas con A, B y mezcla, densos, caso peor y monocromo (A contra `sprite_slot`). `tb_mode160_spr` pasa en 4 y 8 bpp. En 80 columnas el caso peor de B necesita `limit` >= 185-187 (falla con 184): hay 8-10 de margen sobre 195.
- ROM, firmware, web y SPRDBUF actualizados el 7 de noviembre de 2026, sin commit. La ROM solo cambia después del salto al bloque 1: el bloque 0 sale idéntico byte a byte al de la ROM anterior (comprobado con `cmp` sobre los dos ensamblados). `SprClear` borra la página con el mismo tamaño que antes (sobraba el último `ld (2100),a`, porque el último sprite del bucle ya es el 0) y `*SPRCOL`, `*SPRPIX` y `*SPRMASK` van detrás de `SD81RUNCMD`, para no mover ninguna dirección a la que apunte el bloque 0. La ROM pasa de `$2FE1` a `$304D`: cruza `$3000`, y lo último de la lista de comandos y el mensaje de error quedan por encima.
- Snapshots: línea nueva `SPRITE_PAGE n página transparente`, solo si no son 0. `SPRITE` no cambia, y los snapshots antiguos cargan en formato A.
- Regresiones aceptadas por el usuario (7 de noviembre de 2026): con ROM alternativas (teclas 0-9 o `.ROM`) la pagina no se limpia y un programa con sprites debe hacer `POKE 2130,0`; las capturas de la web con sprites leen hasta 8 KB mas de la hoja aunque el programa solo use formato A.
- Probado en placa el 7 de noviembre de 2026: el usuario confirma que funciona (FPGA, ROM y SPRDBUF de `build/sprites-mix`). `DEBUGGER.cpp` y la web siguen sin compilar.
- Antes de esa prueba: ni la ROM ni `sprdbuf.bin` se habían ejecutado. SPRDBUF tiene una fila nueva (Y=130) con A, B, máscara y color transparente en la misma línea.
- Falta: probar en placa (`.mcs`, ROM y SPRDBUF en `build/sprites-mix`), emulador (otra sesión), manual y ayuda en línea (`claude/planning/manual_pendiente.md`).

## 4h. Número de sprites variable, solo formato B (propuesta del 7 de noviembre de 2026; sin diseñar del todo, sin sintetizar)

Tiempo medido en simulación, caso peor de 12 sprites B: en 32 columnas hace falta `limit` 114 (hay 120) y en 80 columnas 187 (hay 195). Quedan unos 12 pasos y 8 pasos. Presupuesto: 2 + N + 8 × K ≤ unos 174 (32 columnas) o 170 (80 columnas). El barrido acaba antes si se llenan los 12 slots, así que el caso peor solo se da si los sprites de la línea tienen índice bajo.

- Bajar de 64 no ahorra RAM del Z80 (las tablas están en la sombra de ROM) ni mejora nada con K = 12, porque 64 ya caben.
- Subir: con 12 B por línea caben unos 76 en 32 columnas y 72 en 80; con 8 B por línea, unos 108. Al pasarse se pierden sprites en las líneas más densas, sin más efecto.
- Propuesta: `POKE 2131` = M sprites extra (0 = como ahora; registro de la FPGA, se borra con el reset, no hace falta ROM). Son solo B y viven en la hoja, 16 bytes cada uno desde la página 0, usando `fld[3:0]` como desplazamiento: 1 X bajo, 2 X alto y transparente, 3 Y, 4-11 máscara, 13 página. Ninguna ventana de POKEs: el Z80 los escribe como RAM. Sin bit de activo: Y=0 los deja fuera. Se barren después del sprite 0 (la prioridad más baja).
- Cambio del mismo día: el usuario creía que los sprites A seguían en memoria distribuida; como están en la BRAM, los extra pasan a ser de los dos formatos. Cada uno usa una entrada de 32 bytes con los mismos campos que la tabla normal, en `{bloque, página, campo}`, con la página igual a su número: gasta una celda de la hoja. Con página 0 en su campo 29 es A, y con otra, B. Esto sustituye a la entrada de 16 bytes descrita arriba. Con 32 bytes: 4.450 LUTs (+28), 2.866 registros, 1.392 slices (97 %), temporización cumplida. Los slices variaron entre 1.347 y 1.392 con cambios casi iguales: es ruido del emplazamiento, y el margen real está cerca del límite. Sin simular. Por línea (calculado): 32 extra, 9 B o 12 A; 64 extra, 5 B o 6-7 A.
- Coste medido el 7 de noviembre de 2026 en una copia de la VM (`~/campExtra`, sin tocar el repositorio): 4.449 LUTs (+27), 2.867 registros (igual), 1.347 slices (94 %) frente a 1.374, temporización cumplida. La bajada de slices es efecto del emplazamiento, no un ahorro. Registro de 7 bits (`POKE 2131`), hasta 127 extra. Solo se ha sintetizado: el funcionamiento de los sprites extra no se ha simulado.

### Implementado (7 de noviembre de 2026, sin commit)

- Motor y `SD81.v` en el repositorio, con las entradas de 32 bytes. La simulación encontró un fallo de la copia medida: `scan_end` es una igualdad y, tras cargar un sprite, el barrido se la saltaba y seguía leyendo detrás del último extra. Corregido: la carga vuelve a reposo si ya no quedan sprites.
- `tb_sprite_engine` con `+extra=M` (franjas con lo que garantiza el tiempo, y caso peor con los últimos extra) y `+kb=N`. El caso peor confirma el cálculo: con 64 extra caben 5 B en 32 columnas y con 6 falla.
- Firmware (`SPRITE_EXTRA` en snapshots, byte 22 de la captura) y web (dibuja los extra con su prioridad; no reproduce el límite de tiempo). Sin compilar.
- SPRDBUF: tres extra en Y=116 (A, B y B con color transparente).
- Simulación completa (7 de noviembre de 2026): `tb_sprite_engine.sh` pasa todo en 32 y 80 columnas, con y sin extra, y `tb_mode160_spr` en 4 y 8 bpp. Los casos peores confirman lo garantizado con 64 extra: 5 B en las dos anchuras, 7 A en 32 columnas y 6 A en 80 (con uno más fallan). Un fallo en 80 columnas con extra A era del banco (comparaba antes de que el motor acabara de cargar), no del motor.
- Síntesis en el repositorio: 4.436 LUTs, 2.860 registros, 1.379 slices (96 %), temporización cumplida. `.mcs` estampado en `build/sprites-mix`.
- Placa: SPRDBUF con los extra funciona (usuario, 7 de noviembre). La pelota que desaparecía a ratos con la versión anterior ya no lo hace; no se sabe la causa.
- `EXAMPLES/SPRXTRA`: prueba de 4 bpp (arco iris de 15 colores animado) y de más de 64 sprites (64 normales y hasta 64 extra; la tecla E cambia M). Comprobado en el PC con el Z80 de EightyOne (`scratchpad`, arnés propio) y con el motor simulado sobre sus tablas: con 64 extra se ven 6 de las 12 bolas de la fila de abajo. Funciona en placa (usuario, 7 de noviembre).
- SPRXTRA pasado al modo 160x100 (7 de noviembre, a petición del usuario): pone el modo 175, carga `FONDO.JPG` con el comando 76 (recortada; si no está, fondo negro) y reparte las 128 bolas en 12 franjas (12 normales por franja; luego extra 0-48 en franjas de 8, 11, 9, 8, 7 y 6; extra 49-63 quietos abajo). Arnés con MCU simulado (con fondo, sin él, sin convertir y con cabecera mala) y motor RTL a 80 columnas: la carga por franja coincide con el modelo para 0, 32, 48 y 64 extra (abajo se ven 6 de 15). Sin probar en placa.

## 5. Emulador

EightyOne no emula los sprites nuevos hasta que la sesión del emulador (rama `sprites-hoja` del repo Eightyone2) los tenga; la verificación en PC es el arnés Python/Z80 y la final es la placa.
