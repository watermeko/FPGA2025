#!/bin/bash
# ==============================================================================
# 快速启动脚本 - Upload Full Integration V0 Simulation
# ==============================================================================

echo "================================================================"
echo "  Upload Full Integration Test - VERSION 0"
echo "  Testing: Adapter_0 + Packer_0 + Arbiter_0"
echo "  NOTE: This version has SPI > UART priority bug"
echo "================================================================"

cd "$(dirname "$0")"

if ! command -v vsim &> /dev/null; then
    echo "ERROR: ModelSim (vsim) not found in PATH"
    exit 1
fi

echo ""
echo "Starting ModelSim simulation..."
echo ""

vsim -do cmd.do -c

echo ""
echo "================================================================"
echo "  Simulation complete! (Version 0)"
echo "================================================================"
echo ""
echo "Key observations in this version:"
echo "  - SPI has higher priority than UART (Bug!)"
echo "  - Uses fifo_rd_en_ctrl workaround"
echo ""
echo "To view waveform in GUI mode:"
echo "  vsim -do cmd.do"
echo ""
