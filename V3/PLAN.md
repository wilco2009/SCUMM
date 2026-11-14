# Plan: intérprete SCUMM v3 (Indy3 EGA) para el Z80

Fecha: 2026-11-11. Base: `ESTUDIO_SCUMMV3.md`; las cifras y los porqués están allí.
Primer juego: **Indiana Jones and the Last Crusade EGA** (DOS, inglés; el castellano también está en disco). Loom EGA usa el mismo formato y vendrá después, cuando haya ficheros.

## Reglas para todas las fases

- **La referencia es ScummVM** (`C:\ClaudeCode\scummvm_src\engines\scumm`), clase `ScummEngine_v3old`: `script_v5.cpp` + `script_v4.cpp` + `script_v3.cpp`, `actor.cpp` (`Actor_v3`), `boxes.cpp`, `room.cpp`, `object.cpp`, `string.cpp` y `players/player_v2*.cpp`.
  No suponer reglas: si algo no está claro, se lee ScummVM.
- **El código Z80 no puede pasar de `$8000`**. Al acabar cada fase, el montaje imprime el final del residente y el tamaño de cada overlay.
- **Nombres de fichero de la SD sin "_"**.
- **Sin regresiones en v2:** `V2/ENGINE/test/build_test.sh` (Maniac y Zak) tiene que seguir pasando. Si una fase toca un fichero compartido, lo comprueba.
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
      - **ATENCION para la fase 5:** el overlay B queda con 248 B libres (7.944 de 8.192); los manejadores de la fase 5 no caben: hace falta otro overlay (otra pagina fisica) o mover algo.
  - Con la fase 5 (necesitan la sala cargada o la cola de frases): `doSentence`, `startObject`, `getVerbEntrypoint`, `drawObject`, `pickupObject`, `findObject`,
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

### Fase 6 (Opus): caminata de v3
- Primero en el modelo (`vmmodel3.py`), copiando ScummVM sin aproximar:
  - `Actor_v3::walkActor`, `calcMovementFactor`, `actorWalkStep` y `updateActorDirection` de v3 (`_facingXYratio`);
  - `findPathTowardsOld` con `getGates`;
  - `getNextBox` de v3 (ternas por caja, con el WORKAROUND de la sala 46);
  - `adjustXYToBeInBox`, `getClosestPtOnBox` y `checkXYInBoxBounds` con cuadriláteros en s16, y los flags de caja.
- Después en el Z80 (`walk.asm`/`geom.asm` de v3), comparando la traza de posiciones fotograma a fotograma con el modelo.
- **Hecho cuando:** Indy cruza las salas con varias cajas (pasillo, 15 Venecia, 20 y 28 del castillo) igual que el modelo en escenarios de clics.

### Fase 7 (Sonnet): interfaz de Indy3
- Verbos colocados por el script (`verbOps`: posición, nombre, colores y tecla), línea de la frase e inventario con flechas, en las 6 filas de D3.
- Mensajes de 2 líneas arriba, con la fuente de 6 px y el color del actor.
- Cursor y ratón: `mouse.asm` ya existe en v2.
- Teclas: `VAR_CUTSCENEEXIT_KEY` (27), pausa y reinicio.
- **Hecho cuando:** en el arnés se puede jugar la primera parte (Barnett College) con clics de escenario.

### Fase 8 (Sonnet): actores y sonido
- Sprites de los actores con los blobs de la fase 2; caché de firma como en v2.
- Posturas especiales por fotograma pedido; reparto de sprites según D6.
- Objetos animados: recomponer columnas (salas 20 y 28, unos 2 objetos por fotograma).
- Sonido: `snd.asm` con la tabla de v3 y `VAR_MUSIC_TIMER` de v3, porque las esperas del intro dependen de él.
- **Hecho cuando:**
  - el intro va al ritmo de la música;
  - en el arnés se ven bien los actores de las salas 1, 15, 20 y 28;
  - no se pasa de los sprites disponibles en las salas con 4-6 actores (32, 35, 36, 41, 43, 46, 66, 70, 72, 76, 82).

