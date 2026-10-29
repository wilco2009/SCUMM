# Auditoría del intérprete AGI v2 frente a ScummVM (engines/agi)

Fecha 2026-10-29. Solo lectura. Nuestro lado: `V2/TOOLS/agi_vm.py` (nº de línea entre paréntesis). ScummVM: `cycle.cpp`, `motion.cpp`, `checks.cpp`, `view.cpp`, `sprite.cpp`, `op_cmd.cpp`, `op_test.cpp` (master). WebFetch resume, así que las citas son pseudocódigo fiel, no literales; las dudas se marcan «verificar».
Ya corregido hoy y no repetido: banderas 0/3 en new.room, línea 0 siempre bloquea, zona de `block`, relleno de `show.obj`, guardado/carga.
Gravedad: **A** puede romper una sala; **M** probable efecto visible/temporización; **B** marginal.

## 1. Ciclo e inicio de sala

| Regla | ScummVM | Nuestro modelo | Veredicto |
|---|---|---|---|
| Orden del ciclo | `interpretCycle`: sincroniza dir del ego ↔ v6 → `checkAllMotions` (decide dirección de move.obj/follow/wander) → `runLogic(0)` en bucle (re-ejecuta tras new.room) → dir ego ← v6 → `updateScreenObjTable` (por objeto: elegir bucle, ciclar celdas; luego UNA vez `updatePosition` para todos) | `interpret_cycle` (1644): lógica 0 → `update_objects` (1554) que por objeto hace move + cycle | CORREGIDO (2026-10-29: checkAllMotions antes de la lógica; ciclos y bucles, y después la posición de todos). Antes: DIFERENTE (B). La dirección de move.obj/follow se calcula tras la lógica en vez de antes; ver §2 por el efecto en la posición final |
| Borde v2/v4/v5 | `updatePosition` los pone a 0 al empezar y también en cada pasada de la lógica 0 | (1664) a 0 antes de mover | IGUAL |
| Bandera 2 (ENTERED_CLI) y 4 (SAID_ACCEPTED) | se limpian cada ciclo | (1667) | IGUAL |
| Banderas 5 (NEW_ROOM_EXEC), 6 (RESTART), 12 (RESTORE_JUST_RAN) | se limpian al final del ciclo | 5 y 6 sí (1671); la 12 no se toca en `interpret_cycle` (¿la maneja save_load?) | verificar (B) |
| v9 (WORD_NOT_FOUND) y v19 (KEY) | `playGame` los limpia **tras cada ciclo ejecutado** | v9 solo se limpia al parsear una línea nueva (391) o en new.room (618); v19 solo en evento `text` (1629) o al consumir con have.key | DIFERENTE (**M**). Una lógica que haga `v9 > 0` o `v19 == n` ve el valor rancio en todos los ciclos siguientes. Corrección: `v[9]=v[19]=0` al final de `interpret_cycle` (junto a `self.input=None`) |
| Controladores | `resetControllers` al final de cada pasada de lógica 0 (también al re-ejecutar tras new.room) | `self.ctl = set()` al inicio del ciclo (1647) | DIFERENTE (B): tras new.room la lógica 0 re-ejecutada ve los controladores del ciclo; en ScummVM no |
| new.room: objetos | para TODOS los objetos (ego incluido): quita animated y drawn, pone update, y `stepTime=stepTimeCount=cycleTime=cycleTimeCount=stepSize=1` | (622-629): solo anim/drawn de no-ego; el ego queda `anim`, con step/ctime intactos | DIFERENTE (**M**). El ego conserva el `step.size` de la sala anterior; si una sala nueva no lo fija, andará distinto a ScummVM. Corrección: en `do_new_room` poner `step=stime=scount=ctime=ccount=1` en todos los objetos |
| new.room: otros | playerControl=true, block off, horizon=36, v1=v0, v0=n, v4=v5=0, v[EGO_VIEW]=vista del ego, reposición del ego por v2 (1→y=167, 2→x=0, 3→y=horizon+1, 4→x=160−w), v2=0, flag5=1 | (613-652) idéntico (v16 se fija en set.view) | IGUAL |
| new.room: v3+ | `motionType` del ego a normal y v6=0 | no aplica a v2 | n/a |
| Tras reposicionar el ego | (`draw` y `reposition` llaman a `fixPosition`; ver §2) | no hay | ver §2 |

