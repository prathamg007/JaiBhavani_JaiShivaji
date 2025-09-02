classdef RegFileSys < matlab.System & matlab.system.mixin.CustomIcon
% 32x32 Register file, 2R1W, x0 hardwired zero
properties (Access=private)
    R
end
methods (Access=protected)
    function setupImpl(obj), obj.R=zeros(32,1,'uint32'); end
    function icon=getIconImpl(~), icon="RegFile"; end
    function [rd1, rd2] = stepImpl(obj, rs, rt, rd, wdata, wen)
        rs=double(rs)+1; rt=double(rt)+1; rd=double(rd)+1;
        if wen && rd~=1, obj.R(rd)=uint32(wdata); end
        rd1 = (rs==1) * uint32(0) + (rs~=1) * obj.R(rs);
        rd2 = (rt==1) * uint32(0) + (rt~=1) * obj.R(rt);
    end
end
end
