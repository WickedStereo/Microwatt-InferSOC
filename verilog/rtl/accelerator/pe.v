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
 * Processing Element (PE) for Systolic Array
 * 
 * Implements a single PE for matrix multiplication:
 * - Takes input activation (from left) and weight (from top)
 * - Accumulates: partial_sum_out = partial_sum_in + (activation * weight)
 * - Passes activation right and weight down
 * 
 * Pipeline: 1 cycle multiply + accumulate
 * Data type: signed INT8
 */

module pe #(
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire weight_load,  // Signal to load weight into this PE
    
    // Input activation (from left PE)
    input wire signed [DATA_WIDTH-1:0] act_in,
    // Input weight (from top PE)
    input wire signed [DATA_WIDTH-1:0] weight_in,
    // Partial sum input (from top PE in output stationary mode)
    input wire signed [ACCUM_WIDTH-1:0] psum_in,
    
    // Output activation (to right PE)
    output reg signed [DATA_WIDTH-1:0] act_out,
    // Output weight (to bottom PE)
    output reg signed [DATA_WIDTH-1:0] weight_out,
    // Partial sum output (to bottom PE)
    output reg signed [ACCUM_WIDTH-1:0] psum_out
);

    // Stored weight for weight-stationary operation
    reg signed [DATA_WIDTH-1:0] weight_stored;
    
    // Internal multiply result (combinational)
    wire signed [2*DATA_WIDTH-1:0] mult_result;
    assign mult_result = act_in * weight_stored;
    
    always @(posedge clk) begin
        if (rst) begin
            act_out <= 0;
            weight_out <= 0;
            weight_stored <= 0;
            psum_out <= 0;
        end else begin
            // Always pass weights down (flows top to bottom)
            weight_out <= weight_in;
            
            // Load weight when load signal is pulsed (controlled by array)
            if (weight_load) begin
                weight_stored <= weight_in;
            end
            
            // Compute when enabled
            if (enable) begin
                act_out <= act_in;
                psum_out <= psum_in + mult_result;
            end else begin
                psum_out <= 0;  // Clear when not computing
            end
        end
    end

endmodule

`default_nettype wire

