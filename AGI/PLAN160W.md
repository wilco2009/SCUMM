# PLAN160W: AGI v2 en el modo 160x200 a 4 bpp ("160w") — rama `agi-mode160w`

Fecha: 2026-11-01. Base: `ESTUDIO_160x168.md`. Regla: todo detras de `GFX4` (constante de compilacion en ENGINE, flag `--gfx4` / `AGI_GFX4=1` en Python);
con `GFX4=0` el binario y la bateria (`dump/runall.sh`, "OKs 5 DIFs 0") han de salir **identicos** a master.

## 1. Lo que hay (leido en el codigo)

- `h_draw_pic` (agipic.asm) no dibuja vectores: lee `PICnnn.GFX` (ya rasterizado por `agi2hr.py`): bitmap 5376 B -> `$A000+256`, atributos -> `$C000+256`
  (la fila de estado ocupa las 8 primeras lineas), prioridad RLE (pag. 29 y 30) + maximos por bloques de 8 px AGI (pag. 43). Luego `OVE_BGSAVE` (A2/E) copia a las pag. 31/32 (fondo limpio).
- Sprites: 64 por hardware (agihws/agicel, overlay A1, tablas de `agi2spr.py`, mosaicos 8x8 sobre 256 px HiRes con estirado x1,6 `lo(x)`, mascara de prioridad `(5*x)>>3`);
  celdas anchas (> `SW_TILES`) y `add.to.pic` van por software (agisw.asm, overlay E/A2: compone por lineas con bufer LBBM/LBAT sobre PG_BGB/PG_BGA, regla de 2 colores por celda con `plot`).
- Texto: `agitx.inc` (incluido en B y F) escribe glifos 6x8 pixel a pixel con `plot` (42 columnas) en el bitmap, y tambien en la copia de fondo (`text_bg`); barra de estado = lineas 0-7, pie = filas 22-24;
  `t_textscr`/`t_gfxfix` (agic) limpian bitmap/atributos; ventanas, menus y `OVB_CLRRECT` restauran desde el fondo limpio.
- Modelo: `agi_vm.py` (`screen()`, `render()`, `hw_sprites()`, `sw_blit()`, `blit_cel()`), `agi_text.py` (`put_line`, `plot_hr`).

## 2. Geometria y mapa de memoria con GFX4

- `POKE 2045,176`; ventana de imagen `POKE 2070,1` / `POKE 2071,22` (filas de texto 1-21 = lineas 8-175); paleta `pal16` por omision = colores digitales de Chroma81,
  asi que **el indice de color sigue siendo `to_chroma(ega)`**: no cambia ninguna tabla de colores ni el texto.
- Imagen 160x168 a 4 bpp, 80 B/linea (nibble alto = izquierda): **13.440 B en `HFILE=$A000-$D47F`** (bloques 5-6, como hoy). Sin fila de estado en memoria (HFILE = linea 8): `HR_BM+256` desaparece.
- Plano de texto 40x25: 1.000 codigos en `$D480-$D867` (justo tras la imagen), activado con `POKE 2069,1`; `POKE 2068` = papel*16+tinta.
- Fondo limpio: 13.440 B en **dos paginas** (PG_BGB, PG_BGA; la segunda queda con 5.248 B de resto). Prioridad: RLE y maximos igual que hoy (pag. 29/30/43); ya no hay `(5*x)>>3` (1 px AGI = 1 px de pantalla; el bloque de maximos de 8 px = 1 mosaico).
- Fichero `PICnnn.GFX` **version 2** (misma cabecera `AGIP`, `+4`=2): `+256` imagen 13.440 B, luego prioridad, prioridad de sprites y maximos como hoy.
- Glifos del plano de texto: tabla de 2 KB alineada (registro I), fuente de 6 px `font6.inc` (ASCII 32-127 y la copia invertida en 128-255). **Sitio sin decidir** (en `$3800-$3FFF`/otro libre; se mide en la fase 4: el nucleo acaba en `$6D00`, los datos llegan a `$7E60`, la ventana de logica `$8000`).
- Sin doble buffer (13.440 B > 8 KB): `POKE 2057` se queda como esta con GFX4 (85); el dibujo software se vera durante el barrido.

## 3. Texto (fase 4): plano de la FPGA

- Barra de estado = fila 0, pie = filas 22-24: **solo celdas de texto** (la ventana de imagen no las cubre). Las filas 1-21 llevan texto *encima* de la imagen: celdas `>=32` son opacas, `<32` transparentes.
- Limitacion de hardware: **un solo par tinta/papel global** (`POKE 2068`) + inversion por el bit 7 del codigo -> dos esquemas: normal (tinta 15 / papel 0) e inverso (negro sobre blanco: barra de estado, ventanas `print`, menus).
  Los colores arbitrarios de `display`/`set.text.attribute`: bg 0 -> normal, cualquier otro bg -> inverso (ScummVM los pinta con colores EGA; se documenta como diferencia de hardware).
