@echo off
REM Git merge driver: keep "theirs" (incoming) version. Args: %P %O %A %B -> copy %B to %A
REM /B = binary copy (required; default copy would treat as text and corrupt .uasset / LFS)
copy /B /Y "%~4" "%~3" >nul
exit /b 0
