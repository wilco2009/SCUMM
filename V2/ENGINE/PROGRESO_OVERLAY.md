# Particion del overlay (progreso)

Estado: **hecho y probado en el arnes** (carpeta temporal; no se han tocado los .bin de ENGINE ni el emulador). Sin commit.

## Diseno
* Overlay 1 (`overlay.asm`, pagina 50, bloque 0 siempre): ui, hrui, cam, actors, dark, mouse y las rutinas sueltas. Tabla de entradas (`ovl_entries.inc`) sin cambios: los `call OVL_xxx` del residente no cambian de significado; `OVL_SND_EVENT` (21) y `OVL_SND_TICK` (24) siguen existiendo y saltan a las puertas.
* Overlay 2 (`overlay2.asm`, pagina 51 = `OVL2_PAGE`): `snd.asm` + `save.asm` (`ho_saveload` -> `sv_saveload`). Se ensambla DESPUES de overlay.asm (incluye `overlay.sym`).
* Puertas (overlay.asm, tras la tabla): `ovg_ev`, `ovg_tick`, `ovg_sv` = `ld d,a / ld bc,pagina*256+$E7 / xor a / out (c),a`; la instruccion siguiente ya sale del overlay 2, que tiene ahi un `jp` a su rutina. Al acabar `ov2_exit` (6 bytes, justo antes de `ovg_ret`) vuelve a mapear el overlay 1 y la instruccion siguiente es el `ret` de `ovg_ret`. Coste residente: 0 bytes (`ac_sp` sigue en $7FDE). Coste por llamada: 2 OUT.
* Copia a su pagina: `ov_copy2` (overlay 1, la llama `ov_init`) usa `ov_done` del residente (1 = recien copiado el overlay 1; pasa a 2 al copiar el 2; un restart no copia nada; `sc_quit` pone 0 y se copian los dos). El residente no cambia salvo `scumm.asm`: `OVERLAY2_IMAGE: incbin "overlay2.bin"` va el primero (en $A000) y `OVERLAY_IMAGE` detras (la direccion del overlay 2 no depende del tamano del 1). `ov_copy2` copia `OV2_COPY` ($0C00) bytes: `overlay2.asm` da error si no caben.
* `sdx_ini` (solo pone variables a cero) se quedo en el overlay 1 porque ov_init corre antes de copiar el overlay 2.
* Cargar partida: `gf_load_room` llama a `OVL_DKMASK`/`OVL_DARK` (overlay 1), que no pueden ejecutarse con el overlay 2 en el bloque 0. `sv_saveload` solo pone `SV_FIN`=1 ($9797, byte libre) y el envoltorio `ho_saveload` del overlay 1 hace despues `gf_load_room`, `load_slot` y HRES=3 (lo mismo que antes, en el mismo orden).
* Pagina 51: ya no la usaba la cache de paginas de datos (el indice de la 50 se salta; la 51 queda libre por el desplazamiento).

## Reglas para ampliar
* Codigo nuevo de guardado/paleta/sonido: en `save.asm`/`snd.asm` (overlay 2): no puede llamar a nada del overlay 1 ni a resident->OVL_xxx. Si lo necesita, hacerlo en el envoltorio de overlay 1 (como `ho_saveload`).
* Camara, luces, teclas: overlay 1 (cam.asm, actors.asm/dark.asm, ui.asm).
* Compilacion: 4 pasos (scumm, savestamp, overlay, overlay2, scumm). `compila_scumm.bat` y `build_scumm.sh` ya los hacen.

## Tamanos (compilado en la carpeta temporal)
| | antes | ahora |
|--|--|--|
| overlay 1 | 8202 de 8192 (!) | 7043 -> **1149 libres** |
| overlay 2 | - | 1363 (tope OV2_COPY 3072: 1709 libres; la pagina da hasta 8192) |
| residente (`ac_sp`) | $7FDE | $7FDE (igual) |

## Pruebas (arnes test_scumm, Zak, 900 fotogramas)
* check_hr: 0 bytes distintos; pantalla renderizada identica byte a byte a la de antes; mismos sucesos de sonido (3 en 900 fot., 170 en 3000, identicos).
* Guardar (SAVE01.SAV) y cargar por `ho_saveload`: ficheros identicos byte a byte a los del programa anterior, HRES=3, SV_FIN sube y baja, ERR=0, misma sala.
* Formato de partidas guardadas, perfil y DATA.BIN: **sin cambios**.
* Nota: el overlay de antes (8202) desbordaba la pagina en 10 bytes ($4000-$4009 del residente en el arnes): la base ya estaba rota.

## Pendiente / riesgos
* Probar en placa/emulador real que el `OUT` del bloque 0 con la instruccion siguiente leida de la otra pagina funciona (el arnes lo simula; el hardware mapea de forma combinacional).
* `TS_OSYM=overlay.sym` ya no tiene los simbolos del sonido y de guardar (estan en `overlay2.sym`).
