local gzip = {--[[
    A very thin wrapper around zlib.h; basically does two things:
    - binds the necessary functions so you don't have to (TODO more functions);
    - ensures that open handles are closed during garbage collection.
]]}

local ffi = require "ffi"
local zlib = ffi.load "z"; --[[zlib.h]]

ffi.cdef --[[https://www.zlib.net/manual.html#Gzip]] [[
    typedef struct gzFile_s* gzFile;
    gzFile gzopen(const char* path, const char* mode);
    char* gzgets(gzFile file, char* buf, int len);
    int gzputs(gzFile file, const char* s);
    int gzputc(gzFile file, int c);
    int gzclose(gzFile file);
]]


gzip.gzopen = function (filename, mode, logger)
    -- Garbage-collectable gzFile_s* --
    local FILE = zlib.gzopen(filename, mode)
    _ = logger and logger("gzip: opened " .. tostring(FILE))
    return ffi.gc(FILE, function (FILE)
        zlib.gzclose(FILE)
        _ = logger and logger("gzip: closed " .. tostring(FILE))
    end)
end


gzip.safe_gzopen = gzip.gzopen
gzip.gzgets = zlib.gzgets
gzip.gzputs = zlib.gzputs
gzip.gzputc = zlib.gzputc


return gzip
