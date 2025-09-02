function mdl = create_dualcore_model(mdl)
%CREATE_DUALCORE_MODEL Build a dual-core scaffold (portable blocks only).
% Usage:
%   mdl = create_dualcore_model;            % 'DualMIPS_sim'
%   mdl = create_dualcore_model('MyModel'); % custom name

if nargin < 1, mdl = 'DualMIPS_sim'; end
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl); open_system(mdl);

set_param(mdl,'Solver','FixedStepDiscrete','FixedStep','1',...
                'StartTime','0','StopTime','1000');

%% ---------- Core subsystems ----------
add_block('built-in/Subsystem',[mdl '/Core1'],'Position',[100  80 300 240]);
add_block('built-in/Subsystem',[mdl '/Core2'],'Position',[100 300 300 460]);

for c = 1:2
    cs = sprintf('%s/Core%d',mdl,c);
    open_system(cs);
    % Inports
    add_block('built-in/Inport', [cs '/ramload'],  'Position',[20  40 50  54]);
    add_block('built-in/Inport', [cs '/ramstate'], 'Position',[20  70 50  84]);
    add_block('built-in/Inport', [cs '/irq_in'],   'Position',[20 100 50 114]);
    % Outports
    add_block('built-in/Outport',[cs '/ramREN'],   'Position',[380  40 410  54]);
    add_block('built-in/Outport',[cs '/ramWEN'],   'Position',[380  70 410  84]);
    add_block('built-in/Outport',[cs '/ramaddr'],  'Position',[380 100 410 114]);
    add_block('built-in/Outport',[cs '/ramstore'], 'Position',[380 130 410 144]);
    add_block('built-in/Outport',[cs '/irq_out'],  'Position',[380 160 410 174]);
    close_system(cs);
end

%% ---------- Memory Controller ----------
add_block('simulink/User-Defined Functions/MATLAB System', [mdl '/MemCtrl'], ...
          'System','MemCtrlSys','Position',[560 180 680 240]);

%% ---------- Arbiter (Core1 priority) ----------
arb = [mdl '/Arbiter'];
add_block('built-in/Subsystem',arb,'Position',[350 180 510 320]);
open_system(arb);

% Inports
inps = {'c1REN','c1WEN','c1addr','c1store','c2REN','c2WEN','c2addr','c2store','ramload','ramstate'};
y = 30;
for k=1:numel(inps)
    add_block('built-in/Inport',[arb '/' inps{k}],'Position',[20 y 50 y+14]); y = y+30;
end

% Outports
outs = {'ramREN','ramWEN','ramaddr','ramstore','c1load','c1state','c2load','c2state'};
y = 60;
for k=1:numel(outs)
    add_block('built-in/Outport',[arb '/' outs{k}],'Position',[380 y 410 y+14]); y = y+30;
end

% c1req = c1REN || c1WEN
add_block('simulink/Logic and Bit Operations/Logical Operator',[arb '/c1req'], ...
          'Operator','OR','Position',[90 60 120 90]);
add_line(arb,'c1REN/1','c1req/1'); add_line(arb,'c1WEN/1','c1req/2');

% Switches choosing between Core1 and Core2 requests
makeSel = @(name,pos) add_block('simulink/Signal Routing/Switch',[arb '/' name], ...
                                'Criteria','u2 ~= 0','Threshold','0.5','Position',pos);
makeSel('selREN',   [180  60 230  90]);
makeSel('selWEN',   [180  90 230 120]);
makeSel('selADDR',  [180 120 230 150]);
makeSel('selSTORE', [180 150 230 180]);

add_line(arb,'c1req/1','selREN/2');   add_line(arb,'c1REN/1','selREN/1');   add_line(arb,'c2REN/1','selREN/3');
add_line(arb,'c1req/1','selWEN/2');   add_line(arb,'c1WEN/1','selWEN/1');   add_line(arb,'c2WEN/1','selWEN/3');
add_line(arb,'c1req/1','selADDR/2');  add_line(arb,'c1addr/1','selADDR/1'); add_line(arb,'c2addr/1','selADDR/3');
add_line(arb,'c1req/1','selSTORE/2'); add_line(arb,'c1store/1','selSTORE/1'); add_line(arb,'c2store/1','selSTORE/3');

