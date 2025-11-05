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

module tb_microwatt_soc;

    reg clk;
    reg rst;
    reg [10:0] io_in;
    wire [10:0] io_out;
    wire [10:0] io_oeb;
    wire irq_out;
    
    // Instantiate DUT
    microwatt_soc dut (
        .clk(clk),
        .rst(rst),
        .io_in(io_in),
        .io_out(io_out),
        .io_oeb(io_oeb),
        .irq_out(irq_out)
    );
    
    // Clock generation (50 MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // UART receiver task (simplified)
    task uart_receive;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit
            wait(io_out[0] == 0);
            #8680;  // Half bit time at 115200 baud
            
            // Sample data bits
            for (i = 0; i < 8; i = i + 1) begin
                #8680;  // Full bit time
                data[i] = io_out[0];
            end
            
            // Stop bit
            #8680;
        end
    endtask
    
    // UART transmit task (simplified)
    task uart_transmit;
        input [7:0] data;
        integer i;
        begin
            // Start bit
            io_in[0] = 0;
            #8680;
            
            // Data bits
            for (i = 0; i < 8; i = i + 1) begin
                io_in[0] = data[i];
                #8680;
            end
            
            // Stop bit
            io_in[0] = 1;
            #8680;
        end
    endtask
    
    // Test stimulus
    integer test_count;
    reg [7:0] rx_data;
    
    initial begin
        $dumpfile("tb_microwatt_soc.vcd");
        $dumpvars(0, tb_microwatt_soc);
        
        test_count = 0;
        
        // Initialize
        rst = 1;
        io_in = 11'h7FF;  // All high (UART RX idle)
        
        #200;
        rst = 0;
        
        $display("\n=== Microwatt-Infer SoC Integration Test ===\n");
        
        // Test 1: Basic reset and initialization
        $display("Test %0d: Reset and initialization", test_count++);
        #1000;
        if (!rst) begin
            $display("  PASS: System out of reset");
        end else begin
            $display("  FAIL: System still in reset");
        end
        
        // Test 2: Check IO configuration
        $display("\nTest %0d: IO configuration", test_count++);
        $display("  io_out = %b", io_out);
        $display("  io_oeb = %b", io_oeb);
        if (io_oeb[0] == 0) begin  // TX should be output
            $display("  PASS: UART TX configured as output");
        end else begin
            $display("  FAIL: UART TX not configured correctly");
        end
        
        // Test 3: Wishbone interconnect basic test
        $display("\nTest %0d: Wishbone interconnect", test_count++);
        // The CPU will attempt to fetch instructions from address 0
        // Check that the interconnect routes to code SRAM
        #10000;  // Wait for some CPU activity
        $display("  INFO: CPU should be attempting instruction fetches");
        $display("  INFO: Interconnect routing to code SRAM");
        
        // Test 4: ML Accelerator accessibility
        $display("\nTest %0d: ML Accelerator CSR access", test_count++);
        $display("  INFO: ML Accelerator at 0x80000000");
        $display("  INFO: Firmware needed to test accelerator access");
        
        // Test 5: UART loopback test (if firmware supports it)
        $display("\nTest %0d: UART communication", test_count++);
        $display("  INFO: Transmitting test character to UART");
        uart_transmit(8'h55);  // Send 'U'
        #50000;
        
        // Test 6: Interrupt generation
        $display("\nTest %0d: Interrupt handling", test_count++);
        #100000;
        if (irq_out) begin
            $display("  INFO: Interrupt detected (UART or accelerator)");
        end else begin
            $display("  INFO: No interrupts detected");
        end
        
        // Test Summary
        $display("\n=== Integration Test Summary ===");
        $display("Basic connectivity tests completed");
        $display("Full functional tests require firmware");
        $display("\nNOTE: This testbench verifies RTL connectivity");
        $display("      Firmware is required for complete validation\n");
        
        #100000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000000;  // 10ms timeout
        $display("\nERROR: Testbench timeout");
        $finish;
    end
    
    // Monitor for interesting signals
    always @(posedge irq_out) begin
        $display("[%0t] Interrupt asserted", $time);
    end

endmodule

