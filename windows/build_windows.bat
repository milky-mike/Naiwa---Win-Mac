@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo Build Naiwa Windows exe (needs Python + pip)
echo ============================================
if exist ".venv\Scripts\python.exe" goto have_venv
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 -m venv .venv
) else (
  python -m venv .venv
)
if errorlevel 1 (
  echo Python 3.10+ is required. Install it first.
  if not defined CI pause
  exit /b 1
)
:have_venv
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r requirements.txt "pyinstaller>=6.5,<7"
if errorlevel 1 (
  echo Could not install requirements.
  if not defined CI pause
  exit /b 1
)
".venv\Scripts\python.exe" -m PyInstaller --noconfirm --clean --windowed --onedir ^
 --name NaiwaPetWindows --add-data "..\assets;assets" ^
 --icon "..\assets\AppIcon.ico" main.py
if errorlevel 1 (
  echo Build failed. Send the Terminal output for troubleshooting.
  if not defined CI pause
  exit /b 1
)
echo.
echo SUCCESS: %CD%\dist\NaiwaPetWindows\NaiwaPetWindows.exe
echo Keep all files inside the dist\NaiwaPetWindows folder together.
if not defined CI pause
