`timescale 1ns/1ps

module tb_rv32i_stage1;

    logic clk = 0;
    logic reset = 1;
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic dmem_we;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    integer i;
    integer errors = 0;

    always #5 clk = ~clk;

    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[7:2]];

    always_ff @(posedge clk)
        if (!reset && dmem_we)
            dmem[dmem_addr[7:2]] <= dmem_wdata;

    rv32i_core dut (
        .clk(clk), .reset(reset),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_rdata(dmem_rdata)
    );

    function automatic [31:0] enc_i(
        input integer imm, rs1, funct3, rd, opcode
    );
        enc_i = {
            imm[11:0], rs1[4:0], funct3[2:0],
            rd[4:0], opcode[6:0]
        };
    endfunction

    function automatic [31:0] enc_r(
        input integer funct7, rs2, rs1, funct3, rd, opcode
    );
        enc_r = {
            funct7[6:0], rs2[4:0], rs1[4:0],
            funct3[2:0], rd[4:0], opcode[6:0]
        };
    endfunction

    function automatic [31:0] enc_u(
        input integer imm20, rd, opcode
    );
        enc_u = {imm20[19:0], rd[4:0], opcode[6:0]};
    endfunction

    task automatic check_reg(
        input integer regno,
        input logic [31:0] expected
    );
        begin
            if (dut.regs[regno] !== expected) begin
                $display("FAIL x%0d expected=%h actual=%h",
                    regno, expected, dut.regs[regno]);
                errors = errors + 1;
            end else begin
                $display("PASS x%0d = %h", regno, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/rv32i_stage1.vcd");
        $dumpvars(0, tb_rv32i_stage1);

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end

        imem[0]  = enc_i(-8, 0, 0, 1, 7'b0010011);
        imem[1]  = enc_i(2, 0, 0, 2, 7'b0010011);
        imem[2]  = enc_r(0, 2, 2, 1, 3, 7'b0110011);
        imem[3]  = enc_r(0, 2, 1, 5, 4, 7'b0110011);
        imem[4]  = enc_r(32, 2, 1, 5, 5, 7'b0110011);
        imem[5]  = enc_i(3, 2, 1, 6, 7'b0010011);
        imem[6]  = enc_i(2, 1, 5, 7, 7'b0010011);
        imem[7]  = enc_i(32'h402, 1, 5, 8, 7'b0010011);
        imem[8]  = enc_r(0, 2, 1, 3, 9, 7'b0110011);
        imem[9]  = enc_r(0, 2, 1, 2, 10, 7'b0110011);
        imem[10] = enc_i(-1, 1, 2, 11, 7'b0010011);
        imem[11] = enc_i(-1, 1, 3, 12, 7'b0010011);
        imem[12] = enc_u('h12345, 13, 7'b0110111);
        imem[13] = enc_u(1, 14, 7'b0010111);

        // Stop execution in a stable loop.
        imem[14] = 32'h0000006f;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 0;

        repeat (40) @(posedge clk);
        #1;

        $display("\n--- Stage 1 instruction results ---");
        check_reg(0,  32'h00000000);
        check_reg(1,  32'hfffffff8);
        check_reg(2,  32'h00000002);
        check_reg(3,  32'h00000008);
        check_reg(4,  32'h3ffffffe);
        check_reg(5,  32'hfffffffe);
        check_reg(6,  32'h00000010);
        check_reg(7,  32'h3ffffffe);
        check_reg(8,  32'hfffffffe);
        check_reg(9,  32'h00000000);
        check_reg(10, 32'h00000001);
        check_reg(11, 32'h00000001);
        check_reg(12, 32'h00000001);
        check_reg(13, 32'h12345000);
        check_reg(14, 32'h00001034);

        if (errors == 0)
            $display("\nALL STAGE 1 TESTS PASSED");
        else
            $display("\nSTAGE 1 TESTS FAILED: %0d error(s)", errors);

        $finish;
    end

endmodule

