@echo off
REM ============================================================
REM InstaVault - Inject Dylib into Instagram IPA (Windows)
REM ============================================================
REM Usage: inject.bat "path\to\Instagram.ipa"
REM ============================================================

setlocal enabledelayedexpansion

set INPUT=%~1
set DYLIB=obj\InstaVault.dylib
set WORKDIR=%TEMP%\InstaVault_%RANDOM%

if "%INPUT%"=="" (
    echo Usage: inject.bat "path\to\Instagram.ipa"
    echo.
    echo Example: inject.bat "D:\IPA APP\com.burbn.instagram_442.0.0_und3fined.ipa"
    exit /b 1
)

if not exist "%INPUT%" (
    echo ERROR: %INPUT% not found
    exit /b 1
)

if not exist "%DYLIB%" (
    echo ERROR: %DYLIB% not found
    echo Build the tweak first or download from GitHub Actions
    exit /b 1
)

echo === InstaVault IPA Injector ===
echo.

echo [1/5] Extracting IPA...
mkdir "%WORKDIR%" 2>nul
cd /d "%WORKDIR%"
powershell -Command "Expand-Archive -Path '%INPUT%' -DestinationPath '.' -Force"

for /d %%d in (Payload\*.app) do set APP=%%d
echo   App: %APP%

echo [2/5] Copying dylib...
mkdir "%APP%\Frameworks" 2>nul
copy /Y "%OLDPWD%\%DYLIB%" "%APP%\Frameworks\InstaVault.dylib"

echo [3/5] Injecting load command...
REM Requires optool in PATH or same folder
where optool >nul 2>&1
if %errorlevel%==0 (
    optool install -c load -p @executable_path/Frameworks/InstaVault.dylib -t "%APP%\Instagram"
) else (
    echo   optool not found. Install it:
    echo   brew install optool  OR  download from GitHub
    echo.
    echo   Manual injection:
    echo   optool install -c load -p @executable_path/Frameworks\InstaVault.dylib -t "%APP%\Instagram"
    pause
    exit /b 1
)

echo [4/5] Signing...
where ldid >nul 2>&1
if %errorlevel%==0 (
    ldid -S "%APP%\Instagram"
    echo   Ad-hoc signed
) else (
    echo   ldid not found, skipping signature
)

echo [5/5] Creating IPA...
cd /d "%WORKDIR%"
powershell -Command "Compress-Archive -Path 'Payload' -DestinationPath '%OLDPWD%\InstaVault.ipa' -Force"

cd /d "%OLDPWD%"
rmdir /s /q "%WORKDIR%" 2>nul

echo.
echo === Done! ===
echo Output: InstaVault.ipa
echo Install via Sideloadly
