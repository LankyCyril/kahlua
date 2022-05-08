local gzip = {--[[
    A very thin wrapper around zlib.h; basically does two things:
    - binds the necessary functions so you don't have to;
    - ensures that open handles are closed during garbage collection.
]]}

local ffi = require "ffi"
local sys = require "kahlua.sys" --[[sys.lua]]
gzip.__zlib = ffi.load "z"; --[[zlib.h]]

ffi.cdef --[[https://www.zlib.net/manual.html#Gzip]] [[
    typedef struct gzFile_s *gzFile;
    gzFile gzopen(const char *path, const char* mode);
    int gzclose(gzFile file);
]]

local IMPORTED_FUNCTION_SPECS = { --[[https://www.zlib.net/manual.html#Gzip]]
    {"char *",       "gzgets",     "(gzFile file, char *buf, int len)"},
    {"int",          "gzputs",     "(gzFile file, const char *s)"},
    {"int",          "gzgetc",     "(gzFile file)"},
    {"int",          "gzungetc",   "(int c, gzFile file)"},
    {"int",          "gzputc",     "(gzFile file, int c)"},
    {"int",          "gzflush",    "(gzFile file, int flush)"},
    {"long",         "gzseek",     "(gzFile file, long offset, int whence)"},
    {"int",          "gzrewind",   "(gzFile file)"},
    {"long",         "gztell",     "(gzFile file)"},
    {"long",         "gzoffset",   "(gzFile file)"},
    {"int",          "gzeof",      "(gzFile file)"},
    {"const char *", "gzerror",    "(gzFile file, int *errnum)"},
    {"void",         "gzclearerr", "(gzFile file)"},
}


for _, spec in ipairs(IMPORTED_FUNCTION_SPECS) do
    ffi.cdef(table.concat(spec, " ") .. ";")
    gzip[spec[2]] = gzip.__zlib[spec[2]]
end


gzip.safe_gzopen = function (filename, mode, logger)
    -- Garbage-collectable gzFile_s* --
    local FILE = gzip.__zlib.gzopen(filename, mode)
    if FILE == nil then
        sys.Cerror("gzip.gzopen")
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


return gzip
