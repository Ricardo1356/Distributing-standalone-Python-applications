@echo off
rem --- Step 1: Run packaging script to build _temp\TestInstaller
python SetupFiles\package_app.py ^
  "C:\School\b\example_app" ^
  "TestInstaller" ^
  "main.py" ^
  "1.0.0" ^
  "3.12.0"

if %ERRORLEVEL% neq 0 (
    echo [build_installer] Packaging failed! Aborting.
    exit /b 1
)

rem --- Step 2: Compile the installer using Inno Setup
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

rem --- Step 3: Cleanup _temp folder (optional)
rmdir /s /q _temp

echo [build_installer] Done.
pause
