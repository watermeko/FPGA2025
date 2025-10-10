@echo off
REM ==============================================================================
REM Windows批处理脚本 - Upload Full Integration Simulation
REM ==============================================================================

echo ================================================
echo   Upload Full Integration Test
echo   Testing: Adapter + Packer + Arbiter
echo ================================================
echo.

REM 切换到脚本所在目录
cd /d %~dp0

REM 检查ModelSim是否可用
where vsim >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: ModelSim ^(vsim^) not found in PATH
    echo Please ensure ModelSim is installed and added to PATH
    echo.
    echo Typical ModelSim location:
    echo   C:\intelFPGA\20.1\modelsim_ase\win32aloem
    echo.
    pause
    exit /b 1
)

echo Starting ModelSim simulation...
echo.

REM 运行仿真（命令行模式）
vsim -c -do cmd.do

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Simulation failed!
    pause
    exit /b 1
)

echo.
echo ================================================
echo   Simulation complete!
echo ================================================
echo.
echo Generated files:
echo   - work\          ^(compiled library^)
echo   - transcript     ^(simulation log^)
echo   - upload_full_integration_tb.vcd ^(waveform^)
echo.
echo To view waveform in GUI mode:
echo   vsim -do cmd.do
echo.
pause
