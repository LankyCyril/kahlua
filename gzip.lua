local gzip = {--[[
    A very thin wrapper around zlib.h; basically does two things:
    - binds the necessary functions so you don't have to (TODO more functions);
    - ensures that open handles are closed during garbage collection.
]]}

local ffi = require "ffi"
local sys = require "kahlua.sys" --[[sys.lua]]
gzip.__zlib = ffi.load "z"; --[[zlib.h]]

ffi.cdef --[[https://www.zlib.net/manual.html#Gzip]] [[
    typedef struct gzFile_s *gzFile;
    gzFile gzopen(const char *path, const char* mode);
    char *gzgets(gzFile file, char *buf, int len);
    int gzputs(gzFile file, const char *s);
    int gzputc(gzFile file, int c);
    int gzclose(gzFile file);
]]


gzip.safe_gzopen = function (filename, mode, logger)
    -- Garbage-collectable gzFile_s* --
    local FILE = gzip.__zlib.gzopen(filename, mode)
    if FILE == nil then
        error("gzip.gzopen: " .. ffi.string(sys.C.strerror(ffi.errno())))
    else
        _ = logger and logger(
            ("gzip.gzopen: %s as %s (%s)"):format(filename, FILE, mode)
        )
        return ffi.gc(FILE, function (FILE)
            gzip.__zlib.gzclose(FILE)
            _ = logger and logger(
                ("gzip.gzclose: %s, was %s (%s)"):format(filename, FILE, mode)
            )
        end)
    end
end


gzip.gzopen = gzip.safe_gzopen
gzip.gzgets = gzip.__zlib.gzgets
gzip.gzputs = gzip.__zlib.gzputs
gzip.gzputc = gzip.__zlib.gzputc


return gzip
