@echo off
title Atualizar catalogo - Pastas de Rede
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Atualizar-Indice.ps1"
echo.
pause
