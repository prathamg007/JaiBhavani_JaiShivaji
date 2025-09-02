function build_core_only_v2(save_dir)
% Creates CoreOnly.slx with one Core subsystem (IF->ID->EX->MEM->WB)
% and saves it to save_dir (defaults to pwd).

if nargin<1, save_dir = pwd; end
mdl = 'CoreOnly';
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist(fullfile(save_dir,[mdl '.slx']),'file')
    delete(fullfile(save_dir,[mdl '.slx']));
end

new_system(mdl); open_system(mdl);

% helpers
m      = @(p) [mdl '/' p];
addBlk = @(lib,parent,name,pos) add_block(lib,[parent '/' name], ...
                                          'Position',pos,'MakeNameUnique','off');

% ----------------------------------------------------------------------
% Make Core subsystem with I/O ports
% ----------------------------------------------------------------------
core = m('Core');
addBlk('simulink/Ports & Subsystems/Subsystem', mdl, 'Core', [90 80 1160 500]);
open_system(core);

% Inports
addBlk('simulink/Ports & Subsystems/In1', core, 'ramload',  [20 110 50 130]);
addBlk('simulink/Ports & Subsystems/In1', core, 'ramstate', [20 150 50 170]);
addBlk('simulink/Ports & Subsystems/In1', core, 'irq_in',   [20 190 50 210]);

% Outports
addBlk('simulink/Ports & Subsystems/Out1', core, 'ramREN',   [1090 110 1120 130]);
addBlk('simulink/Ports & Subsystems/Out1', core, 'ramWEN',   [1090 150 1120 170]);
addBlk('simulink/Ports & Subsystems/Out1', core, 'ramaddr',  [1090 190 1120 210]);
addBlk('simulink/Ports & Subsystems/Out1', core, 'ramstore', [1090 230 1120 250]);
addBlk('simulink/Ports & Subsystems/Out1', core, 'irq_out',  [1090 270 1120 290]);

% ----------------------------------------------------------------------
% IF stage
% ----------------------------------------------------------------------
addBlk('simulink/Discrete/Unit Delay', core, 'PC',      [210 60 260 90]);
set_param([core '/PC'],'InitialCondition','0');

addBlk('simulink/Sources/Constant',    core, 'const4',  [110 60 160 90]);
set_param([core '/const4'],'Value','uint32(4)');

addBlk('simulink/Math Operations/Add', core, 'PCp4',    [160 60 200 90]);
set_param([core '/PCp4'],'Inputs','++');

addBlk('simulink/Discrete/Unit Delay', core, 'IF_instr',[210 120 260 150]);

addBlk('simulink/Signal Routing/Bus Creator',core,'IFID_bus',[290 110 310 160]);
set_param([core '/IFID_bus'],'Inputs','2');

addBlk('simulink/Discrete/Unit Delay', core, 'IFID_hold',[350 120 400 150]);

% IF wiring
add_line(core,'const4/1','PCp4/2');
add_line(core,'PC/1','PCp4/1');
add_line(core,'ramload/1','IF_instr/1');
add_line(core,'PCp4/1','IFID_bus/1');
add_line(core,'IF_instr/1','IFID_bus/2');
add_line(core,'IFID_bus/1','IFID_hold/1');
add_line(core,'PCp4/1','PC/1','autorouting','on'); % sequential PC+4

% ----------------------------------------------------------------------
% ID stage blocks
% ----------------------------------------------------------------------
% MATLAB Function: control_decode (wrapper around your control_decode.m)
addBlk('simulink/User-Defined Functions/MATLAB Function', core, ...
       'control_decode', [440 100 620 220]);
set_param([core '/control_decode'],'Script', ...
['function [alu_op, alu_src_b_imm, reg_write, mem_read, mem_write, mem_to_reg, branch_type, jump, link, extop, shamt] = control_decode_wrap(instr)',newline,...
'%#codegen',newline,...
'coder.extrinsic(''control_decode'');',newline,...
'[alu_op, alu_src_b_imm, reg_write, mem_read, mem_write, mem_to_reg, branch_type, jump, link, extop, shamt] = control_decode(instr);',newline,...
'end']);

% MATLAB Function: rsrt
addBlk('simulink/User-Defined Functions/MATLAB Function', core, 'rsrt', [440 240 560 320]);
set_param([core '/rsrt'],'Script', ...
['function [rs,rt,rd,shamt,imm] = rsrt(instr)',newline,...
'rs    = uint8(bitand(bitshift(instr,-21),uint32(31)));',newline,...
'rt    = uint8(bitand(bitshift(instr,-16),uint32(31)));',newline,...
'rd    = uint8(bitand(bitshift(instr,-11),uint32(31)));',newline,...
'shamt = uint8(bitand(bitshift(instr,-6), uint32(31)));',newline,...
'imm   = uint32(bitand(instr, uint32(65535)));',newline,...
'end']);

% MATLAB System: RegFileSys
addBlk('simulink/User-Defined Functions/MATLAB System', core, 'RegFile', [650 230 740 340]);
set_param([core '/RegFile'],'System','RegFileSys');

% MATLAB Function: immext
addBlk('simulink/User-Defined Functions/MATLAB Function', core, 'immext', [630 360 750 420]);
set_param([core '/immext'],'Script', ...
['function imm32 = immext(imm,extop)',newline,...
'if extop==2, imm32 = bitshift(imm,16);',newline,...
'elseif extop==1, imm32 = uint32(imm);',newline,...
'else, imm32 = uint32( typecast( int16( typecast(uint16(imm),''int16'' ) ), ''uint32'' ) );',newline,...
'end',newline,'end']);

% ID wiring
add_line(core,'IFID_hold/1','control_decode/1');
add_line(core,'IFID_hold/1','rsrt/1');
add_line(core,'rsrt/1','RegFile/1'); % rs
add_line(core,'rsrt/2','RegFile/2'); % rt
add_line(core,'rsrt/5','immext/1');  % imm
add_line(core,'control_decode/10','immext/2'); % extop

% ----------------------------------------------------------------------
% EX stage
% ----------------------------------------------------------------------
addBlk('simulink/Signal Routing/Switch', core, 'Bsel', [800 360 840 420]);
set_param([core '/Bsel'],'Criteria','u2 ~= 0');

addBlk('simulink/User-Defined Functions/MATLAB Function', core, 'alu', [840 230 930 320]);
set_param([core '/alu'],'Script', ...
['function [y, zero, ovf] = alu_wrap(op,a,b,shamt)',newline,...
'%#codegen',newline,...
'coder.extrinsic(''alu_func'');',newline,...
'[y, zero, ovf] = alu_func(op,a,b,shamt);',newline,...
'end']);

% EX wiring
add_line(core,'RegFile/2','Bsel/1');                % rd2
add_line(core,'control_decode/2','Bsel/2');         % alu_src_b_imm
add_line(core,'immext/1','Bsel/3');                 % imm32
add_line(core,'RegFile/1','alu/2');                 % rd1
add_line(core,'Bsel/1','alu/3');                    % B
add_line(core,'control_decode/1','alu/1');          % alu_op
add_line(core,'rsrt/4','alu/4');                    % shamt

% ----------------------------------------------------------------------
% MEM stage
% ----------------------------------------------------------------------
% mem_ctrl
addBlk('simulink/User-Defined Functions/MATLAB Function', core, 'mem_ctrl', [940 110 1040 190]);
set_param([core '/mem_ctrl'],'Script', ...
['function [mREN,mWEN,mADDR,mSTORE] = mem_ctrl(memR,memW,addr,rd2)',newline,...
'mREN=memR; mWEN=memW; mADDR=addr; mSTORE=rd2;',newline,'end']);

% mem_arb
addBlk('simulink/User-Defined Functions/MATLAB Function', core, 'mem_arb', [960 210 1080 310]);
set_param([core '/mem_arb'],'Script', ...
['function [REN,WEN,ADDR,STORE] = mem_arb(ifREN,ifADDR,memREN,memWEN,memADDR,memSTORE)',newline,...
'if ifREN',newline,...
'  REN=true; WEN=false; ADDR=ifADDR; STORE=uint32(0);',newline,...
'elseif memREN || memWEN',newline,...
'  REN=memREN; WEN=memWEN; ADDR=memADDR; STORE=memSTORE;',newline,...
'else',newline,...
'  REN=false; WEN=false; ADDR=uint32(0); STORE=uint32(0);',newline,...
'end',newline,'end']);

% constants + WB mux
addBlk('simulink/Sources/Constant', core, 'trueC',  [930 60 960 80]); set_param([core '/trueC'],'Value','true');
addBlk('simulink/Logic and Bit Operations/Relational Operator', core, 'isMemToReg', [700 110 760 140]);
set_param([core '/isMemToReg'],'Operator','==');
addBlk('simulink/Sources/Constant', core, 'oneU8',  [670 60 700 80]); set_param([core '/oneU8'],'Value','uint8(1)');
addBlk('simulink/Signal Routing/Switch', core, 'wb_mux', [700 170 760 210]);
set_param([core '/wb_mux'],'Criteria','u2 ~= 0');

% MEM wiring
add_line(core,'control_decode/4','mem_ctrl/1'); % mem_read
add_line(core,'control_decode/5','mem_ctrl/2'); % mem_write
add_line(core,'alu/1','mem_ctrl/3');           % addr
add_line(core,'RegFile/2','mem_ctrl/4');       % store

add_line(core,'trueC/1','mem_arb/1');          % ifREN
add_line(core,'PC/1','mem_arb/2');             % ifADDR
add_line(core,'mem_ctrl/1','mem_arb/3');       % memREN
add_line(core,'mem_ctrl/2','mem_arb/4');       % memWEN
add_line(core,'mem_ctrl/3','mem_arb/5');       % memADDR
add_line(core,'mem_ctrl/4','mem_arb/6');       % memSTORE

add_line(core,'mem_arb/1','ramREN/1');
add_line(core,'mem_arb/2','ramWEN/1');
add_line(core,'mem_arb/3','ramaddr/1');
add_line(core,'mem_arb/4','ramstore/1');

% WB wiring
add_line(core,'ramload/1','wb_mux/1');
add_line(core,'control_decode/6','isMemToReg/1');
add_line(core,'oneU8/1','isMemToReg/2');
add_line(core,'isMemToReg/1','wb_mux/2');
add_line(core,'alu/1','wb_mux/3');

% RegFile writeback (temp: write to rt)
add_line(core,'rsrt/2','RegFile/3');     % dest = rt
add_line(core,'wb_mux/1','RegFile/4');   % wdata
add_line(core,'control_decode/3','RegFile/5'); % wen

% tie off irq_out
addBlk('simulink/Sources/Constant', core, 'zeroC',[1030 290 1060 310]);
set_param([core '/zeroC'],'Value','0');
add_line(core,'zeroC/1','irq_out/1');

% model options + save
set_param(mdl,'StopTime','100','SolverType','Fixed-step','Solver','FixedStepDiscrete');
save_system(mdl, fullfile(save_dir,[mdl '.slx']));
fprintf('Saved %s\n', fullfile(save_dir,[mdl '.slx']));
end