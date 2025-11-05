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
 * Microwatt-Infer SoC Top-Level
 * 
 * Integrates:
 * - Microwatt POWER CPU core (64-bit)
 * - ML accelerator (systolic array, vector ALU, SFU)
 * - SRAM memory (code + data, 8KB total)
 * - UART for I/O
 * - Wishbone interconnect fabric
 * 
 * Memory Map:
 * 0x0000_0000 - 0x0000_1FFF: Code SRAM (8KB)
 * 0x0000_2000 - 0x0000_2FFF: Weight SRAM (4KB)
 * 0x0000_3000 - 0x0000_3FFF: Activation SRAM (4KB)
 * 0x8000_0000 - 0x8000_0FFF: ML Accelerator CSRs
 * 0x8000_1000 - 0x8000_1FFF: UART peripheral
 */

module microwatt_soc #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
`ifdef USE_POWER_PINS
    inout vccd1,   // User area 1 1.8V supply
    inout vssd1,   // User area 1 digital ground
`endif

    input wire clk,
    input wire rst,
    
    // GPIO/IO interface
    input wire [10:0] io_in,
    output wire [10:0] io_out,
    output wire [10:0] io_oeb,
    
    // Interrupt output
    output wire irq_out
);

    // Microwatt Wishbone buses (64-bit data, 29-bit address)
    // Note: Microwatt uses 64-bit data width, we'll adapt to 32-bit
    
    // Instruction Wishbone bus
    wire [28:0] wb_insn_adr;
    wire [63:0] wb_insn_dat_write;
    wire [7:0] wb_insn_sel;
    wire wb_insn_cyc;
    wire wb_insn_stb;
    wire wb_insn_we;
    wire [63:0] wb_insn_dat_read;
    wire wb_insn_ack;
    wire wb_insn_stall;
    
    // Data Wishbone bus
    wire [28:0] wb_data_adr;
    wire [63:0] wb_data_dat_write;
    wire [7:0] wb_data_sel;
    wire wb_data_cyc;
    wire wb_data_stb;
    wire wb_data_we;
    wire [63:0] wb_data_dat_read;
    wire wb_data_ack;
    wire wb_data_stall;
    
    // Interconnect buses (32-bit)
    wire [ADDR_WIDTH-1:0] m0_adr, m1_adr;
    wire [DATA_WIDTH-1:0] m0_dat_w, m1_dat_w;
    wire [DATA_WIDTH-1:0] m0_dat_r, m1_dat_r;
    wire [3:0] m0_sel, m1_sel;
    wire m0_cyc, m0_stb, m0_we, m0_ack, m0_stall;
    wire m1_cyc, m1_stb, m1_we, m1_ack, m1_stall;
    
    // Slave buses
    wire [ADDR_WIDTH-1:0] s0_adr, s1_adr, s2_adr, s3_adr;
    wire [DATA_WIDTH-1:0] s0_dat_w, s1_dat_w, s2_dat_w, s3_dat_w;
    wire [DATA_WIDTH-1:0] s0_dat_r, s1_dat_r, s2_dat_r, s3_dat_r;
    wire [3:0] s0_sel, s1_sel, s2_sel, s3_sel;
    wire s0_cyc, s0_stb, s0_we, s0_ack, s0_stall;
    wire s1_cyc, s1_stb, s1_we, s1_ack, s1_stall;
    wire s2_cyc, s2_stb, s2_we, s2_ack, s2_stall;
    wire s3_cyc, s3_stb, s3_we, s3_ack, s3_stall;
    
    // SRAM interface signals
    wire [3:0] sram0_clk0, sram0_csb0, sram0_web0;
    wire [3:0][3:0] sram0_wmask0;
    wire [3:0][8:0] sram0_addr0;
    wire [3:0][31:0] sram0_din0, sram0_dout0;
    wire [3:0] sram0_clk1, sram0_csb1;
    wire [3:0][8:0] sram0_addr1;
    wire [3:0][31:0] sram0_dout1;
    
    wire [3:0] sram1_clk0, sram1_csb0, sram1_web0;
    wire [3:0][3:0] sram1_wmask0;
    wire [3:0][8:0] sram1_addr0;
    wire [3:0][31:0] sram1_din0, sram1_dout0;
    wire [3:0] sram1_clk1, sram1_csb1;
    wire [3:0][8:0] sram1_addr1;
    wire [3:0][31:0] sram1_dout1;
    
    // UART signals
    wire uart_tx, uart_rx;
    wire uart_irq;
    
    // ML accelerator interrupt
    wire ml_accel_irq;
    
    // Combine interrupts
    assign irq_out = uart_irq | ml_accel_irq;
    
    // Adapt Microwatt 64-bit buses to 32-bit interconnect
    // We'll use lower 32 bits for now (can be extended later)
    assign m0_adr = {3'b000, wb_insn_adr};
    assign m0_dat_w = wb_insn_dat_write[31:0];
    assign m0_sel = wb_insn_sel[3:0];
    assign m0_cyc = wb_insn_cyc;
    assign m0_stb = wb_insn_stb;
    assign m0_we = wb_insn_we;
    assign wb_insn_dat_read = {32'h0, m0_dat_r};
    assign wb_insn_ack = m0_ack;
    assign wb_insn_stall = m0_stall;
    
    assign m1_adr = {3'b000, wb_data_adr};
    assign m1_dat_w = wb_data_dat_write[31:0];
    assign m1_sel = wb_data_sel[3:0];
    assign m1_cyc = wb_data_cyc;
    assign m1_stb = wb_data_stb;
    assign m1_we = wb_data_we;
    assign wb_data_dat_read = {32'h0, m1_dat_r};
    assign wb_data_ack = m1_ack;
    assign wb_data_stall = m1_stall;
    
    // Instantiate Microwatt CPU core
    core microwatt_core (
        .clk(clk),
        .rst(rst),
        .alt_reset(1'b0),
        
        // Timebase control
        .\tb_ctrl.reset (1'b0),
        .\tb_ctrl.rd_prot (1'b0),
        .\tb_ctrl.freeze (1'b0),
        
        // Instruction Wishbone bus
        .\wishbone_insn_in.dat (wb_insn_dat_read),
        .\wishbone_insn_in.ack (wb_insn_ack),
        .\wishbone_insn_in.stall (wb_insn_stall),
        .\wishbone_insn_out.adr (wb_insn_adr),
        .\wishbone_insn_out.dat (wb_insn_dat_write),
        .\wishbone_insn_out.sel (wb_insn_sel),
        .\wishbone_insn_out.cyc (wb_insn_cyc),
        .\wishbone_insn_out.stb (wb_insn_stb),
        .\wishbone_insn_out.we (wb_insn_we),
        
        // Data Wishbone bus
        .\wishbone_data_in.dat (wb_data_dat_read),
        .\wishbone_data_in.ack (wb_data_ack),
        .\wishbone_data_in.stall (wb_data_stall),
        .\wishbone_data_out.adr (wb_data_adr),
        .\wishbone_data_out.dat (wb_data_dat_write),
        .\wishbone_data_out.sel (wb_data_sel),
        .\wishbone_data_out.cyc (wb_data_cyc),
        .\wishbone_data_out.stb (wb_data_stb),
        .\wishbone_data_out.we (wb_data_we),
        
        // Snoop bus (not used)
        .\wb_snoop_in.adr (29'h0),
        .\wb_snoop_in.dat (64'h0),
        .\wb_snoop_in.sel (8'h0),
        .\wb_snoop_in.cyc (1'b0),
        .\wb_snoop_in.stb (1'b0),
        .\wb_snoop_in.we (1'b0),
        
        // DMI debug interface (not used)
        .dmi_addr(4'h0),
        .dmi_din(64'h0),
        .dmi_dout(),
        .dmi_req(1'b0),
        .dmi_wr(1'b0),
        .dmi_ack(),
        
        // Interrupts
        .ext_irq(irq_out),
        .msg_in(1'b0),
        .msg_out(),
        
        // Status
        .run_out(),
        .terminated_out()
    );
    
    // Instantiate Wishbone interconnect
    wb_interconnect #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) interconnect (
        .clk(clk),
        .rst(rst),
        
        // Master 0: Instruction fetch
        .m0_cyc_i(m0_cyc),
        .m0_stb_i(m0_stb),
        .m0_we_i(m0_we),
        .m0_adr_i(m0_adr),
        .m0_dat_i(m0_dat_w),
        .m0_sel_i(m0_sel),
        .m0_ack_o(m0_ack),
        .m0_dat_o(m0_dat_r),
        .m0_stall_o(m0_stall),
        
        // Master 1: Data access
        .m1_cyc_i(m1_cyc),
        .m1_stb_i(m1_stb),
        .m1_we_i(m1_we),
        .m1_adr_i(m1_adr),
        .m1_dat_i(m1_dat_w),
        .m1_sel_i(m1_sel),
        .m1_ack_o(m1_ack),
        .m1_dat_o(m1_dat_r),
        .m1_stall_o(m1_stall),
        
        // Slave 0: Code SRAM
        .s0_cyc_o(s0_cyc),
        .s0_stb_o(s0_stb),
        .s0_we_o(s0_we),
        .s0_adr_o(s0_adr),
        .s0_dat_o(s0_dat_w),
        .s0_sel_o(s0_sel),
        .s0_ack_i(s0_ack),
        .s0_dat_i(s0_dat_r),
        .s0_stall_i(s0_stall),
        
        // Slave 1: Data SRAM
        .s1_cyc_o(s1_cyc),
        .s1_stb_o(s1_stb),
        .s1_we_o(s1_we),
        .s1_adr_o(s1_adr),
        .s1_dat_o(s1_dat_w),
        .s1_sel_o(s1_sel),
        .s1_ack_i(s1_ack),
        .s1_dat_i(s1_dat_r),
        .s1_stall_i(s1_stall),
        
        // Slave 2: ML Accelerator
        .s2_cyc_o(s2_cyc),
        .s2_stb_o(s2_stb),
        .s2_we_o(s2_we),
        .s2_adr_o(s2_adr),
        .s2_dat_o(s2_dat_w),
        .s2_sel_o(s2_sel),
        .s2_ack_i(s2_ack),
        .s2_dat_i(s2_dat_r),
        .s2_stall_i(s2_stall),
        
        // Slave 3: UART
        .s3_cyc_o(s3_cyc),
        .s3_stb_o(s3_stb),
        .s3_we_o(s3_we),
        .s3_adr_o(s3_adr),
        .s3_dat_o(s3_dat_w),
        .s3_sel_o(s3_sel),
        .s3_ack_i(s3_ack),
        .s3_dat_i(s3_dat_r),
        .s3_stall_i(s3_stall)
    );
    
    // Instantiate SRAM controller for code memory
    sram_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRAM_ADDR_WIDTH(9),
        .NUM_SRAMS(4)
    ) sram_ctrl_code (
        .clk(clk),
        .rst(rst),
        
        .wb_cyc_i(s0_cyc),
        .wb_stb_i(s0_stb),
        .wb_we_i(s0_we),
        .wb_adr_i(s0_adr),
        .wb_dat_i(s0_dat_w),
        .wb_sel_i(s0_sel),
        .wb_ack_o(s0_ack),
        .wb_dat_o(s0_dat_r),
        .wb_stall_o(s0_stall),
        
        .sram_clk0(sram0_clk0),
        .sram_csb0(sram0_csb0),
        .sram_web0(sram0_web0),
        .sram_wmask0(sram0_wmask0),
        .sram_addr0(sram0_addr0),
        .sram_din0(sram0_din0),
        .sram_dout0(sram0_dout0),
        .sram_clk1(sram0_clk1),
        .sram_csb1(sram0_csb1),
        .sram_addr1(sram0_addr1),
        .sram_dout1(sram0_dout1)
    );
    
    // Instantiate SRAM controller for data memory
    sram_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SRAM_ADDR_WIDTH(9),
        .NUM_SRAMS(4)
    ) sram_ctrl_data (
        .clk(clk),
        .rst(rst),
        
        .wb_cyc_i(s1_cyc),
        .wb_stb_i(s1_stb),
        .wb_we_i(s1_we),
        .wb_adr_i(s1_adr),
        .wb_dat_i(s1_dat_w),
        .wb_sel_i(s1_sel),
        .wb_ack_o(s1_ack),
        .wb_dat_o(s1_dat_r),
        .wb_stall_o(s1_stall),
        
        .sram_clk0(sram1_clk0),
        .sram_csb0(sram1_csb0),
        .sram_web0(sram1_web0),
        .sram_wmask0(sram1_wmask0),
        .sram_addr0(sram1_addr0),
        .sram_din0(sram1_din0),
        .sram_dout0(sram1_dout0),
        .sram_clk1(sram1_clk1),
        .sram_csb1(sram1_csb1),
        .sram_addr1(sram1_addr1),
        .sram_dout1(sram1_dout1)
    );
    
    // Instantiate ML accelerator
    ml_accelerator #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(10)
    ) ml_accel (
        .clk(clk),
        .rst(rst),
        
        .wb_cyc_i(s2_cyc),
        .wb_stb_i(s2_stb),
        .wb_we_i(s2_we),
        .wb_adr_i(s2_adr[9:0]),
        .wb_dat_i(s2_dat_w),
        .wb_sel_i(s2_sel),
        .wb_ack_o(s2_ack),
        .wb_dat_o(s2_dat_r),
        .wb_stall_o(s2_stall),
        
        .irq_o(ml_accel_irq)
    );
    
    // Instantiate UART
    uart_wb_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uart (
        .clk(clk),
        .rst(rst),
        
        .wb_cyc_i(s3_cyc),
        .wb_stb_i(s3_stb),
        .wb_we_i(s3_we),
        .wb_adr_i(s3_adr),
        .wb_dat_i(s3_dat_w),
        .wb_sel_i(s3_sel),
        .wb_ack_o(s3_ack),
        .wb_dat_o(s3_dat_r),
        .wb_stall_o(s3_stall),
        
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .irq_o(uart_irq)
    );
    
    // GPIO mapping
    // io_in[0]: UART RX
    // io_out[0]: UART TX
    // io_out[1]: Status LED (CPU running)
    assign uart_rx = io_in[0];
    assign io_out = {9'b0, 1'b1, uart_tx};  // TX + status
    assign io_oeb = 11'b11111111100;  // TX and status are outputs

    // Note: SRAM macros need to be instantiated separately in synthesis
    // For now, this is a structural placeholder
    // In actual implementation, replace with sky130_sram_2kbyte_1rw1r_32x512_8

endmodule

`default_nettype wire

