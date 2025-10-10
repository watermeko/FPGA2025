@echo off
REM ==============================================================================
REM Windows批处理脚本 - Upload Full Integration V0 Simulation
REM ==============================================================================

echo ================================================================
echo   Upload Full Integration Test - VERSION 0
echo   Testing: Adapter_0 + Packer_0 + Arbiter_0
echo   NOTE: This version has SPI ^> UART priority bug
echo ================================================================
echo.

cd /d %~dp0

where vsim >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: ModelSim ^(vsim^) not found in PATH
    pause
    exit /b 1
)

echo Starting ModelSim simulation...
echo.

vsim -c -do cmd.do

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Simulation failed!
    pause
    exit /b 1
)

echo.
echo ================================================================
echo   Simulation complete! ^(Version 0^)
echo ================================================================
echo.
echo Generated files:
echo   - work\          ^(compiled library^)
echo   - transcript     ^(simulation log^)
echo   - upload_full_integration_v0_tb.vcd ^(waveform^)
echo.
echo Key observations in this version:
echo   - SPI has higher priority than UART ^(Bug!^)
echo   - Uses fifo_rd_en_ctrl workaround
echo.
echo To view waveform in GUI mode:
echo   vsim -do cmd.do
echo.
pause
