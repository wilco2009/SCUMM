# Pruebas en la placa: SCUMM v3 (Indy3 EGA) — lista para el usuario

Fase 9 de `PLAN.md`. Todo lo de abajo está probado **en el arnés de PC** (trazas iguales al modelo de Python, `check_hr.py`, `check_spr.py`); lo que sigue **no se ha podido ver en la placa**:
el vídeo real (scroll, paleta, sprites), el sonido real (VGM), el teclado y el ratón, el tiempo real y la SD. Cada prueba dice qué mirar y qué apuntar si falla.

## 0. Montaje y copia a la SD

```
cd SCUMM\V3\ENGINE
compila_scumm.bat            monta y copia a la SD del emulador (\ClaudeCode\Eightyone2\EightyOne\SD81\SD81)
compila_scumm.bat X:\        copia a la raíz de la tarjeta X:
compila_scumm.bat nocopia    solo deja la carpeta lista en SCUMM\V3\SDOUT\ (cópiala tú a la SD)
```

Necesita `pasmo` y `python` en el PATH y, una vez, los datos convertidos (`V3\preview_hr\gfx`, `cost` y `snd`: ver `FASE2.md`). Deja en la SD:

| Fichero | Qué es |
|---|---|
| `SCUMM\V3\SCUMM.BIN` | el programa (se carga en `$4200`; entrada `RAND USR 16917`) |
| `SCUMM\V3\INDY3\INDY3.B81` | el BASIC que lo arranca |
| `SCUMM\V3\INDY3\DATA\DATA.BIN` | los datos (scripts, objetos, cajas, trajes, tabla de sonidos, perfil) |
| `SCUMM\V3\INDY3\DATA\OVLB.BIN`, `OVLC.BIN`, `OVLD.BIN` | los tres overlays (páginas físicas 49, 48 y 46) |
| `SCUMM\V3\INDY3\DATA\ROOMnn.GFX` | las 88 salas |
| `SCUMM\V3\INDY3\DATA\SND\SOUNDnnn.VGM` | los sonidos |

