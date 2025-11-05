# Verification Plan

This document describes the verification strategy for the Microwatt-Infer SoC.

## Overview

Verification is performed at multiple levels:
1. **Unit Level**: Individual components (PE, systolic array, vector ALU, SFU)
2. **Integration Level**: Complete accelerator with Wishbone interface
3. **System Level**: Full SoC with CPU, memory, and peripherals
4. **Gate Level**: Post-synthesis and post-layout verification

## Verification Hierarchy

```
System Level (microwatt_soc)
├── Integration Level (ml_accelerator)
│   ├── Unit Level (systolic_array)
│   │   └── Component (pe)
│   ├── Unit Level (vector_alu)
│   └── Unit Level (sfu)
├── Integration Level (wb_interconnect)
├── Integration Level (sram_controller)
└── Integration Level (uart_wb_wrapper)
```

## Unit Testbenches

### 1. Processing Element (PE)

**File**: `verilog/dv/accelerator/tb_pe.v`

**Test Cases**:
- Multiply-accumulate operation
- Data forwarding (activation left-to-right, weight top-to-bottom)
- Pipeline behavior
- Reset and enable signals

**Success Criteria**:
- Correct MAC computation
- Proper data propagation timing
- No combinational loops

### 2. Systolic Array

**File**: `verilog/dv/accelerator/tb_systolic_array.v`

**Test Cases**:
1. Identity matrix multiplication
2. Simple 4x4 matrix multiplication
3. Weight loading sequence
4. Activation streaming
5. Result accumulation

**Success Criteria**:
- Mathematically correct results
- Proper weight stationary behavior
- Timing closure in synthesis

**Example Test**:
```verilog
// Test: 4x4 identity matrix * input
// Expected: Output = Input * 1 = Input
```

### 3. Vector ALU

**File**: `verilog/dv/accelerator/tb_vector_alu.v`

**Test Cases**:
- ADD operation on 8-element vectors
- SUB operation with negative results
- MUL with saturation
- RELU on mixed positive/negative
- MAX/MIN operations
- SCALE with fixed-point shift
- CLIP to specified range

**Success Criteria**:
- All operations produce correct results
- Saturation works properly
- Pipeline latency is consistent

### 4. Special Function Unit (SFU)

**File**: `verilog/dv/accelerator/tb_sfu.v`

**Test Cases**:
- Softmax on uniform distribution
- Softmax on varied inputs
- Layer normalization on zero-mean data
- Layer normalization on skewed data
- Vector lengths from 1 to 16
- Edge cases (all zeros, all same value)

**Success Criteria**:
- Softmax output sums to ~1 (within quantization error)
- LayerNorm produces zero mean
- No numerical instability

**Accuracy Requirements**:
- Softmax: Within 5% of floating-point reference
- LayerNorm: Within 10% of floating-point reference
- No overflow/underflow

## Integration Testbenches

### 5. ML Accelerator

**File**: `verilog/dv/accelerator/tb_ml_accelerator.v`

**Test Cases**:
1. Wishbone CSR read/write
2. Matrix multiplication through Wishbone
3. Vector operations through Wishbone
4. SFU operations through Wishbone
5. Interrupt generation
6. Concurrent access attempts
7. Error conditions (invalid addresses)

**Success Criteria**:
- Correct Wishbone protocol handshake
- CSR programming takes effect
- Data buffers work correctly
- Interrupts assert at completion
- No bus conflicts

### 6. Wishbone Interconnect

**File**: `verilog/dv/interconnect/tb_wb_interconnect.v`

**Test Cases**:
1. Single master, single slave
2. Multiple masters with arbitration
3. Address decoding to each slave
4. Priority enforcement (instruction > data)
5. Simultaneous requests
6. Invalid address handling

**Success Criteria**:
- Correct routing to slaves
- Arbitration follows priority
- No data corruption
- Proper stall/ack signaling

### 7. SRAM Controller

**File**: `verilog/dv/memory/tb_sram_controller.v`

**Test Cases**:
1. Single word read/write
2. Burst read/write
3. Different byte enables (wmask)
4. Multiple SRAM selection
5. Read-after-write hazards
6. Timing compliance with SRAM macro

**Success Criteria**:
- Data integrity on read/write
- Proper SRAM control signals
- Correct address decoding
- Meet SRAM timing requirements

## System Testbench

### 8. Microwatt SoC

**File**: `verilog/dv/microwatt_soc/tb_microwatt_soc.v`

**Test Scenarios**:

1. **Boot and Initialization**
   - Reset sequence
   - CPU fetches from code SRAM
   - Peripherals initialize

