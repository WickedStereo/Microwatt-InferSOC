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

module tb_sfu;

    reg clk;
    reg rst;
    reg start;
    reg [1:0] operation;
    reg [3:0] vec_len;
    reg signed [7:0] data_in;
    reg data_in_valid;
    wire signed [7:0] data_out;
    wire data_out_valid;
    wire busy;
    wire done;
    
    // Instantiate DUT
    sfu #(
        .VEC_SIZE(16),
        .DATA_WIDTH(8),
        .ACCUM_WIDTH(32),
        .LUT_SIZE(256)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .operation(operation),
        .vec_len(vec_len),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .busy(busy),
        .done(done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test stimulus
    integer i;
    reg signed [7:0] test_data [0:7];
    
    initial begin
        $dumpfile("tb_sfu.vcd");
        $dumpvars(0, tb_sfu);
        
        // Initialize
        rst = 1;
        start = 0;
        operation = 0;
        vec_len = 0;
        data_in = 0;
        data_in_valid = 0;
        
        #20;
        rst = 0;
        #10;
        
        // Prepare test data
        test_data[0] = 8'd10;
        test_data[1] = 8'd20;
        test_data[2] = 8'd30;
        test_data[3] = 8'd40;
        test_data[4] = 8'd50;
        test_data[5] = 8'd60;
        test_data[6] = 8'd70;
        test_data[7] = 8'd80;
        
        // Test Softmax operation
        $display("\n=== Testing Softmax operation ===");
        operation = 2'b00;  // Softmax
        vec_len = 4'd8;
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Feed input data
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            data_in = test_data[i];
            data_in_valid = 1;
        end
        @(posedge clk);
        data_in_valid = 0;
        
        // Wait for completion
        wait(done);
        $display("Softmax completed");
        
        // Collect results
        $display("Softmax results:");
        i = 0;
        while (i < 8) begin
            @(posedge clk);
            if (data_out_valid) begin
                $display("  Output[%0d] = %d", i, data_out);
                i = i + 1;
            end
        end
        
        #100;
        
        // Test LayerNorm operation
        $display("\n=== Testing LayerNorm operation ===");
        rst = 1;
        #20;
        rst = 0;
        #10;
        
        operation = 2'b01;  // LayerNorm
        vec_len = 4'd8;
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Feed input data
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            data_in = test_data[i];
            data_in_valid = 1;
        end
        @(posedge clk);
        data_in_valid = 0;
        
        // Wait for completion
        wait(done);
        $display("LayerNorm completed");
        
        // Collect results
        $display("LayerNorm results:");
        i = 0;
        while (i < 8) begin
            @(posedge clk);
            if (data_out_valid) begin
                $display("  Output[%0d] = %d", i, data_out);
                i = i + 1;
            end
        end
        
        #100;
        $display("\nSFU tests completed");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule

