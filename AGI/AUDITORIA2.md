# AUDITORIA2 — nuestro intérprete AGI v2 contra el código real de ScummVM

Se hizo leyendo el código de ScummVM **en disco** (no con WebFetch).

- Origen: `git clone --depth 1 --filter=blob:none --sparse https://github.com/scummvm/scummvm.git` en `C:\ClaudeCode\scummvm_src`, con `sparse-checkout set engines/agi`.
- **Commit de ScummVM: `f7403b6efaae2f033e8abea80b3fb6bee5303369`** (30-oct-2026).
- No se ha ejecutado nada de ese código.
- Las citas son literales de ese commit. Las rutas `ScummVM fichero:línea` son de `engines/agi/`.

Nuestro lado:

- **Modelo**: `V2/TOOLS/agi_vm.py` (`py:línea`).
- **Z80**: `V2/ENGINE/*.asm`.
- Por defecto el Z80 y el modelo coinciden (el modelo se validó contra el Z80). **Solo afirmo cosas del Z80 en las líneas que he leído** (ver §6). Donde pone "Z80: NO COMPROBADO", el defecto está en el modelo y no he mirado el ensamblador.

Numeración de variables y banderas de este ScummVM (`agi.h:213-300`, distinta de la de mis notas previas):

| Qué | Valor |
|---|---|
| v2 | BORDER_TOUCH_EGO |
| v4 | BORDER_CODE (nº de objeto) |
| v5 | BORDER_TOUCH_OBJECT (borde) |
| v6 | EGO_DIRECTION |
| v9 | WORD_NOT_FOUND |
| v16 | EGO_VIEW_RESOURCE |
| v19 | KEY |
| v21 | WINDOW_AUTO_CLOSE_TIMER |
| v25 | SELECTED_INVENTORY_ITEM |
| f0 | EGO_WATER |
| f1 | EGO_INVISIBLE |
| f2 | ENTERED_CLI |
| f3 | EGO_TOUCHED_P2 |
| f4 | SAID_ACCEPTED_INPUT |
| f5 | NEW_ROOM_EXEC |
| f6 | RESTART_GAME |
| f9 | SOUND_ON |
| f11 | LOGIC_ZERO_FIRST_TIME |
| f12 | RESTORE_JUST_RAN |
| f13 | STATUS_SELECTS_ITEMS |
| f14 | MENUS_ACCESSIBLE |
| f15 | OUTPUT_MODE |
| f16 | AUTO_RESTART |

Estados: **DIFERENTE** (hace otra cosa), **FALTA** (no existe), **IGUAL** (leído y comparado). "Justificable" = por hardware o memoria, y por qué. Si no lo es, lo digo. **No clasifico por gravedad.** El orden es el de ejecución del ciclo.

---

## 1. Resumen del flujo de un ciclo en ScummVM (`cycle.cpp`) y dónde se separa el nuestro

Orden real:

1. `playGame` (373-438) hace en cada iteración:
   1. `processAGIEvents()`: sondea teclas y las procesa **una por llamada**.
   2. `inGameTimerUpdate()`.
   3. Si pasaron los ciclos de `v10`: `interpretCycle()`.
   4. Limpieza: `f2=0; f4=0; v9=0; v19=0` (432-435).
2. `interpretCycle` (157-211):
   1. `if !playerControl v6 = ego.direction else ego.direction = v6`.
   2. `checkAllMotions()`.
   3. `while (runLogic(0)==0 && !quit) { v9=0; v4=0; v5=0; f2=0; exitAllLogics=false; resetControllers() }`.
   4. Tras el bucle: `resetControllers`; `ego.direction = v6`; statusDraw; `v4=0; v5=0; f5=0; f6=0; f12=0`; `updateScreenObjTable()`.

Nuestro `interpret_cycle` (`py:1926-1976`) y el `main_loop` del Z80 (`agivm.asm:192-278`) tienen **el mismo esqueleto**. Las diferencias de detalle están abajo.

---

## 2. Diferencias en el orden del ciclo

### D01 — Entrada de teclas: `v19` se pone también con las teclas de controlador y de dirección
- **ScummVM** `cycle.cpp:250-258`:
  ```
  if (!handleController(key)) {
      // Only set VAR_KEY, when no controller/direction was detected
      setVar(VM_VAR_KEY, key & 0xFF);
  ```
- `handleController` (`keyboard.cpp:527-533`) devuelve `true` y marca `controllerOccurred[slot]` si la tecla tiene `set.key`.
- También devuelve `true` con las flechas (`keyboard.cpp:600-611`).
- **Resultado**: una tecla con `set.key` o una flecha **no** pone `v19`. `have.key` no la ve.
- **Modelo** `py:1915-1920`: `v[19]=n` siempre, y además `ctl.add(keys[n])`.
- **Z80** `agiin.asm:110-111` (`key_push`): `ld (VARS+19),a` siempre y luego mira `KEYMAP`.
- **Estado**: DIFERENTE (modelo y Z80).
- **Efecto**:
  - Un `if (have.key()) {…}` de una pantalla "pulsa una tecla" se dispara con F-keys, ESC, ENTER y cualquier tecla mapeada, que en ScummVM no lo disparan.
  - Los menús, la pausa y las teclas de dirección también ponen `v19`.
  - Una lógica que haga `if (v19 == X)` ve teclas que ScummVM no ve.
- **Justificable**: no. El ZX81 genera el mismo evento. Es cuestión de ordenar el código: primero mirar `KEYMAP`, y solo poner `v19` si no hay controlador.

### D02 — `v19` tras escribir una línea: ScummVM pone 13 (la tecla ENTER), nosotros 0
- **ScummVM**: el ENTER de una línea no vacía no tiene controlador (salvo `set.key`). Llega a `setVar(VM_VAR_KEY, key & 0xFF)` (`cycle.cpp:253`), o sea `v19 = 13`. Antes, cada carácter tecleado ya ha puesto `v19`.
- **Modelo** `py:1911` y **Z80** `agiin.asm:90` (`ev_text`): `v19 = 0` al llegar la línea.
- **Estado**: DIFERENTE.
- **Efecto**: `have.key()` (cond 0x0D) es cierta en ScummVM en el ciclo en que se envió una frase y falsa en el nuestro.
- **Justificable**: parcialmente. El Z80 tiene un editor de línea propio y no ve las teclas individuales. Hay que decidir: o emular `v19 = 13` al enviar, o dejarlo documentado.

### D03 — Direcciones: ScummVM cambia `v6` solo en el evento y con alternancia; nosotros fijamos `v6 = dirhold` en cada ciclo
- **ScummVM** `keyboard.cpp:600-611`:
  ```
  if (screenObjEgo->direction == newDirection) setVar(VM_VAR_EGO_DIRECTION, 0);
  else setVar(VM_VAR_EGO_DIRECTION, newDirection);
  if (_game.playerControl) screenObjEgo->motionType = kMotionNormal;
  ```
- Además `flags &= ~fAdjEgoXY`.
- Sin `hold.key`: una pulsación hace que el ego camine hasta otra pulsación, y la misma tecla de nuevo lo para.
- Con `hold.key` (`op_cmd.cpp:1057`, `_keyHoldMode`): al soltar la tecla llega `AGI_KEY_STATIONARY` (`keyboard.cpp:337-370`).
- **Modelo** `py:1923` y **Z80** `agivm.asm:199-203`: `v6 = dirhold` en cada ciclo con `pcontrol`. `dirhold` es el estado de la tecla mantenida. No hay alternancia ni `motionType = Normal`.
- **Estado**: DIFERENTE.
- **Efecto**:
  - Sin `hold.key`, el ScummVM sigue andando al soltar la tecla; el nuestro se para.
  - Pulsar la misma dirección dos veces para parar no existe.
  - Una dirección pulsada con el ego en `move.obj` no cancela el movimiento programado en ScummVM si `pcontrol` es falso. Para `kMotionEgo` (ratón) sí.
- **Justificable**: en parte. Un ZX81 sin eventos de "soltar" necesita el modo "mantener". Pero lo exacto sería emular el modo toggle según `hold.key`/`release.key`. Hoy `hold.key`/`release.key` no existen en el modelo (ver D40).

