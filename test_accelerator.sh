#!/bin/bash
# Test script for ML Accelerator RTL verification

set -e  # Exit on error

echo "==================================="
echo "ML Accelerator RTL Verification"
echo "==================================="
echo ""

cd "$(dirname "$0")/verilog/dv/accelerator"

# Test 1: Systolic Array
echo "Test 1: Systolic Array (4x4 Matrix Multiply)"
echo "-------------------------------------------"
iverilog -g2012 -o tb_systolic_array tb_systolic_array.v \
    ../../rtl/accelerator/pe.v \
    ../../rtl/accelerator/systolic_array.v
./tb_systolic_array
echo ""

# Test 2: Vector ALU
echo "Test 2: Vector ALU (8-element SIMD operations)"
echo "----------------------------------------------"
iverilog -g2012 -o tb_vector_alu tb_vector_alu.v \
    ../../rtl/accelerator/vector_alu.v
./tb_vector_alu
echo ""

# Test 3: SFU
echo "Test 3: Special Function Unit (Softmax/LayerNorm)"
echo "-------------------------------------------------"
iverilog -g2012 -o tb_sfu tb_sfu.v \
    ../../rtl/accelerator/sfu.v
./tb_sfu
echo ""

echo "==================================="
echo "All tests completed!"
echo "==================================="
echo ""
echo "Check output above for PASS/FAIL status"
echo "VCD waveform files generated:"
echo "  - tb_systolic_array.vcd"
echo "  - tb_vector_alu.vcd"
echo "  - tb_sfu.vcd"
echo ""
echo "View waveforms with: gtkwave tb_systolic_array.vcd &"

