# lfl2hr.py: conversor de salas de SCUMM v2 al HiRes 8x1 de 16 colores

Convierte el fondo y los objetos de cada sala (`NN.LFL`, Maniac Mansion y Zak McKracken DOS v2) a `ROOMnn.GFX` para el modo
**Superfast HiRes nativo con atributos de Chroma modo 0** del SD81 Booster: un byte de bitmap y un byte de atributo (papel en el
nibble alto, tinta en el bajo, colores de Chroma) por cada franja de **8x1 píxeles**. No hay tiles ni límite de tiles: el único
límite es el de **2 colores por franja**. Sustituye a `lfl2gfx.py` (tiles de 8x8, 208 por ventana de cámara), que queda en el
repositorio por si se quiere comparar. Plan y decisiones: `claude/planning/scumm_hires16.md`.

Es **offline**: se ejecuta en el PC y los `.GFX` se copian a la SD (`compila_scumm.bat`).

## Uso

Desde `SCUMM/TOOLS`:

```
python lfl2hr.py ../V2/ManiacMansionDOS all -o ../preview_hr
python lfl2hr.py "../V2/Zak McKracken" all --cfg ../games/zak_rooms.cfg -o ../preview_zak_hr
python lfl2hr.py "../V2/Zak McKracken" 1 12 -o ../preview_zak_hr        # solo algunas salas
```

Antes de `compila_scumm.bat` hace falta además `DATA.BIN` y los sonidos (ver la cabecera del `.bat`); `pack_data.py` busca
`snd/SOUNDS.TXT` en la misma carpeta (`preview_hr/snd`, `preview_zak_hr/snd`).

Salida (carpetas ignoradas por git: llevan datos derivados de LucasArts):

| Fichero | Qué es |
|---|---|
| `gfx/ROOMnn.GFX` | el fichero que se copia a la SD |
| `salaNN.png` | cuatro bandas: **1** original EGA, **2** el original pasado a los 16 colores de Chroma, **3** el resultado, **4** el resultado con las imágenes de **todos** los objetos puestas (todos los estados a la vez: se ve amontonada, es normal) |
| `resumen.md` | una fila por sala: ancho, error, tamaño, objetos, verificación |

**Error** = % de píxeles distintos de la banda 2. **Verif.** tiene que decir `OK`: el conversor vuelve a leer los bytes del
fichero y reconstruye la sala y los objetos. El suelo del error (3-5 %) es la regla de 2 colores por 8x1, que no depende del
conversor. `medir8x1.py` compara el error con el de los tiles (lo que se midió para decidir el cambio).

## Ajustes por sala

Los de `games/zak_rooms.cfg` / `gfx_rooms.cfg` (una línea por sala, `#` comenta) que **siguen valiendo**:

| Opción | Para qué sirve |
|---|---|
| `map=EGA,Chroma` | cambia a qué color de Chroma va un color EGA en esa sala |
| `objcolor=ID,EGA,Chroma` | idem, solo para un objeto |
| `objpng=ID,fichero.png` | sustituye la imagen de un objeto por un PNG retocado (colores de Chroma, tamaño exacto) |
| `objhide=ID` | el objeto no lleva imagen |
| `rarity=F` | peso de los colores raros de la sala al elegir el par de cada franja (0,5 por defecto; 0 lo desactiva) |

`protect`, `keep`, `pool`, `tiles` y `objprio` eran para repartir tiles: se **ignoran**. Opciones de línea de órdenes: `--map`,
`--rarity`, `--cfg`, `--no-objects`, `-o`.

## Formato del `.GFX` (versión 1)

```
+0    'HRGF'
+4    u8 versión (1), u8 0
+6    u16 columnas de la sala (ancho / 8)
+8    u8 líneas (128), u8 número de objetos
+10   u16 desplazamiento de la sección de objetos (0: no hay)
+12   hasta +255: ceros
+256  las columnas: la k está en 256 * (k + 1); por columna 128 bytes de bitmap (línea 0..127) y 128 de atributos
      (bit 7 = el píxel de la izquierda; 1 = tinta)
sección de objetos: por objeto, en el orden de la sala, 6 bytes: u16 dónde están sus datos (FFFF: sin imagen), u8 columna,
u8 línea, u8 columnas, u8 líneas; después los datos: por columna, `líneas` bytes de bitmap y `líneas` de atributos
```

- La columna k empieza en un múltiplo de 256 para que **32 columnas llenen exactamente una página de 8 KB**: el Z80 trae cada
  columna por la ventana de datos sin cruzar páginas. Los datos de un objeto sí pueden cruzar páginas (`hr_fcopy`).
- Los objetos son opacos; los datos idénticos se comparten; los que sobresalen por abajo de la sala (la interfaz) se recortan.
- Máximo 84 objetos por sala (`HR_OBJREC`, 6 bytes cada uno, en el hueco libre del bloque del bitmap) y 48 KB por fichero
  (6 páginas físicas, la 8-13). El mayor mide ~44 KB.
- La máscara de profundidad de los personajes sigue yendo en `DATA.BIN` (`pack_data.py`), no en el `.GFX`.

## Cómo lo usa el motor

`ENGINE/hr.asm` (carga en páginas, composición de columnas, scroll con el motor por hardware), `ENGINE/hrui.asm` (interfaz de
40 columnas de 6 píxeles) y `ENGINE/dark.asm` (oscuridad con los atributos). Verificación en el arnés: `ENGINE/test/check_hr.py`.
