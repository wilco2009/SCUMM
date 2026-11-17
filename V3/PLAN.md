# Plan: intérprete SCUMM v3 (Indy3 EGA) para el Z80

Fecha: 2026-11-11. Base: `ESTUDIO_SCUMMV3.md`; las cifras y los porqués están allí.
Primer juego: **Indiana Jones and the Last Crusade EGA** (DOS, inglés; el castellano también está en disco). Loom EGA usa el mismo formato y vendrá después, cuando haya ficheros.

## Reglas para todas las fases

- **La referencia es ScummVM** (`C:\ClaudeCode\scummvm_src\engines\scumm`), clase `ScummEngine_v3old`: `script_v5.cpp` + `script_v4.cpp` + `script_v3.cpp`, `actor.cpp` (`Actor_v3`), `boxes.cpp`, `room.cpp`, `object.cpp`, `string.cpp` y `players/player_v2*.cpp`.
  No suponer reglas: si algo no está claro, se lee ScummVM.
- **El código Z80 no puede pasar de `$8000`**. Al acabar cada fase, el montaje imprime el final del residente y el tamaño de cada overlay.
- **Nombres de fichero de la SD sin "_"**.
- **Sin regresiones en v2:** `V2/ENGINE/test/build_test.sh` (Maniac y Zak) tiene que seguir pasando. **Solo se pasa si la fase toca algo de `SCUMM/V2`** (o lo común en la fase 9): `V3/ENGINE` es una copia y no afecta a v2 (usuario, 2026-11-14).
- **Pruebas (usuario, 2026-11-16; sustituye a todo lo anterior sobre pruebas):** durante el día **solo pruebas específicas del cambio** (p. ej. un `build_boot.sh` corto con los sucesos que tocan lo cambiado, `build_test.sh` con 1-3 salas, `check_hr.py` en la sala afectada). **La prueba larga se pasa una vez al día, por la noche**: `ENGINE/test/pruebas_noche.sh`, lanzada a las 02:00 por la tarea de Windows "SCUMM v3 pruebas noche" (núcleo, arranque, Barnett, guardar/cargar, actores, objetos, mutaciones y v2). Resumen en `ENGINE/test/build/noche/AAAA-MM-DD.txt`: cada sesión lo lee al empezar. Ninguna sesión pasa la batería completa ni `mutaciones.py` de día salvo que el usuario lo pida. **Límites (usuario, 2026-11-17): ninguna prueba de día pasa de 30 minutos, y la noche entera no pasa de 3-4 horas** (la tarea la corta a las 4 h; cada paso de `pruebas_noche.sh` tiene su tope y su presupuesto escrito en la cabecera del guion; v2 solo si cambia `V2/` o `COMMON/`, un juego por noche). **Y solo se prueba lo relacionado con lo que se ha tocado, también de noche** (usuario, 2026-11-17): tabla de fichero a pruebas; la noche pasa solo las pruebas (y las mutaciones) de los ficheros cambiados desde la última noche buena; si no ha cambiado nada, no pasa nada. **La batería completa (`pruebas_completas.sh`) se conserva solo para el final, para dar el juego por bueno, y con permiso del usuario.** Una prueba que no quepa se recorta; nunca se alarga el presupuesto sin preguntar.
- **No hay commit** sin que lo pida el usuario. Se trabaja en `main` del repo `SCUMM`, sin worktrees.
- **Primero el modelo de Python y luego el Z80**, como en v2: el Z80 se compara con el modelo por trazas en el arnés.
- **Pruebas en la placa: las hace el usuario.** La sesión deja `compila_scumm.bat` listo y dice qué probar.
- Herramientas que ya existen (estudio): `V3/TOOLS/scumm3res.py` (recursos), `scumm3dis.py` (decodificador, validado con descumm), `scumm3vm.py` (VM de medida), `medir_*.py`, `analiza.py`.

## Decisiones (D1 y D2 confirmadas por el usuario el 2026-11-12)

| | Decisión | Propuesta |
|---|---|---|
| D1 | ¿Fuentes del motor v3 compartidos con v2 (`IF V3`) o copia? | **CONFIRMADO: copia**: `V3/ENGINE` parte de una copia de `V2/ENGINE`. Así v2 no puede romperse y el residente de v3 no carga con lo que solo usa v2. Lo común y estable (`mcu.asm`, `loader.asm`, `dp_cache.inc`, `hr.asm`, `snd.asm`, `mouse.asm`) se mueve a `SCUMM/COMMON/` en la fase 9, cuando ya no cambie. |
| D2 | ¿Protección anticopia (sala 92)? | **CONFIRMADO: como en el original**: con ratón se contesta. Opción `proteccion = 0` en el perfil del juego para saltarla poniendo `Var[57] = 1`, como hace el script local 204 al acertar. |
| D3 | Pantalla HiRes de 192 líneas | 16 líneas de mensajes arriba, 128 de sala y 48 de interfaz (6 filas: frase, verbos e inventario, con la fuente de 6 px del v2). Escenas de 184-200 líneas: con `SetScreen` de 200, ventana de 192 con el scroll vertical por hardware (fase 3 del scroll, ya sintetizada). Si no se ha probado en la placa, se recortan las 8 líneas de arriba. |
| D4 | Segundo overlay | Página física **49** para el overlay B (la 50 es la del A y la 63 es del depurador). B lleva los manejadores con subopcodes, `expression`, `stringOps` y la frase. A sigue con interfaz, cámara, actores, sonido, oscuridad, guardar y ratón. Se cambia de página con `OUT`, nunca leyendo la SD en mitad de una vuelta. |
| D5 | Scripts de más de 6 KB (solo el 95, 6.711 B) | **RESUELTA en la fase 3**: páginas solapadas (la página k lleva los bytes `[k * 4096, k * 4096 + 6144)`, `pack_data3.add_big`) y comprobación de franja al empezar cada instrucción (`es_loop`/`es_cross`, 21 T). Ver `FASE3.md`. |
| D6 | Más de 64 sprites (4-6 actores en el 9 % de fotogramas) | Primero, `escala_N` por traje en el perfil (como Zak). Si no basta, los sprites extra de la FPGA (`POKE 2131`, hasta 127). |

## Fases

Cada fase dice el modelo que la hace, qué entrega y cuándo está terminada. Las fases Sonnet van de una en una si tocan los mismos ficheros.

### Fase 0 (Sonnet): arnés del v2 en marcha — HECHA 2026-11-11
- **Causa del atasco:** `test/build/sd/DATA.BIN` era de la versión 1 del formato (del 21-oct); `load_data` (`loader.asm`) exige la 2 → `tx_nodata` → `sc_fatal` → `sc_wait_key`, que espera una tecla en `swk1` (`$742E`) llamando a `sc_scan` (`$74xx`). No faltaba ROM, overlay ni `.B81`. Los `.GFX` de esa carpeta también eran viejos.
- **Arreglo:** carpeta nueva `V2/ENGINE/test/build/sdzak/` (ignorada por git) con `DATA.BIN` regenerado (`pack_data.py ... --game games/zak.cfg --sounds preview_zak_hr/snd`), los `ROOMnn.GFX` de `preview_zak_hr/gfx` y `SND/`. `test/build/sd` no se ha tocado. Ya no hace falta `ZX81_ROM`.
- **Arnés:** `test_scumm.cpp` recibe `TS_VM=1` (con `TS_PROF` y `TS_T=1`): cuenta las instrucciones de script ejecutadas y los T de cada una (decodificación + manejador, con el prólogo de `exec_script`, restando las ejecuciones anidadas), por opcode. Además `TS_PROF` imprime ahora la **media** de T por vuelta. Pasos exactos en `V2/ENGINE/README.md` ("Medir").
- **Medido** (T-estados puros del Z80, sin esperas; 65.000 T = un fotograma de 50 Hz a 3,25 MHz; las vueltas son las de `main_loop`):

| | A: arranque, sala 46 (fot. 100-400) | B: Zak camina y la cámara hace scroll, sala 1 (300-1000) | C: B con 5 actores en la sala (700-1000) |
|---|---|---|---|
| T por vuelta: media / mediana / p90 / máximo | 114.499 / 103.405 / 143.781 / 333.764 | 130.931 / 71.167 / 242.217 / 658.408 | 149.584 / 80.536 / 275.257 / 726.975 |
| Instrucciones de script por vuelta: media / mediana / p90 / máx. | 11,8 / 12 / 14 / 17 | 13,7 / 8 / 15 / 111 | 12,2 / 5 / 13 / 111 |
| **T por instrucción de script**: media / mediana / p90 / p99 | 1.102 / 757 / 1.478 / 1.640 | 1.785 / 1.213 / 1.573 / 19.037 | 1.881 / 1.213 / 1.573 / 19.351 |
| T de la VM sobre el total de la vuelta | 12 % | 19 % | 15 % |

  (C es sintético: `TS_POKE` pone en la sala 1 a los actores 2, 3, 4 y 7 con sus trajes; se dibujan los 5. Zak no tiene una sala con tantos actores al alcance de un recorrido corto.)
