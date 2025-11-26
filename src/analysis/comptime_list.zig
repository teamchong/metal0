const std = @import("std");
const ast = @import("ast");
const ComptimeValue = @import("comptime_eval.zig").ComptimeValue;

/// List operation evaluation helpers
pub const ListOps = struct {
    allocator: std.mem.Allocator,
    tryEvalFn: *const fn (*anyopaque, ast.Node) ?ComptimeValue,
    ctx: *anyopaque,

    pub fn init(
        allocator: std.mem.Allocator,
        ctx: *anyopaque,
        tryEvalFn: *const fn (*anyopaque, ast.Node) ?ComptimeValue,
    ) ListOps {
        return .{
            .allocator = allocator,
            .ctx = ctx,
            .tryEvalFn = tryEvalFn,
        };
    }

    pub fn evalLiteral(self: ListOps, items: []ast.Node) ?ComptimeValue {
        var values = std.ArrayList(ComptimeValue){};

        for (items) |item| {
            const val = self.tryEvalFn(self.ctx, item) orelse {
                values.deinit(self.allocator);
                return null; // Not all items are constant
            };
            values.append(self.allocator, val) catch {
                values.deinit(self.allocator);
                return null;
            };
        }

        const result = values.toOwnedSlice(self.allocator) catch return null;
        return ComptimeValue{ .list = result };
    }

    pub fn evalSubscript(self: ListOps, value: ComptimeValue, index_node: ComptimeValue) ?ComptimeValue {
        if (value == .list and index_node == .int) {
            const idx = index_node.int;
            // Handle negative indexing
            const actual_idx: usize = if (idx < 0) blk: {
                const neg_idx = -idx;
                if (neg_idx > value.list.len) return null; // Out of bounds
                break :blk value.list.len - @as(usize, @intCast(neg_idx));
            } else blk: {
                if (idx >= value.list.len) return null; // Out of bounds
                break :blk @as(usize, @intCast(idx));
            };
            return value.list[actual_idx];
        }

        if (value == .string and index_node == .int) {
            const idx = index_node.int;
            // Handle negative indexing
            const actual_idx: usize = if (idx < 0) blk: {
                const neg_idx = -idx;
                if (neg_idx > value.string.len) return null; // Out of bounds
                break :blk value.string.len - @as(usize, @intCast(neg_idx));
            } else blk: {
                if (idx >= value.string.len) return null; // Out of bounds
                break :blk @as(usize, @intCast(idx));
            };
            // Return single character as string
            const result = self.allocator.alloc(u8, 1) catch return null;
            result[0] = value.string[actual_idx];
            return ComptimeValue{ .string = result };
        }

        return null;
    }
};
