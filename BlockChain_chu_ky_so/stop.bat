@echo off
title Stop Frontend Server
echo ==============================================
echo      DANG TAT SERVER FRONTEND...
echo ==============================================
echo.

set PID=
FOR /F "tokens=5" %%T IN ('netstat -a -n -o ^| find "LISTENING" ^| find ":5173"') DO (
    set PID=%%T
)

if defined PID (
    echo Dang dung tien trinh Node.js voi PID: %PID% (Port 5173)
    taskkill /F /PID %PID%
    echo [OK] Da tat thanh cong!
) else (
    echo [THONG BAO] Khong tim thay server nao dang chay tren Port 5173.
)
echo.
pause
