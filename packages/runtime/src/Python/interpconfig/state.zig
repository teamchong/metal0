/// state - Interpreter State
/// Mirrors cpython/Python/interpconfig.c (state section)
///
/// Manages individual interpreter state:
/// - Unique identifier per interpreter
/// - Configuration snapshot
/// - Reference counting for lifetime management
/// - Main vs sub-interpreter distinction
/// - Linked list for manager traversal

const std = @import("std");
const Atomic = std.atomic.Value;
const config_mod = @import("config.zig");

/// Unique identifier for an interpreter
pub const InterpId = u64;

/// Simple interpreter state for configuration
pub const InterpreterState = struct {
    /// Unique ID
    id: InterpId,

    /// Configuration used to create this interpreter
    config: config_mod.PyInterpreterConfig,

    /// Whether this is the main interpreter
    is_main: bool,

    /// Whether interpreter is finalized
    finalized: bool,

    /// Reference count (for management)
    refcount: Atomic(u32),

    /// Next interpreter in list
    next: ?*InterpreterState,

    /// Previous interpreter in list
    prev: ?*InterpreterState,

    const Self = @This();

    /// Create a new interpreter state
    pub fn create(id: InterpId, cfg: config_mod.PyInterpreterConfig, is_main: bool) Self {
        return .{
            .id = id,
            .config = cfg,
            .is_main = is_main,
            .finalized = false,
            .refcount = Atomic(u32).init(1),
            .next = null,
            .prev = null,
        };
    }

    /// Check if interpreter uses own GIL
    pub fn hasOwnGil(self: *const Self) bool {
        return self.config.gil == .own or
            (self.config.gil == .default and !self.is_main);
    }

    /// Check if threads are allowed
    pub fn allowsThreads(self: *const Self) bool {
        return self.config.allow_threads;
    }

    /// Increment reference count
    pub fn incref(self: *Self) void {
        _ = self.refcount.fetchAdd(1, .release);
    }

    /// Decrement reference count
    pub fn decref(self: *Self) u32 {
        return self.refcount.fetchSub(1, .release) - 1;
    }
};
