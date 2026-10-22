# ROOMVIEW: visor de salas SCUMM en el SD81 Booster

Prueba de la fase 3 del plan (`claude/planning/scumm_plan.md`): enseña las salas de Maniac Mansion ya convertidas
(`ROOMnn.GFX`) con el modo que usará el motor:

- Superfast texto de 32 columnas con **256 caracteres** (`LOAD *256C`, `I = $38`), color **Chroma modo 0**
  (un par de colores por scanline de cada código) y pantalla alternativa en `$8000`;
- cada tile es un código de carácter: se cargan 8 bytes de forma en `$3800+8*código` y 8 de color en
  `$C000+8*código`;
- al mover la cámara se recargan solo los tiles que entran por el borde (listas `rstart` / `lstart` del `.GFX`);
- **scroll fino** por hardware (`POKE 2090`, 0-7 píxeles). Las filas 16-23 (la línea de estado) no se desplazan
  (`POKE 2093,0`). La columna que asoma por la derecha con el scroll fino es la 33 de la ventana: el conversor trabaja con ventanas de 33 columnas (`--view 33`), así que sus tiles ya están cargados y entra sin saltos.

Los códigos de carácter con el bit 7 puesto (128 en adelante) salen invertidos por el hardware, así que el
conversor guarda esas formas al revés. Los 40 glifos de la fuente (espacio, cifras, letras, `/ : .`, copiados de la ROM) van a los códigos 216-255 (texto de la línea de estado); el 216 es el espacio y hace de tile en blanco. Los slots de tiles llegan hasta 215.

## Teclas

| Tecla | Hace |
|---|---|
| `O` / `P` | desplaza 1 píxel a la izquierda / derecha |
| `B` / `N` | sala anterior / siguiente (salta las que no tienen fichero) |
| `ESPACIO` | sale a BASIC |

## Probar en el emulador

1. Los `.GFX` salen de `SCUMM/TOOLS/lfl2gfx.py` (necesita los `.LFL` de Maniac Mansion DOS v2):
   `python lfl2gfx.py ../V2/ManiacMansionDOS all -o ../preview`
2. `compila.bat` ensambla `roomview.asm` y copia el programa a `SD81\TOOLS\ROOMVIEW` y los `.GFX` a `SD81\SCUMM`
   (la raíz de la SD del emulador es `\ClaudeCode\Eightyone2\EightyOne\SD81`).
3. Cargar `ROOMVIEW.B81` (pásalo a `.P`) y `RUN`. Ficheros que lee: `/SCUMM/ROOMnn.GFX`.

## Qué se ha comprobado y qué no

`test/run_test.sh` ejecuta el programa en el Z80 de EightyOne con un MCU simulado (los ficheros del disco) y un
teclado con guion, y compara las 32 x 16 celdas de la pantalla, las tablas de formas y las de color con la
conversión de la sala, tras caminar a derecha e izquierda y cambiar de sala. **Pasa en las 7 comprobaciones.**

No se ha probado en hardware ni en el emulador: que Chroma 0 + 256C + pantalla alternativa + scroll fino convivan
(riesgo 7 del plan), los colores reales, ni que la velocidad de la recarga de tiles evite parpadeos. El visor no
espera al borrado vertical al copiar la ventana, así que puede verse un fotograma a medias al cruzar una columna.
