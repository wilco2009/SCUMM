# Estudio: AGI v2 en un modo 160x168 (o 160x200) con 4 bpp reales

Fecha: 2026-11-01. Solo lectura: no se ha tocado ENGINE, FPGA ni nada compilable. (El informe va en `SCUMM/AGI/` porque `SCUMM/AGI/V2/AGI/` no existe.)
Fuentes: `V2/ENGINE/*.asm` (agivm, agipic, agispr, agicel, agisw, agihws), `V2/PLAN.md`, `FPGA/SD81V2.1000/mode160.v`, `EXAMPLES/MODE160`,
`claude/planning/modos_160_sprites_mixto.md` (28/10: ya trae el presupuesto de LUTs de este mismo modo) y la memoria del proyecto.
Las cifras de T-estados son **contadas a ojo sobre el código** (no medidas en placa); se dan para comparar, no como garantía. Reloj del Z80: 3,25 MHz.

## 0. Veredicto

**Viable, y lo más fiel que se puede hacer, pero no es barato en FPGA y el texto es el problema real.**
- La imagen a 4 bpp es **más simple** que la de ahora: el conversor (`agi2hr.py`) deja de cuantificar, desaparece el choque de atributos (hoy 1,5-2,0 % de píxeles cambiados, peor caso 3,6-5,5 %) y el código Z80 de `plot`/composición se simplifica mucho.
- Cabe en memoria igual que hoy (mismos 2 bloques de vídeo, mismas 2 páginas de fondo limpio).
- Lo caro es el hardware: modo 4 bpp + sprites en ese modo + texto de 40 columnas. Juntos: **~200-270 LUTs, slices del 88 % al ~93-95 %**, justo en la zona donde cuesta cerrar los 208 MHz del PDM.
- Recomendación: **no abordar todo a la vez**. Fase 0 en PC (medir), fase 1 FPGA mínima (solo 4 bpp 160x200, ~30-40 LUTs) con imagen + sprites software y texto de 4 px por software, y decidir el plano de texto y los sprites hardware con datos.

## 1. Memoria

### Hoy (8x1)
- Vídeo: bitmap `$A000` (5.376 B = 168x32) + atributos `$C000` (5.376 B), con la fila 0 de estado desplazada 8 líneas. Ocupa los bloques 5 y 6.
- Fondo limpio (para restaurar rótulos por software): páginas 31 (`PG_BGB`) y 32 (`PG_BGA`). Prioridad RLE para `can_be_here`: página 29; prioridad de sprites RLE: 30; máximos por bloques de 8 px (168x20 = 3.360 B): 43.
- Fichero `PICnnn.GFX` ≈ 13,5 KB (5.376 + 5.376 + RLE ~2,6 KB), más el plano de máximos.
- Páginas usadas: 16-23 (lógicas), 24-28 (vistas, palabras, sonido, eventos, depurador), 29-32, 33-40 (caché de bucles de sprites), 41-49 (overlays, inventario, guardar). Si la RAM es de 512 KB (64 páginas de 8 KB) quedan **50-63 libres** (a confirmar en `agivm.asm`; no lo he podido verificar).
- Núcleo: 10.989/11.008 B; overlay A1 5,8 KB, A2 3 KB, B 8.188/8.192. **Esto no cambia con 4 bpp** salvo por lo que se quite o añada (ver §2).

### Con 4 bpp
| Concepto | Bytes | Comentario |
|---|---|---|
| Pantalla visible 160x168 a 4 bpp | **13.440** (80 B/línea) | 2 bloques (16.384): sobran 2.944 B. En `$A000-$D47F` sigue donde está hoy (bloques 5-6; `HFILE` es parámetro en `mode160.v`). |
| Marco completo 160x200 | 16.000 | 2 bloques, 384 B de sobra. Las 32 líneas de texto (estado + 3 filas inferiores) se pintarían en el propio mapa. |
| Fondo limpio | 13.440 | 2 páginas (`PG_BGB`/`PG_BGA`): **mismo nº de páginas** que hoy. |
| Prioridad | RLE (igual) 2×~2,6 KB, o 1 B/píxel = 26.880 (4 páginas), o nibbles = 13.440 (2 páginas) | Dejarla RLE y decodificar por filas es lo que hay; el plano plano solo compensa si se quiere quitar `pd_row` (ver §2). |
| Fichero `PICnnn.GFX` | ~19,5 KB (13.440 + 2×2,6 + 3.360) | 451 imágenes: ~8,7 MB frente a ~6 MB. Cabe de sobra en SD; la lectura sube ~25 % (§2). |
| Plano de texto (opción a) | 1.000 códigos + 1.000 atributos + fuente 768 B = **2.768** | Cabe en los 2.944 B sobrantes de los 2 bloques si el marco es de 168 líneas (176 B de margen). Con marco de 200 líneas habría que sacarlo a otro bloque. |

