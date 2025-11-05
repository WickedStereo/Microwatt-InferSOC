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
 * UART Wishbone Wrapper
 * 
 * Wraps the UART16550 IP core with a standard Wishbone interface
 * Compatible with the SoC interconnect
 */

module uart_wb_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
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
    
    // UART serial interface
    input wire uart_rx_i,
    output wire uart_tx_o,
    
    // Interrupt output
    output wire irq_o
);

    // UART16550 doesn't stall
    assign wb_stall_o = 1'b0;
    
    // UART16550 core (from microwatt/uart16550)
    uart_top uart_inst (
        .wb_clk_i(clk),
        .wb_rst_i(rst),
        
        // Wishbone interface (3-bit address for 8 registers)
        .wb_adr_i(wb_adr_i[4:2]),
        .wb_dat_i(wb_dat_i[7:0]),
        .wb_dat_o(wb_dat_o[7:0]),
        .wb_we_i(wb_we_i),
        .wb_stb_i(wb_stb_i && wb_cyc_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_ack_o(wb_ack_o),
        .wb_sel_i(4'b0001),  // Always byte access
        
        // Serial I/O
        .srx_pad_i(uart_rx_i),
        .stx_pad_o(uart_tx_o),
        
        // Modem signals (not used, tie off)
        .rts_pad_o(),
        .cts_pad_i(1'b0),
        .dtr_pad_o(),
        .dsr_pad_i(1'b0),
        .ri_pad_i(1'b0),
        .dcd_pad_i(1'b0),
        
        // Interrupt
        .int_o(irq_o),
        
        // Baud clock (not used in synchronous mode)
        .baud_o()
    );
    
    // Zero-extend data output
    always @(posedge clk) begin
        if (rst) begin
            wb_dat_o <= 0;
        end else begin
            wb_dat_o[31:8] <= 24'h0;
        end
    end

endmodule

`default_nettype wire

