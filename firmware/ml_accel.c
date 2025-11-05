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

#include "ml_accel.h"

void ml_accel_init(void) {
    // Reset control register
    ML_ACCEL_REG(ML_ACCEL_CTRL) = 0;
    ML_ACCEL_REG(ML_ACCEL_CONFIG) = 0;
}

void ml_accel_matmul(const int8_t *a, const int8_t *b, int32_t *c) {
    int i;
    
    // Load weights (matrix B) into systolic array
    for (i = 0; i < 16; i += 4) {
        uint32_t weight_word = ((uint32_t)b[i+3] << 24) |
                               ((uint32_t)b[i+2] << 16) |
                               ((uint32_t)b[i+1] << 8) |
                               ((uint32_t)b[i+0]);
        ML_ACCEL_REG(ML_ACCEL_SYS_WEIGHT + (i << 2)) = weight_word;
    }
    
    // Load activations (matrix A)
    for (i = 0; i < 16; i += 4) {
        uint32_t act_word = ((uint32_t)a[i+3] << 24) |
                            ((uint32_t)a[i+2] << 16) |
                            ((uint32_t)a[i+1] << 8) |
                            ((uint32_t)a[i+0]);
        ML_ACCEL_REG(ML_ACCEL_SYS_DATA + (i << 2)) = act_word;
    }
    
    // Start systolic array computation
    ML_ACCEL_REG(ML_ACCEL_CTRL) = CTRL_SYS_START;
    
    // Wait for completion
    ml_accel_wait_done(CTRL_SYS_DONE);
    
    // Read results
    for (i = 0; i < 16; i++) {
        c[i] = (int32_t)ML_ACCEL_REG(ML_ACCEL_SYS_OUTPUT + (i << 2));
    }
    
    // Clear done bit
    ML_ACCEL_REG(ML_ACCEL_CTRL) = 0;
}

void ml_accel_vector_op(uint8_t op, const int8_t *a, const int8_t *b, 
                        int8_t *out, int8_t scalar) {
    int i;
    uint64_t vec_a, vec_b, vec_out;
    
    // Pack vectors into 64-bit words
    vec_a = 0;
    vec_b = 0;
    for (i = 0; i < 8; i++) {
        vec_a |= ((uint64_t)(a[i] & 0xFF) << (i * 8));
        vec_b |= ((uint64_t)(b[i] & 0xFF) << (i * 8));
    }
    
    // Write vectors to accelerator
    ML_ACCEL_REG(ML_ACCEL_VALU_A) = (uint32_t)vec_a;
    ML_ACCEL_REG(ML_ACCEL_VALU_A + 4) = (uint32_t)(vec_a >> 32);
    ML_ACCEL_REG(ML_ACCEL_VALU_B) = (uint32_t)vec_b;
    ML_ACCEL_REG(ML_ACCEL_VALU_B + 4) = (uint32_t)(vec_b >> 32);
    
    // Configure operation
    ML_ACCEL_REG(ML_ACCEL_CONFIG) = (op & 0xF) | ((scalar & 0xFF) << 8);
    
    // Start vector ALU
    ML_ACCEL_REG(ML_ACCEL_CTRL) = CTRL_VALU_START;
    
    // Wait for completion
    ml_accel_wait_done(CTRL_VALU_DONE);
    
    // Read results
    vec_out = ML_ACCEL_REG(ML_ACCEL_VALU_OUT);
    vec_out |= ((uint64_t)ML_ACCEL_REG(ML_ACCEL_VALU_OUT + 4) << 32);
    
    for (i = 0; i < 8; i++) {
        out[i] = (int8_t)((vec_out >> (i * 8)) & 0xFF);
    }
    
    // Clear done bit
    ML_ACCEL_REG(ML_ACCEL_CTRL) = 0;
}

void ml_accel_softmax(const int8_t *in, int8_t *out, uint8_t len) {
    int i;
    
    // Configure SFU for softmax
    ML_ACCEL_REG(ML_ACCEL_CONFIG) = (SFU_OP_SOFTMAX << 16) | ((len & 0xF) << 18);
    
    // Start SFU
    ML_ACCEL_REG(ML_ACCEL_CTRL) = CTRL_SFU_START;
    
    // Stream input data
    for (i = 0; i < len; i++) {
        ML_ACCEL_REG(ML_ACCEL_SFU_IN) = (uint32_t)in[i];
    }
    
    // Wait for completion
    ml_accel_wait_done(CTRL_SFU_DONE);
    
    // Read output data
    for (i = 0; i < len; i++) {
        out[i] = (int8_t)(ML_ACCEL_REG(ML_ACCEL_SFU_OUT + (i << 2)) & 0xFF);
    }
    
    // Clear done bit
    ML_ACCEL_REG(ML_ACCEL_CTRL) = 0;
}

void ml_accel_layernorm(const int8_t *in, int8_t *out, uint8_t len) {
    int i;
    
    // Configure SFU for layer normalization
    ML_ACCEL_REG(ML_ACCEL_CONFIG) = (SFU_OP_LAYERNORM << 16) | ((len & 0xF) << 18);
    
    // Start SFU
    ML_ACCEL_REG(ML_ACCEL_CTRL) = CTRL_SFU_START;
    
    // Stream input data
    for (i = 0; i < len; i++) {
        ML_ACCEL_REG(ML_ACCEL_SFU_IN) = (uint32_t)in[i];
    }
    
    // Wait for completion
    ml_accel_wait_done(CTRL_SFU_DONE);
    
    // Read output data
    for (i = 0; i < len; i++) {
        out[i] = (int8_t)(ML_ACCEL_REG(ML_ACCEL_SFU_OUT + (i << 2)) & 0xFF);
    }
    
    // Clear done bit
    ML_ACCEL_REG(ML_ACCEL_CTRL) = 0;
}

int ml_accel_wait_done(uint32_t done_bit) {
    volatile uint32_t timeout = 100000;
    
    while (timeout > 0) {
        if (ML_ACCEL_REG(ML_ACCEL_CTRL) & done_bit) {
            return 0;
        }
        timeout--;
    }
    
    return -1;  // Timeout
}

void ml_accel_irq_enable(int enable) {
    uint32_t ctrl = ML_ACCEL_REG(ML_ACCEL_CTRL);
    
    if (enable) {
        ctrl |= CTRL_IRQ_EN;
    } else {
        ctrl &= ~CTRL_IRQ_EN;
    }
    
    ML_ACCEL_REG(ML_ACCEL_CTRL) = ctrl;
}