## 2. Movimiento y colisiones

| Regla | ScummVM | Nuestro modelo | Veredicto / gravedad |
|---|---|---|---|
| **Borde descartado si el movimiento se revierte** | `updatePosition`: tras recortar a bordes, `if checkCollision(obj) \|\| !checkPriority(obj)` → restaura (x,y) antiguos, **`border = 0`** y llama a `fixPosition`. Solo si `border != 0` se escribe v2 (ego) o v4/v5 | `move` (1519-1528): escribe v2/v4/v5 con `border` aunque `can_be_here` haya rechazado el paso | DIFERENTE (**A**). Con una línea de control o un objeto que bloquea junto al borde, la lógica ve un v2 que ScummVM no produce y salta `new.room` espuria. Corrección: `border=0` cuando `can_be_here` falla (y si `o.motion==3` + border, parar el move.obj, ver siguiente) |
| Borde y move.obj | si hay borde y `motionType==MoveObj` → `motionMoveObjStop` (restaura step, pone la bandera de llegada, motion normal; ego: pcontrol=true, v6=0) | no se para | DIFERENTE (M). Un move.obj que roza el borde en ScummVM termina; en el modelo sigue empujando |
| **`fixPosition`** (espiral O,S,E,N de radio creciente) | se llama en `draw`, `reposition`, `reposition.to` y en `updatePosition` tras revertir. Busca la primera celda con `checkPosition && !checkCollision && checkPriority` desde la posición actual (antes sube `y` a `horizon+1` si no ignora horizonte) | no existe | FALTA (**A**). Si el ego se coloca (position/draw) sobre línea 0/1, dentro de un objeto o en `y<=horizon`, ScummVM lo saca a la celda libre más cercana; el modelo lo deja atrapado (todo paso `can_be_here` falso) o dibujado en un sitio ilegal. Candidato nº 1 a las salas rotas de SQ1. Corrección: `fix_position(o)` y llamarla en `c_draw`, `c_reposition`, `c_reposition_to(_v)` y en `move` al revertir. `position` NO la llama |
| Recorte superior | `y - ySize < -1` → `y = ySize-1`, border=1 (cadena if/else-if con el fondo y el horizonte; puede pisar el 4/2 de lateral) | solo lateral, fondo (>167) y horizonte (1507-1517) | FALTA (B) |
| Recorte lateral | `x<0`→0, border 4; si no, `x+w>160`→`160-w`, border 2 | igual | IGUAL |
| Horizonte | `y <= horizon` sin `ignore.horizon` → `y = horizon+1`, border 1 | igual (1516) | IGUAL |
| Colisión entre objetos (x) | salta solo si `x + w < q.x \|\| x > q.x + qw` ⇒ **bordes que solo se tocan SÍ colisionan** (comparación inclusiva) | `x < q.x+qw and q.x < x+w` (1452), estricta | DIFERENTE (**M**). Ajuste de 1 px en cada lado. Corrección: `x <= q.x+qw and q.x <= x+w` |
| Colisión (y) | misma `y`, o cruce de la línea base comparando posiciones previas de ambos | misma `y` o cruce con `o.y` previo frente a `q.y` actual | IGUAL en la práctica (si `q` se mueve a la vez el resultado puede diferir; B) |
| Condiciones del otro objeto | animated+drawn, no ignore.objs, no el mismo | igual | IGUAL |
| Línea de control 1 | `p==1 && !fIgnoreBlocks` bloquea a **cualquier objeto** | solo si `o is ego` (1426, 1438) | DIFERENTE (**M/A**, verificar con el juego): en ScummVM un objeto no-ego que observa bloques tampoco cruza la línea azul. Si algún objeto de SQ1 cruzaba la azul en el PC, es que no hacía `ignore.blocks`. Corrección: quitar `and o is ego` |
| Línea 0 | bloquea siempre | igual (1424) | IGUAL |
| Prioridad 15 | si `priority == 15` se salta TODO el escaneo (ni control ni agua) | se escanea siempre | DIFERENTE (**M**). Objetos con `set.priority 15` (y add.to.pic) atravesarían líneas en ScummVM. Corrección: `if o.pri != 15:` alrededor del bucle |
| Agua | `touchedWater` = TODOS los píxeles bajo el sprite son 3. `on.water`: bloquea si NO todo es agua; `on.land`: bloquea si TODO es agua. Se escanea hasta el 1.er 0 / 1 | `on.land` bloquea si hay ALGÚN píxel de agua; `on.water` bloquea si hay algún píxel de tierra (1440-1443) | DIFERENTE (**A** si hay salas de agua). Con ScummVM el objeto `on.land` puede entrar a medias en el agua; sólo se frena cuando todo el sprite está en agua. Corrección: `on.water` → `if water != w: bloquear`; `on.land` → `if water == w: bloquear` |
| `on.water` + `on.land` | son dos banderas independientes (`object.on.anything` limpia ambas) | un solo valor `o.water` (0/1/2) | DIFERENTE (B) |
| **`fOnWater/fOnLand` del ego** | `updateScreenObjTable` los **limpia cada ciclo** tras mover (`ego.flags &= ~(OnWater\|OnLand)`) | persisten (840-842) | DIFERENTE (**M**). La lógica debe repetir `object.on.water/land` cada ciclo; el modelo los deja puestos para siempre. Corrección: al final de `update_objects` `ego.water = 0` |
| Banderas del ego 0 (agua) y 3 (trigger) | se **escriben en cada llamada a `checkPriority`** (movimiento, `draw`, `fixPosition`), también cuando el paso se rechaza (valores parciales) | solo se escriben en un movimiento permitido (1444-1446); un `draw`/`position` no las refresca; si el paso se rechaza no cambian | DIFERENTE (**M**). Al entrar en sala el ego sobre agua debería ver flag 0 =1 ya tras `draw`. Corrección: calcular las dos banderas en `fix_position`/`draw` y en el rechazo |
| `block` + `ignore.blocks` | `changePos` (en `checkMotion`, solo si `dir != 0`, !ignoreBlocks): si el estado dentro/fuera del rectángulo cambiaría, `dir = 0` y (ego) v6 = 0 | resuelto hoy (1413-1417) pero solo rechaza el paso; no pone `dir=0` | IGUAL salvo B: para no-ego sin move.obj el `dir` se queda |
| `ignore.blocks` | salta línea 1 y el rectángulo; la 0 sigue bloqueando | igual | IGUAL |
| Márgenes de `add.to.pic` | `border <= 3`: caja de prioridad (línea inferior, lados y techo si alto >1; el alto limitado a la banda de prioridad `priorityFromY`), solo en la pantalla de prioridad | `margin < 2`, solo una línea bajo la celda, máx. 8 (682, 1434) | DIFERENTE (**M**): bordes 2 (trigger) y 3 (agua) no se modelan; lados y techo faltan |
| `add.to.pic`: prioridad 0 | `pri == 0` → `priorityFromY(y)` y flags sin FixedPriority | usa `pri` tal cual (680) | DIFERENTE (B, verificar) |
| `add.to.pic` y objetos | usa un objeto interno aparte (no gasta ranura) | ocupa la ranura libre 31..24 (674) | DIFERENTE (B): con >8 se pierden; ranuras de lógica altas pueden chocar |
| `move.obj` | guarda `move_stepSize`; si `step != 0`, `stepSize = step`; limpia bandera; llama a `moveObj` YA (dirección disponible en el mismo ciclo, v>2.272); ego: pcontrol=false | (896-905) igual salvo que no calcula dir inmediato | IGUAL (B) |
| `move.obj`: llegada | `getDirection` usa `checkStep(delta, step)`: delta ≤ −step → −1, ≥ step → +1, entre medias 0. El objeto **se para a menos de `step` del destino** en cada eje y **no recorta** el último paso; llegada = dir 0 | `move` (1468-1488) recorta `dx,dy` al paso y aterriza EXACTO en (tx,ty) | DIFERENTE (**M/A**): el ego termina en otra posición; lógicas con `posn`/`obj.in.box` ajustados tras un `move.obj` pueden no cumplirse (o cumplirse de más). Corrección: dir por `checkStep` y movimiento `step*DX[dir]`; llegada cuando dir==0 |
| `follow.ego` | `follow_stepSize = max(step, stepSize)` solo para el umbral de llegada; el movimiento sigue siendo `stepSize`. Apunta al **centro x** del ego y a su `y`; llegada cuando `getDirection==0` (|dx|<step y |dy|<step). Si no se movió: dir aleatoria + contador | cambia `o.step = step` (más rápido, permanente) (909-916); llegada con \|dx\|≤2·step y \|dy\|≤step sobre `x` izquierda (1491) | DIFERENTE (**M**): velocidad y distancia de llegada distintas (monstruos que persiguen). Corrección: campo `fstep`, centro x, umbral `< fstep` |
| `wander` | `wander_count` baja; al cero o si no se movió: dir aleatoria 0..8 (incluye 0), `count = rnd + 6` (6..49) | dir 1..8, count 4..13 (1499-1503) | DIFERENTE (B) |
| `stop.motion` | dir=0, motion=normal; ego: v6=0, pcontrol=false. **No existe «mon»**: el objeto sigue movible con `set.dir` | `mon=False` (881) bloquea el movimiento y el ciclo de celdas de ese objeto (1565); no pone motion=0 | DIFERENTE (**M**). Un move.obj/wander activo sobrevive a stop.motion en el modelo (en ScummVM se cancela); además `mon=False` no es lo mismo que «no moverse» |
| `start.motion` | motion=normal; ego: v6=0, pcontrol=true | solo `mon=True` y pcontrol (889) | DIFERENTE (M): no cancela el motion ni limpia v6 |
| `player.control` | pcontrol=true **y** si `ego.motion != Ego` → motion normal (cancela move.obj/follow/wander del ego) | solo pcontrol=true (930) | DIFERENTE (**A**): tras `move.obj ego` seguido de `player.control` el ego del modelo sigue andando solo al destino |
| `program.control` | solo pcontrol=false | igual | IGUAL |
| `move.obj`/`follow`/`wander` y `mon` | no tocan ningún «mon» | ponen `mon=True` | DIFERENTE (B), consecuencia de la fila stop.motion |
| Selección de bucle | en `updateScreenObjTable` (todos los objetos animated+update+drawn, no `fixloop`): 2–3 bucles → `loopTable2[dir]`, 4 bucles → `loopTable4[dir]`, **5+ bucles: sin cambio**; solo si `stepTimeCount == 1` | `pick_loop` solo dentro de `move` y con `n >= 4` usa LOOP4 también para 5+ (1456-1464) | DIFERENTE (**M**): vistas de 5+ bucles cambian de bucle solas en el modelo. Corrección: `n==4` → LOOP4; `n in (2,3)` → LOOP2; resto nada |
| Orden bucle→celda | por objeto: bucle, ciclo; el movimiento va después, para todos a la vez | movimiento y ciclo por objeto, en orden de número | DIFERENTE (B) |
| `step.time` / `step.size` | `stepTime=stepTimeCount=var` (sin mínimo 1); `updatePosition`: `if count>1: count--; sigue; else count=stepTime` | `max(1, v)` (894) | IGUAL en la práctica (un 0 se comporta como 1) |
| `stepTime` del ego en `animate.obj` | `animate.obj` NO toca step/ctime/ign (los pone new.room) | resetea todo en `animate.obj` (737-743) | DIFERENTE (M, ver fila de new.room): tras `unanimate.all` + `animate.obj` ScummVM conserva el step |
| `animate.obj` | `flags = Animated\|Update\|Cycling` (borra TODOS los demás: fixpri, fixloop, ignore*, on.water/land, drawn); motion normal, ciclo normal, dir 0; si ya estaba animado no hace nada | igual en efecto (734-745) | IGUAL |
| `draw` | además de dibujar: `fixPosition`, `setLoop/setCel` actuales, limpia DontUpdate | (750-758) sin fixPosition | FALTA (**A**), ver arriba |
| `reposition(.to)` | flag UpdatePos (ese ciclo no avanza el paso), `fixPosition`, `reposition` recorta a 0 pero no por arriba | (766-780) sin fixPosition ni UpdatePos | FALTA (**M**) |
| `position` | solo asigna pos y previa; sin fixPosition | igual | IGUAL |
| `set.view` / `set.loop` / `set.cel` | clamp de bucle/celda; `setCel` aplica `clipViewCoordinates` (si se sale por la derecha: `x` a la izquierda + UpdatePos; arriba `y = ySize-1`; `y <= horizon` → `horizon+1`) | `cell()` clamp (183) sin clipViewCoordinates | FALTA (**M**): un objeto con celda más ancha junto al borde puede quedar medio fuera; ScummVM lo recoloca |
| `set.cel`: DontUpdate | `set.cel` limpia DontUpdate | no existe | B |
| `distance` | `x` = `xPos + xSize/2` de cada objeto, `y` = `yPos`; |dx|+|dy| con máx **254**; 255 si alguno no está drawn | usa `o.x` (esquina izquierda) y `min(255, …)` (850-855) | DIFERENTE (**M**): distancias distintas en comprobaciones de «cerca» (SQ1 las usa para persecuciones). Corrección: centros y tope 254 |
| `get.posn` | trunca a 8 bits | igual | IGUAL |
| `random(min,max)` | `rnd(max-min) + min`, max alcanzable | `lo + rand % (hi-lo+1)` | IGUAL |
| `set.horizon` | solo guarda | igual | IGUAL |
| `object.on.*`, `ignore.*` | ver filas de agua | — | — |

