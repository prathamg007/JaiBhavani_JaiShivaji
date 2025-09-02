function INIT_RAM = bin_to_INIT_RAM(binPath, baseAddr)
%BIN_TO_INIT_RAM Load a raw binary into a uint32 INIT_RAM vector
%
%   INIT_RAM = bin_to_INIT_RAM('app.bin', 0)
%
% Arguments:
%   binPath  - path to a raw binary file (e.g. produced by objcopy)
%   baseAddr - starting address offset (in bytes, usually 0)
%
% Result:
%   INIT_RAM - uint32 vector suitable for preloading into MemCtrlSys

    if nargin < 2
        baseAddr = 0;
    end

    % Read file as bytes
    fid = fopen(binPath,'rb');
    if fid == -1
        error('Could not open binary file: %s', binPath);
    end
    by = fread(fid, inf, '*uint8');
    fclose(fid);

    % Pad to multiple of 4 bytes
    pad = mod(numel(by),4);
    if pad
        by(end+1:end+4-pad) = 0;
    end

    % Group into words (little-endian)
    by = reshape(by,4,[])';
    w = uint32(by(:,1)) + bitshift(uint32(by(:,2)),8) + ...
        bitshift(uint32(by(:,3)),16) + bitshift(uint32(by(:,4)),24);

    % Apply base address offset (in words)
    offsetWords = floor(double(baseAddr)/4);
    INIT_RAM = [zeros(offsetWords,1,'uint32'); w];

    % Export to base workspace for MemCtrlSys to pick up
    assignin('base','INIT_RAM',INIT_RAM);

    fprintf('Loaded %d words from %s into INIT_RAM (base 0x%08X)\n', ...
        numel(w), binPath, baseAddr);
end
