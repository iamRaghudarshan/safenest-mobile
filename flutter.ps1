# Run Flutter without flutter.bat.
#
# WHY THIS EXISTS
# flutter.bat hangs indefinitely on this machine — every invocation sat at zero
# CPU until it was killed, and each one left the startup lock held, so the next
# one blocked behind it as well. The tool itself is fine: run the same snapshot
# through dart.exe and it answers immediately.
#
# The bat script's job is only to bootstrap (find the SDK, build the snapshot if
# it is missing, then hand over). That bootstrap is already done — the snapshot
# and every artifact stamp are present in bin\cache — so skipping straight to the
# handover loses nothing.
#
#   .\flutter.ps1 pub get
#   .\flutter.ps1 analyze
#   .\flutter.ps1 build apk
#
param([Parameter(ValueFromRemainingArguments = $true)] $Args)

$env:FLUTTER_ROOT = "D:\flutter"
$dart = "D:\flutter\bin\cache\dart-sdk\bin\dart.exe"
$snapshot = "D:\flutter\bin\cache\flutter_tools.snapshot"

# A previous run that was killed leaves this behind, and every later invocation
# waits on it for ever rather than reporting why.
$lock = "D:\flutter\bin\cache\lockfile"
if (Test-Path $lock) { Remove-Item -Force $lock -ErrorAction SilentlyContinue }

& $dart --disable-dart-dev $snapshot @Args
exit $LASTEXITCODE