- **Lo que dice la medida:**
  - **Una instrucción de script cuesta 750-1.500 T, no 150-400** (mediana 757-1.213). El coste fijo del despachador (prólogo de `exec_script`, tabla, `decode`) es ~600-700 T: `breakHere` 678 T y `jumpRelative` 686 T no hacen nada más; con una variable y una palabra (`isEqual`) son ~1.360; `move` 1.213, `increment` 957, `getRandomNr` 1.567. Fuera de ahí hay pocas instrucciones muy caras: `drawObject` 18.600-23.200, `getDist` 15.500, `startSound` 10.500, `print`/`printEgo` 70.000-89.000.
  - Con ~12 instrucciones por vuelta la VM gasta 15.000-25.000 T por vuelta; **cada 100 instrucciones de script por vuelta cuestan unos 120.000 T**. El presupuesto de la fase 10 (325.000 T) da para ~270 instrucciones por vuelta si no hiciera nada más; en la práctica menos, y los manejadores caros (arriba) no se pueden contar como medios.
  - Recorrer las ranuras cuesta aparte (`slot_addr`, `ra_loop`, `ra_next`, `load_slot`, `update_ptr`): ~5 % de la vuelta, unos 6.000 T, tenga o no scripts. Con más ranuras en v3 sube.
  - **La VM es el 12-19 % de la vuelta.** El resto es overlay y vídeo: interfaz `hr_ui` (`hu_cmp`, `hu_next`: 16-18 %), dibujo de actores (`acd_cell`: 15 % en A, ~2,5 % con 5 actores quietos), scroll (`hs_l`, `hfc2`, `fo_rec`, `hr_busy`: las vueltas de 600.000-730.000 T son de scroll de la cámara) y objetos (`dro_loop`, `obj_drawn`, `hou_*`).
  - Para el estudio de v3: usar ~1.200 T por instrucción típica (no 150-400) y revisar las cuentas de instrucciones por vuelta de Indy3 con esa cifra; reducir el coste fijo del despachador (prólogo y `decode`) es lo que más rinde en la VM.
- Efecto en v2: ninguno. Solo cambia el arnés de PC (`test_scumm.cpp`); no se ha tocado el motor Z80 ni `build_test.sh`.

### Fase 1 (Sonnet): modelo de referencia v3
- `V3/TOOLS/vmmodel3.py`, a partir de `scumm3vm.py`, con la misma forma que `V2/TOOLS/vmmodel.py` + `vmgame.py`:
  - núcleo determinista;
  - llamadas al anfitrión anotadas en la traza (`H`, `E`, `D`);
  - `World` que empaqueta lo que necesita el arnés;
  - escenarios (`SCRIPT`, `LOADROOM`, `OBJ`, `INPUT`, `FRAMES`).
- Quitar de `scumm3vm.py` lo que era solo de medida, y dejar en el modelo la semántica de ScummVM completa para los 96 opcodes.
  Hoy son aproximados `animateActor` (ya corregido), los mensajes, `getDist`, `actorFromPos` y `findObject` sin la cadena de padres.
- **La caminata se queda aproximada en esta fase**; la exacta es la fase 6.
- **Hecho cuando:** el arranque llega al pasillo (sala 1) igual que hoy y `vmmodel3.py scenarios` genera trazas reproducibles con varias semillas.

### Fase 2 (Sonnet): conversores de datos (PC)
1. **`lfl3hr.py`**: salas v3 a `ROOMnn.GFX` con el formato de `V2/TOOLS/LFL2HR.md`. La imagen sale de `scumm3res.Room.image()` y la conversión a 8x1 se reutiliza de `lfl2hr.py`.
   - Alturas de 128 a 200 líneas: añadir el alto al formato si hoy es fijo en 128.
   - Máscara de profundidad: la de v3 viene por franjas (`decode_mask`), no por columnas.
   - Objetos con imagen: los que no la tienen comparten OBIM (ver `object_image`).
2. **`costume3.py`** (o una opción de `costume2.py`): blobs de trajes con la numeración de v3 (inicio 1, andar 2, quieto 3, hablar 4/5) **y las posturas especiales** que piden los scripts (`animateActor` con fotograma 6-30 y `actorOps` 4/5/6/14).
   Primero hay que contar por traje qué fotogramas se piden: el actor del `animateActor` va en el primer parámetro, y se cruza con el traje que le pone `actorOps`.
3. **`pack_data3.py`**: `DATA.BIN` de v3. Hay que agrandar las tablas:
   - 1.000 objetos, con dueño, estado y 3 bytes de clases;
   - salas hasta la 99;
   - trajes hasta el 128;
   - scripts globales y, por sala, los locales (id ≥ 200).
   La cabecera lleva versión 3. El script 95 queda según D5.
4. **Sonido**: `sound2vgm.py` con el índice de v3. El formato es el de v2 y los 73 sonidos ya se convierten. Falta el `VAR_MUSIC_TIMER` de v3, que en `Player_V2Base::getMusicTimer` sale de `_music_timer`, no del canal 0.
- **Hecho cuando:** salen todas las salas, trajes y sonidos sin errores, con PNG de comprobación de unas cuantas salas y trajes, y `DATA.BIN` se puede leer de vuelta.

### Fase 3 (Opus): mapa de memoria y núcleo de la VM
- Copiar `V2/ENGINE` a `V3/ENGINE` (D1) y montar el segundo overlay (D4).
- **Decodificador de operandos de 16 bits** en `vm_core`:
  - variable u16 con 0x8000 (bit dentro de una variable: `(v >> 4) & 0xFF` y el bit `v & 0xF`), 0x4000 (local de la ranura, 0-15) y 0x2000 (índice indirecto con otra palabra);
  - resultado con indirección;
  - un código nuevo de operando para las listas (`getWordVararg`);
  - locales: 16 palabras por ranura.
- `gen_vmtables3.py`: la tabla de 256 opcodes sale de `scumm3dis.py`, igual que la de v2 sale de `scummdis.py`.
- Variables 0-255 (Indy3 usa hasta la 253), con los números de `ScummEngine::setupScummVars` en `vars_v3.inc`.
- Arnés `test/test_vm.cpp` y `build_test.sh` para v3, comparando con `vmmodel3.py`.
- **Hecho cuando:**
  - el núcleo (control, variables, scripts, retardos, `cutscene`/`override`, `freeze`, `expression`) pasa la comparación de trazas con escenarios del juego real;
  - el residente acaba antes de `$8000` y hay sitio apuntado para las fases siguientes;
  - D5 está resuelta.
  - **El despachador cuesta menos que el de v2.** La fase 0 midió un coste fijo de 600-700 T por instrucción (prólogo de `exec_script`, tabla y `decode`) y unos 1.200 T de mediana.
    En las salas 20 y 28 del castillo, Indy3 ejecuta 112-122 instrucciones por vuelta: con esa cifra se pasa del presupuesto con scroll. Objetivo: ≤ 400 T de coste fijo, medido con `TS_VM=1`.

- **HECHA 2026-11-12** (Opus): resultado completo en `V3/FASE3.md`. Resumen:
  - `V3/ENGINE` es la copia de `V2/ENGINE`; el nucleo nuevo es `vm_core.asm` + `vm_ops.asm` + `arith32.asm`, el overlay B es `ovlb.asm` (pagina 49) y el montaje de pruebas
    `vm.asm`. `scumm.asm` de v3 aun no ensambla (capa de juego de v2): lo arregla la fase 5.
  - Mapa de memoria completo en `FASE3.md`: el estado de la VM llena el bloque 7 (variables, estado/dueno/clases de 1.000 objetos, SCRDIR, ranuras, 16 locales por ranura,
    pilas); las tablas frias (ROOMDIR, ODIR, OBJROOM, COSTDIR) van a la pagina fisica 15 y se leen con `cold_rd`.
  - Despachador por tabla partida (`disp_lo`/`disp_hi`) y lectura de operandos en el manejador; decodificador generico (`decode`) para lo demas, con la especificacion como
    datos (`scumm3dis.SPEC`, comprobada contra el `Decoder` en las 20.219 instrucciones del juego).
  - D5 resuelta: paginas solapadas (la pagina k lleva `[k * 4096, k * 4096 + 6144)`) y comprobacion de franja al empezar cada instruccion.
  - Modelo en modo nucleo (`vmmodel3.CoreVM`, orden `scenarios-core`) y arnes nuevo con `DATA.BIN` como mundo.
  - Cifras: trazas **1.485/1.485 iguales** (todas las salas, locales, objetos, globales y D5); residente del nucleo **`$4200-$512F` (3.887 B)**, libres **11.985 B** hasta `$8000`
    (FASE3.md reparte ese sitio entre las fases 4-8: queda ~1 KB de margen, asi que lo nuevo va al overlay B); tablas `$8000-$869F`; overlay B 286 B; bloque 7 libre 445 B.
    **Coste fijo del despachador 164 T** hasta el manejador (194 con la vuelta), frente a 600-700 de v2; `move` 614 T (v2 1.213), `isEqual` 797 (~1.360).
  - v2 con Maniac sigue pasando (2.912 iguales). Con Zak, `V2/ENGINE/test/build_test.sh` falla en el modelo de v2 (`operando J en el anfitrion`) **desde antes de esta fase**.

### Fase 4 (Sonnet): manejadores
Como se prueba cada manejador nuevo (lo monto la fase 3; `V3/FASE3.md`):
1. **Modelo:** el nombre pasa a `vmmodel3.CORE_OPS` (deja de salir al anfitrion). Si toca estado que aun no esta en el resumen, se anade a `CoreVM.digest` (p. ej. `O=` con
   el crc de estados, duenos y clases, `A=` con `Actor.pack()`, `C=` la camara: los mismos campos que `VM.game_digest`) y el arnes (`test/test_vm.cpp`, `digest()`) calcula
   lo mismo desde la memoria del Z80. Los sucesos (`E n [...]`) van por el puerto `$F2`, como en v2.
