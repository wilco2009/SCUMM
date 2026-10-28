# AGI en el ZX81: teclas, menus y controladores (pendiente de decidir)

Documento de trabajo (2026-10-28) para cuando haya que decidir **que teclas nuevas hacen falta**. Los datos son de SQ1 (logicas 0, 100 y 104); los otros juegos de Sierra
tienen el mismo esquema con pequenas diferencias.

## 1. Como funciona en AGI

- El juego asigna teclas del PC a **controladores** con `set.key(ascii, codigo, controlador)` (logica 104 en SQ1). Las teclas de funcion son `ascii = 0` y el codigo de
  barrido del PC (F1 = 59 ... F10 = 68); las de control, el ASCII (Ctrl-C = 3, Ctrl-E = 5, Tab = 9, Ctrl-J = 10, Ctrl-R = 18...).
- Al pulsar la tecla se enciende el controlador y la logica 0 ejecuta la accion (`controller(cN)`). Casi todas las acciones tienen **otro camino**: la orden escrita
  (`said`, p. ej. "save game") o el menu (ESC), asi que una tecla de funcion es solo un atajo.
- Los textos del menu llevan escrita la tecla del PC (`Save <F5>`, `Quit <Alt-Z>`...). En el ZX81 esos textos no valen: hay que cambiarlos (ver 5).

## 2. Teclado del ZX81 hoy (`ENGINE/agia.asm`)

| Capa | Teclas |
|------|--------|
| Base | letras en minuscula, espacio, `.`; cifras **solas** = funciones: `5`/`6`/`7`/`8` = izquierda/abajo/arriba/derecha del ego (se combinan en diagonal), `9` = **ESC** (la unica), `0` = borrar |
| SHIFT | letras en mayuscula y cifras |
| ENTER + tecla | simbolos (`: ; ? / \ ~ \` ' { } [ _ ! @ # \| % & " ) ( $ ] = + - ^`); ENTER solo = retorno de carro (al soltar) |
| **Libres** | las cifras **1, 2, 3 y 4 solas** (antes `1` era ESC) |

## 3. Opciones del menu de SQ1 (ESC)

Controlador y tecla del PC segun la logica 104. "Texto" = se puede escribir la orden. Estado = en este interprete.

| Menu | Opcion | Ctrl | Tecla PC | Texto | Estado |
|------|--------|------|----------|-------|--------|
| Sierra | About SQ | c21 | — | — | hecho (ventana) |
| Sierra | Help | c2 | F1 | "help" | falta: llama a la logica 92 (paginas de ayuda con texto); revisar |
| File | Save | c3 | F5 | "save game" | hecho |
| File | Restore | c5 | F7 | "restore game" | hecho |
| File | (separador) | c20 | — | — | desactivado por el juego |
| File | Restart | c7 | F9 | "restart game" | hecho: confirmacion (ENTER reinicia, ESC sigue) y el estado vuelve al del arranque |
| File | Quit | c1 | Alt-Z | "quit" | hecho (para el interprete) |
| Action | See Object | c22 (y c4) | F4 | — | hecho a medias: `show.obj` muestra la **descripcion** del objeto (el dibujo no) |
| Action | Inventory | c10 | Tab | — | hecho: ventana con la lista; con "See Object" se elige un objeto (flechas y ENTER) |
| Special | Sound On/Off | c16 | F2 | — | hecho (bandera 9); al apagarlo se para el sonido que suene |
| Special | Graphics Mode | c12 | Ctrl-R | — | no aplica (`toggle.monitor`) |
| Special | Joystick / Controller | c15 | Ctrl-J | — | no aplica (`init.joy`) |
| Special | Pause | c18 | Esc (otros equipos) | "pause game" | hecho (ventana, cualquier tecla sigue) |
| Speed | Normal / Slow / Fast / Fastest | c24 / c25 / c23 / c28 | — (F10 = c29) | "normal", "slow", "fast", "fastest" | hecho (v10) |

## 4. Otras teclas que el juego asigna y que no tienen opcion de menu

| Ctrl | Tecla PC | Accion | Necesidad |
|------|----------|--------|-----------|
| c9 | F3, Ctrl-E | `echo.line`: repite la ultima orden en la linea de entrada | **util**: el comando ya esta hecho, falta una tecla |
| c17 | Ctrl-C | `cancel.line`: borra la linea de entrada | **util** (hoy se borra con la tecla 0) |
| c26 / c27 | `+` / `-` | volumen (v23, de 0 a 15) | opcional: hoy el volumen no llega al AY |
| c6 / c8 | F6 / F8 | ponen las banderas 128 / 130 (usos propios de SQ1) | no hace falta |
| c29 | F10 | uso propio del juego | no hace falta |
| c13 | Alt-1 | `show.mem` (depuracion) | no aplica |
| c14 | Alt-D | `version` (depuracion) | no aplica |
| c19 | Esc | menu | hecho (tecla 9) |

## 5. Decisiones pendientes

1. **Que teclas para `echo.line` y `cancel.line`** (y, si se quiere, volumen). Opciones:
   - las cifras libres `1`, `2`, `3`, `4` solas (cuestan una tecla de funcion cada una);
   - la capa ENTER + tecla (p. ej. ENTER+E y ENTER+C: da los codigos 5 y 3 que ya espera el juego sin tocar `set.key`);
   - dejarlo sin tecla (la orden se retecla; `cancel.line` ya lo hace la tecla 0).
   `agia.asm` (overlay A) esta casi lleno (8014 de 8192 bytes): cualquier tecla nueva obliga a hacer sitio.
2. **Textos del menu**: sustituir `<F5>`, `<Alt-Z>`, `<Tab>`... por la tecla real del ZX81, o quitarlos (todo es accesible desde el menu con las flechas y ENTER). Los
   mensajes son de la logica 0; habria que cambiarlos al cargar el juego (en la conversion, `agi2log.py`) para no tocar los datos originales.
3. **Pantalla de ayuda** (c2, logica 92): habla de las teclas del PC; hay que reescribirla con las del ZX81.
4. **Otros juegos** (KQ1, KQ2, PQ1, SQ2, Larry1): repetir esta tabla con su logica de teclas antes de fijar la correspondencia.
5. **Funciones que faltan** (no son teclas): el dibujo de `show.obj`.

## 6. Que se puede hacer ya sin teclas nuevas

Todo lo del menu se alcanza con ESC (tecla 9), las flechas (5/6/7/8) y ENTER, y casi todo tambien escribiendo la orden. Las teclas de la seccion 4 son comodidad.
