@echo off
REM ============================================================
REM  ONE-TIME SETUP: let the Android emulator run on this machine
REM ============================================================
REM
REM Everything else is already installed — the Android SDK, the emulator, a
REM Pixel 6 running Android 15, and the JDK. The one remaining piece needs
REM Administrator rights, which is why it is a separate file you start yourself.
REM
REM WHAT AND WHY. An Android emulator runs x86_64 Android code, and that needs
REM hardware virtualisation. This machine has virtualisation enabled in its
REM firmware but no hypervisor driver installed, so the emulator refuses to
REM start with "x86_64 emulation currently requires hardware acceleration".
REM This installs Google's own driver (AEHD) to fix exactly that.
REM
REM Run this ONCE. After that, use "Start Simulator.bat", which needs no
REM administrator rights at all.
REM
REM If you would rather not install a driver, the alternative is to turn on the
REM Windows feature "Windows Hypervisor Platform" in
REM   Control Panel > Programs > Turn Windows features on or off
REM and reboot. Either one works; you do not need both.

REM --- re-launch elevated if we are not already ---------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Asking for Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

setlocal
set "DRV=%LOCALAPPDATA%\Android\Sdk\extras\google\Android_Emulator_Hypervisor_Driver"

if not exist "%DRV%\silent_install.bat" (
  echo.
  echo Could not find the driver at:
  echo   %DRV%
  echo.
  pause
  exit /b 1
)

echo Installing the Android Emulator hypervisor driver...
echo.
pushd "%DRV%"
call silent_install.bat
popd

echo.
sc query aehd | find "RUNNING" >nul
if %errorlevel% equ 0 (
  echo ==========================================
  echo  Done. The simulator can now start.
  echo  Next: run  tool\Start Simulator.bat
  echo ==========================================
) else (
  echo ==========================================
  echo  The driver did not come up.
  echo.
  echo  Most likely cause: virtualisation is off
  echo  in the BIOS, or Hyper-V is already using
  echo  it. Turning on the Windows feature
  echo  "Windows Hypervisor Platform" and
  echo  rebooting is the other way to do this.
  echo ==========================================
)
echo.
pause
endlocal
