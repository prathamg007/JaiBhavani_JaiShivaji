function [alu_op, alu_src_b_imm, reg_write, mem_read, mem_write, mem_to_reg, ...
          branch_type, jump, link, extop, shamt] = control_decode(instr)
% Decode MIPS-like instruction

opcode = bitshift(instr, -26); % [31:26]
funct  = bitand(instr, uint32(63));
shamt  = uint8(bitand(bitshift(instr, -6), uint32(31)));

alu_op = uint8(AluOp.ADD);
alu_src_b_imm = false;
reg_write = false;
mem_read  = false;
mem_write = false;
mem_to_reg = uint8(0); % 0: ALU, 1: Mem, 2: Link
branch_type = uint8(BranchType.NONE);
jump = uint8(0);
link = false;
extop = uint8(ExtOp.SIGNED);

if opcode == 0 % R-type
    switch uint32(funct)
        case 32, alu_op=uint8(AluOp.ADD); reg_write=true;  % ADD
        case 34, alu_op=uint8(AluOp.SUB); reg_write=true;  % SUB
        case 36, alu_op=uint8(AluOp.AND); reg_write=true;  % AND
        case 37, alu_op=uint8(AluOp.OR);  reg_write=true;  % OR
        case 42, alu_op=uint8(AluOp.SLT); reg_write=true;  % SLT
        case 8,  branch_type=uint8(BranchType.JR);         % JR
    end
else
    switch uint32(opcode)
        case 35, alu_op=uint8(AluOp.ADD); alu_src_b_imm=true; reg_write=true; mem_read=true; mem_to_reg=1; % LW
        case 43, alu_op=uint8(AluOp.ADD); alu_src_b_imm=true; mem_write=true; % SW
        case 4,  alu_op=uint8(AluOp.SUB); branch_type=uint8(BranchType.BEQ);
        case 5,  alu_op=uint8(AluOp.SUB); branch_type=uint8(BranchType.BNE);
        case 2,  branch_type=uint8(BranchType.J);
        case 3,  branch_type=uint8(BranchType.J); link=true; mem_to_reg=2;
        case 8,  alu_op=uint8(AluOp.ADD); alu_src_b_imm=true; reg_write=true; % ADDI
        case 12, alu_op=uint8(AluOp.AND); alu_src_b_imm=true; reg_write=true; extop=uint8(ExtOp.UNSIGNED); % ANDI
        case 13, alu_op=uint8(AluOp.OR);  alu_src_b_imm=true; reg_write=true; extop=uint8(ExtOp.UNSIGNED); % ORI
        case 15, alu_op=uint8(AluOp.PASSB); alu_src_b_imm=true; reg_write=true; extop=uint8(ExtOp.LUI);   % LUI
    end
end
end