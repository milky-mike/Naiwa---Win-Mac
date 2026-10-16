@echo off
setlocal
cd /d "%~dp0"
echo ================================
echo Naiwa Desktop Pet - Windows
ECHO ================================
if exist ".venv\Scripts\python.exe" goto have_venv
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 -m venv .venv
) else (
  python -m venv .venv
)
if errorlevel 1 (
  echo Python 3.10+ is required. Install Python from https://www.python.org/downloads/windows/
  pause
  exit /b 1
)
:have_venv
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r requirements.txt
if errorlevel 1 (
  echo Dependency install failed. Check your connection and try again.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" main.py
if errorlevel 1 pause
