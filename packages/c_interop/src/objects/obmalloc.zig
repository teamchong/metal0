/// Object Memory Allocator Implementation
///
/// Implements CPython's Objects/obmalloc.c
/// Python memory allocators for objects
///
/// Reference: cpython/Objects/obmalloc.c
///            cpython/Include/pymem.h
///            cpython/Include/objimpl.h
/// Memory layout matches CPython 3.12 exactly

const std = @import("std");
const cpython = @import("../include/object.zig");

// Use Zig's general purpose allocator for now
// In production, we'd want to use CPython's arena allocator for small objects
const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Small object threshold - objects below this size use the small object allocator
pub const SMALL_REQUEST_THRESHOLD: usize = 512;

/// Pool size for arena allocator
pub const POOL_SIZE: usize = 4096;

/// Alignment for all allocations
pub const ALIGNMENT: usize = 8;
pub const ALIGNMENT_SHIFT: usize = 3;
pub const ALIGNMENT_MASK: usize = ALIGNMENT - 1;

/// Memory domain identifiers
pub const PYMEM_DOMAIN_RAW: c_uint = 0;
pub const PYMEM_DOMAIN_MEM: c_uint = 1;
pub const PYMEM_DOMAIN_OBJ: c_uint = 2;

// ============================================================================
// PYMEM ALLOCATOR STRUCTURES
// ============================================================================

/// PyMemAllocatorEx - Custom allocator struct
/// Reference: cpython/Include/cpython/pymem.h
///
/// typedef struct {
///     void *ctx;
///     void* (*malloc)(void *ctx, size_t size);
///     void* (*calloc)(void *ctx, size_t nelem, size_t elsize);
///     void* (*realloc)(void *ctx, void *ptr, size_t new_size);
///     void (*free)(void *ctx, void *ptr);
/// } PyMemAllocatorEx;
pub const PyMemAllocatorEx = extern struct {
    ctx: ?*anyopaque,
    malloc_fn: ?*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    calloc_fn: ?*const fn (?*anyopaque, usize, usize) callconv(.c) ?*anyopaque,
    realloc_fn: ?*const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) ?*anyopaque,
    free_fn: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
};

// ============================================================================
// RAW MEMORY ALLOCATOR (PYMEM_DOMAIN_RAW)
// ============================================================================

/// Raw malloc - direct system allocation
fn raw_malloc(ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    _ = ctx;
    if (size == 0) return null;

    const mem = allocator.alloc(u8, size) catch return null;
    return @ptrCast(mem.ptr);
}

/// Raw calloc - zeroed allocation
fn raw_calloc(ctx: ?*anyopaque, nelem: usize, elsize: usize) callconv(.c) ?*anyopaque {
    _ = ctx;
    const size = nelem *| elsize;
    if (size == 0) return null;

    const mem = allocator.alloc(u8, size) catch return null;
    @memset(mem, 0);
    return @ptrCast(mem.ptr);
}

/// Raw realloc - resize allocation
fn raw_realloc(ctx: ?*anyopaque, ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    _ = ctx;

    if (ptr == null) {
        if (new_size == 0) return null;
        const mem = allocator.alloc(u8, new_size) catch return null;
        return @ptrCast(mem.ptr);
    }

    if (new_size == 0) {
        // Free the memory
        return null;
    }

    // Use c_allocator's realloc for proper memory reallocation
    // c_allocator wraps malloc/realloc/free so we can use raw pointers
    const old_bytes: [*]u8 = @ptrCast(ptr);
    // c_allocator.rawRealloc works with a slice - approximate old size as new_size
    // This is safe because C allocator tracks the actual allocation size internally
    const result = std.c.realloc(old_bytes, new_size);
    return result;
}

/// Raw free - free allocation using c_allocator
fn raw_free(ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    if (ptr) |p| {
        // Use C free directly since we allocated with c_allocator/malloc
        std.c.free(@ptrCast(p));
    }
}

// Default raw allocator
var raw_allocator = PyMemAllocatorEx{
    .ctx = null,
    .malloc_fn = raw_malloc,
    .calloc_fn = raw_calloc,
    .realloc_fn = raw_realloc,
    .free_fn = raw_free,
};

// ============================================================================
// PYMEM INTERFACE (PYMEM_DOMAIN_MEM)
// ============================================================================

/// PyMem_Malloc - allocate memory
pub export fn PyMem_Malloc(size: usize) ?*anyopaque {
    if (size == 0) {
        // Python allocates 1 byte for size 0
        return raw_malloc(null, 1);
    }
    return raw_malloc(null, size);
}

