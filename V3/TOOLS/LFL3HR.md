# lfl3hr.py: salas de SCUMM v3 (Indy3 EGA) al HiRes 8x1 de 16 colores

Convierte el fondo y los objetos de cada sala (`NN.LFL` de Indiana Jones and the Last Crusade EGA, DOS) a `ROOMnn.GFX`, para el modo
**Superfast HiRes nativo con atributos de Chroma modo 0** del SD81 Booster: un byte de bitmap y un byte de atributo (papel en el nibble alto,
tinta en el bajo) por cada franja de **8x1 pixeles**, con el limite de 2 colores por franja. Es `V2/TOOLS/lfl2hr.py` con otro lector (la imagen
sale de `scumm3res.Room.image()`, la de los objetos de `Room.object_image()`) y con el formato `.GFX` **version 2**, que admite salas de
cualquier alto. La conversion a franjas (`lfl2gfx.row_spec`), el mapa EGA -> Chroma y los ajustes por sala se importan de `lfl2gfx.py` y
`lfl2hr.py` sin tocarlos. El formato de v2 (`V2/TOOLS/LFL2HR.md`, version 1) sigue valiendo para Maniac y Zak.

Es **offline**: se ejecuta en el PC.

## Uso

Desde `SCUMM/V3/TOOLS`:

```
python lfl3hr.py "../Indy Last Crusade" all -o ../preview_hr                  # las 88 salas
python lfl3hr.py "../Indy Last Crusade" 1 15 20 28 79 -o ../preview_hr        # solo algunas
python lfl3hr.py "../Indy Last Crusade" all --png all                         # PNG de todas (por omision solo 1, 15, 20, 28 y 79)
```

Salida (en `SCUMM/V3/preview_hr/`, ignorada por git: son datos derivados del juego):

| Fichero | Que es |
|---|---|
| `gfx/ROOMnn.GFX` | el fichero que ira a la SD |
| `salaNN.png` | cinco bandas: **1** original EGA, **2** el original en los 16 colores de Chroma, **3** el resultado, **4** el resultado con las imagenes de **todos** los objetos puestas (todos los estados a la vez: sale amontonada, y en salas como la 20 y la 28, cuyo fondo es negro y se compone de objetos, los ultimos tapan a los primeros), **5** el resultado con la **mascara de profundidad** en rojo (lo que tapa al personaje) |
| `resumen.md` | una fila por sala: tamano, error, bytes, objetos con imagen, objetos con mascara propia y verificacion |

**Error** = % de pixeles distintos de la banda 2 (el suelo, 3-5 %, es la regla de 2 colores por franja). **Verif.** tiene que decir `OK`: el
conversor vuelve a leer los bytes del fichero con las reglas del formato y reconstruye la sala y los objetos.

Ajustes por sala (`--cfg`, mismo formato que `gfx_rooms.cfg`; no hay ninguno por omision): `map=EGA,Chroma`, `objcolor=ID,EGA,Chroma`, `objpng=ID,fichero.png`,
`objhide=ID`, `rarity=F`. `--map`, `--rarity`, `--no-objects`, `-o`.

## Formato del `.GFX` (version 2)

Igual que la version 1 salvo el alto de las columnas, que antes era siempre 128:

```
+0    'HRGF'
+4    u8 version (2), u8 0
+6    u16 columnas de la sala (ancho / 8)
+8    u8 lineas de la sala (8-200), u8 numero de objetos
+10   u16 desplazamiento de la seccion de objetos (0: no hay)
+12   u8 columnas por pagina (cpp = 8192 // (2 * lineas))
+13   hasta +255: ceros
+256  las columnas. La k empieza en 256 + (k // cpp) * 8192 + (k % cpp) * 2 * lineas; por columna `lineas` bytes de bitmap (linea 0..) y `lineas` de
      atributos (bit 7 = el pixel de la izquierda; 1 = tinta). Lo que sobra al final de cada pagina de 8 KB son ceros
seccion de objetos: a continuacion de la ultima columna (sin relleno), por objeto en el orden de la sala 6 bytes: u16 donde estan sus datos (FFFF:
      sin imagen), u8 columna, u8 linea, u8 columnas, u8 lineas; despues los datos: por columna, `lineas` bytes de bitmap y `lineas` de atributos
```

| lineas | columnas por pagina | bytes sin usar por pagina |
|---:|---:|---:|
| 128 | 32 | 0 (igual que la version 1) |
| 136 | 30 | 32 |
| 184 | 22 | 96 |
| 192 | 21 | 128 |
| 200 | 20 | 192 |

- Una columna no cruza nunca una pagina de 8 KB, como en la version 1: el Z80 la trae por la ventana de datos de una vez. Los datos de un objeto si
  pueden cruzar paginas (`hr_fcopy`).
- Los objetos son opacos; los datos iguales se comparten; lo que sobresale por abajo de la sala o por la derecha se recorta (al **alto de la
  sala**, no a 128).
- Los objetos sin imagen propia (comparten OBIM con otro, `Room.object_image` devuelve `None`) llevan `FFFF`.
- Los desplazamientos son u16: un fichero no puede pasar de 64 KB (el mayor, la sala 79, mide 50.602 B). Maximo 84 objetos por sala
  (`HR_OBJREC`) y 48 KB por fichero (6 paginas fisicas, la 8-13): **solo la sala 79 (1280x136) pasa de 48 KB** y necesita una septima pagina.
- La mascara de profundidad **no va en el `.GFX`**: va en `DATA.BIN` (`pack_data3.py`), una por sala, en el formato de `lfl2gfx.mask_blob`. En
  v3 viene por franjas (`scumm3res.decode_mask`: un byte por franja de 8 pixeles y fila, bit 7 = el pixel de la izquierda), que es justo lo
  que `mask_blob` espera, asi que no hay que transformarla; solo cambia que ya no son 128 filas siempre.
- Las mascaras propias de los objetos (zplane 1 del OBIM) **no se empaquetan**: `resumen.md` dice cuantos objetos de cada sala la tienen. Es una
  cuestion abierta para el motor (fase 5 u 8).

## Como lo usara el motor

El mismo `hr.asm` del v2, con tres cambios que son de la fase 5: leer el alto del byte `+8` (antes 128), calcular la posicion de la columna con
`cpp` (para 128 lineas da lo mismo que antes) y recortar los objetos al alto de la sala. Las salas de 184-200 lineas piden la ventana con el
scroll vertical por hardware (decision D3 del plan). Nombre en la SD: `ROOMnn.GFX`, sin `_`.