Las partidas (`SAVEnn.SAV`, unos 13,5 KB cada una) y los puntos IQ van a `SCUMM\V3\INDY3\`. **La carpeta de trabajo tiene que ser `SCUMM\V3\INDY3`** (el BASIC hace `LOAD FAST "../SCUMM.BIN"` y el programa abre `DATA/...` relativo a ella).
Firmware del MCU: el actual (los comandos `FCREATE` 71 y `FWRITE` 56 ya los usa v2; `PLAY_VGM`, `STOP_VGM` y `LOOP_VGM` también). Sin firmware nuevo.

Para arrancar: entra en `SCUMM\V3\INDY3`, `LOAD "INDY3"` (o `LOAD *…` como con v2) y `RUN`. Sale con **SHIFT + X** (el código de error de la VM sale por `PRINT USR`: 0 = normal).

## 1. Teclas

| Tecla | Qué hace |
|---|---|
| letras (sin SHIFT) | la tecla del verbo de Indy3 (q a z w s x e d c r f v t g b y u h j n m o l); **X = Look** |
| **Intro** | clic izquierdo (con el cursor activo) |
| **SHIFT + 5 / 6 / 7 / 8** | mover el cursor: izquierda / abajo / arriba / derecha (3 px por fotograma) |
| **SHIFT + ESPACIO** | ESC (saltar una escena cortada) |
| ESPACIO | pausa ("GAME PAUSED - PRESS SPACE") |
| **SHIFT + S** | **F5: abre el diálogo de guardar y cargar de Indy3** (nuevo en la fase 9) |
| **SHIFT + 0** | borrar (RUBOUT) al escribir el nombre de una partida |
| SHIFT + R | reiniciar el juego (como el arranque, sin releer los overlays) |
| SHIFT + X | salir al BASIC |
| ratón Bluetooth | mueve el cursor; botón izquierdo = clic; botón derecho = ESC |

## 2. Qué probar (en este orden; cada una depende de la anterior)

### 2.1 Arranque
- Aparece el logo de LucasArts (sala 76), luego los créditos (79) con la cámara moviéndose, el mapa (6) y por fin el pasillo de Barnett College (sala 1).
- **Mirar:** que no haya basura al cambiar de sala, que el texto de arriba (2 filas) y los verbos de abajo salgan, y el tiempo hasta el pasillo (en el modelo: fotograma 582 a 50 Hz ≈ 12 s si la placa va a tiempo real).
- Si el programa vuelve al BASIC: apunta el número de `PRINT USR` (1 = faltan los overlays, 2 = falta `DATA.BIN`, otro = error de la VM) y mira que `DATA\OVLB.BIN` etc. estén.

### 2.2 Protección anticopia (sala 92)
- El perfil trae `proteccion = 0`: la sala 92 (la rueda de códigos) se **salta sola** a los 30 fotogramas (`Var[57] = 1`). Tiene que pasar de la 92 a la 73 (el gimnasio / Barnett) sin pedir nada.
- Para probar la protección de verdad hay que poner `proteccion = 1` en `V3\games\indy3.cfg` y recompilar: se contesta con el ratón.

### 2.3 Barnett College (salas 73, 1, 8 y siguientes)
- Clics en verbos y objetos; la frase aparece en la **segunda fila de mensajes de arriba** (decisión del usuario: Indy3 usa 7 filas de interfaz y D3 da 6), así que **mientras hay un mensaje la frase no se ve**.
- Probar: LOOK a una taquilla, WALK TO por el pasillo (Indy camina por las cajas), OPEN una puerta, inventario con las flechas, un diálogo largo (el texto se parte a las 40 columnas, sin partir por palabras).
- **Mirar:** que los clics caigan donde toca (la conversión pantalla → SCUMM es `x/6*8` en la interfaz y la identidad en la sala), que Indy no atraviese paredes, que los sprites (Indy, Henry...) no parpadeen ni se corten al borde.

### 2.4 Venecia (sala 15) y el castillo (salas 20 y 28)
- Se llega por los scripts del juego; si cuesta llegar, `DBG_ROOM` (escribir el número de sala en `SV+196` = `$87C4`, palabra, desde el emulador) carga la sala.
- **Venecia:** muchos objetos y actores; mira el scroll horizontal de la cámara y los objetos animados.
- **Castillo (20 y 28):** objetos animados (antorchas, cuerdas). En el arnés cuestan **334.000 y 451.000 T por vuelta** frente a los 325.000 del presupuesto: **es de esperar que vayan a tirones**; apunta cuánto (fase 10: rendimiento).

### 2.5 Scroll
- Lo más delicado del vídeo (no se ha visto en la placa): el scroll por hardware con las filas `$FC / $FF / $03` (se desplazan las filas 2-17 de la sala; las 0-1 de mensajes y las 18-23 de interfaz se quedan quietas) y el recorte de las salas de 144 líneas o más (se pierden las 16 de arriba).
- **Mirar:** que los mensajes y la interfaz **no** se muevan con la cámara, que no haya un salto o línea de más al empezar o acabar el scroll, y que las salas altas (8 con 200 líneas, 12 con 192, 20 con 184) se vean sin franjas.
- El pasillo con scroll cuesta ~1.000.000 T por vuelta en el arnés (fase 10): el scroll irá más lento que 50 Hz; **apunta si se ve a saltos o solo lento**.

### 2.6 Sonido (importante: que el VGM y `VAR_MUSIC_TIMER` no se separen)
- El MCU reproduce el `SOUNDnnn.VGM` a su ritmo; el Z80 lleva `VAR_MUSIC_TIMER` a 236 Hz sobre los fotogramas (`snd3.asm`) y las **esperas del intro dependen de él**.
- **Mirar:** en el logo (sala 76, sonido 35) y los créditos, que las escenas cambien **al ritmo de la música** (el modelo: los créditos a los 129 fotogramas ≈ 2,6 s, el mapa a los 515 ≈ 10 s, el pasillo a los 582 ≈ 11,6 s). Si la música acaba mucho antes o después de que cambie la escena, apunta los segundos y la sala: el temporizador se separa del VGM.
- Probar también: que un efecto (puerta, pasos) interrumpa y luego vuelva la música si es reiniciable, y que **parar** no deje la música colgada al cambiar de sala.
- Tras **cargar una partida** la música que sonaba empieza otra vez desde el principio (no se guarda la posición del VGM): es lo esperado.

### 2.7 Guardar y cargar (nuevo en la fase 9)
1. Entra en una sala con control del jugador (Barnett) y pulsa **SHIFT + S**: sale el diálogo de Indy3 (sala 14) con las ranuras (los nombres de las partidas ya guardadas salen en la lista).
2. Escribe un nombre y guarda en la ranura 1 (tarda **2-3 s**: 13,5 KB por el bus del MCU). Debe volver al juego.
3. Muévete / abre algo / cambia de sala y vuelve a **SHIFT + S → cargar** la ranura 1: tienen que volver la sala, la posición de Indy y los actores, el inventario y los verbos; la música del momento empieza otra vez.
4. Comprueba el nombre en la lista al reabrir el diálogo y guarda en una segunda ranura; carga una ranura vacía (debe decir que falla, sin tocar la partida).
5. **Entre dos arranques distintos** (apagar y encender) las partidas siguen en la SD: cárgalas tras un `SHIFT + R`.
- **Mirar:** que tras cargar la pantalla se repinte entera (sala, objetos, verbos, paleta) y los sprites aparezcan en 2 fotogramas, y que `SAVEnn.SAV` mida **14.943 bytes**. Un guardado de otra versión del programa o de otro `DATA.BIN` se rechaza (la carga falla sin tocar nada).
- Los puntos IQ (`saveLoadVars` con la cadena 7 / 9) **no se guardan** todavía (ver "Pendiente").

### 2.8 Sala 70 (D6: peleas)
- La sala 70 (y la 83) pueden pedir **más de 63 sprites** con las posturas de pelea (trajes 90 y 91): el programa manda los que no caben a los **sprites extra de la FPGA** (`POKE 2131`, hasta 32; reparto de delante a atrás).
- **Mirar:** si en una pelea faltan personajes o partes (peor caso: 66 de 63), si hay parpadeo de sprites en una misma línea (la FPGA tiene 12 por línea y un presupuesto de pasos), y apunta la sala y el momento. Esta parte **no se ha probado nunca en la placa**.
- Si falla: D6 dice primero `escala_N` por traje en el perfil y, si no basta, dar prioridad al ego.

## 3. Qué apuntar si algo falla
- La sala, el fotograma aproximado (o los segundos desde el arranque) y qué se hacía.
- Si hay `ERR` de la VM: el número que da `PRINT USR` al salir.
- Para el vídeo: si es un fallo de **imagen** (gráfico), de **sprites** o de **color** (la paleta de 16 con el marrón del EGA y los `roomOps` 2 y 4 no se han visto en la placa).
- El estado de `STAT` (LED) y de la SD (que `SAVEnn.SAV` se cree y mida 14.943 bytes).

## 4. Pendiente (conocido, no es un fallo nuevo)
- Puntos IQ de Indy3 (`saveLoadVars` 7 y 9): sin fichero.
- `oldRoomEffect` (barridos y disolvencias de pantalla): el cambio de sala es un corte.
- Texto: sin partir por palabras, solo mayúsculas, sin colores por verbo (hover) ni verbos atenuados.
- El texto suelto de `print` (ranura 1) no se pinta.
- Rendimiento (fase 10): vueltas de 330.000 a 1.000.000 T con scroll u objetos animados (presupuesto 325.000).
