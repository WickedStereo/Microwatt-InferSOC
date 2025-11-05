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

`default_nettype none

/*
 * Vector ALU for Element-wise Operations
 * 
 * Performs SIMD-style operations on vectors:
 * - ADD: element-wise addition
 * - SUB: element-wise subtraction
 * - MUL: element-wise multiplication
 * - RELU: max(x, 0)
 * - MAX: element-wise maximum
 * - MIN: element-wise minimum
 * - SCALE: multiply by scalar with shift
 * 
 * Operates on 8 INT8 elements in parallel (64-bit SIMD)
 * Pipeline: 2 stages (operation + result)
 */

module vector_alu #(
    parameter VEC_SIZE = 8,          // Number of elements per vector
    parameter ELEM_WIDTH = 8,        // Bits per element (INT8)
    parameter DATA_WIDTH = 64        // Total vector width (8*8 = 64)
) (
    input wire clk,
    input wire rst,
    input wire enable,
    
    // Operation control
    input wire [3:0] opcode,
    // 4'b0000: ADD
    // 4'b0001: SUB
    // 4'b0010: MUL
    // 4'b0011: RELU
    // 4'b0100: MAX
    // 4'b0101: MIN
    // 4'b0110: SCALE (multiply by scalar)
    // 4'b0111: CLIP (clamp to range)
    
    // Vector inputs
    input wire signed [DATA_WIDTH-1:0] vec_a,
    input wire signed [DATA_WIDTH-1:0] vec_b,
    
    // Scalar input (for SCALE operation)
    input wire signed [ELEM_WIDTH-1:0] scalar,
    
    // Output
    output reg signed [DATA_WIDTH-1:0] vec_out,
    output reg valid_out
);

    // Break vectors into elements
    wire signed [ELEM_WIDTH-1:0] elem_a [0:VEC_SIZE-1];
    wire signed [ELEM_WIDTH-1:0] elem_b [0:VEC_SIZE-1];
    reg signed [ELEM_WIDTH-1:0] elem_result [0:VEC_SIZE-1];
    
    genvar i;
    generate
        for (i = 0; i < VEC_SIZE; i = i + 1) begin : gen_elements
            assign elem_a[i] = vec_a[i*ELEM_WIDTH +: ELEM_WIDTH];
            assign elem_b[i] = vec_b[i*ELEM_WIDTH +: ELEM_WIDTH];
        end
    endgenerate
    
    // Pipeline registers
    reg [3:0] opcode_r;
    reg signed [DATA_WIDTH-1:0] vec_a_r, vec_b_r;
    reg signed [ELEM_WIDTH-1:0] scalar_r;
    reg enable_r;
    
    integer j;
    always @(posedge clk) begin
        if (rst) begin
            opcode_r <= 0;
            vec_a_r <= 0;
            vec_b_r <= 0;
            scalar_r <= 0;
            enable_r <= 0;
            vec_out <= 0;
            valid_out <= 0;
        end else begin
            // Stage 1: Register inputs
            opcode_r <= opcode;
            vec_a_r <= vec_a;
            vec_b_r <= vec_b;
            scalar_r <= scalar;
            enable_r <= enable;
            
            // Stage 2: Compute and output
            if (enable_r) begin
                for (j = 0; j < VEC_SIZE; j = j + 1) begin
                    case (opcode_r)
                        4'b0000: // ADD
                            elem_result[j] = elem_a[j] + elem_b[j];
                        
                        4'b0001: // SUB
                            elem_result[j] = elem_a[j] - elem_b[j];
                        
                        4'b0010: begin // MUL (with saturation)
                            reg signed [2*ELEM_WIDTH-1:0] mul_tmp;
                            mul_tmp = elem_a[j] * elem_b[j];
                            // Saturate to INT8 range
                            if (mul_tmp > 127)
                                elem_result[j] = 127;
                            else if (mul_tmp < -128)
                                elem_result[j] = -128;
                            else
                                elem_result[j] = mul_tmp[ELEM_WIDTH-1:0];
                        end
                        
                        4'b0011: // RELU
                            elem_result[j] = (elem_a[j] > 0) ? elem_a[j] : 0;
                        
                        4'b0100: // MAX
                            elem_result[j] = (elem_a[j] > elem_b[j]) ? elem_a[j] : elem_b[j];
                        
                        4'b0101: // MIN
                            elem_result[j] = (elem_a[j] < elem_b[j]) ? elem_a[j] : elem_b[j];
                        
                        4'b0110: begin // SCALE (multiply by scalar, shift right 7)
                            reg signed [2*ELEM_WIDTH-1:0] scale_tmp;
                            scale_tmp = elem_a[j] * scalar_r;
                            // Shift right to maintain Q7 fixed point
                            elem_result[j] = scale_tmp >>> 7;
                        end
                        
                        4'b0111: // CLIP (clamp between scalar and -scalar)
                            if (elem_a[j] > scalar_r)
                                elem_result[j] = scalar_r;
                            else if (elem_a[j] < -scalar_r)
                                elem_result[j] = -scalar_r;
                            else
                                elem_result[j] = elem_a[j];
                        
                        default:
                            elem_result[j] = elem_a[j];
                    endcase
                end
                
                // Pack results back into vector
                for (j = 0; j < VEC_SIZE; j = j + 1) begin
                    vec_out[j*ELEM_WIDTH +: ELEM_WIDTH] <= elem_result[j];
                end
                
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire

