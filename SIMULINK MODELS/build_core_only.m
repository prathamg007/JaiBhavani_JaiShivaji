function build_core_only(save_dir)
% build_core_only(save_dir)
% Creates CoreOnly.slx with one Core subsystem and saves it to save_dir.
% If save_dir is omitted, uses pwd.

if nargin<1, save_dir = pwd; end
mdl = 'CoreOnly';
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([save_dir filesep mdl '.slx'],'file'), delete([save_dir filesep mdl '.slx']); end

new_system(mdl); open_system(mdl);

%% --- Helpers
blk = @(p) [mdl '/' p];
add = @(lib,name,pos) add_block(lib, blk(name), 'Position', pos);

% Small utility to create MATLAB Function block with given script
function add_mf(name, code, pos)
    add_block('simulink/User-Defined Functions/MATLAB Function', blk(name), 'Position', pos);
    set_param(blk(name),'Script', code);
end

%% --- Top-level Core subsystem I/O (so you can copy this Core anywhere)
core = 'Core';
add_block('simulink/Ports & Subsystems/Subsystem', blk(core), 'Position',[90 80 1160 500]);
open_system(blk(core));

% Inports
add_block('simulink/Ports & Subsystems/In1',  [blk(core) '/ramload'],  'Position',[20 110 50 130]);
add_block('simulink/Ports & Subsystems/In1',  [blk(core) '/ramstate'], 'Position',[20 150 50 170]);
add_block('simulink/Ports & Subsystems/In1',  [blk(core) '/irq_in'],   'Position',[20 190 50 210]);

% Outports
add_block('simulink/Ports & Subsystems/Out1', [blk(core) '/ramREN'],   'Position',[1090 110 1120 130]);
add_block('simulink/Ports & Subsystems/Out1', [blk(core) '/ramWEN'],   'Position',[1090 150 1120 170]);
add_block('simulink/Ports & Subsystems/Out1', [blk(core) '/ramaddr'],  'Position',[1090 190 1120 210]);
add_block('simulink/Ports & Subsystems/Out1', [blk(core) '/ramstore'], 'Position',[1090 230 1120 250]);
add_block('simulink/Ports & Subsystems/Out1', [blk(core) '/irq_out'],  'Position',[1090 270 1120 290]);

%% --- IF stage
add('simulink/Discrete/Unit Delay','PC',[210 60 260 90]);
set_param([blk(core) '/PC'],'InitialCondition','0');

add('simulink/Sources/Constant','const4',[110 60 160 90]);
set_param([blk(core) '/const4'],'Value','uint32(4)');

add('simulink/Math Operations/Add','PCp4',[160 60 200 90]); set_param([blk(core) '/PCp4'],'Inputs','++');

add('simulink/Discrete/Unit Delay','IF_instr',[210 120 260 150]);

add('simulink/Signal Routing/Bus Creator','IFID_bus',[290 110 310 160]);
set_param([blk(core) '/IFID_bus'],'Inputs','2');

add('simulink/Discrete/Unit Delay','IFID_hold',[350 120 400 150]);

% wires IF
add_line(blk(core),'const4/1','PCp4/2');
add_line(blk(core),'PC/1','PCp4/1');
add_line(blk(core),'ramload/1','IF_instr/1');
add_line(blk(core),'PCp4/1','IFID_bus/1');
add_line(blk(core),'IF_instr/1','IFID_bus/2');
add_line(blk(core),'IFID_bus/1','IFID_hold/1');
% (PC update) sequential for now
add_line(blk(core),'PCp4/1','PC/1','autorouting','on');

%% --- ID stage blocks
% control_decode wrapper (calls your control_decode.m)
code_cd = [
'function [alu_op, alu_src_b_imm, reg_write, mem_read, mem_write, mem_to_reg, branch_type, jump, link, extop, shamt] = control_decode_wrap(instr)\n' ...
'%#codegen\n' ...
'coder.extrinsic(''control_decode'');\n' ...
'[alu_op, alu_src_b_imm, reg_write, mem_read, mem_write, mem_to_reg, branch_type, jump, link, extop, shamt] = control_decode(instr);\n' ...
'end\n'];
add_mf('control_decode', code_cd, [440 100 620 220]);

% rsrt extractor
code_rsrt = [
'function [rs,rt,rd,shamt,imm] = rsrt(instr)\n' ...
'rs    = uint8(bitand(bitshift(instr,-21),uint32(31)));\n' ...
'rt    = uint8(bitand(bitshift(instr,-16),uint32(31)));\n' ...
'rd    = uint8(bitand(bitshift(instr,-11),uint32(31)));\n' ...
'shamt = uint8(bitand(bitshift(instr,-6), uint32(31)));\n' ...
'imm   = uint32(bitand(instr, uint32(65535)));\n' ...
'end\n'];
add_mf('rsrt', code_rsrt, [440 240 560 320]);

% RegFile (MATLAB System)
add_block('simulink/User-Defined Functions/MATLAB System', [blk(core) '/RegFile'], 'Position',[650 230 740 340]);
set_param([blk(core) '/RegFile'],'System','RegFileSys');

% immext
code_immext = [
'function imm32 = immext(imm,extop)\n' ...
'% 0 SIGNED, 1 UNSIGNED, 2 LUI\n' ...
'if extop==2\n' ...
'    imm32 = bitshift(imm,16);\n' ...
'elseif extop==1\n' ...
'    imm32 = uint32(imm);\n' ...
'else\n' ...
'    imm32 = uint32( typecast( int16( typecast(uint16(imm),''int16'') ), ''uint32'' ) );\n' ...
'end\n' ...
'end\n'];
add_mf('immext', code_immext, [630 360 750 420]);

