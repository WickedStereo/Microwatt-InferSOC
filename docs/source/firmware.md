# Firmware Development Guide

This guide covers firmware development for the Microwatt-Infer SoC.

## Overview

The firmware provides:
1. ML accelerator driver library
2. Demo application showcasing accelerator features
3. Build system for PowerPC cross-compilation

## Prerequisites

### Toolchain Installation

The Microwatt CPU uses the 64-bit PowerPC ISA (little-endian). You need a cross-compiler:

#### Ubuntu/Debian:
```bash
sudo apt-get install gcc-powerpc64le-linux-gnu \
                     binutils-powerpc64le-linux-gnu
```

#### From Source (Bootlin):
```bash
wget https://toolchains.bootlin.com/downloads/releases/toolchains/powerpc64le-power8/tarballs/powerpc64le-power8--glibc--stable-2022.08-1.tar.bz2
tar xf powerpc64le-power8--glibc--stable-2022.08-1.tar.bz2
export PATH=$PWD/powerpc64le-power8--glibc--stable-2022.08-1/bin:$PATH
```

## Directory Structure

```
firmware/
├── ml_accel.h      # Accelerator driver header
├── ml_accel.c      # Accelerator driver implementation
├── demo.c          # Demo application
├── linker.ld       # Linker script (memory layout)
├── Makefile        # Build system
└── README.md       # This file
```

## ML Accelerator Driver API

### Initialization

```c
#include "ml_accel.h"

void ml_accel_init(void);
```

Initializes the ML accelerator, resets control registers.

### Matrix Multiplication

```c
void ml_accel_matmul(const int8_t *a, const int8_t *b, int32_t *c);
```

Performs 4x4 matrix multiplication using the systolic array:
- **Input A**: 16 INT8 elements (row-major)
- **Input B**: 16 INT8 elements (row-major)
- **Output C**: 16 INT32 elements (row-major)

**Example**:
```c
int8_t matrix_a[16] = {1, 2, 3, 4, ...};
int8_t matrix_b[16] = {1, 0, 0, 0, ...};
int32_t result[16];

ml_accel_matmul(matrix_a, matrix_b, result);
```

### Vector Operations

```c
void ml_accel_vector_op(uint8_t op, const int8_t *a, const int8_t *b, 
                        int8_t *out, int8_t scalar);
```

Performs element-wise operations on 8-element vectors:

**Operations**:
- `VALU_OP_ADD` - Element-wise addition
- `VALU_OP_SUB` - Element-wise subtraction
- `VALU_OP_MUL` - Element-wise multiplication
- `VALU_OP_RELU` - ReLU activation: max(x, 0)
- `VALU_OP_MAX` - Element-wise maximum
- `VALU_OP_MIN` - Element-wise minimum
- `VALU_OP_SCALE` - Multiply by scalar with fixed-point shift
- `VALU_OP_CLIP` - Clamp to range [-scalar, scalar]

**Example**:
```c
int8_t vec_a[8] = {10, -5, 20, -10, 30, -15, 40, -20};
int8_t vec_b[8] = {1, 1, 1, 1, 1, 1, 1, 1};
int8_t result[8];

// ReLU: max(vec_a, 0)
ml_accel_vector_op(VALU_OP_RELU, vec_a, vec_b, result, 0);
// result = {10, 0, 20, 0, 30, 0, 40, 0}
```

### Softmax

```c
void ml_accel_softmax(const int8_t *in, int8_t *out, uint8_t len);
```

Computes softmax over a vector (up to 16 elements):
- Uses LUT-based exp() approximation
- Numerically stable (subtracts max before exp)

**Example**:
```c
int8_t logits[8] = {10, 20, 30, 40, 50, 60, 70, 80};
int8_t probabilities[8];

ml_accel_softmax(logits, probabilities, 8);
```

### Layer Normalization

```c
void ml_accel_layernorm(const int8_t *in, int8_t *out, uint8_t len);
```

Computes layer normalization: `(x - mean) / sqrt(variance + epsilon)`

**Example**:
```c
int8_t activations[8] = {10, 20, 30, 40, 50, 60, 70, 80};
int8_t normalized[8];

ml_accel_layernorm(activations, normalized, 8);
```

### Interrupt Control

```c
void ml_accel_irq_enable(int enable);
int ml_accel_wait_done(uint32_t done_bit);
```

Enable/disable accelerator interrupts and wait for completion.

## Memory Map

Firmware must respect the SoC memory layout:

| Address | Size | Region | Usage |
|---------|------|--------|-------|
| 0x0000_0000 | 8KB | Code RAM | Firmware .text, .rodata |
| 0x0000_2000 | 8KB | Data RAM | .data, .bss, stack, heap |
| 0x8000_0000 | 4KB | ML Accelerator | Memory-mapped registers |
| 0x8000_1000 | 4KB | UART | Serial I/O |

## Building Firmware

```bash
cd firmware
make CROSS_COMPILE=powerpc64le-linux-gnu-
```

