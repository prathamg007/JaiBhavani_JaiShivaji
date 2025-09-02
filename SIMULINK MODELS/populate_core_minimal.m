function populate_core_minimal(mdl, coreName)
% Populate a basic 5-stage (no-cache) pipeline inside mdl/coreName.
% Uses the single top-level RAM port already exposed by create_dualcore_model.
% Supported ops: ADDI, LW, SW, BEQ, J. Good enough to smoke-test.

if ~bdIsLoaded(mdl), load_system(mdl); end
cs = [mdl '/' coreName];
open_system(cs);

% ---- block helpers ----
blk = @(name) [cs '/' name];
add = @(lib,name,pos) add_block(lib,blk(name),'Position',pos);

% ========== IF stage ==========
add('simulink/Discrete/Unit Delay','PC',[120 60 180 90]); set_param(blk('PC'),'SampleTime','1','InitialCondition','0');
add('simulink/Math Operations/Add','PCp4',[210 60 260 90]); set_param(blk('PCp4'),'Inputs','++');
add('simulink/Sources/Constant','const4',[160 20 190 40]); set_param(blk('const4'),'Value','uint32(4)');
add('simulink/Signal Routing/Switch','PC_mux',[60 120 110 150]); set_param(blk('PC_mux'),'Criteria','u2 ~= 0');
add('simulink/Signal Routing/Switch','IF_MEM_ARB',[300 60 350 90]); set_param(blk('IF_MEM_ARB'),'Criteria','u2 ~= 0');

% ========== ID stage ==========
add('simulink/User-Defined Functions/MATLAB Function','decode',[430 40 600 120]);
set_param(blk('decode'),'Script', [
"function [op, useImm, memR, memW, br, jmp] = decode(instr)",newline, ...
"% very small decoder: ADDI (0x08), LW (0x23), SW (0x2B), BEQ(0x04), J(0x02)",newline, ...
"op=uint8(0); useImm=false; memR=false; memW=false; br=false; jmp=false;",newline, ...
"opc = bitshift(instr,-26);",newline, ...
"if opc==uint32(8)      % ADDI",newline, ...
"  op=uint8(0); useImm=true;",newline, ...
"elseif opc==uint32(35) % LW",newline, ...
"  op=uint8(0); useImm=true; memR=true;",newline, ...
"elseif opc==uint32(43) % SW",newline, ...
"  op=uint8(0); useImm=true; memW=true;",newline, ...
"elseif opc==uint32(4)  % BEQ",newline, ...
"  op=uint8(1); br=true;",newline, ...
"elseif opc==uint32(2)  % J",newline, ...
"  jmp=true;",newline, ...
"end",newline, ...
"end" ...
]);

% Reg file (System object you already have)
add('simulink/User-Defined Functions/MATLAB System','RegFile',[430 140 520 200]);
set_param(blk('RegFile'),'System','RegFileSys');

% Imm extender
add('simulink/User-Defined Functions/MATLAB Function','immext',[430 210 560 250]);
set_param(blk('immext'),'Script', [
"function imm = immext(instr)",newline, ...
"imm16 = bitand(instr,uint32(65535));",newline, ...
"if bitget(imm16,16)==1",newline, ...
"  imm = bitor(uint32(bitshift(uint32(65535),16)), imm16);",newline, ...
"else",newline, ...
"  imm = imm16;",newline, ...
"end",newline, ...
"end" ...
]);

% ========== EX stage ==========
add('simulink/User-Defined Functions/MATLAB Function','alu',[620 150 760 210]);
set_param(blk('alu'),'Script', [
"function y = alu(op,a,b)",newline, ...
"if op==0, y = uint32(uint32(a)+uint32(b));",newline, ...
"else,     y = uint32(a); end",newline, ...
"end" ...
]);

% Branch target calc
add('simulink/User-Defined Functions/MATLAB Function','br_target',[620 40 780 100]);
set_param(blk('br_target'),'Script', [
"function [take, target] = br_target(br,instr,pcp4)",newline, ...
"take=false; target=pcp4;",newline, ...
"if br",newline, ...
"  imm16 = bitand(instr,uint32(65535));",newline, ...
"  off = bitshift(uint32(imm16),2);",newline, ...
"  target = uint32(pcp4 + off); take=true;",newline, ...
"end",newline, ...
"end" ...
]);

% Jump target calc
add('simulink/User-Defined Functions/MATLAB Function','j_target',[620 250 780 310]);
set_param(blk('j_target'),'Script', [
"function [take, target] = j_target(j, instr)",newline, ...
"take=false; target=uint32(0);",newline, ...
"if j",newline, ...
"  tgt = bitand(instr,uint32(hex2dec('03FFFFFF')));",newline, ...
"  target = bitshift(tgt,2); take=true;",newline, ...
"end",newline, ...
"end" ...
]);

% ========== MEM stage ==========
% internal arbiter between IF fetch and data access
add('simulink/User-Defined Functions/MATLAB Function','mem_arb',[300 120 450 180]);
set_param(blk('mem_arb'),'Script', [
"function [REN,WEN,ADDR,STORE] = mem_arb(ifREN,ifADDR,memREN,memWEN,memADDR,memSTORE)",newline, ...
"% IF has priority over MEM for now",newline, ...
"if ifREN",newline, ...
"  REN = true; WEN=false; ADDR=ifADDR; STORE=uint32(0);",newline, ...
"elseif memREN||memWEN",newline, ...
"  REN = memREN; WEN = memWEN; ADDR = memADDR; STORE = memSTORE;",newline, ...
"else",newline, ...
"  REN=false; WEN=false; ADDR=uint32(0); STORE=uint32(0);",newline, ...
"end",newline, ...
"end" ...
]);

% ========== WB stage ==========
% Writeback mux
add('simulink/Signal Routing/Switch','wb_mux',[820 160 880 190]); set_param(blk('wb_mux'),'Criteria','u2 ~= 0');

% ========== small wires and tap blocks ==========
% From Core inports
add('simulink/Sinks/Terminator','term_irq',[90 100 100 110]);
add_line(cs,'irq_in/1','term_irq/1');

% PC path
add('simulink/Signal Routing/Mux','pc_mux',[20 50 40 100]);
add_line(cs,'ramload/1','PC/1'); % allow load into PC if needed (not used)
add_line(cs,'PC/1','PCp4/1');
add_line(cs,'const4/1','PCp4/2');
add_line(cs,'PCp4/1','br_target/3');

% Instruction fetch: use IF_MEM_ARB to choose IF read (always true) -> mem_arb
add('simulink/Sources/Constant','oneTrue',[250 120 270 140]); set_param(blk('oneTrue'),'Value','1');
add_line(cs,'PC/1','IF_MEM_ARB/1');
add_line(cs,'oneTrue/1','IF_MEM_ARB/2');  % request fetch
add_line(cs,'PC/1','IF_MEM_ARB/3');      % data ignored, just using switch pattern

% IF_MEM_ARB -> mem_arb IF inputs
add_line(cs,'IF_MEM_ARB/1','mem_arb/1'); % ifREN
add_line(cs,'PC/1','mem_arb/2');         % ifADDR

% RAM response -> instruction register (use Unit Delay as IF/ID.reg)
add('simulink/Discrete/Unit Delay','IFID_instr',[430 10 520 40]);
add_line(cs,'ramload/1','IFID_instr/1');

% Decode & imm
add_line(cs,'IFID_instr/1','decode/1');
add_line(cs,'IFID_instr/1','immext/1');

% Register file addressing
add('simulink/User-Defined Functions/MATLAB Function','rsrt',[430 270 560 320]);
set_param(blk('rsrt'),'Script', [
"function [rs,rt] = rsrt(instr)",newline, ...
"rs = uint8(bitand(bitshift(instr,-21),uint32(31)));",newline, ...
"rt = uint8(bitand(bitshift(instr,-16),uint32(31)));",newline, ...
"end" ...
]);
add_line(cs,'IFID_instr/1','rsrt/1');
add_line(cs,'rsrt/1','RegFile/1'); % rs
add_line(cs,'rsrt/2','RegFile/2'); % rt

