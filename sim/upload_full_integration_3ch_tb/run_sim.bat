@echo off
REM Windows batch script to run 3-channel upload integration simulation
REM Tests UART + SPI + DSM handlers with complete upload pipeline

echo ================================================
echo 3-Channel Upload Integration Simulation
echo ================================================
echo.
echo This simulation tests:
echo   - UART Handler with upload pipeline
echo   - SPI Handler with upload pipeline
echo   - DSM Handler with upload pipeline
echo   - Complete 3-channel arbitration
echo.
echo ================================================

REM Check if ModelSim is available
where vsim >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: ModelSim not found in PATH
    echo Please install ModelSim or add it to your PATH
    pause
    exit /b 1
)

REM Run ModelSim with the do script
echo Starting ModelSim...
vsim -do cmd.do

echo.
echo ================================================
echo Simulation complete!
echo ================================================
pause