% Wires ID
add_line(blk(core),'IFID_hold/1','control_decode/1');
add_line(blk(core),'IFID_hold/1','rsrt/1');
add_line(blk(core),'rsrt/1','RegFile/1'); % rs
add_line(blk(core),'rsrt/2','RegFile/2'); % rt
add_line(blk(core),'rsrt/5','immext/1');  % imm
add_line(blk(core),'control_decode/10','immext/2'); % extop

%% --- EX stage blocks
% Bsel mux
add('simulink/Signal Routing/Switch','Bsel',[800 360 840 420]); set_param([blk(core) '/Bsel'],'Criteria','u2 ~= 0');

% ALU wrapper (calls your alu_func.m)
code_alu = [
'function [y, zero, ovf] = alu_wrap(op,a,b,shamt)\n' ...
'%#codegen\n' ...
'coder.extrinsic(''alu_func'');\n' ...
'[y, zero, ovf] = alu_func(op,a,b,shamt);\n' ...
'end\n'];
add_mf('alu', code_alu, [840 230 930 320]);

% wires EX
add_line(blk(core),'RegFile/2','Bsel/1');                   % rd2 → Bsel.u1
add_line(blk(core),'control_decode/2','Bsel/2');            % alu_src_b_imm
add_line(blk(core),'immext/1','Bsel/3');                    % imm32 → Bsel.u3
add_line(blk(core),'RegFile/1','alu/2');                    % rd1 → alu.a
add_line(blk(core),'Bsel/1','alu/3');                       % Bsel → alu.b
add_line(blk(core),'control_decode/1','alu/1');             % alu_op → alu.op
add_line(blk(core),'rsrt/4','alu/4');                       % shamt

%% --- MEM stage helpers
% mem_ctrl
code_memctrl = [
'function [mREN,mWEN,mADDR,mSTORE] = mem_ctrl(memR,memW,addr,rd2)\n' ...
'mREN=memR; mWEN=memW; mADDR=addr; mSTORE=rd2;\n' ...
'end\n'];
add_mf('mem_ctrl', code_memctrl, [940 110 1040 190]);

% mem_arb
code_memarb = [
'function [REN,WEN,ADDR,STORE] = mem_arb(ifREN,ifADDR,memREN,memWEN,memADDR,memSTORE)\n' ...
'if ifREN\n' ...
'  REN=true; WEN=false; ADDR=ifADDR; STORE=uint32(0);\n' ...
'elseif memREN || memWEN\n' ...
'  REN=memREN; WEN=memWEN; ADDR=memADDR; STORE=memSTORE;\n' ...
'else\n' ...
'  REN=false; WEN=false; ADDR=uint32(0); STORE=uint32(0);\n' ...
'end\n' ...
'end\n'];
add_mf('mem_arb', code_memarb, [960 210 1080 310]);

% constants & compare & wb mux
add('simulink/Sources/Constant','trueC',[930 60 960 80]); set_param([blk(core) '/trueC'],'Value','true');
add('simulink/Logic and Bit Operations/Relational Operator','isMemToReg',[700 110 760 140]);
set_param([blk(core) '/isMemToReg'],'Operator','==');
add('simulink/Sources/Constant','oneU8',[670 60 700 80]); set_param([blk(core) '/oneU8'],'Value','uint8(1)');
add('simulink/Signal Routing/Switch','wb_mux',[700 170 760 210]); set_param([blk(core) '/wb_mux'],'Criteria','u2 ~= 0');

% wires MEM + WB
% mem_ctrl inputs
add_line(blk(core),'control_decode/4','mem_ctrl/1'); % mem_read
add_line(blk(core),'control_decode/5','mem_ctrl/2'); % mem_write
add_line(blk(core),'alu/1','mem_ctrl/3');            % addr = alu_y
add_line(blk(core),'RegFile/2','mem_ctrl/4');        % store data = rd2

% mem_arb inputs
add_line(blk(core),'trueC/1','mem_arb/1');           % ifREN
add_line(blk(core),'PC/1','mem_arb/2');              % ifADDR
add_line(blk(core),'mem_ctrl/1','mem_arb/3');        % memREN
add_line(blk(core),'mem_ctrl/2','mem_arb/4');        % memWEN
add_line(blk(core),'mem_ctrl/3','mem_arb/5');        % memADDR
add_line(blk(core),'mem_ctrl/4','mem_arb/6');        % memSTORE

% to Core outports
add_line(blk(core),'mem_arb/1','ramREN/1');
add_line(blk(core),'mem_arb/2','ramWEN/1');
add_line(blk(core),'mem_arb/3','ramaddr/1');
add_line(blk(core),'mem_arb/4','ramstore/1');

% WB path
add_line(blk(core),'ramload/1','wb_mux/1');
add_line(blk(core),'control_decode/6','isMemToReg/1');
add_line(blk(core),'oneU8/1','isMemToReg/2');
add_line(blk(core),'isMemToReg/1','wb_mux/2');
add_line(blk(core),'alu/1','wb_mux/3');

% RegFile writeback (write to rt for bring-up)
add_line(blk(core),'rsrt/2','RegFile/3');     % rd (dest) = rt (temp choice)
add_line(blk(core),'wb_mux/1','RegFile/4');   % wdata
add_line(blk(core),'control_decode/3','RegFile/5'); % wen

% Tie off irq_out for now
add_block('simulink/Sources/Constant', [blk(core) '/zeroC'], 'Position',[1030 290 1060 310]); set_param([blk(core) '/zeroC'],'Value','0');
add_line(blk(core),'zeroC/1','irq_out/1');

%% --- Save
set_param(mdl,'StopTime','100','SolverType','Fixed-step','Solver','FixedStepDiscrete');
save_system(mdl, [save_dir filesep mdl '.slx']);
fprintf('Saved %s\n', [save_dir filesep mdl '.slx']);
end