% ALU operands & result
add('simulink/Signal Routing/Switch','Bsel',[590 200 610 220]); set_param(blk('Bsel'),'Criteria','u2 ~= 0');
add_line(cs,'RegFile/1','alu/2');
add_line(cs,'RegFile/2','Bsel/1');
add_line(cs,'immext/1','Bsel/3');
add_line(cs,'decode/2','Bsel/2');
add_line(cs,'Bsel/1','alu/3');

% Branch / Jump computations
add_line(cs,'decode/5','br_target/1'); % br
add_line(cs,'IFID_instr/1','br_target/2');
add_line(cs,'decode/6','j_target/1'); % j
add_line(cs,'IFID_instr/1','j_target/2');

% PC update mux (priority: jump > branch > +4)
add('simulink/Signal Routing/Switch','PC_sel_br',[820 40 870 70]); set_param(blk('PC_sel_br'),'Criteria','u2 ~= 0');
add('simulink/Signal Routing/Switch','PC_sel_j',[900 40 950 70]); set_param(blk('PC_sel_j'),'Criteria','u2 ~= 0');
add_line(cs,'PCp4/1','PC_sel_br/1');
add_line(cs,'br_target/2','PC_sel_br/3');
add_line(cs,'br_target/1','PC_sel_br/2');
add_line(cs,'PC_sel_br/1','PC_sel_j/1');
add_line(cs,'j_target/2','PC_sel_j/3');
add_line(cs,'j_target/1','PC_sel_j/2');
add_line(cs,'PC_sel_j/1','PC/1');

% Data-memory address = ALU result; mem controls from decoder
add('simulink/Sources/Constant','zeroU32',[590 240 610 260]); set_param(blk('zeroU32'),'Value','uint32(0)');
add('simulink/User-Defined Functions/MATLAB Function','mem_ctrl',[620 300 760 360]);
set_param(blk('mem_ctrl'),'Script', [
"function [mREN,mWEN,mADDR,mSTORE] = mem_ctrl(memR,memW,addr,rd2)",newline, ...
"mREN=memR; mWEN=memW; mADDR=addr; mSTORE=rd2;",newline, ...
"end" ...
]);

add_line(cs,'decode/3','mem_ctrl/1'); % memR
add_line(cs,'decode/4','mem_ctrl/2'); % memW
add_line(cs,'alu/1','mem_ctrl/3');   % addr
add_line(cs,'RegFile/2','mem_ctrl/4'); % store data

% Hook mem_ctrl into mem_arb MEM side
add_line(cs,'mem_ctrl/1','mem_arb/3'); % memREN
add_line(cs,'mem_ctrl/2','mem_arb/4'); % memWEN
add_line(cs,'mem_ctrl/3','mem_arb/5'); % memADDR
add_line(cs,'mem_ctrl/4','mem_arb/6'); % memSTORE

% mem_arb -> Core outports (drive top-level RAM)
add_line(cs,'mem_arb/1','ramREN/1');
add_line(cs,'mem_arb/2','ramWEN/1');
add_line(cs,'mem_arb/3','ramaddr/1');
add_line(cs,'mem_arb/4','ramstore/1');

% Writeback: mem_to_reg = memR
add_line(cs,'ramload/1','wb_mux/1');   % memory data
add_line(cs,'decode/3','wb_mux/2');    % select memory when memR
add_line(cs,'alu/1','wb_mux/3');       % ALU result
% Destination reg (rt for I-type)
add('simulink/User-Defined Functions/MATLAB Function','dest_rt',[820 210 940 250]);
set_param(blk('dest_rt'),'Script', [
"function rd = dest_rt(instr)",newline, ...
"rd = uint8(bitand(bitshift(instr,-16),uint32(31)));",newline, ...
"end" ...
]);
add_line(cs,'IFID_instr/1','dest_rt/1');

% Connect writeback to RegFile
add('simulink/Sources/Constant','oneBool',[900 270 920 290]); set_param(blk('oneBool'),'Value','true');
add_line(cs,'dest_rt/1','RegFile/3');  % rd
add_line(cs,'wb_mux/1','RegFile/4');   % wdata
add_line(cs,'oneBool/1','RegFile/5');  % wen (always true for this minimal core; decode can gate later)

end