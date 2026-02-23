`timescale 1ns/1ps

// tb_basic.sv
// ------------------------------------------------------------
// Student-visible *SMOKE* testbench for tbl2026.8.pdf (Section 10)
//
// Minimum directed checks (public):
//   Case A: 0 flips   -> valid=1 and correct data_out
//   Case B: 1-3 flips -> MUST correct (valid=1, correct data_out)
//   Case C: 4 flips   -> MUST reject (valid=0)
//
// Also checks the required interface timing:
//   - Encoder done must assert exactly +2 cycles after start (1-cycle pulse)
//   - Decoder done must assert within 12 cycles after start (1-cycle pulse)
//
// IMPORTANT:
//   Passing tb_basic does NOT mean you have finished the project.
//   The instructor tb_hidden will include more corner cases + randomized regression.
//
// ------------------------------------------------------------

module tb_basic;

  import polar_common_pkg::*;

  logic clk;
  logic rst_n;

  // Encoder DUT ports
  logic        enc_start, enc_done;
  logic [23:0] data_in;
  logic [63:0] codeword;

  // Decoder DUT ports
  logic        dec_start, dec_done;
  logic [63:0] rx;
  logic [23:0] data_out;
  logic        valid;

  // Test signals
  logic [23:0] din;
  logic [63:0] cw_ref, cw_dut;
  logic [23:0] dout;
  logic        v;
  int unsigned lat;

  // Local flags used in the main initial block (declared here for VCS compatibility)
  logic enc_timing_ok;
  logic dec_timing_ok;
  bit   timing_ok_all;
  bit   enc_ok;
  bit   dec_ok;

  // Smoke scoring (small on purpose)
  int smoke_score;
  int smoke_total;
  int smoke_fail;

  polar64_crc16_encoder u_enc (
    .clk(clk), .rst_n(rst_n),
    .start(enc_start), .data_in(data_in),
    .done(enc_done), .codeword(codeword)
  );

  polar64_crc16_decoder u_dec (
    .clk(clk), .rst_n(rst_n),
    .start(dec_start), .rx(rx),
    .done(dec_done), .data_out(data_out), .valid(valid)
  );

  // 100 MHz clock
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Start pulse helper (1-cycle pulse, aligned to negedges)
  task automatic pulse_start(ref logic s);
    begin
      @(negedge clk);
      s = 1'b1;
      @(negedge clk);
      s = 1'b0;
    end
  endtask

  // Reference encoder (matches handout exactly)
  function automatic logic [63:0] ref_encode(input logic [23:0] din);
    logic [15:0] crc;
    logic [63:0] u;
    begin
      crc = crc16_ccitt24(din);
      u   = build_u(din, crc);
      return polar_transform64(u);
    end
  endfunction

  // Encode transaction + strict latency check (done exactly 2 cycles after start sampled)
  task automatic do_encode(
    input  logic [23:0] din,
    output logic [63:0] cw,
    output logic        timing_ok
  );
    begin
      timing_ok = 1'b1;
      data_in   = din;
      pulse_start(enc_start);

      // +1 cycle: done must still be 0
      @(posedge clk); @(negedge clk);
      if (enc_done) timing_ok = 1'b0;

      // +2 cycles: done must be 1
      @(posedge clk); @(negedge clk);
      if (!enc_done) timing_ok = 1'b0;

      cw = codeword;

      // +3 cycle: done must drop back to 0
      @(posedge clk); @(negedge clk);
      if (enc_done) timing_ok = 1'b0;
    end
  endtask

  // Decode transaction + latency check (done within 12 cycles after start)
  task automatic do_decode(
    input  logic [63:0] rx_in,
    output logic [23:0] dout,
    output logic        v,
    output int unsigned lat,
    output logic        timing_ok
  );
    begin
      timing_ok = 1'b1;
      lat       = 0;
      rx        = rx_in;
      pulse_start(dec_start);

      // Wait up to 12 cycles for done
      while (1) begin
        @(posedge clk); lat++;
        @(negedge clk);
        if (dec_done) break;
        if (lat >= 12) begin
          timing_ok = 1'b0;
          break;
        end
      end

      dout = data_out;
      v    = valid;

      // done should be a 1-cycle pulse (only check if we saw it)
      if (timing_ok) begin
        @(posedge clk); @(negedge clk);
        if (dec_done) timing_ok = 1'b0;
      end
    end
  endtask

  // Convenience: single-bit mask
  function automatic logic [63:0] bit_mask(input int unsigned b);
    logic [63:0] m;
    begin
      m = 64'b0;
      m[b] = 1'b1;
      return m;
    end
  endfunction

  task automatic smoke_item(
    input string name,
    input int    pts,
    input bit    pass
  );
    begin
      if (pass) begin
        smoke_score += pts;
        $display("[SMOKE][PASS] +%0d : %s", pts, name);
      end else begin
        smoke_fail++;
        $display("[SMOKE][FAIL] +%0d : %s", pts, name);
      end
    end
  endtask

  initial begin
    enc_start  = 1'b0;
    dec_start  = 1'b0;
    data_in    = '0;
    rx         = '0;

    smoke_score = 0;
    smoke_fail  = 0;
    smoke_total = 30;

    // reset
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("============================================================");
    $display(" tb_basic (tbl2026.8) : PUBLIC smoke checks (NOT full grading)");
    $display("============================================================");

    $display("[TB] pos_tables_ok=%0d, min_info_row_weight=%0d (target >= 8)",
             pos_tables_ok(), min_info_row_weight());

    // Use the handout example value
    din    = 24'hABCDEF;
    cw_ref = ref_encode(din);

    // -------------------------
    // Encoder smoke check
    // -------------------------
    do_encode(din, cw_dut, enc_timing_ok);

    enc_ok = pos_tables_ok() && enc_timing_ok && (cw_dut === cw_ref);

    smoke_item("Encoder: matches reference on 24'hABCDEF and done @ +2", 10, enc_ok);

    // -------------------------
    // Decoder smoke checks (Case A/B/C)
    // -------------------------
    timing_ok_all = enc_timing_ok;

    dec_ok = 1'b1;

    // Case A: 0 flips
    do_decode(cw_ref, dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= (v === 1'b1) && (dout === din);

    // Case B: 1 flip / 2 flips / 3 flips (directed)
    do_decode(cw_ref ^ bit_mask(5), dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= (v === 1'b1) && (dout === din);

    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(63), dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= (v === 1'b1) && (dout === din);

    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(1) ^ bit_mask(63), dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= (v === 1'b1) && (dout === din);

    // Case C: 4 flips must reject (valid=0)
    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(1) ^ bit_mask(2) ^ bit_mask(3), dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= (v === 1'b0);

    // Optional fail-safe spot-check (5 flips): if valid==1 then data must be correct
    do_decode(cw_ref ^ bit_mask(0) ^ bit_mask(1) ^ bit_mask(2) ^ bit_mask(3) ^ bit_mask(4), dout, v, lat, dec_timing_ok);
    timing_ok_all &= dec_timing_ok;
    dec_ok &= !((v === 1'b1) && (dout !== din));

    smoke_item("Decoder: Case A/B/C on ABCDEF (plus 1 fail-safe spot check)", 10, dec_ok);

    // -------------------------
    // Timing / handshake smoke check
    // -------------------------
    smoke_item("Interface timing: ENC done @+2, DEC done <=12, pulses are 1-cycle", 10, timing_ok_all);

    // Summary
    $display("------------------------------------------------------------");
    $display("[SUMMARY] SMOKE score = %0d / %0d", smoke_score, smoke_total);
    $display("------------------------------------------------------------");

    if (smoke_fail != 0) begin
      $display("[tb_basic] FAIL");
      $fatal(1);
    end else begin
      $display("[tb_basic] PASS");
      $display("[NOTE] Passing tb_basic does NOT guarantee full credit.");
      $display("[NOTE] Completion/checkoff requires BASE SCORE 100/100 in tb_hidden (excluding bonus).");
      $finish;
    end
  end

endmodule