**Outputs**:
- `demo.elf` - ELF executable (for debugging)
- `demo.bin` - Raw binary (for loading to SRAM)
- `demo.hex` - Intel HEX format (for some tools)
- `demo.lst` - Disassembly listing

### Makefile Targets

```bash
make clean          # Remove build artifacts
make demo.lst       # Generate disassembly listing
```

## Linker Script Details

The linker script (`linker.ld`) defines memory layout:

```ld
MEMORY
{
    CODE_RAM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    DATA_RAM (rw)  : ORIGIN = 0x00002000, LENGTH = 8K
}

SECTIONS
{
    .text : { *(.text*) *(.rodata*) } > CODE_RAM
    .data : { *(.data*) } > DATA_RAM
    .bss  : { *(.bss*) } > DATA_RAM
}
```

**Key Points**:
- Stack grows down from `0x00004000` (end of DATA_RAM)
- No heap allocator by default (add if needed)
- All code must fit in 8KB
- Total RAM for data/stack: 8KB

## Example Application

The demo application (`demo.c`) tests all accelerator functions:

```c
int main(void) {
    // Initialize
    ml_accel_init();
    
    // Test 1: Matrix Multiplication
    int8_t mat_a[16] = {...};
    int8_t mat_b[16] = {...};
    int32_t result[16];
    ml_accel_matmul(mat_a, mat_b, result);
    
    // Test 2: Vector Operations
    int8_t vec_a[8] = {...};
    int8_t vec_b[8] = {...};
    int8_t vec_out[8];
    ml_accel_vector_op(VALU_OP_ADD, vec_a, vec_b, vec_out, 0);
    
    // Test 3: Softmax
    int8_t logits[8] = {...};
    int8_t probs[8];
    ml_accel_softmax(logits, probs, 8);
    
    // Output results via UART
    uart_puts("Tests complete!\r\n");
    
    while(1);  // Infinite loop
}
```

## Implementing ML Models

### Workflow

1. **Train model** in PyTorch/TensorFlow
2. **Quantize to INT8** using QAT or PTQ
3. **Export weights** to C arrays
4. **Tile layers** to fit in 8KB SRAM
5. **Implement inference** using driver API

### Example: Small Transformer Layer

```c
// Weights stored in code section
const int8_t query_weights[16] __attribute__((section(".rodata"))) = {...};
const int8_t key_weights[16] = {...};
const int8_t value_weights[16] = {...};

void transformer_attention(int8_t *input, int8_t *output) {
    int32_t query[16], key[16], value[16];
    int8_t scores[8];
    
    // Q = input * W_q
    ml_accel_matmul(input, query_weights, query);
    
    // K = input * W_k
    ml_accel_matmul(input, key_weights, key);
    
    // Attention scores = Q * K^T
    ml_accel_matmul((int8_t*)query, (int8_t*)key, (int32_t*)scores);
    
    // Softmax(scores)
    ml_accel_softmax(scores, scores, 8);
    
    // V = input * W_v
    ml_accel_matmul(input, value_weights, value);
    
    // Output = scores * V
    ml_accel_matmul(scores, (int8_t*)value, (int32_t*)output);
}
```

### Tiling Strategy

For layers larger than SRAM:

```c
#define TILE_SIZE 4

void matmul_tiled(int8_t *A, int8_t *B, int32_t *C, int M, int N, int K) {
    for (int i = 0; i < M; i += TILE_SIZE) {
        for (int j = 0; j < N; j += TILE_SIZE) {
            // Load tile from external source (e.g., SPI flash)
            load_tile(&A[i*K], TILE_SIZE);
            load_tile(&B[j], TILE_SIZE);
            
            // Compute tile
            ml_accel_matmul(&A[i*K], &B[j], &C[i*N + j]);
        }
    }
}
```

## Debugging

### Serial Output

Use UART for printf-style debugging:

```c
void uart_putc(char c);
void uart_puts(const char *s);
void print_int(int32_t val);
```

### Common Issues

1. **Stack overflow**: Reduce local variable usage or increase stack size
2. **Code too large**: Enable optimization (`-Os`), remove unused functions
3. **Alignment errors**: Ensure data is aligned (use `__attribute__((aligned(4)))`)

## Performance Optimization

### Tips

1. **Batch operations**: Group multiple vector ops together
2. **Reuse data**: Keep frequently-used weights in SRAM
3. **Pipeline**: Overlap CPU and accelerator execution
4. **Fixed-point**: Use INT8/INT16 for all computations

### Profiling

Add cycle counters:

```c
uint64_t start = read_cycle_counter();
ml_accel_matmul(a, b, c);
uint64_t cycles = read_cycle_counter() - start;
```

## References

- Microwatt ISA: https://openpowerfoundation.org/
- PowerPC Programming: https://www.ibm.com/docs/en/aix/7.2?topic=architecture-powerpc
- INT8 Quantization: https://arxiv.org/abs/1712.05877