### D04 — Varias teclas por ciclo y cola
- **ScummVM**: `processAGIEvents` consume 1 tecla por llamada y el bucle principal la llama varias veces entre ciclos. Todos los controladores marcados se acumulan hasta `resetControllers`.
- **Nosotros**: `keyq` de 8 (`agiin.asm:113`), pero `v19` guarda solo la última.
- **Estado**: DIFERENTE de detalle.
- **Efecto**: si llegan dos teclas en el mismo ciclo, ScummVM deja `v19` = la última sin controlador y marca ambos controladores. Nosotros ponemos `v19` = la última (aunque tenga controlador, ver D01).

### D05 — `have.key` (cond 0x0D)
- **ScummVM** `op_test.cpp:121-144`: `if (getVar(VM_VAR_KEY)) return true;` y si no, `processAGIEvents()` con inner loop `HAVEKEY`. Esto toma una tecla de la cola **sin pasar por `handleController`**, hace `setVar(VM_VAR_KEY, key)` y devuelve `true`. Si no hay tecla, falso.
- **Modelo** `py:520-536` y **Z80** `agiin.asm:176-194`: `v19 != 0` → cierto, y la espera especial en pantalla de texto (`hk_seen`/`pr_wait`).
- **Estado**: IGUAL en la primera mitad. DIFERENTE en la segunda: nosotros no consultamos la cola en ciclos normales, solo en pantalla de texto.
- **Efecto**: un bucle `if (!have.key()) goto` espera una tecla que llega a media lógica, y ScummVM la recoge con la cola. En ciclos normales nosotros solo vemos la tecla en el siguiente ciclo.
- **Justificable**: sí (un bucle apretado en una lógica no deja pasar tiempo en nuestro intérprete). El Z80 lo resuelve con `pr_wait` solo en `txtm`.
- Nota: `key & 0xFF` (`cycle.cpp:253`). Una F-key sin controlador pone `v19 = 0`. En `have.key` (op_test.cpp:136) `v19 = key` (byte) y devuelve cierto, así que `have.key` puede ser cierta con `v19 == 0`.

### D06 — `set.key`: clave de 16 bits, sin alternancia y con límite de 39
- **ScummVM** `op_cmd.cpp:2111-2134`:
  - `key = p0 + (p1<<8)`, con 39 entradas máximo.
  - Duplicados ignorados.
  - Pone `controllerOccurred[slot] = false`.
- **Modelo** `py:1367`: `keys[a if a else {…}.get(s, s<<8)] = c`.
- **Z80** `agiin.asm:140-163`: tabla de 128 por ASCII.
- **Estado**: DIFERENTE.
  - Si `a != 0`, ignoramos el scancode `s`. En ScummVM la tecla es `a|(s<<8)` y una tecla ASCII que llega solo como ASCII no coincidiría con una entrada con `s != 0`.
  - No limitamos a 39 (sin efecto práctico).
  - No ponemos `controllerOccurred[slot] = false`.
- **Justificable**: la traducción F4-F10 → códigos de control 29,28,31,30,25,26 sí (el ZX81 no tiene F-keys). El resto no.

### D07 — `checkAllMotions` y la dirección del ego: orden
- **ScummVM** `cycle.cpp:160-165`: primero v6↔dirección del ego, luego `checkAllMotions`. **Modelo** `py:1938-1943`: IGUAL.
- **Z80**: `agivm.asm:207-208` llama a `OVC_PRE` (overlay C, NO LEÍDO).

### D08 — Lógica 0 que termina sin `return`
- **ScummVM** `op_cmd.cpp:2434-2531`: `runLogic` devuelve **1** con `return` y **0** si el bucle acaba por `cIP >= size` o por `exitAllLogics`. `interpretCycle` repite `runLogic(0)` mientras devuelva 0 (`cycle.cpp:174`).
- **Modelo** `py:555-624` y **Z80** `agivm.asm:683-687` (`ret z`): acaban sin más.
- **Estado**: DIFERENTE.
- **Efecto**: una lógica 0 sin `return` final se repetiría en ScummVM (con la limpieza de v9, v4, v5, f2). Un bucle infinito en ScummVM, un ciclo normal en nuestro caso.
- **Justificable**: es un caso patológico, pero la regla es copiar.

### D09 — Limpieza dentro del bucle de `runLogic(0)`
- **ScummVM** `cycle.cpp:175-184`: tras cada pasada fallida: `v9=0; v4=0; v5=0; oldScore; f2=0; exitAllLogics=false; _veryFirst…; resetControllers`. No toca `f4`.
- **Modelo** `py:1948-1958` y **Z80** `agivm.asm:214-231`: IGUAL para `new.room` (f2, v9, v4, v5 en `do_new_room`) y para `restore.game`.
- **Estado**: IGUAL, salvo que `restore.game` pone `flags[2]=0` y `v4,v5,v9=0`. Es lo mismo.

### D10 — Fin de ciclo: dónde se limpian f5, f6 y f12
- **ScummVM** `cycle.cpp:200-204`: `v4=0; v5=0; f5=0; f6=0; f12=0`, **antes** de `updateScreenObjTable()`.
- **Modelo/Z80**: después de `update_objects`.
- **Estado**: DIFERENTE en orden, IGUAL en resultado (el movimiento no toca esas banderas).
- Además `rs_keep`/`ml_k6` mantiene f5 y f6 tras restart/restore. ScummVM no hace nada especial: `restart.game` pone `f6` en el comando y `interpretCycle` lo apaga al final del ciclo.
- **Justificable**: no hace falta. Vigilar `restart.game` (D47).

### D11 — Inicialización de variables y banderas al arrancar
- **ScummVM**: `agiInit` (`agi.cpp:86-88`) pone todas las variables y banderas a 0. `runGame` (`cycle.cpp:465-522`) pone:

  | Variable | Valor |
  |---|---|
  | v20 | 0 |
  | v22 | 1 |
  | v26 | 3 |
  | v8 | 180 |
  | v24 | 38 |

  `playGame` (`cycle.cpp:340-342`) pone `f11=1; f5=1; f9=1`. v10 queda a 0 (el comentario dice que el original no la ponía).
- **Modelo** `py:144-154`: v8=255, **v10=2**, **v15=3**, v20=0, **v22=15**, **v24=41**, v26=3; f9, f5, f11 = 1.
- **Estado**: DIFERENTE en v8, v10, v15, v22 y v24. IGUAL en el resto.
- **Efecto**: las lógicas que leen `v22` (tipo de sonido) o `v24` (máx. caracteres de entrada) toman otro camino. `v10 = 2` cambia la velocidad hasta que el juego la ponga.
- **Justificable**: `v22 = 15` puede serlo (chip AY). `v24 = 41` y `v8 = 255` no se ve por qué. **Necesita decisión.**
- Z80: NO COMPROBADO (inicio en `OVC_RESTART`).

---

## 3. `new.room` y recursos

### D12 — `newRoom` ejecuta todo en el momento del comando; nosotros, tras salir de la lógica
- **ScummVM** `op_cmd.cpp:253-257` llama a `vm->newRoom()` (`cycle.cpp:41-149`), que lo hace inmediatamente. Luego `exitAllLogics = true` corta la ejecución al terminar el comando.
- **Modelo** `py:675-679`: solo marca `newroom`/`exit_all`. El estado se cambia en `do_new_room` (`py:683-727`) al volver al bucle de `interpret_cycle`. **Z80** `agivm.asm:1386-1393`/`888-946`: igual.
- **Estado**: DIFERENTE de forma, **IGUAL de resultado** salvo en dos puntos:
  1. En ScummVM, `testIfCode` sale de la condición si `exitAllLogics` está puesto tras evaluar un comando de condición (`op_test.cpp:428-434`). Nosotros evaluamos las condiciones restantes de ese `if` (D13). Si una de ellas tiene efectos (said), se ejecutan.
  2. Las lógicas llamadas por `call` dentro del mismo ciclo ven el estado nuevo en ScummVM. Con `exit_all` ninguna sigue corriendo, así que no importa.

### D13 — `testIfCode` hace cortocircuito; nosotros evaluamos todas las condiciones
- **ScummVM** `op_test.cpp:442-462`: en modo Y, la primera condición falsa hace `skipInstructionsUntil(0xFF)` y no se evalúan las demás. En modo O, la primera cierta salta hasta el `0xFC`.
- **Modelo** `py:568-609` (bucle del `if`) y **Z80** `agivm.asm:743-850` (`do_if`, que acumula `c_res` y sigue): evalúan **todas**.
- **Estado**: DIFERENTE (modelo y Z80).
- **Efecto**: concreto.
  - `if (isset(f40) && said("take","key"))` con f40=0: ScummVM **no ejecuta** `said`, así que no pone f4. Nosotros sí lo ejecutamos: si la frase coincide ponemos f4=1 y `said_done`, y un `said` posterior en el mismo ciclo no puede coincidir.
  - Lo mismo con `have.key`, que en nuestro caso espera tecla en `txtm`.
  - Y con `controller`, que no tiene efectos.
