@echo off
REM ============================================================
REM  Run SafeNest on a simulated phone, on this computer
REM ============================================================
REM
REM Boots a Pixel 6 running Android 15 and installs the app onto it from the
REM current source. This is the REAL Android app — the same code that ships —
REM not the browser preview, so the camera roll, backup, notifications and the
REM native player all behave as they do on a phone.
REM
REM No administrator rights needed. If the emulator refuses to start, run
REM "Enable Simulator (run once, as admin).bat" first.
REM
REM MEMORY. This computer also runs the SafeNest server, and its commit limit —
REM not its RAM — is what binds: a 2 GB emulator plus a Gradle daemon took it to
REM 61 GB of 65 and the live API stopped answering, which looked from the phone
REM like the server was down. The emulator is set to 1.5 GB now, and this script
REM stops the Gradle daemons once the build is done rather than leaving a
REM multi-gigabyte JVM resident for the rest of the day.
REM
REM   tool\Start Simulator.bat            boot the phone and run the app
REM   tool\Start Simulator.bat --boot     boot the phone only
REM
REM While it is running, in the terminal: r = hot reload, R = restart, q = quit.

setlocal
cd /d "%~dp0.."

set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "ADB=%SDK%\platform-tools\adb.exe"
set "EMU=%SDK%\emulator\emulator.exe"
set "FLUTTER=D:\flutter\bin\flutter.bat"

if not exist "%EMU%" (
  echo The Android SDK is not where it is expected:
  echo   %SDK%
  exit /b 1
)

REM --- is a device already up? -------------------------------------------
"%ADB%" devices | find "emulator-" >nul
if %errorlevel% equ 0 (
  echo A simulator is already running.
  goto :run
)

echo Starting the simulator...
start "" "%EMU%" -avd SafeNestPhone -gpu auto

echo Waiting for it to finish booting ^(first time takes a minute or two^)...
"%ADB%" wait-for-device
:bootloop
for /f "delims=" %%b in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
echo %BOOTED% | find "1" >nul
if %errorlevel% neq 0 (
  timeout /t 3 /nobreak >nul
  goto :bootloop
)
echo The phone is up.

:run
if "%~1"=="--boot" (
  echo.
  echo Simulator running. Install the app with:  tool\Start Simulator.bat
  exit /b 0
)

echo.
echo Building and installing SafeNest...
echo ^(r = hot reload, R = restart, q = quit^)
echo.
call "%FLUTTER%" run -d emulator

REM The build is over; the daemons are not needed and the server is.
echo.
echo Freeing the build daemons...
call "%~dp0..ndroid\gradlew.bat" --stop >nul 2>&1

endlocal