2. **Tabla:** en `V3/TOOLS/gen_vmtables3.py`, `NATIVE` (el manejador lee sus operandos: `rd_vb1`, `rd_vw2`, `rd_res`...; lo mas rapido) o `SPEC_HANDLERS` (empieza con
   `call decode` y usa `ARGS`/`ARGN`/`RESV`/`JTGT`, como los de v2; el resultado se escribe con `set_res`, no con `write_var` de un byte).
3. **Z80:** residente (`vm_ops4.asm`, incluido desde `vm.asm`) solo si es de cada instruccion o de cada fotograma (queda ~1 KB de margen en el residente, `FASE3.md`); si no,
   en `ovlb.asm`: entrada en su tabla de saltos y en el residente `h3_x: ld hl,OVB_X / jp call_ovb` (como `h3_expression`). Dentro de B no se puede mapear otra cosa en el
   bloque 0: las tablas frias se leen con `cold_rd` (residente).
4. **Prueba:** `sh test/build_test.sh` (todas las salas) sin diferencias, y `TS_VM=1` para ver lo que cuesta. Antes de dar la fase por hecha, mutaciones (adaptar
   `test/mutaciones.py` de v2).
- **4a.** Los opcodes de "misma semantica" (`compara_bytecode.py`, clase `codif`) que no son nucleo (38): llevar los manejadores de v2 (`game.asm`, `walk.asm`, `input.asm` de
  `V3/ENGINE`, copia de v2) a la lectura de operandos nueva. Por grupos, cada uno con su estado en el resumen:
  - sonido (`startSound`, `startMusic`, `stopSound`, `stopMusic`, `isSoundRunning`): sucesos `E 1-4`, `VAR_LAST_SOUND`;
  - objetos (`getObjectOwner`, `setOwnerOf`, `setObjectName`): `O=` e inventario `I=`;
  - camara (`setCameraAt`, `panCameraTo`, `actorFollowCamera`): `C=`;
  - actores sin caminar (`putActor`, `putActorInRoom`, `putActorAtObject`, `getActor*`, `animateActor`, `faceActor`, `actorFromPos`, `getClosestObjActor`, `getDist`,
    `findObject`): `A=`;
  - sala (`loadRoom`, `pseudoRoom`, `lights`, `setBoxFlags`) y `saveLoadGame`, `waitForSentence`: necesitan `startScene` y la cola de frases (fase 5): se dejan para ella;
  - caminata (`walkActorTo`, `walkActorToObject`, `walkActorToActor`, `waitForActor`): con la fase 6.
  - **HECHA 2026-11-13** (Sonnet `scumm3-f4a`, terminada por Opus): 27 opcodes mas en el nucleo (sonido 5, objetos 3, camara 3, actores 16). `findObject` se queda en el
    anfitrion (necesita los objetos de sala de la fase 5).
    - Modelo: `CoreVM.digest` con `A=` (actores, `Actor.pack()` = el registro de 64 B del Z80), `O=`, `I=`, `N=` (nombres nuevos), `M=` (mensaje y sonido) y `C=` (camara);
      ordenes de escenario `OWNER`, `STATE`, `CLASS`, `INV` y `ACTORSET`; `NUM_NEW_NAMES = 50` (ScummVM v4). `actorFollowCamera` con un actor fuera de la sala sale al
      anfitrion (`startScene` es de la fase 5).
    - Z80: los manejadores van en el overlay B (`ENGINE/ovb4.asm`, etiquetas `b_<nombre>`); en el residente todos entran por `h3_ovb` y B los reparte por el opcode
      (`ovbtab.inc`, generada por `gen_vmtables3.py` desde `OVB_HANDLERS`). Memoria: actores en `$8B00`, nombres nuevos en `$8E40`, el resto en el bloque 7 (`FASE3.md`).
    - Marcado `FASE5`/`FASE6` en `ovb4.asm` lo que espera a una sala cargada: `obj_index` (sin objetos de sala), `getObjectXYPos` (`putActorAtObject` con un objeto de sala
      da `E_BADOBJ`), `adjust_xy` con cajas, la anchura de un objeto de sala.
    - Cifras: trazas **1.484/1.484 iguales** (todas las salas); residente `$4200-$51C7` (**11.832 B libres**); overlay B **3.328 de 8.192 B**; bloque 7 libre 228 B.
      T medidos (`TS_VM=1`): `getActorX` 1.468, `getActorY` 1.514, `getActorRoom` 1.086, `getActorMoving` 1.278, `animateActor` 1.243, `putActor` 2.180, `getDist` 2.688,
      `startSound` 797, `stopSound` 675, `getObjectOwner` 937, `setOwnerOf` 9.466, `setObjectName` 11.609, `actorFollowCamera` 5.766 (con el salto al overlay B: unos 200 T).
    - Mutaciones: `ENGINE/test/mutaciones.py` reescrito para v3 (nucleo y 4a, escenarios de las salas 1, 15, 20, 28, 46 y 70): **24 de 28 detectadas**. Sin detectar, por caminos que
      los scripts de Indy3 apenas recorren: indice `0x2000` mayor de 7, `stopScript` de un script que esta en la pila de anidados, `divide` con los dos negativos y cadenas con
      el codigo `$FF 8`. Para cubrirlos haria falta un script sintetico (como `vmsynth.py` de v2): queda para la fase 10. Los escenarios del nucleo llevan ahora un fotograma con
      `delta` 40 y `VAR_MUSIC_TIMER` distinto de 0 (las dos mutaciones que antes se escapaban por eso).
    - Un fallo encontrado al cerrarla: `getActorRoom` leia siempre el actor 1 (`is_act13` deja 1 en A).
- **4b.** Los 17 que cambian y los 20 nuevos, en el overlay B:
  - con subopcodes: `actorOps`, `verbOps`, `roomOps` (parámetros antes del subopcode), `cursorCommand`, `resourceRoutines`;
  - `print`/`printEgo` (`decodeParseString` de v5), `stringOps`, `setClass`/`ifClassOfIs` (24 bits, con la traducción de clases de `GF_SMALL_HEADER`);
  - `startObject`, `setState`/`ifState`/`ifNotState` de 8 bits, `drawObject` en x, y (`stopObjectScript` y `freezeScripts` ya estan: nucleo de la fase 3);
  - `pickupObject` v4, `saveLoadVars` (puntos IQ: de momento sin fichero), `saveRestoreVerbs`, `oldRoomEffect`, `drawBox`, `systemOps`.
  - y los nuevos que no tienen subopcodes: `findInventory`, `getInventoryCount`, `getVerbEntrypoint`, `getStringWidth`, `getActorWidth`, `getAnimCounter`, `isActorInBox`,
    `doSentence`, `loadRoomWithEgo` (estos dos con la fase 5).
  - Donde: todos en `ovlb.asm` (B tiene 7,9 KB libres; estimado ~3,5 KB). Los de lista (`actorOps`, `verbOps`, `print`, `setClass`...) leen sus subopcodes a mano con los
    lectores del residente (`rd_vb1`... sobre el `OPC` que dejan): la especificacion de `scumm3dis.SPEC` dice exactamente que lee cada uno.
