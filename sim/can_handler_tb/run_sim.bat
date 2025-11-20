@echo off
REM CAN Handler Simulation Script for Windows
REM Usage: run_sim.bat

echo ========================================
echo CAN Handler Simulation
echo ========================================
echo.

cd /d %~dp0

echo Cleaning previous simulation...
if exist work (
    rmdir /s /q work
)
if exist transcript (
    del /q transcript
)

echo.
echo Starting ModelSim...
vsim -do cmd.do

echo.
echo Simulation finished!
pause