## 3. Cel cycling

| Regla | ScummVM (`updateView`) | Nuestro modelo (`cycle_cel` 1530) | Veredicto |
|---|---|---|---|
| `end.of.loop` | al llegar a la última celda, **en la misma llamada**: bandera=1, `cycling=false`, **`direction=0`**, ciclo normal | la bandera se pone en la llamada SIGUIENTE a haber llegado a la última (`if o.cel+1 >= n` con la celda aún sin avanzar); no pone `dir=0` | DIFERENTE (**M**): la bandera llega un `cycle.time` tarde y un objeto con movimiento sigue andando al terminar la animación (p.ej. puerta/explosión que debía parar) |
| `reverse.loop` | igual hacia la celda 0 | `if o.cel == 0` antes de decrementar | DIFERENTE (**M**), misma causa |
| `end.of.loop`/`reverse.loop` | ponen DontUpdate: el 1.er `updateView` solo lo limpia (no avanza); `cyclerActivated` | no hay | DIFERENTE (B/M): la animación arranca un tick más tarde |
| `ignoreLoopFlag` | si el objeto ya tenía motion al activar el ciclador, no se pone la bandera de fin | no existe | B (workaround de ScummVM para fidelidad con el original) |
| Cycling | solo si `fCycling` y `cycleTimeCount != 0`; decrementa, al llegar a 0 → `updateView` y recarga `cycleTime` | igual (1570-1574) | IGUAL |
| `reverse.cycle` | baja y da la vuelta; no para | `ctype 3` igual | IGUAL |