- **Reparto de la 4b (2026-11-13, tras la 4a):** quedan 40 opcodes fuera del nucleo. Van en dos sesiones, una detras de otra (tocan los mismos ficheros):
  - **4b-1** (no necesitan sala ni mensajes): `actorOps`, `verbOps`, `saveRestoreVerbs`, `cursorCommand`, `stringOps`, `getStringWidth`, `setClass`, `ifClassOfIs`,
    `setState`, `ifState`, `ifNotState`, `getActorWidth`, `findInventory`, `getInventoryCount`, `roomOps`, `resourceRoutines`, `lights`, `oldRoomEffect`, `drawBox`,
    `systemOps`, `saveLoadVars`, `saveLoadGame` (22). Los que en el modelo completo son sobre todo anfitrion (`roomOps`, `resourceRoutines`, `lights`, `oldRoomEffect`,
    `drawBox`, `saveLoadVars`, `saveLoadGame`) pasan al nucleo con la semantica de su `o_*` de `vmmodel3.py`: lo que hacen en variables o estado y su linea `H` con los
    argumentos de ese `o_*` (no los de `run_spec`). Resumen nuevo: `U=` (userPut y cursor), verbos y cadenas.
    - **HECHA 2026-11-13** (Sonnet): los 22 en el nucleo, en el overlay B (`ENGINE/ovb4b.asm`, etiquetas `b_<nombre>`; `OVB_HANDLERS` en `gen_vmtables3.py`).
      Por grupos: estados y clases (`setState`, `ifState`, `ifNotState`, `setClass`, `ifClassOfIs`: clases de 24 bits con la traduccion de `GF_SMALL_HEADER`);
      inventario (`findInventory`, `getInventoryCount`, `getActorWidth`); cadenas (`stringOps`, `getStringWidth`); cursor y verbos (`cursorCommand`, `verbOps`,
      `saveRestoreVerbs`); `actorOps`; sala y recursos (`roomOps`, `resourceRoutines`, `lights`, `oldRoomEffect`, `drawBox`, `systemOps`, `saveLoadVars`, `saveLoadGame`).
      `roomOps`, `lights` y `cursorCommand` leen con `decode` (spec) y arreglan `ARGS` (la traza del modelo pone el subopcode primero); `oldRoomEffect` y `drawBox` van por el
      anfitrion generico (`HOST_CORE`); el resto lee a mano.
      - **Modelo:** `CORE_OPS` +22. Resumen nuevo: `U=` (`_userPut`, `_cursor.state`, `main_top`, `main_h`), `W=` (crc de los 36 verbos con su nombre), `T=` (crc de las cadenas)
        y `P=` (nombres de actor). Lo que hace el Z80 con memoria fija pasa a ser limite del modelo (`vmcommon3.py`; error `E_RANGE`): `NUM_VERBS` 36 (la ranura 0 es de
        trabajo, como en ScummVM; el arranque de Indy3 llega a 30), `NUM_STRINGS` 32 ids, `STR_HEAP` 480 B en total y `MAX_STRLEN` 255 (Indy3: 8 vivas, 355 B), ids y `saveid`
        de verbo 0-255, clases de 24 bits, campos de un byte de actor y verbo guardados en un byte. `verbOps` 20 (nombre desde una cadena) da `E_BADSUB`: el nombre de un
        verbo o de un actor es un puntero (pagina y direccion) al texto del script, no una copia; Indy3 no lo usa. `systemOps` 1 y 3 dan `E_HALT` (12) en modo nucleo (el
        Z80 vuelve de la API con ese error); `systemOps` 2 no hace nada y ya no sale al anfitrion. `actorOps` 2 con el actor en movimiento (`calcMovementFactor`) da
        `E_BADOP` en los dos: es de la fase 6.
      - **Memoria** (`FASE3.md`): nombres de actor, verbos y monton de cadenas en el hueco de `ODIRBUF` (bloque 4); cursor y tablas de cadenas en el bloque 7. Quedan
        **187 B** en el hueco y **122 B** en el bloque 7: la fase 5 no cabe sin mover OBJCLS a una pagina fria (ya estaba previsto).
      - **Prueba:** nueva orden de escenario `CODE <hex>` (bytecode como script global 199; una pagina de datos libre por `CODE`) y `TOOLS/vmsynth3.py`, que genera 1.200
        scripts al azar por semilla con los 22 opcodes y sus subopcodes (parametros directos y por variable): recorren lo que Indy3 no toca (`copyString`, `createString`,
        `roomOps` 7-16, `actorOps` raros...). `build_test.sh` los anade a los de las salas. Cifras: ver la tabla Estado.
      - **Mutaciones:** `mutaciones.py` +17 (una a tres por grupo), todas detectadas: **41 de 45** (las 4 sin detectar son las mismas de la 4a: indice `0x2000` > 7,
        `stopScript` de un anidado, `divide` con los dos negativos y `$FF 8` en cadenas).
      - **T medidos** (`TS_VM=1`, media exclusiva con el despachador; mezcla de escenarios de sala y sinteticos): `setState` 1.014, `ifState` 1.104, `ifNotState` 948, `setClass`
        1.818, `ifClassOfIs` 1.812, `findInventory` 6.338, `getInventoryCount` 5.937 (recorren las 80 ranuras), `getActorWidth` 993, `stringOps` 6.839 (desplaza el monton),
        `getStringWidth` 1.547, `cursorCommand` 1.567, `verbOps` 4.926, `saveRestoreVerbs` 22.382 (recorre hasta 256 verbos), `actorOps` 2.646, `roomOps` 3.065,
        `resourceRoutines` 872, `lights` 1.795, `oldRoomEffect` 1.109, `drawBox` 3.105, `systemOps` 539, `saveLoadVars` 1.821, `saveLoadGame` 1.016. Los de inventario y
        `saveRestoreVerbs` son lo primero que mirar en la fase 10 (los sinteticos los cargan mas que el juego).
  - **4b-2**: `print` y `printEgo` (`decodeParseString`, `actorTalk`, `displayDialog` en cada fotograma, sucesos `E 5`): el mensaje entra en el fotograma de `CoreVM`.
    - **HECHA 2026-11-14** (Sonnet): los dos en el nucleo, en el overlay B (`ENGINE/ovb4c.asm`: `b_print`, `b_printEgo`, `convert_all`/`cm_run` (convertMessageToString recursivo), `actor_talk`,
      `display_dialog`); en el residente solo `talk_frame` (`vm_core.asm`: `talk_delay -= delta` y salto a `display_dialog` por `call_ovb` si hay mensaje y no queda espera) y `MSGBUF`.
      Detalle y limites del Z80 en `FASE3.md` ("Fase 4b-2").
      - **Modelo:** `CORE_OPS` +2. `CoreVM.step_frame` hace ahora `talk_delay`, `display_dialog` y `VAR_HAVE_MSG` como `VM.step_frame`. Resumen nuevo `X=` (`use_talk_anims`, `msg_count`, posicion en el bufer,
        `charset_color`, crc del bufer y de los valores por omision de las 4 ranuras de texto). Limites que pasan al modelo (`vmcommon3.py`): `MSG_MAX` 320, `MSG_DEPTH` 4, variable de mensaje con 0x2000 = `E_RANGE`,
        `talk_delay` de 16 bits, color de un byte, lecturas con ceros mas alla del final del mensaje. **FASE5:** el nombre de un objeto de sala o de inventario (`FF 6`) sale vacio hasta que haya OBCD.
      - **Prueba:** `vmsynth3.py` genera `print`/`printEgo` (4 de 16 generadores) con todos los subopcodes, mensajes con todos los codigos `$FF` (1-14, invalidos, `@`, `$FE`), variables normales, locales, bits y
        `0x2000`, nombres de verbo, actor y cadena (anidados), mensajes muy largos y una cadena que se cita a si misma; los escenarios sinteticos corren de 2 a 70 fotogramas (delta 1-15) para recorrer `displayDialog`.
        Cifras en la tabla Estado.
      - **Mutaciones:** `mutaciones.py` +9 (`displayDialog`, `convertMessage`, `emit_dec`, `actorTalk`, `print` x3, `talk_frame`), **las 9 detectadas**: **50 de 54** (las 4 sin detectar son las mismas). Nuevo segundo argumento:
        `python mutaciones.py 1,15 "print|talk_frame"` solo corre las que contengan esas palabras.
      - **T medidos** (`TS_VM=1`): `print` 8.360 T de media y `printEgo` 14.104 (con la conversion y el primer `displayDialog`; v2: 70.000-89.000); `talk_frame` sin mensaje 75 T (133 con `talk_delay`), con mensaje
        esperando 198, y `displayDialog` escribiendo una linea hasta ~4.000.
      - **Overlay B lleno (248 B libres) -> overlay C abierto el mismo dia** (pagina fisica 48; `ovlc.asm`, `ovc1.asm`, `call_ovc`; detalle en `FASE3.md`, "Overlay C"). Salieron de B a C `roomOps`, `resourceRoutines`, `lights`,
        `systemOps` y `saveLoadGame`: B 7.680 B (~680 libres), C 1.024 B; la fase 5 pone sus manejadores en C. La fase 9 tiene que quitar la pagina 48 de la cache de paginas.
  - Con la fase 5 (necesitan la sala cargada o la cola de frases; **hechos, ver la fase 5**): `doSentence`, `startObject`, `getVerbEntrypoint`, `drawObject`, `pickupObject`, `findObject`,
    `isActorInBox`, `loadRoom`, `loadRoomWithEgo`, `pseudoRoom`, `setBoxFlags`, `waitForSentence`. Con la fase 6: `walkActorTo`, `walkActorToActor`, `walkActorToObject`,
    `waitForActor`.
- Cada manejador se prueba con escenarios contra el modelo (receta de arriba).
- **Hecho cuando:** la comparación de trazas pasa en los 96 opcodes y las mutaciones (`mutaciones.py`) se detectan.

### Fase 5 (Sonnet): salas, objetos y frases
- `startScene` de v3:
  - scripts de salida y entrada globales (`VAR_EXIT_SCRIPT`, `VAR_ENTRY_SCRIPT` y sus 2);
  - matar los scripts locales y de sala;
  - ocultar actores y mostrarlos al entrar.
- Scripts locales de sala, objetos de la sala con verbos en ternas (`getVerbEntrypoint` +17), inventario como copias del OBCD, `whereIsObject`, `findObject` con la cadena de padres.
- Frases (`doSentence`, `checkAndRunSentenceScript` con argumentos en locales) y `runInputScript` con `VAR_VERB_SCRIPT`.
- Pantalla con el diseño D3: `hr.asm` con la sala de 128 líneas a partir de la fila 2.
- **Hecho cuando:** en el arnés el juego arranca, pasa el logo y los créditos y llega al pasillo con la imagen correcta (`check_hr.py`), con las trazas iguales a las del modelo.
  **La fase 5 no lo cumplio (el programa completo seguia siendo la copia de v2): lo cumple la fase 5b, abajo en la tabla Estado y en `FASE3.md`.**

