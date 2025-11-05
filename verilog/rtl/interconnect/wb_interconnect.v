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
 * Wishbone Interconnect Fabric
 * 
 * Connects multiple Wishbone masters to multiple slaves
 * - 2 masters: Microwatt instruction fetch, Microwatt data
 * - 4 slaves: SRAM (code), SRAM (data), ML accelerator, UART
 * 
 * Address Map:
 * 0x0000_0000 - 0x0000_1FFF: Code SRAM (8KB)
 * 0x0000_2000 - 0x0000_2FFF: Weight SRAM (4KB)
 * 0x0000_3000 - 0x0000_3FFF: Activation SRAM (4KB)
 * 0x8000_0000 - 0x8000_0FFF: ML Accelerator CSRs
 * 0x8000_1000 - 0x8000_1FFF: UART peripheral
 * 
 * Arbitration: Priority-based (instruction fetch has priority)
 */

module wb_interconnect #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    
    // Master 0: Instruction fetch
    input wire m0_cyc_i,
    input wire m0_stb_i,
    input wire m0_we_i,
    input wire [ADDR_WIDTH-1:0] m0_adr_i,
    input wire [DATA_WIDTH-1:0] m0_dat_i,
    input wire [3:0] m0_sel_i,
    output reg m0_ack_o,
    output reg [DATA_WIDTH-1:0] m0_dat_o,
    output wire m0_stall_o,
    
    // Master 1: Data access
    input wire m1_cyc_i,
    input wire m1_stb_i,
    input wire m1_we_i,
    input wire [ADDR_WIDTH-1:0] m1_adr_i,
    input wire [DATA_WIDTH-1:0] m1_dat_i,
    input wire [3:0] m1_sel_i,
    output reg m1_ack_o,
    output reg [DATA_WIDTH-1:0] m1_dat_o,
    output wire m1_stall_o,
    
    // Slave 0: Code SRAM
    output reg s0_cyc_o,
    output reg s0_stb_o,
    output reg s0_we_o,
    output reg [ADDR_WIDTH-1:0] s0_adr_o,
    output reg [DATA_WIDTH-1:0] s0_dat_o,
    output reg [3:0] s0_sel_o,
    input wire s0_ack_i,
    input wire [DATA_WIDTH-1:0] s0_dat_i,
    input wire s0_stall_i,
    
    // Slave 1: Data SRAM
    output reg s1_cyc_o,
    output reg s1_stb_o,
    output reg s1_we_o,
    output reg [ADDR_WIDTH-1:0] s1_adr_o,
    output reg [DATA_WIDTH-1:0] s1_dat_o,
    output reg [3:0] s1_sel_o,
    input wire s1_ack_i,
    input wire [DATA_WIDTH-1:0] s1_dat_i,
    input wire s1_stall_i,
    
    // Slave 2: ML Accelerator
    output reg s2_cyc_o,
    output reg s2_stb_o,
    output reg s2_we_o,
    output reg [ADDR_WIDTH-1:0] s2_adr_o,
    output reg [DATA_WIDTH-1:0] s2_dat_o,
    output reg [3:0] s2_sel_o,
    input wire s2_ack_i,
    input wire [DATA_WIDTH-1:0] s2_dat_i,
    input wire s2_stall_i,
    
    // Slave 3: UART
    output reg s3_cyc_o,
    output reg s3_stb_o,
    output reg s3_we_o,
    output reg [ADDR_WIDTH-1:0] s3_adr_o,
    output reg [DATA_WIDTH-1:0] s3_dat_o,
    output reg [3:0] s3_sel_o,
    input wire s3_ack_i,
    input wire [DATA_WIDTH-1:0] s3_dat_i,
    input wire s3_stall_i
);

    // Address decoder
    function [2:0] decode_address;
        input [ADDR_WIDTH-1:0] addr;
        begin
            if (addr < 32'h0000_2000)
                decode_address = 3'd0;  // Code SRAM
            else if (addr < 32'h0000_4000)
                decode_address = 3'd1;  // Data SRAM (weight + activation)
            else if (addr >= 32'h8000_0000 && addr < 32'h8000_1000)
                decode_address = 3'd2;  // ML Accelerator
            else if (addr >= 32'h8000_1000 && addr < 32'h8000_2000)
                decode_address = 3'd3;  // UART
            else
                decode_address = 3'd7;  // Invalid (no slave)
        end
    endfunction
    
    // Arbiter state
    reg [1:0] granted_master;  // Which master currently has access
    reg [2:0] active_slave;    // Which slave is currently active
    
    wire [2:0] m0_slave = decode_address(m0_adr_i);
    wire [2:0] m1_slave = decode_address(m1_adr_i);
    
    // Stall signals: stall if wrong master or slave is stalled
    assign m0_stall_o = (granted_master != 2'd0) || 
                        ((active_slave == 3'd0) && s0_stall_i) ||
                        ((active_slave == 3'd1) && s1_stall_i) ||
                        ((active_slave == 3'd2) && s2_stall_i) ||
                        ((active_slave == 3'd3) && s3_stall_i);
    
    assign m1_stall_o = (granted_master != 2'd1) || 
                        ((active_slave == 3'd0) && s0_stall_i) ||
                        ((active_slave == 3'd1) && s1_stall_i) ||
                        ((active_slave == 3'd2) && s2_stall_i) ||
                        ((active_slave == 3'd3) && s3_stall_i);
    
    always @(posedge clk) begin
        if (rst) begin
            granted_master <= 2'd0;
            active_slave <= 3'd7;
            
            m0_ack_o <= 0;
            m0_dat_o <= 0;
            m1_ack_o <= 0;
            m1_dat_o <= 0;
            
            s0_cyc_o <= 0;
            s0_stb_o <= 0;
            s0_we_o <= 0;
            s0_adr_o <= 0;
            s0_dat_o <= 0;
            s0_sel_o <= 0;
            
            s1_cyc_o <= 0;
            s1_stb_o <= 0;
            s1_we_o <= 0;
            s1_adr_o <= 0;
            s1_dat_o <= 0;
            s1_sel_o <= 0;
            
            s2_cyc_o <= 0;
            s2_stb_o <= 0;
            s2_we_o <= 0;
            s2_adr_o <= 0;
            s2_dat_o <= 0;
            s2_sel_o <= 0;
            
            s3_cyc_o <= 0;
            s3_stb_o <= 0;
            s3_we_o <= 0;
            s3_adr_o <= 0;
            s3_dat_o <= 0;
            s3_sel_o <= 0;
        end else begin
            // Default: clear strobes and acks
            m0_ack_o <= 0;
            m1_ack_o <= 0;
            
            s0_cyc_o <= 0;
            s0_stb_o <= 0;
            s1_cyc_o <= 0;
            s1_stb_o <= 0;
            s2_cyc_o <= 0;
            s2_stb_o <= 0;
            s3_cyc_o <= 0;
            s3_stb_o <= 0;
            
            // Arbiter: Priority to master 0 (instruction fetch)
            if (m0_cyc_i && m0_stb_i) begin
                granted_master <= 2'd0;
                active_slave <= m0_slave;
                
                // Route to appropriate slave
                case (m0_slave)
                    3'd0: begin  // Code SRAM
                        s0_cyc_o <= 1;
                        s0_stb_o <= 1;
                        s0_we_o <= m0_we_i;
                        s0_adr_o <= m0_adr_i;
                        s0_dat_o <= m0_dat_i;
                        s0_sel_o <= m0_sel_i;
                        
                        if (s0_ack_i) begin
                            m0_ack_o <= 1;
                            m0_dat_o <= s0_dat_i;
                        end
                    end
                    
                    3'd1: begin  // Data SRAM
                        s1_cyc_o <= 1;
                        s1_stb_o <= 1;
                        s1_we_o <= m0_we_i;
                        s1_adr_o <= m0_adr_i;
                        s1_dat_o <= m0_dat_i;
                        s1_sel_o <= m0_sel_i;
                        
                        if (s1_ack_i) begin
                            m0_ack_o <= 1;
                            m0_dat_o <= s1_dat_i;
                        end
                    end
                    
                    3'd2: begin  // ML Accelerator
                        s2_cyc_o <= 1;
                        s2_stb_o <= 1;
                        s2_we_o <= m0_we_i;
                        s2_adr_o <= m0_adr_i;
                        s2_dat_o <= m0_dat_i;
                        s2_sel_o <= m0_sel_i;
                        
                        if (s2_ack_i) begin
                            m0_ack_o <= 1;
                            m0_dat_o <= s2_dat_i;
                        end
                    end
                    
                    3'd3: begin  // UART
                        s3_cyc_o <= 1;
                        s3_stb_o <= 1;
                        s3_we_o <= m0_we_i;
                        s3_adr_o <= m0_adr_i;
                        s3_dat_o <= m0_dat_i;
                        s3_sel_o <= m0_sel_i;
                        
                        if (s3_ack_i) begin
                            m0_ack_o <= 1;
                            m0_dat_o <= s3_dat_i;
                        end
                    end
                    
                    default: begin  // Invalid address
                        m0_ack_o <= 1;
                        m0_dat_o <= 32'hDEADBEEF;
                    end
                endcase
            end else if (m1_cyc_i && m1_stb_i) begin
                granted_master <= 2'd1;
                active_slave <= m1_slave;
                
                // Route to appropriate slave
                case (m1_slave)
                    3'd0: begin  // Code SRAM
                        s0_cyc_o <= 1;
                        s0_stb_o <= 1;
                        s0_we_o <= m1_we_i;
                        s0_adr_o <= m1_adr_i;
                        s0_dat_o <= m1_dat_i;
                        s0_sel_o <= m1_sel_i;
                        
                        if (s0_ack_i) begin
                            m1_ack_o <= 1;
                            m1_dat_o <= s0_dat_i;
                        end
                    end
                    
                    3'd1: begin  // Data SRAM
                        s1_cyc_o <= 1;
                        s1_stb_o <= 1;
                        s1_we_o <= m1_we_i;
                        s1_adr_o <= m1_adr_i;
                        s1_dat_o <= m1_dat_i;
                        s1_sel_o <= m1_sel_i;
                        
                        if (s1_ack_i) begin
                            m1_ack_o <= 1;
                            m1_dat_o <= s1_dat_i;
                        end
                    end
                    
                    3'd2: begin  // ML Accelerator
                        s2_cyc_o <= 1;
                        s2_stb_o <= 1;
                        s2_we_o <= m1_we_i;
                        s2_adr_o <= m1_adr_i;
                        s2_dat_o <= m1_dat_i;
                        s2_sel_o <= m1_sel_i;
                        
                        if (s2_ack_i) begin
                            m1_ack_o <= 1;
                            m1_dat_o <= s2_dat_i;
                        end
                    end
                    
                    3'd3: begin  // UART
                        s3_cyc_o <= 1;
                        s3_stb_o <= 1;
                        s3_we_o <= m1_we_i;
                        s3_adr_o <= m1_adr_i;
                        s3_dat_o <= m1_dat_i;
                        s3_sel_o <= m1_sel_i;
                        
                        if (s3_ack_i) begin
                            m1_ack_o <= 1;
                            m1_dat_o <= s3_dat_i;
                        end
                    end
                    
                    default: begin  // Invalid address
                        m1_ack_o <= 1;
                        m1_dat_o <= 32'hDEADBEEF;
                    end
                endcase
            end else begin
                active_slave <= 3'd7;
            end
        end
    end

endmodule

`default_nettype wire

