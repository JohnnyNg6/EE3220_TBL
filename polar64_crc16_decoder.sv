`timescale 1ns / 1ps

// ============================================================================
// 3. Decoder Module (Strict Bounded-Distance Implementation)
// ============================================================================
module polar64_crc16_decoder import polar_common_pkg::*; (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] rx,
    output logic        done,
    output logic [23:0] data_out,
    output logic        valid
);

    logic [63:0] u_hat;
    logic [63:0] codeword_hat; // Re-encoded codeword
    logic [23:0] decoded_data;
    logic [15:0] decoded_crc;
    logic [15:0] calc_crc;
    
    logic        decoding_active;
    logic [3:0]  cycle_count;
    int          hamming_dist;

    typedef int llr_t;
    
    // SC Decoder Function (Behavioral Model)
    function automatic logic [63:0] sc_decode(input logic [63:0] rx_bits);
        llr_t llrs [0:6][0:63];         
        logic [0:63] partial_sums [0:6][0:63]; 
        logic [63:0] u_result;
        
        int s, i, j, k, bit_idx;
        int stage_size, sub_block, offset;
        llr_t a, b, f_val, g_val;
        int abs_a, abs_b, min_val;
        logic u_prev, u_l, u_r;
        
        begin
            // Initialize LLRs
            for (i = 0; i < 64; i = i + 1) begin
                llrs[0][i] = (rx_bits[i] == 1'b0) ? 10 : -10;
            end

            // SC Loop
            for (bit_idx = 0; bit_idx < 64; bit_idx = bit_idx + 1) begin
                
                // --- Step A: Calculate LLRs (Top-down) ---
                for (s = 0; s < 6; s = s + 1) begin
                    stage_size = 64 >> s;
                    sub_block = stage_size / 2;
                    
                    if ((bit_idx % sub_block) == 0) begin
                        for (j = 0; j < (1 << s); j = j + 1) begin
                            offset = j * stage_size;
                            if (bit_idx >= offset && bit_idx < (offset + stage_size)) begin
                                for (k = 0; k < sub_block; k = k + 1) begin
                                    a = llrs[s][offset + k];
                                    b = llrs[s][offset + sub_block + k];
                                    
                                    // f operation
                                    abs_a = (a > 0) ? a : -a;
                                    abs_b = (b > 0) ? b : -b;
                                    min_val = (abs_a < abs_b) ? abs_a : abs_b;
                                    if ((a > 0 && b > 0) || (a < 0 && b < 0)) f_val = min_val;
                                    else f_val = -min_val;

                                    // g operation
                                    u_prev = partial_sums[s+1][offset + k]; 
                                    g_val = (u_prev == 0) ? (b + a) : (b - a);

                                    llrs[s+1][offset + k] = f_val;
                                    llrs[s+1][offset + sub_block + k] = g_val;
                                end
                            end
                        end
                    end
                end

                // --- Step B: Decision ---
                if (is_frozen(bit_idx)) begin
                    u_result[bit_idx] = 1'b0; // Frozen bits are always 0
                end else begin
                    u_result[bit_idx] = (llrs[6][bit_idx] >= 0) ? 1'b0 : 1'b1;
                end
                
                // --- Step C: Update Partial Sums (Bottom-up) ---
                partial_sums[6][bit_idx] = u_result[bit_idx];
                
                for (s = 5; s >= 0; s = s - 1) begin
                    stage_size = 64 >> s;
                    sub_block = stage_size / 2;
                    
                    if (((bit_idx + 1) % sub_block) == 0) begin
                        for (j = 0; j < (1 << s); j = j + 1) begin
                            offset = j * stage_size;
                            if (bit_idx >= offset && bit_idx < (offset + stage_size)) begin
                                for (k = 0; k < sub_block; k = k + 1) begin
                                    u_l = partial_sums[s+1][offset + k];
                                    u_r = partial_sums[s+1][offset + sub_block + k];
                                    partial_sums[s][offset + k] = u_l ^ u_r;
                                    partial_sums[s][offset + sub_block + k] = u_r;
                                end
                            end
                        end
                    end
                end
            end
            return u_result;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 0;
            valid <= 0;
            data_out <= 0;
            decoding_active <= 0;
            cycle_count <= 0;
        end else begin
            done <= 0; 
            if (start) begin
                decoding_active <= 1;
                cycle_count <= 0;
            end
            if (decoding_active) begin
                cycle_count <= cycle_count + 1;
                
                // Simulate processing time (within 12 cycles)
                if (cycle_count == 2) begin
                    // 1. SC Decoding
                    u_hat = sc_decode(rx);
                    
                    // 2. Re-Encode to get the candidate codeword
                    codeword_hat = polar_transform(u_hat);

                    // 3. Calculate Hamming Distance (Strict Radius Check)
                    hamming_dist = calc_hamming_dist(rx, codeword_hat);

                    // 4. Extract Data and CRC
                    for (int k = 0; k < 24; k = k + 1) decoded_data[k] = u_hat[data_pos[k]];
                    for (int k = 0; k < 16; k = k + 1) decoded_crc[k] = u_hat[crc_pos[k]];

                    // 5. Check CRC
                    calc_crc = calc_crc16(decoded_data);

                    // 6. Final Decision Logic
                    // Must satisfy BOTH:
                    // A. CRC Matches
                    // B. Hamming Distance <= 3 (Bounded Distance Rule)
                    if ((calc_crc == decoded_crc) && (hamming_dist <= 3)) begin
                        valid <= 1;
                        data_out <= decoded_data;
                    end else begin
                        valid <= 0; // Reject packet
                        data_out <= 0; 
                    end
                    
                    done <= 1;
                    decoding_active <= 0;
                end
            end
        end
    end
endmodule
