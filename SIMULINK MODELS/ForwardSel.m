classdef ForwardSel < uint8
    % Forwarding select for operand muxes
    enumeration
        FROM_IDEX   (0) % value in pipeline reg
        FROM_EXMEM  (1) % forwarded from EX/MEM
        FROM_MEMWB  (2) % forwarded from MEM/WB
    end
end