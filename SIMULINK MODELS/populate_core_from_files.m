function populate_core_from_files(modelName, coreName)
% Populate a 5-stage pipeline inside modelName/coreName using your MATLAB files.
% Requirements (on path): build_buses, RegFileSys, alu_func, control_decode,
% forwarding_unit_func, hazard_unit_func.
%
% Top-level Core ports (already exist from create_dualcore_model):
%   In : ramload(uint32), ramstate(uint8), irq_in
%   Out: ramREN(bool), ramWEN(bool), ramaddr(uint32), ramstore(uint32), irq_out

assert(bdIsLoaded(modelName), 'Open the model first.');
cs = [modelName '/' coreName];
open_system(cs);

% Helpers
B = @(p) [cs '/' p];
add = @(lib,name,xy) add_block(lib,B(name),'Position',xy);

%% ---------------- IF stage ----------------
add('simulink/Discrete/Unit Delay','PC',[80 60 140 90]);  set_param(B('PC'),'InitialCondition','0');
add('simulink/Math Operations/Add','PCp4',[170 60 220 90]); set_param(B('PCp4'),'Inputs','++');
add('simulink/Sources/Constant','const4',[120 20 150 40]); set_param(B('const4'),'Value','uint32(4)');

% IF/ID register (Bus = IFID)
add('simulink/Signal Routing/Bus Creator','IFID_bus',[380 55 430 105]);
set_param(B('IFID_bus'),'Inputs','2');
add('simulink/Discrete/Unit Delay','IFID_hold',[450 60 520 100]); % simple hold; use Enable/Reset later

% Instruction register is driven by ramload (fetch)
add('simulink/Discrete/Unit Delay','IF_instr',[300 20 360 50]);
add('simulink/Signal Routing/Switch','pc_update',[230 40 280 70]); set_param(B('pc_update'),'Criteria','u2 ~= 0');

%% ---------------- ID stage ----------------
add('simulink/User-Defined Functions/MATLAB Function','control_decode',[560 20 740 110]);
set_param(B('control_decode'),'Script', fileread(which('control_decode.m')));

% Register File
add('simulink/User-Defined Functions/MATLAB System','RegFile',[560 130 660 190]); set_param(B('RegFile'),'System','RegFileSys');

% rs/rt extract
add('simulink/User-Defined Functions/MATLAB Function','rsrt',[560 200 690 240]); set_param(B('rsrt'),'Script', ...
"function [rs,rt,rd,shamt,imm] = rsrt(instr)" + newline + ...
"rs = uint8(bitand(bitshift(instr,-21),uint32(31)));" + newline + ...
"rt = uint8(bitand(bitshift(instr,-16),uint32(31)));" + newline + ...
"rd = uint8(bitand(bitshift(instr,-11),uint32(31)));" + newline + ...
"shamt = uint8(bitand(bitshift(instr,-6),uint32(31)));" + newline + ...
"imm = uint32(bitand(instr,uint32(65535)));" + newline + "end");

% Sign/zero/LUI extender (simple)
add('simulink/User-Defined Functions/MATLAB Function','immext',[560 250 690 300]); set_param(B('immext'),'Script', ...
"function imm32 = immext(imm,extop)" + newline + ...
"% extop: 0 SIGNED, 1 UNSIGNED, 2 LUI" + newline + ...
"if extop==2, imm32 = bitshift(imm,16);" + newline + ...
"elseif extop==1, imm32 = uint32(imm);" + newline + ...
"else, imm32 = uint32(typecast(int32(bitshift(int32(imm),0)), 'uint32'));" + newline + ...
"end");

% Hazard unit (stall/flush/pc_en)
add('simulink/User-Defined Functions/MATLAB Function','hazard',[720 130 880 190]);
set_param(B('hazard'),'Script', fileread(which('hazard_unit_func.m')));

%% ---------------- EX stage ----------------
add('simulink/User-Defined Functions/MATLAB Function','fwd',[720 200 880 260]);
set_param(B('fwd'),'Script', fileread(which('forwarding_unit_func.m')));

add('simulink/Signal Routing/Switch','selA',[910 175 960 205]); set_param(B('selA'),'Criteria','u2 == 1');  % 1=EX/MEM, 2=MEM/WB
add('simulink/Signal Routing/Switch','selA2',[970 175 1020 205]); set_param(B('selA2'),'Criteria','u2 == 2');
add('simulink/Signal Routing/Switch','selB',[910 215 960 245]); set_param(B('selB'),'Criteria','u2 == 1');
add('simulink/Signal Routing/Switch','selB2',[970 215 1020 245]); set_param(B('selB2'),'Criteria','u2 == 2');

