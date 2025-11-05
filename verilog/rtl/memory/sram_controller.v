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
 * SRAM Controller for SKY130 SRAM Macros
 * 
 * Controls SKY130 2KB SRAM macros (sky130_sram_2kbyte_1rw1r_32x512_8)
 * - Wishbone slave interface
 * - Handles address decoding and timing
 * - Supports single 1RW1R port (one read/write, one read-only)
 * 
 * Memory organization: 32-bit words x 512 depth = 2KB per SRAM
 * Multiple SRAM instances can be used for larger memory
 */

module sram_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter SRAM_ADDR_WIDTH = 9,  // 512 words
    parameter NUM_SRAMS = 4          // 4x2KB = 8KB total
) (
    input wire clk,
    input wire rst,
    
    // Wishbone slave interface
    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire wb_we_i,
    input wire [ADDR_WIDTH-1:0] wb_adr_i,
    input wire [DATA_WIDTH-1:0] wb_dat_i,
    input wire [3:0] wb_sel_i,
    
    output reg wb_ack_o,
    output reg [DATA_WIDTH-1:0] wb_dat_o,
    output wire wb_stall_o,
    
    // SRAM interface signals (one per SRAM instance)
    output reg [NUM_SRAMS-1:0] sram_clk0,
    output reg [NUM_SRAMS-1:0] sram_csb0,
    output reg [NUM_SRAMS-1:0] sram_web0,
    output reg [NUM_SRAMS-1:0][3:0] sram_wmask0,
    output reg [NUM_SRAMS-1:0][SRAM_ADDR_WIDTH-1:0] sram_addr0,
    output reg [NUM_SRAMS-1:0][DATA_WIDTH-1:0] sram_din0,
    input wire [NUM_SRAMS-1:0][DATA_WIDTH-1:0] sram_dout0,
    
    // Read-only port (port 1) - optional, can be tied off
    output reg [NUM_SRAMS-1:0] sram_clk1,
    output reg [NUM_SRAMS-1:0] sram_csb1,
    output reg [NUM_SRAMS-1:0][SRAM_ADDR_WIDTH-1:0] sram_addr1,
    input wire [NUM_SRAMS-1:0][DATA_WIDTH-1:0] sram_dout1
);

    // Wishbone is not stalled
    assign wb_stall_o = 1'b0;
    
    // Address decoding
    // Lower bits are word offset within SRAM
    // Upper bits select which SRAM
    wire [SRAM_ADDR_WIDTH-1:0] sram_word_addr = wb_adr_i[SRAM_ADDR_WIDTH+1:2];
    wire [1:0] sram_select = wb_adr_i[SRAM_ADDR_WIDTH+3:SRAM_ADDR_WIDTH+2];
    
    wire wb_valid = wb_cyc_i && wb_stb_i;
    
    reg [1:0] sram_select_r;
    reg wb_we_r;
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            wb_ack_o <= 0;
            wb_dat_o <= 0;
            sram_select_r <= 0;
            wb_we_r <= 0;
            
            for (i = 0; i < NUM_SRAMS; i = i + 1) begin
                sram_clk0[i] <= 0;
                sram_csb0[i] <= 1;  // Chip select is active low
                sram_web0[i] <= 1;  // Write enable is active low
                sram_wmask0[i] <= 4'b0000;
                sram_addr0[i] <= 0;
                sram_din0[i] <= 0;
                sram_clk1[i] <= 0;
                sram_csb1[i] <= 1;
                sram_addr1[i] <= 0;
            end
        end else begin
            // Default: deassert chip selects
            for (i = 0; i < NUM_SRAMS; i = i + 1) begin
                sram_csb0[i] <= 1;
                sram_csb1[i] <= 1;
                sram_clk0[i] <= clk;
                sram_clk1[i] <= clk;
            end
            
            // Pipeline stage 1: Initiate SRAM access
            if (wb_valid && !wb_ack_o) begin
                sram_select_r <= sram_select;
                wb_we_r <= wb_we_i;
                
                // Select the appropriate SRAM
                if (sram_select < NUM_SRAMS) begin
                    sram_csb0[sram_select] <= 0;  // Assert chip select
                    sram_addr0[sram_select] <= sram_word_addr;
                    
                    if (wb_we_i) begin
                        // Write operation
                        sram_web0[sram_select] <= 0;  // Assert write enable
                        sram_din0[sram_select] <= wb_dat_i;
                        sram_wmask0[sram_select] <= wb_sel_i;
                    end else begin
                        // Read operation
                        sram_web0[sram_select] <= 1;  // Deassert write enable
                        sram_wmask0[sram_select] <= 4'b1111;
                    end
                end
                
                // Acknowledge immediately (SRAM is synchronous, 1-cycle)
                wb_ack_o <= 1;
            end else begin
                wb_ack_o <= 0;
                
                // Deassert write enable after write
                for (i = 0; i < NUM_SRAMS; i = i + 1) begin
                    sram_web0[i] <= 1;
                end
            end
            
            // Pipeline stage 2: Capture read data
            if (wb_ack_o && !wb_we_r) begin
                if (sram_select_r < NUM_SRAMS) begin
                    wb_dat_o <= sram_dout0[sram_select_r];
                end else begin
                    wb_dat_o <= 32'h0;
                end
            end
        end
    end

endmodule

`default_nettype wire

