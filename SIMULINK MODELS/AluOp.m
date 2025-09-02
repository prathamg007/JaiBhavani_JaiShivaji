classdef AluOp < uint8
    % ALU operation selector (MIPS-like)
    enumeration
        ADD (0)
        SUB (1)
        AND (2)
        OR  (3)
        XOR (4)
        SLL (5)
        SRL (6)
        SRA (7)
        SLT (8)
        SLTU(9)
        NOR (10)
        PASSB (11) % e.g. for LUI
    end
end