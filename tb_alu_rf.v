// tb_alu_rf.v
`timescale 1ns/1ps

module tb_alu_rf;
    reg         clk;
    reg         rst_n;
    reg         we;
    reg  [2:0]  waddr;
    reg  [2:0]  raddr1;
    reg  [2:0]  raddr2;
    reg  [1:0]  alu_op;
    reg         wdata_sel;
    reg  [31:0] ext_wdata;
    
    wire [31:0] alu_out;
    wire [31:0] reg_out1;
    wire [31:0] reg_out2;

    // 实例化DUT
    top_dut u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .we(we),
        .waddr(waddr),
        .raddr1(raddr1),
        .raddr2(raddr2),
        .alu_op(alu_op),
        .wdata_sel(wdata_sel),
        .ext_wdata(ext_wdata),
        .alu_out(alu_out),
        .reg_out1(reg_out1),
        .reg_out2(reg_out2)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 生成FSDB波形用于Verdi调试
    initial begin
        $fsdbDumpfile("inter.fsdb");
        $fsdbDumpvars(0, tb_alu_rf);
    end

    // 测试序列
    initial begin
        // 初始化
        rst_n = 0; we = 0; waddr = 0; raddr1 = 0; raddr2 = 0; alu_op = 0; wdata_sel = 0; ext_wdata = 0;
        #20 rst_n = 1;

        // 1. Data Storage: 加载 a, b, c, d 到 Reg0, Reg1, Reg2, Reg3
        // a = 2
        @(posedge clk) we = 1; wdata_sel = 0; waddr = 3'd0; ext_wdata = 32'd2;
        // b = 3
        @(posedge clk) we = 1; wdata_sel = 0; waddr = 3'd1; ext_wdata = 32'd3;
        // c = 4
        @(posedge clk) we = 1; wdata_sel = 0; waddr = 3'd2; ext_wdata = 32'd4;
        // d = 5
        @(posedge clk) we = 1; wdata_sel = 0; waddr = 3'd3; ext_wdata = 32'd5;
        
        // 2. Execution & 3. Write-Back
        // 计算 ac (Reg0 * Reg2) -> 存入 Reg6 (中间变量)
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd0; raddr2 = 3'd2; alu_op = 2'b10; waddr = 3'd6;
        // 计算 bd (Reg1 * Reg3) -> 存入 Reg7 (中间变量)
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd1; raddr2 = 3'd3; alu_op = 2'b10; waddr = 3'd7;
        // 计算实部 ac - bd (Reg6 - Reg7) -> 存入 Reg4
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd6; raddr2 = 3'd7; alu_op = 2'b01; waddr = 3'd4;
        
        // 计算 ad (Reg0 * Reg3) -> 存入 Reg6
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd0; raddr2 = 3'd3; alu_op = 2'b10; waddr = 3'd6;
        // 计算 bc (Reg1 * Reg2) -> 存入 Reg7
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd1; raddr2 = 3'd2; alu_op = 2'b10; waddr = 3'd7;
        // 计算虚部 ad + bc (Reg6 + Reg7) -> 存入 Reg5
        @(posedge clk) we = 1; wdata_sel = 1; raddr1 = 3'd6; raddr2 = 3'd7; alu_op = 2'b00; waddr = 3'd5;
        
        // 结束写入，准备读出结果进行比对
        @(posedge clk) we = 0; raddr1 = 3'd4; raddr2 = 3'd5;
        @(posedge clk);
        
        // 4. Self-Checking Logic
        if ($signed(reg_out1) == -7 && $signed(reg_out2) == 22) begin
            $display("=======================================");
            $display("Simulation PASSED");
            $display("Real Part (Reg4) = %0d, Imag Part (Reg5) = %0d", $signed(reg_out1), $signed(reg_out2));
            $display("=======================================");
        end else begin
            $display("=======================================");
            $display("Simulation FAILED");
            $display("Expected: Real = -7, Imag = 22");
            $display("Got: Real = %0d, Imag = %0d", $signed(reg_out1), $signed(reg_out2));
            $display("=======================================");
        end

        #20 $finish;
    end
endmodule
