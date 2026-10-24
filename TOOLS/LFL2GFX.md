# lfl2gfx.py: conversor de salas de SCUMM v2 a gráficos del SD81 Booster

Convierte el fondo de cada sala de Maniac Mansion (DOS v2, ficheros `NN.LFL`) a `ROOMnn.GFX`, el formato que
carga el motor (y el visor `SCUMM/VIEWER`). Es **offline**: se ejecuta en el PC y los `.GFX` se copian a la SD.

Diseño y formato del fichero: `claude/planning/scumm_plan.md` (secciones 3.4 y 3.5).

## Qué hace, en una frase

Cada fila de 8 píxeles de la sala solo puede tener **2 colores** (Chroma modo 0) y cada tile (8x8) es un código de
carácter, de los que caben **210** distintos en una ventana de 33 columnas de la cámara. El conversor reduce la
imagen a eso intentando que se pierda lo menos posible de lo que importa, y escribe el `.GFX` con los tiles que
hay que cargar al mover la cámara.

## Requisitos

- Python 3 (solo la biblioteca estándar).
- Los `NN.LFL` de Maniac Mansion DOS v2 en `SCUMM/V2/ManiacMansionDOS` (datos de LucasArts: no se versionan).

## Uso rápido

Desde `SCUMM/TOOLS`:

```
python lfl2gfx.py ../V2/ManiacMansionDOS all -o ../preview        # todas las salas (1-2 minutos)
python lfl2gfx.py ../V2/ManiacMansionDOS 4 43 -o ../preview       # solo las salas 4 y 43
```

Para verlas en el emulador: `SCUMM/VIEWER/compila.bat` copia los `.GFX` a `SD81\SCUMM` (la raíz de la SD del
emulador es `\ClaudeCode\Eightyone2\EightyOne\SD81`). Teclas del visor: `O`/`P` scroll, `B`/`N` sala.

## Qué sale

En la carpeta de `-o` (`SCUMM/preview`, ignorada por git):

| Fichero | Qué es |
|---|---|
| `gfx/ROOMnn.GFX` | el fichero que se copia a la SD |
| `salaNN.png` | tres bandas: **1** original EGA, **2** el original pasado a los 16 colores de Chroma, **3** el resultado final. Las zonas `protect` salen en un marco magenta sobre la banda 1 |
| `resumen.md` | una fila por sala: tiles totales, máximo por ventana, error, tamaño |

La línea que imprime por sala: `| sala | ancho | tiles | máx. ventana | slots | error | bytes | verif. |`.

- **Error**: % de píxeles distintos del original (en Chroma). La mediana de las 53 salas es del 5 %; la peor ronda el 18 %.
- **Verif.** tiene que decir `OK`: simula la carga de tiles al mover la cámara a derecha, izquierda y con saltos, y
  comprueba que todas las celdas visibles tienen sus bytes. Si dice `FALLA`, no usar el fichero.

**Lo que se pierde se ve comparando las bandas 2 y 3:**
- La banda 2 ya pierde detalle respecto a la 1: es el límite de 2 colores por fila de 8 píxeles. Eso no se arregla
  con más tiles (por ejemplo, los teclados de la sala 43 solo usan 43 tiles y aun así pierden colores).
- La diferencia entre la 2 y la 3 es lo que cuesta el límite de tiles. Eso sí se puede repartir con los ajustes.

## Ajustes por sala: `gfx_rooms.cfg`

Fichero de texto en esta misma carpeta (se lee solo, no hace falta pasarlo). Una línea por sala, `#` comenta:

```
sala: protect=x0,y0,x1,y1  keep=C  keep=C,x0,y0,x1,y1  tiles=N  rarity=F
```

