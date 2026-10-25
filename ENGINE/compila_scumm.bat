@echo off
rem Ensambla el programa SCUMM y lo copia a la SD del emulador con esta disposicion:
rem   SCUMM\SCUMM.BIN                      el programa, comun a todos los juegos
rem   SCUMM\MANIAC\MANIAC.B81              el BASIC que lo arranca (la carpeta actual debe ser la del juego)
rem   SCUMM\MANIAC\DATA\DATA.BIN, ROOMnn.GFX, SND\SOUNDnnn.VGM   los datos del juego
rem Los nombres de los ficheros son relativos a la carpeta actual, asi que el mismo SCUMM.BIN sirve para cualquier juego.
rem Antes hay que haber generado los datos (ver SCUMM\TOOLS\LFL2GFX.md y SCUMM\TOOLS\pack_data.py):
rem   python SCUMM\TOOLS\lfl2gfx.py SCUMM\V2\ManiacMansionDOS all -o SCUMM\preview
rem   python SCUMM\TOOLS\pack_data.py SCUMM\V2\ManiacMansionDOS SCUMM\preview\DATA.BIN --game SCUMM\games\maniac.cfg --sounds SCUMM\preview\snd
rem   python SCUMM\TOOLS\sound2vgm.py SCUMM\V2\ManiacMansionDOS SCUMM\preview\snd
cd /d "%~dp0"
set BASE=\ClaudeCode\Eightyone2\EightyOne\SD81\SD81
rem sin argumento copia los datos de Maniac Mansion; con 'zak' (o 'zack') los de Zak McKracken (SCUMM\preview_zak, ver games\zak.cfg)
set P=..\preview
set G=MANIAC
if /i "%1"=="zak" set P=..\preview_zak
if /i "%1"=="zak" set G=ZAK
if /i "%1"=="zack" set P=..\preview_zak
if /i "%1"=="zack" set G=ZAK
echo Juego: %G% (datos de %P%)
rem montaje en tres pasos: el overlay (overlay.asm) necesita las direcciones del programa (scumm.sym) y el programa incluye overlay.bin al final
if not exist overlay.bin type nul > overlay.bin
pasmo scumm.asm scumm.bin scumm.sym || goto error
pasmo overlay.asm overlay.bin overlay.sym || goto error
pasmo scumm.asm scumm.bin scumm.sym || goto error
set D=%BASE%\SCUMM\%G%
rem el perfil del juego (games\*.cfg) va dentro de DATA.BIN: se regenera siempre para que un cambio en el .cfg llegue a la SD
if /i "%G%"=="MANIAC" python ..\TOOLS\pack_data.py ..\V2\ManiacMansionDOS %P%\DATA.BIN --game ..\games\maniac.cfg --sounds %P%\snd >nul || goto error
if /i "%G%"=="ZAK" python ..\TOOLS\pack_data.py "..\V2\Zak McKracken" %P%\DATA.BIN --game ..\games\zak.cfg --sounds %P%\snd >nul || goto error
if not exist "%D%\DATA\SND" mkdir "%D%\DATA\SND"
copy /y scumm.bin "%BASE%\SCUMM\SCUMM.BIN" >nul || goto error
copy /y SCUMM.B81 "%D%\%G%.B81" >nul || goto error
copy /y %P%\DATA.BIN "%D%\DATA" >nul || goto error
copy /y %P%\gfx\*.GFX "%D%\DATA" >nul || goto error
if exist %P%\snd\*.VGM copy /y %P%\snd\*.VGM "%D%\DATA\SND" >nul
echo OK: %BASE%\SCUMM\SCUMM.BIN y el juego en %D%
echo Para jugar: entra en la carpeta %G% y carga %G%
exit /b 0

:error
echo *** ERROR: se para aqui ***
exit /b 1
