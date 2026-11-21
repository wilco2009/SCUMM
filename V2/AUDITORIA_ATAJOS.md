# Auditoria de atajos del interprete SCUMM v2 (V2/ENGINE) frente a ScummVM

**Estado: PARCIAL.** Se agoto el limite de uso a mitad. Lo de aqui esta verificado leyendo codigo
(ENGINE y `scummvm_src/engines/scumm`) y con un histograma de opcodes sobre los datos reales
de Maniac y Zak (script de trabajo propio, no incluido en el repo). Lo que NO se reviso esta
al final. Los numeros de linea son aproximados: otras sesiones tienen cambios sin commit.

Metodo del histograma: `scummdis.py` sobre todos los scripts globales, ENCD, EXCD y objetos
de ambos juegos (1 script de Maniac y la sala 0 de cada juego no decodifican: no afecta).

## Conclusion general
El nucleo (`vm_core.asm`: control de flujo, variables, ranuras, estados, doSentence, cola de
frases) y `walk.asm`/`geom.asm` (cajas, adjustXYToBeInBox, banderas de caja) son transcripciones
fieles de ScummVM, incluso con sus peculiaridades. Los atajos estan casi todos en el lado
"anfitrion" (`host_ops` en `cam.asm`, interfaz, texto, camara) y en lo que se ignora.

## A. Usado en los datos reales y DIFERENTE / IGNORADO (por impacto)

### A1. roomOps ignorado (opcode 0x33/0xB3/0xF3) — ALTO
- Ubicacion: `cam.asm` `host_ops` (~l.8-35) no tiene caso para $33 -> vuelve sin hacer nada.
- ScummVM (`script_v2.cpp:1500`): subop 1 SO_ROOM_SCROLL fija VAR_CAMERA_MIN_X / MAX_X
  (a*8, b*8, acotado a 160..ancho-160); subop 2 SO_ROOM_COLOR hace `_roomPalette[b]=a` y
  repinta. `startScene` reinicia `_roomPalette[i]=i`.
- Datos: Zak 176 usos (51 scroll, 125 color); Maniac 0 (1 en bytes muertos).
  Scroll en ENCD de salas 10,15,23,27,28,33,35,36,37,38,40,43,44,53 y scripts 100,121.
  Color en ENCD de salas 14,21,23,24,29,37,45,48,52,53 y scripts 64 y 66 (muchos).
- Efecto: la camara no respeta los limites que fija el script (salas anchas de Zak,
  p. ej. la 23 con 34/56/100); colores de sala sin remapear. No existe `_roomPalette` en el motor.
- Coste: scroll BAJO (2 variables + clamp, ya existe `cm_clamp`); color MEDIO-ALTO
  (hace falta una tabla de remapeo de colores de sala en el vídeo HiRes/paleta; ver sesion zak-paleta).
- Fallos conocidos relacionados: "paleta"/"negro azul" (parcial).

### A2. Codigo de texto 6 (nombre de objeto/actor) sin soporte — ALTO
- `game.asm` `convert_msg` (~l.620-630): codigos 5 y 6 -> `jr cm_space`, no emiten nada.
- ScummVM (`string.cpp:1656`): 6 -> `convertNameMessage` = nombre del objeto o actor de la variable;
  5 -> `convertVerbMessage` (nombre del verbo).
- Datos: Zak 14 mensajes con codigo 6 (scripts 24, 26, 53, 62, 78, 119, 133, 138, 149; p. ej.
  "That's the last X with transparent gloves", "Put it in the X"). Codigo 5: 0 usos. Maniac: 0 usos de 6.
- Efecto: frases con el nombre perdido ("Put it in the .").
- Coste: BAJO-MEDIO (ya hay `ui_objname` que resuelve nombre de objeto/actor, incl. setObjectName).

### A3. Proteccion de copia de Zak (startScript 15 en sala 45) — ALTO (jugabilidad)
- `vm_core.asm` `h_o2_startScript` (~l.1379) solo trata los scripts 87 y 155 (parche de Maniac).
- ScummVM (`script_v2.cpp:1129`): con `_copyProtection` falso (por omision) NO arranca el
  script 15 si la sala es la 45. El script 15 pide el codigo de la rueda ("Traveler's Section... Enter code").
- Se arranca desde los scripts 13, 24 y 30. Sin el atajo hay que tener el manual.
- Coste: BAJO (lista "no arrancar script N en sala M" en el perfil `zak.cfg`/PROF).

### A4. Mensajes sin actor: color de `_string[0].color` ignorado — MEDIO
- `game.asm` `h_o2_actorOps` (~l.387-390): actor 0 + subop 5 = `ret` (ScummVM guarda `_string[0].color=arg`).
  `scumm.asm` `tx_setclr` (~l.1127): sin actor habla -> blanco fijo ($0F).
- ScummVM: `actorTalk` con actor 0xFF usa `_string[0].color` (los boot scripts de ambos juegos
  lo ponen a 9, tambien s52/s64/s107/s135 y ENCD de salas 43 y 9 lo cambian).
  Datos: print(255,...) 74 veces en Maniac, 112 en Zak.