- **Justificable**: no. Es un error de lógica (un `if` con `said` en segundo lugar).

### D14 — Lo que hace `newRoom` (comparación punto por punto)
- ScummVM `cycle.cpp:56-148` frente a `py:683-727` y `agivm.asm:888-946`.
- **IGUAL**:
  - Todos los objetos: `flags &= ~(fAnimated|fDrawn); |= fUpdate; stepTime=1; stepTimeCount=1; cycleTime=1; cycleTimeCount=1; stepSize=1`.
  - `playerControl = true`; `block.active = false`; `horizon = 36`.
  - `v1 = v0; v0 = n; v4 = 0; v5 = 0; v16 = ego.view`.
  - Reposición del ego por `v2` (1→167, 2→x=0, 3→horizonte+1, 4→160-ancho) y `v2 = 0` después.
  - `f5 = 1`.
  - Logic 0 no se descarga; las demás vuelven a `sIP=2` (`unloadResources`, `agi.cpp:182-192`).
  - Larry1: `f36 = 0` (`GID_LSL1`).
  - SQ1: `draw.pic(20)` pone `f103 = 0`.
- **DIFERENTE**:
  - **a)** El modelo borra la imagen y los `add.to.pic` (`py:690-693`, `self.pic_ops.append(('z',))`). ScummVM **no** borra la imagen en `newRoom`; sigue hasta el `draw.pic` siguiente. Efecto: si la lógica de la sala nueva consulta prioridades (`ego` en `reposition`, `fixPosition`, `checkPriority`) **antes** de su `draw.pic`, ScummVM usa la imagen anterior. Nosotros no. Z80 `agivm.asm:891` ("los add.to.pic se olvidan (siguen pintados…)") conserva la imagen, pero deja `st_n=0`. Es lo que ScummVM conserva en pantalla; el efecto en la prioridad no lo he podido comprobar.
  - **b)** `snd_stop()` en nuestro `do_new_room` pone las banderas de los sonidos pendientes (`py:1578-1582`). ScummVM llama a `_sound->stopSound()` (`cycle.cpp:62`). **No he leído `sound.cpp`**, así que no puedo decir si pone la bandera.
  - **c)** El modelo crea 32 objetos y no 255 (`NOBJ = 32`). ScummVM tiene `SCREENOBJECTS_MAX = 255` (`agi.h:80`). **Justificable** por memoria, mientras ningún juego use objetos ≥ 32 (comprobar con las 6 lógicas: ver §7).
  - **d)** `f2 = 0` y `v9 = 0` en `do_new_room`. ScummVM lo hace en el bucle de `interpretCycle`, justo después. Mismo efecto.

---

## 4. Objetos, movimiento, ciclo (en el orden en que se ejecutan en el ciclo)

### D15 — `animate.obj`
- **ScummVM** `op_cmd.cpp:1260-1282`: `if (flags & fAnimated) return; flags = fAnimated|fUpdate|fCycling; motionType = Normal; cycle = Normal; direction = 0`.
- **Modelo** `py:827-840`: IGUAL. Borra `drawn` e ignora/observa, y no toca `step`/`stime`/`ctime`, como ScummVM.
- **Estado**: IGUAL.

### D16 — `follow.ego`, `move.obj`, `wander`: ScummVM pone `fUpdate`; nosotros ponemos `mon` y no `upd`
- **ScummVM** `op_cmd.cpp:1669`, `1697`, `1750`: `flags |= fUpdate`.
- **Modelo** `py:1068` (`follow_ego`), `1054` (`move_obj`), `1074` (`wander`): ponen `o.mon = True` y **no** `o.upd = True`.
- **Estado**: DIFERENTE. (No he comprobado qué es `mon`. En `objbytes` va en el bit 4 de F1. ScummVM solo pone `fMotion` en `changePos`, `checks`/`motion.cpp:41-60`.)
- **Efecto**: un objeto con `stop.update` al que luego se le da `move.obj`/`follow.ego`/`wander` se vuelve a actualizar en ScummVM y sigue parado en el nuestro.

### D17 — `changePos` pone/borra `fMotion`
- **ScummVM** `motion.cpp:52-59`: `fMotion` se borra o pone según el cruce del bloque, y `direction = 0` (más `v6 = 0` en el ego).
- **Modelo** `py:1758-1764`: pone `dir = 0` y `v6 = 0`, pero no lleva el bit `fMotion`.
- **Estado**: FALTA el bit. Efecto: ScummVM no lee `fMotion` en ningún otro sitio de los ficheros que he leído, así que **sin efecto observable por lógica**. Lo anoto por completitud.

### D18 — `cyclerActivated`: FALTA
- **ScummVM** `motion.cpp:110-138`. Al llamar a `end.of.loop`/`reverse.loop` con un movimiento activo, el original pisaba el campo del movimiento con la bandera del ciclador:
  - Wander: `wander_count = loop_flag`.
  - FollowEgo: `follow_stepSize = loop_flag`.
  - MoveObj: `move_x = loop_flag`.
- Lo llaman `cmdEndOfLoop` (`op_cmd.cpp:1559`) y `cmdReverseLoop` (`1532`).
- **Modelo/Z80**: solo existe `motionActivated` (el `nolf`, `py:1049, 1064, 1073`; `agiobj.asm:654`). `cyclerActivated` no existe (`grep` en ambos).
- **Estado**: FALTA.
- **Efecto**: la nota de ScummVM dice que hace falta para las brujas de Black Cauldron (sala 12) y deja `move_x` = bandera. En juegos de nuestra lista (KQ1 sala 22 águila, KQ2) el comentario cita KQ1 y KQ2.
- **Justificable**: no.

### D19 — `follow.ego`, `move.obj`: detalles
- `cmdMoveObj` (`op_cmd.cpp:1675-1707`) llama a `moveObj` solo si `version > 0x2272`.
- `cmdFollowEgo` (1650-1673): `follow_flag`.
- **Modelo** `py:1046-1068`: IGUAL (`mstep`, `wander=255`, `flags[f]=0`, `nolf`).
- **Estado**: IGUAL, salvo D16 y D18.

### D20 — `motionWander`, `motionFollowEgo`, `motionMoveObj`, `getDirection`, `checkStep`
- **ScummVM** `motion.cpp:27-29, 140-224, 315-318`; **modelo** `py:1690-1764`.
- **IGUAL** en la lógica. Se compararon línea a línea:
  - wander: `wander_count--`; con `orig==0` o `fDidntMove`, dirección al azar `0..8` y `wander_count = random(50)` hasta ≥ 6.
  - follow: centros en x, `follow_count`, dirección al azar nunca 0 si `fDidntMove`, decremento por `stepSize`.
  - moveObj: dirección por `checkStep`.
- Los números aleatorios no pueden ser iguales (otro generador). **Justificable** (hardware: LFSR).
- La distribución de `wander`: `rand8() % 9` y `% 51` (módulo) frente a `getRandomNumber(8)`/`(50)` (uniforme). Sesgo mínimo. **Justificable**.

### D21 — `checkMotion` y bloques
- **ScummVM** `motion.cpp:226-246`.
- **Modelo** `py:1743-1764`: IGUAL (usa `<` estricto en `checkBlock`, `motion.cpp:31-39`).
- **Estado**: IGUAL.

### D22 — `updateScreenObjTable` (selección de bucle y ciclo): IGUAL, con un recorte nuestro
- **ScummVM** `view.cpp:675-732`.
- **IGUAL**:
  - Tablas `loopTable2`/`loopTable4`.
  - `stepTimeCount == 1` para cambiar de bucle.
  - Cuenta atrás del ciclo y `updateView`.
  - `updateView` (`view.cpp:48-105`) con end.of.loop y reverse.loop.
  - El `fDontUpdate`.
