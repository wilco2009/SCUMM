@echo off
rem Ensambla ROOMVIEW y lo copia, con los ROOMnn.GFX, a la SD del emulador.
cd /d "%~dp0"
set BASE=\ClaudeCode\Eightyone2\EightyOne\SD81
pasmo roomview.asm roomview.bin roomview.sym || goto error
if not exist "%BASE%\SD81\TOOLS\ROOMVIEW" mkdir "%BASE%\SD81\TOOLS\ROOMVIEW"
if not exist "%BASE%\SCUMM" mkdir "%BASE%\SCUMM"
copy /y roomview.bin "%BASE%\SD81\TOOLS\ROOMVIEW" >nul || goto error
copy /y ROOMVIEW.B81 "%BASE%\SD81\TOOLS\ROOMVIEW" >nul || goto error
copy /y ..\preview\gfx\*.GFX "%BASE%\SCUMM" >nul || goto error
echo OK: ROOMVIEW copiado en %BASE%\SD81\TOOLS\ROOMVIEW y los .GFX en %BASE%\SCUMM
exit /b 0

:error
echo *** ERROR: se para aqui ***
exit /b 1