- Efecto: textos de sistema/narracion siempre blancos en vez del color del script.
- Coste: BAJO (guardar el byte; `tx_setclr` ya traduce EGA->Chroma).

### A5. Boton derecho = ESC (saltar cutscene) en v2 — MEDIO
- `scumm.asm` `keys` (~l.511-522): el boton derecho en la escena hace `reset_sentence` y ejecuta
  un clic de escena (camina).
- ScummVM (`input.cpp:436`): en v0-v3 el clic derecho se trata como la tecla ESC
  (cutsceneExitKey) y NO ejecuta el script 4 de escena.
- Efecto: el clic derecho no salta las cutscenes con override y si hace caminar al ego.
- Coste: BAJO. Cuidado: el usuario puede preferir el atajo actual por la botonera del ZX81.

### A6. Temporizacion: DELTA en fotogramas de 50 Hz y recortado a 15 — MEDIO (HECHO: DELTA en jiffies con resto; el recorte a 15 es el de ScummVM y se conserva)
- `scumm.asm` `main_loop` (~l.157-190) espera TIMER_NEXT*5/6 fotogramas y pasa `DELTA` = fotogramas;
  `vm_core.asm` `vm_frame` (~l.179-183) recorta DELTA a 15.
- ScummVM: `scummLoop(delta)` con delta = VAR_TIMER_NEXT en jiffies (1/60 s); `waitForTimer(delta*4)`.
  Nada de recorte.
- Efecto: delays y `_talkDelay` descuentan 1 por fotograma (50/s) en vez de 60/s: ~20 % mas lento;
  tras una carga pesada el recorte a 15 pierde tiempo (una pausa larga dura de mas).
- Relacionado: intro de Zak parada por MACHINE_SPEED (ya arreglado, perfil `maquina=0x7FFF`).
- Coste: BAJO-MEDIO (convertir frames a jiffies: DELTA = frames*6/5; quitar el recorte con cuidado).

### A7. Orden dentro del fotograma — BAJO-MEDIO (HECHO: vm_frame en el orden de ScummVM)
- Nuestro `vm_frame`: delays -> displayDialog -> process_input -> check_sentence -> runAllScripts -> walkActors.
- ScummVM: displayDialog -> processInput(script 4) -> updateScummVars -> runAllScripts -> checkExecVerbs ->
  checkAndRunSentenceScript -> walkActors -> camara.
- Efecto: la frase (script 2) corre un fotograma antes que en ScummVM respecto a los demas scripts.
- Coste: BAJO, pero puede cambiar tiempos finos de los scripts de dialogos; probar.

### A8. getActorFromPos "aproximado" — MEDIO
- `input.asm` `h_o2_actorFromPos` (~l.189): rectangulo del sprite dibujado (o 16x32).
- ScummVM v2 (`actor.cpp:2115`): salta el ego; usa y2 = pos.y, y1 = pos.y - 80 (si `(uint16)y1>128` y1=1)
  y comprueba x con los bits de uso de graficos (stripes dibujados).
- Efecto: clics sobre personajes (Zak 1 uso, Maniac 1 uso, pero pasa por script 4/click) pueden acertar o fallar distinto.
- Coste: MEDIO.

### A9. Interfaz: colores, resaltado, modo "dim" — MEDIO (parte hardware)
- `ui.asm` `ui_draw_verb`, `hrui.asm`: todo se pinta en un color; no hay `color/hicolor/dimcolor`
  (ScummVM: color 2, hicolor `_hiLiteColorVerbArrow`, dimcolor 8), ni resaltado al pasar el cursor
  (`checkV2MouseOver`), ni los verbos en modo 2 (atenuado) se distinguen.
- Solo 15 ranuras de verbo (ScummVM `_numVerbs`); los datos usan ranuras 0-14 en ambos juegos: suficiente.
- Teclas: solo digitos 1-9,0 (perfil `[teclas]`); no hay teclas de verbo (`vs->key`), ni u/j/i/o/k/l de inventario,
  ni '+'/'-' de velocidad de texto (ScummVM `_defaultTextSpeed`, aqui fija a 6 = valor por omision),
  ni espacio=pausa, ni F8 restart. Razon: teclado del ZX81 (hardware).
- Coste: ALTO para colores (atributos por celda); BAJO para resaltado/atenuado con otro atributo.

### A10. setObjPreposition ignorado (0x0B/0x4B/0x8B/0xCB) — BAJO
- `host_ops` sin caso. Zak 1 uso (sala 25 EXCD, objeto 81 prep 0). ScummVM cambia la preposicion del objeto.
  Efecto practico casi nulo (prep 0). Coste: BAJO (escribir bits 5-7 del byte 12 en el bloque del objeto).

### A11. pickupObject incompleto — BAJO
- `input.asm` `h_o2_pickupObject` (~l.830): no comprueba `getObjectIndex==-1` (objeto que no esta en la sala se ignora en ScummVM),
  no hace `markObjectRectAsDirty`/`clearDrawObjectQueue` ni `runInventoryScript(1)` (redibujar inventario: lo hace la UI por UI_DIRTY).