- **Modelo** `py:1848`: **recorte propio**. Con `v10 <= 1` y un objeto distinto del ego, `ctype == 0`, `motion == 0`, `dir == 0`, **no cambia de celda** aunque `ccount` llegue a 0.
- **Estado**: DIFERENTE. Es un truco de rendimiento ("Speed Fast/Fastest").
- **Efecto**: `current.cel` de ese objeto no avanza y las lógicas que leen la celda (`last.cel`, `current.cel`) ven otra cosa.
- **Justificable**: por hardware, pero cambia el estado visible por las lógicas. **Hay que decidir y documentar.**
- Z80: NO COMPROBADO.

### D23 — `updatePosition`: orden de operaciones y puesta a cero de v2, v4 y v5
- **ScummVM** `checks.cpp:187-289`. Pone `v5=0; v2=0; v4=0` al empezar, **solo si hay algún objeto** (`view.cpp:723`, `changeCount`).
- **Modelo** `py:1962-1964`; **Z80** `agivm.asm:234-237`: IGUAL (v2 solo con objetos, v4 y v5 siempre, además en `interpretCycle:200-201`).
- **Estado**: IGUAL.
- **Comprobado igual**:
  - Cálculo de bordes (`checks.cpp:219-263`): orden izquierda, derecha, arriba, abajo, horizonte.
  - Códigos de borde 1-4.
  - `border` anulado si falla la colisión o la prioridad (`checks.cpp:268-273`).
  - `motionMoveObjStop` si borde y `kMotionMoveObj`.
  - `fUpdatePos` borrado (`287`).

### D24 — `checkCollision`: usa `yPos_prev` de **ambos** objetos; nosotros usamos la posición actual
- **ScummVM** `checks.cpp:95-100`:
  ```
  if ((screenObj->yPos > checkObj->yPos && screenObj->yPos_prev < checkObj->yPos_prev) ||
      (screenObj->yPos < checkObj->yPos && screenObj->yPos_prev > checkObj->yPos_prev))
  ```
- **Modelo** `py:1616`: `(o.y < q.y <= y) or (y < q.y <= o.y)`. Usa la `y` actual del objeto como "anterior" y la `y` actual de `q`.
- **Estado**: DIFERENTE.
  - `yPos_prev` solo se actualiza en `showSprites` (`sprite.cpp:360-368`, con `stepTimeCount == stepTime`) y en `position`/`draw`/`addToPic`.
  - La del otro objeto es **su** `yPos_prev`, no su `yPos`.
- **Efecto**: cuando otro objeto se ha movido este ciclo, o cuando el objeto ha sido recolocado con `reposition.to` (que no toca `*_prev`), el cruce de línea base da otro resultado. Casos típicos: el ego rodeando a un NPC que camina, `fixPosition` tras `reposition`.
- **Justificable**: no (hace falta guardar `yPos_prev` por objeto; 1 byte).
- Z80: NO COMPROBADO.

### D25 — `fDidntMove` (`dm`)
- **ScummVM** `sprite.cpp:352-369`. Solo para los objetos de la lista regular (animados, `fUpdate`, dibujados, vista cargada, dentro de pantalla). Solo si `stepTimeCount == stepTime`. `if pos == pos_prev { fDidntMove } else { prev = pos; ~fDidntMove }`.
- **Modelo** `py:1806`: `dm = (x,y) == (ox,oy)`, comparando con la posición **antes del paso de este ciclo**.
- **Estado**: DIFERENTE.
  - Tras `reposition.to`/`reposition` (que no tocan `*_prev`), ScummVM ve "movido" y borra `fDidntMove`; nosotros lo ponemos si el paso no movió.
  - Si el objeto se coloca con `position` (`_prev = pos`), coincide.
- **Efecto**: wander y follow.ego usan `fDidntMove` para elegir otra dirección. Tras un `reposition.to` el objeto no se gira en ScummVM y sí en el nuestro.
- **Justificable**: no.

### D26 — `checkPriority` / `fixPosition` / `checkPosition`
- **ScummVM** `checks.cpp:27-63, 106-174, 305-352`; **modelo** `py:876-911, 1622-1665`.
- **IGUAL**:
  - Recorrido de píxeles, `touchedWater`/`touchedControl`/`touchedTrigger`, `f0` y `f3` del ego aunque se rechace.
  - `fOnWater`/`fOnLand`.
  - Espiral de `fixPosition` (O, S, E, N con `size` creciente).
  - Prioridad 15 = sin comprobación.
  - Tabla de prioridad por defecto (`graphics.cpp` `createDefaultPriorityTable`): 4 hasta y<48, luego +1 cada 12.
- **DIFERENTE**:
  - Tope de 170 vueltas en `fix_position` (`py:892`): ScummVM no tiene tope. **Justificable** (evitar bucle infinito).
  - `set.pri.base` (`op_cmd.cpp:2255`, solo 2.425 y ≥ 2.936) **no existe** en el modelo. FALTA; solo importa si algún juego lo usa.
  - El KQ3 `ladder` (`checks.cpp:168`) no aplica.
  - `use_pic`: sin imagen, `can_be_here` devuelve cierto (`py:1618`). ScummVM siempre tiene tabla de prioridad. Sin efecto con imagen.

### D27 — `setView`/`setLoop`/`setCel` y `v16`
- **ScummVM** `view.cpp:475-608`:
  - `setView`: si el bucle actual ≥ nº de bucles → bucle **0**; si no, se conserva. Luego `setLoop` (si la celda actual ≥ celdas → celda **0**).
  - `setLoop` con bucle ≥ nº de bucles → **el último**.
  - `setCel` con celda ≥ nº de celdas → la última.
  - Cada paso acaba en `clipViewCoordinates` (`view.cpp:615-632`).
  - **No toca `v16`.** Solo `newRoom` lo escribe (`cycle.cpp:84`; `grep` en todo `engines/agi`).
- **Modelo** `py:190-199` (`cell`): `o.loop = min(o.loop, n-1)` y `o.cel = min(o.cel, len-1)` en **todos** los casos. `py:927-934` pone `v16 = view` si es el ego. **Z80** `agiobj.asm:276` y `agic.asm:1221` escriben `VARS+16`.
- **Estado**: DIFERENTE en cuatro cosas:
  1. `set.view` con bucle fuera de rango: ScummVM → bucle 0; nosotros → el último.
  2. `set.view`/`set.loop` con celda fuera de rango: ScummVM → celda 0; nosotros → la última.
  3. `v16` se escribe en `set.view` del ego (no lo hace ScummVM).
  4. `set.cel` fuera de rango sí es el último en ambos (IGUAL).
- **Efecto**: una lógica que cambia de vista y deja el bucle/celda viejos ve otra celda y otras dimensiones (y por tanto otro `fixPosition`, otra colisión). Un `v16` distinto cambia lo que leen las lógicas que usan `v16`.
- **Justificable**: no. El comentario del modelo dice "como en AGI", pero ScummVM no lo hace.

### D28 — `clipViewCoordinates`
- **ScummVM** `view.cpp:615-632`. **Modelo** `py:1677-1688`: IGUAL (`fUpdatePos` incluido).
- **Estado**: IGUAL.

### D29 — `set.cel`/`set.loop`/`fix.loop`/`end.of.loop`/`reverse.loop`/`normal.cycle`/`reverse.cycle`
- **ScummVM** `op_cmd.cpp:456-531, 571-589, 1521-1560`.
- **Modelo** `py:948-1026`.
- **IGUAL**: efectos sobre `fDontUpdate`/`fCycling`/`cycle`; `setFlag(loop_flag,false)`.
- **Estado**: IGUAL (salvo D27 y D18).

### D30 — `reposition`, `reposition.to`, `position`, `get.posn`, `distance`
- **ScummVM** `op_cmd.cpp:1354-1475, 1405-1413, 1912-1965`.
- **Modelo** `py:864-925, 994-1000`: **IGUAL**.
  - `position` pone `_prev`; `reposition.to` no.
  - Recorte de `reposition` negativo.
  - `distance` con centros en x y tope 254.
- **Estado**: IGUAL, con la consecuencia de D24/D25: el modelo no lleva `*_prev`.

