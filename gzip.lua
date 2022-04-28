-- XXX NOTE: work in progress; must implement faster direct ffi access XXX --

local gzip = {}

local sys = require "kahlua.sys" -- sys.lua
local ffi = sys.loadglobal "ffi"

local zlib = sys.loadffi ( -- https://www.zlib.net/manual.html#Gzip
    "zlib", "z", "gzopen", [[
        typedef struct gzFile_s* gzFile;
        gzFile gzopen(const char* path, const char* mode);
        int gzclose_r(gzFile file);
        int gzoffset(gzFile file);
        char* gzgets(gzFile file, char* buf, int len);
        int gzeof(gzFile file);
    ]]
)

local gzopen, gzclose_r = zlib.gzopen, zlib.gzclose_r
local gzgets, gzeof, gzoffset = zlib.gzgets, zlib.gzeof, zlib.gzoffset


local _gzFile_open_rb = function (filename)
    -- Open file for reading with zlib and stage for garbage collection --
    return ffi.gc(gzopen(filename, "rb"), function (FILE)
        if gzoffset(FILE) ~= -1 then -- has not been closed manually
            gzclose_r(FILE)
        end
    end)
end


local _gzFile_read = function (gzf, kind)
    -- Read data from files in tables returned by `gzip.open` --
    if kind and (kind:sub(1, 2) ~= "*l") then
        error("kahlua.gzip ->...-> read: currently only kind '*line' supported")
    end
    local buffer = ffi.new("char[?]", gzf.bufsize)
    local line
    while gzgets(gzf.FILE, buffer, gzf.bufsize) and (gzeof(gzf.FILE) ~= 1) do
        local chunk, newline_count = ffi.string(buffer):gsub("\n+$", "")
        line = (line or "") .. chunk:gsub("\r+$", "")
        if newline_count ~= 0 then
            return line
        end
    end
end


local _gzFile_close = function (gzf)
    -- Close files in tables returned by `gzip.open` --
    if gzf.is_open == true then
        gzclose_r(gzf.FILE)
        gzf.is_open = false
    else
        error("kahlua.gzip: attempt to use a closed file")
    end
end


local _gzFile_EOF = function (gzf)
    -- Check for EOF --
    return gzeof(gzf.FILE) ~= 0
end


gzip.open = function (filename, mode, bufsize)
    -- Mimic behavior of rt mode of io.open, but with zlib support --
    mode = mode or "rt"
    bufsize = bufsize or 4096
    if (mode ~= "rt") and (mode ~= "tr") and (mode ~= "r") then
        error("kahlua.gzip.open: currently only mode 'rt|tr|r' supported")
    end
    -- check existence of file:
    local handle, err = io.open(filename)
    if handle then
        handle:close()
        return {
            FILE = _gzFile_open_rb(filename),
            bufsize = bufsize,
            is_open = true,
            read = _gzFile_read, -- mimic :read()
            close = _gzFile_close, -- mimic :close()
            eof = _gzFile_EOF,
        }
    else
        return nil, "kahlua.gzip.open: file does not exist"
    end
end


return gzip