| Opción | Para qué sirve |
|---|---|
| `protect=x0,y0,x1,y1` | Rectángulo en **píxeles de la sala** (0,0 arriba a la izquierda; la sala mide 128 de alto) cuyos tiles casi no se funden con otros. Para rótulos, personajes, cuadros, mapas. Se pueden poner varios. |
| `keep=C` | El color `C` de Chroma (tabla abajo) **no se pierde** en las filas de los tiles de toda la sala: es siempre uno de los 2 colores de cada fila. Para cifras, rótulos finos. |
| `keep=C,x0,y0,x1,y1` | Lo mismo, solo en esa zona. |
| `tiles=N` | Presupuesto de tiles por ventana para esa sala (por defecto 210). |
| `rarity=F` | Peso de los colores raros de la sala (por defecto 0,5; 0 lo desactiva). |
| `pool=N` | Tiles de la reserva de objetos (por defecto 64; 0 = sin objetos). Se restan al presupuesto del fondo. |

Ejemplo real:

```
4: protect=0,35,88,96 protect=130,60,260,127     # sala 4: rótulo SECRIT LAB y esqueleto
43: keep=15                                       # sala 43: el blanco de los teclados es sagrado
```

Cómo trabajar una sala mala:

1. Mira `preview/salaNN.png`. Si el detalle ya está mal en la banda 2, solo `keep` puede ayudar (y poco).
   Si se estropea entre la 2 y la 3, usa `protect` sobre ese detalle.
2. Añade la línea, ejecuta solo esa sala (`python lfl2gfx.py ../V2/ManiacMansionDOS 4 -o ../preview`) y vuelve a
   mirar el PNG (el marco magenta te dice qué zona has marcado).
3. No protejas de más: lo protegido ocupa tiles de la misma ventana de 33 columnas (264 píxeles), y lo que queda
   sin proteger se estropea más. Protege lo imprescindible.
4. Cuando estés conforme, repite con `all` (o con las salas tocadas), copia con `compila.bat` y mira en el emulador.

### Colores de Chroma (para `keep`)

Índice = bit 3 brillo, bit 2 verde, bit 1 rojo, bit 0 azul. Se pasa de EGA a Chroma por el color más cercano
(el marrón del EGA, 6, va al amarillo 6):

| 0 negro | 1 azul | 2 rojo | 3 magenta | 4 verde | 5 cian | 6 amarillo | 7 gris |
|---|---|---|---|---|---|---|---|
| 8 gris oscuro | 9 azul claro | 10 rojo claro | 11 magenta claro | 12 verde claro | 13 cian claro | 14 amarillo claro | 15 blanco |

Si no sabes el número, el color del EGA original suele ser el mismo índice que el de Chroma (EGA 15 = blanco = 15).

## Opciones de la línea de órdenes

Se aplican a todas las salas (el `.cfg` manda sobre ellas donde coincide):

| Opción | Por defecto | Qué hace |
|---|---|---|
| `--tiles N` | 208 | Tiles distintos por ventana. Los códigos 208-209 son las flechas (de color) del inventario y 210-255 la fuente de la interfaz (46 glifos) |
| `--view N` | 33 | Columnas de la ventana de cámara: 32 visibles + la que asoma con el scroll fino. No cambiarlo sin cambiar el visor |
| `--metric color\|count` | color | `color`: el error al fundir tiles se mide por distancia de color; `count`: por píxeles distintos (el método original) |
| `--power P` | 0,5 | Coste de fundir un tile = apariciones^P × distancia. 1 sacrifica antes los tiles raros; 0 los trata igual |
| `--rarity F` | 0,5 | Peso de los colores raros de la sala (el blanco de un esqueleto) |
| `--centroid` | no | Tras fundir, cada tile pasa a ser el representante de su grupo. Casi no mejora y tarda más |
| `--sal F` | 0 | Protege los tiles de mucho contraste. Casi no ayuda |
| `--protect "x0,y0,x1,y1;..."` | — | Como `protect` del `.cfg`, para todas las salas del comando |
| `--map "6=2,..."` | — | Cambia la correspondencia EGA→Chroma, p. ej. `6=2` manda el marrón al rojo |
| `--code-base N` | 0 | Primer código de carácter de los slots |
| `--pool N` | 64 | Tiles de la reserva de objetos por sala (0 = sin objetos) |
| `--no-objects` | no | No incluye las imágenes de los objetos |
| `--cfg ruta` | `gfx_rooms.cfg` | Otro fichero de ajustes |
| `-o carpeta` | `preview` | Dónde escribir |