add('simulink/User-Defined Functions/MATLAB Function','alu',[1040 180 1180 240]); 
set_param(B('alu'),'Script', fileread(which('alu_func.m')));

% EX/MEM bus placeholders (use Bus Creator later if you prefer)
add('simulink/Signal Routing/Bus Creator','EXMEM_bus',[1200 170 1250 230]); set_param(B('EXMEM_bus'),'Inputs','3');

%% ---------------- MEM stage ----------------
% Very small internal arbiter between IF fetch and data access to the single external RAM port
add('simulink/User-Defined Functions/MATLAB Function','mem_arb',[300 120 470 180]); set_param(B('mem_arb'),'Script', ...
"function [REN,WEN,ADDR,STORE] = mem_arb(ifREN,ifADDR,memREN,memWEN,memADDR,memSTORE)" + newline + ...
"% IF has priority" + newline + ...
"if ifREN, REN=true; WEN=false; ADDR=ifADDR; STORE=uint32(0);" + newline + ...
"elseif memREN||memWEN, REN=memREN; WEN=memWEN; ADDR=memADDR; STORE=memSTORE;" + newline + ...
"else, REN=false; WEN=false; ADDR=uint32(0); STORE=uint32(0); end" + newline + "end");

% Address/data mux for D side
add('simulink/User-Defined Functions/MATLAB Function','mem_ctrl',[1200 240 1340 300]); set_param(B('mem_ctrl'),'Script', ...
"function [mREN,mWEN,mADDR,mSTORE] = mem_ctrl(memR,memW,addr,rd2)" + newline + ...
"mREN=memR; mWEN=memW; mADDR=addr; mSTORE=rd2;" + newline + "end");

%% ---------------- WB stage ----------------
add('simulink/Signal Routing/Switch','wb_mux',[1360 180 1420 210]); set_param(B('wb_mux'),'Criteria','u2 ~= 0');

% Write enables
add('simulink/Sources/Constant','falseC',[1420 220 1440 240]); set_param(B('falseC'),'Value','false');

%% ========== WIRING ==========

% PC -> PC+4
add_line(cs,'PC/1','PCp4/1'); add_line(cs,'const4/1','PCp4/2');

% IF controls: always fetch (you can gate with hazards later)
add('simulink/Sources/Constant','trueC',[200 120 220 140]); set_param(B('trueC'),'Value','true');

% IF fetch: PC to mem_arb IF side
add_line(cs,'trueC/1','mem_arb/1');       % ifREN
add_line(cs,'PC/1','mem_arb/2');          % ifADDR

% RAM load -> IF_instr (instruction)
add_line(cs,'ramload/1','IF_instr/1');

% IF/ID bus contents
add_line(cs,'PCp4/1','IFID_bus/1');      % pc+4
add_line(cs,'IF_instr/1','IFID_bus/2');  % instr
add_line(cs,'IFID_bus/1','IFID_hold/1');

% ID inputs from IF/ID
add_line(cs,'IFID_hold/1','control_decode/1');
add_line(cs,'IFID_hold/1','rsrt/1');

% RegFile read
add_line(cs,'rsrt/1','RegFile/1'); % rs
add_line(cs,'rsrt/2','RegFile/2'); % rt

% Imm extend: control_decode returns 'extop' as output #10 in our earlier version; if your file differs, adjust
% (For robustness, just feed sign-extended immediate from rsrt)
add_line(cs,'rsrt/5','immext/1');
add('simulink/Sources/Constant','extop_signed',[520 260 540 280]); set_param(B('extop_signed'),'Value','uint8(0)');
add_line(cs,'extop_signed/1','immext/2');

% Hazard unit (very basic hookup)
% id_rs, id_rt, ex_rt, ex_memread, branch_in_id
add('simulink/Sources/Constant','zeroU8',[700 210 720 230]); set_param(B('zeroU8'),'Value','uint8(0)');
add('simulink/Sources/Constant','falseB',[700 240 720 260]); set_param(B('falseB'),'Value','false');
add_line(cs,'rsrt/1','hazard/1'); add_line(cs,'rsrt/2','hazard/2');
add_line(cs,'zeroU8/1','hazard/3'); add_line(cs,'falseB/1','hazard/4'); add_line(cs,'falseB/1','hazard/5');

% Forwarding unit (hook with placeholders now)
add_line(cs,'zeroU8/1','fwd/1'); add_line(cs,'zeroU8/1','fwd/2'); % idex_rs/rt
add_line(cs,'zeroU8/1','fwd/3'); add_line(cs,'falseB/1','fwd/4');  % exmem rd/regwrite
add_line(cs,'zeroU8/1','fwd/5'); add_line(cs,'falseB/1','fwd/6');  % memwb rd/regwrite

