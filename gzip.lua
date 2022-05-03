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
    if FILE == nil then
        pcall(function () ffi.cdef "char* strerror(int errnum);" end)
        local strerror_ok, err = pcall(function ()
            return ffi.string(ffi.C.strerror(ffi.errno()))
        end)
        error("gzip.gzopen: " .. (strerror_ok and err or "unspecified error"))
    else
        _ = logger and logger(
            ("gzip.gzopen: %s as %s (%s)"):format(filename, FILE, mode)
        )
        return ffi.gc(FILE, function (FILE)
            zlib.gzclose(FILE)
            _ = logger and logger(
                ("gzip.gzclose: %s, was %s (%s)"):format(filename, FILE, mode)
            )
        end)
    end
end


gzip.safe_gzopen = gzip.gzopen
gzip.gzgets = zlib.gzgets
gzip.gzputs = zlib.gzputs
gzip.gzputc = zlib.gzputc


return gzip
