const std = @import("std");
const ast = @import("../ast.zig");

/// Variable lifetime information for optimization
pub const VariableLifetime = struct {
    name: []const u8,
    first_assignment: usize, // Line number
    last_use: usize, // Line number
    scope_end: usize,
    is_loop_local: bool,
    reassignment_count: usize,

    pub fn init(name: []const u8) VariableLifetime {
        return .{
            .name = name,
            .first_assignment = 0,
            .last_use = 0,
            .scope_end = 0,
            .is_loop_local = false,
            .reassignment_count = 0,
        };
    }
};

/// Expression chain detection for optimization
pub const ExpressionChain = struct {
    op: ast.Operator,
    operands: []ast.Node,
    chain_length: usize,
    is_string_op: bool,

    pub fn init(allocator: std.mem.Allocator, op: ast.Operator, is_string_op: bool) !ExpressionChain {
        return .{
            .op = op,
            .operands = try allocator.alloc(ast.Node, 0),
            .chain_length = 0,
            .is_string_op = is_string_op,
        };
    }

    pub fn deinit(self: *ExpressionChain, allocator: std.mem.Allocator) void {
        allocator.free(self.operands);
    }
};

/// Complete semantic analysis information
pub const SemanticInfo = struct {
    lifetimes: std.StringHashMap(VariableLifetime),
    expr_chains: std.ArrayList(ExpressionChain),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SemanticInfo {
        return .{
            .lifetimes = std.StringHashMap(VariableLifetime).init(allocator),
            .expr_chains = std.ArrayList(ExpressionChain){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SemanticInfo) void {
        self.lifetimes.deinit();
        for (self.expr_chains.items) |*chain| {
            chain.deinit(self.allocator);
        }
        self.expr_chains.deinit(self.allocator);
    }

    /// Add or update a variable's lifetime information
    pub fn recordVariableUse(self: *SemanticInfo, name: []const u8, line: usize, is_assignment: bool) !void {
        var lifetime = self.lifetimes.get(name) orelse VariableLifetime.init(name);

        if (is_assignment) {
            if (lifetime.first_assignment == 0) {
                lifetime.first_assignment = line;
            } else {
                lifetime.reassignment_count += 1;
            }
        }

        lifetime.last_use = line;
        try self.lifetimes.put(name, lifetime);
    }

    /// Mark a variable's scope end
    pub fn markScopeEnd(self: *SemanticInfo, name: []const u8, line: usize) !void {
        if (self.lifetimes.getPtr(name)) |lifetime| {
            lifetime.scope_end = line;
        }
    }

    /// Mark a variable as loop-local
    pub fn markLoopLocal(self: *SemanticInfo, name: []const u8) !void {
        if (self.lifetimes.getPtr(name)) |lifetime| {
            lifetime.is_loop_local = true;
        }
    }

    /// Check if a variable can be optimized away early
    pub fn canOptimizeAway(self: *SemanticInfo, name: []const u8, current_line: usize) bool {
        const lifetime = self.lifetimes.get(name) orelse return false;
        return current_line >= lifetime.last_use;
    }

    /// Check if a variable is mutated (reassigned) after its first assignment
    pub fn isMutated(self: *SemanticInfo, name: []const u8) bool {
        const lifetime = self.lifetimes.get(name) orelse return false;
        return lifetime.reassignment_count > 0;
    }
};
