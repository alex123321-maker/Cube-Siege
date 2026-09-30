@echo off
title Cube Siege
cd /d "%~dp0"
if not defined GODOT_BIN if exist ".godot_path" set /p GODOT_BIN=<".godot_path"
if defined GODOT_BIN (
    start "" "%GODOT_BIN%" --path "%~dp0."
    exit /b
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "" godot --path "%~dp0."
    exit /b
)
echo Set GODOT_BIN or create .godot_path with the path to Godot.
pause