- `print`/menus: celdas opacas + marco rojo/blanco pintado en la imagen (rellenos de rectangulo de 4 bpp, 1 LDIR/fila); al cerrar, se **borran celdas** (nada que restaurar de texto) y se restaura el marco desde el fondo limpio (1 pasada).
- 40 columnas (hoy 42): el ajuste de lineas de `print` (30 car.) no cambia; cambian `COLS` y las posiciones x (`col*4` px de imagen).
- Pantalla de texto (`text.screen`) = plano entero opaco (la imagen no se toca); `graphics` = plano a 0 salvo barra y pie.
- Se retira de B/F el uso de `plot`/`text_bg`/`t_srow`; el nucleo pierde `plot`+`sd_get`+`sdt_*` (≈ 0,5 KB) y gana el plot de nibble (≈ 0,15 KB): el nucleo **baja** de tamano con GFX4=1.

## 4. Sprites (fase 3)

Primero software con mascara de prioridad (metodo original) para todos los objetos: guardar fondo / pintar con prioridad / restaurar, en 4 bpp (nibble RMW; ≈ 40 T/px). Sustituye a agisw `plot` por celdas.
El hardware **ya soporta** sprites 8x8 en 160w (`mode160w.asm`, +32 en X e Y, 2 colores/fila); reutilizar `agihws`/`agi2spr` con mosaico 8 px nativos (sin `lo(x)` ni `(5*x)>>3`) es probablemente mas barato que el software
y no pierde rendimiento: se decide con los ms/objeto medidos en el arnes (fase 3b, solo si el estudio lo confirma).

## 5. Ficheros que cambian

| Fase | Fichero | Cambio |
|---|---|---|
| 1 | `TOOLS/agi2hr.py` | `--gfx4`: PIC v2 (imagen 4 bpp sin cuantificar), verificacion 0 % |
| 1 | `TOOLS/agi_vm.py`, `agi_text.py` | modo GFX4: pantalla 4 bpp (`screen4()`), plot/relleno/composicion de sprites software, PNG |
| 2 | `ENGINE/agipic.asm`, `agivm.asm` (`video_init`), `agisw.asm` (`t_bgsave`, `lb_*`), `agic.asm` (`t_textscr`/`t_gfxfix`), `test` (arnes: ver abajo) | carga 13.440 B, fondo limpio, rellenos |
| 3 | `agisw.asm`, `agispr.asm` (`plot4`), `agihws.asm` | sprites |
| 4 | `agitx.inc`, `agib.asm`, `agif.asm`, `agic.asm`, `font6.inc`, `gen_font.py` | plano de texto |
| 5 | `agid.asm` (guardar), `agivm.asm` | integracion, pruebas |

Tamano del nucleo (tope 11.008 B, hoy ~10.989): con GFX4=1 baja (sale `plot`+tablas de distancia) y se pone el nuevo `plot4`; los overlays solo llaman al nucleo; A1/A2/B/F quedan por debajo al desaparecer la logica de atributos (B 8.188/8.192 es el punto critico: el cambio lo reduce).

## 6. Verificacion

- GFX4=0: `sh ENGINE/test_vm.sh` y `sh dump/runall.sh` (segundo plano, sin editar ENGINE) -> "OKs 5 DIFs 0"; binarios identicos a master (`cmp`).
- GFX4=1: el arnes de PC (`V2/ENGINE/test`, en SCUMM) emula el HiRes 8x1; hay que **extenderlo** para el formato 176 (mapa $A000, nibbles, ventana, plano de texto) y comparar contra `agi_vm.py --gfx4` (pantalla + sprites + texto).
- Imagen: `agi2hr.py --gfx4` relee el fichero y exige 0 pixeles distintos frente a `Picture.vis`. **Aviso:** la equivalencia de `agi_read.Picture` con `picture.cpp` de ScummVM esta marcada como no auditada (AUDITORIA3 D55); "0 % frente a ScummVM" solo es cierto frente al rasterizador de Python.
- EightyOne no emula 160w: verificacion visual = PNG del modelo + placa (`mode160w` ya funciona en la placa).

## 7. Riesgos

Un par de colores global en el plano de texto; ausencia de doble buffer (parpadeo en el barrido con el dibujo software); sitio de la tabla de glifos; +25 % de lectura de SD por imagen.

## Estado (2026-11-01)

- Fase 1 y 2: hechas (`755fa14`, `2471fb5`).
- Fase 3 (sprites **hardware 8x8**, decision del usuario): `agi2spr.py` y `agi_vm.py` con `AGI_GFX4=1` (1 pixel AGI = 1 pixel del sprite, imagen desde la linea 0 de la ventana, sin `(5*x)>>3`);
  Z80: `lo16`, `hg_okb`, `hx2ax`, limites y `hw_top` bajo `GFX4`. Z80 == modelo en SQ1 (14 sprites), KQ2 (28), PQ1 y KQ1, con prioridad por pixel. GFX4=0: binarios identicos.
  **Pendiente (3b):** rotulos anchos (> `SW_TILES` mosaicos por fila) y `add.to.pic` se saltan (no se dibujan) en GFX4; hay que pintarlos por software en 4 bpp (agisw) sobre pantalla y fondo limpio.
