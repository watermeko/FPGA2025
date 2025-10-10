#!/bin/bash
# Linux/Mac shell script to run 3-channel upload integration simulation
# Tests UART + SPI + DSM handlers with complete upload pipeline

echo "================================================"
echo "3-Channel Upload Integration Simulation"
echo "================================================"
echo ""
echo "This simulation tests:"
echo "  - UART Handler with upload pipeline"
echo "  - SPI Handler with upload pipeline"
echo "  - DSM Handler with upload pipeline"
echo "  - Complete 3-channel arbitration"
echo ""
echo "================================================"

# Check if ModelSim is available
if ! command -v vsim &> /dev/null; then
    echo "ERROR: ModelSim not found in PATH"
    echo "Please install ModelSim or add it to your PATH"
    exit 1
fi

# Run ModelSim with the do script
echo "Starting ModelSim..."
vsim -do cmd.do

echo ""
echo "================================================"
echo "Simulation complete!"
echo "================================================"