- **HECHA 2026-11-14** (Sonnet, sesión aparte; sin commit): `startScene`, los objetos de sala, los nombres de objeto, la cola de frases y los 12 opcodes del alcance (`loadRoom`,
  `loadRoomWithEgo`, `pseudoRoom`, `startObject`, `getVerbEntrypoint`, `drawObject`, `pickupObject`, `findObject`, `isActorInBox`, `setBoxFlags`, `doSentence`, `waitForSentence`),
  en el modelo (`CoreVM`) y en el Z80. Detalle, mapa de memoria y límites en `V3/FASE3.md` ("Fase 5"). Resumen:
  - **Colocación (decisión):** `OBJCLS` (3.000 B) sale del bloque 7 a la **página fría 47** (se mira por el bloque 1 con `cls_open`/`cls_close`, sin leer el script entre las dos);
    en su sitio van el blob de la sala (`RBLOB`, 1.536 B), la cola de frases (6 x 7 B), el mapa de pseudosalas (128 B) y unas variables de sala: **quedan 1.282 B libres** en el bloque 7.
    El residente gana ~360 B (los helpers que comparten B y C: `obj_index`, `wio`, `odir`, `run_inv`, `chk_actor`...: salieron de B). Los manejadores van en el **overlay C**
    (`ENGINE/ovc5.asm`, 3.840 B de 8.192: 4.352 libres); B queda con 512 libres y gana cinco puntos de entrada fijos para C (`OVB_STOPTALK/HIDE/SHOWACT/FOLLOW/PUTACT`).
  - **Modelo:** `CoreVM` carga los objetos (y las cajas) de la sala con `ROOM n [1]` y `startScene`; nuevas órdenes de escenario `LOADROOM`, `SENTENCE`, `PSEUDO` y `ACTORSET ... ign`;
    resumen nuevo `Q=` (cola de frases) y `R=` (objetos y cajas de la sala, `ego_positioned`, mapa de pseudosalas). El inventario ya no copia el OBCD: usa el de `ODIR`.
    Escenarios nuevos: `clrm` (startScene entre dos salas), `csnt` (frases reales con el script de frases de Indy3), scripts globales con sala en uso y `vmsynth3.gen_room5` (los 12 opcodes al azar).
  - **Límites que el modelo hace suyos** (`E_RANGE`): sala de `loadRoom`/`loadRoomWithEgo` fuera de 0..255, verbo de `doSentence` fuera de 0..255, `pseudoRoom` con sala 0, `drawObject` con x fuera de 0..254
    o y fuera de 0..255 (el Z80 guarda x/8 e y/8 en un byte). `findObject` lee el estado de los padres **vivo** (`OBJST`), no la copia `objs[].state` que ScummVM refresca cada fotograma
    (solo difiere si se cambia el estado y se llama a `findObject` en el mismo fotograma). La cola de frases cuenta `freeze` en un byte.
  - **Lo que sigue en la fase 6** (E_BADOP en modelo y Z80, con trazas iguales hasta el error): `adjustXYToBeInBox` con cajas (afecta a `putActor`, `showActors` y `loadRoomWithEgo` en una sala con
    cajas con un actor que no ignora cajas) y `startWalkActor` (`loadRoomWithEgo` con x <> -1). `isActorInBox` y `setBoxFlags` ya funcionan con cajas reales.
  - **Lo que sigue en la fase 7:** `runInputScript`, `checkExecVerbs` y el ratón (clics y teclas): el gancho está en `vm_frame` (entre `run_all` y la comprobación de la cola de frases).
  - **Trazas: 3.192/3.192 iguales** (88 salas, 1 semilla: 1.992 de las salas, locales, objetos, scripts globales, `clrm` (startScene), `csnt` (frases), `cfnd` (findObject), `cbox` (isActorInBox) y 1.200 sintéticos con
    `gen_room5`; el modelo da ERR 8 en ~10 % de ellos: los límites de la fase 6). Aparte, 600 escenarios de `isActorInBox` con coordenadas extremas: iguales.
  - **Mutaciones:** `mutaciones.py` +25 de la fase 5 (frases, cola congelada, `findObject`, `drawObject`, `pickupObject`, `startObject`, `getVerbEntrypoint`, `startScene`, pseudosalas, `loadRoomWithEgo`,
    `isActorInBox`, `setBoxFlags`, nombre de objeto, `getObjectXYPos` y las clases en la página fría): **72 de 77 detectadas** con las salas 1, 15 y 20 (la 20 es la que tiene cadenas de padres; el argumento de salas de
    `mutaciones.py` ahora conviene que sea `1,15,20`). Sin detectar: las 4 de siempre (índice `0x2000` > 7, `stopScript` de un anidado, `divide` con los dos negativos y `$FF 8` en cadenas) y "rechazo rápido de
    `isActorInBox` con 3 esquinas" (equivalente con las cajas de Indy3: casi todas tienen pares de esquinas con la misma x). Se retiraron las 2 mutaciones del anfitrión con resultado y con salto
    (`h_host_r`, `h_host_j`): tras esta fase ningún opcode usa esas rutas (solo `drawBox`, `oldRoomEffect` y los de caminata van por `h_host`; se pueden borrar en la fase 10).
  - **v2 sin regresiones:** Maniac 2.912/2.912 (no se ha tocado nada de `V2/`; `V3/ENGINE` es una copia y V2 no incluye nada de V3, así que no puede verse afectado). Zak no se repitió: tarda ~50 min y `V2/ENGINE` tiene cambios sin commit de otras sesiones (3.732 escenarios en vez de 3.662).
  - T (`TS_VM=1`, media exclusiva con despachador): ver `FASE3.md`.

### Fase 6 (Opus): caminata de v3
- Primero en el modelo (`vmmodel3.py`), copiando ScummVM sin aproximar:
  - `Actor_v3::walkActor`, `calcMovementFactor`, `actorWalkStep` y `updateActorDirection` de v3 (`_facingXYratio`);
  - `findPathTowardsOld` con `getGates`;
  - `getNextBox` de v3 (ternas por caja, con el WORKAROUND de la sala 46);
  - `adjustXYToBeInBox`, `getClosestPtOnBox` y `checkXYInBoxBounds` con cuadriláteros en s16, y los flags de caja.
- Después en el Z80 (`walk.asm`/`geom.asm` de v3), comparando la traza de posiciones fotograma a fotograma con el modelo.
- **Hecho cuando:** Indy cruza las salas con varias cajas (pasillo, 15 Venecia, 20 y 28 del castillo) igual que el modelo en escenarios de clics.

- **HECHA 2026-11-14** (Opus/Fable, sin commit). Detalle en `V3/FASE3.md` ("Fase 6"). Resumen:
  - **Modelo revisado contra ScummVM** funcion a funcion (`actor.cpp`, `boxes.cpp`, `script_v5.cpp`, `script_v3.cpp`, `common/rect.h`). Lo que estaba mal: la aritmetica de
    `closestPtOnLine`/`compareSlope` (es de `int` de 32 bits que desborda), `Common::Point::sqrDist` (tope de 0x1000 por eje = 0xFFFFFF), los tipos de la caminata (`xfrac`/`xAdd`
    uint16, posicion int16), `setDirection` (marca `_needRedraw` solo si cambia) y el WORKAROUND de la sala 46 (mira el recurso de la sala). Lo demas coincidia. **No hay un ScummVM
    ejecutable para comparar posiciones**: la comprobacion es la lectura del codigo y que el Z80 da las mismas trazas (riesgo que queda para la placa).
  - **Z80:** overlay nuevo **D** (pagina fisica **46**; `ovld.asm` = `geom.asm` + `walk.asm`, 4.392 B) con cuatro entradas fijas (`OVD_WALK`, `OVD_ADJUST`, `OVD_STARTWALK`,
    `OVD_CALCMF`; argumentos en `WKX`, `WKY`, `WKDIR`, `WKBOX` e IX); los cuatro opcodes (`walkActorTo`, `walkActorToActor`, `walkActorToObject`, `waitForActor`) en el overlay C
    (`ovc6.asm`); `walk_frame` en el residente (al final de `vm_frame`). Ya no queda ningun `E_BADOP` de la fase 5 (`adjust_xy`, `adjust_actor_pos` con cajas de direccion fija,
    `actorOps` 2 en movimiento, `loadRoomWithEgo` con x <> -1). Los 96 opcodes estan en el nucleo salvo `oldRoomEffect` y `drawBox` (anfitrion generico).
  - **Limites que el modelo hace suyos** (`E_RANGE`): division por cero en la geometria y velocidad 0 al andar (ScummVM se cuelga), `_stepX` > 255 (velocidad y 255), una caja que
    no existe. `closest[]` de `getGates` sin candidato vale 0 y la matriz de cajas no se lee mas alla de su final (en ScummVM, sin definir).
  - **Trazas: 3.492/3.492 iguales**; `wlk_test.py` (coordenadas extremas) 600/600. **Mutaciones: 120 de 126** (caminata: 48 de 49; sin detectar, las 5 de antes y el umbral 4 de
    `getGates`). Residente `$421E-$5578` (**10.888 B libres**), overlay B 7.680 B (512 libres), C 4.096 B (4.096 libres), **D 4.392 B (3.800 libres)**, bloque 7 **987 B libres**.
  - **T:** un paso de caminata **8.329 T** de media (max. 21.598); `walk_frame` sin nadie andando 942 T; un fotograma con cambio de tramo (puerta entre dos cajas) 134.670 T de media
    y 1.467.429 de maximo: es lo primero que mirar en la fase 10 (ideas en `FASE3.md`).
  - **Escenarios de clics:** `cwlk<sala>.<k>` (12 en las salas 1, 15, 20 y 28; 3 en las demas con cajas): un clic es `walkActorTo` del ego; el clic de verdad
    (`runInputScript`, `checkExecVerbs`) es de la fase 7. `moveCamera` y `updateObjectStates` (van tras `walkActors` en ScummVM) siguen fuera del nucleo: la camara no sigue al
    ego mientras anda hasta que alguien los lleve (5b o 7).

