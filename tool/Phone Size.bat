@echo off
REM ============================================================
REM  Make the simulator the width of a real phone
REM ============================================================
REM
REM WHY THIS MATTERS MORE THAN IT SOUNDS. Every layout fault found in this app
REM has been a WIDTH fault — a nav bar too tight for six tabs, a card whose text
REM was squeezed to one character per line, six actions that would not fit a
REM row. What decides all of them is the width in DP, and dp is pixels divided
REM by density, not the pixel count people quote.
REM
REM The Pixel 6 the simulator was created from is 1080x2400 at 420 dpi, which is
REM 411dp. A Xiaomi with the SAME 1080x2400 runs at 440 dpi and is 393dp. So the
REM simulator was eighteen points WIDER than the phone this app is used on — it
REM would have shown every one of those faults as fine.
REM
REM   tool\Phone Size.bat            393dp — a Xiaomi, the usual phone here
REM   tool\Phone Size.bat iphone     390dp — what the designs are drawn at
REM   tool\Phone Size.bat small      320dp — the narrowest phone still in use
REM   tool\Phone Size.bat tablet     600dp — where the layout changes
REM   tool\Phone Size.bat reset      back to the device's own density

setlocal
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

if /i "%~1"=="iphone" ( set "D=443" & set "W=390" & goto :set )
if /i "%~1"=="small"  ( set "D=540" & set "W=320" & goto :set )
if /i "%~1"=="tablet" ( set "D=288" & set "W=600" & goto :set )
if /i "%~1"=="reset"  ( goto :reset )
set "D=440" & set "W=393"

:set
"%ADB%" shell wm density %D%
echo Simulator is now about %Wdp% wide ^(1080px at %D% dpi^).
echo The app restarts its layout on its own; no rebuild needed.
goto :done

:reset
"%ADB%" shell wm density reset
echo Back to the device's own density.

:done
endlocal
