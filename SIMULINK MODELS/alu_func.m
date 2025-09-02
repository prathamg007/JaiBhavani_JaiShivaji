function [y, zero, ovf] = alu_func(op, a, b, shamt)
% Simple 32-bit ALU
a = uint32(a); b = uint32(b); sa = int32(a); sb = int32(b);

switch uint8(op)
    case uint8(AluOp.ADD)
        tmp = uint64(a) + uint64(b);
        y = uint32(bitand(tmp, uint64(2^32-1)));
        ovf = tmp > uint64(2^32-1);
    case uint8(AluOp.SUB)
        tmp = int64(sa) - int64(sb);
        y = uint32(typecast(int32(tmp), 'uint32'));
        ovf = (tmp > int64(intmax('int32'))) || (tmp < int64(intmin('int32')));
    case uint8(AluOp.AND),  y = bitand(a,b); ovf=false;
    case uint8(AluOp.OR),   y = bitor(a,b);  ovf=false;
    case uint8(AluOp.XOR),  y = bitxor(a,b); ovf=false;
    case uint8(AluOp.NOR),  y = bitcmp(bitor(a,b),'uint32'); ovf=false;
    case uint8(AluOp.SLL),  y = bitshift(b, int16(shamt)); ovf=false;
    case uint8(AluOp.SRL),  y = bitshift(b, -int16(shamt)); ovf=false;
    case uint8(AluOp.SRA),  y = uint32(bitshift(sa, -int16(shamt))); ovf=false;
    case uint8(AluOp.SLT),  y = uint32(sa < sb); ovf=false;
    case uint8(AluOp.SLTU), y = uint32(a < b); ovf=false;
    case uint8(AluOp.PASSB),y = b; ovf=false;
    otherwise,              y = uint32(0); ovf=false;
end
zero = (y == 0);
end