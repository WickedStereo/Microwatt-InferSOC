# Microwatt-Infer SoC Architecture

## Overview

The Microwatt-Infer SoC is a fully open-source System-on-Chip designed for efficient small-scale language model inference at the edge. It combines a proven 64-bit POWER ISA CPU (Microwatt) with a custom ML accelerator, targeting the SKY130 PDK.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Microwatt-Infer SoC                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────┐         Wishbone Interconnect              │
│  │            │         ┌──────────────────┐               │
│  │  Microwatt ├─────────┤                  │               │
│  │   CPU      │ Insn    │                  │               │
│  │  (64-bit)  ├─────────┤   Arbiter &      │               │
│  │            │ Data    │   Crossbar       │               │
│  └────────────┘         │                  │               │
│                         └────┬─────┬───┬───┘               │
│                              │     │   │                    │
│                    ┌─────────┴┐ ┌──┴───▼──┐                │
│                    │          │ │         │                │
│  ┌─────────────┐   │  Code    │ │  Data   │   ┌────────┐  │
│  │             │   │  SRAM    │ │  SRAM   │   │ UART   │  │
│  │ ML Accel.   │   │  (8KB)   │ │  (8KB)  │   │        │  │
│  │             │   │          │ │         │   └────────┘  │
│  │ ┌─────────┐ │   └──────────┘ └─────────┘               │
│  │ │Systolic │ │                                           │
│  │ │ Array   │ │   Memory Map:                             │
│  │ │ (4x4)   │ │   0x0000_0000 - Code SRAM                 │
│  │ └─────────┘ │   0x0000_2000 - Data SRAM                 │
│  │             │   0x8000_0000 - ML Accelerator            │
│  │ ┌─────────┐ │   0x8000_1000 - UART                      │
│  │ │ Vector  │ │                                           │
│  │ │  ALU    │ │                                           │
│  │ └─────────┘ │                                           │
│  │             │                                           │
│  │ ┌─────────┐ │                                           │
│  │ │   SFU   │ │                                           │
│  │ │Softmax/ │ │                                           │
│  │ │LayerNorm│ │                                           │
│  │ └─────────┘ │                                           │
│  └─────────────┘                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Microwatt CPU Core

- **Architecture**: 64-bit POWER ISA (OpenPOWER)
- **Pipeline**: Multi-stage with branch prediction
- **ISA**: PowerPC subset optimized for embedded use
- **Bus Interface**: Dual Wishbone (instruction fetch + data access)
- **Role**: Controls accelerator, manages I/O, executes control flow

### 2. ML Accelerator

The ML accelerator consists of three main units:

#### 2.1 Systolic Array
- **Size**: 4x4 processing elements
- **Data Type**: INT8 inputs, INT32 accumulation
- **Architecture**: Weight-stationary dataflow
- **Throughput**: 16 MAC operations per cycle
- **Performance**: 3.2 GOPS @ 50MHz
- **Use Case**: Matrix multiplication for attention and FC layers

#### 2.2 Vector ALU
- **Width**: 64-bit SIMD (8 x INT8 elements)
- **Operations**: ADD, SUB, MUL, RELU, MAX, MIN, SCALE, CLIP
- **Pipeline**: 2 stages
- **Use Case**: Element-wise operations, activations

#### 2.3 Special Function Unit (SFU)
- **Functions**: Softmax, Layer Normalization
- **Method**: LUT-based approximation + iterative refinement
- **Precision**: INT8 input/output with INT32 internal precision
- **Use Case**: Attention softmax, layer normalization

### 3. Memory Subsystem

- **Code SRAM**: 8KB @ 0x0000_0000
  - Stores firmware and small constants
  
- **Data SRAM**: 8KB @ 0x0000_2000
  - Weight storage (4KB)
  - Activation storage (4KB)
  - Tiling required for larger models

- **SRAM Macro**: sky130_sram_2kbyte_1rw1r_32x512_8
  - 2KB per macro, 32-bit wide
  - Dual-port: 1 read/write + 1 read-only