2. **Memory Access**
   - CPU reads/writes code SRAM
   - CPU reads/writes data SRAM
   - Proper instruction fetch vs data access

3. **Accelerator Access**
   - CPU programs accelerator CSRs
   - CPU loads data to accelerator
   - CPU reads results from accelerator
   - Interrupt handling

4. **UART Communication**
   - Transmit test characters
   - Receive test characters
   - Baud rate timing

5. **Full Inference**
   - Load weights to SRAM
   - Execute matrix multiplication
   - Apply activation function
   - Compute softmax
   - Read final results

**Success Criteria**:
- Firmware executes without errors
- All accelerator tests pass
- UART communication works
- No bus conflicts or deadlocks
- Interrupts handled correctly

**Note**: Full functional testing requires firmware. The testbench performs structural connectivity tests.

## Golden Reference Models

For quantitative verification, we use golden reference models:

### Python Reference Implementation

```python
# systolic_array_ref.py
import numpy as np

def systolic_matmul_ref(A, B):
    """Reference matrix multiplication in INT8"""
    assert A.dtype == np.int8
    assert B.dtype == np.int8
    
    # Compute in INT32 to match hardware
    C = np.matmul(A.astype(np.int32), B.astype(np.int32))
    return C

def softmax_ref(x):
    """Reference softmax implementation"""
    x_max = np.max(x)
    exp_x = np.exp(x - x_max)  # Numerical stability
    return exp_x / np.sum(exp_x)
```

### Verification Flow

1. Generate test vectors with Python
2. Run HDL simulation
3. Compare HDL output with Python output
4. Assert match within tolerance

## Coverage Metrics

### Code Coverage
- **Target**: >90% line coverage
- **Tool**: Verilator `--coverage` or VCS

### Functional Coverage
- All CSR registers accessed
- All accelerator operations executed
- All address ranges accessed
- All interrupt sources triggered

### Corner Cases
- Maximum/minimum data values
- Zero matrices
- Identity matrices
- Full SRAM utilization
- Back-to-back operations

## Gate-Level Verification

### Post-Synthesis

**Files**: `verilog/gl/ml_accelerator.v`, etc.

**Tests**:
- Re-run all unit tests with gate-level netlist
- Verify timing with SDF annotation
- Check for X propagation

**Success Criteria**:
- All tests pass with gate-level netlist
- No timing violations
- No X states in outputs

### Post-Layout

**Files**: `verilog/gl/*.v` + SPEF

**Tests**:
- Re-run system tests with full parasitic extraction
- Verify setup/hold timing
- Check power consumption

**Success Criteria**:
- All functional tests pass
- Timing closure at all corners (slow, typical, fast)
- Power within budget

## Regression Testing

### Continuous Integration

**Trigger**: On every commit to main branch

**Tests**:
1. Lint check (Verilator --lint-only)
2. Unit testbenches (all)
3. Integration testbenches
4. Synthesis check (no errors)

**Tools**:
- GitHub Actions or GitLab CI
- Verilator for simulation
- Yosys for synthesis check

### Full Regression

**Trigger**: Before tape-out

**Tests**:
- All unit + integration tests
- System tests with firmware
- Gate-level tests (post-synth, post-layout)
- Corner analysis (PVT variations)
- Monte Carlo simulation

**Duration**: 1-2 days

## Known Limitations

1. **Testbench Coverage**: Not all corner cases covered due to time constraints
2. **Firmware Tests**: Limited by SRAM size (8KB code + 8KB data)
3. **Timing**: Conservative clock period; optimization possible
4. **Power**: No power verification performed (estimate only)

## Future Verification Work

1. **Formal Verification**: Property checking for bus protocols
2. **UVM Testbench**: Constrained-random testing for accelerator
3. **System-Level Tests**: Actual ML model inference
4. **Hardware Test**: Validate on silicon (post-fabrication)

## Test Execution

### Running All Tests

```bash
cd verilog/dv

# Unit tests
make test-accelerator

# Integration tests  
make test-interconnect

# System test
make test-soc

# All tests
make test-all
```

### Viewing Results

```bash
# Check for PASS/FAIL in logs
grep -r "PASS\|FAIL" *.log

# View waveforms
gtkwave tb_systolic_array.vcd &
```

## Verification Checklist

Before tape-out:

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] System tests pass with demo firmware
- [ ] Gate-level simulation clean
- [ ] No DRC violations
- [ ] No LVS violations
- [ ] Timing closure at all corners
- [ ] Power analysis complete
- [ ] Code coverage >90%
- [ ] All known bugs resolved or documented

