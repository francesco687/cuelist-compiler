@echo off
echo Cuelist Compiler OSC Proxy - starting...
cd /d "%~dp0"
if not exist node_modules (
    echo Installing dependencies ^(one-time, ~5 seconds^)...
    call npm install
    if errorlevel 1 (
        echo.
        echo npm install failed. Check that Node.js is installed and try again.
        pause
        exit /b 1
    )
)
echo.
node ws2osc.js
echo.
echo Bridge stopped. Press any key to close.
pause >nul