### Fase 9 (Sonnet + usuario): montaje, SD y placa
- `compila_scumm.bat` de v3. En la SD: `SCUMM\V3\SCUMM.BIN`, `SCUMM\V3\INDY3\INDY3.B81` y `SCUMM\V3\INDY3\DATA\`, sin "_".
- Guardar y cargar (`save.asm` con el estado de v3: locales, clases, inventario v3).
- Mover lo común a `SCUMM/COMMON/` (D1) y volver a pasar las pruebas de v2.
- El usuario prueba en la placa: arranque, protección, Barnett College, Venecia, castillo, scroll, sonido, guardar y cargar.

### Fase 10 (Opus): rendimiento y repaso
- Perfil con `TS_PROF` en las salas medidas en el estudio: 1, 20, 28, 70 y una de 4-6 actores. Las vueltas tienen que caber en `delta` 6 (325.000 T).
- Repaso de las diferencias que queden con ScummVM y lista de lo pendiente para Loom EGA.

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
| 4b-2 | **Hecha** (2026-11-14): `print` y `printEgo` en el nucleo (overlay B, `ovb4c.asm`; `talk_frame` y `MSGBUF` en el residente). **2.687/2.687 trazas iguales** (1.487 de las salas + 1.200 sinteticos); mutaciones 50/54 (las 9 nuevas detectadas). Residente `$4200-$5392`: **11.374 B libres** hasta `$8000` (+421 B, 320 de `MSGBUF`); overlay B **7.944 de 8.192 B (248 libres)**: la fase 5 necesita otro sitio; bloque 7: **60 B** libres; hueco de `ODIRBUF`: 187 B. T: `print` 8.360, `printEgo` 14.104, `talk_frame` 75 T sin mensaje. v2 sin tocar y sin regresiones (Maniac 2.912/2.912, Zak 3.662/3.662). Sin commit |
| 5 a 10 | Sin empezar. La 5 (salas, objetos y frases) es la siguiente; ver arriba el aviso del overlay B |

### Pendiente de la fase 1 (lo que el modelo aproxima o no hace)

- **Caminata**: `startWalkActor`, `walkActor`, `calcMovementFactor`, `actorWalkStep`, `remapDirection`, `findPathTowardsOld`, `getGates`, `getNextBox`, `adjustXYToBeInBox`, `checkXYInBoxBounds` y `closestPtOnLine` están transcritas de ScummVM v3 con sus nombres, pero solo se han leído: no se han comparado con una ejecución real. La fase 6 las verifica.
- **Sin trajes**: el fotograma del actor es el último pedido (`_frame`); `getAnimCounter` devuelve 0 (el opcode no existe en v3). El rectángulo de un actor para `actorFromPos` es una caja fija (`actor_rect`) hasta la fase 8.
- **Sin diseño de texto**: el modelo no mide letras; el salto de línea nunca falla y el rectángulo de un verbo mide 8 px por letra y 8 de alto (`findVerbAtPos`, `getStringWidth`). La pantalla principal es la de `roomOps` 3 (por omisión y = 16..160).
- **Sonido**: dos modos. `mock` (escenarios): `isSoundRunning` sale como suceso `E 4` y `VAR_MUSIC_TIMER` no avanza. `timed` (arranque): 60 jiffies por efecto, 3600 por canción (>1000 bytes) y temporizador como `Player_V2Base` (236 Hz, +1 cada 126 ticks tras fijar el tempo). La fase 8 usa el real.
- **Escenarios**: `INIT` va seguido del estado de después del arranque (`boot_snapshot`: variables, `pseudoRoom`, cadenas, dueños, estados, clases, actores), porque con todo a cero los scripts de sala fallan. El arnés del Z80 tiene que entender además `PSEUDO`, `STRING`, `OWNER`, `STATE`, `CLASS`, `ACTOR`, `CLICK`, `RCLICK`, `KEY`, `ESC`, `SENTENCE` y `OPT`.
- **Protección anticopia**: el modelo la deja como el original (`protection=True`); `boot` la salta por omisión (los clics al azar no pueden contestarla) y `--proteccion` la deja; `OPT proteccion 0` en un escenario pone `Var[57] = 1` a los 30 fotogramas en la sala 92.
- **Pendiente para el Z80**: ~~`world3.bin` PROVISIONAL~~ (fase 3: el mundo del arnes es `DATA.BIN` de `pack_data3.py`; la orden `pack` ya no existe). `loadFlObject` (`resourceRoutines` 20) y `roomOps` 13/14 (guardar/cargar cadenas en fichero) dan error `E_BADSUB`. Los valores de variables son de 16 bits (ScummVM usa 32; solo difiere si hay desbordamiento).
