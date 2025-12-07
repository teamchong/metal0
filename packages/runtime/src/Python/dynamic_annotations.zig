/// dynamic_annotations - Thread Sanitizer Annotations
/// Mirrors cpython/Python/dynamic_annotations.c
///
/// Provides annotations for thread sanitizers (TSan, ASan, etc.) to help
/// detect data races and memory errors in multithreaded code.

const std = @import("std");

// ============================================================================
// Annotation Types
// ============================================================================

/// Types of dynamic annotations
pub const AnnotationType = enum {
    /// Happens-before relationship
    happens_before,
    /// Happens-after relationship
    happens_after,
    /// Memory access annotation
    memory_access,
    /// Lock annotation
    lock,
    /// Benign race annotation
    benign_race,
    /// Ignore begin/end
    ignore,
    /// Thread creation/destruction
    thread,
    /// Publish/unpublish
    publish,
};

/// Memory access modes
pub const AccessMode = enum {
    read,
    write,
    read_write,
};

// ============================================================================
// Annotation Functions
// ============================================================================

/// Annotation interface (typically implemented via compiler intrinsics or macros)
pub const Annotations = struct {
    /// Indicate a happens-before relationship
    pub fn happensBefore(addr: *anyopaque) void {
        // TSan: __tsan_release(addr)
        _ = addr;
        std.atomic.fence(.release);
    }

    /// Indicate a happens-after relationship
    pub fn happensAfter(addr: *anyopaque) void {
        // TSan: __tsan_acquire(addr)
        _ = addr;
        std.atomic.fence(.acquire);
    }

    /// Annotate a memory read
    pub fn memoryRead(addr: *const anyopaque, size: usize) void {
        // TSan: __tsan_read_range(addr, size)
        _ = addr;
        _ = size;
    }

    /// Annotate a memory write
    pub fn memoryWrite(addr: *anyopaque, size: usize) void {
        // TSan: __tsan_write_range(addr, size)
        _ = addr;
        _ = size;
    }

    /// Annotate lock acquire
    pub fn lockAcquire(lock: *anyopaque) void {
        // TSan: __tsan_mutex_post_lock(lock)
        _ = lock;
    }

    /// Annotate lock release
    pub fn lockRelease(lock: *anyopaque) void {
        // TSan: __tsan_mutex_pre_unlock(lock)
        _ = lock;
    }

    /// Annotate a benign race (intentional race that is safe)
    pub fn benignRace(addr: *anyopaque, description: []const u8) void {
        // TSan: AnnotateBenignRace(addr, description)
        _ = addr;
        _ = description;
    }

    /// Begin ignoring memory accesses (for noise reduction)
    pub fn ignoreReadsBegin() void {
        // TSan: AnnotateIgnoreReadsBegin()
    }

    /// End ignoring memory reads
    pub fn ignoreReadsEnd() void {
        // TSan: AnnotateIgnoreReadsEnd()
    }

    /// Begin ignoring memory writes
    pub fn ignoreWritesBegin() void {
        // TSan: AnnotateIgnoreWritesBegin()
    }

    /// End ignoring memory writes
    pub fn ignoreWritesEnd() void {
        // TSan: AnnotateIgnoreWritesEnd()
    }

    /// Annotate thread creation
    pub fn threadCreate(parent: std.Thread.Id, child: std.Thread.Id) void {
        _ = parent;
        _ = child;
    }

    /// Annotate thread join
    pub fn threadJoin(joiner: std.Thread.Id, joinee: std.Thread.Id) void {
        _ = joiner;
        _ = joinee;
    }

    /// Publish memory to other threads
    pub fn publish(addr: *anyopaque, size: usize) void {
        _ = addr;
        _ = size;
        std.atomic.fence(.release);
    }

    /// Unpublish memory from other threads
    pub fn unpublish(addr: *anyopaque, size: usize) void {
        _ = addr;
        _ = size;
        std.atomic.fence(.acquire);
    }

    /// Annotate condition variable signal
    pub fn condSignal(cond: *anyopaque) void {
        _ = cond;
    }

    /// Annotate condition variable wait
    pub fn condWait(cond: *anyopaque) void {
        _ = cond;
    }

    /// Annotate rwlock read lock
    pub fn rwlockRdlock(lock: *anyopaque) void {
        _ = lock;
    }

    /// Annotate rwlock write lock
    pub fn rwlockWrlock(lock: *anyopaque) void {
        _ = lock;
    }

    /// Annotate rwlock unlock
    pub fn rwlockUnlock(lock: *anyopaque) void {
        _ = lock;
    }
};

// ============================================================================
// Annotation Scope Guards
// ============================================================================

/// RAII guard for ignoring reads
pub const IgnoreReadsGuard = struct {
    pub fn init() @This() {
        Annotations.ignoreReadsBegin();
        return .{};
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
        Annotations.ignoreReadsEnd();
    }
};

