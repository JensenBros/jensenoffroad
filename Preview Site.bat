@echo off
REM Double-click this to preview the website locally (videos will play on-page).
REM It starts a small local web server and opens your browser. Close the window to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