Conclusión: **la memoria no es un obstáculo**. El único coste nuevo es de disco y de páginas de prioridad, si se decide ampliarla.
**El doble buffer de placa solo copia un bloque de 8 KB** (BRAM 32/32), así que con 13.440 B **no hay doble buffer**. Hoy sí se usa (`POKE 2057,168+4`): se perdería, y el dibujo por software dejaría de ser "atómico" por trama (ver §2.4).

## 2. Rendimiento (Z80)

### 2.1 Un dato importante: el Z80 no dibuja vectores
`h_draw_pic` (`agipic.asm`) **no ejecuta las órdenes F0-FA de AGI**: lee `PICnnn.GFX`, ya rasterizado por `agi2hr.py` en el PC, con `f_read_n` directamente a `$A000`/`$C000`. Por tanto **no existe hoy un coste de plot/línea/relleno de `agipic` que comparar**; el pase a 4 bpp solo cambia el *tamaño* de la lectura y quita trabajo al conversor. (Si en el futuro se quisiera dibujar vectores en el Z80, un relleno 4 bpp con nibbles costaría del orden de 60-90 T por píxel relleno; no se propone.)

| Operación | Hoy (8x1) | 4 bpp | Notas |
|---|---|---|---|
| Carga de imagen (lectura SD → RAM) | 2×5.376 = 10.752 B + prioridad | 13.440 B + prioridad (+25 %) | Si `f_read_n` cuesta ~21 T/B, +56k T ≈ +17 ms por `draw.pic`. Poco frente a la latencia de SD. Ver riesgo: tiempo de lectura de SD aún sin medir en placa (PLAN). |
| Copiar fondo limpio → pantalla (LDIR) | 10.752 B ≈ 226k T ≈ 70 ms | 13.440 B ≈ 282k T ≈ 87 ms | Casi 1:1, +25 %. |
| `plot` de un píxel (`agispr.asm:205`) | ~45-60 instrucciones ≈ **400-600 T** (máscara, 2 atributos, 3 ramas de color) | RMW de nibble ≈ **35-45 T** (par/impar desenrollado) | **x10-x12 más rápido**; desaparece la lógica de papel/tinta. |
| Máscara de prioridad por 8 px (`hg_okb`, `agicel.asm:94`) | ~215 T/píxel (calcula `(5*x)>>3`) ≈ **1.7k T por mosaico** | 1:1 → `PROW[x]` directo ≈ 45 T/píxel ≈ **360 T** | x5; además `pmax` por bloques de 8 px de AGI pasa a ser 1 bloque = 1 mosaico. |
| `pd_row` (decodifica una fila RLE a `PROW`) | ~26 T/px × 160 + sobrecarga ≈ 4,5k T | igual (160 px AGI) | Sin cambio con RLE. Con plano plano no hay decodificación, a costa de 2 páginas más y de expandir al cargar la sala (~700k T ≈ 215 ms) o leer 26.880 B del disco. |
| Texto: glifo 6x8 | por celdas 8x1, con atributos | ~8 filas × ~150 T ≈ **1.2k T/carácter** (tabla de 4 entradas por pareja de colores) | Ver §3. |

### 2.2 Sprites hardware (si se llevan al modo)
- El motor (`sprite_engine.v`) es independiente del modo; solo necesita `pos_x`, `pos_y` y entra el color por `c4` → `pal16` (planning §3). Quedaría **2 colores por fila de 8**, como ahora, pero ya sin ruido de atributos del fondo.
- El mosaico de 8 px nativos son 8 píxeles AGI (hoy ~5): **−37 % de mosaicos por objeto** y el umbral `SW_TILES = 6` pasa a ser 48 px AGI (~77 px HiRes de hoy). Menos objetos caen al camino software y menos presión sobre el límite de 12 por línea y los 64 sprites.
- El rótulo de 23 mosaicos de SQ1 pasaría a ~15: sigue necesitando camino software (>12 por línea).
- Pérdida a medir: objetos con >2 colores por fila de 8 siguen cuantificando. Hoy esa pérdida existe también (`agi2spr`: 2 más frecuentes por fila); **no hay cifra medida** para 1:1 (§7, fase 0).

