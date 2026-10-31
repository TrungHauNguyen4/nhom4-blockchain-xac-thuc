@echo off
title Start Frontend Server
echo ==============================================
echo      DANG KHOI DONG SERVER FRONTEND...
echo ==============================================
echo.
cd frontend
start "Frontend Server - Port 5173" cmd /k "echo Dang khoi dong Vite... && npm run dev"
echo [OK] Server da duoc bat trong mot cua so moi!
echo Ban co the truy cap vao: http://localhost:5173
echo.
pause
