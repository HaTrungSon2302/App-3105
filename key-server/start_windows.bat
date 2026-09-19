@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Khong tim thay Python Launcher ^(py^). Hay cai Python 3.11/3.12 va tick "Add Python to PATH".
  pause
  exit /b 1
)

if not exist .venv (
  echo [1/4] Tao moi truong Python...
  py -m venv .venv
)

call .venv\Scripts\activate

echo [2/4] Cap nhat pip...
python -m pip install --upgrade pip

echo [3/4] Cai thu vien...
python -m pip install -r requirements.txt
if errorlevel 1 (
  echo [ERROR] Khong cai duoc thu vien.
  pause
  exit /b 1
)

if not exist .env copy .env.example .env >nul

echo [4/4] Khoi dong Tizi Mod Key Server...
echo Mo trinh duyet: http://127.0.0.1:8000/admin
python app.py
pause