### 2.3 Sprites por software con máscara de prioridad (el "método original")
Es lo que hace ScummVM y lo que el PLAN descartó en la etapa 7 (aparte de por el ruido de atributos, que aquí desaparece). Estimación para un objeto típico de ~10x25 px AGI (250 px):

| Paso | T-estados (aprox.) |
|---|---|
| Guardar fondo (≈ 6-7 B/fila × 27 filas, LDIR) | ~5k |
| Pintar con prioridad (≈ 50-70 T/píxel con RLE de vista, pares de píxeles cuando se puede) | ~12-18k |
| Restaurar fondo anterior | ~5k |
| **Total por objeto que se mueve** | **~22-28k T ≈ 7-9 ms** |

A 10 ciclos/s (`v10 = 2` → 100 ms/ciclo, que ya consume el intérprete: SQ1 sala 2 ≈ 34.000 instrucciones/ciclo según el PLAN), 3-4 objetos móviles ya ocupan un 30 % de presupuesto, y las salas con 10+ objetos se irían a 200 ms. **El camino software es posible pero es un retroceso de rendimiento frente al hardware**, y sin doble buffer se ve el barrido. Sirve como fallback para rótulos anchos (donde ya se usa), no como camino general.

### 2.4 Redibujado y guardar/restaurar
- Guardar/restaurar partida no cambia (no se guardan píxeles).
- Restaurar el área bajo un cuadro de diálogo o menú: hoy `OVB_CLRRECT` copia del fondo limpio por celdas 8x1 (bitmap + atributos = 2 LDIR por fila); con 4 bpp es **1 LDIR por fila** (ancho/2 bytes). Mitad de pasadas, el mismo orden de coste total por píxel.
- Con un plano de texto (§3a) no hay nada que restaurar: se borran celdas.

### 2.5 Gráficos que no son sprites (estimación, T a 3,25 MHz, sin medir)

| Operación | Hoy (8x1) | 4 bpp | Comentario |
|---|---|---|---|
| `draw.pic` completo: lectura SD (visual + 2 prioridades + máximos) | ~10.752 + 5.200 + 3.360 ≈ 19,3 KB ≈ 405k T ≈ 125 ms | ~13.440 + 5.200 + 3.360 ≈ 22 KB ≈ 460k T ≈ 142 ms | +14 %. La lectura es lo que más pesa; el RLE de prioridad no cambia. |
| `draw.pic`: copia a fondo limpio (`OVE_BGSAVE`, LDIR) | 10.752 B ≈ 226k T ≈ 70 ms | 13.440 B ≈ 282k T ≈ 87 ms | +25 %. Se puede evitar leyendo del SD a las páginas de fondo y copiando una sola vez a pantalla (mismo LDIR), o dejando el fondo en la propia pantalla si no hay rótulos software. |
| `pri_index` (160 px × 168 filas de RLE) | ~100-150k T | igual | No cambia. |
| **`draw.pic` total** | **~200 ms** | **~230-240 ms** | Se nota solo al cambiar de sala o redibujar; en una sala con 48 `add.to.pic` recordados se suma lo siguiente. |
| `add.to.pic` (objeto fijo, ~250 px) | pasa por el camino software de 8x1: `plot` ≈ 500 T/píxel en celdas parciales, en pantalla y en fondo limpio, más prioridad → del orden de **100k T ≈ 30 ms** | blit nibble ≈ 60 T/px × 250 ≈ 15k T en pantalla + 15k en fondo + escritura de prioridad ≈ 8k → **~40k T ≈ 12 ms** | Mejora ~2,5x. Peor caso al rehacer la sala: 48 recordados ≈ 0,6 s con 4 bpp frente a ~1,5 s. |
| Rótulo ancho por software (`agisw`, compone por líneas) | por línea: armar buffer 32 B + 32 B de atributos, componer celdas, `plot` en bordes | buffer de 80 B, copia de fondo con LDIR + OR/AND de nibbles, sin atributos | Menos código (el overlay A2 de 3 KB ganaría margen) y ~2-3x menos T por línea; sigue siendo ~60 T/px. |
| Rellenar rectángulo (ventana `print`, `clear.lines`, `OVB_CLRRECT`) | LDIR por fila en bitmap y en atributos (2 pasadas) | 1 pasada: w/2 B por fila | Ventana de 30x6 caracteres en 120x48 px: 48 filas × 60 B ≈ 61k T ≈ 19 ms; hoy ≈ 2 pasadas ≈ 38 ms. |
| Restaurar bajo una ventana al cerrarla | LDIR del fondo limpio, bitmap + atributos | LDIR del fondo limpio, 1 pasada | Igual de simple, mitad de coste; con plano de texto (a) → 0. |
| Pantalla negra / `show.pic` | 10.752 B | 13.440 B | +25 %. |
| Texto con `display`/`print` sobre la imagen | glifo 6x8 por celdas | ~1,2k T/carácter (§2.1) | 40 caracteres ≈ 48k T ≈ 15 ms. |
| `shake.screen` | desplazamiento de vídeo | idem si se usa el registro de posición `POKE 2099` (hoy en `mode160` es de 1/3 de píxel); sin él habría que copiar la pantalla | A confirmar; no lo he leído en el código. |