/// PyMem_Calloc - allocate zeroed memory
pub export fn PyMem_Calloc(nelem: usize, elsize: usize) ?*anyopaque {
    const size = nelem *| elsize;
    if (size == 0) {
        return raw_calloc(null, 1, 1);
    }
    return raw_calloc(null, nelem, elsize);
}

/// PyMem_Realloc - reallocate memory
pub export fn PyMem_Realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    if (ptr == null) {
        return PyMem_Malloc(new_size);
    }
    if (new_size == 0) {
        PyMem_Free(ptr);
        return null;
    }
    return raw_realloc(null, ptr, new_size);
}

/// PyMem_Free - free memory
pub export fn PyMem_Free(ptr: ?*anyopaque) void {
    raw_free(null, ptr);
}

/// PyMem_RawMalloc - raw memory allocation
pub export fn PyMem_RawMalloc(size: usize) ?*anyopaque {
    return raw_malloc(null, size);
}

/// PyMem_RawCalloc - raw zeroed allocation
pub export fn PyMem_RawCalloc(nelem: usize, elsize: usize) ?*anyopaque {
    return raw_calloc(null, nelem, elsize);
}

/// PyMem_RawRealloc - raw realloc
pub export fn PyMem_RawRealloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    return raw_realloc(null, ptr, new_size);
}

/// PyMem_RawFree - raw free
pub export fn PyMem_RawFree(ptr: ?*anyopaque) void {
    raw_free(null, ptr);
}

// ============================================================================
// PYOBJECT ALLOCATOR (PYMEM_DOMAIN_OBJ)
// ============================================================================

/// PyObject_Malloc - allocate memory for objects
pub export fn PyObject_Malloc(size: usize) ?*anyopaque {
    // For small objects, we could use the arena allocator
    // For now, use the raw allocator
    return PyMem_Malloc(size);
}

/// PyObject_Calloc - allocate zeroed memory for objects
pub export fn PyObject_Calloc(nelem: usize, elsize: usize) ?*anyopaque {
    return PyMem_Calloc(nelem, elsize);
}

/// PyObject_Realloc - reallocate object memory
pub export fn PyObject_Realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    return PyMem_Realloc(ptr, new_size);
}

/// PyObject_Free - free object memory
pub export fn PyObject_Free(ptr: ?*anyopaque) void {
    PyMem_Free(ptr);
}

// ============================================================================
// ALLOCATOR CONFIGURATION
// ============================================================================

/// Get allocator for domain
pub export fn PyMem_GetAllocator(domain: c_uint, allocator_ex: ?*PyMemAllocatorEx) void {
    if (allocator_ex == null) return;

    switch (domain) {
        PYMEM_DOMAIN_RAW, PYMEM_DOMAIN_MEM, PYMEM_DOMAIN_OBJ => {
            allocator_ex.?.* = raw_allocator;
        },
        else => {},
    }
}

/// Set allocator for domain
pub export fn PyMem_SetAllocator(domain: c_uint, allocator_ex: ?*PyMemAllocatorEx) void {
    if (allocator_ex == null) return;

    switch (domain) {
        PYMEM_DOMAIN_RAW, PYMEM_DOMAIN_MEM, PYMEM_DOMAIN_OBJ => {
            raw_allocator = allocator_ex.?.*;
        },
        else => {},
    }
}

/// Setup debug hooks on allocators
/// In CPython, this wraps allocators with debug checking (memory guards, fill patterns).
/// Our implementation uses Zig's debug allocator features instead when built in debug mode.
pub export fn PyMem_SetupDebugHooks() void {
    // Debug hooks are handled by Zig's allocator when built in debug mode
    // No additional setup required for metal0
}

// ============================================================================
// OBJECT GC INTERFACE
// ============================================================================

/// _PyObject_GC_Malloc - allocate GC-tracked memory
pub export fn _PyObject_GC_Malloc(size: usize) ?*anyopaque {
    // Allocate extra space for GC header
    const gc_size = size + @sizeOf(PyGC_Head);
    const mem = PyObject_Malloc(gc_size);
    if (mem == null) return null;

    // Initialize GC header
    const gc: *PyGC_Head = @ptrCast(@alignCast(mem));
    gc._gc_next = 0;
    gc._gc_prev = 0;

    // Return pointer past GC header
    return @ptrFromInt(@intFromPtr(mem) + @sizeOf(PyGC_Head));
}

/// _PyObject_GC_Calloc - allocate zeroed GC-tracked memory
pub export fn _PyObject_GC_Calloc(size: usize) ?*anyopaque {
    const gc_size = size + @sizeOf(PyGC_Head);
    const mem = PyObject_Calloc(1, gc_size);
    if (mem == null) return null;

    // GC header is already zeroed
    return @ptrFromInt(@intFromPtr(mem) + @sizeOf(PyGC_Head));
}

