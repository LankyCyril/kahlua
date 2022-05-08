local shm = {--[[
    Implements Shmem(), a simplistic shared-memory handle.
 
    The focus of this module is to allow interacting with CDATA in a shmem.
    If your application uses strings / serialized data, you might use lua-luaipc
    (https://github.com/siffiejoe/lua-luaipc) instead.
 
    Some useful references:
    - https://gist.github.com/garcia556/8231e844a90457c99cc72e5add8388e4
    - https://github.com/siffiejoe/lua-luaipc/blob/master/memfile.c
]]}

local ffi = require "ffi"
local sys = require "kahlua.sys" --[[sys.lua]]
_ = (ffi.os == "Linux") or error("kahlua.shm: only Linux is supported")
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
    -- Memory-maps file in /dev/shm to a pointer; attaches a garbage collector --
    local ptr = shm.__rt.mmap(NULL, memsize, PROT_READWRITE, MAP_SHARED, fd, 0)
    ffi.C.close(fd)
    if (ptr == NULL) or (ptr == MAP_FAILED) then
        shm.__rt.shm_unlink(id)
        sys.Cerror("kahlua.shm.MMapGarbageCollectable: rt.mmap()")
    elseif unlink then
        shm.__rt.shm_unlink(id)
    end
    return ffi.gc(ptr, function (ptr)
        ffi.C.munmap(ptr, memsize)
        shm.__rt.shm_unlink(id)
    end)
end


shm.Shmem = function (memsize, id, unlink)
    -- Creates (if id==nil) or attaches to (with an existing id) shared memory block; unlinks underlying file if `unlink` --
    -- TODO: fall back onto /tmp
 
    local id, fill, copy, sizeof, typeof =
        id, ffi.fill, ffi.copy, ffi.sizeof, ffi.typeof
    if (not id) and unlink then
        error("Shmem: `unlink` cannot be used without an existing `id`")
    elseif not id then -- weird luajit behavior: new files not created with ffi
        id = sys.uuid4()
        pcall(function() io.open("/dev/shm/" .. id, "w"):close() end)
    end
    local fd = shm.__rt.shm_open(id, O_RDWR_NONBLOCK, I_URW)
    _ = ((fd or -1) >= 0)
        or sys.Cerror("kahlua.shm.Shmem: rt.shm_open()")
    _ = (ffi.C.ftruncate(fd, memsize) >= 0)
        or sys.Cerror("kahlua.shm.Shmem: ftruncate()")
    local ptr = MMapGarbageCollectable(memsize, fd, id, unlink) -- XXX
 
    return {
        id=id, memsize=memsize, ptr=ptr,
        init = function (self, _cast_type, initializer, byref_aka_inplace)
            local obj = ffi.cast(_cast_type, ptr)
            if byref_aka_inplace then
                initializer(obj)
            else
                obj = initializer()
            end
            return obj
        end;
        cast = function (self, _cast_type)
            return ffi.cast(_cast_type, ptr)
        end;
        write = function (self, src, sz)
            sz = sz and ((type(sz) == "number") and sz or sizeof(sz)) or memsize
            copy(ptr, src, sz)
        end;
        read = function (self, _type)
            local dst = typeof(_type)()
            copy(dst, ptr, sizeof(_type))
            return dst
        end;
        clear = function (self)
            fill(ptr, memsize, 0)
        end;
        destroy = function (self)
            ffi.C.munmap(ptr, memsize)
            shm.__rt.shm_unlink(id)
        end;
    }
end


return shm
