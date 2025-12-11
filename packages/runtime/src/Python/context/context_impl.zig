/// Context - immutable mapping of ContextVars to values
/// Uses HAMT for efficient structural sharing

const std = @import("std");
const Allocator = std.mem.Allocator;
const hamt = @import("../hamt.zig");

// Forward declarations
pub const ContextVar = @import("context_var.zig").ContextVar;
const global_state = @import("global_state.zig");

/// Sentinel value indicating a deleted variable in HAMT
/// We use this pattern because HAMT doesn't support delete operations.
/// A "deleted" variable is one whose value is set to this sentinel.
const DELETED_SENTINEL: *anyopaque = @ptrFromInt(1);

/// Context - immutable mapping of ContextVars to values
/// Uses HAMT for efficient structural sharing
pub const Context = struct {
    allocator: Allocator,
    vars: VarMap, // ContextVar -> value mapping
    prev_context: ?*Context = null, // For context stack
    entered: bool = false,

    const Self = @This();

    // Use pointer-based HAMT for context variables
    const VarMap = hamt.Hamt(*ContextVar, *anyopaque);

    fn varHash(cv: *ContextVar) u32 {
        return @truncate(@intFromPtr(cv));
    }

    fn varEql(a: *ContextVar, b: *ContextVar) bool {
        return a == b;
    }

    /// Create empty context
    pub fn create(allocator: Allocator) !*Self {
        const ctx = try allocator.create(Self);
        ctx.* = .{
            .allocator = allocator,
            .vars = VarMap.init(allocator, varHash, varEql),
        };
        return ctx;
    }

    /// Create context as copy of another
    pub fn copy(allocator: Allocator, other: *Self) !*Self {
        const ctx = try allocator.create(Self);
        ctx.* = .{
            .allocator = allocator,
            .vars = other.vars, // Structural sharing via HAMT
        };
        return ctx;
    }

    pub fn destroy(self: *Self) void {
        self.vars.deinit();
        self.allocator.destroy(self);
    }

    /// Get value for a ContextVar
    /// Returns null if the variable is not set or was deleted
    pub fn getVar(self: *Self, cv: *ContextVar) ?*anyopaque {
        const value = self.vars.get(cv) orelse return null;
        // Check for deletion sentinel
        if (value == DELETED_SENTINEL) return null;
        return value;
    }

    /// Set value for a ContextVar (creates new context state)
    pub fn setVar(self: *Self, cv: *ContextVar, value: *anyopaque) !void {
        self.vars = try self.vars.set(cv, value);
    }

    /// Delete a ContextVar from context
    /// Since HAMT doesn't support deletion, we set the value to a sentinel
    /// that getVar treats as "not present".
    pub fn delVar(self: *Self, cv: *ContextVar) !void {
        self.vars = try self.vars.set(cv, DELETED_SENTINEL);
    }

    /// Enter this context (push onto stack)
    pub fn enter(self: *Self) !void {
        if (self.entered) {
            return error.ContextAlreadyEntered;
        }

        self.prev_context = global_state.getCurrentContext();
        global_state.setCurrentContext(self);
        self.entered = true;

        global_state.notifyWatchers(.switched, self);
    }

    /// Exit this context (pop from stack)
    pub fn exit(self: *Self) !void {
        if (!self.entered) {
            return error.ContextNotEntered;
        }

        if (global_state.getCurrentContext() != self) {
            return error.WrongContext;
        }

        global_state.setCurrentContext(self.prev_context);
        self.prev_context = null;
        self.entered = false;

        global_state.notifyWatchers(.switched, global_state.getCurrentContext());
    }

    /// Run a function in this context
    pub fn run(self: *Self, comptime func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        try self.enter();
        defer self.exit() catch {};

        return @call(.auto, func, args);
    }

    /// Get number of variables in context
    pub fn size(self: *Self) usize {
        return self.vars.size();
    }

    /// Check if context has been entered
    pub fn isEntered(self: *Self) bool {
        return self.entered;
    }

    /// Create iterator over context variables
    pub fn iterator(self: *Self) VarMap.Iterator {
        return self.vars.iterator();
    }
};