### D31 — `add.to.pic`
- **ScummVM** `sprite.cpp:439-480` y `op_cmd.cpp:1477-1510`.
- **Modelo** `py:751-768`.
- **DIFERENTE**:
  1. El margen: ScummVM dibuja la caja de prioridad si `border <= 3` (`sprite.cpp:473`). El modelo: `margin < 3` (`py:763`). Con `border == 3` ScummVM dibuja una caja con prioridad 3 (agua). El modelo lo omite (comentario: "El valor 3 (agua) no se admite"). **Justificable** (el Z80 usa 2 bits) pero cambia `f0` del ego.
  2. ScummVM aplica `fixPosition` al objeto añadido (con `fIgnoreObjects|fIgnoreHorizon|fFixedPriority`, prioridad 15, `sprite.cpp:455-459`). Eso mueve el objeto si queda fuera de pantalla (`checkPosition`). El modelo no lo hace.
  3. Límite de 48 (`ST_MAX`) `add.to.pic` por imagen. ScummVM no tiene límite. **Justificable** (memoria).
  4. `priority == 0` (`sprite.cpp:460-469`): se calcula con `priorityFromY(yPos)` **después** del `fixPosition`. El modelo usa la `y` original.

### D32 — Bandera f1 (EGO_INVISIBLE)
- **ScummVM** `sprite.cpp:269-271`: `drawCel` del ego pone `f1 = isViewHidden` (hay prioridad que lo tape por completo).
- **Modelo**: `grep flags[1]` no aparece. **Z80**: `grep FLAGS+1\b` no aparece en `ENGINE/*.asm`.
- **Estado**: FALTA.
- **Efecto**: las lógicas que leen `f1` ("ego tapado") siempre ven 0.
- **Justificable**: el dibujo lo hace el hardware de sprites. Se podría calcular desde el plano de prioridad. **Hay que decidir.**

### D33 — `stop.motion`, `start.motion`, `player.control`, `program.control`
- **ScummVM** `op_cmd.cpp:1600-1648`.
- `stop.motion`: `direction = 0; motionType = Normal; ego → v6 = 0, playerControl = false`.
- `start.motion`: igual, con `playerControl = true`.
- `player.control`: `playerControl = true` y `motionType = Normal` salvo `kMotionEgo`.
- **Modelo** `py:1029-1041, 1083-1085`: IGUAL (`kMotionEgo` no existe: viene del ratón).
- **Estado**: IGUAL.

### D34 — `set.dir`, `get.dir`, `step.size`, `step.time`, `cycle.time`, `block`, `unblock`, `ignore/observe *`, `object.on.*`, `set.horizon`, `get.priority`, `set.priority`, `release.priority`, `fix.loop`
- **ScummVM** `op_cmd.cpp:304-405, 519-556, 591-605, 1575-1591`; **modelo** `py:967-992, 1043-1044, 1079-1080`.
- **Estado**: IGUAL.
- Nota: `step.time` y `cycle.time` aceptan 0 como ScummVM (el comentario del modelo lo menciona).

---

## 5. Texto, entrada de línea, cadenas

### D35 — `parse` de la frase: palabras `a`/`i`, id 0, palabra desconocida y f2
- **ScummVM** `words.cpp:247-391`.
  1. Las palabras de **una letra `a` o `i`** se ignoran (`DICTIONARY_RESULT_IGNORE = 0`) **aunque no estén en el diccionario** (`words.cpp:265-268`).
  2. Los ids 0 del diccionario también son "ignorar" y no se cuentan.
  3. Una palabra desconocida se cuenta en `egoWordCount` (`words.cpp:368-376`): `v9 = wordCount`, `break`.
  4. `f2 = (egoWordCount > 0)`; `f4 = 0`.
  5. Solo se parsea cuando el prompt tiene algo (`text.cpp:857`).
- **Modelo** `py:452-471` y `py:1910` (`flags[2] = 1`); **Z80** `agiin.asm:862-` y `ev_text` (`:92`, `f2 = 1`).
- **Estado**: DIFERENTE en cuatro cosas:
  1. `a`/`i` ausentes del diccionario: ScummVM las ignora; nosotros las damos como desconocidas (`v9 = n`).
  2. Palabra desconocida: ScummVM pone **`f2 = 1`** y la cuenta como palabra de id 0. Nosotros ponemos `f2 = 1` siempre, pero `say()` falla con `v9 != 0` (D36).
  3. **`f2 = 1` aunque no haya palabras** (frase solo con palabras de ignorar, como "the"). ScummVM: `f2 = 0`. Nosotros: `f2 = 1`, y la lógica 0 típica ("if (isset(f2) && !isset(f4)) print I don't understand") responde con el mensaje de "no entiendo". ScummVM no responde.
  4. `%w`/`word.to.string` devuelve la palabra en minúsculas (`py:466-467`). ScummVM conserva el original (`words.cpp:368`: `userInput` sin pasar a minúsculas; solo `userInputLowercase` se usa para comparar).
- **Efecto**: concreto en 2 y 3 (ver arriba).
- **Justificable**: 4, sí (el ZX81 solo teclea mayúsculas). 1-3, no.

### D36 — `testSaid` no mira `v9`; nosotros sí
- **ScummVM** `op_test.cpp:336`: `if (f4 || !f2) return false;`. No mira `v9`.
- **Modelo** `py:474`: `self.input is None or flags[4] or vars[9]` → falso. **Z80** `agiin.asm:1146-1148` (`hc_said`): igual.
- **Estado**: DIFERENTE.
- **Efecto**: con una palabra desconocida, ScummVM puede dar `said(…, anyword)` (1) o `said(…, 9999)` ciertos (la palabra desconocida tiene id 0 y se compara con el patrón). Nosotros nunca. Las lógicas que atienden `v9` en la lógica 0 antes de `said` no lo notan. Las que no lo hacen, sí.
- **Justificable**: no.

### D37 — Normalización de la frase y del diccionario
- **ScummVM** `words.cpp:181-245`.
  - Separan: espacio `, . ? ! ( ) ; : [ ] { }`.
  - Se **quitan sin separar**: `' ` - \ "`.
  - Todo lo demás se queda dentro de la palabra.
  - El diccionario se compara tal cual.
- **Modelo** `agi_read.py:506-510` (`norm_word`) y **Z80** `agiin.asm:884-901` (`parse_text`): quitan `' ` - " .` (el punto **sin separar**) y separan todo lo que no sea letra/cifra. El diccionario se normaliza igual.
- **Estado**: DIFERENTE.
  - `take.sword` es una palabra en nuestro caso y dos en ScummVM.
  - `\` separa en nuestro caso y se quita en ScummVM.
  - Caracteres como `+ = / @ #` se quedan dentro de la palabra en ScummVM y separan en el nuestro.
  - Máximo 16 tokens en el Z80 (`agiin.asm:907`).
- **Justificable**: en parte (símbolos caros en el ZX81, comentario de `norm_word`). Pero cambia el significado de las frases con `.`. **Documentar** o igualar los separadores.

### D38 — Selección de palabra del diccionario: último/primero por orden de fichero
- **ScummVM** `words.cpp:271-307`: recorre las palabras de la letra, y cada coincidencia completa sobrescribe la anterior (sale en la coincidencia perfecta).
- **Modelo** `py:459-465`: prueba de más larga a más corta.
- **Estado**: DIFERENTE en el algoritmo. **Iguales** mientras el diccionario esté ordenado alfabéticamente y las frases largas sean prefijo más largo (siempre en `WORDS.TOK` estándar). No verificado con los 6 diccionarios.

### D39 — `set.string` no hace `printf`; los textos son de 39 caracteres; hay 25 cadenas
- **ScummVM** `op_cmd.cpp:2136-2141`: `setString(stringNr, texts[textNr])`, sin `stringPrintf`. `setString` (`agi.cpp:855-862`) hace `strlcpy(…, MAX_STRINGLEN=40)` → 39 caracteres.
- Cadenas `0..24` (`MAX_STRINGS = 24`, `agi.h:83`).
- **Modelo** `py:1311`: `self.strs[s] = self.msg(m)[:40]`, y `msg()` aplica `fmt` (`py:446-449`). `strs = [''] * 12` (`py:80`). **Z80** `agiin.asm:286-296`: `cp 12 / ret nc` y `build_str` con `ld c,40`; no he leído `build_str`.
- **Estado**: DIFERENTE en cuatro cosas:
  1. `set.string` aplica el formato (`%v`, `%w`…) en el modelo; ScummVM copia el texto en bruto y lo formatea al imprimir.
  2. 40 frente a 39 caracteres.
  3. Solo 12 cadenas frente a 25. Las cadenas 12-24 se ignoran (`ret nc`).
  4. `%s` en un mensaje formatea recursivamente la cadena (ver D41).
