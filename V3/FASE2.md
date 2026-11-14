# Fase 2: conversores de datos de Indy3 EGA (resultado, 2026-11-11)

Todo en `V3/TOOLS/`. La salida va a `V3/preview_hr/` (ignorada por git). Se regenera con:

```
cd SCUMM/V3/TOOLS
python lfl3hr.py "../Indy Last Crusade" all -o ../preview_hr                      # 88 salas, ~5 min (el PNG solo de 1, 15, 20, 28 y 79)
python costume3.py "../Indy Last Crusade" frames > ../preview_hr/frames.txt       # recuento de fotogramas pedidos por los scripts
python costume3.py "../Indy Last Crusade" convert -o ../preview_hr                # trajes: cost/COSTnnn.bin y COSTnnnX.bin, trajes.md
python costume3.py "../Indy Last Crusade" png 1 -o ../preview_hr                  # hoja de contacto del traje 1 (y 1X si lo hay)
python sound3vgm.py "../Indy Last Crusade" ../preview_hr/snd                      # 73 VGM + SOUNDS.TXT, ~8 min
python pack_data3.py "../Indy Last Crusade" ../preview_hr/DATA.BIN --costumes ../preview_hr --sounds ../preview_hr/snd
python pack_data3.py "../Indy Last Crusade" ../preview_hr/DATA.BIN check --costumes ../preview_hr
```

| Fichero | Que hace |
|---|---|
| `lfl3hr.py` + `LFL3HR.md` | salas a `ROOMnn.GFX`, formato **version 2** (alto variable, 128-200) |
| `costume3.py` | trajes a blobs con la numeracion de v3, las posturas especiales y la paleta del actor |
| `pack_data3.py` | `DATA.BIN` version 3 y comando `check` (lee de vuelta y compara con los recursos) |
| `sound3vgm.py` | sonidos a VGM del AY y `SOUNDS.TXT` con lo que hace falta para `VAR_MUSIC_TIMER` |

## Cifras

**Salas** (`preview_hr/resumen.md`): 88 `.GFX` sin errores, todos con verificacion `OK`.
- Alturas: 59 de 128, 2 de 136, 1 de 176, 10 de 184, 6 de 192, 10 de 200. 31 salas miden mas de 320 de ancho (hasta 1.280).
- Tamano: total 1.854.598 B, mediana 16.992 B, maximo 50.602 B (sala 79, 1280x136). **Solo la 79 pasa de los 48 KB** (6 paginas) y pide una septima.
- Error del paso a 8x1: media 4,5 %, mediana 4,0 %, maximo 17,8 % (sala 13). Es la misma perdida que Zak (el estudio medio 4 % de media).
- Las salas 20 y 28 tienen el fondo negro: se componen solo de objetos (16 y 22).
- 697 objetos con imagen propia. **212 objetos de 34 salas llevan ademas mascara propia** (zplane 1 del OBIM): no se empaquetan, ver "Abierto".

**Trajes** (`preview_hr/trajes.md`): 100 trajes sin errores, ninguno cae al "no cabe".

| | Trajes | Mediana | Maximo | Total |
|---|---:|---:|---:|---:|
| recurso original | 100 | 4.179 B | 15.804 B | 432.297 B |
| blob principal | 100 | 2.090 B | 6.031 B | 260.017 B |
| blob extra (segunda pagina) | 24 | 4.979 B | 6.067 B | 99.810 B |

Celdas del principal: mediana 68, maximo 203 (el limite del formato es 256).

**`DATA.BIN`**: 640.768 B = 14.080 de tablas + 102 paginas de 6.144 B, lectura de vuelta correcta (129 scripts, 929 objetos, 88 salas, 232
scripts locales, 100 trajes, 61 mascaras de sala; con un byte cambiado en un script, en el script 95 o en un blob, `check` lo detecta).

| Parte | Bytes | % |
|---|---:|---:|
| trajes (principal + extra) | 359.827 | 60,5 |
| scripts globales (sin el 95) | 65.821 | 11,1 |
| bloques OBCD de objetos | 51.944 | 8,7 |
| scripts locales de sala | 38.571 | 6,5 |
| mascaras de profundidad | 32.321 | 5,4 |
| blobs de sala (cajas, matriz, objetos) | 28.155 | 4,7 |
| entrada y salida de sala | 10.622 | 1,8 |
| script 95 (dos paginas aparte) | 6.707 | 1,1 |

Mayor blob de sala: 1.496 B (v2 reservaba 1.024: el motor de v3 tiene que reservar mas).

