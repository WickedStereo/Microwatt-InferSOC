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
 * ML Accelerator Top-Level
 * 
 * Integrates:
 * - Systolic array (4x4) for matrix multiplication
 * - Vector ALU for element-wise operations
 * - Special Function Unit (SFU) for Softmax/LayerNorm
 * 
 * Wishbone slave interface for control and data
 * 
 * Memory Map (relative to base address):
 * 0x000-0x003: Control/Status Register
 * 0x004-0x007: Config Register
 * 0x010-0x04F: Systolic Array Data Input (16 words)
 * 0x050-0x08F: Systolic Array Weight Input (16 words)
 * 0x090-0x0CF: Systolic Array Output (16 words)
 * 0x100-0x13F: Vector ALU Input A (16 words)
 * 0x140-0x17F: Vector ALU Input B (16 words)
 * 0x180-0x1BF: Vector ALU Output (16 words)
 * 0x200-0x23F: SFU Input (16 words)
 * 0x240-0x27F: SFU Output (16 words)
 */

module ml_accelerator #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
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
    
    // Interrupt output
    output reg irq_o
);

    // Control/Status register bits
    localparam CSR_SYS_START = 0;
    localparam CSR_SYS_DONE = 1;
    localparam CSR_VALU_START = 2;
    localparam CSR_VALU_DONE = 3;
    localparam CSR_SFU_START = 4;
    localparam CSR_SFU_DONE = 5;
    localparam CSR_IRQ_EN = 8;
    
    // Registers
    reg [DATA_WIDTH-1:0] control_reg;
    reg [DATA_WIDTH-1:0] config_reg;
    
    // Systolic array signals
    reg sys_enable;
    reg sys_weight_load;
    reg [31:0] sys_act_in;      // Flattened: 4 x 8-bit
    reg [31:0] sys_weight_in;   // Flattened: 4 x 8-bit
    wire [127:0] sys_psum_out;  // Flattened: 4 x 32-bit
    
    // Vector ALU signals
    reg valu_enable;
    reg [3:0] valu_opcode;
    reg signed [63:0] valu_vec_a;
    reg signed [63:0] valu_vec_b;
    reg signed [7:0] valu_scalar;
    wire signed [63:0] valu_vec_out;
    wire valu_valid_out;
    
    // SFU signals
    reg sfu_start;
    reg [1:0] sfu_operation;
    reg [3:0] sfu_vec_len;
    reg signed [7:0] sfu_data_in;
    reg sfu_data_in_valid;
    wire signed [7:0] sfu_data_out;
    wire sfu_data_out_valid;
    wire sfu_busy;
    wire sfu_done;
    
    // Internal data buffers
    reg [31:0] sys_data_buf [0:15];
    reg [31:0] sys_weight_buf [0:15];
    reg [31:0] sys_output_buf [0:15];
    reg [31:0] valu_a_buf [0:15];
    reg [31:0] valu_b_buf [0:15];
    reg [31:0] valu_out_buf [0:15];
    reg [31:0] sfu_in_buf [0:15];
    reg [31:0] sfu_out_buf [0:15];
    
    // Instantiate systolic array
    systolic_array #(
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ACCUM_WIDTH(32)
    ) sys_array (
        .clk(clk),
        .rst(rst),
        .enable(sys_enable),
        .weight_load_en(sys_weight_load),
        .weight_data_in(sys_weight_in),
        .act_data_in(sys_act_in),
        .psum_out(sys_psum_out)
    );
    
    // Instantiate vector ALU
    vector_alu #(
        .VEC_SIZE(8),
        .ELEM_WIDTH(8),
        .DATA_WIDTH(64)
    ) valu (
        .clk(clk),
        .rst(rst),
        .enable(valu_enable),
        .opcode(valu_opcode),
        .vec_a(valu_vec_a),
        .vec_b(valu_vec_b),
        .scalar(valu_scalar),
        .vec_out(valu_vec_out),
        .valid_out(valu_valid_out)
    );
    
    // Instantiate SFU
    sfu #(
        .VEC_SIZE(16),
        .DATA_WIDTH(8),
        .ACCUM_WIDTH(32),
        .LUT_SIZE(256)
    ) sfu_inst (
        .clk(clk),
        .rst(rst),
        .start(sfu_start),
        .operation(sfu_operation),
        .vec_len(sfu_vec_len),
        .data_in(sfu_data_in),
        .data_in_valid(sfu_data_in_valid),
        .data_out(sfu_data_out),
        .data_out_valid(sfu_data_out_valid),
        .busy(sfu_busy),
        .done(sfu_done)
    );
    
    // Wishbone bus handling
    wire wb_valid = wb_cyc_i && wb_stb_i;
    assign wb_stall_o = 1'b0;  // No stalling for now
    
    reg wb_ack_r;
    reg [DATA_WIDTH-1:0] wb_dat_r;
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            wb_ack_o <= 0;
            wb_dat_o <= 0;
            control_reg <= 0;
            config_reg <= 0;
            sys_enable <= 0;
            sys_weight_load <= 0;
            valu_enable <= 0;
            sfu_start <= 0;
            sfu_data_in_valid <= 0;
            irq_o <= 0;
            
            for (i = 0; i < 16; i = i + 1) begin
                sys_data_buf[i] <= 0;
                sys_weight_buf[i] <= 0;
                sys_output_buf[i] <= 0;
                valu_a_buf[i] <= 0;
                valu_b_buf[i] <= 0;
                valu_out_buf[i] <= 0;
                sfu_in_buf[i] <= 0;
                sfu_out_buf[i] <= 0;
            end
        end else begin
            // Default: clear one-shot signals
            wb_ack_o <= 0;
            sys_enable <= 0;
            sys_weight_load <= 0;
            valu_enable <= 0;
            sfu_start <= 0;
            sfu_data_in_valid <= 0;
            
            // Update status bits
            if (sys_psum_out[31:0] != 0 || sys_psum_out[63:32] != 0 || 
                sys_psum_out[95:64] != 0 || sys_psum_out[127:96] != 0)
                control_reg[CSR_SYS_DONE] <= 1;
            
            if (valu_valid_out)
                control_reg[CSR_VALU_DONE] <= 1;
            
            if (sfu_done)
                control_reg[CSR_SFU_DONE] <= 1;
            
            // Capture SFU output
            if (sfu_data_out_valid) begin
                // Store SFU output in buffer (streaming)
                // For simplicity, store in first available slot
                sfu_out_buf[0] <= {{24{sfu_data_out[7]}}, sfu_data_out};
            end
            
            // Capture Vector ALU output
            if (valu_valid_out) begin
                valu_out_buf[0] <= valu_vec_out[31:0];
                valu_out_buf[1] <= valu_vec_out[63:32];
            end
            
            // Capture systolic array output
            if (control_reg[CSR_SYS_DONE]) begin
                sys_output_buf[0] <= sys_psum_out[31:0];
                sys_output_buf[1] <= sys_psum_out[63:32];
                sys_output_buf[2] <= sys_psum_out[95:64];
                sys_output_buf[3] <= sys_psum_out[127:96];
            end
            
            // Generate interrupt
            if (control_reg[CSR_IRQ_EN] && 
                (control_reg[CSR_SYS_DONE] || control_reg[CSR_VALU_DONE] || control_reg[CSR_SFU_DONE]))
                irq_o <= 1;
            else
                irq_o <= 0;
            
            // Wishbone read/write
            if (wb_valid && !wb_ack_o) begin
                wb_ack_o <= 1;
                
                if (wb_we_i) begin
                    // Write operation
                    case (wb_adr_i[9:2])
                        8'h00: begin  // Control register
                            control_reg <= wb_dat_i;
                            // Trigger operations
                            if (wb_dat_i[CSR_SYS_START]) begin
                                sys_enable <= 1;
                                // Load activations from buffer
                                sys_act_in[7:0] <= sys_data_buf[0][7:0];
                                sys_act_in[15:8] <= sys_data_buf[1][7:0];
                                sys_act_in[23:16] <= sys_data_buf[2][7:0];
                                sys_act_in[31:24] <= sys_data_buf[3][7:0];
                            end
                            if (wb_dat_i[CSR_VALU_START]) begin
                                valu_enable <= 1;
                                valu_vec_a <= {valu_a_buf[1], valu_a_buf[0]};
                                valu_vec_b <= {valu_b_buf[1], valu_b_buf[0]};
                            end
                            if (wb_dat_i[CSR_SFU_START]) begin
                                sfu_start <= 1;
                            end
                        end
                        
                        8'h01: config_reg <= wb_dat_i;  // Config register
                        
                        // Systolic array data input
                        8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B,
                        8'h0C, 8'h0D, 8'h0E, 8'h0F, 8'h10, 8'h11, 8'h12, 8'h13:
                            sys_data_buf[wb_adr_i[5:2]] <= wb_dat_i;
                        
                        // Systolic array weight input
                        8'h14, 8'h15, 8'h16, 8'h17, 8'h18, 8'h19, 8'h1A, 8'h1B,
                        8'h1C, 8'h1D, 8'h1E, 8'h1F, 8'h20, 8'h21, 8'h22, 8'h23: begin
                            sys_weight_buf[wb_adr_i[5:2] - 6'h14] <= wb_dat_i;
                            // Trigger weight load
                            sys_weight_load <= 1;
                            sys_weight_in[7:0] <= wb_dat_i[7:0];
                            sys_weight_in[15:8] <= wb_dat_i[15:8];
                            sys_weight_in[23:16] <= wb_dat_i[23:16];
                            sys_weight_in[31:24] <= wb_dat_i[31:24];
                        end
                        
                        // Vector ALU input A
                        8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
                        8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F:
                            valu_a_buf[wb_adr_i[5:2] - 6'h40] <= wb_dat_i;
                        
                        // Vector ALU input B
                        8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57,
                        8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C, 8'h5D, 8'h5E, 8'h5F:
                            valu_b_buf[wb_adr_i[5:2] - 6'h50] <= wb_dat_i;
                        
                        // SFU input
                        8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87,
                        8'h88, 8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F: begin
                            sfu_in_buf[wb_adr_i[5:2] - 7'h80] <= wb_dat_i;
                            // Stream to SFU
                            sfu_data_in <= wb_dat_i[7:0];
                            sfu_data_in_valid <= 1;
                        end
                        
                        default: ;
                    endcase
                end else begin
                    // Read operation
                    case (wb_adr_i[9:2])
                        8'h00: wb_dat_o <= control_reg;
                        8'h01: wb_dat_o <= config_reg;
                        
                        // Systolic array output
                        8'h24, 8'h25, 8'h26, 8'h27, 8'h28, 8'h29, 8'h2A, 8'h2B,
                        8'h2C, 8'h2D, 8'h2E, 8'h2F, 8'h30, 8'h31, 8'h32, 8'h33:
                            wb_dat_o <= sys_output_buf[wb_adr_i[5:2] - 6'h24];
                        
                        // Vector ALU output
                        8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67,
                        8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6F:
                            wb_dat_o <= valu_out_buf[wb_adr_i[5:2] - 7'h60];
                        
                        // SFU output
                        8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
                        8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F:
                            wb_dat_o <= sfu_out_buf[wb_adr_i[5:2] - 7'h90];
                        
                        default: wb_dat_o <= 32'h0;
                    endcase
                end
            end
        end
    end
    
    // Config register fields
    assign valu_opcode = config_reg[3:0];
    assign valu_scalar = config_reg[15:8];
    assign sfu_operation = config_reg[17:16];
    assign sfu_vec_len = config_reg[21:18];

endmodule

`default_nettype wire