- **Efecto**: un `set.string(s, "Score %v3")` guarda ya la puntuación sustituida. En ScummVM guarda el texto, y cada vez que se imprime, el valor actual.
- **Justificable**: 3, sí (memoria). 1 y 2, no.

### D40 — Comandos que faltan del todo
- **ScummVM** `opcodes.cpp:179-363` (tabla v2). Sin función en el modelo (`cmd()` los anota como `noop`, `py:626-631`):

  | Comando | Efecto en ScummVM |
  |---|---|
  | `hold.key` (0xAD) | `_keyHoldMode = true` (`op_cmd.cpp:1057`) |
  | `release.key` (0xB5) | — |
  | `set.pri.base` (0xAE) | — |
  | `set.speed` | `speedLevel` (v1) |
  | `adj.ego.move.to.x.y`, `fence.mouse`, `get.mse.posn`, `hide/show.mouse` | solo con ratón |
  | `set.simple`, `push/pop.script` | `set.simple` activa el guardado automático |
  | `script.size` | — |
  | `cmdToggleMonitor`, `trace.*`, `init.joy` | no hacen nada |

- **Estado**: FALTA `hold.key`/`release.key` (D03), `set.pri.base`. Los demás no importan sin ratón. El modelo sí implementa `echo.line`/`cancel.line` como `pass` (`py:1363-1364`): ScummVM sí hace algo (rellena/limpia la línea de entrada; `text.cpp:893-923`). Solo cambia la línea de entrada, no el estado de las lógicas.
- **Justificable**: ratón, sí. `hold.key`: el ZX81 ya mantiene el modo "mantener" por defecto (D03).

### D41 — `stringPrintf` (formato de mensajes)
- **ScummVM** `text.cpp:1304-1383`.
- **Modelo** `py:421-437`.
- **DIFERENTE**:
  1. `%vNN|W`: relleno con ceros a ancho `W`. El modelo ignora `|W`.
  2. `%0N`: nombre del objeto N−1 (`text.cpp:1341-1344`). **FALTA** en el modelo (el regex solo reconoce `[vmsgw]`).
  3. `%sN`: formatea la cadena N recursivamente (`1353-1356`). El modelo devuelve la cadena en bruto, y solo para N < 12.
  4. `%mN`: formatea recursivamente el mensaje N (`1357-1361`). El modelo devuelve el mensaje en bruto.
  5. `\` + carácter: el carácter literal (`1370-1372`). No visto en el modelo.
  6. Formatea el valor como entero sin signo, sin ceros (`i = 99` caso): IGUAL.
- **Justificable**: no. Nombres de objetos con `%0` son frecuentes en las respuestas del juego ("You take the %o1").

### D42 — `print` / `print.at` / `display`
- **ScummVM** `text.cpp:240-287, 402-426, 428-478`.
- **Ventana bloqueante**: `messageBox` espera ENTER, ESC o el temporizador (`v21 × 20` ciclos), ignora las demás teclas y pone `v21 = 0` al cerrar. Con `f15` (OUTPUT_MODE) pone la ventana y **sigue** (`f15 = 0`).
- **Modelo** `py:1181-1213`: cualquier tecla cierra (`if len(self.keyq) > n: break`, sin mirar cuál); `v21*25` vueltas (no `*20` ciclos de 25 ms, hay que ver el factor real). Con `f15` no espera, IGUAL.
- **Estado**: DIFERENTE: cualquier tecla cierra la ventana. En ScummVM solo ENTER/ESC. ESC marca `_messageBoxCancelled`. Lo usan `restart.game`, `save.game`, etc., con la tecla (`py:1160`).
- **Justificable**: parcialmente (en el ZX81 no hay ESC; la ayuda dice "pulsa cualquier tecla").
- **Z80**: `agiin.asm:437-492` (`pr_wait`) NO LEÍDO a fondo.
- Aparte: `print` con número de mensaje fuera de rango se ignora en ScummVM (`text.cpp:404`). Modelo: `msg()` devuelve `''` y abre una ventana vacía. **DIFERENTE**.
- `display` (`text.cpp:247`): mismo patrón (`textNr` fuera de rango no dibuja). Modelo: dibuja vacío. Sin efecto visible.

### D43 — `get.string` y `get.num`
- **ScummVM** `op_cmd.cpp:1999-2097`:
  - `get.string` es **bloqueante**: no corre ningún ciclo, y ESC deja la cadena vacía y sale.
  - `get.num` también es bloqueante: pide hasta 3 cifras y guarda `atoi(...)` (byte).
- **Modelo** `py:1315-1349`:
  - `get.string` corre "ciclos" (`apply_events`) hasta que llega una línea.
  - **`get.num` NO espera**: toma `textq.pop(0)` o `'0'` si no hay (`py:1348`).
  - `get.string` no trata ESC.
- **Estado**: DIFERENTE.
- **Efecto**: `get.num` en el modelo devuelve 0 si el evento no estaba preparado.
- **Z80**: `agiin.asm:732-796` (`h_get_string`, `h_get_num` → `OVC_GETNUM`) NO LEÍDO.

### D44 — Línea de estado, `set.text.attribute`, `clear.lines`, `clear.text.rect`
- **ScummVM** `op_cmd.cpp:2160-2197`; `text.cpp:652-695`.
- **Estado**: NO COMPARADO. Es presentación: el modelo ya lleva sus propias reglas (`agi_text.py`, no leído).
- Una cosa sí de estado: ScummVM redibuja la línea de estado al cambiar `v3` o `f9` (`cycle.cpp:197-198`); el modelo, en `status_tick` (`py:1300-1309`) con `(v3, v7, f9)`. **IGUAL en efecto**.

### D45 — `status` (inventario) y `v25`
- **ScummVM** `inv.cpp:43-206`, `op_cmd.cpp:1860-1874`. Pasa a pantalla de texto.
- **Lista de objetos en 2 columnas, ordenada por número de objeto.**
- Con `f13`: el elemento activo empieza en el objeto igual a `v25`, y ENTER devuelve el nº de objeto en `v25`, ESC devuelve 255.
- **Con el inventario vacío y `f13`**, hay una entrada falsa "Nothing" con `objectNr = 0` y `_activeItemNr = 0`, así que ENTER deja **`v25 = 0`** (`inv.cpp:95-104`, `191-196`).
- **Modelo** `py:1100-1128`: con `f13` y sin objetos pone `v25 = 255` sin esperar; con objetos usa un menú de una columna (empieza en el primero, no en `v25`).
- **Estado**: DIFERENTE (presentación, justificable); la semántica de `v25` con inventario vacío y el comienzo en `v25` son lógica visible.
- **Justificable**: la presentación sí. `v25` no.

### D46 — Menús: momento de ejecución, selección recordada, `submit.menu`, `restart`
- **ScummVM** `op_cmd.cpp:744-748`, `menu.cpp:308-403, 494-`.
- `menu.input` **solo marca** `_delayedExecuteViaKeyboard`. El menú se ejecuta en el siguiente `processAGIEvents`, o sea **fuera de la lógica**, antes del ciclo siguiente. El controlador del elemento (`controllerOccurred[slot] = true`) lo ve la lógica del ciclo siguiente.
- Requisitos de `execute` (`menu.cpp:321-`): `_submitted` (por `submit.menu`) y `_allowed`.
- Recuerda `_lastSelectedMenuNr` y el elemento seleccionado de cada menú.
- ENTER sobre elemento desactivado se ignora; ESC sale.
- **Modelo** `py:1401-1450` (y **Z80** `agiin.asm:518-` `h_menu_input`): ejecuta el menú **inmediatamente** dentro de la lógica y añade el controlador a `ctl` en el mismo ciclo. `submit.menu` es `pass`. Siempre empieza en el menú 0, elemento 0.
- **Estado**: DIFERENTE en tres cosas:
  1. El momento (el resto de la lógica del ciclo ve el controlador ya puesto).
  2. `submit.menu` no se exige.
  3. No se recuerda la selección.
- **Efecto**: una lógica que llama a `menu.input` y luego comprueba `controller(X)` en el mismo ciclo ve el controlador en el nuestro y no en ScummVM.
- **Justificable**: la inmediatez, tal vez (el menú del ZX81 es un bucle modal); lo demás, no.
- `restart.game`: ScummVM hace `itemEnableAll()` (`op_cmd.cpp:1908`). El modelo (`RESTART_FIELDS`, `py:1154-1155`) **no incluye `menus`**, así que los elementos desactivados siguen desactivados. DIFERENTE (el `restore.game` sí los reactiva, `py:1509-1511`).
- Z80: NO COMPROBADO.

### D47 — `restart.game`
- **ScummVM** `op_cmd.cpp:1894-1910`. Si `f16` (AUTO_RESTART) está puesto, reinicia **sin preguntar**. Si no, `restartDialog()`.
- Pone `_restartGame` y `f6 = 1`. `runGame` repite `agiInit` (todo a 0 salvo `strings`, `agi.cpp:121-123`).
- **Modelo** `py:1157-1174`: siempre pregunta (ignora `f16`). Mantiene `f6`/`f5` con `rs_keep`.
- **Estado**: DIFERENTE: `f16` no se mira. Efecto: un `restart.game` con `f16` pregunta cuando no debe.
- `RESTART_FIELDS` (`py:1154-1155`) no incluye `strs`: correcto, ScummVM conserva las cadenas en un restart (`agi.cpp:121-123`). Sí incluye `inv`, `keys`, `flags`, `vars` y `objs`, que `agiInit` reinicia. No he comparado campo a campo con `agiInit`.

### D48 — `save.game`/`restore.game`
- **ScummVM** `saveload.cpp:345-757` (`loadGame`), `805-824` (`doLoad`).
- **IGUAL**:
  - `f12 = 1`.
  - `exitAllLogics = true` tras cargar.
  - Se restauran flags, vars, strings, objetos, controladores (`set.key`), sIP/cIP, tabla de objetos, `horizon`, `playerControl`.
  - `v8 = 180` se re-escribe.
  - `clearEgoWords` (no `f2`; pero el bucle de `interpretCycle` pone `f2 = 0`).
  - `itemEnableAll`.
- **DIFERENTE**: ScummVM re-escribe `v8 = 180` tras cargar (`saveload.cpp:480`). El modelo no escribe `v8`.
- Presentación (12 ranuras, diálogos): no comparada. **Justificable**.
- `saveGame` (`saveload.cpp:70-344`): **NO LEÍDO**.

### D49 — `cmdParse` (`parse(s)`)
- **ScummVM** `op_cmd.cpp:1120-1128`: `v9=0; f2=0; f4=0` y luego `parseUsingDictionary(stringPrintf(string))`.
- Nota: aplica `stringPrintf` a la cadena antes de parsear.
- **Modelo** `py:1354-1360`: cadena vacía → `f2=0` y salir. No pone `v9=0` ni `f4=0` explícitamente (lo hace `parse()` para v9, `py:456`; `f4` no). Con cadena vacía no toca `v9` ni `f4`.
- **Estado**: DIFERENTE: `f4` no se borra; `stringPrintf` no se aplica; y `f2 = 1` aunque no haya palabras (D35).

### D50 — `cmdSetKey`/`controller` y `resetControllers`
- Ya en D06. Nota: `resetControllers` se llama **dos veces** (dentro del `while` y tras él; `cycle.cpp:183, 193`). Modelo: `clr_ctl` al inicio del ciclo y tras `new.room` (`agivm.asm:195, 218`). **IGUAL en efecto**.

### D51 — `random`
- **ScummVM** `op_cmd.cpp:162-168`: `random(max-min) + min` (rango inclusivo).
- **Modelo** `py:670-672`: `lo + rand8() % (hi - lo + 1)`. Con `hi < lo`, ScummVM tiene un comportamiento extraño; el nuestro pone `lo`.
- **Estado**: IGUAL como rango. El generador es distinto. **Justificable** (hardware).

### D52 — `put` / `put.v` y la lectura de los parámetros
- **ScummVM** `op_cmd.cpp:615-630`:
  ```
  void cmdPut(...)  { objectNr = parameter[0]; varNr = parameter[1]; byte varVal = vm->getVar(varNr); vm->objectSetLocation(objectNr, varVal); }
  void cmdPutF(...) { varVal1 = getVar(p0); varVal2 = getVar(p1); objectSetLocation(varVal1, varVal2); }
  ```
  Tabla (`opcodes.cpp:275-276`): `put "nn"`, `put.v "vv"`.
- **Nuestro decompilador** (`agi_logic.py:43`): `put (i, n)` y `put.v (i, v)`.
- **Modelo** `py:1091-1092` y **Z80** `agivm.asm:1458-1471`: `put(o, r)` guarda `r` **literal**, y `put.v(o, v)` guarda `v[v]` con el objeto **literal**.
- **Estado**: DIFERENTE en este commit de ScummVM.
- **Pero**: la tabla de ScummVM llama `nn` al segundo parámetro de `put` y el código lo trata como variable. Es incoherente consigo misma. **No he podido determinar cuál es correcta para los juegos reales** sin datos. Hay que verificarlo contra la lógica de un juego (p. ej. un `put(oX, N)` cuya sala N se conozca) antes de cambiar nada.
- **No adopto la lectura de ScummVM sin comprobarlo.** Sospecha: error de esta copia de ScummVM o un cambio reciente. Prioridad alta de verificación.

---

## 6. Qué es IGUAL (leído y comparado)

- `testSaid` (la coincidencia de palabras: 1 = cualquiera, 9999 = resto), salvo D36.
- `cond`: `equal*`, `less*`, `greater*`, `isset*`, `has`, `obj.in.room`, `posn`, `controller`, `compare.strings` (separadores `' ' \t - . , : ; ! '`; el modelo usa una expresión equivalente `py:538`).
- `obj.in.box`, `center.posn`, `right.posn`: IGUAL salvo D53.
- `increment` (tope 255), `decrement`, `assign*`, `add*`, `sub*`, `mul*`, `div*` (división por cero: ScummVM se cuelga; el modelo da 0), `lindirect*`, `rindirect`, `set/reset/toggle (+v)`: IGUAL.
- `newRoom` (núcleo), `animate.obj`, `draw`, `erase`, `position`, `reposition(.to)`, `get.posn`.
- `distance`, `stop/start.motion`, `player/program.control`, `step.*`, `cycle.time`, `block`, `unblock`, `ignore/observe`, `object.on.*`, `fix/release.loop`, `set/release.priority`.
- `updateView`, `loopTable`, `clipViewCoordinates`, `updatePosition` (bordes), `checkPriority`, `fixPosition`, `checkPosition`.
- `wander`/`follow.ego`/`move.obj` y sus fases de movimiento (salvo D16, D18).
- `loadGame` (núcleo).
- Reloj `v11-v14`: **no comparado** (ScummVM usa `inGameTimerUpdate`, que no he leído).

