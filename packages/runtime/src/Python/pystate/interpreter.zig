/// interpreter - Interpreter State
/// Python interpreter state structure and related types.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const lifecycle = @import("../pylifecycle.zig");
const types = @import("types.zig");

pub const ThreadStateList = types.ThreadStateList;
pub const ImportState = types.ImportState;
pub const CodecState = types.CodecState;
pub const GCState = types.GCState;
pub const LongState = types.LongState;
pub const DictState = types.DictState;
pub const CEvalState = types.CEvalState;
pub const InterpreterWhence = types.InterpreterWhence;

// ============================================================================
// Interpreter State
// ============================================================================

/// Python interpreter state
pub const InterpreterState = struct {
    /// Unique interpreter ID
    id: i64 = 0,

    /// Reference count for ID
    id_refcount: i64 = 0,

    /// Does interpreter require ID references?
    requires_idref: bool = false,

    /// Linked list pointers (global)
    next: ?*InterpreterState = null,
    prev: ?*InterpreterState = null,

    /// Is the interpreter ready for use?
    _ready: bool = false,

    /// Is the interpreter finalizing?
    finalizing: bool = false,

    /// How was this interpreter created?
    _whence: InterpreterWhence = .unknown,

    /// Feature flags
    feature_flags: u64 = 0,

    /// Configuration
    config: lifecycle.Config = .{},

    /// Thread state list
    threads: ThreadStateList = .{},

    /// Modules dictionary
    modules: ?*anyopaque = null,

    /// Builtins module
    builtins: ?*anyopaque = null,

    /// Import state
    imports: ImportState = .{},

    /// Codec state
    codecs: CodecState = .{},

    /// Warnings state
    warnings: ?*anyopaque = null,

    /// Audit hooks
    audit_hooks: ?*anyopaque = null,

    /// GC state
    gc: GCState = .{},

    /// Integer string conversion limit
    long_state: LongState = .{},

    /// Type cache
    type_cache: ?*anyopaque = null,

    /// Dict state
    dict_state: DictState = .{},

    /// CEVAL state
    ceval: CEvalState = .{},

    /// Allocator
    allocator: std.mem.Allocator = allocator_helper.fast_allocator,

    const Self = @This();

    pub fn isMain(self: *const Self) bool {
        return self.id == 0;
    }

    pub fn isReady(self: *const Self) bool {
        return self._ready;
    }
};
