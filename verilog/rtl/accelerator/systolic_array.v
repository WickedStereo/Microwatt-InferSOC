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
 * Systolic Array for Matrix Multiplication
 * 
 * 4x4 array of processing elements for efficient matrix multiply
 * - Weight stationary: weights are preloaded and remain in PEs
 * - Activations flow left-to-right
 * - Partial sums accumulate top-to-bottom
 * 
 * Supports INT8 input data with INT32 accumulation
 * 
 * Operation: C[4x4] = A[4xN] * B[Nx4]
 * - Weights B are preloaded column-wise into each PE column
 * - Activations A flow through row-wise
 * - Results accumulate and output from bottom row
 */

module systolic_array #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire enable,
    
    // Weight loading interface
    input wire weight_load_en,
    input wire [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] weight_data_in,
    
    // Activation inputs (one per row)
    input wire [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] act_data_in,
    
    // Partial sum outputs (one per column, from bottom row)
    output wire [ARRAY_SIZE-1:0][ACCUM_WIDTH-1:0] psum_out
);

    // Internal PE interconnections
    // Horizontal activation flow (left to right)
    wire signed [ARRAY_SIZE:0][ARRAY_SIZE-1:0][DATA_WIDTH-1:0] act_h;
    
    // Vertical weight flow (top to bottom)
    wire signed [ARRAY_SIZE-1:0][ARRAY_SIZE:0][DATA_WIDTH-1:0] weight_v;
    
    // Vertical partial sum flow (top to bottom)
    wire signed [ARRAY_SIZE-1:0][ARRAY_SIZE:0][ACCUM_WIDTH-1:0] psum_v;
    
    // Connect inputs to array edges
    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : gen_input_rows
            assign act_h[0][row] = act_data_in[row];
        end
        
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : gen_input_cols
            // Top row gets weights during load, zeros for partial sums
            assign weight_v[col][0] = weight_load_en ? weight_data_in[col] : 0;
            assign psum_v[col][0] = 0;
            
            // Bottom row outputs
            assign psum_out[col] = psum_v[col][ARRAY_SIZE];
        end
    endgenerate
    
    // Instantiate PE array
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : gen_rows
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : gen_cols
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACCUM_WIDTH(ACCUM_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .enable(enable),
                    
                    // Horizontal activation flow
                    .act_in(act_h[col][row]),
                    .act_out(act_h[col+1][row]),
                    
                    // Vertical weight flow
                    .weight_in(weight_v[col][row]),
                    .weight_out(weight_v[col][row+1]),
                    
                    // Vertical partial sum flow
                    .psum_in(psum_v[col][row]),
                    .psum_out(psum_v[col][row+1])
                );
            end
        end
    endgenerate

endmodule

`default_nettype wire

