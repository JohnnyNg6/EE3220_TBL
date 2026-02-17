`timescale 1ns / 1ps

// ============================================================================
// 2. Encoder Module
// ============================================================================
module polar64_crc16_encoder import polar_common_pkg::*; (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [23:0] data_in,
    output logic        done,
    output logic [63:0] codeword
);

    logic [63:0] p2_u_vec;
    logic        p2_valid;
    logic [15:0] debug_crc_val;
    logic [63:0] debug_u_temp;

    // Pipeline Stage 1: Map
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_u_vec <= 0;
            p2_valid <= 0;
        end else begin
            if (start) begin
                int k;
                debug_crc_val = calc_crc16(data_in);
                debug_u_temp = 64'b0; // Initialize all to 0 (Frozen)

                // Map Data (Blue)
                for (k = 0; k < 24; k = k + 1) debug_u_temp[data_pos[k]] = data_in[k];
                // Map CRC (Red)
                for (k = 0; k < 16; k = k + 1) debug_u_temp[crc_pos[k]] = debug_crc_val[k];

                p2_u_vec <= debug_u_temp;
                p2_valid <= 1;
            end else begin
                p2_valid <= 0;
            end
        end
    end

    // Pipeline Stage 2: Transform
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            codeword <= 0;
            done     <= 0;
        end else begin
            if (p2_valid) begin
                codeword <= polar_transform(p2_u_vec);
                done     <= 1;
            end else begin
                done     <= 0;
            end
        end
    end
endmodule
