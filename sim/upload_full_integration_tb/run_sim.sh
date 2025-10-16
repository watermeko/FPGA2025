#!/bin/bash
# ==============================================================================
# 快速启动脚本 - Upload Full Integration Simulation
# ==============================================================================

echo "================================================"
echo "  Upload Full Integration Test"
echo "  Testing: Adapter + Packer + Arbiter"
echo "================================================"

# 进入仿真目录
cd "$(dirname "$0")"

# 检查ModelSim是否可用
if ! command -v vsim &> /dev/null; then
    echo "ERROR: ModelSim (vsim) not found in PATH"
    echo "Please ensure ModelSim is installed and added to PATH"
    exit 1
fi

# 运行仿真
echo ""
echo "Starting ModelSim simulation..."
echo ""

vsim -do cmd.do -c

echo ""
echo "================================================"
echo "  Simulation complete!"
echo "================================================"
echo ""
echo "Generated files:"
echo "  - work/          (compiled library)"
echo "  - transcript     (simulation log)"
echo "  - upload_full_integration_tb.vcd (waveform)"
echo ""
echo "To view waveform in GUI mode:"
echo "  vsim -do cmd.do"
echo ""
