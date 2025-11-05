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

#include <stdint.h>
#include "ml_accel.h"

// Simple UART functions (placeholder)
void uart_putc(char c) {
    volatile uint32_t *uart_base = (volatile uint32_t *)0x80001000;
    uart_base[0] = c;  // Simplified UART write
}

void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

void print_int(int32_t val) {
    char buf[12];
    int i = 0;
    int neg = 0;
    
    if (val < 0) {
        neg = 1;
        val = -val;
    }
    
    do {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    } while (val > 0);
    
    if (neg) {
        buf[i++] = '-';
    }
    
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

int main(void) {
    int i, j;
    
    // Test matrices for matrix multiplication
    int8_t mat_a[16] = {
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 11, 12,
        13, 14, 15, 16
    };
    
    int8_t mat_b[16] = {
        2, 0, 0, 0,
        0, 2, 0, 0,
        0, 0, 2, 0,
        0, 0, 0, 2
    };
    
    int32_t mat_c[16];
    
    // Test vectors for vector operations
    int8_t vec_a[8] = {10, 20, 30, 40, 50, 60, 70, 80};
    int8_t vec_b[8] = {5, 5, 5, 5, 5, 5, 5, 5};
    int8_t vec_out[8];
    
    // Test vector for softmax
    int8_t softmax_in[8] = {10, 20, 30, 40, 50, 60, 70, 80};
    int8_t softmax_out[8];
    
    uart_puts("\r\n=== Microwatt-Infer SoC Demo ===\r\n\r\n");
    
    // Initialize accelerator
    uart_puts("Initializing ML accelerator...\r\n");
    ml_accel_init();
    
    // Test 1: Matrix Multiplication
    uart_puts("\r\nTest 1: Matrix Multiplication (4x4 * 4x4)\r\n");
    uart_puts("Matrix A * Matrix B (B is 2*I):\r\n");
    
    ml_accel_matmul(mat_a, mat_b, mat_c);
    
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 4; j++) {
            print_int(mat_c[i*4 + j]);
            uart_putc(' ');
        }
        uart_puts("\r\n");
    }
    
    // Test 2: Vector Addition
    uart_puts("\r\nTest 2: Vector Addition\r\n");
    uart_puts("A: ");
    for (i = 0; i < 8; i++) {
        print_int(vec_a[i]);
        uart_putc(' ');
    }
    uart_puts("\r\nB: ");
    for (i = 0; i < 8; i++) {
        print_int(vec_b[i]);
        uart_putc(' ');
    }
    
    ml_accel_vector_op(VALU_OP_ADD, vec_a, vec_b, vec_out, 0);
    
    uart_puts("\r\nA+B: ");
    for (i = 0; i < 8; i++) {
        print_int(vec_out[i]);
        uart_putc(' ');
    }
    uart_puts("\r\n");
    
    // Test 3: ReLU
    uart_puts("\r\nTest 3: ReLU (on negative values)\r\n");
    vec_a[0] = -10;
    vec_a[1] = 20;
    vec_a[2] = -30;
    vec_a[3] = 40;
    
    ml_accel_vector_op(VALU_OP_RELU, vec_a, vec_b, vec_out, 0);
    
    uart_puts("Result: ");
    for (i = 0; i < 4; i++) {
        print_int(vec_out[i]);
        uart_putc(' ');
    }
    uart_puts("\r\n");
    
    // Test 4: Softmax
    uart_puts("\r\nTest 4: Softmax\r\n");
    uart_puts("Input: ");
    for (i = 0; i < 8; i++) {
        print_int(softmax_in[i]);
        uart_putc(' ');
    }
    
    ml_accel_softmax(softmax_in, softmax_out, 8);
    
    uart_puts("\r\nOutput: ");
    for (i = 0; i < 8; i++) {
        print_int(softmax_out[i]);
        uart_putc(' ');
    }
    uart_puts("\r\n");
    
    // Test 5: Layer Normalization
    uart_puts("\r\nTest 5: Layer Normalization\r\n");
    ml_accel_layernorm(softmax_in, softmax_out, 8);
    
    uart_puts("Output: ");
    for (i = 0; i < 8; i++) {
        print_int(softmax_out[i]);
        uart_putc(' ');
    }
    uart_puts("\r\n");
    
    uart_puts("\r\n=== All tests completed ===\r\n");
    uart_puts("Inference SoC operational!\r\n\r\n");
    
    // Infinite loop
    while (1) {
        __asm__ volatile ("nop");
    }
    
    return 0;
}

