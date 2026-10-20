`timescale 1ns/1ps

module tb_rv32i_control;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic dmem_we;
    logic [31:0] dmem_rdata;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    integer i;
    integer errors = 0;

    always #5 clk = ~clk;

    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[7:2]];

    always_ff @(posedge clk) begin
        if (!reset && dmem_we)
            dmem[dmem_addr[7:2]] <= dmem_wdata;
    end

    rv32i_core dut (
        .clk(clk),
        .reset(reset),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata)
    );

    function automatic [31:0] enc_i(input integer imm, input integer rs1,
                                     input integer funct3, input integer rd,
                                     input integer opcode);
        enc_i = {imm[11:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_r(input integer funct7, input integer rs2,
                                     input integer rs1, input integer funct3,
                                     input integer rd, input integer opcode);
        enc_r = {funct7[6:0], rs2[4:0], rs1[4:0], funct3[2:0], rd[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_s(input integer imm, input integer rs2,
                                     input integer rs1, input integer funct3,
                                     input integer opcode);
        enc_s = {imm[11:5], rs2[4:0], rs1[4:0], funct3[2:0], imm[4:0], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_b(input integer imm, input integer rs2,
                                     input integer rs1, input integer funct3,
                                     input integer opcode);
        enc_b = {imm[12], imm[10:5], rs2[4:0], rs1[4:0], funct3[2:0],
                 imm[4:1], imm[11], opcode[6:0]};
    endfunction

    function automatic [31:0] enc_j(input integer imm, input integer rd,
                                     input integer opcode);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], opcode[6:0]};
    endfunction

    task automatic check_reg(input integer regno, input logic [31:0] expected);
        begin
            if (dut.regs[regno] !== expected) begin
                $display("FAIL x%0d: expected %0d (0x%08x), got %0d (0x%08x)",
                         regno, expected, expected, dut.regs[regno], dut.regs[regno]);
                errors = errors + 1;
            end else begin
                $display("PASS x%0d = %0d (0x%08x)", regno, expected, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/rv32i_control.vcd");
        $dumpvars(0, tb_rv32i_control);

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013; 
            dmem[i] = 32'b0;
        end

        imem[0]  = enc_i(5,  0, 0, 1, 7'b0010011);          
        imem[1]  = enc_i(7,  0, 0, 2, 7'b0010011);          
        imem[2]  = enc_r(0,  2, 1, 0, 3, 7'b0110011);      
        imem[3]  = enc_r(7'b0100000, 1, 3, 0, 4, 7'b0110011); 
        imem[4]  = enc_s(0,  4, 0, 2, 7'b0100011);       
        imem[5]  = enc_i(0,  0, 2, 5, 7'b0000011);       
        imem[6]  = enc_r(0,  2, 5, 0, 6, 7'b0110011);     
        imem[7]  = enc_b(8,  6, 6, 0, 7'b1100011);         
        imem[8]  = enc_i(99, 0, 0, 7, 7'b0010011);         
        imem[9]  = enc_j(8,  8, 7'b1101111);              
        imem[10] = enc_i(88, 0, 0, 9, 7'b0010011);        
        imem[11] = enc_i(11, 0, 0, 9, 7'b0010011);         
        imem[12] = enc_i(-1, 0, 0, 10, 7'b0010011);  
        imem[13] = enc_i(1,  0, 0, 11, 7'b0010011);     
        imem[14] = enc_b(8, 11, 10, 4, 7'b1100011);     
        imem[15] = enc_i(99, 0, 0, 12, 7'b0010011);      
        imem[16] = enc_i(13, 0, 0, 13, 7'b0010011);
        imem[17] = enc_b(8, 10, 11, 5, 7'b1100011);     
        imem[18] = enc_i(99, 0, 0, 14, 7'b0010011);       
        imem[19] = enc_i(15, 0, 0, 15, 7'b0010011);
        imem[20] = enc_b(8, 11, 10, 6, 7'b1100011);       
        imem[21] = enc_i(16, 0, 0, 16, 7'b0010011);
        imem[22] = enc_b(8, 11, 10, 7, 7'b1100011);       
        imem[23] = enc_i(99, 0, 0, 17, 7'b0010011);      
        imem[24] = enc_i(18, 0, 0, 18, 7'b0010011);
        imem[25] = enc_i(116, 0, 0, 19, 7'b0010011);      
        imem[26] = enc_i(0, 19, 0, 20, 7'b1100111);       
        imem[27] = enc_i(99, 0, 0, 21, 7'b0010011);       
        imem[28] = enc_i(88, 0, 0, 22, 7'b0010011);       
        imem[29] = enc_i(23, 0, 0, 23, 7'b0010011);       
        imem[30] = enc_j(0, 0, 7'b1101111);   

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        repeat (50) @(posedge clk);
        #1;

        $display("\n--- Directed verification results ---");
        check_reg(0,  32'd0);
        check_reg(1,  32'd5);
        check_reg(2,  32'd7);
        check_reg(3,  32'd12);
        check_reg(4,  32'd7);
        check_reg(5,  32'd7);
        check_reg(6,  32'd14);
        check_reg(7,  32'd0);
        check_reg(8,  32'd40);
        check_reg(9,  32'd11);
        check_reg(10, 32'hFFFFFFFF);
        check_reg(11, 32'd1);
        check_reg(12, 32'd0);
        check_reg(13, 32'd13);
        check_reg(14, 32'd0);
        check_reg(15, 32'd15);
        check_reg(16, 32'd16);
        check_reg(17, 32'd0);
        check_reg(18, 32'd18);
        check_reg(19, 32'd116);
        check_reg(20, 32'd108);
        check_reg(21, 32'd0);
        check_reg(22, 32'd0);
        check_reg(23, 32'd23);

        if (dmem[0] !== 32'd7) begin
            $display("FAIL dmem[0]: expected 7, got %0d", dmem[0]);
            errors = errors + 1;
        end else begin
            $display("PASS dmem[0] = 7");
        end

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\nTESTS FAILED: %0d error(s)", errors);

        $finish;
    end
endmodule