## Cosas que conviene recordar

- **Los códigos de carácter ≥ 128 salen invertidos por el hardware.** El conversor ya guarda esas formas al revés
  (y `verify_gfx` lo deshace al comprobar). Si algún día cambia el reparto de códigos, revisar esto.
- **210 slots + 46 de fuente.** El motor usa los códigos 210-255 para su texto (el visor solo 216-255). El motor definitivo tendrá que
  decidir qué fuente necesita la interfaz y, si hace falta más, bajar `tiles`.
- **Tamaño.** El `.GFX` más grande (sala 29) mide unos 14,5 KB y el visor tiene un buffer de 15 KB. El motor
  tendrá que dar más sitio, o la sala 29 no cabrá.
- **Compartir ajustes con el comprobador.** `SCUMM/VIEWER/test/check_view.py` reproduce la conversión para
  comprobar la pantalla del visor; usa los valores por defecto de aquí y lee `gfx_rooms.cfg`. Si cambian los
  valores por defecto de `lfl2gfx.py`, hay que cambiarlos también ahí (`L.METRIC`, `L.POWER`, `L.RARITY`...) o
  `run_test.sh` fallará.
- **Si falla al escribir un PNG** (`no se puede escribir...`): en Windows el visor de imágenes o el antivirus a
  veces bloquean el fichero un instante; el conversor reintenta 10 veces. Cierra la imagen y repite la sala.
- **El resultado es determinista:** ejecutar la misma orden dos veces da el mismo `.GFX`.
- **Datos derivados de LucasArts.** `SCUMM/preview/` y los `.GFX` no se suben al repositorio (ver `.gitignore`).
  `gfx_rooms.cfg` y el conversor sí, porque son propios.

## Comprobar que todo sigue bien

```
sh ../VIEWER/test/run_test.sh        # ejecuta el visor en el Z80 de EightyOne y compara pantalla y tiles con la conversión
```

Tiene que acabar con todas las comprobaciones en `OK`.

## Objetos con imagen (versión 2 del `.GFX`)

En Maniac Mansion v2 el fondo de la sala (`NN.LFL`) no incluye todo lo que se ve: los **objetos** (puertas, interruptores,
cajones, el recuadro de selección, los parpadeos de los retratos...) tienen cada uno su imagen (bloque OBIM, el mismo RLE por
columnas que el fondo). Un objeto se dibuja encima del fondo mientras su estado tiene el bit 8 («intrínseco») y los padres
tienen el estado pedido; cuando el bit se apaga, se restaura el fondo. Los scripts lo cambian con `setStateIntrinsicOn/Off`.

El conversor mete esas imágenes en el `.GFX` como una **reserva de tiles**: hasta `P` tiles (por omisión 64) con las formas y
colores de todos los objetos de la sala, a los que apuntan las celdas de cada objeto. La reserva ocupa los códigos de carácter
de **más arriba de los slots** del fondo (de `210 - P` a 209), así que el fondo trabaja con `210 - P` tiles por ventana en las
salas con objetos. Si los objetos de una sala tienen más de `P` tiles distintos se funden los menos importantes (como en el
fondo). En el Z80, al empezar la sala se cargan los `P` tiles de golpe y, cada vez que se copia la ventana a la pantalla, se
pintan encima los objetos que se dibujan (del último al primero de la lista de la sala); cuando un script cambia el estado de
un objeto, el núcleo avisa al programa (suceso `EV_OBJSTATE`) y se vuelve a componer la ventana.

Ajuste por sala en `gfx_rooms.cfg`: `pool=N` (0 = la sala no lleva objetos). Opciones de la línea de órdenes: `--pool N` y
`--no-objects`. Formato de la sección (al final del fichero, sus dos últimos bytes dicen dónde empieza): ver `object_section`
en `lfl2gfx.py`.
