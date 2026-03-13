// alu_rf_top.v
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  op,    // 00: ADD, 01: SUB, 10: MUL
    output reg [31:0] result
);
    always @(*) begin
        case(op)
            2'b00: result = a + b;
            2'b01: result = a - b;
            2'b10: result = a * b;
            default: result = 32'd0;
        endcase
    end
endmodule

module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [2:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [2:0]  raddr1,
    input  wire [2:0]  raddr2,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] registers [7:0];
    integer i;

    // 异步读
    assign rdata1 = registers[raddr1];
    assign rdata2 = registers[raddr2];

    // 同步写
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                registers[i] <= 32'd0;
        end else if (we) begin
            registers[waddr] <= wdata;
        end
    end
endmodule

// 顶层模块：集成ALU和寄存器堆
module top_dut (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,         // 寄存器写使能
    input  wire [2:0]  waddr,      // 寄存器写地址
    input  wire [2:0]  raddr1,     // 寄存器读地址1 (ALU输入A)
    input  wire [2:0]  raddr2,     // 寄存器读地址2 (ALU输入B)
    input  wire [1:0]  alu_op,     // ALU操作码
    input  wire        wdata_sel,  // 0: 写入外部数据, 1: 写入ALU结果
    input  wire [31:0] ext_wdata,  // 外部输入数据
    output wire [31:0] alu_out,    // ALU输出结果 (用于Testbench监控)
    output wire [31:0] reg_out1,   // 寄存器输出1 (用于Testbench监控)
    output wire [31:0] reg_out2    // 寄存器输出2 (用于Testbench监控)
);

    wire [31:0] rf_wdata;
    
    // 数据选择器：决定写入寄存器的是外部数据还是ALU结果
    assign rf_wdata = wdata_sel ? alu_out : ext_wdata;

    regfile u_regfile (
        .clk(clk),
        .rst_n(rst_n),
        .we(we),
        .waddr(waddr),
        .wdata(rf_wdata),
        .raddr1(raddr1),
        .raddr2(raddr2),
        .rdata1(reg_out1),
        .rdata2(reg_out2)
    );

    alu u_alu (
        .a(reg_out1),
        .b(reg_out2),
        .op(alu_op),
        .result(alu_out)
    );

endmodule