### D53 — `obj.in.box`/`center.posn`/`right.posn` con objeto no dibujado
- **ScummVM** `op_test.cpp:305-326` usa `xSize` siempre (conserva el último tamaño aunque no esté dibujado).
- **Modelo** `py:541`: `w, h = (0, 0)` si no está dibujado.
- **Estado**: DIFERENTE.
- **Efecto**: tras `erase`, `obj.in.box` y `right.posn` dan otra cosa en el nuestro (ancho 0).

### D54 — `show.obj`
- **ScummVM** `sprite.cpp:395-424`: dibuja la vista (objeto 255, prioridad 15) y muestra la descripción en un messageBox.
- **Modelo** `py:1130-1150`: igual en efecto sobre el estado (solo una ventana). Presentación. **Justificable**.

### D55 — Imágenes: `draw.pic`, `overlay.pic`, `load.pic`, `show.pic`, `discard.*`
- **ScummVM** `op_cmd.cpp:1166-1250`. `draw.pic` borra los sprites, decodifica, reconstruye y redibuja. `show.pic`: `f15 = 0`, `closeWindow`.
- **Modelo** `py:729-824, 1225-1228`: IGUAL en estado (`f15`, ventana).
- `picture.cpp` **NO LEÍDO**; las diferencias de dibujo no están auditadas.

---

## 7. LO QUE NO PUDE LEER O COMPARAR (honesto)

### ScummVM (`engines/agi`)

**Leídos enteros** (línea 22 hasta el final, 14 ficheros):

- `agi.cpp`, `op_cmd.cpp`, `op_test.cpp`, `logic.cpp`, `cycle.cpp`, `motion.cpp`, `checks.cpp`
- `sprite.cpp`, `view.cpp`, `keyboard.cpp`, `text.cpp`, `words.cpp`, `inv.cpp`, `objects.cpp`

**Leídos solo en parte:**