% Outputs to MemCtrl
add_line(arb,'selREN/1','ramREN/1');   add_line(arb,'selWEN/1','ramWEN/1');
add_line(arb,'selADDR/1','ramaddr/1'); add_line(arb,'selSTORE/1','ramstore/1');

% Return path: to chosen requester
add_block('simulink/Logic and Bit Operations/Logical Operator',[arb '/not_c1req'],...
          'Operator','NOT','Position',[90 210 120 240]);
makeSel('sel_c1load',  [240 200 300 230]);  % c1load
makeSel('sel_c2load',  [240 260 300 290]);  % c2load
makeSel('sel_c1state', [310 200 370 230]);  % c1state
makeSel('sel_c2state', [310 260 370 290]);  % c2state
add_block('simulink/Sources/Constant',[arb '/zero32'],'Value','uint32(0)','Position',[140 235 170 255]);
add_block('simulink/Sources/Constant',[arb '/zero8'],'Value','uint8(0)','Position',[140 265 170 285]);

add_line(arb,'c1req/1','sel_c1load/2');   add_line(arb,'zero32/1','sel_c1load/1');  add_line(arb,'ramload/1','sel_c1load/3');  add_line(arb,'sel_c1load/1','c1load/1');
add_line(arb,'not_c1req/1','sel_c2load/2'); add_line(arb,'zero32/1','sel_c2load/1'); add_line(arb,'ramload/1','sel_c2load/3');  add_line(arb,'sel_c2load/1','c2load/1');

add_line(arb,'c1req/1','sel_c1state/2'); add_line(arb,'zero8/1','sel_c1state/1'); add_line(arb,'ramstate/1','sel_c1state/3'); add_line(arb,'sel_c1state/1','c1state/1');
add_line(arb,'not_c1req/1','sel_c2state/2'); add_line(arb,'zero8/1','sel_c2state/1'); add_line(arb,'ramstate/1','sel_c2state/3'); add_line(arb,'sel_c2state/1','c2state/1');

close_system(arb);

%% ---------- Top wiring ----------
% Requests from cores to arbiter
add_line(mdl,'Core1/1','Arbiter/1');  % c1REN   (you'll drive from inside Core1)
add_line(mdl,'Core1/2','Arbiter/2');  % c1WEN
add_line(mdl,'Core1/3','Arbiter/3');  % c1addr
add_line(mdl,'Core1/4','Arbiter/4');  % c1store

add_line(mdl,'Core2/1','Arbiter/5');  % c2REN
add_line(mdl,'Core2/2','Arbiter/6');  % c2WEN
add_line(mdl,'Core2/3','Arbiter/7');  % c2addr
add_line(mdl,'Core2/4','Arbiter/8');  % c2store

% Arbiter <-> MemCtrl
add_line(mdl,'Arbiter/1','MemCtrl/1');  % ramREN
add_line(mdl,'Arbiter/2','MemCtrl/2');  % ramWEN
add_line(mdl,'Arbiter/3','MemCtrl/3');  % ramaddr
add_line(mdl,'Arbiter/4','MemCtrl/4');  % ramstore
add_line(mdl,'MemCtrl/1','Arbiter/9');  % ramload
add_line(mdl,'MemCtrl/2','Arbiter/10'); % ramstate

% Arbiter feedback to cores
add_line(mdl,'Arbiter/5','Core1/1');    % c1load -> Core1.ramload
add_line(mdl,'Arbiter/6','Core1/2');    % c1state-> Core1.ramstate
add_line(mdl,'Arbiter/7','Core2/1');    % c2load -> Core2.ramload
add_line(mdl,'Arbiter/8','Core2/2');    % c2state-> Core2.ramstate

% Ground IRQs for now
add_block('simulink/Sources/Constant',[mdl '/gndIRQ'],'Value','0','Position',[40 20 60 40]);
add_line(mdl,'gndIRQ/1','Core1/3'); add_line(mdl,'gndIRQ/1','Core2/3');

save_system(mdl);
disp(['Created scaffold model: ' mdl '  (open with open_system(''' mdl ''').)']);
end