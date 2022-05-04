local shm = {}

local ffi = require "ffi"
local sys = require "kahlua.sys" --[[sys.lua]]
shm.__rt = ffi.load "rt" --[[/usr/include/x86_64-linux-gnu/sys/mman.h]]

ffi.cdef --[[/usr/include/x86_64-linux-gnu/sys/mman.h]] [[
    void* mmap (void* a, size_t s, int prot, int flags, int fd, long int ofs);
    int munmap (void* a, size_t s);
    extern int shm_unlink (const char *__name);
    extern int shm_open (const char* __name, int __oflag, unsigned int __mode);
]]
ffi.cdef --[[unistd.h]] [[
    int ftruncate (int fd, unsigned long length);
    int close (int fd);
]]

local O_RDWR_NONBLOCK = 6 -- O_RDWR|O_NONBLOCK
local I_URW = 384 -- 0600 i.e. u+rw
local PROT_READWRITE = 3 -- PROT_READ|PROT_WRITE
local MAP_SHARED = 1
local MAP_FAILED = ffi.cast("void*", -1) --[[/usr/include/x86_64-linux-gnu/sys/mman.h]]


local MMapGarbageCollectable = function (memsize, fd, id, unlink)
    local ptr = shm.__rt.mmap(NULL, memsize, PROT_READWRITE, MAP_SHARED, fd, 0)
    ffi.C.close(fd)
    if (ptr == NULL) or (ptr == MAP_FAILED) then
        shm.__rt.shm_unlink(id)
        error("mmap")
    elseif unlink then
        shm.__rt.shm_unlink(id)
    end
    return ffi.gc(ptr, function (ptr)
        ffi.C.munmap(ptr, memsize)
        shm.__rt.shm_unlink(id)
    end)
end


shm.Shmem = function (memsize, id, unlink)
    -- TODO: fall back onto /tmp --
    local id, fill, copy, sizeof, typeof =
        id, ffi.fill, ffi.copy, ffi.sizeof, ffi.typeof
    if (not id) and unlink then
        error("Shmem: `unlink` cannot be used without an existing `id`")
    elseif not id then -- weird luajit behavior: new files not created with ffi
        id = sys.uuid4()
        pcall(function() io.open("/dev/shm/" .. id, "w"):close() end)
    end
    local fd = shm.__rt.shm_open(id, O_RDWR_NONBLOCK, I_URW)
    _ = ((fd or -1) >= 0) or error("shm_open")
    _ = (ffi.C.ftruncate(fd, memsize) >= 0) or error("ftruncate")
    local ptr = MMapGarbageCollectable(memsize, fd, id, unlink) -- XXX
    return {
        id=id, memsize=memsize, ptr=ptr,
        clear = function (self) fill(ptr, memsize, 0) end;
        write = function (self, src, sz)
            sz = sz and ((type(sz) == "number") and sz or sizeof(sz)) or memsize
            copy(ptr, src, sz)
        end;
        read = function (self, _type)
            local dst = typeof(_type)()
            copy(dst, ptr, sizeof(_type))
            return dst
        end;
        cast = function (self, _cast_type)
            return ffi.cast(_cast_type, ptr)
        end;
        destroy = function (self)
            ffi.C.munmap(ptr, memsize)
            shm.__rt.shm_unlink(id)
        end;
    }
end


return shm
