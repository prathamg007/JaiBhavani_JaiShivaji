classdef RAMSys < matlab.System
    properties
        Mem = zeros(1024,1,'uint32');
    end
    
    methods(Access=protected)
        function data_out = stepImpl(obj, addr, data_in, wen)
            if wen
                obj.Mem(addr+1) = data_in;
            end
            data_out = obj.Mem(addr+1);
        end
    end
end