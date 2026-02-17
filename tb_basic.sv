
// ============================================================================
// 4. Testbench
// ============================================================================
module tb_basic;
    parameter CLK_PERIOD = 10;
    logic clk, rst_n;
    logic enc_start, enc_done;
    logic [23:0] enc_data_in;
    logic [63:0] codeword;
    logic dec_start, dec_done, dec_valid;
    logic [63:0] rx_channel;
    logic [23:0] dec_data_out;

    polar64_crc16_encoder encoder_inst (
        .clk(clk), .rst_n(rst_n),
        .start(enc_start), .data_in(enc_data_in),
        .done(enc_done), .codeword(codeword)
    );

    polar64_crc16_decoder decoder_inst (
        .clk(clk), .rst_n(rst_n),
        .start(dec_start), .rx(rx_channel),
        .done(dec_done), .data_out(dec_data_out), .valid(dec_valid)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task run_test_case(input string name, input [23:0] data, input int num_errors);
        logic [63:0] noisy_codeword;
        logic [63:0] error_mask;
        
        $display("\n---------------------------------------------------");
        $display("TEST CASE: %s (Injecting %0d Errors)", name, num_errors);

        // 1. Encode
        @(posedge clk);
        enc_data_in = data;
        enc_start = 1;
        @(posedge clk);
        enc_start = 0;
        wait(enc_done);
        @(posedge clk);
        
        $display("  Input Data: 0x%h", data);
        $display("  Codeword:   0x%h", codeword);

        // 2. Inject Errors
        error_mask = 0;
        if (num_errors >= 1) error_mask[5]  = 1;
        if (num_errors >= 2) error_mask[12] = 1;
        if (num_errors >= 3) error_mask[40] = 1;
        if (num_errors >= 4) error_mask[55] = 1; 
        if (num_errors >= 5) error_mask[60] = 1; 

        noisy_codeword = codeword ^ error_mask;
        $display("  Rx Vector:  0x%h (Mask: %h)", noisy_codeword, error_mask);

        // 3. Decode
        rx_channel = noisy_codeword;
        dec_start = 1;
        @(posedge clk);
        dec_start = 0;
        wait(dec_done);
        @(posedge clk);

        // 4. Verify
        $display("  Decoded:    0x%h (Valid: %b)", dec_data_out, dec_valid);
        
        if (num_errors <= 3) begin
            // Should correct
            if (dec_valid === 1 && dec_data_out === data) 
                $display("  RESULT: [PASS] Corrected successfully.");
            else 
                $display("  RESULT: [FAIL] Failed to correct.");
        end else begin
            // Should detect (reject)
            // With Strict Radius 3 check, even if SC "accidentally" corrects 4 errors,
            // the distance check will see dist=4 and force valid=0.
            if (dec_valid === 0) 
                $display("  RESULT: [PASS] Detected uncorrectable errors (Valid=0).");
            else 
                $display("  RESULT: [FAIL] False Positive! (Marked valid despite >3 errors).");
        end
    endtask

    initial begin
        rst_n = 0;
        enc_start = 0;
        dec_start = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        run_test_case("Clean Channel", 24'hABCDEF, 0);
        run_test_case("1 Bit Flip", 24'h123456, 1);
        run_test_case("2 Bit Flips", 24'h789ABC, 2);
        run_test_case("3 Bit Flips", 24'hCAFE00, 3);
        
        // This is the critical test for Bounded Distance.
        // Even if SC miraculously corrects this, valid MUST be 0 because distance is 4.
        run_test_case("4 Bit Flips", 24'hBADF00, 4); 
        
        run_test_case("5 Bit Flips", 24'hFFFFFF, 5);

        #(CLK_PERIOD * 20);
        $display("\nAll tests completed.");
        $stop;
    end
endmodule