## 4. Sprites y prioridades (`sprite.cpp`)

| Regla | ScummVM | Nuestro modelo | Veredicto |
|---|---|---|---|
| Orden de dibujo | clave = `yPos` (o `priorityToY(pri)` con prioridad fija); ordenación estable ascendente por clave y por nº de objeto. Primero la lista estática (animated+drawn, sin update) y luego la normal | `draw_order` (194): por `(pri, y, n)`; los estáticos con `y = 0` | DIFERENTE (**M**, ya es una decisión de hardware: los sprites HW se ordenan por prioridad numérica, no por «y»). El cambio de ScummVM es que un sprite de prioridad fija mayor NO se pinta encima de uno de y mayor salvo que `priorityToY` lo ponga ahí. Ojo si se ve un objeto tapado/destapado mal |
| Prioridad vs. pic | un píxel de la celda se pinta si `picPri > 2 && picPri <= viewPri`; píxeles con pic 0–2 (control) se pintan según `checkControlPixel` | modelo por tiras (`spans`) y sprites HW | verificar (no leído `checkControlPixel`) |
| `show.obj` | pos x=((159−w)/2), y=167, pri 15, `messageBox` con descripción, restaura el fondo | resuelto hoy | IGUAL |
| Ego invisible | si ningún píxel del ego se dibuja → `VM_FLAG_EGO_INVISIBLE` (bandera 11? numerada en agi.h) | no se calcula | FALTA (B/M): ninguna sala de SQ1 conocida la usa, pero KQ1/KQ2 sí (el ego tapado por una prioridad). Corrección: bandera 11 en `render`/`draw_order` |
| Rechazo de sprites | `buildSpriteListAdd` descarta si `x<0`, `y<0` o fuera | — | B |
| `priorityFromY` | valores 5..14 por bandas de 12 desde y=48 (y<48 → 4) | `set_pri` (762): `4 if y<48 else min(15, (y-48)//12+5)` | IGUAL (la banda 15 no se alcanza con y≤167: 12*11+48=180; el `min` sobra) |