### Fase 7 (Sonnet): interfaz de Indy3
- Verbos colocados por el script (`verbOps`: posición, nombre, colores y tecla), línea de la frase e inventario con flechas, en las 6 filas de D3.
- Mensajes de 2 líneas arriba, con la fuente de 6 px y el color del actor.
- Cursor y ratón: `mouse.asm` ya existe en v2.
- Teclas: `VAR_CUTSCENEEXIT_KEY` (27), pausa y reinicio.
- **Hecho cuando:** en el arnés se puede jugar la primera parte (Barnett College) con clics de escenario.
- **HECHA 2026-11-15** (Sonnet, sin commit): ver la tabla Estado y `V3/FASE3.md` ("Fase 7"). Resumen: el nucleo recibe un suceso de entrada por fotograma (`INEV`; `vm_input.asm`) y el programa traduce teclado y raton a
  coordenadas de SCUMM (`in_poll`, `in_conv`); el rectangulo de un verbo es `[left, left + 8 * V_LEN)` con `V_LEN` fijado al dibujarlo (`VSZ` = 19); la pantalla de texto `UIVB` (8 x 40 de 6 px) pone la frase en la fila 1
  (**fila de arriba**: decision confirmada por el usuario) y los verbos e inventario en las 6 de abajo; los mensajes (`EV_TEXT`, `PGBUF`) en las 2 de arriba. Se corrigio el modelo: la pantalla principal mide `main_h - main_top`.

### Fase 8 (Sonnet): actores y sonido
- Sprites de los actores con los blobs de la fase 2; caché de firma como en v2.
- Posturas especiales por fotograma pedido; reparto de sprites según D6.
- Objetos animados: recomponer columnas (salas 20 y 28, unos 2 objetos por fotograma).
- Sonido: `snd.asm` con la tabla de v3 y `VAR_MUSIC_TIMER` de v3, porque las esperas del intro dependen de él.
- **Hecho cuando:**
  - el intro va al ritmo de la música;
  - en el arnés se ven bien los actores de las salas 1, 15, 20 y 28;
  - no se pasa de los sprites disponibles en las salas con 4-6 actores (32, 35, 36, 41, 43, 46, 66, 70, 72, 76, 82).
- **HECHA 2026-11-15** (Sonnet, sin commit): detalle en `V3/FASE3.md` ("Fase 8"). Resumen:
  - **Actores:** `ovd_act.asm` (overlay D, entrada `OVD_ACTORS`; variables en `ac_vars.inc`, bloque 7 `$F1BD-$F47F`): orden por y, animacion `fotograma * 4 + direccion` en el blob principal o el extra (posturas especiales 6-30) con caida al fotograma de quieto, poses con un contador por actor, cache de firma, mascara de profundidad por pixel
    (con alto de sala variable) y recorte a la ventana de la sala. Referencia en Python `TOOLS/sprites3.py`; `test/check_spr.py` la compara con los sprites del volcado.
  - **D6:** sprites extra de la FPGA como desbordamiento (`POKE 2129 = 0`, entradas en la sombra `$0000-$03FF`, `POKE 2131`; hasta 32): los actores de delante van a los 63 normales y, desde el primero que no cabe, los de detras a los extra (tienen menos prioridad: el orden se conserva). Medido: el peor caso de las 11 salas pide 4-66 sprites (la 70 y la 83 pasan de 63 con posturas de pelea). Sin probar en la placa.
  - **Objetos animados:** sin codigo nuevo (`obj_drawn` y `hr_objupd` de la 5b); comprobado con 2 cambios de estado por fotograma en las salas 20 y 28 (`check_hr.py` 0 distintos); cuestan 334.176 y 451.235 T por vuelta de media: fase 10.
  - **Sonido:** `snd3.asm` = Player_V2 (prioridad, cola, reiniciables, bucle, duraciones de la tabla) con ordenes al MCU y `VAR_MUSIC_TIMER` como `Player_V2Base` (236 Hz sobre fotogramas de 50 Hz; la 5b usaba 60). Modelo `real` en `vmgame3.py`. El intro llega al pasillo en el fotograma 582 (antes 694).