- Fallo conocido relacionado: dibujo de objetos tras recoger (sombrero?).

## B. Aproximado por hardware / aceptable (documentado)
- Efectos de transicion de sala (`fadeOut/_newEffect`) no existen (cosmetico).
- `getRandomNr`: LCG propio en vez del RNG de ScummVM (no comparable por definicion).
- NSLOT 24 en vez de 80 ranuras; MAXNEST 15; SENTQ de 6 (como ScummVM `NUM_SENTENCE`).
- Camara: nuestra ventana mide 256 px (no 320): `cam.asm` recentra con 128 y mueve 8 px/frame con
  fino por hardware; ScummVM mueve la camara por tiras y `panCameraTo` a 1 stripe por fotograma (equivalente aprox.).
- Cursor/clic por teclado de ZX81, ratón BT.
- resourceRoutines (0x0C): ignorado, igual de inocuo (gestion de memoria; 211+268 usos).
- o2_dummy 0x5C/6B/6E y switchCostumeSet (v2 PC = dummy): IGNORADO igual que ScummVM.

## C. IMPLEMENTADO igual (verificado)
stopObjectCode, breakHere, delay/delayVariable, saltos y comparaciones (sin signo como `uint16` de ScummVM), move/add/sub/
inc/dec/indirectos, setVarRange, get/setBitVar, startScript (87/155 de Maniac), stopScript, chainScript, isScriptRunning,
waitForMessage/Sentence, estados de objeto (set/if State*), doSentence (cola, FB/FC, subops 1/2),
checkAndRunSentenceScript, runInputScript (variables), runObjectScript (verbos 250/253/254), getDist,
getClosestObjActor, findObject, ifClassOfIs, getObjPreposition, setOwnerOf/getObjectOwner, inventario por ranuras,
cutscene/endCutscene/beginOverride + ESC (VAR_CUTSCENEEXIT_KEY 4/13/64->27), freeze/unfreeze, setBoxFlags,
box flags en adjustXYToBeInBox/walk, startScene (orden de EXCD, kill, resetSentence, hide, camara min/max 160, ENCD, script 5),
loadRoomWithEgo, pseudoRoom, actorOps (sound, costume, talkcolor, name, SO_PALETTE por actor: ya arreglado),
displayDialog (60 + 6/char, 320 en salto de linea), VAR_CHARCOUNT/HAVE_MSG, saveLoadGame (parcial, ver D).

## D. NO REVISADO (queda pendiente)
- Variables del sistema: comprobar VAR_* en `vars_v2.inc` contra `setupScummVars` (visto: faltan nombres
  VAR_EGO(0), VAR_MACHINE_SPEED(6, se escribe como VARS+12), VAR_NUM_ACTOR(11), VAR_CURRENTDRIVE(13);
  `resetScummVars` v2 solo fija MACHINE_SPEED=0x7FFF en Zak: OK; falta verificar VAR_TIMER_NEXT inicial,
  VAR_CAMERA_POS_X por fotograma, VAR_MUSIC_TIMER).
- Sonido (`snd.asm`, `h_o5_startSound`: ScummVM comprueba prioridad/cola de Player_V2; sonidos 47,48,53 no PCjr; VGM largos
  recortados a 180 s/1 h; musica no se guarda al guardar partida).
- Guardar/cargar (`save.asm`): no guarda el estado de la musica; no revisado el resto (ACTPAL, camara, dark).
- Luces/linterna (`dark.asm`, `ho_lights`: lights(a,b,c=1) tamano; ScummVM v2 usa `_flashlight` xsize/ysize).
- drawObject (`overlay.asm`), mascaras/orden de dibujo, escala (v2 no tiene escala por caja: no aplica),
  elevacion, `animateActor`/`startAnim` detalle, `actorFollowCamera` fino, putActorAtObject, faceActor.
- Mensajes: codigos de texto 1/2/3/8 (73 + 110 en datos, tratados en `display_dialog`), offsets de texto sobre actor
  (nuestro texto va en filas fijas, ScummVM `_string[0].overhead`).

## E. Propuesta de orden de trabajo (por ficheros, sin pisarse)
1. `vm_core.asm` + `progdata`/`games/zak.cfg` + `gameprofile.py`: A3 (saltar script 15 en sala 45), A6 (DELTA en jiffies, quitar recorte) y A7 (orden).
2. `game.asm` (+ `ui.asm` para el nombre): A2 (codigos 5/6) y A4 (color de `_string[0]`; escribir en `h_o2_actorOps`, leer en `scumm.asm tx_setclr`).
3. `cam.asm`: A1-scroll (roomOps subop 1), A10 (setObjPreposition), A5 (clic derecho = ESC; coordinar con `scumm.asm` keys).
4. Paleta (sesion zak-paleta): A1-color (roomOps subop 2 + reset en startScene) tocando `hr.asm`/`hrui.asm`/`dark.asm`/`ovl`.
5. `input.asm`: A8 (actorFromPos), A11 (pickupObject).
6. UI (`ui.asm`/`hrui.asm`): A9 (resaltado/atenuado), si se quiere.
7. Despues: revisar D (sonido, save, luces) en una segunda pasada.