## 5. Comandos y condiciones

Faltan en el modelo (se cuentan en `noop`): `load.logics(.v)`, `load.pic`, `load.view(.v)`, `load.sound`, `discard.pic`, `discard.view(.v)` — nulos sin consecuencia; `show.pic` (la pic ya se muestra con `draw.pic`; ScummVM sí distingue: `draw.pic` NO muestra hasta `show.pic`, y las lógicas dibujan pic + objetos antes de `show.pic`: **verificar** que no se vea un fotograma intermedio, B); `show.pri.screen` (depuración); `shake.screen` (**M** visual: explosiones en SQ1; no cambia lógica); `obj.status.v`, `show.mem`, `trace.*`, `script.size`, `configure.screen`, `init.disk`, `init.joy`, `toggle.monitor` (nulos); `set.scan.start` / `reset.scan.start` (**B**, v2.4+; cambia el punto de entrada de la lógica; verificar si lo usa algún juego con `grep -r` en las lógicas); `clear.text.rect`, `set.upper.left`, `open.dialogue`, `close.dialogue`, `close.window` (**B**; `clear.text.rect` puede dejar texto en pantalla).

Implementadas distinto:

| Comando / condición | ScummVM | Modelo | Veredicto |
|---|---|---|---|
| `obj.in.box` | `x ≥ x1, y ≥ y1, x+w−1 ≤ x2, y ≤ y2`, con `w` siempre | igual, pero `w=0` si no está drawn (449) | IGUAL (B: no drawn) |
| `posn`, `center.posn`, `right.posn` | inclusivos, `w/2` entero | igual | IGUAL |
| `greater/less/equal` | sin signo, estrictos | igual | IGUAL |
| `compare.strings` | quita espacios, tab y `- . , : ; ! '`, minúsculas, igualdad | `lower().split()` (467) | DIFERENTE (B) |
| `said` | exige flag2 y NO flag4; 1 = cualquier palabra; 9999 = resto; pone flag4 | `self.input`/`said_done`/v9 (409-428) | IGUAL en esencia; en el modelo `said` es falso si v9≠0 (palabra desconocida) aunque ScummVM lo evaluaría con las palabras reconocidas hasta la desconocida: verificar con el parser (B) |
| `increment`/`decrement` | tope 255 / suelo 0 (sin wrap) | (564-571) no revisadas aquí | verificar (B) |
| `add/sub/mul/div` | `byte` (wrap) | wrap `& 255`; div por 0 → 0 | IGUAL |
| `controller` | `controllerOccurred[c]` | `a[0] in self.ctl` | IGUAL |
| `have.key` | si v19≠0 true; si no, un sondeo | cola `keyq` | DIFERENTE (B, ver v19 en §1) |
| `restart.game` | pone flag6 y `restartGame` | (1001) | IGUAL |
| `reposition` negativo | `dx` con signo; si `x < −dx` → 0 | (775-780) sin recorte a 0 | DIFERENTE (B): `o.x` puede quedar negativo |

