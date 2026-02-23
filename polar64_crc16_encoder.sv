`timescale 1ns / 1ps


/*
 * ============================================================================
 * Encoder 模組說明
 * ============================================================================
 * [工作原理]
 * 本模組實作一個 64-bit Polar Code 編碼器，並串接 16-bit CRC-CCITT。
 * 採用 3 級管線 (Pipeline) 設計，確保精準的 2 Cycles Latency。
 * 
 * [流程圖 (Flowchart)]
 * [Cycle 0] start=1, 輸入 data_in (24-bit)
 *    |
 * [Cycle 1] Stage 1: 計算 CRC16 -> 將 Data 與 CRC 映射到 u 向量的 INFO_POS
 *    |               (未映射的位元自動為 0，即 Frozen bits / ECC)
 *    |
 * [Cycle 2] Stage 2: 執行 Polar Transform (u * G_64) 產生 codeword
 *    |
 * [Cycle 3] Stage 3: 輸出 codeword，並舉起 done=1 (精準延遲 2 cycles)
 * 
 * [數據流向 (Data Flow: Data, CRC, ECC)]
 * 1. Data (24-bit): data_in -> 參與計算 CRC -> 映射至 u[INFO_POS[0~23]]
 * 2. CRC  (16-bit): 由 data_in 算出 -> 映射至 u[INFO_POS[24~39]]
 * 3. ECC  (24-bit): 即 Frozen bits，固定為 0 -> 隱含於 u 的其餘位置
 * 4. Codeword (64-bit): u 經過 Polar Transform 後的結果，輸出至外部
 * ============================================================================
 */


/*
 * ============================================================================
 * Encoder 模組 (修正版)
 * ============================================================================
 * [修正說明]
 * 1. 增加管線級數以符合 tb_basic 的嚴格時序要求 (Exactly 2 cycles after start)。
 * 2. 控制路徑：start -> r_valid_1 -> r_valid_2 -> done
 * 3. 資料路徑：
 *    - Cycle 1: 計算 CRC 並映射至 u 向量 (r_u_vec)
 *    - Cycle 2: 執行 Polar Transform (r_codeword)
 *    - Cycle 3: 輸出結果 (codeword) 並舉起 done
 * ============================================================================
 */

module polar64_crc16_encoder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [23:0] data_in,
    output logic        done,
    output logic [63:0] codeword
);

    // ========================================================================
    // 內部參數與映射表
    // ========================================================================
    localparam int data_pos [0:23] = '{
        63, 62, 61, 59, 55, 47, 31, 
        60, 58, 57, 54, 53, 51, 46, 45, 43, 39, 30, 29, 27, 23, 15, 
        56, 52 
    };

    localparam int crc_pos [0:15] = '{
        50, 49, 44, 42, 41, 38, 37, 35, 
        28, 26, 25, 22, 21, 19, 14, 13
    };

    // ========================================================================
    // 內部函式：CRC-16-CCITT Generator
    // ========================================================================
    function automatic logic [15:0] calc_crc16(input logic [23:0] din);
        logic [15:0] crc;
        logic feedback;
        int i;
        begin
            crc = 16'h0000; 
            for (i = 23; i >= 0; i = i - 1) begin
                feedback = din[i] ^ crc[15];
                crc = (crc << 1) & 16'hFFFF;
                if (feedback) begin
                    crc = crc ^ 16'h1021;
                end
            end
            return crc;
        end
    endfunction

    // ========================================================================
    // 內部函式：Polar Transform
    // ========================================================================
    function automatic logic [63:0] polar_transform(input logic [63:0] u);
        logic [63:0] v;
        int step, half, i, j, s;
        begin
            v = u;
            for (s = 0; s < 6; s = s + 1) begin
                step = 1 << (s + 1);
                half = 1 << s;
                for (i = 0; i < 64; i = i + step) begin
                    for (j = 0; j < half; j = j + 1) begin
                        v[i + j] = v[i + j] ^ v[i + j + half];
                    end
                end
            end
            return v;
        end
    endfunction

    // ========================================================================
    // 硬體管線設計 (修正為 2-Cycle Latency 邏輯)
    // ========================================================================
    
    logic [63:0] r_u_vec;
    logic [63:0] r_codeword;
    logic        r_valid_1;
    logic        r_valid_2;

    // Pipeline Stage 1: 收到 start 後，計算 CRC 並完成 u 向量映射
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_u_vec    <= 64'b0;
            r_valid_1  <= 1'b0;
        end else begin
            if (start) begin
                logic [15:0] calc_crc;
                logic [63:0] temp_u;
                int k;
                
                calc_crc = calc_crc16(data_in);
                temp_u = 64'b0; 
                
                // Mapping
                for (k = 0; k < 24; k = k + 1) temp_u[data_pos[k]] = data_in[23-k];
                for (k = 0; k < 16; k = k + 1) temp_u[crc_pos[k]]  = calc_crc[15-k];

                r_u_vec    <= temp_u;
                r_valid_1  <= 1'b1;
            end else begin
                r_valid_1  <= 1'b0;
            end
        end
    end

    // Pipeline Stage 2: 執行 Polar Transform
    // 這裡增加一級暫存 (r_valid_2)，確保 done 在 start 後的正確時刻舉起
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_codeword <= 64'b0;
            r_valid_2  <= 1'b0;
        end else begin
            if (r_valid_1) begin
                r_codeword <= polar_transform(r_u_vec);
                r_valid_2  <= 1'b1;
            end else begin
                r_valid_2  <= 1'b0;
            end
        end
    end

    // Output Stage: 輸出結果
    // 當 r_valid_2 為 1 時，代表已經過了 2 個 Cycle 的處理，此時舉起 done
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            codeword <= 64'b0;
            done     <= 1'b0;
        end else begin
            if (r_valid_2) begin
                codeword <= r_codeword;
                done     <= 1'b1;
            end else begin
                done     <= 1'b0;
            end
        end
    end

endmodule