### 4. Wishbone Interconnect

- **Masters**: 
  - Microwatt instruction fetch (priority 0)
  - Microwatt data access (priority 1)

- **Slaves**:
  - Code SRAM controller
  - Data SRAM controller
  - ML Accelerator CSRs
  - UART peripheral

- **Arbitration**: Priority-based (instruction fetch has priority)
- **Protocol**: Wishbone B3 pipelined

### 5. UART Peripheral

- **Standard**: 16550 compatible
- **Baud Rate**: 115200 (configurable)
- **Use**: Firmware download, debug output, demo I/O

## Memory Map

| Address Range | Size | Component | Description |
|---------------|------|-----------|-------------|
| 0x0000_0000 - 0x0000_1FFF | 8KB | Code SRAM | Firmware code and constants |
| 0x0000_2000 - 0x0000_2FFF | 4KB | Weight SRAM | ML model weights |
| 0x0000_3000 - 0x0000_3FFF | 4KB | Activation SRAM | Intermediate activations |
| 0x8000_0000 - 0x8000_0FFF | 4KB | ML Accelerator | CSRs and data buffers |
| 0x8000_1000 - 0x8000_1FFF | 4KB | UART | 16550 registers |

## ML Accelerator Register Map

| Offset | Name | Description |
|--------|------|-------------|
| 0x000 | CTRL | Control/status register |
| 0x004 | CONFIG | Configuration register |
| 0x010-0x04F | SYS_DATA | Systolic array input data (16 words) |
| 0x050-0x08F | SYS_WEIGHT | Systolic array weights (16 words) |
| 0x090-0x0CF | SYS_OUTPUT | Systolic array results (16 words) |
| 0x100-0x13F | VALU_A | Vector ALU input A (16 words) |
| 0x140-0x17F | VALU_B | Vector ALU input B (16 words) |
| 0x180-0x1BF | VALU_OUT | Vector ALU output (16 words) |
| 0x200-0x23F | SFU_IN | SFU input (16 words) |
| 0x240-0x27F | SFU_OUT | SFU output (16 words) |

## Data Flow

### Typical Inference Flow

1. **Weight Loading**: CPU loads quantized weights to weight SRAM (0x2000-0x2FFF)
2. **Input Processing**: Input data arrives via UART, stored in activation SRAM
3. **Layer Execution**:
   - CPU programs accelerator CSRs
   - Systolic array performs MatMul
   - Vector ALU applies activation function (ReLU, etc.)
   - SFU computes Softmax/LayerNorm as needed
4. **Tiling**: For large layers, data is tiled through SRAM
5. **Output**: Final results sent via UART

## Performance Targets

- **Clock Frequency**: 25-50 MHz (conservative for SKY130)
- **MatMul Throughput**: 3.2 GOPS @ 50MHz
- **Inference Rate**: 5-10 inferences/sec for tiny model
- **Power**: <10mW @ 1.8V (estimated)
- **Area**: ~6-8 mm² total

## Design Considerations

### Area Budget
- Microwatt core: ~2850 x 3000 µm
- ML accelerator: ~1000 x 1000 µm
- SRAM (16KB): ~800 x 1200 µm
- Interconnect/peripherals: ~500 x 500 µm

### Timing Constraints
- Critical paths expected in:
  - Microwatt execute stage
  - Systolic array accumulation
  - SFU iterative operations
- Conservative 40ns clock period (25 MHz) for initial timing closure

### Power Management
- Clock gating for idle units
- Power domains: VCCD1 (1.8V digital)
- No dynamic voltage/frequency scaling in initial version

## Future Enhancements

1. **Larger Systolic Array**: Scale to 8x8 if area permits
2. **More SRAM**: Integrate additional memory for larger models
3. **Optimizations**: Better tiling strategies, compression
4. **Advanced Features**: Sparsity support, quantization-aware ops

