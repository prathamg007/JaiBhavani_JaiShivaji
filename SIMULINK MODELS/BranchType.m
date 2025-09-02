classdef BranchType < uint8
    % Branch type encoding
    enumeration
        NONE (0)
        BEQ  (1)
        BNE  (2)
        J    (3)
        JAL  (4)
        JR   (5)
    end
end