const std = @import("std");
const ast = @import("ast");
const ComptimeValue = @import("comptime_eval.zig").ComptimeValue;

/// Builtin function evaluation helpers (len, str, int, etc.)
pub const BuiltinOps = struct {
    allocator: std.mem.Allocator,
    tryEvalFn: *const fn (*anyopaque, ast.Node) ?ComptimeValue,
    ctx: *anyopaque,

    pub fn init(
        allocator: std.mem.Allocator,
        ctx: *anyopaque,
        tryEvalFn: *const fn (*anyopaque, ast.Node) ?ComptimeValue,
    ) BuiltinOps {
        return .{
            .allocator = allocator,
            .ctx = ctx,
            .tryEvalFn = tryEvalFn,
        };
    }

    pub fn evalBuiltin(self: BuiltinOps, name: []const u8, args: []ast.Node) ?ComptimeValue {
        if (std.mem.eql(u8, name, "len")) {
            if (args.len != 1) return null;
            const arg = self.tryEvalFn(self.ctx, args[0]) orelse return null;

            if (arg == .list) {
                return ComptimeValue{ .int = @intCast(arg.list.len) };
            } else if (arg == .string) {
                return ComptimeValue{ .int = @intCast(arg.string.len) };
            }
        }

        if (std.mem.eql(u8, name, "str")) {
            if (args.len != 1) return null;
            const arg = self.tryEvalFn(self.ctx, args[0]) orelse return null;
            return self.convertToString(arg);
        }

        if (std.mem.eql(u8, name, "int")) {
            if (args.len != 1) return null;
            const arg = self.tryEvalFn(self.ctx, args[0]) orelse return null;
            return self.convertToInt(arg);
        }

        return null;
    }

    fn convertToString(self: BuiltinOps, value: ComptimeValue) ?ComptimeValue {
        return switch (value) {
            .string => value,
            .int => |i| blk: {
                var buf = std.ArrayList(u8){};
                buf.writer(self.allocator).print("{d}", .{i}) catch {
                    buf.deinit(self.allocator);
                    break :blk null;
                };
                const result = buf.toOwnedSlice(self.allocator) catch break :blk null;
                break :blk ComptimeValue{ .string = result };
            },
            .float => |f| blk: {
                var buf = std.ArrayList(u8){};
                buf.writer(self.allocator).print("{d}", .{f}) catch {
                    buf.deinit(self.allocator);
                    break :blk null;
                };
                const result = buf.toOwnedSlice(self.allocator) catch break :blk null;
                break :blk ComptimeValue{ .string = result };
            },
            .bool => |b| ComptimeValue{ .string = if (b) "True" else "False" },
            .list => null, // Cannot convert list to string
        };
    }

    fn convertToInt(self: BuiltinOps, value: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (value) {
            .int => value,
            .float => |f| blk: {
                // Check if float is within i64 range before converting
                const min_i64: f64 = @floatFromInt(std.math.minInt(i64));
                const max_i64: f64 = @floatFromInt(std.math.maxInt(i64));
                if (f < min_i64 or f > max_i64 or std.math.isNan(f) or std.math.isInf(f)) {
                    break :blk null; // Out of range, cannot convert at comptime
                }
                break :blk ComptimeValue{ .int = @intFromFloat(f) };
            },
            .bool => |b| ComptimeValue{ .int = if (b) 1 else 0 },
            .string => |s| blk: {
                const result = std.fmt.parseInt(i64, s, 10) catch break :blk null;
                break :blk ComptimeValue{ .int = result };
            },
            .list => null, // Cannot convert list to int
        };
    }
};
