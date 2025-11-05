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

`timescale 1ns/1ps

module tb_vector_alu;

    reg clk;
    reg rst;
    reg enable;
    reg [3:0] opcode;
    reg signed [63:0] vec_a;
    reg signed [63:0] vec_b;
    reg signed [7:0] scalar;
    wire signed [63:0] vec_out;
    wire valid_out;
    
    // Instantiate DUT
    vector_alu #(
        .VEC_SIZE(8),
        .ELEM_WIDTH(8),
        .DATA_WIDTH(64)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .opcode(opcode),
        .vec_a(vec_a),
        .vec_b(vec_b),
        .scalar(scalar),
        .vec_out(vec_out),
        .valid_out(valid_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test stimulus
    integer i;
    integer pass_count, fail_count;
    
    initial begin
        $dumpfile("tb_vector_alu.vcd");
        $dumpvars(0, tb_vector_alu);
        
        pass_count = 0;
        fail_count = 0;
        
        // Initialize
        rst = 1;
        enable = 0;
        opcode = 0;
        vec_a = 0;
        vec_b = 0;
        scalar = 0;
        
        #20;
        rst = 0;
        #10;
        
        // Test ADD operation
        $display("\n=== Testing ADD operation ===");
        opcode = 4'b0000;  // ADD
        vec_a = {8'd1, 8'd2, 8'd3, 8'd4, 8'd5, 8'd6, 8'd7, 8'd8};
        vec_b = {8'd8, 8'd7, 8'd6, 8'd5, 8'd4, 8'd3, 8'd2, 8'd1};
        enable = 1;
        
        wait(valid_out);
        @(posedge clk);
        $display("Result: %h (expected all 9s)", vec_out);
        if (vec_out[7:0] == 8'd9) pass_count++; else fail_count++;
        
        enable = 0;
        #30;
        
        // Test RELU operation
        $display("\n=== Testing RELU operation ===");
        opcode = 4'b0011;  // RELU
        vec_a = {8'sd10, -8'sd5, 8'sd20, -8'sd10, 8'sd30, -8'sd1, 8'sd40, 8'sd0};
        enable = 1;
        
        wait(valid_out);
        @(posedge clk);
        $display("Result: %h", vec_out);
        if (vec_out[7:0] == 8'd0 && vec_out[15:8] == 8'd40) pass_count++; else fail_count++;
        
        enable = 0;
        #30;
        
        // Test MAX operation
        $display("\n=== Testing MAX operation ===");
        opcode = 4'b0100;  // MAX
        vec_a = {8'd10, 8'd20, 8'd30, 8'd40, 8'd50, 8'd60, 8'd70, 8'd80};
        vec_b = {8'd15, 8'd15, 8'd35, 8'd35, 8'd45, 8'd65, 8'd65, 8'd85};
        enable = 1;
        
        wait(valid_out);
        @(posedge clk);
        $display("Result: %h", vec_out);
        if (vec_out[7:0] == 8'd85) pass_count++; else fail_count++;
        
        enable = 0;
        #30;
        
        // Summary
        $display("\n=== Test Summary ===");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED");
        end
        
        #100;
        $finish;
    end

endmodule

