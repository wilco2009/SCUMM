# PLAN_TRAJES4: trajes de SCUMM v2 en sprites de 4 bpp (formato B), poses precalculadas en DATA.BIN

Decidido con el usuario (22 de noviembre de 2026). Reglas de siempre: sin commit ni push salvo orden; nada de codigo Z80 por encima de $8000;
no compilar el firmware del STM32 (y no usar el MCU para esto: todo en el Z80); sin "_" en ficheros de la SD.

## Decision final

- **Sprites de 4 bpp (formato B)**: 16 colores exactos por pixel, todo a 1/1 (fuera la escala y la eleccion de 2 colores por fila).
- **Poses precalculadas en DATA.BIN** por pack_data (no se componen en el Z80): todas las de caminar (todos los pasos), parado, hablar,
  y cada pose base con cada fotograma de overlay del traje (sombrero, casco, mascara...). Medido: 1170 poses base + 3529 con overlay,
  10.769 celdas unicas -> ~690 KB (hoy ~715 KB con 2 colores por fila, escala y pocos pasos).
- **Carga por demanda** con la cache de paginas de datos que ya existe (dp_cache.inc, 45 paginas, reloj): los datos de cada traje ordenados
  por uso (parado y caminar primero, hablar despues, overlays al final) para que al entrar en una sala solo se lea lo que se dibuja.
- **Compositor Z80 (compose.asm) solo de respaldo** para combinaciones no precalculadas (dos overlays a la vez): exacto pero lento
  (~300 k T por pose, medido). Opcional, al final.
- El estado "que overlay lleva puesto" sigue siendo AC_OVF + overlay_kept (regla de ScummVM: cada animacion solo cambia los miembros
  que nombra), ya generalizada.

## Formato B (SCUMM/AGI/PLAN_SPRITES4.md, FPGA sprite_engine.v y cabecera de POKEs de SD81.v)

- Celda de 32 B: 8 filas de 4 bytes, nibble alto = pixel de la izquierda; color = pal16[indice] (paleta por defecto: codigos Chroma).
- Hoja: bloque de 8 KB `POKE 2129` (se aplica en el VSYNC), leida del espejo de la sombra (lo que ESCRIBE el Z80). Pagina por sprite en el
  campo 29 (`POKE 2130`; 0 = formato A). Mascara 1 = visible en los campos 20-27 (`POKE 2121-2128`). Transparente: nibble alto de `POKE 2103`.
- Los extra (POKE 2131) tienen su entrada de 32 B en la pagina j de la misma hoja.

## Decisiones del usuario (22-11-2026)

- D1. Hoja en el **bloque 0** (`POKE 2129,0`): el overlay esta mapeado de solo lectura, las escrituras solo llegan a la sombra.
  Zonas de la sombra del bloque 0 que NO se pisan (las mismas que AGI): $07E0-$085F (POKEs), $0C00-$0FFF y $1800-$1BFF (tablas),
  $1000-$17FF (traza del depurador), $1E00-$1FFF (fuente). Paginas libres para celdas: 16-62, 67-95, 224-239 (92); pagina 0 = formato A;
  paginas 1-15 = entradas de los extra.
- D2. La forma la da la mascara (forma AND profundidad); el indice 0 es un color (negro), no transparente.
- D3. pal16 por defecto (EGA de SCUMM -> Chroma con lfl2gfx.default_map), sin reservar indices.

## Hecho (sin commit)

- Etapa 1: arnes (`test/test_scumm.cpp`: el bloque 0 escribe en la sombra; POKE 2129, 2130 y el transparente en el volcado) y render
  (`test/render_screen.py`: celdas de 4 bpp desde la hoja; los extra se leen de la sombra en el bloque de POKE 2129).
- Referencia: `costume2.cells4` (compone sin escala en celdas de 4 bpp + forma).
- Compositor Z80 de prueba: `ENGINE/compose.asm` + `test/comp/` (comptest.asm/.cpp, comp_check.py: identico a cells4 en 24 poses;
  all_poses.py: T por pose, mediana 302 k T).

## Diseño de datos (pack_data / costume2)

- Celda en el fondo de celdas: banderas (bit 2 = 4 bpp), 32 B de pixeles, 8 B de forma. Paleta del actor (ac_pm) aplicada nibble a nibble al copiar.
- Un traje = varios sub-bloques (cada uno cabe en una pagina de 6 KB, formato de costume_blob: na, tabla de celdas, listas por animacion).
  El primero lleva un directorio: clave -> (pagina, direccion) del sub-bloque que la tiene. Claves: 0-3 caminar, 4-7 hablar, 4*f+dir
  overlay parado, 128 + 4*f + dir caminar con el overlay f. Sustituye a las paginas de andar actuales.

## Cambios en el Z80