## Correcciones propuestas (orden de prioridad)

1. **CORREGIDO (border descartado al rechazar; el stop de move.obj va con el punto 5)** **`move` (agi_vm.py:1466)** — descartar `border` si `can_be_here` rechaza el paso; si el borde se tocó con `motion==3`, parar el move.obj (restaura step, bandera de llegada, ego: pcontrol=True, v6=0). Mismo cambio en el Z80 (`ENGINE/*.asm`, rutina de movimiento).
2. **CORREGIDO (modelo y Z80, overlay C OVC_FIXPOS; position y reposition.to ya no son la misma)** **Nueva `fix_position(o)`** (espiral O,S,E,N desde la posición actual; requisitos: dentro de pantalla, `!colisión`, `checkPriority`), llamada desde `c_draw` (750), `c_reposition` (775), `c_reposition_to(_v)` (772) y desde `move` al revertir. Refresca las banderas 0/3 del ego.
3. **CORREGIDO (modelo y Z80; las banderas 0/3 se calculan con la fila entera, sin cortar en el primer 0/1; la linea 1 ya vale para todo objeto)** **`can_be_here` (1407)** — (a) `if o.pri != 15` alrededor del escaneo; (b) agua: `on.water` bloquea si `water != w`, `on.land` si `water == w`; (c) línea 1 para todo objeto que no ignore bloques (quitar `o is ego`; verificar con una sala de SQ1); (d) colisión en x inclusiva; (e) escribir las banderas 0/3 también cuando se rechaza.
4. **CORREGIDO (modelo y Z80; el bit mon queda sin uso en estos comandos)** **`player.control` (930), `stop.motion` (880), `start.motion` (888)** — como ScummVM: `player.control` pone `motion=0` en el ego; `stop.motion`/`start.motion` ponen `motion=0` (y ego: v6=0); eliminar `mon` o dejarlo sin efecto sobre el movimiento (ScummVM no lo tiene).
5. **CORREGIDO (modelo y Z80; ya no aterriza exacto: riesgo de scripts que comparen la posicion final)** **`move.obj` (`move`, 1468)** — dirección con `checkStep` y paso completo `step*DX[dir]`; llegada con `dir==0` (sin aterrizar exacto). Llamar a la dirección ya en `c_move_obj`.
6. **CORREGIDO (modelo y Z80; fstep en mstep, follow_count en wander, fDidntMove = bit 3 de F2; sin cobertura de la bateria)** **`follow.ego` (909, 1489)** — campo `fstep=max(step, o.step)`, comparar centros x, umbral `< fstep`, no tocar `o.step`.
7. **CORREGIDO** **Ego `fOnWater/fOnLand`** (`update_objects`, 1554) — ponerlo a 0 al final de cada ciclo.
8. **CORREGIDO (con fDontUpdate en end.of.loop/reverse.loop, borrado por set.cel y draw)** **`cycle_cel` (1530)** — end.of.loop/reverse.loop: bandera en la misma llamada al llegar al extremo, `cycling=False`, **`dir=0`**, `ctype=0`; opcional DontUpdate del primer tick.
9. **CORREGIDO** **`interpret_cycle` (1644)** — `v[9]=v[19]=0` al final del ciclo.
10. **CORREGIDO** **`do_new_room` (613)** — `step=stime=scount=ctime=ccount=1` en todos los objetos (incluido el ego).
11. **CORREGIDO** **`pick_loop` (1456)** — bucle automático solo con 2, 3 (LOOP2) o 4 (LOOP4) bucles; ejecutarlo para todo objeto animated+update+drawn cada ciclo (antes de mover), no solo al moverse.
12. **CORREGIDO** **`c_distance` (850)** — centros en x, `y` base, tope 254.
13. **CORREGIDO** **`c_set_view/set_loop/set_cel` (786-810)** — `clipViewCoordinates` tras cambiar de celda.
14. **`c_add_to_pic` (671)** — bordes 2 y 3, caja completa (lados y techo) y `pri==0` → `priorityFromY`; no usar ranuras de objeto.
15. **Menores**: recorte superior de `move`, `wander` (dir 0..8, contador 6..49), `reposition` con recorte a 0, `compare.strings` con puntuación, bandera 11 (ego invisible), `set.scan.start`, `shake.screen`, `clear.text.rect`.

## Lo que no se pudo comprobar (WebFetch resume)
- Cuerpos de `checkControlPixel`, `priorityToY`, `motionMoveObj` completo y `fixPosition` más allá del resumen.
- Si ScummVM aplica la línea 1 a objetos que no sean el ego (el resumen lo dice: `p==1 && !fIgnoreBlocks`); comprobar con el original o con una sala concreta antes de cambiar.
- `show.pic` frente a `draw.pic` y el momento real de refresco de pantalla.
