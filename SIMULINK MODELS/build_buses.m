function build_buses()
%BUILD_BUSES Define Simulink.Bus objects for pipeline and cache interfaces.

%% IF/ID
IFID = Simulink.Bus;
addEl = @(bus,n,dt) setfield(bus,'Elements', [bus.Elements; makeEl(n,dt)]); %#ok<SFLD>
IFID = addEl(IFID,'pc_plus4','uint32');
IFID = addEl(IFID,'instr',   'uint32');
assignin('base','IFID',IFID);

%% ID/EX  (match counts exactly)
IDEX = Simulink.Bus;
names  = {'rd1','rd2','imm_ext','rs','rt','rd','alu_op','alu_src_b_imm',...
          'reg_write','mem_read','mem_write','mem_to_reg','branch_type',...
          'jump','link','shamt'};
dtypes = {'uint32','uint32','uint32','uint8','uint8','uint8','uint8','boolean',...
          'boolean','boolean','boolean','uint8','uint8','uint8','boolean','uint8'};
for i = 1:numel(names)
    IDEX = addEl(IDEX,names{i},dtypes{i});
end
assignin('base','IDEX',IDEX);

%% EX/MEM
EXMEM = Simulink.Bus;
names  = {'alu_out','rd2','reg_write','mem_read','mem_write','mem_to_reg','rd'};
dtypes = {'uint32','uint32','boolean','boolean','boolean','uint8','uint8'};
for i=1:numel(names)
    EXMEM = addEl(EXMEM,names{i},dtypes{i});
end
assignin('base','EXMEM',EXMEM);

%% MEM/WB
MEMWB = Simulink.Bus;
names  = {'mem_data','alu_out','reg_write','mem_to_reg','rd'};
dtypes = {'uint32','uint32','boolean','uint8','uint8'};
for i=1:numel(names)
    MEMWB = addEl(MEMWB,names{i},dtypes{i});
end
assignin('base','MEMWB',MEMWB);

%% Datapath–Cache (dcif)
DCIF = Simulink.Bus;
names  = {'imemaddr','imemREN','imemload','ihit',...
          'dmemaddr','dmemstore','dmemREN','dmemWEN','dmemload','dhit'};
dtypes = {'uint32','boolean','uint32','boolean',...
          'uint32','uint32','boolean','boolean','uint32','boolean'};
for i=1:numel(names)
    DCIF = addEl(DCIF,names{i},dtypes{i});
end
assignin('base','DCIF',DCIF);

%% Caches–Memory (cif)
CIF = Simulink.Bus;
names  = {'ramREN','ramWEN','ramaddr','ramstore','ramload','ramstate'};
dtypes = {'boolean','boolean','uint32','uint32','uint32','uint8'};
for i=1:numel(names)
    CIF = addEl(CIF,names{i},dtypes{i});
end
assignin('base','CIF',CIF);

disp('Defined buses: IFID, IDEX, EXMEM, MEMWB, DCIF, CIF');
end

function el = makeEl(name, dtype)
el = Simulink.BusElement;
el.Name = name;
el.DataType = dtype;
end