1. acd_anim: si la animacion no esta en el sub-bloque mapeado, buscarla en el directorio y mapear su pagina (generaliza acd_wov).
2. acd_cell: celda de 4 bpp -> copiar 32 B a la pagina de hoja de la ranura (bloque 0: `$0000 + 32 * pagina`), campo 29 = pagina,
   mascara = forma AND profundidad (acd_mput). Una pagina de hoja fija por ranura (63 normales + 15 extra = 78 de las 92 libres).
3. POKE 2129 = 0; SPRX pasa al bloque 0 (las entradas de los extra en $0020 + 32 * j); ac_xd (SPRX+30) es una variable: moverla a RAM.
4. Paleta del actor nibble a nibble (solo si ac_pf).
5. Quitar la escala y lo que sobre de las paginas de andar (walk_overlay_blob, walk_blob_fit).

## Estado (22-11-2026, sin commit)

- pack_data: cada traje = sub-bloques de animaciones (costume2.keys_blob4: fotogramas con referencias (posicion, fondo, indice)) + fondos de
  celdas compartidos por todo el traje (costume2.costume4, en orden de primer uso) + directorio (COSTDIR -> u8 na, na x (pagina, direccion),
  u8 fondos, fondos x (pagina, direccion)). Todos los pasos de caminar, tambien con overlay (claves WALK_OVL = 128 + 4 * f + dir).
  Zak: 141 paginas desde la 16 (antes 156), trajes 559 KB; Maniac: 74 paginas.
  Celda: banderas (bit 2 = 4 bpp, bit 0 forma completa, nibble alto = color transparente que la celda no usa), 32 B, 8 B de forma.
- Z80 (actors.asm): ac_key (clave -> sub-bloque por el directorio), seleccion de pose reescrita (sin acd_wov ni paginas de andar),
  acd_nd copia las referencias a AC_RB ($DC85) y acd_cell mapea el fondo de cada celda (ac_lpool / ac_pool), acd_b4 (celda a la hoja:
  pagina fija por ranura con ac_shp, transparente, paleta del actor nibble a nibble, forma AND profundidad), ac_mkpal calcula ac_ptr.
  SPRX = $0000, POKE 2129 = 0 en ov_init, ac_xd a $94FF. Overlay 1: 7753 de 8192.
- Pruebas (arnes): sombrero_vendedor, casco_melissa, disfraz_capo y mascara_curandero pasan; renders de las salas 4, 16, 28 y 38 bien;
  con 3 actores en la sala 4 se usan 5 extra y se ven bien.
- Velocidad (sala 4, Zak andando, fotogramas 100-300): 8,54 M instrucciones frente a 7,40 M antes (+15 %): sobre todo el cambio de pagina del
  fondo por celda. Se puede mejorar (cachear la tabla de fondos del traje).
- Sin probar en placa: que las escrituras al bloque 0 con el overlay mapeado lleguen a la hoja de la FPGA (nunca se ha probado en placa);
  sprites por linea con personajes a 1/1 (10 en la prueba de 3 actores; tope 12); POKE 2129 no se devuelve a 2 al volver a BASIC
  (no cabe en el nucleo).
- Pendiente de limpiar: funciones viejas sin uso (scaled_costume, best_costume, walk_pages, walk_blob_fit en pack_data; costume_blob,
  walk_overlay_blob, cells_of con escala, blob4 ya no existe) y `[trajes] escala` de games/zak.cfg.

## Complementos que se suman (23-11-2026, sin commit)

- Gafas y sombrero del ego (script 150: animateActor 1 con Var[164], Var[167] y 68): en ScummVM cada animacion cambia solo los miembros que
  nombra y los fotogramas se suman; AC_OVF guardaba solo el ultimo (el 17, que no dibuja nada). costume2.overlay_combos: complementos = miembros
  que no nombran las animaciones 0-23; los estados que no son de un fotograma solo son fotogramas virtuales (desde num_anim // 4 + 1, con poses
  parado y caminar). El directorio del traje lleva detras de los fondos u8 n y n x (actual, fotograma, nuevo); ac_trans (actors.asm) lo busca
  en act_s. Zak: 12 virtuales, 118 transiciones; DATA.BIN 159 paginas (antes 141).
- save.asm: COSTDIR ($FF40) esta en la zona guardada; al cargar se conserva el de la DATA.BIN actual (como ROOMDIR+13).

## Etapas

1. [hecho] Arnes y render con formato B.
2. [hecho] Referencia en Python y prototipo del compositor (medido: demasiado lento para todas las poses -> poses precalculadas).
3. [hecho] pack_data/costume2: sub-bloques de 4 bpp con directorio; comprobar tamano total y paginas.
4. [hecho] Z80: acd_anim con directorio, acd_cell en 4 bpp, hoja en el bloque 0, extra en el bloque 0.
5. Pruebas: casco_melissa, sombrero_vendedor, disfraz_capo, mascara_curandero, renders de varias salas, Maniac; medir la carga de paginas.
