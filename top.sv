`timescale 1ns / 1ps

// ============================================================================
// 1. Package: Parameters, Mapping, and Shared Functions
// ============================================================================
package polar_common_pkg;

    // Code Parameters
    parameter int N = 64;
    parameter int K_TOTAL = 40; // 24 Data + 16 CRC

    // ========================================================================
    // ROBUST MAPPING STRATEGY (Reed-Muller Weight Based)
    // Objective: Minimum Distance (d_min) >= 8
    // Rule: All chosen indices must have Hamming Weight >= 3.
    // ========================================================================

    // [Blue Bars] Data Positions (24 bits)
    const int data_pos [0:23] = '{
        63, // Weight 6
        62, 61, 59, 55, 47, 31, // Weight 5
        60, 58, 57, 54, 53, 51, 46, 45, 43, 39, 30, 29, 27, 23, 15, // Weight 4
        56, 52 // Best of Weight 3 (High indices)
    };

    // [Red Bars] CRC Positions (16 bits)
    const int crc_pos [0:15] = '{
        50, 49, 44, 42, 41, 38, 37, 35, 
        28, 26, 25, 22, 21, 19, 14, 13
    };

    // Helper to check if an index is frozen (Fixed to 0)
    function automatic bit is_frozen(input int idx);
        int i;
        for (i = 0; i < 24; i++) if (data_pos[i] == idx) return 0;
        for (i = 0; i < 16; i++) if (crc_pos[i] == idx) return 0;
        return 1; // It is frozen
    endfunction

    // CRC-16-CCITT Calculation Function
    function automatic logic [15:0] calc_crc16(input logic [23:0] data);
        logic [15:0] crc;
        int i;
        begin
            crc = 16'h0000; 
            for (i = 23; i >= 0; i = i - 1) begin
                if (crc[15] ^ data[i])
                    crc = (crc << 1) ^ 16'h1021;
                else
                    crc = crc << 1;
            end
            return crc;
        end
    endfunction

    // Polar Transform Function (Shared by Encoder and Decoder for Re-encoding)
    // No Bit Reversal per spec
    function automatic logic [63:0] polar_transform(input logic [63:0] u);
        logic [63:0] x;
        int step_size, half_size, j, s, i;
        begin
            x = u;
            // N=64, 6 stages. 
            for (s = 0; s < 6; s = s + 1) begin
                step_size = 1 << (s + 1);
                half_size = 1 << s;
                
                for (i = 0; i < 64; i = i + step_size) begin
                    for (j = 0; j < half_size; j = j + 1) begin
                        // Butterfly: v[i+j] = v[i+j] XOR v[i+j+half]
                        x[i + j] = x[i + j] ^ x[i + j + half_size];
                    end
                end
            end
            return x;
        end
    endfunction

    // Hamming Distance Calculation
    function automatic int calc_hamming_dist(input logic [63:0] v1, input logic [63:0] v2);
        logic [63:0] diff;
        int distance_val, i;
        begin
            diff = v1 ^ v2;
            distance_val = 0;
            for (i = 0; i < 64; i++) begin
                distance_val = distance_val + diff[i];
            end
            return distance_val;
        end
    endfunction

endpackage
