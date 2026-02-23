`timescale 1ns / 1ps

/*
 * ============================================================================
 * Decoder 模組說明
 * ============================================================================
 * [工作原理]
 * 本模組實作一個嚴格半徑 3 的 Bounded-Distance Polar Code 解碼器。
 * 利用 Polar Code 轉換矩陣的對合特性 (Involution, G = G^-1)，
 * 透過窮舉翻轉接收端 rx 的 0~3 個 bits，並檢查轉換後的 Frozen bits 是否全為 0。
 * 若找到合法字組，則提取 Data 與 CRC，並進行 CRC Fail-safe 檢查。
 * 
 * [流程圖 (Flowchart)]
 * [Cycle 0] start=1, 接收 rx (64-bit)
 *    |
 * [Cycle 1] 進入解碼狀態機，儲存 rx
 *    |
 * [Cycle 2] 執行 BD-3 搜尋 (Decode_BD3):
 *    |      1. 預算基底向量 (basis vectors)
 *    |      2. 嘗試 0~3 bits 翻轉 (rx ^ error_pattern)
 *    |      3. 檢查 Frozen bits 是否全為 0 (ECC 檢查)
 *    |      4. 提取 ext_data 與 ext_crc
 *    |      5. 重新計算 CRC 並與 ext_crc 比對
 *    |
 * [Cycle 3] 輸出解碼結果 (data_out, valid)，並舉起 done=1
 * 
 * [數據流向 (Data Flow: Data, CRC, ECC)]
 * 1. 接收資料: rx (包含 Data, CRC, ECC 與雜訊) -> 進入 BD-3 搜尋
 * 2. ECC 檢查: 將翻轉後的 rx 轉換回 u_cand，檢查 u_cand[FROZEN_POS] 是否全為 0
 * 3. Data 提取: 若 ECC 檢查通過，從 u_hat[INFO_POS[0~23]] 提取 24-bit Data
 * 4. CRC 提取: 從 u_hat[INFO_POS[24~39]] 提取 16-bit 接收端 CRC
 * 5. CRC 驗證: 將提取的 Data 重新計算 CRC，若等於提取的 CRC，則 valid=1
 * ============================================================================
 */

/*
 * ============================================================================
 * Decoder 模組 (修正版 - Bounded Distance Radius 3)
 * ============================================================================
 * [修正說明]
 * 1. 採用 Behavioral Brute-force Search (BD-3) 演算法。
 * 2. 利用 G = G^-1 特性，翻轉 rx 的 0~3 bits 後進行轉換，檢查 Frozen bits。
 * 3. 確保 data_pos 與 crc_pos 與 Encoder 完全一致，解決 CRC Check 失敗問題。
 * ============================================================================
 */

module polar64_crc16_decoder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [63:0] rx,
    output logic        done,
    output logic [23:0] data_out,
    output logic        valid
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

    // 預先計算 Frozen Bits 的遮罩 (Mask)，加速檢查過程
    function automatic logic [63:0] get_frozen_mask();
        logic [63:0] mask;
        int i;
        mask = 64'hFFFF_FFFF_FFFF_FFFF;
        for (i = 0; i < 24; i = i + 1) mask[data_pos[i]] = 1'b0;
        for (i = 0; i < 16; i = i + 1) mask[crc_pos[i]]  = 1'b0;
        return mask;
    endfunction

    localparam logic [63:0] FROZEN_MASK = get_frozen_mask();

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
    // 內部函式：Polar Transform (G_64)
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
    // 內部函式：嚴格半徑 3 的 Bounded-Distance 解碼 (Behavioral Search)
    // ========================================================================
    function automatic logic [64:0] decode_bd3(input logic [63:0] rx_val);
        logic [63:0] e;
        logic [63:0] u;
        int i, j, k;
        begin
            // 0 flips (無錯誤)
            u = polar_transform(rx_val);
            if ((u & FROZEN_MASK) == 64'b0) return {1'b1, u};

            // 1 flip (1 bit 錯誤)
            for (i = 0; i < 64; i = i + 1) begin
                e = 64'h1 << i;
                u = polar_transform(rx_val ^ e);
                if ((u & FROZEN_MASK) == 64'b0) return {1'b1, u};
            end

            // 2 flips (2 bits 錯誤)
            for (i = 0; i < 63; i = i + 1) begin
                for (j = i + 1; j < 64; j = j + 1) begin
                    e = (64'h1 << i) | (64'h1 << j);
                    u = polar_transform(rx_val ^ e);
                    if ((u & FROZEN_MASK) == 64'b0) return {1'b1, u};
                end
            end

            // 3 flips (3 bits 錯誤)
            for (i = 0; i < 62; i = i + 1) begin
                for (j = i + 1; j < 63; j = j + 1) begin
                    for (k = j + 1; k < 64; k = k + 1) begin
                        e = (64'h1 << i) | (64'h1 << j) | (64'h1 << k);
                        u = polar_transform(rx_val ^ e);
                        if ((u & FROZEN_MASK) == 64'b0) return {1'b1, u};
                    end
                end
            end

            // 超過 3 bits 錯誤，回傳失敗
            return 65'b0; 
        end
    endfunction

    // ========================================================================
    // 解碼器狀態機與邏輯
    // ========================================================================

    logic [63:0] r_rx;
    logic        r_active;
    logic [3:0]  r_cycle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done     <= 1'b0;
            valid    <= 1'b0;
            data_out <= 24'b0;
            r_active <= 1'b0;
            r_cycle  <= 4'b0;
        end else begin
            done <= 1'b0; // 預設為 0，確保 done 是一個 1-cycle pulse
            
            if (start) begin
                r_rx     <= rx;
                r_active <= 1'b1;
                r_cycle  <= 4'd1;
            end else if (r_active) begin
                r_cycle <= r_cycle + 4'd1;
                
                // 在第 3 個週期輸出結果 (符合時序圖 lat=3，且滿足 <= 12 條件)
                if (r_cycle == 4'd2) begin
                    logic [64:0] decode_res;
                    logic [63:0] u_hat;
                    logic [23:0] ext_data;
                    logic [15:0] ext_crc;
                    logic [15:0] comp_crc;
                    int k;
                    
                    // 1. 執行半徑 3 的 Bounded-Distance 搜尋
                    decode_res = decode_bd3(r_rx);
                    
                    if (decode_res[64]) begin
                        u_hat = decode_res[63:0];
                        
                        // 2. 提取 Data 與 CRC
                        for (k = 0; k < 24; k = k + 1) ext_data[23-k] = u_hat[data_pos[k]];
                        for (k = 0; k < 16; k = k + 1) ext_crc[15-k]  = u_hat[crc_pos[k]];
                        
                        // 3. 重新計算 CRC 並比對 (Fail-safe rule)
                        comp_crc = calc_crc16(ext_data);
                        
                        if (comp_crc == ext_crc) begin
                            valid    <= 1'b1;
                            data_out <= ext_data;
                        end else begin
                            valid    <= 1'b0; // CRC 錯誤，拒絕封包
                            data_out <= 24'b0;
                        end
                    end else begin
                        valid    <= 1'b0; // 找不到半徑 3 內的合法字組，拒絕封包
                        data_out <= 24'b0;
                    end
                    
                    done     <= 1'b1;
                    r_active <= 1'b0;
                end
            end
        end
    end

endmodule
