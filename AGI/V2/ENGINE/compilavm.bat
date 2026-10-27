@echo off
rem Ensambla el interprete AGI, convierte los datos del juego y lo deja todo en la SD del emulador (modo real: sin limite de ciclos ni resumenes):
rem   compilavm.bat SQ1
rem   SD81\SD81\AGI\V2\AGIVM.BIN                    el interprete, comun a todos los juegos
rem   SD81\SD81\AGI\V2\SQ1\AGIVM.B81                el BASIC que lo carga (la carpeta actual debe ser la del juego: lee de ella sus ficheros)
rem   SD81\SD81\AGI\V2\SQ1\LOG*.AGL, VIEW*.GFX, PIC*.GFX, *.BIN, VIEWS.HDR ...   los datos convertidos
rem Necesita los datos originales del juego en AGI\V2\SQ1 (no estan en git). Cambia BASE si la SD del emulador esta en otro sitio.
rem Los eventos (teclas) aun no se leen del teclado: EVENTS.BIN va vacio, asi que solo se ve lo que ocurre solo (introducciones).
set BASE=C:\ClaudeCode\Eightyone2\EightyOne\SD81\SD81
set G=%1
if "%G%"=="" set G=SQ1
cd /d "%~dp0"
if not exist ..\%G% (echo *** no hay datos de %G% en AGI\V2\%G% & goto error)
python -I ..\TOOLS\gen_agitab.py agivm.asm agiobj.asm agiin.asm agipic.asm agitab.inc || goto error
python -I ..\TOOLS\gen_sprtab.py sprtab.inc || goto error
pasmo agivm.asm agivm.bin agivm.sym || goto error
python -I ..\TOOLS\gen_font.py font6.inc || goto error
copy /y agivm.sym agires.inc >nul
pasmo agitxt.asm agitxt.bin agitxt.sym || goto error
set T=..\dump\%G%\log
python -I ..\TOOLS\agi2log.py ..\%G% %T% || goto error
python -I ..\TOOLS\agi2hr.py ..\%G% %T% || goto error
python -I ..\TOOLS\mkovl.py agitxt.bin %T%\TEXT.OVL || goto error
python -I ..\TOOLS\mkevents.py %T%\EVENTS.BIN 0 "" || goto error
set S=%BASE%\AGI\V2
set D=%S%\%G%
if not exist "%D%" mkdir "%D%"
copy /y agivm.bin "%S%\AGIVM.BIN" >nul || goto error
copy /y AGIVM.B81 "%D%\AGIVM.B81" >nul || goto error
copy /y %T%\* "%D%" >nul || goto error
echo OK: %S%\AGIVM.BIN y el juego en %D%  (LOAD "AGIVM.B81" desde esa carpeta)
exit /b 0

:error
echo *** ERROR ***
exit /b 1
