/// dataflow - Data Flow Analysis
/// Provides abstract value tracking and data flow state management

const std = @import("std");
const Allocator = std.mem.Allocator;
const TypeState = @import("type_inference.zig").TypeState;

// ============================================================================
// Data Flow Analysis
// ============================================================================

/// Abstract value for data flow
pub const AbstractValue = struct {
    /// Type information
    type_state: TypeState,
    /// Definition site (instruction index)
    def_site: u32,
    /// Uses of this value
    uses: std.ArrayList(u32),

    /// Create new abstract value
    pub fn init(allocator: Allocator, def_site: u32) AbstractValue {
        return AbstractValue{
            .type_state = TypeState.unknown(),
            .def_site = def_site,
            .uses = std.ArrayList(u32).init(allocator),
        };
    }

    /// Free resources
    pub fn deinit(self: *AbstractValue, allocator: Allocator) void {
        self.uses.deinit(allocator);
    }

    /// Add use
    pub fn addUse(self: *AbstractValue, allocator: Allocator, use_site: u32) !void {
        try self.uses.append(allocator, use_site);
    }
};

/// Data flow analysis state
pub const DataFlowState = struct {
    const Self = @This();

    /// Values at each stack slot
    stack: std.ArrayList(TypeState),
    /// Values at each local variable
    locals: std.ArrayList(TypeState),
    /// Values at each free variable
    freevars: std.ArrayList(TypeState),
    /// Memory allocator
    allocator: Allocator,

    /// Create new state
    pub fn init(allocator: Allocator, num_locals: usize, num_freevars: usize) !Self {
        var locals: std.ArrayList(TypeState) = .{};
        var freevars: std.ArrayList(TypeState) = .{};

        try locals.resize(allocator, num_locals);
        for (locals.items) |*s| s.* = TypeState.unknown();

        try freevars.resize(allocator, num_freevars);
        for (freevars.items) |*s| s.* = TypeState.unknown();

        return Self{
            .stack = .{},
            .locals = locals,
            .freevars = freevars,
            .allocator = allocator,
        };
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
        self.locals.deinit(self.allocator);
        self.freevars.deinit(self.allocator);
    }

    /// Push type to stack
    pub fn push(self: *Self, state: TypeState) !void {
        try self.stack.append(self.allocator, state);
    }

    /// Pop type from stack
    pub fn pop(self: *Self) ?TypeState {
        return self.stack.popOrNull();
    }

    /// Peek at top of stack
    pub fn peek(self: *const Self) ?TypeState {
        if (self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }

    /// Get local type
    pub fn getLocal(self: *const Self, idx: usize) ?TypeState {
        if (idx >= self.locals.items.len) return null;
        return self.locals.items[idx];
    }

    /// Set local type
    pub fn setLocal(self: *Self, idx: usize, state: TypeState) !void {
        if (idx >= self.locals.items.len) {
            try self.locals.resize(self.allocator, idx + 1);
        }
        self.locals.items[idx] = state;
    }

    /// Join with another state
    pub fn join(self: *Self, other: *const Self) void {
        // Join stacks
        const min_len = @min(self.stack.items.len, other.stack.items.len);
        for (0..min_len) |i| {
            self.stack.items[i] = self.stack.items[i].join(other.stack.items[i]);
        }

        // Join locals
        for (0..@min(self.locals.items.len, other.locals.items.len)) |i| {
            self.locals.items[i] = self.locals.items[i].join(other.locals.items[i]);
        }
    }

    /// Clone state
    pub fn clone(self: *const Self) !Self {
        var new_state = Self{
            .stack = try self.stack.clone(self.allocator),
            .locals = try self.locals.clone(self.allocator),
            .freevars = try self.freevars.clone(self.allocator),
            .allocator = self.allocator,
        };
        return new_state;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "dataflow state" {
    const allocator = std.testing.allocator;
    const TypeLattice = @import("type_inference.zig").TypeLattice;

    var state = try DataFlowState.init(allocator, 3, 0);
    defer state.deinit();

    try state.push(TypeState.fromType(.small_int));
    try state.push(TypeState.fromType(.float_type));

    try std.testing.expectEqual(@as(usize, 2), state.stack.items.len);
    try std.testing.expectEqual(TypeLattice.float_type, state.peek().?.type_lattice);

    _ = state.pop();
    try std.testing.expectEqual(TypeLattice.small_int, state.peek().?.type_lattice);
}
