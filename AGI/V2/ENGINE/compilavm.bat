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
for %%A in (agivm.bin) do if %%~zA GTR 11008 (echo agivm.bin pasa de VARS: %%~zA bytes, maximo 11008 & goto error)
python -I ..\TOOLS\gen_font.py font6.inc || goto error
copy /y agivm.sym agires.inc >nul
pasmo agia.asm agia.bin agia.sym || goto error
pasmo agib.asm agib.bin agib.sym || goto error
pasmo agic.asm agic.bin agic.sym || goto error
pasmo agid.asm agid.bin agid.sym || goto error
pasmo agie.asm agie.bin agie.sym || goto error
set T=..\dump\%G%\log
python -I ..\TOOLS\agi2log.py ..\%G% %T% || goto error
python -I ..\TOOLS\agi2hr.py ..\%G% %T% || goto error
python -I ..\TOOLS\agi2spr.py ..\%G% %T% || goto error
python -I ..\TOOLS\agi2snd.py ..\%G% %T% || goto error
python -I ..\TOOLS\mkovl.py agia.bin %T%\DATA\OVERA.OVL || goto error
python -I ..\TOOLS\mkovl.py agib.bin %T%\DATA\OVERB.OVL || goto error
python -I ..\TOOLS\mkovl.py agic.bin %T%\DATA\OVERC.OVL || goto error
python -I ..\TOOLS\mkovl.py agid.bin %T%\DATA\OVERD.OVL || goto error
python -I ..\TOOLS\mkovl.py agie.bin %T%\DATA\OVERE.OVL || goto error
python -I ..\TOOLS\mkevents.py %T%\DATA\EVENTS.BIN 0 "" || goto error
set S=%BASE%\AGI\V2
set D=%S%\%G%
if not exist "%D%" mkdir "%D%"
if not exist "%D%\SAV" mkdir "%D%\SAV"
copy /y agivm.bin "%S%\AGIVM.BIN" >nul || goto error
copy /y AGIVM.B81 "%D%\AGIVM.B81" >nul || goto error
rem los datos van por carpetas (LOG, PIC, SPR, SND, VIEW, DATA); en la del juego solo queda el BASIC y se quitan los ficheros sueltos de versiones anteriores
for %%e in (AGL MSG GFX SPR VGM BIN HDR OVL) do del /q "%D%\*.%%e" 2>nul
xcopy /e /i /y /q "%T%\*" "%D%\" >nul || goto error
echo OK: %S%\AGIVM.BIN y el juego en %D%  (LOAD "AGIVM.B81" desde esa carpeta)
exit /b 0

:error
echo *** ERROR ***
exit /b 1
