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

module tb_systolic_array;

    reg clk;
    reg rst;
    reg enable;
    reg weight_load_en;
    reg [3:0][7:0] weight_data_in;
    reg [3:0][7:0] act_data_in;
    wire [3:0][31:0] psum_out;
    
    // Instantiate DUT
    systolic_array #(
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ACCUM_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .weight_load_en(weight_load_en),
        .weight_data_in(weight_data_in),
        .act_data_in(act_data_in),
        .psum_out(psum_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test stimulus
    integer i;
    initial begin
        $dumpfile("tb_systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
        
        // Initialize
        rst = 1;
        enable = 0;
        weight_load_en = 0;
        weight_data_in = 0;
        act_data_in = 0;
        
        #20;
        rst = 0;
        
        // Load weights (identity matrix for simple test)
        $display("Loading weights...");
        weight_load_en = 1;
        weight_data_in[0] = 8'd1;
        weight_data_in[1] = 8'd0;
        weight_data_in[2] = 8'd0;
        weight_data_in[3] = 8'd0;
        #10;
        
        weight_data_in[0] = 8'd0;
        weight_data_in[1] = 8'd1;
        weight_data_in[2] = 8'd0;
        weight_data_in[3] = 8'd0;
        #10;
        
        weight_data_in[0] = 8'd0;
        weight_data_in[1] = 8'd0;
        weight_data_in[2] = 8'd1;
        weight_data_in[3] = 8'd0;
        #10;
        
        weight_data_in[0] = 8'd0;
        weight_data_in[1] = 8'd0;
        weight_data_in[2] = 8'd0;
        weight_data_in[3] = 8'd1;
        #10;
        
        weight_load_en = 0;
        
        // Feed activations
        $display("Feeding activations...");
        enable = 1;
        act_data_in[0] = 8'd5;
        act_data_in[1] = 8'd10;
        act_data_in[2] = 8'd15;
        act_data_in[3] = 8'd20;
        
        // Wait for results to propagate through array
        repeat(10) @(posedge clk);
        
        $display("Results:");
        $display("  psum_out[0] = %d (expected 5)", psum_out[0]);
        $display("  psum_out[1] = %d (expected 10)", psum_out[1]);
        $display("  psum_out[2] = %d (expected 15)", psum_out[2]);
        $display("  psum_out[3] = %d (expected 20)", psum_out[3]);
        
        if (psum_out[0] == 5 && psum_out[1] == 10 && 
            psum_out[2] == 15 && psum_out[3] == 20) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
        end
        
        #100;
        $finish;
    end

endmodule

