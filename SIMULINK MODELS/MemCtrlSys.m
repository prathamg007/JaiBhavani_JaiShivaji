classdef MemCtrlSys < matlab.System & matlab.system.mixin.CustomIcon
properties(Nontunable)
    DEPTH uint32 = 4096;
end
properties(Access=private)
    ram;
end
methods(Access=protected)
    function setupImpl(obj)
        obj.ram=zeros(obj.DEPTH,1,'uint32');
        try
            if evalin('base','exist(''INIT_RAM'',''var'')')
                im=evalin('base','INIT_RAM'); im=uint32(im(:));
                n=min(numel(im),numel(obj.ram)); obj.ram(1:n)=im(1:n);
            end
        catch, end
    end
    function icon=getIconImpl(~), icon="MemCtrl"; end
    function [ramload,ramstate]=stepImpl(obj,ramREN,ramWEN,ramaddr,ramstore)
        if ramWEN, idx=bitshift(uint32(ramaddr),-2)+1; obj.ram(idx)=ramstore; ramload=0; ramstate=1;
        elseif ramREN, idx=bitshift(uint32(ramaddr),-2)+1; ramload=obj.ram(idx); ramstate=1;
        else, ramload=0; ramstate=0; end
    end
end
end