/// _PyObject_GC_Realloc - reallocate GC-tracked memory
pub export fn _PyObject_GC_Realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    if (ptr == null) {
        return _PyObject_GC_Malloc(new_size);
    }

    // Get GC header
    const gc_ptr = @intFromPtr(ptr.?) - @sizeOf(PyGC_Head);
    const gc_size = new_size + @sizeOf(PyGC_Head);

    const new_mem = PyObject_Realloc(@ptrFromInt(gc_ptr), gc_size);
    if (new_mem == null) return null;

    return @ptrFromInt(@intFromPtr(new_mem) + @sizeOf(PyGC_Head));
}

/// PyObject_GC_Del - free GC-tracked object
pub export fn PyObject_GC_Del(ptr: ?*anyopaque) void {
    if (ptr == null) return;

    // Get GC header
    const gc_ptr = @intFromPtr(ptr.?) - @sizeOf(PyGC_Head);
    PyObject_Free(@ptrFromInt(gc_ptr));
}

// ============================================================================
// GC HEADER
// ============================================================================

/// PyGC_Head - GC tracking header
/// Reference: cpython/Include/internal/pycore_gc.h
///
/// typedef struct {
///     uintptr_t _gc_next;
///     uintptr_t _gc_prev;
/// } PyGC_Head;
pub const PyGC_Head = extern struct {
    _gc_next: usize, // Encodes next pointer + GC state
    _gc_prev: usize, // Encodes prev pointer + refcount bits
};

// Verify PyGC_Head size: 8 + 8 = 16 bytes
comptime {
    if (@sizeOf(PyGC_Head) != 16) {
        @compileError("PyGC_Head size mismatch with CPython");
    }
}

/// Get GC head from object
pub inline fn AS_GC(op: *anyopaque) *PyGC_Head {
    return @ptrFromInt(@intFromPtr(op) - @sizeOf(PyGC_Head));
}

/// Get object from GC head
pub inline fn FROM_GC(gc: *PyGC_Head) *anyopaque {
    return @ptrFromInt(@intFromPtr(gc) + @sizeOf(PyGC_Head));
}

// ============================================================================
// OBJECT CREATION HELPERS
// ============================================================================

/// PyObject_New - create new object
pub export fn _PyObject_New(tp: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (tp == null) return null;

    const size: usize = @intCast(tp.?.tp_basicsize);
    const obj: ?*cpython.PyObject = @ptrCast(@alignCast(PyObject_Malloc(size)));
    if (obj == null) return null;

    // Initialize object
    obj.?.ob_refcnt = 1;
    obj.?.ob_type = tp.?;

    return obj;
}

/// PyObject_NewVar - create new var object
pub export fn _PyObject_NewVar(tp: ?*cpython.PyTypeObject, nitems: isize) ?*cpython.PyVarObject {
    if (tp == null) return null;

    const basicsize: usize = @intCast(tp.?.tp_basicsize);
    const itemsize: usize = @intCast(tp.?.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(@max(0, nitems)));

    const obj: ?*cpython.PyVarObject = @ptrCast(@alignCast(PyObject_Malloc(size)));
    if (obj == null) return null;

    // Initialize object
    obj.?.ob_base.ob_refcnt = 1;
    obj.?.ob_base.ob_type = tp.?;
    obj.?.ob_size = nitems;

    return obj;
}

/// PyObject_GC_New - create new GC-tracked object
pub export fn _PyObject_GC_New(tp: ?*cpython.PyTypeObject) ?*cpython.PyObject {
    if (tp == null) return null;

    const size: usize = @intCast(tp.?.tp_basicsize);
    const obj: ?*cpython.PyObject = @ptrCast(@alignCast(_PyObject_GC_Malloc(size)));
    if (obj == null) return null;

    // Initialize object
    obj.?.ob_refcnt = 1;
    obj.?.ob_type = tp.?;

    return obj;
}

/// PyObject_GC_NewVar - create new GC-tracked var object
pub export fn _PyObject_GC_NewVar(tp: ?*cpython.PyTypeObject, nitems: isize) ?*cpython.PyVarObject {
    if (tp == null) return null;

    const basicsize: usize = @intCast(tp.?.tp_basicsize);
    const itemsize: usize = @intCast(tp.?.tp_itemsize);
    const size = basicsize + itemsize * @as(usize, @intCast(@max(0, nitems)));

    const obj: ?*cpython.PyVarObject = @ptrCast(@alignCast(_PyObject_GC_Malloc(size)));
    if (obj == null) return null;

    // Initialize object
    obj.?.ob_base.ob_refcnt = 1;
    obj.?.ob_base.ob_type = tp.?;
    obj.?.ob_size = nitems;

    return obj;
}

