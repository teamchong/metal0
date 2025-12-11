/// Control Flow Context (PEP 765)
/// Tracks control flow state for finally block warnings

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Context for tracking control flow in finally blocks
pub const ControlFlowContext = struct {
    /// In a finally block
    in_finally: bool = false,
    /// In a function definition
    in_funcdef: bool = false,
    /// In a loop
    in_loop: bool = false,
};

/// Stack of control flow contexts
pub const ContextStack = struct {
    const Self = @This();

    contexts: std.ArrayList(ControlFlowContext),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .contexts = std.ArrayList(ControlFlowContext).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.contexts.deinit();
    }

    pub fn push(self: *Self, ctx: ControlFlowContext) !void {
        try self.contexts.append(ctx);
    }

    pub fn pop(self: *Self) void {
        if (self.contexts.items.len > 0) {
            _ = self.contexts.pop();
        }
    }

    pub fn top(self: *const Self) ?ControlFlowContext {
        if (self.contexts.items.len == 0) return null;
        return self.contexts.items[self.contexts.items.len - 1];
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.contexts.items.len == 0;
    }
};