| Fichero | Qué se leyó |
|---|---|
| `opcodes.cpp` | líneas 30-420 (tablas v1/v2 y `setupOpCodes`; no 420-531) |
| `saveload.cpp` | 345-757 (`loadGame`), 805-824, 943-1012 |
| `menu.cpp` | `keyPress`, `execute`, `delayedExecute*` por `sed`; no el fichero entero |
| `graphics.cpp` | solo `createDefaultPriorityTable`, `setPriorityTable`, `priorityToY/FromY`, `checkControlPixel` (por `sed`) |
| `agi.h` | líneas 195-330 (enums de variables y banderas) y `grep` de constantes |

**NO leídos:**

- `picture.cpp` (864), `systemui.cpp` (1234)
- Resto de `graphics.cpp` (1570)
- Resto de `saveload.cpp`, incluido `saveGame` (70-344), y `menu.cpp`
- Resto de `agi.h`
- `sound*.cpp` — no sé si `stopSound` pone la bandera (afecta a D14b y a `c_sound`)
- `loader*.cpp`, `console.cpp`, `op_dbg.cpp`, `font.cpp`, `global.cpp`, `lzw.cpp`, `wagparser.cpp`, `metaengine.cpp`, `detection*.`
- `preagi` (descartado a petición)

Consecuencias: no puedo afirmar nada del dibujo de imágenes ni de los sonidos. Del reloj `inGameTimerUpdate` (`v11-v14`, y el avance de ciclos por `v10`) tampoco: es un punto del flujo (a) que queda **sin auditar**.

### Nuestro lado

- **Modelo `agi_vm.py`**: leído 71-215 (init), 412-1999. No leído 215-412 (dibujo de sprites) ni 2000-2041 (`main`).
- **Z80**: leídos `agivm.asm` 186-295 y 676-955, `agiin.asm` 15-195, 286-296, 862-925 y 1130-1250. Más `grep` de etiquetas y de `FLAGS+1`, `VARS+16`, `cyclerAct`.
- **NO leídos**: `agic.asm`, `agiobj.asm` (`update_objects`, `fix_position`, motion), `agipic.asm`, `agia.asm`, `agie.asm`, `agid.asm`, `agib.asm`, `agisw.asm`, `agihws.asm`, `agispr.asm`, `agiview.asm`, `agicel.asm`, `mcu.asm`.
- Todo el movimiento y los objetos del Z80 (`OVC_PRE`, `update_objects`, `obj_cell`, `fix_position`) quedan **sin auditar contra ScummVM**. Cada vez que escribo "modelo y Z80" me refiero al modelo y a las líneas del Z80 anteriores. En los demás casos, el Z80 hereda el defecto **solo por suposición** ("el modelo se validó contra el Z80"), que no he verificado.
- `agi_text.py` (ajuste de línea, ventanas) no comparado con `stringWordWrap`/`drawMessageBox`.
- La comprobación de si algún juego usa objetos ≥ 32, cadenas ≥ 12 o `set.pri.base` (D14c, D39, D26) no la hice.

---

## 8. Casos de prueba que deberían añadirse a la batería

Cada uno ejercita una diferencia concreta. Formato: lógica de prueba → resultado esperado según ScummVM.

1. **D13 (cortocircuito)**: `if (isset(f40) && said(take, key)) {…}` con f40=0 y la frase "take key" tecleada. Esperado: **f4 sigue a 0** y un segundo `if (said(take,key))` en el mismo ciclo **sí** coincide.
2. **D13 (OR)**: `if (isset(f40) || controller(3))` con f40=1. Las dos formas dan lo mismo, pero con `said` en la segunda rama, solo ScummVM no la evalúa.
3. **D01**: `set.key(0,0x3B,5)` y evento de tecla F1. Esperado: `controller(5)` cierta; **`v19 == 0`** y `have.key()` falsa.
4. **D01/D03**: evento de flecha con el ego bajo control del jugador. Esperado: `v6` cambia y **`v19` no**.
5. **D03**: pulsar la flecha derecha (`v6 = 3`), soltar, ciclo siguiente. Esperado (sin `hold.key`): `v6` sigue en 3. Pulsar la misma otra vez: `v6 = 0`.
6. **D02**: escribir "look" + ENTER. Esperado: `v19 == 13` en ese ciclo.
7. **D35.3**: teclear "the" (palabra con id 0) y "a" y "i". Esperado: **f2 = 0**, sin "no entiendo".
8. **D35.1**: diccionario sin "a": teclear "give a key". Esperado: `v9 == 0`, la `a` se ignora.
9. **D35.2 + D36**: teclear "look zzz" con `said(look, anyword)` y `said(look, 9999)`. Esperado: ambos ciertos; `v9 = 2`; `f2 = 1`.
10. **D37**: "take.sword" y "take,sword". Esperado: la primera es una sola palabra (desconocida); la segunda, dos.
11. **D27**: `set.view(o1, 5)` donde el objeto tenía `loop=3, cel=4` y la vista 5 tiene 2 bucles y 2 celdas. Esperado: `loop=0, cel=0` (no `1, 1`). Comprobar con `current.loop`/`current.cel`.
12. **D27**: `set.loop(o1, 9)` en una vista de 2 bucles. Esperado: bucle 1 (último), celda 0 si la actual no existe.
13. **D27**: `set.view(ego, N)`. Esperado: **`v16` no cambia**.
14. **D16**: `stop.update(o2); wander(o2)` (y con `move.obj`, `follow.ego`). Esperado: `o2` se actualiza (tiene `fUpdate`).
15. **D18**: `wander(o3); end.of.loop(o3, f60)`. Esperado: `wander_count` pasa a 60 (observable por cuánto tarda en volver a elegir dirección). `follow.ego(o4,…); reverse.loop(o4, f61)`: `follow_stepSize = 61`.
16. **D24/D25**: `reposition.to(o1, x, y)` y observar `fDidntMove` (dirección de un wander en el ciclo siguiente) y cruce de línea base contra un objeto que se mueve ese ciclo.
17. **D53**: `erase(o5)` y luego `obj.in.box(o5, …)` / `right.posn`. Esperado: usa el ancho de la última celda.
18. **D41**: mensaje con `%0 3`, `%v12|3` (con v12=7 → `007`), `%s1` con la cadena 1 = `"x%v3"` y `%m2` anidado. Esperado: objeto, `007`, valor de v3 sustituido, mensaje 2 formateado.
19. **D39**: `set.string(1, "S%v3")` con v3=5, luego v3=9 e imprimir `%s1`. Esperado: `S9`. Cadena de 45 caracteres: se corta a 39.
20. **D42**: `print` con una tecla distinta de ENTER/ESC. Esperado: la ventana **no** se cierra. `v21 = 2` y sin tecla: se cierra a los 40 ciclos y `v21 = 0`. `print` con mensaje 99 inexistente: no abre ventana.
21. **D43**: `get.num` sin evento de cadena preparado. Esperado: se queda esperando (no devuelve 0). Cadena `999` → `v = 231`. `get.string` + ESC: cadena vacía.
22. **D45**: `f13=1`, inventario vacío, ENTER → `v25 = 0`; ESC → `v25 = 255`. Con `v25=7` y el objeto 7 en el inventario, el cursor empieza en el 7.
23. **D46**: `menu.input` seguida de `if (controller(X))` en el mismo ciclo con ENTER ya en la cola. Esperado: **falso** en ese ciclo, cierto en el siguiente. Abrir el menú dos veces: la segunda vez empieza en el último menú/elemento elegido.
24. **D47**: `f16=1; restart.game`. Esperado: reinicia sin ventana. Después, los `disable.item` previos vuelven a estar activos (D46).
25. **D11**: la primera lógica 0 lee `v22`, `v24`, `v8`, `v10`, `v15` antes de tocarlas. Esperado: 1, 38, 180, 0, 0.
26. **D14a**: `new.room(N)` seguido, antes del `draw.pic`, de `reposition.to` del ego a un píxel de control. Esperado: usa la prioridad de la imagen anterior.
27. **D32**: ego detrás de un objeto fijo de prioridad alta. Esperado: `f1 = 1`.
28. **D22**: objeto estático con `cycle.time` normal y `v10 = 1`. Esperado: `current.cel` avanza.
29. **D08**: lógica 0 sin `return` final. Esperado: se repite hasta `new.room`/salir.
30. **D52**: una lógica con `put(oX, 7)` y `v7 ≠ 7`. Determinar cuál de las dos lecturas es la del juego real **antes** de decidir.