### Fase 9 (Sonnet + usuario): montaje, SD y placa
- `compila_scumm.bat` de v3. En la SD: `SCUMM\V3\SCUMM.BIN`, `SCUMM\V3\INDY3\INDY3.B81` y `SCUMM\V3\INDY3\DATA\`, sin "_".
- Guardar y cargar (`save.asm` con el estado de v3: locales, clases, inventario v3).
- Quitar de la caché de páginas la 46 (overlay D, fase 6), la 47 (OBJCLS, fase 5; lleva también la copia de la tabla de caracteres) y la 48 (overlay C) además de la 49 y la 50; cargar `ovld.bin` en la 46 y repetir los `OVD_*` de `vm.asm`; repetir en el programa de la placa los `OVB_*` y `OVC_*` de `vm.asm` y las entradas de API `vm_load_room` y `vm_sentence`.
- Mover lo común a `SCUMM/COMMON/` (D1) y volver a pasar las pruebas de v2.
- El usuario prueba en la placa: arranque, protección, Barnett College, Venecia, castillo, scroll, sonido, guardar y cargar.
- **HECHA 2026-11-16** (salvo la placa): ver la tabla Estado y `V3/FASE3.md` ("Fase 9"). La lista de pruebas para el usuario esta en `V3/PRUEBAS_PLACA.md`.

### Fase 10 (Opus): rendimiento y repaso
- Perfil con `TS_PROF` en las salas medidas en el estudio: 1, 20, 28, 70 y una de 4-6 actores. Las vueltas tienen que caber en `delta` 6 (325.000 T).
- Repaso de las diferencias que queden con ScummVM y lista de lo pendiente para Loom EGA.

**Subdivisión (usuario, 2026-11-16):** la fase 10 va en subtareas independientes, **una sesión cada vez** (tocan los mismos ficheros), con Opus (el usuario descartó Fable el 2026-11-16 por su coste). Cada subtarea deja escrito en `FASE3.md` lo hecho y lo que falta antes de acabar, para poder retomarla en otra sesión.
**Pruebas en la fase 10:** las de "Reglas para todas las fases" (solo pruebas específicas del cambio; la larga, por la noche).

| Sub | Qué | Estado |
|---|---|---|
| 10a | **Fallos de la placa** (2026-11-16): (1) al salir de una sala los sprites deben apagarse antes de borrar el fondo; (2) en el gimnasio Indy se ve por encima de la puerta antes de pasar a la sala de al lado; (3) la caja del clic de un verbo no coincide con su longitud (solo responde la mitad izquierda de la palabra); (4) **LOAD de una partida guardada se cuelga** | **Arreglados los cuatro (2026-11-16), solo ensamblado**: (1) `evh_room` apaga los sprites antes de `gf_load_room`; (2) Indy sale por la puerta con `ignoreBoxes` (caja 255) y en v3 `getMaskFromBox(255)` = 1: ahora lleva máscara (2.º intento, tras la prueba del usuario; además la máscara ya no se quita con el borde izquierdo en columna negativa); (3) `in_conv` no restaba los 8 px de margen de `hr_ui`; (4) tras cargar, el script seguía por el opcode de guardar y no por el de cargar (ScummVM: `updateScriptPtr` al final de `o4_saveLoadGame`), bucle sin fin en el diálogo: reproducido en el modelo. El usuario confirmó en el emulador el 1 y el 4; el 2 corregido de nuevo, sin probar; TALK/TRAVEL no se pueden pinchar porque el juego los atenúa en el gimnasio (ya se pintan atenuados con su `dimcolor`: `ui3.asm`, sin probar). **Faltan las pruebas del arnés (pendientes del permiso del usuario) y la placa.** Detalle en `FASE3.md` ("Fase 10a"). Sin commit |
| 10b | Rendimiento: pasillo (sala 1) con scroll, ~1.000.000 T por vuelta | **Hecha (2026-11-16)**: los picos eran `hr_objupd` recomponiendo un rango minimo-maximo (casi toda la pantalla); ahora mapa de bits de columnas sucias, `hr_stride` desenrollado, `hr_mkdl` sin buscar en `OV_ZL`, `drawObject` y `obj_drawn` sin recalcular registros. `TS_PROF=582-760`: media **362.787 -> 192.782 T**, p90 1.100.705 -> 271.147; sin las 2 vueltas de la SD, maximo 1.306.870 -> 404.736 y vueltas > 325.000: 38 -> 4 de 176. Residente hasta `$7A57` (1.449 B libres). **Pruebas pasadas**: `build_test.sh` 3.687/3.687, pasillo 761/761, arranque 1.501/1.501, Barnett 1.751/1.751, `savetest.sh` todo igual, `check_hr` 0 distintos (salvo 8 en el dialogo F5, que son el texto de la capa que `check_hr` no modela). **Falta la placa.** Detalle en `FASE3.md` ("Fase 10b"). Sin commit |
| 10c | Rendimiento: recomposición de objetos en las salas 20/28 (`hm_o`, `hr_makecol`; 334.176 y 451.235 T de media, máx. 1,2 y 1,5 M) | **Hecha (2026-11-16)**: de cada objeto que cambia se recompone solo su rectangulo (sus lineas, no las 128 de la columna; `hr_orect`), con la lista filtrada de los objetos que lo tocan (`hr_ofilt`), sin el fondo si un objeto lo tapa, sin repetir rectangulos (los dos estados de una animacion) y sin borrar `OV_FLG` en cada columna. `objflip.sh`: sala 20 media **336.409 -> 296.946** (p90 595.654 -> 396.272, max. 773.808 -> 612.902); sala 28 **450.177 -> 375.332** (p90 864.143 -> 519.463, max. 1.511.340 -> 849.790); pasillo (sin la SD) 167.050 -> 150.609, max. 351.130. **La 28 no baja de ~310.000 aunque no cambie nada** (scripts y actores; la vuelta maxima es un calculo de camino: 10d). Residente hasta `$7C6F` (913 B libres). **Pruebas**: `check_hr` 0 distintos en las dos salas; pasillo 761/761 y `check_hr` 0. **Falta la placa** y la prueba de la noche. Detalle en `FASE3.md` ("Fase 10c"). Sin commit |
| 10d | Rendimiento: cambio de tramo de la caminata (134.670 T de media, máx. 1.467.429), perfil de las salas 70 y una de 4-6 actores, y scripts y actores de la sala 28 (~310.000 T por vuelta aunque no cambie nada; 10c) | **Hecha en parte (2026-11-17), solo arnés**: (1) **tabla de puertas** (`pack_data3.gate_table`, calculada con `get_gates` del modelo; `gt_load` la copia a la página 47 al cargar sala o partida; `gates` la consulta y, si falta, calcula), **`closestPtOnLine` reescrita** sin pila de 32 bits ni `mul32`, y en `adjustXYToBeInBox` poda exacta por arista, `checkXYInBoxBounds` solo en la 1.ª pasada y `inBoxQuickReject` como distancia al rectángulo: cambio de tramo **148.198 → 19.158 T de media, máx. 1.428.728 → 79.454**; `walkActorTo` 70.230 → 37.687 (máx. 3,88 M → 1,11 M); (2) `div32s` con divisor de 16 bits (43.000 T por vuelta en la sala 70), `loc_addr`, `ex_push`/`ex_pop`, `isActorInBox`; (3) sprites: máscara por píxel con una variante por desplazamiento, camino directo de la máscara sin `aq_mt` cuando no hay máscara de la sala ni recorte, tabla de celdas por actor, `aq_slot` y rellenos más cortos. Vueltas (sin las de la SD; HEAD → 10d): sala 28 parada máx. 574.314 → **283.246** (media 282.914 → 245.834); sala 70 con 1-6 actores máx. 368.853 → **290.568** (14 → **0** vueltas > 325.000); sala 20 con 1-6 actores 486.898 → 352.151 (26 → **7**); sala 15 (máscara) 583.134 → 442.710 (16 → **9**). **Pruebas**: núcleo en 11 salas, `wlk_test` 600/600, `ibx_test` 600/600, `exp_test` (nuevo) 600/600, pasillo 761/761 y `check_hr` 0, `savetest.sh` todo igual, `actscen.sh` igual que HEAD. Residente hasta `$7CAD` (**851 B libres**); D 7.163 B; B a 1 byte de llenarse. **Falta**: la placa, la noche, y las vueltas de 4-6 actores redibujados a la vez en las salas 20 (7) y 15 (9, la máscara de la sala). **Pendiente (usuario, 2026-11-17): conservar la máscara descodificada por actor**, sin empezar. Detalle en `FASE3.md` ("Fase 10d"). Sin commit |
| 10e | Huecos de las pruebas: mutaciones de actores sin detectar (fase 8), las 4 de `moveCamera` y las 4 de la fase 7, mutaciones de `ovc9.asm`, y las 8 escenas de `actscen.sh` en la sala 70 distintas del modelo (actores 8 y 10; ya pasaba en HEAD antes de la 10d) | **Hecha (2026-11-17), solo arnes**: nucleo (grupo pedido) **33/46 -> 43/43 + 4 equivalentes** (escenarios fijos `cgap*`; ordenes del arnes `CODER` y `SYNTH`); actores **30/44 -> 41/41 + 3 equivalentes** (escenas fijas X0-X13 en `mk_actscen.py`); `ovc9.asm` (nuevo `mut_fase9.py`, 43 + 2 equivalentes): **sin cifra, queda para la validacion final**. Sala 70: **era la prueba** (los sprites coincidian; `EXPECT_PC` miraba a los actores 8 y 10, que mueven los scripts de la sala como en ScummVM): `EXPECT_ACT`, 8/8. `mutaciones.py` rehace lo esperado si cambia el modelo y pasa un control sin mutar; equivalentes en `EQUIV`/`EQUIV8`/`EQUIV9` con su motivo; la noche pasa tambien `mut_fase8.py` y `mut_fase9.py`. **Pendiente:** sala 20 con 12 escenas da `ERR=6` (de antes); el segundo dialogo de guardar con una partida en la ranura 3 (`ev_dialogo2.txt`) difiere del modelo (sin investigar). Detalle en `FASE3.md` ("Fase 10e"). Sin commit |
| 10f | Repaso de las diferencias con ScummVM y lista de lo pendiente para Loom EGA; antes, dos fallos de la 10e | **Hecha (2026-11-17, sin commit).** A (`actscen.sh 1 20 12`, ERR=6): era del arnes (RESMAP a cero y cutscene del guardia de la sala 20); arreglado, 23 escenas sin diferencias. B (`ev_dialogo2.txt`): era del arnes (las teclas llevaban el cursor a x=0); arreglado, 2.401/2.401. El modelo apaga ademas la ventana movil al cambiar de sala. Lista de diferencias y de Loom en `FASE3.md`, "Fase 10f" |

## Orden y paralelismo

- Las fases 0, 1 y 2 no tocan los mismos ficheros: pueden ir en paralelo (tres sesiones Sonnet).
- La fase 3 necesita la 1 (modelo) y conviene tener la 0 (medidas).
- Las fases 4 y 5 necesitan la 3. La 6 puede ir en paralelo con la 4: el modelo primero, el Z80 cuando la 3 esté.
- Las fases 7 y 8 necesitan la 5. La 9 necesita todas. La 10 va al final.

## Estado

| Fase | Estado |
|---|---|
| 0 | **Hecha** (2026-11-11): arnés en marcha, perfil de Zak y T por instrucción medidos (ver la fase). Sin commit |
| 1 | **Hecha** (2026-11-11): `V3/TOOLS/vmmodel3.py` + `vmgame3.py` + `vmcommon3.py`, prueba `test_vmmodel3.py` (arranque a la sala 1, escenarios reproducibles, salas 1, 15, 20 y 28 sin errores). El formato de la traza y de los escenarios está en el docstring de `vmmodel3.py`. Aproximado: ver "Pendiente de la fase 1" abajo. Sin commit |
| 2 | **Hecha** (2026-11-11): `lfl3hr.py` (+ `LFL3HR.md`, `.GFX` versión 2 con alto variable: 88 salas, 1,85 MB, solo la 79 pasa de 48 KB), `costume3.py` (100 trajes; 24 necesitan una segunda página; posturas especiales y paleta del actor), `pack_data3.py` (`DATA.BIN` v3 de 640 KB con comando `check`; script 95 aparte en dos páginas) y `sound3vgm.py` (73 sonidos; `VAR_MUSIC_TIMER` anotado). Cifras, decisiones y lo abierto para la fase 3 en `V3/FASE2.md`. Sin commit |
| 3 | **Hecha** (2026-11-12): nucleo v3 en el Z80 (`V3/ENGINE`), mapa de memoria, D5, arnes con `DATA.BIN`, modelo en modo nucleo. 1.485/1.485 trazas iguales; residente del nucleo 3.887 B (11.985 libres); despachador 164 T (v2 600-700). Detalle en `V3/FASE3.md`. Sin commit |
| 4a | **Hecha** (2026-11-13): 27 opcodes mas (sonido, objetos, camara, actores sin caminar) en el overlay B; 1.484/1.484 trazas iguales; residente 11.832 B libres, B 3.328 B. Sin commit |
| 4b-1 | **Hecha** (2026-11-13): 22 opcodes mas en el nucleo (overlay B). **2.686/2.686 trazas iguales** (1.486 de las salas, locales, objetos y globales + 1.200 sinteticos con `CODE`); mutaciones 41/45 (las 17 nuevas detectadas). Residente `$4200-$51ED`: **11.795 B libres** hasta `$8000`; overlay B **6.656 de 8.192 B** (1.536 libres); hueco de `ODIRBUF` (bloque 4): **187 B** libres; bloque 7: **122 B** libres. Sin commit |
| 4b-2 | **Hecha** (2026-11-14): `print` y `printEgo` en el nucleo (overlay B, `ovb4c.asm`; `talk_frame` y `MSGBUF` en el residente). **2.687/2.687 trazas iguales** (1.487 de las salas + 1.200 sinteticos); mutaciones 50/54 (las 9 nuevas detectadas). Residente `$4200-$5392` (tras abrir el overlay C, `$53A8`: **11.352 B libres** hasta `$8000`; +421 B, 320 de `MSGBUF`); overlay B **7.944 de 8.192 B (248 libres)**, y con el overlay C (`call_ovc`, pagina 48): B 7.680 B y C 1.024 B; bloque 7: **60 B** libres; hueco de `ODIRBUF`: 187 B. T: `print` 8.360, `printEgo` 14.104, `talk_frame` 75 T sin mensaje. v2 sin tocar y sin regresiones (Maniac 2.912/2.912, Zak 3.662/3.662). Sin commit |
| 5 | **Hecha** (2026-11-14): `startScene`, objetos de sala, nombres de objeto, cola de frases y los 12 opcodes (`ovc5.asm`, overlay C). **3.192/3.192 trazas iguales**; mutaciones 72/77. OBJCLS a la página fría 47; residente `$421E-$550E` (**10.994 B libres** hasta `$8000`), overlay C 3.840 B (4.352 libres), overlay B 7.680 B (512 libres), bloque 7: **1.282 B libres**. T: `startObject` 7.620, `drawObject` 8.628, `findObject` 8.869, `isActorInBox` 3.215, `loadRoom` 49.052, `doSentence` 2.745. Sin hacer (fase 6): `adjustXYToBeInBox` con cajas y `startWalkActor` (E_BADOP). Sin commit |
| 6 | **Hecha** (2026-11-14): caminata de v3 revisada contra ScummVM en el modelo y hecha en el Z80 (overlay D nuevo, página 46: `geom.asm` + `walk.asm`; opcodes en `ovc6.asm`). **3.492/3.492 trazas iguales** (300 escenarios `cwlk` de clics y mezcla en todas las salas con cajas, 12 en las salas 1, 15, 20 y 28) y `wlk_test.py` 600/600; **mutaciones 120/126** (caminata 48/49). Residente `$421E-$5578` (**10.888 B libres**), overlay B 7.680 B (512 libres), C 4.096 B (4.096 libres), **D 4.392 B (3.800 libres)**, bloque 7 **987 B libres**. **T de un paso de caminata: 8.329** (máx. 21.598); cambio de tramo 134.670 de media (máx. 1.467.429): para la fase 10. Sin commit |
| 5b | **Hecha** (2026-11-15): `scumm.asm` de v3 es ya el programa completo (cargador v3, overlays B/C/D desde la SD, bucle principal, camara, sonido simulado `timed`, proteccion saltada) y el arnes `test_scumm` lo arranca hasta el pasillo: **1.501/1.501 fotogramas con el mismo resumen D que el modelo** (`vmmodel3.py boot-core`; sala 1 en el fotograma 694) y `check_hr.py` 0 distintos en las salas 76, 79, 1, 8, 12 y 20. **Pantalla D3** en `hr.asm` (16 lineas de mensajes, sala de 128 desde la linea 16, 48 de interfaz; `.GFX` v2; salas de 144 lineas o mas recortadas: se pierden las 16 de arriba). Para llegar al pasillo hizo falta `moveCamera` (overlay C, `ovc7.asm`) y `VAR_CAMERA_POS_X`, en modelo y Z80. Bugs hallados: `map_page` debe conservar BC y el cargador pisaba la pagina fria. `build_test.sh` **3.492/3.492**; mutaciones 129/139: las 126 de antes igual (120 detectadas) y 9 de 13 las nuevas de la camara. Residente `$4200-$65B9` (**6.727 B libres** hasta `$8000`), overlay B 7.680 B (512 libres), **C 4.608 B (3.584 libres)**, D 4.392 B (3.800 libres). Sin texto, interfaz ni actores (fases 7 y 8); el pasillo con scroll cuesta ~1.000.000 T por vuelta (fase 10). Detalle en `FASE3.md`. Sin commit |
| 7 | **Hecha** (2026-11-15): interfaz de Indy3 (`ui3.asm`: verbos colocados por el script, frase, inventario con flechas, mensajes arriba con el color del actor, cursor, teclado y raton, pausa y reinicio) y la entrada en el nucleo (`vm_input.asm`: `processInput`, `checkExecVerbs`, `runInputScript`, ESC / boton derecho / `VAR_CUTSCENEEXIT_KEY`), en modelo y Z80. **`build_test.sh` 3.687/3.687 iguales** (195 escenarios de entrada nuevos); arranque 1.501/1.501 y **partida en Barnett College con 14 sucesos de entrada 1.751/1.751** fotogramas iguales; `check_hr.py` 0 distintos (salas 76, 79, 1, 8, 12, 20; ya comprueba tambien las filas de la interfaz). Mutaciones: 20 de las 24 nuevas (total 148 de 162, sin perder las 129 de 139 de antes). Residente `$4200-$7064` (**3.996 B libres**), overlay B 7.936 B (365 libres), C 4.608 B, D 4.392 B. **Decision (confirmada por el usuario, 2026-11-15):** la frase va en la 2.a fila de mensajes de arriba (Indy3 usa 7 filas de interfaz y D3 da 6). Detalle en `FASE3.md`. Sin commit |
| 8 | **Hecha** (2026-11-15): actores (`ovd_act.asm`, overlay D; sprites3.py / check_spr.py), sonido real (`snd3.asm`, modo `real` del modelo) y objetos animados comprobados. **Punto de partida igual** (3.687/3.687, 1.501/1.501, 1.751/1.751, `check_hr` 0 distintos) y **al final igual**: `build_test.sh` 3.687/3.687; arranque 1.501/1.501 con las 3 ordenes al MCU iguales; Barnett 1.751/1.751; arranque con ~85 sucesos de sonido al azar 701/701 y 92 ordenes al MCU iguales; sprites: 96 escenas al azar en las salas 1, 15, 20 y 28 y los volcados del arranque, 0 distintos; objetos: `check_hr` 0 distintos con 2 cambios por fotograma en las salas 20 y 28. D6 sin sprites extra ni escala (peor caso 4-66 de 63). Mutaciones de la fase 8: sonido 17/17, actores 28/43; `mutaciones.py` del nucleo repetido despues (2026-11-15): **148/162**, las mismas 14 sin detectar que antes. Residente `$4200-$7292` (**3.438 B libres**), overlay B 7.936 B (365 libres), C 4.608 B, **D 6.308 B (1.884 libres)**, bloque 7: 145 B libres. Paleta de 16: el marron del EGA (`hr_pal16`, que v2 programaba y v3 habia perdido) y los `roomOps` 2 y 4 (`_roomPalette`/`_shadowPalette`, suceso `EV_PALETTE`, resumen `Y=`: `build_test.sh` sigue en 3.687/3.687); `oldRoomEffect` son barridos de pantalla, no paleta, y no estan hechos (ver `FASE3.md`, "Paleta"). El intro llega al pasillo en el fotograma 582 (antes 694). Sin commit |
| 9 | **Hecha** (2026-11-16; sin la prueba en la placa): `compila_scumm.bat` (carpeta lista en `V3\SDOUT\SCUMM\V3\`; `SCUMM.B81` con `USR 16917`), **guardar y cargar** en modelo y Z80 (`ovc9.asm`, overlay C; `SAVEnn.SAV` de 14.943 B; los nombres de las partidas en las cadenas 10..24; SHIFT + S = F5 abre el dialogo de Indy3), `SCUMM/COMMON/` (`mcu.asm`, `mouse.asm`, `font6.bin`; v2 byte a byte igual; el resto no se mueve), `V3/PRUEBAS_PLACA.md`. **Hallazgo:** el dialogo de guardar pedia ~1.155 B de cadenas y el monton era de 480: ahora **1.248 B en `$9B20`** (`STRHEAP`). Pruebas: `build_test.sh` **3.687/3.687**, arranque **1.501/1.501**, Barnett **1.751/1.751**; guardar y cargar (entre fotogramas, entre salas, el opcode en un script, el dialogo F5 y SHIFT + S) **701, 901, 401, 1.501 y 1.351 iguales**, `check_hr` 0 distintos; **v2 tras mover COMMON: Maniac 2.917/2.917, Zak 3.672/3.672**. Residente `$4200-$730A` (**3.318 B libres**), overlay B 7.936 B, **C 5.376 B (2.816 libres)**, D 6.308 B. Sin hacer: puntos IQ (sin fichero), sonido guardado, mutaciones de `ovc9.asm`. Detalle en `FASE3.md` ("Fase 9"). Sin commit |
| 10 | Sin empezar |

### Pendiente de la fase 1 (lo que el modelo aproxima o no hace)

- ~~**Caminata** sin verificar~~: **revisada en la fase 6** contra el código de ScummVM (ver la fase 6 y `FASE3.md`); sigue sin compararse con una ejecución real de ScummVM (no hay ejecutable): queda para la placa.
- **Sin trajes**: el fotograma del actor es el último pedido (`_frame`); `getAnimCounter` devuelve 0 (el opcode no existe en v3). El rectángulo de un actor para `actorFromPos` es una caja fija (`actor_rect`) hasta la fase 8.
- **Sin diseño de texto**: el modelo no mide letras; el salto de línea nunca falla y el rectángulo de un verbo mide 8 px por letra y 8 de alto (`findVerbAtPos`, `getStringWidth`). La pantalla principal es la de `roomOps` 3 (por omisión y = 16..160).
- **Sonido**: dos modos. `mock` (escenarios): `isSoundRunning` sale como suceso `E 4` y `VAR_MUSIC_TIMER` no avanza. `timed` (arranque): 60 jiffies por efecto, 3600 por canción (>1000 bytes) y temporizador como `Player_V2Base` (236 Hz, +1 cada 126 ticks tras fijar el tempo). La fase 8 usa el real.
- **Escenarios**: `INIT` va seguido del estado de después del arranque (`boot_snapshot`: variables, `pseudoRoom`, cadenas, dueños, estados, clases, actores), porque con todo a cero los scripts de sala fallan. El arnés del Z80 tiene que entender además `PSEUDO`, `STRING`, `OWNER`, `STATE`, `CLASS`, `ACTOR`, `CLICK`, `RCLICK`, `KEY`, `ESC`, `SENTENCE` y `OPT`.
- **Protección anticopia**: el modelo la deja como el original (`protection=True`); `boot` la salta por omisión (los clics al azar no pueden contestarla) y `--proteccion` la deja; `OPT proteccion 0` en un escenario pone `Var[57] = 1` a los 30 fotogramas en la sala 92.
- **Pendiente para el Z80**: ~~`world3.bin` PROVISIONAL~~ (fase 3: el mundo del arnes es `DATA.BIN` de `pack_data3.py`; la orden `pack` ya no existe). `loadFlObject` (`resourceRoutines` 20) y `roomOps` 13/14 (guardar/cargar cadenas en fichero) dan error `E_BADSUB`. Los valores de variables son de 16 bits (ScummVM usa 32; solo difiere si hay desbordamiento).