% Operand selection: use raw regfile and imm for now
% selA chain
add_line(cs,'RegFile/1','selA/1'); add_line(cs,'RegFile/1','selA2/1');
add('simulink/Sources/Constant','A_fwd_sel',[900 155 920 170]); set_param(B('A_fwd_sel'),'Value','uint8(0)');
add_line(cs,'A_fwd_sel/1','selA/2'); add_line(cs,'selA/1','selA2/1');
add('simulink/Sources/Constant','zeroU32',[890 130 910 150]); set_param(B('zeroU32'),'Value','uint32(0)');
add_line(cs,'zeroU32/1','selA2/3'); % if from MEM/WB, placeholder
% selB chain + immediate select
add_line(cs,'RegFile/2','selB/1'); add_line(cs,'RegFile/2','selB2/1');
add('simulink/Sources/Constant','B_fwd_sel',[900 235 920 250]); set_param(B('B_fwd_sel'),'Value','uint8(0)');
add_line(cs,'B_fwd_sel/1','selB/2'); add_line(cs,'selB/1','selB2/1');
add_line(cs,'immext/1','selB2/3'); % choose imm as final

% ALU
add_line(cs,'selA2/1','alu/2'); add_line(cs,'selB2/1','alu/3');
% For now op=ADD (wire from control later)
add('simulink/Sources/Constant','ALUopADD',[1020 150 1040 170]); set_param(B('ALUopADD'),'Value','uint8(0)');
add_line(cs,'ALUopADD/1','alu/1');

% EXMEM bus (we carry: alu_out, rd2, control bits)
add_line(cs,'alu/1','EXMEM_bus/1');
add_line(cs,'RegFile/2','EXMEM_bus/2');
% 'mem_to_reg' (0 ALU / 1 MEM) and 'reg_write' enable from control_decode later; for now constants
add('simulink/Sources/Constant','memtoregC',[1180 150 1200 170]); set_param(B('memtoregC'),'Value','uint8(0)');
add_line(cs,'memtoregC/1','EXMEM_bus/3');

% D side memory controls
add_line(cs,'EXMEM_bus/1','mem_ctrl/3'); % addr
add_line(cs,'EXMEM_bus/2','mem_ctrl/4'); % store data
% from control_decode (for now constants false)
add('simulink/Sources/Constant','memR0',[1160 240 1180 260]); set_param(B('memR0'),'Value','false');
add('simulink/Sources/Constant','memW0',[1160 270 1180 290]); set_param(B('memW0'),'Value','false');
add_line(cs,'memR0/1','mem_ctrl/1'); add_line(cs,'memW0/1','mem_ctrl/2');

% Internal arbiter: IF side (trueC + PC), MEM side (mem_ctrl outs)
add_line(cs,'trueC/1','mem_arb/1'); add_line(cs,'PC/1','mem_arb/2');
add_line(cs,'mem_ctrl/1','mem_arb/3'); add_line(cs,'mem_ctrl/2','mem_arb/4');
add_line(cs,'mem_ctrl/3','mem_arb/5'); add_line(cs,'mem_ctrl/4','mem_arb/6');

% Drive Core top ports
add_line(cs,'mem_arb/1','ramREN/1'); add_line(cs,'mem_arb/2','ramWEN/1');
add_line(cs,'mem_arb/3','ramaddr/1'); add_line(cs,'mem_arb/4','ramstore/1');

% WB mux: select memory when mem_read, else ALU
add_line(cs,'ramload/1','wb_mux/1'); add_line(cs,'memR0/1','wb_mux/2'); add_line(cs,'alu/1','wb_mux/3');

% Destination reg (rt by default)
add('simulink/User-Defined Functions/MATLAB Function','dest_rt',[1360 220 1480 260]); set_param(B('dest_rt'),'Script', ...
"function rd = dest_rt(instr)" + newline + "rd = uint8(bitand(bitshift(instr,-16),uint32(31))); end");
add_line(cs,'IFID_hold/1','dest_rt/1');

% Writeback to RegFile (always write for now)
add('simulink/Sources/Constant','wenTrue',[1460 270 1480 290]); set_param(B('wenTrue'),'Value','true');
add_line(cs,'dest_rt/1','RegFile/3'); add_line(cs,'wb_mux/1','RegFile/4'); add_line(cs,'wenTrue/1','RegFile/5');

% Update PC: simply +4 for now (you’ll add branch/jump later)
add_line(cs,'PCp4/1','PC/1');

% Tidy
Simulink.BlockDiagram.arrangeSystem(cs);
end