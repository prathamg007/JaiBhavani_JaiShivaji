function [stall, ifid_en, idex_flush, pc_en] = hazard_unit_func(id_rs, id_rt, ex_rt, ex_memread, branch_in_id)
% Classic load-use hazard
stall=false; ifid_en=true; idex_flush=false; pc_en=true;

if ex_memread && ((ex_rt==id_rs && id_rs~=0) || (ex_rt==id_rt && id_rt~=0))
    stall=true; ifid_en=false; idex_flush=true; pc_en=false;
end

if branch_in_id && ex_memread && (ex_rt==id_rs || ex_rt==id_rt)
    stall=true; ifid_en=false; idex_flush=true; pc_en=false;
end
end
