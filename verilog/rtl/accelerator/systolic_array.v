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
    input wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] weight_data_in,
    
    // Activation inputs (one per row)
    input wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] act_data_in,
    
    // Partial sum outputs (one per column, from bottom row)
    output wire [(ARRAY_SIZE*ACCUM_WIDTH)-1:0] psum_out
);

    // Unpack flattened inputs into 2D arrays
    wire signed [DATA_WIDTH-1:0] weight_in [ARRAY_SIZE-1:0];
    wire signed [DATA_WIDTH-1:0] act_in [ARRAY_SIZE-1:0];
    reg signed [ACCUM_WIDTH-1:0] psum_out_arr [ARRAY_SIZE-1:0];
    
    genvar unpack_idx;
    generate
        for (unpack_idx = 0; unpack_idx < ARRAY_SIZE; unpack_idx = unpack_idx + 1) begin : gen_unpack
            assign weight_in[unpack_idx] = weight_data_in[unpack_idx*DATA_WIDTH +: DATA_WIDTH];
            assign act_in[unpack_idx] = act_data_in[unpack_idx*DATA_WIDTH +: DATA_WIDTH];
            assign psum_out[unpack_idx*ACCUM_WIDTH +: ACCUM_WIDTH] = psum_out_arr[unpack_idx];
        end
    endgenerate

    // Internal PE interconnections
    // Horizontal activation flow (left to right)
    wire signed [ARRAY_SIZE:0][ARRAY_SIZE-1:0][DATA_WIDTH-1:0] act_h;
    
    // Vertical weight flow (top to bottom)
    wire signed [ARRAY_SIZE-1:0][ARRAY_SIZE:0][DATA_WIDTH-1:0] weight_v;
    
    // Vertical partial sum flow (top to bottom)
    wire signed [ARRAY_SIZE-1:0][ARRAY_SIZE:0][ACCUM_WIDTH-1:0] psum_v;
    
    // Weight buffer to accumulate weights before loading into array
    reg signed [DATA_WIDTH-1:0] weight_buffer [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [3:0] load_counter;
    reg load_trigger;  // Pulse to actually load weights into PEs
    
    // Buffer incoming weights and trigger load when complete
    always @(posedge clk) begin
        if (rst) begin
            load_counter <= 0;
            load_trigger <= 0;
        end else if (weight_load_en) begin
            // Store incoming weight row
            if (load_counter < ARRAY_SIZE) begin
                for (integer c = 0; c < ARRAY_SIZE; c = c + 1) begin
                    weight_buffer[load_counter][c] <= weight_data_in[c];
                end
                load_counter <= load_counter + 1;
            end
            
            // Trigger load when all rows buffered
            if (load_counter == ARRAY_SIZE - 1) begin
                load_trigger <= 1;
            end else begin
                load_trigger <= 0;
            end
        end else begin
            load_counter <= 0;
            load_trigger <= 0;
        end
    end
    
    // Generate load enable for each PE based on its buffered weight
    wire [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0] pe_weight_in;
    genvar r, c;
    generate
        for (r = 0; r < ARRAY_SIZE; r = r + 1) begin : gen_pe_weights
            for (c = 0; c < ARRAY_SIZE; c = c + 1) begin : gen_pe_weights_col
                assign pe_weight_in[r][c] = weight_buffer[r][c];
            end
        end
    endgenerate
    
    // Connect inputs to array edges
    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : gen_input_rows
            assign act_h[0][row] = act_in[row];
        end
        
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : gen_input_cols
            // Top row gets weight inputs
            assign weight_v[col][0] = weight_in[col];
            
            // Top row starts with zero partial sums
            assign psum_v[col][0] = 0;
            
            // Bottom row outputs
            always @(*) begin
                psum_out_arr[col] = psum_v[col][ARRAY_SIZE];
            end
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
                    .weight_load(load_trigger),  // All PEs load when buffer is full
                    
                    // Horizontal activation flow
                    .act_in(act_h[col][row]),
                    .act_out(act_h[col+1][row]),
                    
                    // Vertical weight flow (use buffered weight during load, normal flow otherwise)
                    .weight_in(load_trigger ? pe_weight_in[row][col] : weight_v[col][row]),
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

