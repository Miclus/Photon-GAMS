@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo ========================================
echo   Galaxy GAMS Resolution Manager
echo ========================================
echo.
echo 1. Download high resolution version (backup low resolution image)
echo 2. Restore backup (delete downloaded image)
echo.
set /p choice=Please select an option (1 or 2):

if "%choice%"=="1" goto download
if "%choice%"=="2" goto restore
echo Invalid choice, exiting.
pause
exit /b

:download
echo.
echo Downloading high resolution version...
if exist "shaders\image\galaxy_gams.png" (
    echo Low res image found, backing up...
    ren "shaders\image\galaxy_gams.png" "galaxy_gams.png.backup"
    echo Backup completed: galaxy_gams.png.backup
) else (
    echo Low res image not found
)

echo.
echo Downloading new image from GitHub...
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/OUdefie17/Photon-GAMS/main/shaders/image/galaxy_gams.png' -OutFile 'shaders\image\galaxy_gams.png'"

if exist "shaders\image\galaxy_gams.png" (
    echo.
    echo [✓] Download successful!
    echo.
    pause
    exit /b 0
) else (
    echo.
    echo [✗] Download failed, please check your internet connection
    echo.
    if exist "shaders\image\galaxy_gams.png.backup" (
        echo Restoring backup...
        ren "shaders\image\galaxy_gams.png.backup" "galaxy_gams.png"
    )
    pause
    exit /b 1
)

:restore
echo.
echo Restoring backup...
if exist "shaders\image\galaxy_gams.png" (
    set "size="
    for %%A in ("shaders\image\galaxy_gams.png") do set "size=%%~zA"
    if defined size if !size! lss 20971520 (
        echo [✓] Current image is already low resolution
        echo.
        pause
        exit /b 0
    )
    echo Deleting downloaded image...
    del /f /q "shaders\image\galaxy_gams.png"
    echo Deletion completed
)

if exist "shaders\image\galaxy_gams.png.backup" (
    echo Restoring backup file...
    ren "shaders\image\galaxy_gams.png.backup" "galaxy_gams.png"
    echo [✓] Restore completed!
) else (
    echo [✗] Backup file not found
)
echo.
pause
exit /b