/// RAII guard for ignoring writes
pub const IgnoreWritesGuard = struct {
    pub fn init() @This() {
        Annotations.ignoreWritesBegin();
        return .{};
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
        Annotations.ignoreWritesEnd();
    }
};

/// RAII guard for ignoring all memory operations
pub const IgnoreAllGuard = struct {
    reads_guard: IgnoreReadsGuard,
    writes_guard: IgnoreWritesGuard,

    pub fn init() @This() {
        return .{
            .reads_guard = IgnoreReadsGuard.init(),
            .writes_guard = IgnoreWritesGuard.init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.writes_guard.deinit();
        self.reads_guard.deinit();
    }
};

// ============================================================================
// Running Status
// ============================================================================

/// Check if thread sanitizer is active
pub fn isRunningOnValgrind() bool {
    // Would check VALGRIND macros
    return false;
}

/// Check if running under TSan
pub fn isRunningUnderTSan() bool {
    // Would check __SANITIZE_THREAD__
    return false;
}

/// Check if running under ASan
pub fn isRunningUnderASan() bool {
    // Would check __SANITIZE_ADDRESS__
    return false;
}

/// Check if running under MSan
pub fn isRunningUnderMSan() bool {
    // Would check __SANITIZE_MEMORY__
    return false;
}

/// Check if any sanitizer is active
pub fn isRunningUnderAnySanitizer() bool {
    return isRunningUnderTSan() or isRunningUnderASan() or isRunningUnderMSan();
}

// ============================================================================
// Debug Helpers
// ============================================================================

/// Annotation debug info
pub const AnnotationDebug = struct {
    enabled: bool = false,
    log_file: ?std.fs.File = null,

    pub fn log(self: *const @This(), comptime fmt: []const u8, args: anytype) void {
        if (!self.enabled) return;
        if (self.log_file) |file| {
            file.writer().print(fmt, args) catch {};
        }
    }
};

var debug_state = AnnotationDebug{};

/// Enable debug logging
pub fn enableDebug(file: std.fs.File) void {
    debug_state.enabled = true;
    debug_state.log_file = file;
}

/// Disable debug logging
pub fn disableDebug() void {
    debug_state.enabled = false;
    debug_state.log_file = null;
}

// ============================================================================
// Python-Specific Annotations
// ============================================================================

/// Annotate GIL acquisition
pub fn annotateGILAcquire(gil: *anyopaque) void {
    Annotations.lockAcquire(gil);
    Annotations.happensAfter(gil);
}

/// Annotate GIL release
pub fn annotateGILRelease(gil: *anyopaque) void {
    Annotations.happensBefore(gil);
    Annotations.lockRelease(gil);
}

/// Annotate object creation
pub fn annotateObjectCreate(obj: *anyopaque, size: usize) void {
    Annotations.publish(obj, size);
}

/// Annotate object destruction
pub fn annotateObjectDestroy(obj: *anyopaque, size: usize) void {
    Annotations.unpublish(obj, size);
}

/// Annotate refcount increment
pub fn annotateIncref(obj: *anyopaque) void {
    Annotations.memoryWrite(obj, @sizeOf(usize));
}

/// Annotate refcount decrement
pub fn annotateDecref(obj: *anyopaque) void {
    Annotations.memoryWrite(obj, @sizeOf(usize));
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the dynamic_annotations module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    disableDebug();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "sanitizer detection" {
    // These should return false in normal test runs
    try std.testing.expect(!isRunningUnderTSan());
    try std.testing.expect(!isRunningUnderASan());
    try std.testing.expect(!isRunningUnderMSan());
}

test "annotation functions don't crash" {
    var dummy: u8 = 0;
    const addr = @as(*anyopaque, @ptrCast(&dummy));

    Annotations.happensBefore(addr);
    Annotations.happensAfter(addr);
    Annotations.memoryRead(@ptrCast(&dummy), 1);
    Annotations.memoryWrite(addr, 1);
    Annotations.lockAcquire(addr);
    Annotations.lockRelease(addr);
}

test "ignore guards" {
    var reads_guard = IgnoreReadsGuard.init();
    defer reads_guard.deinit();

    var writes_guard = IgnoreWritesGuard.init();
    defer writes_guard.deinit();
}

test "ignore all guard" {
    var guard = IgnoreAllGuard.init();
    defer guard.deinit();
}

test "benign race annotation" {
    var dummy: u8 = 0;
    Annotations.benignRace(@ptrCast(&dummy), "test race");
}

test "python annotations" {
    var obj: u64 = 0;
    annotateObjectCreate(@ptrCast(&obj), @sizeOf(u64));
    annotateIncref(@ptrCast(&obj));
    annotateDecref(@ptrCast(&obj));
    annotateObjectDestroy(@ptrCast(&obj), @sizeOf(u64));
}
