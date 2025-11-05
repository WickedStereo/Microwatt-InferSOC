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
 * Special Function Unit (SFU) for Softmax and LayerNorm
 * 
 * Implements:
 * 1. Softmax: exp(x) / sum(exp(x)) approximation using LUTs
 * 2. LayerNorm: (x - mean) / sqrt(variance + epsilon)
 * 
 * Uses:
 * - LUT for exp approximation (piecewise linear)
 * - LUT for reciprocal sqrt approximation
 * - Iterative sum reduction for mean/variance
 * 
 * Processes vectors of up to 16 elements
 * Pipeline: Multi-cycle iterative operation
 */

module sfu #(
    parameter VEC_SIZE = 16,
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32,
    parameter LUT_SIZE = 256
) (
    input wire clk,
    input wire rst,
    
    // Control interface
    input wire start,
    input wire [1:0] operation,
    // 2'b00: Softmax
    // 2'b01: LayerNorm
    // 2'b10: Exp (for testing)
    // 2'b11: Reserved
    
    input wire [3:0] vec_len,  // Actual vector length (1-16)
    
    // Data interface
    input wire signed [DATA_WIDTH-1:0] data_in,
    input wire data_in_valid,
    
    output reg signed [ACCUM_WIDTH-1:0] data_out,
    output reg data_out_valid,
    output reg busy,
    output reg done
);

    // FSM states
    localparam IDLE = 3'd0;
    localparam LOAD_DATA = 3'd1;
    localparam FIND_MAX = 3'd2;
    localparam COMPUTE_EXP = 3'd3;
    localparam COMPUTE_SUM = 3'd4;
    localparam COMPUTE_RECIP = 3'd5;
    localparam NORMALIZE = 3'd6;
    localparam OUTPUT = 3'd7;
    
    reg [2:0] state;
    reg [4:0] counter;
    reg [4:0] vec_len_r;
    reg [1:0] operation_r;
    
    // Data storage
    reg signed [DATA_WIDTH-1:0] data_buf [0:VEC_SIZE-1];
    reg signed [ACCUM_WIDTH-1:0] accum_buf [0:VEC_SIZE-1];
    
    // Working registers
    reg signed [DATA_WIDTH-1:0] max_val;
    reg signed [ACCUM_WIDTH-1:0] sum_accum;
    reg signed [ACCUM_WIDTH-1:0] mean_val;
    reg signed [ACCUM_WIDTH-1:0] variance_val;
    reg signed [ACCUM_WIDTH-1:0] recip_val;
    
    // EXP LUT for INT8 softmax (I-BERT approach)
    // Input: x in range [0, 127] representing negative exponents after max subtraction
    // Output: Q8.8 fixed point representation of exp(-x/16)
    // We scale input by dividing by 16 to get reasonable dynamic range
    function [15:0] exp_lut;
        input [7:0] x;
        reg [15:0] result;
        begin
            // For x > 127 (very negative), return near-zero
            if (x > 8'd127)
                result = 16'h0001;  // ~0.004
            // Piecewise linear approximation for exp(-x/16)
            // Range 0-8: exp(-0) to exp(-0.5) = [1.0, 0.606]
            else if (x <= 8'd8)
                result = 16'h0100 - (x * 16'h0C);  // Linear interpolation
            // Range 8-16: exp(-0.5) to exp(-1.0) = [0.606, 0.368]
            else if (x <= 8'd16)
                result = 16'h009B - ((x - 8'd8) * 16'h07);
            // Range 16-32: exp(-1.0) to exp(-2.0) = [0.368, 0.135]
            else if (x <= 8'd32)
                result = 16'h005E - ((x - 8'd16) * 16'h03);
            // Range 32-48: exp(-2.0) to exp(-3.0) = [0.135, 0.050]
            else if (x <= 8'd48)
                result = 16'h0023 - ((x - 8'd32) >> 2);
            // Range 48-80: exp(-3.0) to exp(-5.0) = [0.050, 0.007]
            else if (x <= 8'd80)
                result = 16'h000D - ((x - 8'd48) >> 4);
            // Range 80+: very small values
            else
                result = 16'h0002;  // ~0.008
            
            exp_lut = result;
        end
    endfunction
    
    // Reciprocal LUT: approximates 65536/x for Q16 fixed-point reciprocal
    // Typical softmax sum range: 200-2000, so 65536/x gives 32-328
    function [15:0] rsqrt_lut;
        input [15:0] x;
        reg [15:0] result;
        reg [31:0] recip_calc;
        begin
            // Direct approximation: result ≈ 65536 / x
            if (x == 0)
                result = 16'hFFFF;
            else if (x < 16'd64)
                recip_calc = 32'd65536 / x;  // Direct divide for small x
            else if (x < 16'd128)
                result = 16'd512;  // 65536/128 = 512
            else if (x < 16'd192)
                result = 16'd384;  // ~65536/170
            else if (x < 16'd256)
                result = 16'd256;  // 65536/256 = 256
            else if (x < 16'd384)
                result = 16'd192;  // ~65536/340
            else if (x < 16'd512)
                result = 16'd128;  // 65536/512 = 128
            else if (x < 16'd768)
                result = 16'd96;   // ~65536/680
            else if (x < 16'd1024)
                result = 16'd64;   // 65536/1024 = 64
            else if (x < 16'd2048)
                result = 16'd32;   // 65536/2048 = 32
            else if (x < 16'd4096)
                result = 16'd16;   // 65536/4096 = 16
            else
                result = 16'd8;    // For very large x
            
            // Use computed value for small x
            if (x < 16'd64)
                result = recip_calc[15:0];
            
            rsqrt_lut = result;
        end
    endfunction
    
    integer i;
    
    // Declare variables used in case statements at top level
    reg signed [DATA_WIDTH-1:0] diff;
    reg [15:0] exp_result;
    reg signed [ACCUM_WIDTH-1:0] centered;
    reg signed [ACCUM_WIDTH-1:0] result;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            counter <= 0;
            vec_len_r <= 0;
            operation_r <= 0;
            max_val <= 0;
            sum_accum <= 0;
            mean_val <= 0;
            variance_val <= 0;
            recip_val <= 0;
            data_out <= 0;
            data_out_valid <= 0;
            busy <= 0;
            done <= 0;
            
            for (i = 0; i < VEC_SIZE; i = i + 1) begin
                data_buf[i] <= 0;
                accum_buf[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    // Clear done only when starting a new operation
                    data_out_valid <= 0;
                    if (start) begin
                        done <= 0;
                        state <= LOAD_DATA;
                        counter <= 0;
                        vec_len_r <= vec_len;
                        operation_r <= operation;
                        busy <= 1;
                        max_val <= -128;  // INT8 minimum
                        sum_accum <= 0;
                    end else begin
                        busy <= 0;
                    end
                end
                
                LOAD_DATA: begin
                    if (data_in_valid) begin
                        data_buf[counter] <= data_in;
                        counter <= counter + 1;
                        
                        // Track maximum for softmax
                        if (data_in > max_val)
                            max_val <= data_in;
                        
                        if (counter == vec_len_r - 1) begin
                            if (operation_r == 2'b00) begin
                                // Softmax: go to exp computation
                                state <= COMPUTE_EXP;
                                counter <= 0;
                            end else begin
                                // LayerNorm: compute mean first
                                state <= COMPUTE_SUM;
                                counter <= 0;
                            end
                        end
                    end
                end
                
                COMPUTE_EXP: begin
                    // Compute exp(x - max) for numerical stability
                    // For INT8 softmax: use (max - x) since we need exp of negative values
                    if (counter < vec_len_r) begin
                        // diff is how much less than max (always positive or zero)
                        diff = max_val - data_buf[counter];
                        
                        // Apply exp LUT (handles negative exponent via positive diff)
                        exp_result = exp_lut(diff[7:0]);
                        accum_buf[counter] <= {{16{1'b0}}, exp_result};
                        sum_accum <= sum_accum + {{16{1'b0}}, exp_result};
                        
                        counter <= counter + 1;
                    end else begin
                        // Compute 1/sum for normalization
                        recip_val <= {{16{1'b0}}, rsqrt_lut(sum_accum[15:0])};
                        state <= OUTPUT;
                        counter <= 0;
                    end
                end
                
                COMPUTE_SUM: begin
                    // Accumulate for mean (LayerNorm)
                    if (counter < vec_len_r) begin
                        sum_accum <= sum_accum + {{24{data_buf[counter][DATA_WIDTH-1]}}, data_buf[counter]};
                        counter <= counter + 1;
                    end else begin
                        // Compute mean
                        mean_val <= sum_accum / vec_len_r;
                        state <= NORMALIZE;
                        counter <= 0;
                        sum_accum <= 0;
                    end
                end
                
                COMPUTE_RECIP: begin
                    // Compute 1/sum for softmax or 1/sqrt(var) for layernorm
                    if (operation_r == 2'b00) begin
                        // Simple reciprocal for softmax (use shift approximation)
                        // For simplicity, use Q8 format: recip ≈ 256*256/sum
                        if (sum_accum > 0)
                            recip_val <= (32'h10000 / sum_accum);
                        else
                            recip_val <= 32'h0100;
                    end else begin
                        // Reciprocal sqrt for layernorm
                        recip_val <= {{16{1'b0}}, rsqrt_lut(variance_val[15:0])};
                    end
                    state <= OUTPUT;
                    counter <= 0;
                end
                
                NORMALIZE: begin
                    // For LayerNorm: compute variance
                    if (counter < vec_len_r) begin
                        centered = {{24{data_buf[counter][DATA_WIDTH-1]}}, data_buf[counter]} - mean_val;
                        accum_buf[counter] <= centered;
                        variance_val <= variance_val + (centered * centered);
                        counter <= counter + 1;
                    end else begin
                        variance_val <= variance_val / vec_len_r;
                        state <= COMPUTE_RECIP;
                        counter <= 0;
                    end
                end
                
                OUTPUT: begin
                    if (counter < vec_len_r) begin
                        if (operation_r == 2'b00) begin
                            // Softmax: (exp(x) * recip_sum)
                            // exp is 16-bit Q8.8 in 32-bit, recip is 16-bit
                            // Multiply: 16×16=32, shift by 8 to get result in Q8.8
                            result = (accum_buf[counter][15:0] * recip_val[15:0]) >>> 8;
                        end else begin
                            // LayerNorm: ((x - mean) * rsqrt(var))
                            // centered value * rsqrt, shift to maintain scale
                            result = (accum_buf[counter] * recip_val) >>> 11;  // Adjusted for better scaling
                        end
                        
                        data_out <= result;
                        data_out_valid <= 1;
                        counter <= counter + 1;
                    end else begin
                        data_out_valid <= 0;
                        state <= IDLE;
                        done <= 1;
                        busy <= 0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

