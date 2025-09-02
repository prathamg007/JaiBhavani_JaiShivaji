classdef SharedCacheSys < matlab.System
    properties
        % Cache: 64 lines
        CacheData = zeros(64,1,'uint32');
        CacheAddr = zeros(64,1,'uint32');
        Valid = false(64,1);
        Dirty = false(64,1);
    end

    methods(Access = protected)
        function [c1_out, c2_out, stall1, stall2, ram_addr, ram_data, ram_wen] = ...
                stepImpl(obj, C1_addr, C1_data, C1_wen, C2_addr, C2_data, Cw_addr)

            % Default outputs
            c1_out = uint32(0); c2_out = uint32(0);
            stall1 = false; stall2 = false;
            ram_addr = uint32(0); ram_data = uint32(0); ram_wen = false;

            % === Core1 read/write ===
            idx1 = find(obj.CacheAddr == C1_addr & obj.Valid, 1);
            if ~isempty(idx1) % hit
                if C1_wen
                    obj.CacheData(idx1) = C1_data;
                    obj.Dirty(idx1) = true;
                else
                    c1_out = obj.CacheData(idx1);
                end
            else % miss
                stall1 = true;
                ram_addr = C1_addr;
            end

            % === Core2 read/write ===
            idx2 = find(obj.CacheAddr == C2_addr & obj.Valid, 1);
            if ~isempty(idx2) % hit
                if C2_wen
                    obj.CacheData(idx2) = C2_data;
                    obj.Dirty(idx2) = true;
                else
                    c2_out = obj.CacheData(idx2);
                end
            else % miss
                stall2 = true;
                ram_addr = C2_addr; % Note: arbitration needed if C1 also misses
            end
        end
    end
end