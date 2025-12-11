/// instrumentation/code_instrumentation - Per-code-object instrumentation state
/// Tracks instrumented bytecode and version synchronization

const std = @import("std");

const Allocator = std.mem.Allocator;

// Version access function - will be set by parent module
var version_getter: ?*const fn () u64 = null;

pub fn setVersionGetter(getter: *const fn () u64) void {
    version_getter = getter;
}

fn getCurrentVersion() u64 {
    if (version_getter) |getter| {
        return getter();
    }
    return 0;
}

// ============================================================================
// Code Object Instrumentation
// ============================================================================

/// Per-code-object instrumentation state
pub const CodeInstrumentation = struct {
    /// Instrumented bytecode (if modified)
    instrumented_code: ?[]u8 = null,
    /// Per-instruction monitoring
    instruction_events: ?[]u16 = null,
    /// Version when instrumentation was last updated
    version: u64 = 0,
    /// Allocator
    allocator: ?Allocator = null,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        if (self.allocator) |alloc| {
            if (self.instrumented_code) |code| {
                alloc.free(code);
            }
            if (self.instruction_events) |events| {
                alloc.free(events);
            }
        }
    }

    /// Check if instrumentation needs update
    pub fn needsUpdate(self: *const Self) bool {
        return self.version != getCurrentVersion();
    }

    /// Mark as updated
    pub fn markUpdated(self: *Self) void {
        self.version = getCurrentVersion();
    }
};
