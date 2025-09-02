classdef DCacheSys < matlab.System & matlab.system.mixin.CustomIcon
properties(Nontunable)
    NUM_SETS uint32=8; NUM_WAYS uint32=2; LINE_WORDS uint32=2;
end
properties(Access=private)
    tag; valid; dirty; data; lru; state; nWay; beat;
end
methods(Access=protected)
    function setupImpl(obj)
        obj.tag=zeros(obj.NUM_SETS,obj.NUM_WAYS,'uint32');
        obj.valid=false(obj.NUM_SETS,obj.NUM_WAYS);
        obj.dirty=false(obj.NUM_SETS,obj.NUM_WAYS);
        obj.data=zeros(obj.NUM_SETS,obj.NUM_WAYS,obj.LINE_WORDS,'uint32');
        obj.lru=false(obj.NUM_SETS,1); obj.state=0; obj.nWay=0; obj.beat=0;
    end
    function icon=getIconImpl(~), icon="DCache"; end
    function [dmemload,dhit,dwait,ccwrite,cctrans]=stepImpl(obj,dmemaddr,dmemstore,dmemREN,dmemWEN,ramload,ramstate,ccsnoopaddr,ccinv,nRST)
        if ~nRST, setupImpl(obj); dmemload=0; dhit=false; dwait=false; ccwrite=false; cctrans=false; return; end
        IDLE=0; LD1=1; LD2=2; WB1=3; WB2=4;
        dmemload=0; dhit=false; dwait=false; ccwrite=false; cctrans=false;
        wordAddr=bitshift(uint32(dmemaddr),-2); bo=bitand(wordAddr,1); idx=bitand(bitshift(wordAddr,-1),obj.NUM_SETS-1); tag=bitshift(wordAddr,-(1+3));
        switch obj.state
            case IDLE
                if dmemREN||dmemWEN
                    hitWay=0;
                    for w=1:obj.NUM_WAYS, if obj.valid(idx+1,w)&&obj.tag(idx+1,w)==tag, hitWay=w; break; end; end
                    if hitWay~=0
                        dhit=true;
                        if dmemREN, dmemload=obj.data(idx+1,hitWay,bo+1);
                        else, obj.data(idx+1,hitWay,bo+1)=dmemstore; obj.dirty(idx+1,hitWay)=true; end
                        obj.lru(idx+1)=(hitWay==1);
                    else
                        victim=1+double(obj.lru(idx+1)); obj.nWay=victim-1;
                        if obj.valid(idx+1,victim)&&obj.dirty(idx+1,victim), obj.state=WB1; dwait=true;
                        else, obj.state=LD1; dwait=true; end
                    end
                end
            case WB1, if ramstate==1, obj.state=WB2; end; dwait=true; ccwrite=true; cctrans=true;
            case WB2, if ramstate==1, obj.dirty(idx+1,1+obj.nWay)=false; obj.valid(idx+1,1+obj.nWay)=false; obj.state=LD1; end; dwait=true; ccwrite=true; cctrans=true;
            case LD1, if ramstate==1, obj.data(idx+1,1+obj.nWay,1)=ramload; obj.state=LD2; end; dwait=true; cctrans=true;
            case LD2, if ramstate==1, obj.data(idx+1,1+obj.nWay,2)=ramload; obj.tag(idx+1,1+obj.nWay)=tag; obj.valid(idx+1,1+obj.nWay)=true; obj.dirty(idx+1,1+obj.nWay)=false; obj.state=IDLE; end; dwait=true;
        end
    end
end
end