**Sonido**: 73 de los 84 sonidos del indice se convierten (los 11 restantes no tienen bloque PCjr, como dice el estudio). 44 MB de VGM en total:
los 8 sonidos que no repiten estado del secuenciador (8, 12, 42, 46, 66, 67, 69 y 70) llegan al tope de 1 hora de `sound2vgm.MAX_TICKS` (otros 9 pasan de 200.000 ticks
antes de repetir) y el 46 pesa 9,4 MB. Es lo mismo que ya pasa con el 70 de Zak; si estorba, se recortan al primer ciclo.

## Lo que se ha hecho distinto de lo que decia el plan

- **Los indices de la lista de animaciones del blob son los del recurso** (fotograma * 4 + direccion), no los 0-7 comprimidos de v2: el Z80 elige el
  fotograma `f` mirando a `d` en la entrada `f * 4 + d`. La numeracion de v3 es inicio 1, andar 2, quieto 3, hablar 4 y cerrar la boca 5.
- **Sin el adelanto de x de v2**: en `Actor_v3` no se aplica el `+8` / `+16` de `Actor_v2::prepareDrawActorCostume`. El origen es (x - 72, y - 100) y
  la imagen se refleja alrededor de x en la direccion 0 (y solo si el traje no lleva el bit 7 del formato).
- **Estado de los miembros** como ScummVM: el fotograma de inicio apaga todo (`_cost.reset()`, version >= 3), una animacion solo cambia los miembros
  que nombra, los comandos 0x79/0x7A paran y reanudan un miembro y 0x7C/0x78 se saltan al avanzar. La postura de un fotograma se compone como
  inicio + quieto + el fotograma.
- **Paleta del actor** (no estaba en el plan): en Indy3 todos los trajes llevan el byte de color 1, que `setPalette` envia a `_palette[0]` (negro por
  omision); y 10 trajes tienen `actorOps 11` con literales. Se hornea en los colores del blob (aproximacion, ver "Abierto").
- **Dos paginas por traje** en vez de menos pasos de andar solo: 24 trajes con todas sus posturas no caben en 6.100 B.

## Recuento de fotogramas (`preview_hr/frames.txt`)

865 `animateActor` en los scripts de Indy3:
- 343 son orden de direccion o de parar (244-255);
- 177 piden un fotograma de 1 a 5, 316 uno de 6 a 30 (20 distintos: 6-22, 26, 27 y 30), 29 el fotograma en una variable;
- 23 llevan el actor en una variable que no es `VAR_EGO` y no se pueden atribuir a un traje.

Mas pedidos: 3 (130 veces, quieto), 6 (48), 10 (45), 9 (38), 7 (31), 12 (31), 13 (23), 8 (22), 1 (21), 11 (16)...
Los actores con traje fijado por literal son 12; `VAR_EGO` recibe los valores 1, 2, 3, 6, 7, 8 y 10.
`actorOps` fija el fotograma de andar a 6 (varios trajes de Indy y otros), a 2; el de hablar a 4/5, 6/13 y 12/5; esos se guardan como andar y hablar.
Un traje recibe todos los fotogramas de los actores que lo llevan en algun momento: el actor 1 recibe 43 trajes distintos en los scripts (Indy, Henry,
Marcus...), asi que todos heredan lo que se pide para el actor 1. Si el traje no define ese fotograma, no se guarda nada; si lo define y nunca se usa con ese
traje, sobra (es lo que infla los 100 KB de blobs extra: una atribucion exacta pide ejecutar los scripts, ver el modelo de la fase 1).

## Que no cabe y que hacer

- **Pasos de andar recortados** (de 4 a 3 o 2 por direccion): trajes 1, 2, 4, 10, 14 y 84. Son sobre todo trajes del actor 1 (Indy): tienen dos animaciones de andar (fotogramas 2 y 6) y
  muchas celdas. Si molesta a la vista, la alternativa es un tercer blob para el andar de Indy.
- **Fotogramas pedidos que se pierden aun con dos paginas**: traje 30 (18, 17, 21), 34 (14, 15), 35 (21), 36 (21), 39 (18, 21); en todos son los menos pedidos
  (1-2 veces en todo el juego). Con una tercera pagina cabrian; lo mas barato es dejarlos y que el motor use el fotograma de quieto.
- **256 celdas por blob**: no se llega (maximo 203/198), pero un traje con mas posturas no cabria sin cambiar el u8 del indice.
- Para la pagina de datos: el motor tiene que buscar la animacion en dos blobs (`COSTDIR` y `COSTDIR2`).

## Sonido: VAR_MUSIC_TIMER en v3

