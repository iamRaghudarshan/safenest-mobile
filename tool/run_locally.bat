@echo off
REM Run the SafeNest phone app on this computer, in a browser.
REM
REM Neither phone platform can be built here — no Xcode, no Android SDK — so
REM until this existed the only way to look at a change was to tag a release,
REM wait for CI, and install an APK. A blank screen then costs half an hour to
REM see. This takes about a minute.
REM
REM   tool\run_locally.bat            rebuild and serve on 5601
REM   tool\run_locally.bat --serve    skip the rebuild, just serve
REM
REM What is real: everything the server answers — sign in, photos, documents,
REM navigation, layout, both skins. What is not: the camera roll, backing up
REM and notifications, none of which a browser has.

setlocal
cd /d "%~dp0.."

if /i "%~1"=="--serve" goto serve

echo Building the app for the browser...
call D:\flutter\bin\flutter.bat build web -t lib/web_main.dart --output build/webapp --no-tree-shake-icons
if errorlevel 1 (
  echo.
  echo Build failed — not starting the server.
  exit /b 1
)

:serve
echo.
echo Opening http://127.0.0.1:5601/
echo Sign in with the address:  127.0.0.1:5601
echo Press Ctrl+C here to stop.
echo.
start "" http://127.0.0.1:5601/
python tool\run_locally.py 5601
endlocal
