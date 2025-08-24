@echo off
setlocal

echo *** Erst flutter build web --base-href "/boat routes/"    ausführen ***
pause >nul

echo *** Baue Flutter Web App...
echo Hello world
if %errorlevel% neq 0 (
    echo [FEHLER] Flutter Build fehlgeschlagen.
    goto :wait
)

echo *** Entferne alten docs-Ordner (falls vorhanden)...
rmdir /S /Q docs 2>nul

echo *** Erstelle neuen docs-Ordner...
mkdir docs

echo *** Kopiere Web-Build nach docs/ ...
xcopy /E /I /Y build\web\* docs\
if %errorlevel% neq 0 (
    echo [FEHLER] Kopieren nach docs fehlgeschlagen.
    goto :wait
)

echo.
set /p msg=Commit-Nachricht eingeben: 
if "%msg%"=="" (
    echo Commit-Nachricht darf nicht leer sein.
    goto :wait
)

echo *** Führe Git-Befehle aus...
git add .
git commit -m "%msg%"
git push origin main

echo.
echo *** Alles erledigt. Seite sollte bald unter https://steffenkastian.github.io/boat_routes/ erreichbar sein.

:wait
echo.
echo *** Drücke eine Taste, um das Fenster zu schließen...
pause >nul