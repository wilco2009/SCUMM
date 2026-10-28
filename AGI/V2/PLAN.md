
## Guardar / cargar partida (2026-10-28)

`save.game` y `restore.game` abren una lista de 9 ranuras (un menu de una sola entrada, con el bucle de `menu.input`; arriba/abajo, ENTER, ESC). La descripcion es automatica ("Room n  Score m"). Los ficheros son `SAV/GAMEn.SAV` en la carpeta del juego (hay que crear `SAV`: lo hace `compilavm.bat`): 32 bytes de descripcion y las variables, banderas, inventario, teclas, objetos, cadenas y unos pocos escalares (`sf_tab` en `agib.asm`). Al cargar: se para el sonido, se rehace la imagen (`lastpic`) y los rangos de los objetos fijos, se activan los menus, se pone la bandera 6 y se sale de la logica en curso. No se guarda el texto escrito sobre la imagen con `display` ni el estado de la linea de entrada.
