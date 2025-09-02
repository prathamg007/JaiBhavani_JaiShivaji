function [selA, selB] = forwarding_unit_func(idex_rs, idex_rt, exmem_rd, exmem_regwrite, memwb_rd, memwb_regwrite)
selA = uint8(ForwardSel.FROM_IDEX);
selB = uint8(ForwardSel.FROM_IDEX);

if exmem_regwrite && exmem_rd ~= 0 && exmem_rd == idex_rs
    selA = uint8(ForwardSel.FROM_EXMEM);
elseif memwb_regwrite && memwb_rd ~= 0 && memwb_rd == idex_rs
    selA = uint8(ForwardSel.FROM_MEMWB);
end

if exmem_regwrite && exmem_rd ~= 0 && exmem_rd == idex_rt
    selB = uint8(ForwardSel.FROM_EXMEM);
elseif memwb_regwrite && memwb_rd ~= 0 && memwb_rd == idex_rt
    selB = uint8(ForwardSel.FROM_MEMWB);
end
end
