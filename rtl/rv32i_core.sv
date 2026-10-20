`timescale 1ns/1ps

module rv32i_core (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic        dmem_we,
    input  logic [31:0] dmem_rdata
);

    localparam logic [31:0] NOP = 32'h00000013; 

    logic [31:0] pc;
    logic [31:0] ifid_pc, ifid_instr;
    logic        ifid_valid;

    logic [31:0] idex_pc, idex_instr, idex_rs1_value, idex_rs2_value, idex_imm;
    logic [4:0]  idex_rs1, idex_rs2, idex_rd;
    logic        idex_valid;

    logic [31:0] exmem_pc4, exmem_alu_result, exmem_store_data;
    logic [4:0]  exmem_rd;
    logic        exmem_regwrite, exmem_memread, exmem_memwrite, exmem_memtoreg;
    logic        exmem_valid;

    logic [31:0] memwb_pc4, memwb_alu_result, memwb_load_data;
    logic [4:0]  memwb_rd;
    logic        memwb_regwrite, memwb_memtoreg, memwb_valid;

    logic [31:0] regs [0:31];

    logic [6:0] ifid_opcode;
    logic [4:0] ifid_rs1, ifid_rs2, ifid_rd;
    logic [31:0] ifid_imm;
    logic [31:0] wb_value;

    logic [31:0] id_rs1_value, id_rs2_value;
    logic [31:0] ex_rs1_value, ex_rs2_value;
    logic [31:0] ex_alu_result, ex_store_data, ex_branch_target;
    logic        ex_regwrite, ex_memread, ex_memwrite, ex_memtoreg;
    logic        ex_redirect, ex_branch_taken;
    logic [4:0]  ex_rd;
    logic [6:0]  ex_opcode;
    logic [2:0]  ex_funct3;
    logic [6:0]  ex_funct7;
    logic        stall;
    logic [31:0] next_pc_target;

    assign imem_addr = pc;
    assign ifid_opcode = ifid_instr[6:0];
    assign ifid_rs1 = ifid_instr[19:15];
    assign ifid_rs2 = ifid_instr[24:20];
    assign ifid_rd   = ifid_instr[11:7];

    function automatic logic uses_rs1(input logic [6:0] opcode);
        begin
            case (opcode)
                7'b0110011,
                7'b0010011, 
                7'b0000011, 
                7'b0100011,
                7'b1100011,
                7'b1100111: uses_rs1 = 1'b1;
                default: uses_rs1 = 1'b0;
            endcase
        end
    endfunction

    function automatic logic uses_rs2(input logic [6:0] opcode);
        begin
            case (opcode)
                7'b0110011, 
                7'b0100011,
                7'b1100011: uses_rs2 = 1'b1;
                default: uses_rs2 = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] immediate(input logic [31:0] instr);
        begin
            case (instr[6:0])
                7'b0010011, 7'b0000011, 7'b1100111:
                    immediate = {{20{instr[31]}}, instr[31:20]};
                7'b0100011:
                    immediate = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                7'b1100011:
                    immediate = {{19{instr[31]}}, instr[31], instr[7],
                                 instr[30:25], instr[11:8], 1'b0};
                7'b1101111:
                    immediate = {{11{instr[31]}}, instr[31],
                                 instr[19:12], instr[20], instr[30:21], 1'b0};
                7'b0110111, 7'b0010111:
                    immediate = {instr[31:12], 12'b0};
                default:
                    immediate = 32'b0;
            endcase
        end
    endfunction

    always_comb begin
        ifid_imm = immediate(ifid_instr);
        wb_value = memwb_memtoreg ? memwb_load_data :
                   memwb_valid && (memwb_rd == 5'd0) ? 32'b0 :
                   memwb_alu_result;

        if (ifid_rs1 == 5'd0)
            id_rs1_value = 32'b0;
        else if (memwb_valid && memwb_regwrite && (memwb_rd == ifid_rs1))
            id_rs1_value = wb_value;
        else
            id_rs1_value = regs[ifid_rs1];

        if (ifid_rs2 == 5'd0)
            id_rs2_value = 32'b0;
        else if (memwb_valid && memwb_regwrite && (memwb_rd == ifid_rs2))
            id_rs2_value = wb_value;
        else
            id_rs2_value = regs[ifid_rs2];
    end

    always_comb begin
        stall = 1'b0;
        if (ifid_valid && idex_valid &&
            (idex_instr[6:0] == 7'b0000011) &&
            (idex_rd != 5'd0)) begin
            if ((uses_rs1(ifid_opcode) && (ifid_rs1 == idex_rd)) ||
                (uses_rs2(ifid_opcode) && (ifid_rs2 == idex_rd)))
                stall = 1'b1;
        end
    end

    assign ex_opcode = idex_instr[6:0];
    assign ex_funct3 = idex_instr[14:12];
    assign ex_funct7 = idex_instr[31:25];
    assign ex_rd     = idex_rd;

    always_comb begin
        ex_rs1_value = idex_rs1_value;
        ex_rs2_value = idex_rs2_value;

        if (exmem_valid && exmem_regwrite && !exmem_memread &&
            (exmem_rd != 5'd0) && (exmem_rd == idex_rs1))
            ex_rs1_value = exmem_alu_result;
        else if (memwb_valid && memwb_regwrite &&
                 (memwb_rd != 5'd0) && (memwb_rd == idex_rs1))
            ex_rs1_value = wb_value;

        if (exmem_valid && exmem_regwrite && !exmem_memread &&
            (exmem_rd != 5'd0) && (exmem_rd == idex_rs2))
            ex_rs2_value = exmem_alu_result;
        else if (memwb_valid && memwb_regwrite &&
                 (memwb_rd != 5'd0) && (memwb_rd == idex_rs2))
            ex_rs2_value = wb_value;
    end

    always_comb begin
        ex_alu_result = 32'b0;
        ex_store_data = ex_rs2_value;
        ex_regwrite = 1'b0;
        ex_memread = 1'b0;
        ex_memwrite = 1'b0;
        ex_memtoreg = 1'b0;
        ex_branch_taken = 1'b0;
        ex_branch_target = idex_pc + idex_imm;

        case (ex_opcode)
            7'b0110011: begin
                case (ex_funct3)
                    3'b000: begin
                        if (ex_funct7 == 7'b0000000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result = ex_rs1_value + ex_rs2_value;
                        end else if (ex_funct7 == 7'b0100000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result = ex_rs1_value - ex_rs2_value;
                        end
                    end
                    3'b001: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value << ex_rs2_value[4:0];
                    end
                    3'b010: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result =
                            ($signed(ex_rs1_value) < $signed(ex_rs2_value)) ? 1 : 0;
                    end
                    3'b011: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result =
                            ($unsigned(ex_rs1_value) < $unsigned(ex_rs2_value)) ? 1 : 0;
                    end
                    3'b100: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value ^ ex_rs2_value;
                    end
                    3'b101: begin
                        if (ex_funct7 == 7'b0000000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result = ex_rs1_value >> ex_rs2_value[4:0];
                        end else if (ex_funct7 == 7'b0100000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result =
                                $signed(ex_rs1_value) >>> ex_rs2_value[4:0];
                        end
                    end
                    3'b110: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value | ex_rs2_value;
                    end
                    3'b111: if (ex_funct7 == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value & ex_rs2_value;
                    end
                    default: begin end
                endcase
            end

            7'b0010011: begin
                case (ex_funct3)
                    3'b000: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value + idex_imm;
                    end
                    3'b010: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result =
                            ($signed(ex_rs1_value) < $signed(idex_imm)) ? 1 : 0;
                    end
                    3'b011: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result =
                            ($unsigned(ex_rs1_value) < $unsigned(idex_imm)) ? 1 : 0;
                    end
                    3'b100: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value ^ idex_imm;
                    end
                    3'b110: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value | idex_imm;
                    end
                    3'b111: begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value & idex_imm;
                    end
                    3'b001: if (idex_instr[31:25] == 7'b0000000) begin
                        ex_regwrite = 1'b1;
                        ex_alu_result = ex_rs1_value << idex_instr[24:20];
                    end
                    3'b101: begin
                        if (idex_instr[31:25] == 7'b0000000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result = ex_rs1_value >> idex_instr[24:20];
                        end else if (idex_instr[31:25] == 7'b0100000) begin
                            ex_regwrite = 1'b1;
                            ex_alu_result =
                                $signed(ex_rs1_value) >>> idex_instr[24:20];
                        end
                    end
                    default: begin end
                endcase
            end

            7'b0000011: begin
                if (ex_funct3 == 3'b010) begin
                    ex_regwrite = 1'b1;
                    ex_memread = 1'b1;
                    ex_memtoreg = 1'b1;
                    ex_alu_result = ex_rs1_value + idex_imm;
                end
            end

            7'b0100011: begin
                if (ex_funct3 == 3'b010) begin
                    ex_memwrite = 1'b1;
                    ex_alu_result = ex_rs1_value + idex_imm;
                end
            end

            7'b1100011: begin
                case (ex_funct3)
                    3'b000: ex_branch_taken = (ex_rs1_value == ex_rs2_value);
                    3'b001: ex_branch_taken = (ex_rs1_value != ex_rs2_value);
                    3'b100: ex_branch_taken =
                        ($signed(ex_rs1_value) < $signed(ex_rs2_value));
                    3'b101: ex_branch_taken =
                        ($signed(ex_rs1_value) >= $signed(ex_rs2_value));
                    3'b110: ex_branch_taken =
                        ($unsigned(ex_rs1_value) < $unsigned(ex_rs2_value));
                    3'b111: ex_branch_taken =
                        ($unsigned(ex_rs1_value) >= $unsigned(ex_rs2_value));
                    default: ex_branch_taken = 1'b0;
                endcase
            end
            
            7'b1101111: begin
                ex_regwrite = 1'b1;
                ex_alu_result = idex_pc + 32'd4;
            end
            
            7'b1100111: begin
                if (ex_funct3 == 3'b000) begin
                    ex_regwrite = 1'b1;
                    ex_alu_result = idex_pc + 32'd4;
                end
            end

            7'b0110111: begin
                ex_regwrite = 1'b1;
                ex_alu_result = idex_imm;
            end

            7'b0010111: begin
                ex_regwrite = 1'b1;
                ex_alu_result = idex_pc + idex_imm;
            end

            default: begin end
        endcase

        ex_redirect = 1'b0;
        next_pc_target = ex_branch_target;

        if (idex_valid && ex_opcode == 7'b1101111) begin
            ex_redirect = 1'b1;
            next_pc_target = idex_pc + idex_imm;
        end else if (idex_valid && ex_opcode == 7'b1100111 &&
                     ex_funct3 == 3'b000) begin
            ex_redirect = 1'b1;
            next_pc_target = (ex_rs1_value + idex_imm) & 32'hFFFFFFFE;
        end else if (idex_valid && ex_opcode == 7'b1100011 &&
                     ex_branch_taken) begin
            ex_redirect = 1'b1;
            next_pc_target = idex_pc + idex_imm;
        end
    end

    assign dmem_addr  = exmem_alu_result;
    assign dmem_wdata = exmem_store_data;
    assign dmem_we    = exmem_valid && exmem_memwrite;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 32'b0;
            ifid_pc <= 32'b0;
            ifid_instr <= NOP;
            ifid_valid <= 1'b0;

            idex_pc <= 32'b0;
            idex_instr <= NOP;
            idex_rs1_value <= 32'b0;
            idex_rs2_value <= 32'b0;
            idex_imm <= 32'b0;
            idex_rs1 <= 5'b0;
            idex_rs2 <= 5'b0;
            idex_rd <= 5'b0;
            idex_valid <= 1'b0;

            exmem_pc4 <= 32'b0;
            exmem_alu_result <= 32'b0;
            exmem_store_data <= 32'b0;
            exmem_rd <= 5'b0;
            exmem_regwrite <= 1'b0;
            exmem_memread <= 1'b0;
            exmem_memwrite <= 1'b0;
            exmem_memtoreg <= 1'b0;
            exmem_valid <= 1'b0;

            memwb_pc4 <= 32'b0;
            memwb_alu_result <= 32'b0;
            memwb_load_data <= 32'b0;
            memwb_rd <= 5'b0;
            memwb_regwrite <= 1'b0;
            memwb_memtoreg <= 1'b0;
            memwb_valid <= 1'b0;

            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else begin
            regs[0] <= 32'b0;
            if (memwb_valid && memwb_regwrite && (memwb_rd != 5'd0))
                regs[memwb_rd] <= wb_value;

            if (ex_redirect) begin
                pc <= next_pc_target;
            end else if (!stall) begin
                pc <= pc + 32'd4;
            end

            if (ex_redirect) begin
                ifid_pc <= 32'b0;
                ifid_instr <= NOP;
                ifid_valid <= 1'b0;
            end else if (!stall) begin
                ifid_pc <= pc;
                ifid_instr <= imem_rdata;
                ifid_valid <= 1'b1;
            end

            if (ex_redirect || stall) begin
                idex_pc <= 32'b0;
                idex_instr <= NOP;
                idex_rs1_value <= 32'b0;
                idex_rs2_value <= 32'b0;
                idex_imm <= 32'b0;
                idex_rs1 <= 5'b0;
                idex_rs2 <= 5'b0;
                idex_rd <= 5'b0;
                idex_valid <= 1'b0;
            end else begin
                idex_pc <= ifid_pc;
                idex_instr <= ifid_valid ? ifid_instr : NOP;
                idex_rs1_value <= id_rs1_value;
                idex_rs2_value <= id_rs2_value;
                idex_imm <= ifid_imm;
                idex_rs1 <= ifid_rs1;
                idex_rs2 <= ifid_rs2;
                idex_rd <= ifid_rd;
                idex_valid <= ifid_valid;
            end

            exmem_pc4 <= idex_pc + 32'd4;
            exmem_alu_result <= ex_alu_result;
            exmem_store_data <= ex_store_data;
            exmem_rd <= ex_rd;
            exmem_regwrite <= idex_valid && ex_regwrite;
            exmem_memread <= idex_valid && ex_memread;
            exmem_memwrite <= idex_valid && ex_memwrite;
            exmem_memtoreg <= idex_valid && ex_memtoreg;
            exmem_valid <= idex_valid;

            memwb_pc4 <= exmem_pc4;
            memwb_alu_result <= exmem_alu_result;
            memwb_load_data <= dmem_rdata;
            memwb_rd <= exmem_rd;
            memwb_regwrite <= exmem_valid && exmem_regwrite;
            memwb_memtoreg <= exmem_valid && exmem_memtoreg;
            memwb_valid <= exmem_valid;
        end
    end

endmodule
