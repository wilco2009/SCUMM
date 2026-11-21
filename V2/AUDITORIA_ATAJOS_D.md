# Auditoria de atajos, seccion D (antes "NO REVISADO") — interprete SCUMM v2 frente a ScummVM

Alcance: V2/ENGINE/*.asm (arbol de trabajo, con A1-A3 sin commit), V2/TOOLS/*.py, games/*.cfg contra `engines/scumm` de ScummVM
(`C:\ClaudeCode\scummvm_src`). Sesion de SOLO LECTURA: no se ha tocado codigo, ni compilado, ni hecho commit. Los numeros de linea de
nuestros ficheros son los del arbol en este momento (otras sesiones estan editando A4-A11: pueden moverse unas lineas).

Restricciones de espacio medidas hoy: `overlay.bin` = 8099 bytes de 8192 (`IF $ > $2000` en overlay.asm:138) => **solo ~90 bytes libres en el
overlay**; el nucleo bajo $8000 tiene 5 libres. Casi todo lo de abajo vive en el overlay, asi que **antes de corregir nada hay que hacer sitio**
(mover codigo frio del overlay a otra pagina, p. ej. save.asm/snd.asm a un segundo overlay) — ver propuesta al final.

Resumen: de los seis puntos, **no hay ningun ALTO nuevo**. Hay 3 MEDIO reales (camara, paleta de sala al cargar, actores en oscuridad),
y el resto es BAJO o ya es igual que ScummVM (se anota para cerrar la duda).

---------------------------------------------------------------------------------------------------------------------------------

## 1. Variables del sistema — IGUAL, salvo detalles BAJOS

Tabla `setupScummVars` v2 (vars.cpp:125-162) contra `vars_v2.inc`: **todos los offsets coinciden** (VAR n = VARS+2n).
Los que faltan por nombre (VAR_EGO 0, VAR_MACHINE_SPEED 6, VAR_NUM_ACTOR 11, VAR_CURRENTDRIVE 13) son solo nombres: ScummVM no los escribe en
v2 (grep en todo engines/scumm: solo los lee/escribe el script del juego; VAR_EGO se lee en actor.cpp/script_v2.cpp:1106 etc. y nosotros leemos `VARS`
directamente: cam.asm:325, input.asm:797). No hay hallazgo.

* `resetScummVars` v2 (vars.cpp:603-608) solo fija MACHINE_SPEED=0x7FFF en Zak: lo hace scumm.asm:151 con PF_SPEED. OK.
* VAR_TIMER_NEXT inicial: en ScummVM es 0 (array a cero) => `delta<1 -> 1` (scumm.cpp:2860-2866); el nuestro empieza a 0 (vm_init limpia VARS,
  vm_core.asm:87) y scumm.asm:179-213 fuerza minimo 1 fotograma. OK. (La conversion 60 Hz -> 50 Hz y el tope de 40 son A6, ya conocidos.)
* VAR_CAMERA_POS_X: ScummVM la pone en `scummLoop_updateScummVars` (scumm.cpp:3413: `camera._cur.x >> V12_X_SHIFT`) al principio del fotograma, antes de
  los scripts; nosotros la escribimos en `cm_clamp` (cam.asm:251) al final del fotograma y los scripts la leen en el siguiente: **mismo valor, mismo
  instante efectivo**. OK.
* VAR_MUSIC_TIMER: ver seccion 2.
* **D-1 (BAJO) scumm.asm:140** pone VAR_CURRENT_LIGHTS=11 "como resetScummVars": falso, `ScummEngine_v2::resetScummVars` NO toca las luces (solo
  `ScummEngine_v0` lo hace, vars.cpp:594-601). En ScummVM arranca a 0 y el script de arranque lo pone. Efecto: ninguno si el script de arranque de
  Zak/Maniac fija `lights(11,0,0)` antes de pintar (en los volcados de Zak lo hace en 27 salas). Coste: 0 (borrar 5 bytes; deja 5 libres en el nucleo
  si ese codigo esta debajo de $8000 — **gana espacio**).
* **D-2 (BAJO)** Maniac v2: `writeVar` (script_v2.cpp:459-488) tiene un apaño para que el clic en la linea de frase ejecute la orden (var 34 := 1
  cuando se escribe 0 desde el script 4 con VAR_CLICK_AREA==5). Es un "enhancement" de ScummVM (kEnhRestoredContent), no del original => **no copiar**
  si queremos fidelidad al original; si se quiere la comodidad, es una comparacion en `write_var` (vm_core.asm:1042, que esta en el nucleo: no cabe).
* Lectura de variables 14-16 como punteros (script_v2.cpp:450-457): implementada igual (vm_core.asm:1016-1036).
* writeVar CUTSCENEEXIT_KEY 4/13/64 -> 27: igual (vm_core.asm:1042-1057).

## 2. Sonido

Modelo de Player_V2 (player_v2.cpp:128-166 `startSound`, `stopSound` 111-126, player_v2base.cpp:349-375 `chainSound/chainNextSound`) contra
snd.asm:72-133 (`sdx_start`), 57-69, 159-173: **la logica de prioridad / reiniciable / cola de uno es identica** (cprio<=prio desplaza; el desplazado
pasa a la cola si es reiniciable y nprio<=prio; mismo sonido no se encola). `getSoundStatus` (actual o siguiente) igual (snd.asm:36-47). `stopAllSounds`
igual (50-54). pack_data/sound2vgm leen prioridad y reiniciable de los bytes +4/+5 del recurso (header_len=4), igual que ScummVM.

Sonidos 47, 48 y 53 de Zak: **no hay rastro de que sean "no PCjr"**. El recurso tiene las direcciones PCjr (offset +10 de la cabecera: 47 -> canales
2 y 3, 48 -> 2 y 3, 53 -> 0,1,2) y sound2vgm los convierte (SOUNDS.TXT: 47 prio 100/265 ticks, 48 prio 105/521, 53 prio 111/901). Nada que corregir; si
alguien oyo algo raro en esos sonidos es de la conversion a AY, no de la logica.

Hallazgos:

* **S-1 (BAJO-MEDIO) `startSound` en ScummVM es diferido y LIFO.** `Sound::startSound` (sound.cpp:120-126) solo mete el sonido en `_soundQueue`;
  `processSoundQueues` (sound.cpp:151-161) lo procesa **una vez por fotograma, al final de scummLoop_handleSound, sacando por el final (`_soundQueuePos--`)**:
  si un script arranca A y despues B en el mismo fotograma, ScummVM dispara primero B y luego A. Nosotros arrancamos A y luego B inmediatamente
  (game.asm:77-89 -> snd.asm:72). Con prioridades distintas el resultado final cambia (con A y B de prioridad igual, en ScummVM suena A y B queda en cola si es
  reiniciable; en el nuestro al reves). `stopSound`/`stopAllSounds` ademas vacian la cola (sound.cpp:963-973, 976-994) — lo nuestro no necesita porque no hay
  cola. `isSoundRunning` ve el sonido encolado (isSoundInQueue, sound.cpp:872) — el nuestro tambien porque arranca ya. Ejemplo: Zak, scripts que juntan un
  `startSound` de efecto y de musica en el mismo fotograma (p. ej. al cambiar de sala). Coste: una cola de ~8 bytes en RAM + vaciarla en `snd_tick`
  (~50 bytes en snd.asm, overlay). No toca el nucleo salvo que `h_o5_startSound` (game.asm, nucleo) pase a escribir en la cola: se puede dejar tal cual y
  que el overlay `snd_event` (EV_SOUND_START) la llene y `snd_tick` la procese al final del fotograma (ya se llama cada fotograma, scumm.asm:235).
* **S-2 (BAJO) VAR_MUSIC_TIMER.** ScummVM la reescribe **cada fotograma** (`updateMusicTimer`, scumm.cpp:3239 -> sound.cpp:2206-2226) con
  `_musicEngine->getMusicTimer()` = `_channels[0].d.music_timer` (player_v2base.cpp:386-391), que vale 0 en cuanto se para el sonido (`clear_channel` hace
  memset) y lo pone el propio script de sonido con el comando "set param" del canal 0. Nosotros: la ponemos a 0 en `startSound` (game.asm:75-76 = o5_startSound,
  igual que script_v5.cpp:2828) y la hacemos subir con el cuentapasos de `sdx_mtimer` (snd.asm:346-381), pero **no la ponemos a 0 al parar el sonido ni la
  reescribimos cada fotograma** (un script que escriba esa variable no queda machacado). Ademas `timer_params` (sound2vgm.py:296-307) descarta los sonidos
  cuyo timer no sube regularmente ("no es regular (no se usara)") => en esos VAR_MUSIC_TIMER queda a 0 siempre. Mirando SOUNDS.TXT de Zak los 7 campos
  tstart/tstep son 0/0 en **todos** los sonidos de Zak y en Maniac solo 50, 55, 58 tienen 24/0: **en Zak VAR_MUSIC_TIMER nunca se mueve**. Zak lo usa en la
  intro (comentario de ScummVM scumm.cpp:3106-3140: "dos comprobaciones de VAR_MUSIC_TIMER al principio de la intro"): si esas comprobaciones esperan un
  valor, la intro puede no avanzar o saltarse la sincronia. **Pendiente de comprobar con el volcado del script de intro de Zak** (buscar `VAR_MUSIC_TIMER`/
  var 17 en dump_out). Coste si hace falta: ampliar `timer_params` (script Python, sin coste de bytes) y poner a 0 al parar (~10 bytes en snd.asm).
* **S-3 (BAJO) recorte de VGM largos.** `MAX_TICKS = 236*3600` (sound2vgm.py:20): los sonidos 17, 49, 80 de Zak (849600 ticks = 1 h exacta) son "no repiten
  nunca el estado" => ScummVM los dejaria sonando hasta el fin del programa de canal (no acaban nunca); a 1 h el nuestro termina. Irrelevante en una partida real.
* **Musica al guardar**: **NO es un fallo**. `Player_V2` no tiene `saveLoadWithSerializer` (grep en players/player_v2*.cpp: ninguno) y
  `loadGameState` hace `_sound->stopAllSounds()` al cargar (saveload.cpp:768-773) — lo nuestro (save.asm:181-184: parar VGM y limpiar sdx_cur/next) es **igual**.
  El script del juego es quien vuelve a pedir la musica.

## 3. Guardar / cargar (save.asm)

ScummVM guarda (saveload.cpp:1404-2260): variables, scripts, actores (incl. paleta/costume/anim), objetos, inventario, nombres nuevos, cola de frases,
camara (incl. _leftTrigger/_rightTrigger, saveload.cpp:1485), `_currentRoom`, `_inventoryOffset` (script v2:2224), `_flashlight.xStrips/yStrips` (2236-2237), la
paleta de sala `_roomPalette` (1909-1916, v<5) y `_currentPalette/_darkenPalette` (1625-1626). Lo nuestro guarda $E000-$FFFF (nucleo), $8800-$8A8F (interfaz,
camara, nombres, `fl_xs/fl_ys`) e INVSL..$9500 (inventario, AC_OVF/LF/LC).

Revisado y **correcto**: ACTPAL ($E830, dentro del nucleo), camara (cam_cx/cam_mode/cam_dest/cam_fol en OVL_VARS), inventario y su desplazamiento (UI_INVO),
linterna (fl_xs/fl_ys, $8A8E-$8A8F), nombres de objeto cambiados (NAMEOV) y de actor (ACTNAME), estado de objetos, VARS (incluida VAR_MACHINE_SPEED), oscuridad
(VAR_CURRENT_LIGHTS va en VARS; `hv_dark` se recalcula cada fotograma en dk_frame), sin musica (como ScummVM).

* **G-1 (MEDIO) La tabla de color de sala de A1 (roomOps subop 2) no se guarda y se pierde al cargar.** ScummVM guarda `_roomPalette` (saveload.cpp:1909-1916).
  Nosotros: `hv_ptab` ($8790, hr.asm:60) esta **fuera de todos los rangos** que escribe save.asm:100-111 (E000-FFFF, 8800-8A8F, INVSL-9500) y `hv_pon`
  (HV+37, SV=$8700 => $8789+...) tambien; y `gf_load_room` (llamado en save.asm:187) pone `hv_pon=0` (hr.asm:535). Resultado: si guardas en una sala cuyo script
  cambio colores con roomOps (Zak: salas con `roomOps(a,b,2)`; A1 los activa), al cargar la sala sale con los colores originales hasta que se vuelva a
  ejecutar el script que los cambio (ENCD no se reejecuta al cargar). Coste: 16 bytes de `hv_ptab` + `hv_pon` a la cabecera del guardado (save.asm: un `f_write_n` y un
  `f_read_n` mas, unos 30 bytes en el overlay) y restaurar `hv_pon` DESPUES de `gf_load_room` (o saltar el reset en la carga). Hay que cambiar `SV_HLEN`/formato
  => invalida partidas viejas (el sello de savestamp ya cambia solo). Dependencia: A1 sin commit (sesion de paleta).
* **G-2 (BAJO) `UI_SV21`** (palabra de VAR_CURSORSTATE guardada por `cutscene()`, ovl_vars.inc: AV+22 = $8A91) queda **2 bytes por encima** del final de
  lo guardado (SV_LEN_O=$290 => $8A8F). Solo importa si se guarda en mitad de una cutscene (en Zak/Maniac el guardado no esta permitido en cutscene). Coste: SV_LEN_O += 3.
* **G-3 (BAJO)** ScummVM, tras cargar, `cameraMoved()` y `setupRoomSubBlocks` recalculan strips/ventana, y mete `camera._last.x = camera._cur.x`
  (saveload.cpp:880-882): sin salto de camara. Nosotros dejamos `cam_new` como estaba al guardar; si estaba a 1 la camara salta (inocuo).
* No se guardan `dk_ok/dk_c0/...` ($97A0-97A8) ni la ventana de la linterna pintada: se rehacen en el primer `dk_frame`. OK.

## 4. Luces y linterna (dark.asm, ho_lights cam.asm:62-70)

`o2_lights` (script_v2.cpp:1401-1426) contra ho_lights: c=0 pone VAR_CURRENT_LIGHTS (lo hace input.asm:1206-1213), c=1 pone xStrips/yStrips (cam.asm:64-67), `_fullRedraw`
(cam.asm:69-70): **igual**. Condicion de dibujar la linterna (`!(lights&2) && lights&4`, scumm.cpp:4146-4149 v5, heredada por v2): igual (dark.asm: bit 1 / bit 2).
Un sitio donde en los volcados de Zak hay `lights(6,4,1)` (linterna de 6x4 franjas) y `lights(Var[111],0,0)`; lo demas es `lights(11,0,0)`.

* **L-1 (MEDIO) El bit 3 de las luces (`LIGHTMODE_actor_use_colors`, valor 8) no se mira.** costume.cpp:805-817 (`ClassicCostumeRenderer::setPalette` para
  GF_OLD_BUNDLE = v2): sin ese bit **toda la paleta del actor pasa a 8 (gris oscuro) y el color 12 a 0**; con el bit, paleta normal. dark.asm y actors.asm no leen
  VAR_CURRENT_LIGHTS (grep: solo dark.asm:30,175, input.asm:1213 y scumm.asm:141). Efecto: en una sala a oscuras con linterna (Zak en la cueva / Maniac en el sotano y
  la mazmorra, donde las luces valen 0/4/6 sin el bit 8) los personajes se ven **a color** en lugar de grises. Sala con luz normal (11 = 1+2+8): no cambia nada. Correccion:
  al construir la paleta de actor (`ac_mkpal`, actors.asm) si `(VAR_CURRENT_LIGHTS & 8) == 0` -> todos los colores a gris 8 y el 12 a negro. Coste: ~25 bytes en el overlay (actors.asm).
* **L-2 (BAJO) Geometria de la linterna.** ScummVM (gfx.cpp:1858-1891): posicion = raton, `x &= ~7`, `y &= ~1`; rectangulo `xStrips*8` x `yStrips*8` centrado
  (`x - w/2`, `y - h/2`, sin truncar: con xStrips impar el borde cae a media celda), recortado a los bordes de la pantalla de 320 y 128 px; esquinas redondeadas con
  `v2FwdCurveData/v2BkwdCurveData` (gfx.cpp:1960-2040). Nosotros (dk_win, dark.asm:169-253): columna = (cursor+hv_fine)/8 - fl_xs/2 (entero: con fl_xs impar queda
  0,5 celda a un lado), fila = (cursor_y+4-fl_ys*4)/8 (cuantiza a 8 en vez de a 2 px), y recorta a 32 columnas de la ventana de 256 px en lugar de a la sala. Es
  una consecuencia del hardware (atributos de 8x8, B), salvo el recorte: con la camara pegada al borde ScummVM no deja que la linterna salga de la pantalla, nosotros
  tampoco. Efecto visual: ventana de la linterna ±4 px distinta con tamanos impares (Zak 6x4 es par => ninguno). **Sin accion** salvo que se quiera la esquina redondeada.

## 5. drawObject, mascaras, animateActor, camara, putActorAtObject, faceActor

* **O-1 (BAJO-MEDIO) drawObject no actualiza walk_x/walk_y.** `o2_drawObject` (script_v2.cpp:773-778) hace `walk_x += xpos*8 - x_pos; walk_y += ...` ademas de
  mover x_pos/y_pos. `ov_drawobj` (overlay.asm:167-201) solo cambia x/y (`iy+5`, `iy+6`) y el registro `.GFX`. El punto de caminar (`getObjectXYPos`, object.cpp:493-494,
  usado por walkActorToObject, putActorAtObject y la distancia de `getDist` en objetos) sigue siendo el de los datos (`object_xy_pos`, walk.asm:872-888 lee `ix+2/ix+3` del
  bloque de objeto en ROM). Ejemplo: un objeto que un script recoloca con `drawObject(obj,x,y)` y al que luego se hace `walkActorToObject`/`putActorAtObject` o que se alcanza
  con un verbo: el personaje camina al sitio viejo. Zak: la ultima fila de commits ("marcas de la maquina de billetes, sala 45") es decorado, pero las puertas/objetos de sala 45
  que reposiciona el mismo script podrian ser destino de `walkActorToObject`. Coste: una tabla de desplazamiento en RAM (2 bytes por objeto movido, p. ej. 8 objetos = 16 bytes + ~40 de
  codigo en `ov_drawobj`/`object_xy_pos`); **object_xy_pos esta en walk.asm = nucleo** => hay que leerla via overlay o gastar bytes del nucleo (no caben: solo 5 libres). Alternativa sin tocar el
  nucleo: que `ov_drawobj` escriba directamente el delta en la copia en RAM del bloque (si el bloque estuviera en RAM; no lo esta: es ROM de pagina).
* **O-2 camara (MEDIO). Seguimiento del actor.** ScummVM (camera.cpp:117-134; triggers `camera._leftTrigger=10`, `_rightTrigger=30` en franjas de 8 px, scumm.cpp:2184-2188):
  la camara **no se mueve mientras el actor esta entre las franjas 10 y 30 de la pantalla (±80 px del centro)**; al salir, `_movingToActor` se activa y la camara va a 8 px por
  fotograma hasta que `cur.x/8 == actor.x/8` (queda centrada), y solo entonces se para (histeresis). Nosotros (cam.asm:347-367, `cf2`): zona muerta de **±16 px** (`ld de,-16 ... jp nc,cm_fin`) y
  siempre se persigue el centro: la camara empieza a moverse antes y a cada paso del personaje, no como en el original, en que el personaje camina hasta ±80 px del centro y entonces se produce
  un barrido hasta centrarlo. Efecto visible en todas las salas anchas (Zak, Maniac), y en rutinas de script que dependen de VAR_CAMERA_POS_X (p. ej. escenas que esperan a que la camara
  llegue). Correccion: zona muerta de ±80 px (10 franjas) + un byte "persiguiendo" (histeresis: se activa al salir de la zona y se desactiva al llegar a la franja del actor). Nuestra ventana es de 256
  px (32 franjas): los triggers 10/30 de la ventana de 40 franjas se pueden conservar como ±80 px del centro (dentro de 128 px de semi-ventana). Coste ~25 bytes (overlay: cam.asm).
* **O-3 camara (MEDIO). `actorFollowCamera` no salta.** `setCameraAt` (camera.cpp:34-48): al activar el seguimiento, si el actor esta a **> 160 px** (`_screenWidth/2`) de la camara actual
  la camara **salta** a su x (`camera._cur.x = pos_x`); si no, `dest = x` y barrido a 8 px/fotograma. `ho_fol` (cam.asm:140-144) solo pone `cam_fol` y `cam_mode=2`, sin salto: aunque el actor este a 250 px
  la camara hace un barrido a 8 px/fotograma. Caso real: Maniac, al cambiar de personaje en la misma sala (`actorFollowCamera(nuevo)`); Zak, cutscenes que pasan el seguimiento de un actor a otro.
  ScummVM ademas hace `camera._movingToActor=false` y `runInventoryScript(0)` (nosotros: UI_DIRTY). Coste: ~20 bytes (overlay; comparar |actor*8 - cam_cx| > 160 en `ho_fol` y poner `cam_new`... ojo:
  `cam_new` tambien tapa a los personajes `ac_hold`; mejor un salto sin `ac_hold`).
* **O-4 (BAJO, B) `cm_edge`** (cam.asm:373-394): el cursor en el borde mueve la camara en modo normal. ScummVM no lo hace (la ventana de 320 px siempre cabe entera); es una decision de hardware porque
  la ventana mide 256 px. Documentado en B; no se corrige, pero conviene que **no** actue durante cutscenes (ScummVM las bloquea con `_userPut`/cursor oculto): `cm_edge` mira `cur_y` pero no `UI_CURSOR`.
* `animateActor`/`startAnim` (game.asm:144-165, 323-): `startAnimActor` es igual (CHORE_REDIRECT 56..60 -> init/walk/stand/talk start/talk stop, actor.cpp:2713-2733, requiere traje != 0 y sala actual);
  chores 61/62/63 = girar / dir ya / parar (`animateActor`, actor.cpp:2840-2861) igual. No se reinicia `_cost.animCounter` (no aplica: los fotogramas son hardware). Sin hallazgo.
* `putActorAtObject` (walk.asm:1074-1112) = `o2_putActorAtObject` (script_v2.cpp:1255-1272): igual, incluido el (30,60) por omision y `adjustXYToBeInBox`. `faceActor` revisado por encima: usa el mismo
  criterio (x del actor < x del objeto -> mira a la derecha); no verificado contra `Actor::faceToObject` linea a linea (BAJO).
* Orden de dibujo / mascaras: ya cubierto por A7/ac_mk y las sesiones de mascaras; no se ha encontrado un atajo nuevo. `ov_drawobj` apaga el estado "intrinseco" (bit 3) de los demas objetos que ocupan el mismo
  rectangulo (como script_v2.cpp:786-792) y deja el suyo (st_set 8) igual.
* Escala por caja y elevacion: v2 no tiene escala (confirmado: `_scalex/_scaley` no existen en v2).

## 6. Codigos de texto 1/2/3/8 y offsets de texto — IGUAL; el segundo punto NO aplica a v2

* `decodeParseString` v2 (script_v2.cpp:368-452) fija `_string[0].overhead = false` en cada mensaje (linea 437): **en v2 el texto NO sale sobre la cabeza del actor**, sale en `xpos=0, ypos=0` (la zona de mensajes
  de la parte alta de la pantalla). Es lo que hace nuestra zona fija (hv_top). El punto "offsets de texto sobre el actor (`_string[0].overhead`)" de la seccion D original **no es un atajo**.
* Codigos (string.cpp:251-285 + displayDialog 1033-1160): 1 = nueva linea (`_msgCount = _screenWidth = 320`), 2 = `_haveMsg=0, _keepText=true`, 3 = `_haveMsg=0xFF, _keepText=false, _msgCount=0`,
  fin de cadena `_haveMsg=1, _keepText=false, _msgCount=0`; 8 en v2 ni se convierte (decodeParseString solo convierte c<8; el 8 se imprimiria como caracter). game.asm:772-812 lo hace **igual** (60 + 6 por
  caracter, `_msgCount*6` en el modo "mantener", VAR_CHARCOUNT++ solo por caracter impreso, no por salto de linea). Orden de displayDialog (talkDelay antes de haveMsg==1) igual; `actor_talk` (game.asm:853-910) =
  `actorTalk` (actor.cpp:3480-3535): actor en otra sala -> se pierde el mensaje sin stopTalk; sin actor -> A4 (color de `_string[0]`).
* **T-1 (BAJO)** ScummVM tambien parte linea al llegar a 320 px (`_nextLeft >= _screenWidth` -> `newLine()`, string.cpp:1237-1240) pero **sin cambiar `_msgCount`**; nosotros partimos por columnas de la zona de mensajes.
  Solo cambia el dibujo, no los tiempos. Sin accion.
* Codigos 4-7 (variable, entero, nombre de objeto, cadena) en `dt_esc` (game.asm:777-783: "8 y los demas se saltan"): los de A2 (5/6) estan aparte; los 4 y 7 se supone que `convert_msg` los expande antes (NO verificado: no he leido `convert_msg`; lo cubre A2).

---------------------------------------------------------------------------------------------------------------------------------

## Resumen por gravedad

| id | gravedad | tema | donde | coste |
|----|----------|------|-------|-------|
| O-2 | MEDIO | camara: zona muerta ±16 px en vez de ±80 y sin histeresis | cam.asm:347-367 | ~25 B overlay |
| O-3 | MEDIO | actorFollowCamera no salta si el actor esta a >160 px | cam.asm:140 | ~20 B overlay |
| G-1 | MEDIO | `_roomPalette` (A1) no se guarda y se resetea al cargar | save.asm:100-111,187; hr.asm:535 | ~30 B overlay + formato de guardado |
| L-1 | MEDIO | actores a color en salas a oscuras (falta el bit 8 de las luces) | actors.asm (ac_mkpal) | ~25 B overlay |
| S-2 | BAJO-MEDIO | VAR_MUSIC_TIMER: 0/0 en todos los sonidos de Zak; no se reescribe cada fotograma ni se pone a 0 al parar | snd.asm:310-381; sound2vgm.py:296 | script Py + ~10 B; comprobar la intro de Zak |
| S-1 | BAJO-MEDIO | cola de sonidos diferida y LIFO por fotograma | snd.asm / game.asm:77 | ~50 B overlay |
| O-1 | BAJO-MEDIO | drawObject no desplaza el punto de caminar (walk_x/y) | overlay.asm:167; walk.asm:872 | ~40 B + RAM; walk.asm es nucleo |
| D-1 | BAJO | VAR_CURRENT_LIGHTS=11 al arrancar (ScummVM v2: 0) | scumm.asm:140 | -5 B (libera) |
| G-2, G-3, L-2, T-1, S-3, O-4, D-2 | BAJO | ver arriba | | |

Ninguno de los hallazgos exige tocar el nucleo bajo $8000, **salvo O-1** (walk.asm). Todos los demas son overlay (8099/8192 usados) o scripts Python.

## Propuesta de reparto (sin choque de ficheros)

0. **Previo (una sesion, solo mecanico)**: hacer sitio en el overlay (>=300 bytes): p. ej. partir `save.asm` + `snd.asm` (frios, ~700 B) a un segundo overlay o moverlos a otra pagina. Toca overlay.asm/scumm.asm/compila_scumm.bat y
   `ovl_entries.inc`. **Tiene que ir antes que las demas**, y esperar a que terminen las sesiones A4-A11 que estan creciendo el overlay.
1. **Camara** (O-2 + O-3, y vigilar `cm_edge` O-4): solo `cam.asm`. Independiente.
2. **Guardado + paleta de sala** (G-1, G-2, G-3): `save.asm` y, si hace falta, una linea en `hr.asm`/`cam.asm` (ho_rcolor). Depende de A1 (commit) y debe ir despues del reparto de overlay.
3. **Luces/actores** (L-1) en `actors.asm` + D-1 en `scumm.asm:140`: dos ficheros, ninguno compartido con 1 y 2.
4. **Sonido** (S-1, S-2, S-3): `snd.asm`, `TOOLS/sound2vgm.py`, `TOOLS/pack_data.py` y, si se quiere, `game.asm` (h_o5_startSound). Antes, mirar con el volcado de la intro de Zak si hay una espera sobre
   VAR_MUSIC_TIMER (var 17).
5. **drawObject / walk** (O-1): `overlay.asm` (ov_drawobj) y `walk.asm` (nucleo): hacerlo en una sesion propia, solo si se reduce primero el nucleo (no caben, solo 5 B libres).

Las sesiones 1, 3 y 4 pueden ir en paralelo (ficheros distintos); la 2 despues de 0 y de A1; la 5 al final.