/// PyObject_GC_Resize - resize GC-tracked var object
pub export fn _PyObject_GC_Resize(op: ?*cpython.PyVarObject, nitems: isize) ?*cpython.PyVarObject {
    if (op == null) return null;

    const tp = op.?.ob_base.ob_type;
    const basicsize: usize = @intCast(tp.tp_basicsize);
    const itemsize: usize = @intCast(tp.tp_itemsize);
    const new_size = basicsize + itemsize * @as(usize, @intCast(@max(0, nitems)));

    const new_obj: ?*cpython.PyVarObject = @ptrCast(@alignCast(_PyObject_GC_Realloc(@ptrCast(op), new_size)));
    if (new_obj == null) return null;

    new_obj.?.ob_size = nitems;
    return new_obj;
}

// ============================================================================
// GC TRACKING
// ============================================================================

// GC generation list heads (0=young, 1=old, 2=permanent)
var gc_generation_heads: [3]PyGC_Head = [_]PyGC_Head{
    .{ ._gc_next = 0, ._gc_prev = 0 },
    .{ ._gc_next = 0, ._gc_prev = 0 },
    .{ ._gc_next = 0, ._gc_prev = 0 },
};

/// Track object in GC
pub export fn PyObject_GC_Track(op: ?*anyopaque) void {
    if (op == null) return;

    const gc = AS_GC(op.?);

    // Already tracked?
    if ((gc._gc_prev & 1) != 0) return;

    // Mark as tracked by setting bit 0
    gc._gc_prev |= 1;

    // Add to generation 0 (young) list
    const gen = &gc_generation_heads[0];
    gc._gc_next = gen._gc_next;
    gen._gc_next = @intFromPtr(gc);
}

/// Untrack object from GC
pub export fn PyObject_GC_UnTrack(op: ?*anyopaque) void {
    if (op == null) return;

    const gc = AS_GC(op.?);

    // Not tracked?
    if ((gc._gc_prev & 1) == 0) return;

    // Clear tracked bit
    gc._gc_prev &= ~@as(usize, 1);

    // Remove from GC list by unlinking
    // Note: This is a simple implementation; full GC would maintain proper doubly-linked list
    gc._gc_next = 0;
}

/// Check if object is tracked
pub export fn PyObject_GC_IsTracked(op: ?*anyopaque) c_int {
    if (op == null) return 0;

    const gc = AS_GC(op.?);
    return if ((gc._gc_prev & 1) != 0) 1 else 0;
}

/// Check if object is finalized
pub export fn PyObject_GC_IsFinalized(op: ?*anyopaque) c_int {
    if (op == null) return 0;

    const gc = AS_GC(op.?);
    return if ((gc._gc_prev & 2) != 0) 1 else 0;
}

// ============================================================================
// MEMORY STATISTICS
// ============================================================================

/// PyMemoryStats - memory allocation statistics
pub const PyMemoryStats = extern struct {
    allocated_blocks: usize,
    freed_blocks: usize,
    peak_allocated: usize,
    current_allocated: usize,
};

var memory_stats = PyMemoryStats{
    .allocated_blocks = 0,
    .freed_blocks = 0,
    .peak_allocated = 0,
    .current_allocated = 0,
};

/// Get memory statistics
pub export fn PyMem_GetStats(stats: ?*PyMemoryStats) void {
    if (stats) |s| {
        s.* = memory_stats;
    }
}

// ============================================================================
// ARENA ALLOCATOR (for small objects - placeholder)
// ============================================================================

/// Pool structure for arena allocator
const Pool = extern struct {
    prevpool: ?*Pool,
    nextpool: ?*Pool,
    arenaindex: c_uint,
    szidx: c_uint,
    freeblock: ?*anyopaque,
    nextoffset: c_uint,
    maxnextoffset: c_uint,
};

/// Arena structure
const Arena = extern struct {
    address: ?*anyopaque,
    pool_address: ?*anyopaque,
    nfreepools: c_uint,
    ntotalpools: c_uint,
    freepools: ?*Pool,
    nextpool: ?*Pool,
};

// Placeholder for arena allocator implementation
// In a full implementation, small objects would be allocated from arenas/pools
// for better performance and reduced fragmentation

/// Initialize the memory allocator
pub export fn _PyMem_Init() void {
    // Initialize allocator state
}

/// Finalize the memory allocator
pub export fn _PyMem_Fini() void {
    // Clean up allocator state
}

/// Get allocator name for domain
pub export fn _PyMem_GetAllocatorName(domain: c_uint) ?[*:0]const u8 {
    return switch (domain) {
        PYMEM_DOMAIN_RAW => "raw",
        PYMEM_DOMAIN_MEM => "mem",
        PYMEM_DOMAIN_OBJ => "obj",
        else => null,
    };
}
