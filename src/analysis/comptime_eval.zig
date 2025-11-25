const std = @import("std");
const ast = @import("../ast.zig");
const string_ops = @import("comptime_string.zig");
const list_ops = @import("comptime_list.zig");
const builtin_ops = @import("comptime_builtins.zig");

// Import split modules
const core = @import("comptime_eval/core.zig");
const arithmetic = @import("comptime_eval/arithmetic.zig");

// Re-export core types
pub const ComptimeValue = core.ComptimeValue;
const isConstantList = core.isConstantList;
const allSameType = core.allSameType;

/// Compile-time evaluator for constant expressions
pub const ComptimeEvaluator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComptimeEvaluator {
        return .{ .allocator = allocator };
    }

    pub fn tryEval(self: *ComptimeEvaluator, node: ast.Node) ?ComptimeValue {
        return switch (node) {
            .constant => |val| switch (val.value) {
                .int => |i| ComptimeValue{ .int = i },
                .float => |f| ComptimeValue{ .float = f },
                .bool => |b| ComptimeValue{ .bool = b },
                .string => |s| ComptimeValue{ .string = s },
                .none => null, // None cannot be compile-time evaluated
            },
            .binop => |op| self.evalBinOp(op),
            .unaryop => |op| self.evalUnaryOp(op),
            .compare => |cmp| self.evalCompare(cmp),
            .boolop => |bop| self.evalBoolOp(bop),
            .call => |call| self.evalCall(call),
            .subscript => |sub| self.evalSubscript(sub),
            .list => |l| {
                if (isConstantList(l.elts) and allSameType(l.elts)) {
                    return null;
                }
                return self.evalListLiteral(l.elts);
            },
            else => null,
        };
    }

    fn evalBinOp(self: *ComptimeEvaluator, op: ast.Node.BinOp) ?ComptimeValue {
        const left = self.tryEval(op.left.*) orelse return null;
        const right = self.tryEval(op.right.*) orelse return null;
        return switch (op.op) {
            .Add => arithmetic.evalAdd(self.allocator, left, right),
            .Sub => arithmetic.evalSub(self.allocator, left, right),
            .Mult => arithmetic.evalMul(self.allocator, left, right),
            .Div => arithmetic.evalDiv(self.allocator, left, right),
            .FloorDiv => arithmetic.evalFloorDiv(self.allocator, left, right),
            .Mod => arithmetic.evalMod(self.allocator, left, right),
            .Pow => arithmetic.evalPow(self.allocator, left, right),
            .BitAnd => arithmetic.evalBitAnd(self.allocator, left, right),
            .BitOr => arithmetic.evalBitOr(self.allocator, left, right),
            .BitXor => arithmetic.evalBitXor(self.allocator, left, right),
        };
    }

    fn evalUnaryOp(self: *ComptimeEvaluator, op: ast.Node.UnaryOp) ?ComptimeValue {
        const operand = self.tryEval(op.operand.*) orelse return null;
        return switch (op.op) {
            .Not => self.evalNot(operand),
            .USub => self.evalUSub(operand),
            .UAdd => operand,
            .Invert => self.evalInvert(operand),
        };
    }

    fn evalCompare(self: *ComptimeEvaluator, cmp: ast.Node.Compare) ?ComptimeValue {
        if (cmp.ops.len != 1 or cmp.comparators.len != 1) return null;
        const left = self.tryEval(cmp.left.*) orelse return null;
        const right = self.tryEval(cmp.comparators[0]) orelse return null;
        return switch (cmp.ops[0]) {
            .Eq => self.evalEq(left, right),
            .NotEq => self.evalNe(left, right),
            .Lt => self.evalLt(left, right),
            .LtEq => self.evalLe(left, right),
            .Gt => self.evalGt(left, right),
            .GtEq => self.evalGe(left, right),
            .In, .NotIn => null,
        };
    }

    fn evalBoolOp(self: *ComptimeEvaluator, bop: ast.Node.BoolOp) ?ComptimeValue {
        var result: bool = switch (bop.op) {
            .And => true,
            .Or => false,
        };
        for (bop.values) |val_node| {
            const val = self.tryEval(val_node) orelse return null;
            const bool_val = self.toBool(val) orelse return null;
            switch (bop.op) {
                .And => {
                    result = result and bool_val;
                    if (!result) break;
                },
                .Or => {
                    result = result or bool_val;
                    if (result) break;
                },
            }
        }
        return ComptimeValue{ .bool = result };
    }

    fn evalNot(self: *ComptimeEvaluator, operand: ComptimeValue) ?ComptimeValue {
        return ComptimeValue{ .bool = !(self.toBool(operand) orelse return null) };
    }

    fn evalUSub(self: *ComptimeEvaluator, operand: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (operand) {
            .int => |i| blk: {
                if (i == std.math.minInt(i64)) break :blk null;
                break :blk ComptimeValue{ .int = -i };
            },
            .float => |f| ComptimeValue{ .float = -f },
            else => null,
        };
    }

    fn evalInvert(self: *ComptimeEvaluator, operand: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (operand) {
            .int => |i| ComptimeValue{ .int = ~i },
            else => null, // Bitwise NOT only applies to integers
        };
    }

    fn evalEq(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        const result = switch (left) {
            .int => |l| switch (right) {
                .int => |r| l == r,
                .float => |r| @as(f64, @floatFromInt(l)) == r,
                else => false,
            },
            .float => |l| switch (right) {
                .int => |r| l == @as(f64, @floatFromInt(r)),
                .float => |r| l == r,
                else => false,
            },
            .bool => |l| switch (right) {
                .bool => |r| l == r,
                else => false,
            },
            .string => |l| switch (right) {
                .string => |r| std.mem.eql(u8, l, r),
                else => false,
            },
            .list => |l| switch (right) {
                .list => |r| blk: {
                    if (l.len != r.len) break :blk false;
                    for (l, r) |left_item, right_item| {
                        const item_eq = self.evalEq(left_item, right_item) orelse break :blk false;
                        if (!item_eq.bool) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
        };
        return ComptimeValue{ .bool = result };
    }

    fn evalNe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        const eq_result = self.evalEq(left, right) orelse return null;
        return ComptimeValue{ .bool = !eq_result.bool };
    }

    fn evalLt(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l < r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) < r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l < @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l < r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = std.mem.lessThan(u8, l, r) },
                else => null,
            },
            else => null,
        };
    }

    fn evalLe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l <= r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) <= r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l <= @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l <= r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = !std.mem.lessThan(u8, r, l) },
                else => null,
            },
            else => null,
        };
    }

    fn evalGt(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l > r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) > r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l > @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l > r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = std.mem.lessThan(u8, r, l) },
                else => null,
            },
            else => null,
        };
    }

    fn evalGe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l >= r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) >= r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l >= @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l >= r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = !std.mem.lessThan(u8, l, r) },
                else => null,
            },
            else => null,
        };
    }

    fn toBool(self: *ComptimeEvaluator, value: ComptimeValue) ?bool {
        _ = self;
        return switch (value) {
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0,
            .list => |l| l.len > 0,
        };
    }

    fn tryEvalWrapper(ctx: *anyopaque, node: ast.Node) ?ComptimeValue {
        const self: *ComptimeEvaluator = @ptrCast(@alignCast(ctx));
        return self.tryEval(node);
    }

    fn evalCall(self: *ComptimeEvaluator, call: ast.Node.Call) ?ComptimeValue {
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            const obj = self.tryEval(attr.value.*) orelse return null;
            return self.evalMethod(obj, attr.attr, call.args);
        }
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            const builtins = builtin_ops.BuiltinOps.init(
                self.allocator,
                @as(*anyopaque, @ptrCast(self)),
                tryEvalWrapper,
            );
            return builtins.evalBuiltin(func_name, call.args);
        }
        return null;
    }

    fn evalMethod(self: *ComptimeEvaluator, obj: ComptimeValue, method: []const u8, args: []ast.Node) ?ComptimeValue {
        if (obj != .string) return null;
        const s = obj.string;
        const str_ops = string_ops.StringOps.init(self.allocator);
        if (std.mem.eql(u8, method, "upper")) {
            return str_ops.evalUpper(s);
        } else if (std.mem.eql(u8, method, "lower")) {
            return str_ops.evalLower(s);
        } else if (std.mem.eql(u8, method, "strip")) {
            return str_ops.evalStrip(s);
        } else if (std.mem.eql(u8, method, "replace")) {
            if (args.len != 2) return null;
            const old = self.tryEval(args[0]) orelse return null;
            const new = self.tryEval(args[1]) orelse return null;
            if (old != .string or new != .string) return null;
            return str_ops.evalReplace(s, old.string, new.string);
        }
        return null;
    }

    fn evalListLiteral(self: *ComptimeEvaluator, items: []ast.Node) ?ComptimeValue {
        var result = std.ArrayList(ComptimeValue){};
        for (items) |item| {
            const val = self.tryEval(item) orelse return null;
            result.append(self.allocator, val) catch return null;
        }
        return ComptimeValue{ .list = result.toOwnedSlice(self.allocator) catch return null };
    }

    fn evalSubscript(self: *ComptimeEvaluator, sub: ast.Node.Subscript) ?ComptimeValue {
        const value = self.tryEval(sub.value.*) orelse return null;
        if (sub.slice != .index) return null;
        const index_node = self.tryEval(sub.slice.index.*) orelse return null;
        const list_helper = list_ops.ListOps.init(
            self.allocator,
            @as(*anyopaque, @ptrCast(self)),
            tryEvalWrapper,
        );
        return list_helper.evalSubscript(value, index_node);
    }
};
