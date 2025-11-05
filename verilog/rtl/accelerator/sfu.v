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
    
    output reg signed [DATA_WIDTH-1:0] data_out,
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
    
    // EXP LUT (piecewise linear approximation for exp(-x) where x is 0 to 8)
    // Using Q8.8 fixed point format
    // exp(-x) ≈ 2^(-x/ln(2)) for x in [0, 8]
    function [15:0] exp_lut;
        input [7:0] x;
        reg [15:0] result;
        begin
            if (x == 0)
                result = 16'h0100;  // exp(0) = 1.0
            else if (x < 8'd32)
                result = 16'h00F0 - (x << 2);  // Linear approx for small x
            else if (x < 8'd64)
                result = 16'h0080 - (x << 1);
            else if (x < 8'd96)
                result = 16'h0040 - x;
            else if (x < 8'd128)
                result = 16'h0020 - (x >> 1);
            else if (x < 8'd160)
                result = 16'h0010 - (x >> 2);
            else if (x < 8'd192)
                result = 16'h0008 - (x >> 3);
            else
                result = 16'h0001;  // Very small for large x
            exp_lut = result;
        end
    endfunction
    
    // Reciprocal sqrt LUT (for LayerNorm)
    // rsqrt(x) ≈ 1/sqrt(x) using Newton-Raphson approximation
    function [15:0] rsqrt_lut;
        input [15:0] x;
        reg [15:0] result;
        begin
            if (x < 16'd16)
                result = 16'h4000;  // ~4.0 for very small x
            else if (x < 16'd64)
                result = 16'h2000;  // ~2.0
            else if (x < 16'd256)
                result = 16'h1000;  // ~1.0
            else if (x < 16'd1024)
                result = 16'h0800;  // ~0.5
            else if (x < 16'd4096)
                result = 16'h0400;  // ~0.25
            else
                result = 16'h0200;  // ~0.125
            rsqrt_lut = result;
        end
    endfunction
    
    integer i;
    
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
                    done <= 0;
                    data_out_valid <= 0;
                    if (start) begin
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
                    if (counter < vec_len_r) begin
                        reg signed [DATA_WIDTH-1:0] diff;
                        reg [15:0] exp_result;
                        
                        diff = data_buf[counter] - max_val;
                        // Clamp negative differences
                        if (diff < 0)
                            diff = -diff;
                        else
                            diff = 0;
                        
                        exp_result = exp_lut(diff[7:0]);
                        accum_buf[counter] <= {{16{1'b0}}, exp_result};
                        sum_accum <= sum_accum + {{16{1'b0}}, exp_result};
                        
                        counter <= counter + 1;
                    end else begin
                        state <= COMPUTE_RECIP;
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
                        reg signed [ACCUM_WIDTH-1:0] centered;
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
                        reg signed [ACCUM_WIDTH-1:0] result;
                        
                        if (operation_r == 2'b00) begin
                            // Softmax: (exp(x) * recip) >> 8
                            result = (accum_buf[counter] * recip_val) >>> 16;
                        end else begin
                            // LayerNorm: ((x - mean) * rsqrt) >> 8
                            result = (accum_buf[counter] * recip_val) >>> 16;
                        end
                        
                        // Clamp to INT8 range
                        if (result > 127)
                            data_out <= 127;
                        else if (result < -128)
                            data_out <= -128;
                        else
                            data_out <= result[DATA_WIDTH-1:0];
                        
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

