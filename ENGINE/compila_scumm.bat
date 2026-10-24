@echo off
rem Ensambla el programa SCUMM y lo copia, con DATA.BIN y los ROOMnn.GFX, a la SD del emulador.
rem Antes hay que haber generado los datos (ver SCUMM\TOOLS\LFL2GFX.md y SCUMM\TOOLS\pack_data.py):
rem   python SCUMM\TOOLS\lfl2gfx.py SCUMM\V2\ManiacMansionDOS all -o SCUMM\preview
rem   python SCUMM\TOOLS\pack_data.py SCUMM\V2\ManiacMansionDOS SCUMM\preview\DATA.BIN --game SCUMM\games\maniac.cfg --sounds SCUMM\preview\snd
rem   python SCUMM\TOOLS\sound2vgm.py SCUMM\V2\ManiacMansionDOS SCUMM\preview\snd
cd /d "%~dp0"
set BASE=\ClaudeCode\Eightyone2\EightyOne\SD81
rem con el argumento 'zak' copia los datos de Zak McKracken (SCUMM\preview_zak, ver games\zak.cfg) en vez de los de Maniac Mansion
set P=..\preview
if /i "%1"=="zak" set P=..\preview_zak
if /i "%1"=="zack" set P=..\preview_zak
if /i "%P%"=="..\preview_zak" (echo Datos de Zak McKracken) else (echo Datos de Maniac Mansion)
rem montaje en tres pasos: el overlay (overlay.asm) necesita las direcciones del programa (scumm.sym) y el programa incluye overlay.bin al final
if not exist overlay.bin type nul > overlay.bin
pasmo scumm.asm scumm.bin scumm.sym || goto error
pasmo overlay.asm overlay.bin overlay.sym || goto error
pasmo scumm.asm scumm.bin scumm.sym || goto error
if not exist "%BASE%\TOOLS\SCUMM" mkdir "%BASE%\TOOLS\SCUMM"
if not exist "%BASE%\SCUMM" mkdir "%BASE%\SCUMM"
copy /y scumm.bin "%BASE%\TOOLS\SCUMM" >nul || goto error
copy /y SCUMM.B81 "%BASE%\TOOLS\SCUMM" >nul || goto error
copy /y %P%\DATA.BIN "%BASE%\SCUMM" >nul || goto error
copy /y %P%\gfx\*.GFX "%BASE%\SCUMM" >nul || goto error
if not exist "%BASE%\SCUMM\SND" mkdir "%BASE%\SCUMM\SND"
if exist %P%\snd\*.VGM copy /y %P%\snd\*.VGM "%BASE%\SCUMM\SND" >nul
echo OK: SCUMM copiado en %BASE%\TOOLS\SCUMM y los datos en %BASE%\SCUMM
exit /b 0

:error
echo *** ERROR: se para aqui ***
exit /b 1