Resumen: lo que **solo se pinta una vez al cambiar de sala** (`draw.pic`) sube ~15-20 %; lo que **se repite por ciclo** (sprites, rótulos) y los rectángulos/`plot` mejoran 2-10x porque desaparece la lógica de atributos. Ninguna operación no sprite empeora de forma que importe salvo la carga de SD (sin medir en placa).

## 3. Texto, menú, barra de estado y mensajes (40 columnas)

Lo que AGI pide: rejilla 40x25 de celdas 8x8 sobre 320x200; barra de estado en la fila 0, imagen en las filas 1-21 (líneas 8-175), línea de entrada y mensajes en las 3 filas inferiores; ventanas `print` y menús **superpuestos a la imagen**, con fondo opaco; el ancho de línea de `print` ronda los 30 caracteres.
Observación útil: en el modo 160 la ventana de vídeo es de 480 ciclos de 13 MHz = **40 celdas de 12 ciclos = 4 px AGI cada una**, con lo que 40 columnas encajan exactamente (es el "celda de 12 ciclos" del planning).

| Opción | Cabe | Coste FPGA | Fidelidad | Riesgo |
|---|---|---|---|---|
| **(a) Plano de caracteres 40x25 en FPGA con transparencia** | sí: 2.000 B + fuente 768 B en el sobrante de los 2 bloques | **100-150 LUTs** (generador nuevo) o 50-80 si se reutiliza el texto superfast de 80 columnas (no leído a fondo; tiene muchas compensaciones calibradas en placa) + mux con el bitmap | La mejor: 40 columnas, ventanas opacas por celda, no hay que guardar/restaurar la imagen bajo ellas, `clear.lines` = borrar celdas. Glifo 6x8 a 2 ciclos/píxel (240 px = 40 celdas). | Slices → 93-95 %. Hay que decidir una máscara de "celda activa" en el atributo. La transparencia es de **celda entera** (suficiente: AGI no mezcla texto a medio píxel). |
| **(b) Caracteres de ancho doble sobre 160 px (20 columnas)** | no | 0 | **Descartada.** AGI formatea mensajes a ~30 columnas; 20 columnas rompen los textos, los menús y las 40 columnas de la barra. Variante realista: **(b') glifo de 4x8 en el propio bitmap** (3 px + 1 de separación, 40 columnas): 0 LUTs, pero ilegible en una TV a 230 ns/píxel con letras de 3 px y caracteres como `m`, `w`, `%` en mal estado. | Solo como prototipo. |
| **(c) Conmutar a modo de texto/320x1bpp al abrir menús o mensajes** | memoria sí (el bitmap no se toca; el texto va en otro bloque) | 0 si se usa el texto existente (80 col o HiRes de 1 bpp con atributos); el modo "320x1 bpp" pedido **no existe** hoy | Solo vale para pantallas a pantalla completa (inventario, ayuda, listas de guardar/cargar, `show.mem`). **No vale para** barra de estado, línea de entrada ni `print` sobre la imagen (1.316 llamadas solo en SQ1): ahí hay que ver la imagen detrás. Una conmutación por línea (mixto) es exactamente la opción 5.1 del planning, con la misma complejidad que (a). | La conmutación debe hacerse en la VSYNC y mantener el bitmap intacto. |

**Recomendación de texto:** empezar con **(b')+(c)**: barra de estado, línea de entrada y mensajes pintados por el Z80 en el bitmap con una fuente 4x8 (o 5x8 en ventanas, 30 columnas = 150 px) y las pantallas completas por conmutación; si el aspecto en la placa no vale, el siguiente paso es **(a)**.
El software de texto que hay en `agib.asm`/`agitx.inc` (42 columnas, `font6.inc` 6x8) hay que rehacerlo para 4 bpp en cualquier caso, pero es más corto que ahora (`plot` pasa de ~500 T a ~40 T).

## 4. FPGA

### 4.1 Estado base (rama `fpga-mode160`, sin commitear)
LUTs 3.889/5.720 (**67 %**), slices 1.272/1.430 (**88 %**), BRAM **32/32**, todas las restricciones cumplidas (208 MHz con ~1,3 ns de margen). `mode160.v` (234 líneas): 160x100 a 8 bpp, 16.000 B, paleta de 256 con PDM, paleta de 16 (`pal16`) para los demás modos y los sprites.

### 4.2 Qué hace falta y cuánto cuesta (estimaciones del planning del 28/10, más las mías)
| Pieza | LUTs |
|---|---|
| 160x200 (direccionar con 8 bits de fila en vez de repetir 2 líneas) | 5-10 |
| 4 bpp (desempaquetar nibble → índice de `pal16`) | 20-30 |
| Sprites en `mode160` (`c4` → `pal16`, `pcnt` como `pos_x`) | 30-60 |
| Plano de texto (a) | 50-150 (más ~20 de mezcla) |
| **Total sin texto** | **55-100** |
| **Total con texto** | **~130-270** |

- Slices: 88 % → ~91 % sin texto; ~93-95 % con texto. El planning ya advierte que por encima del 93-95 % cuesta cerrar los caminos de 208 MHz. Candidatos para liberar sitio (sin medir): la paleta de 256 entradas (~128 LUTs, solo si 4 bpp sustituyera al 8 bpp), bajar de K=12 a 8 slots de sprites, compartir lógica de scroll/sprites/depurador.
- BRAM: no hay margen (32/32). Todo cabe en los bloques de sombra ya existentes (§1). No hace falta ninguna BRAM nueva.
- Temporización: el reloj de píxel no cambia (13 MHz, 3 ciclos por píxel, 480 por ventana). El texto a 2 ciclos/píxel (celda de 12) reutiliza la temporización; el mismo patrón que el 80 columnas.
- Sin blit/doble buffer en este modo (un solo bloque de 8 KB).

### 4.3 Qué hardware existente se reutiliza
- **Sprites (64, K=12, 8x8, 2 colores por fila)**: el motor es independiente del modo; solo cambia la conexión de posición y color en `SD81.v` (`spr_in_display` está atado a 256x192 y a los offsets calibrados `SPR_*_FUDGE`).
- **Paleta de 16 colores (`pal16`)**: es justo el formato de color de AGI (EGA); basta cargar los 16 colores EGA una vez. El 4 bpp indexa `pal16` directamente.
- **Scroll por hardware**: AGI no usa scroll; no se aprovecha.
- **PDM/paleta de 256**: no hace falta (se podría dar de baja si faltase espacio).

## 5. Fidelidad: qué se gana y qué se pierde

| Aspecto | HiRes 8x1 hoy | 160x168 a 4 bpp |
|---|---|---|
| Colores de la imagen | 2 por celda 8x1; 1,5-2,0 % de píxeles cambiados de media (3,6-5,5 % peor caso, medido en 451 imágenes, geometría C) | 16 por píxel, **0 %** |
| Geometría | estirado ×1,6 (reparto 2,2,1,2,2): píxeles de ancho irregular; proporción 1,52 | píxel AGI = píxel de pantalla; proporción de la ventana ≈ 36,9 µs frente a ~39,4 µs de HiRes (6 % más estrecho) |
| Colores exactos | 16 digitales de Chroma81 o `pal16` | `pal16` configurable: se pueden poner los EGA tal cual (con la limitación de la red de resistencias de la SCART: solo colores con (max−min) ≤ 0,455 V) |
| Sprites | HW con atributos pisados por el fondo (hoy resuelto con 2 colores por fila) | HW igual de limitado (2 colores por fila), sin ruido; o software con 16 colores por píxel a costa de CPU |
| Prioridad frente al fondo | máscara por píxel con `(5*x)>>3` | máscara 1:1, más simple y rápida |
| Texto | 42 columnas, fuente 6x8 | 40 columnas exactas con plano de texto (a); con (b') 4x8 más ilegible |
| Doble buffer | sí (1 bloque, `POKE 2057,168+4`) | **no** (13.440 B > 8 KB) |
| Scroll | no se usa | irrelevante |
| Estabilidad | HiRes y atributos probados | `mode160` probado en placa, pero sin 4 bpp, sin 160x200, sin sprites |

## 6. Riesgos
1. **Slices 93-95 %** si se hace el plano de texto + sprites: puede no cerrar temporización a 208 MHz.
2. **Sin doble buffer**: el dibujo por software se ve (tearing). Para los sprites HW no importa; para rótulos software y texto sí.
3. **Texto**: la opción sin FPGA (4x8) puede ser ilegible; (a) es lo que cuesta.
4. **Los sprites en `mode160` y la calibración de posición** son trabajo de placa (`SPR_*_FUDGE`), sin emulador (EightyOne no tiene el modo).
5. **Núcleo y overlays al límite** (11.008, A1 5,8, B 8.188/8.192): el cambio toca `agipic`, `agispr`, `agihws`, `agisw`, `agib` y `agitx`; partir overlays y mover código al nucleo está en cola desde antes.
6. **Disco**: ficheros PIC +45 %; lectura de SD aún sin medir.
7. **Paridad con el modelo en Python** (`agi_vm.py`, `cmp_vm.py`): todas las pruebas de equivalencia comparan pantalla/sprites; habría que rehacerlas para 4 bpp.
8. **Ruido PDM** (ya anotado en la rama): los pasos entre colores EGA hay que verificar en la placa.

## 7. Prototipo barato (sin gastar LUTs para pruebas)

0. **PC, sin FPGA** (1-2 días): ampliar `medir8x1.py`/`agi2spr.py` con (i) la imagen nativa 160x168 → verificar 0 % de cambio y generar `PICnnn.GFX` de 4 bpp; (ii) % de píxeles de sprites que se pierden con 2 colores por fila de 8 px **nativos** (hoy sin cifra); (iii) nº de mosaicos por objeto y cuántos objetos pasan de `SW_TILES` en 160. Con esto se decide si los sprites hardware valen.
1. **FPGA mínima**: 160x200 + 4 bpp en `mode160.v` (≈ 30-40 LUTs, ~+2 % slices) y un programa de prueba tipo `EXAMPLES/MODE160` que cargue 3-4 imágenes de SQ1/KQ2 convertidas, con la paleta EGA en `pal16`. Medir: colores en la TV, tiempo de lectura de SD y copia a pantalla.
2. **Sin tocar más la FPGA**: en ese programa, probar el objeto ego como **sprite por software** (guardar/pintar/restaurar con prioridad desde un `PROW` plano) para tener la cifra real de ms/objeto; es la medida que falta para elegir entre hardware y software.
3. Solo si 0 y 2 salen bien: **sprites en `mode160`** (30-60 LUTs) y luego el plano de texto (a) empezando por la versión que reutiliza el texto superfast.
4. Al integrar en el intérprete, hacerlo detrás de una constante de compilación (`GFX4=1`) para no perder el HiRes 8x1 (regla "sin regresiones").

## 8. Recomendación

**Sí, es viable y mejora claramente la fidelidad (la imagen, que es lo más visible).** Hacerlo por fases y sin comprometer el plano de texto hasta tener datos: fase 0 en PC, fase 1 FPGA mínima (solo 4 bpp 160x200), texto por software de 4 px y pantallas completas por conmutación, y decidir con medidas si los sprites siguen siendo hardware (lo esperable: sí, con mosaicos de 8 px nativos) y si hace falta el plano de texto. **No** recomiendo la opción (b) de 20 columnas. Lo que no se puede dar por hecho es que todo junto entre en la FPGA: el límite real es el empaquetado de slices, no las LUTs.
