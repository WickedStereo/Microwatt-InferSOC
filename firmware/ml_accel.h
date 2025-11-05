// SPDX-FileCopyrightText: 2024 Microwatt-InferSOC Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

#ifndef ML_ACCEL_H
#define ML_ACCEL_H

#include <stdint.h>

// ML Accelerator base address
#define ML_ACCEL_BASE 0x80000000UL

// Register offsets
#define ML_ACCEL_CTRL      0x000
#define ML_ACCEL_CONFIG    0x004
#define ML_ACCEL_SYS_DATA  0x010
#define ML_ACCEL_SYS_WEIGHT 0x050
#define ML_ACCEL_SYS_OUTPUT 0x090
#define ML_ACCEL_VALU_A    0x100
#define ML_ACCEL_VALU_B    0x140
#define ML_ACCEL_VALU_OUT  0x180
#define ML_ACCEL_SFU_IN    0x200
#define ML_ACCEL_SFU_OUT   0x240

// Control register bits
#define CTRL_SYS_START  (1 << 0)
#define CTRL_SYS_DONE   (1 << 1)
#define CTRL_VALU_START (1 << 2)
#define CTRL_VALU_DONE  (1 << 3)
#define CTRL_SFU_START  (1 << 4)
#define CTRL_SFU_DONE   (1 << 5)
#define CTRL_IRQ_EN     (1 << 8)

// Vector ALU operations
#define VALU_OP_ADD   0x0
#define VALU_OP_SUB   0x1
#define VALU_OP_MUL   0x2
#define VALU_OP_RELU  0x3
#define VALU_OP_MAX   0x4
#define VALU_OP_MIN   0x5
#define VALU_OP_SCALE 0x6
#define VALU_OP_CLIP  0x7

// SFU operations
#define SFU_OP_SOFTMAX   0x0
#define SFU_OP_LAYERNORM 0x1

// Register access macros
#define ML_ACCEL_REG(offset) (*(volatile uint32_t *)(ML_ACCEL_BASE + (offset)))

// Function prototypes

/**
 * Initialize the ML accelerator
 */
void ml_accel_init(void);

/**
 * Perform matrix multiplication using systolic array
 * C[4x4] = A[4x4] * B[4x4]
 * 
 * @param a Input matrix A (16 int8 elements, row-major)
 * @param b Input matrix B (16 int8 elements, row-major)
 * @param c Output matrix C (16 int32 elements, row-major)
 */
void ml_accel_matmul(const int8_t *a, const int8_t *b, int32_t *c);

/**
 * Perform vector operation using Vector ALU
 * 
 * @param op Operation code (VALU_OP_*)
 * @param a Input vector A (8 int8 elements)
 * @param b Input vector B (8 int8 elements)
 * @param out Output vector (8 int8 elements)
 * @param scalar Scalar parameter for SCALE/CLIP operations
 */
void ml_accel_vector_op(uint8_t op, const int8_t *a, const int8_t *b, 
                        int8_t *out, int8_t scalar);

/**
 * Perform Softmax operation
 * 
 * @param in Input vector (up to 16 int8 elements)
 * @param out Output vector (same size as input)
 * @param len Vector length (1-16)
 */
void ml_accel_softmax(const int8_t *in, int8_t *out, uint8_t len);

/**
 * Perform Layer Normalization
 * 
 * @param in Input vector (up to 16 int8 elements)
 * @param out Output vector (same size as input)
 * @param len Vector length (1-16)
 */
void ml_accel_layernorm(const int8_t *in, int8_t *out, uint8_t len);

/**
 * Wait for operation to complete
 * 
 * @param done_bit Control bit to check (CTRL_*_DONE)
 * @return 0 on success, -1 on timeout
 */
int ml_accel_wait_done(uint32_t done_bit);

/**
 * Enable/disable accelerator interrupts
 * 
 * @param enable 1 to enable, 0 to disable
 */
void ml_accel_irq_enable(int enable);

#endif // ML_ACCEL_H

