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
 *-------------------------------------------------------------
 *
 * microwatt_wrapper
 *
 * This wrapper integrates the Microwatt POWER CPU core
 * (converted from VHDL via GHDL+Yosys) with the openframe
 * project interface.
 *
 * This is a minimal "smoke test" wrapper to verify that:
 * 1. VHDL-to-Verilog conversion works
 * 2. The core can be synthesized through OpenLane
 * 3. Mixed-language flow is functional
 *
 * Future work: Connect Wishbone bus, DMI debug interface, etc.
 *
 *-------------------------------------------------------------
 */

module microwatt_wrapper (
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Simple interface matching user_proj_timer for initial integration
    input wb_clk_i,
    input wb_rst_i,

    // IOs
    input  [10:0] io_in,
    output [10:0] io_out,
    output [10:0] io_oeb
);

    // Microwatt core instantiation
    // Minimal connections for initial integration
    
    // Wishbone bus signals - tied off for now
    // TODO: Connect to a proper Wishbone bus fabric
    wire [28:0] wishbone_insn_in_adr = 29'h0;
    wire [63:0] wishbone_insn_in_dat = 64'h0;
    wire [7:0]  wishbone_insn_in_sel = 8'h0;
    wire        wishbone_insn_in_cyc = 1'b0;
    wire        wishbone_insn_in_stb = 1'b0;
    wire        wishbone_insn_in_we = 1'b0;
    wire        wishbone_insn_in_ack = 1'b0;
    wire        wishbone_insn_in_stall = 1'b0;
    
    wire [28:0] wishbone_data_in_adr = 29'h0;
    wire [63:0] wishbone_data_in_dat = 64'h0;
    wire [7:0]  wishbone_data_in_sel = 8'h0;
    wire        wishbone_data_in_cyc = 1'b0;
    wire        wishbone_data_in_stb = 1'b0;
    wire        wishbone_data_in_we = 1'b0;
    wire        wishbone_data_in_ack = 1'b0;
    wire        wishbone_data_in_stall = 1'b0;
    
    wire [28:0] wb_snoop_in_adr = 29'h0;
    wire [63:0] wb_snoop_in_dat = 64'h0;
    wire [7:0]  wb_snoop_in_sel = 8'h0;
    wire        wb_snoop_in_cyc = 1'b0;
    wire        wb_snoop_in_stb = 1'b0;
    wire        wb_snoop_in_we = 1'b0;
    
    // Core outputs
    wire [28:0] wishbone_insn_out_adr;
    wire [63:0] wishbone_insn_out_dat;
    wire [7:0]  wishbone_insn_out_sel;
    wire        wishbone_insn_out_cyc;
    wire        wishbone_insn_out_stb;
    wire        wishbone_insn_out_we;
    
    wire [28:0] wishbone_data_out_adr;
    wire [63:0] wishbone_data_out_dat;
    wire [7:0]  wishbone_data_out_sel;
    wire        wishbone_data_out_cyc;
    wire        wishbone_data_out_stb;
    wire        wishbone_data_out_we;
    
    wire [63:0] dmi_dout;
    wire        dmi_ack;
    wire        msg_out;
    wire        run_out;
    wire        terminated_out;
    
    // Instantiate the Microwatt POWER CPU core
    core microwatt_core_inst (
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .alt_reset(1'b0),
        
        // Timebase control - all zeros for now
        .\tb_ctrl.reset (1'b0),
        .\tb_ctrl.rd_prot (1'b0),
        .\tb_ctrl.freeze (1'b0),
        
        // Instruction Wishbone bus (input)
        .\wishbone_insn_in.dat (wishbone_insn_in_dat),
        .\wishbone_insn_in.ack (wishbone_insn_in_ack),
        .\wishbone_insn_in.stall (wishbone_insn_in_stall),
        
        // Instruction Wishbone bus (output)
        .\wishbone_insn_out.adr (wishbone_insn_out_adr),
        .\wishbone_insn_out.dat (wishbone_insn_out_dat),
        .\wishbone_insn_out.sel (wishbone_insn_out_sel),
        .\wishbone_insn_out.cyc (wishbone_insn_out_cyc),
        .\wishbone_insn_out.stb (wishbone_insn_out_stb),
        .\wishbone_insn_out.we (wishbone_insn_out_we),
        
        // Data Wishbone bus (input)
        .\wishbone_data_in.dat (wishbone_data_in_dat),
        .\wishbone_data_in.ack (wishbone_data_in_ack),
        .\wishbone_data_in.stall (wishbone_data_in_stall),
        
        // Data Wishbone bus (output)
        .\wishbone_data_out.adr (wishbone_data_out_adr),
        .\wishbone_data_out.dat (wishbone_data_out_dat),
        .\wishbone_data_out.sel (wishbone_data_out_sel),
        .\wishbone_data_out.cyc (wishbone_data_out_cyc),
        .\wishbone_data_out.stb (wishbone_data_out_stb),
        .\wishbone_data_out.we (wishbone_data_out_we),
        
        // Snoop bus
        .\wb_snoop_in.adr (wb_snoop_in_adr),
        .\wb_snoop_in.dat (wb_snoop_in_dat),
        .\wb_snoop_in.sel (wb_snoop_in_sel),
        .\wb_snoop_in.cyc (wb_snoop_in_cyc),
        .\wb_snoop_in.stb (wb_snoop_in_stb),
        .\wb_snoop_in.we (wb_snoop_in_we),
        
        // Debug Module Interface (DMI)
        .dmi_addr(4'h0),
        .dmi_din(64'h0),
        .dmi_dout(dmi_dout),
        .dmi_req(1'b0),
        .dmi_wr(1'b0),
        .dmi_ack(dmi_ack),
        
        // Interrupts and messages
        .ext_irq(1'b0),
        .msg_in(1'b0),
        .msg_out(msg_out),
        
        // Status outputs
        .run_out(run_out),
        .terminated_out(terminated_out)
    );
    
    // Connect core status to outputs for visibility
    // Show run_out on io_out[0] as a "heartbeat"
    assign io_out = {10'b0, run_out};
    assign io_oeb = 11'b0;  // All outputs enabled (active low)

endmodule

`default_nettype wire

