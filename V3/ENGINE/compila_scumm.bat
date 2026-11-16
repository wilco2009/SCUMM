@echo off
rem Fase 9 (SCUMM\V3\PLAN.md): ensambla el programa SCUMM v3 (Indiana Jones and the Last Crusade, EGA) y deja en una carpeta lista para copiar a la SD:
rem   SCUMM\V3\SCUMM.BIN                          el programa (se carga en $4200 y se entra por RAND USR 16917)
rem   SCUMM\V3\INDY3\INDY3.B81                    el BASIC que lo arranca (la carpeta actual debe ser la del juego)
rem   SCUMM\V3\INDY3\DATA\DATA.BIN                los datos del juego (scripts, objetos, trajes, cajas, tabla de sonidos y perfil de games\indy3.cfg)
rem   SCUMM\V3\INDY3\DATA\OVLB.BIN OVLC.BIN OVLD.BIN   los tres overlays (paginas fisicas 49, 48 y 46: los lee el programa al arrancar)
rem   SCUMM\V3\INDY3\DATA\ROOMnn.GFX              las salas en HiRes 8x1 (88 ficheros)
rem   SCUMM\V3\INDY3\DATA\SND\SOUNDnnn.VGM        los sonidos
rem Las partidas (SAVEnn.SAV) y los puntos IQ (IQ.DAT) se guardan en la carpeta del juego (SCUMM\V3\INDY3\).
rem Ningun nombre de fichero de la SD lleva "_" (el ZX81 no tiene ese caracter).
rem
rem Uso:  compila_scumm.bat            monta y deja la carpeta lista en V3\SDOUT\ y la copia a la SD del emulador (%BASE%)
rem       compila_scumm.bat X:\        igual pero copia a esa raiz (p. ej. la tarjeta SD: X:\SCUMM\V3\...) en vez de a la del emulador
rem       compila_scumm.bat nocopia    solo monta y deja la carpeta V3\SDOUT\ lista (copiala tu a la SD)
rem Antes hay que tener los datos convertidos (una vez; ver V3\FASE2.md): V3\preview_hr\gfx\*.GFX (lfl3hr.py), V3\preview_hr\cost\ (costume3.py) y
rem V3\preview_hr\snd\*.VGM (sound3vgm.py). Este script regenera siempre DATA.BIN con pack_data3.py (el perfil games\indy3.cfg va dentro).
cd /d "%~dp0"
set BASE=\ClaudeCode\Eightyone2\EightyOne\SD81\SD81
set COPIA=1
if /i "%1"=="nocopia" set COPIA=0
if not "%1"=="" if /i not "%1"=="nocopia" set BASE=%~1
set GAMEDIR=..\Indy Last Crusade
set P=..\preview_hr
set B=test\prog
set OUT=..\SDOUT\SCUMM\V3
set D=%OUT%\INDY3\DATA
echo Juego: Indy3 EGA (datos de %P%)
if not exist %B% mkdir %B%
rem las tablas generadas (tables3.inc, ovbtab.inc, ovctab.inc, vars_v3.inc) y la fuente salen de las fuentes de Python
python -I ..\TOOLS\gen_vmtables3.py >nul || goto error
python -I ..\TOOLS\gen_font3.py >nul || goto error
rem montaje en dos pasos: el programa primero; los overlays se ensamblan contra sus simbolos (include "vm.sym": aqui vm.sym es el scumm.sym del programa)
if exist %B%\scumm.bin del %B%\scumm.bin
pasmo scumm.asm %B%\scumm.bin %B%\scumm.sym || goto error
if not exist %B%\scumm.bin goto error
copy /y %B%\scumm.sym %B%\vm.sym >nul || goto error
for %%o in (b c d) do (
  if exist %B%\ovl%%o.bin del %B%\ovl%%o.bin
  pasmo -I %B% ovl%%o.asm %B%\ovl%%o.bin %B%\ovl%%o.sym || goto error
  if not exist %B%\ovl%%o.bin goto error
)
rem los datos: DATA.BIN se regenera siempre para que un cambio en games\indy3.cfg o en los .LFL llegue a la SD
python -I ..\TOOLS\pack_data3.py "%GAMEDIR%" %P%\DATA.BIN --game ..\games\indy3.cfg --costumes %P% --sounds %P%\snd >nul || goto error
if exist ..\SDOUT rmdir /s /q ..\SDOUT
mkdir "%D%\SND" || goto error
copy /y %B%\scumm.bin "%OUT%\SCUMM.BIN" >nul || goto error
copy /y SCUMM.B81 "%OUT%\INDY3\INDY3.B81" >nul || goto error
copy /y %P%\DATA.BIN "%D%\DATA.BIN" >nul || goto error
copy /y %B%\ovlb.bin "%D%\OVLB.BIN" >nul || goto error
copy /y %B%\ovlc.bin "%D%\OVLC.BIN" >nul || goto error
copy /y %B%\ovld.bin "%D%\OVLD.BIN" >nul || goto error
copy /y %P%\gfx\*.GFX "%D%" >nul || goto error
if exist %P%\snd\*.VGM copy /y %P%\snd\*.VGM "%D%\SND" >nul
echo Carpeta lista: V3\SDOUT\SCUMM\V3  (copiala a la raiz de la SD)
if "%COPIA%"=="0" goto fin
if not exist "%BASE%" (
  echo *** No existe %BASE%: no se copia. La carpeta V3\SDOUT\SCUMM\V3 esta lista.
  goto fin
)
xcopy /e /i /y "%OUT%" "%BASE%\SCUMM\V3" >nul || goto error
echo Copiado a %BASE%\SCUMM\V3
:fin
echo Para jugar: entra en la carpeta SCUMM\V3\INDY3 y carga INDY3
exit /b 0

:error
echo *** ERROR: se para aqui ***
exit /b 1
