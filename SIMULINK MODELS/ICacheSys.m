classdef ICacheSys < matlab.System & matlab.system.mixin.CustomIcon
properties(Nontunable)
    NUM_LINES uint32 = 16;
    LINE_WORDS uint32 = 2;
end
properties(Access=private)
    tag; valid; data; state; line; beat;
end
methods(Access=protected)
    function setupImpl(obj)
        obj.tag=zeros(obj.NUM_LINES,1,'uint32');
        obj.valid=false(obj.NUM_LINES,1);
        obj.data=zeros(obj.NUM_LINES,obj.LINE_WORDS,'uint32');
        obj.state=uint8(0); obj.line=0; obj.beat=0;
    end
    function icon=getIconImpl(~), icon="ICache"; end
    function [iload, ihit, iwait]=stepImpl(obj,imemaddr,imemREN,ramload,ramstate,nRST)
        if ~nRST, setupImpl(obj); iload=0; ihit=false; iwait=false; return; end
        IDLE=0; LD1=1; LD2=2;
        iload=uint32(0); ihit=false; iwait=false;
        wordAddr=bitshift(uint32(imemaddr),-2);
        line=bitand(wordAddr,obj.NUM_LINES-1);
        tag=bitshift(wordAddr,-4);
        switch obj.state
            case IDLE
                if imemREN
                    if obj.valid(line+1)&&obj.tag(line+1)==tag
                        ihit=true; iload=obj.data(line+1,bitand(wordAddr,uint32(1))+1);
                    else
                        obj.line=line; obj.beat=0; obj.state=LD1; iwait=true;
                    end
                end
            case LD1
                if ramstate==1, obj.data(obj.line+1,1)=ramload; obj.state=LD2; end; iwait=true;
            case LD2
                if ramstate==1
                    obj.data(obj.line+1,2)=ramload; obj.tag(obj.line+1)=tag; obj.valid(obj.line+1)=true; obj.state=IDLE;
                end; iwait=true;
        end
    end
end
end