Lo que hace `Player_V2Base` (`player_v2base.cpp`, `sound.cpp`) y que el motor del Z80 tiene que reproducir (esta en el docstring de `sound3vgm.py`):
1. `nextTick()` (236 Hz, siempre que el reproductor este activo, suene algo o no) hace `if (_music_timer_ctr++ >= _ticks_per_music_timer) { ctr = 0; _music_timer++ }`.
2. `_ticks_per_music_timer` es 65535 al crear el reproductor (el temporizador no avanza) y pasa a **125** (+1 cada 126 ticks, 0,534 s) la **primera vez** que algun sonido
   ejecuta `0xFF` con el parametro 14 (`tempo`). No vuelve atras en toda la partida. Fijan el tempo, en el tick 0, los sonidos
   29, 35, 38, 39, 40, 41, 42, 54, 66, 67, 69 y 70 (columna 6 de `SOUNDS.TXT`). Hasta que suene uno, `VAR_MUSIC_TIMER` vale 0 siempre.
3. `chainSound` (al empezar cada sonido, tambien al encadenar el siguiente) pone `_music_timer` a 0, pero no el contador intermedio `_music_timer_ctr`: el primer
   incremento llega entre 1 y 126 ticks despues.
4. Cada fotograma (`Sound::updateMusicTimer`, antes de correr los scripts): `VAR(VAR_MUSIC_TIMER) = int(_music_timer * 236,70 / 240)`, o sea x 0,98623 truncado. (236,70 =
   `PIT_BASE_FREQUENCY / PIT_V2_4_DIVISOR` para DOS v3.)
5. En v2 el valor lo escribe el propio sonido en el canal 0; aqui no (`pack_data.sound_table` v2 lo copiaba de la columna 6-7 de `SOUNDS.TXT`; el de v3 usa
   la 6 y la 7 para decir "fija el tempo" y "en que tick").

En `DATA.BIN` v3: bit 2 de las banderas del sonido = fija el tempo; el tick va en la segunda tabla de 256 x 4.
El modelo `scumm3vm.py` usa `music_jiffies // 6`, que no es esto; el modelo de la fase 1 y el Z80 tienen que usar el contador de arriba.

## Abierto para la fase 3 y siguientes

- **D5 (script 95)**: va aparte, en dos paginas consecutivas (`BIGDIR`, `SCRDIR` con pagina 255). 6.707 B de codigo + 4 de cabecera. Es el unico mayor que una pagina (el siguiente mide 4,9 KB).
  La lectura de bytes en el Z80 tiene que pasar de pagina cuando el puntero llegue al final de la ventana, o el motor reserva 8 KB para scripts.
- **Mascaras de objetos**: 212 objetos de 34 salas tienen mascara propia (`resumen.md`, columna "Con mascara"); no estan en `DATA.BIN`. En ScummVM se suman a la de la sala al dibujar
  el objeto. Falta decidir en la fase 5 si hacen falta (pasillos, arcos, columnas delante del personaje) y, si si, un blob por objeto.
- **Paleta**: el remapeo de colores se horneo con lo que escriben los scripts por literal. Si en el juego cambia a mitad (7 `actorOps 11` con actor o color en variable, y los
  indices ambiguos de `trajes.json`: 12, 43, 33...), el motor no puede corregirlo. El motor tampoco aplica el modo "oscuro" del actor (`LIGHTMODE_actor_use_colors`).
- **Tamanos del motor**: blob de sala hasta 1.496 B (v2: 1.024), 100 salas en `ROOMDIR` (32 B cada una), 14 KB de tablas, 102 paginas (v2: Zak ~45). La demanda por pagina del cargador
  (`dp_cache.inc`) sirve; la pagina maxima virtual es la 255, y se usa de la 16 a la 117.
- **`PROFILE`**: va a ceros mientras no haya perfil de Indy3 (`gameprofile.py` es de v2: filas de verbos, teclas...). Lo define la fase 3 o la 7.
- **Alto del `.GFX`**: el motor tiene que leerlo del byte +8 y usar `cpp` (columnas por pagina) en vez de 32. La mascara de sala tambien termina por el alto, no por 128.
- **Objetos 929 de 1.000**: los 71 restantes del indice global no estan en ninguna sala (`OBJROOM = 0`): no tienen OBCD. Los que se recogen se copian del OBCD de su sala (`ODIR`).
- Los trajes de salas con 4-6 actores (D6) siguen pendientes: el tamano de las posturas esta en `trajes.md` (sprites por postura, no medidos aqui).
- Sin cambios en `V2/` ni en los ficheros de las fases 0 y 1. Sin commit.
