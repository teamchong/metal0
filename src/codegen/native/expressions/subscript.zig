/// Subscript and slicing code generation
/// Handles array/dict indexing and slicing operations
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Check if a node is a negative constant
pub fn isNegativeConstant(node: ast.Node) bool {
    if (node == .constant and node.constant.value == .int) {
        return node.constant.value.int < 0;
    }
    if (node == .unaryop and node.unaryop.op == .USub) {
        if (node.unaryop.operand.* == .constant and node.unaryop.operand.constant.value == .int) {
            return true;
        }
    }
    return false;
}

/// Generate a slice index, handling negative indices
/// If in_slice_context is true and we have __s available, convert negatives to __s.len - abs(index)
pub fn genSliceIndex(self: *NativeCodegen, node: ast.Node, in_slice_context: bool) CodegenError!void {
    if (!in_slice_context) {
        try genExpr(self, node);
        return;
    }

    // Check for negative constant or unary minus
    if (node == .constant and node.constant.value == .int and node.constant.value.int < 0) {
        // Negative constant: -2 becomes max(0, __s.len - 2) to prevent underflow
        const abs_val = if (node.constant.value.int < 0) -node.constant.value.int else node.constant.value.int;
        try self.output.writer(self.allocator).print("if (__s.len >= {d}) __s.len - {d} else 0", .{ abs_val, abs_val });
    } else if (node == .unaryop and node.unaryop.op == .USub) {
        // Unary minus: -x becomes saturating subtraction
        try self.output.appendSlice(self.allocator, "__s.len -| ");
        try genExpr(self, node.unaryop.operand.*);
    } else {
        // Positive index - use as-is
        try genExpr(self, node);
    }
}

/// Generate array/dict subscript (a[b])
pub fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    switch (subscript.slice) {
        .index => {
            // Check if this is a dict or list subscript
            const value_type = try self.type_inferrer.inferExpr(subscript.value.*);
            const is_dict = (value_type == .dict);
            const is_list = (value_type == .list);

            if (is_dict) {
                // Dict access: use .get(key).?
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, ".get(");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, ").?");
            } else if (is_list) {
                // ArrayList indexing: a.items[b]
                // Check for negative index
                if (isNegativeConstant(subscript.slice.index.*)) {
                    // Need block to access .items.len
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; break :blk __s.items[");
                    try genSliceIndex(self, subscript.slice.index.*, true);
                    try self.output.appendSlice(self.allocator, "]; }");
                } else {
                    // Positive index - simple subscript
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, ".items[");
                    try genExpr(self, subscript.slice.index.*);
                    try self.output.appendSlice(self.allocator, "]");
                }
            } else {
                // Array/slice/string indexing: a[b]
                // Check for negative index
                if (isNegativeConstant(subscript.slice.index.*)) {
                    // Need block to access .len
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; break :blk __s[");
                    try genSliceIndex(self, subscript.slice.index.*, true);
                    try self.output.appendSlice(self.allocator, "]; }");
                } else {
                    // Positive index - simple subscript
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "[");
                    try genExpr(self, subscript.slice.index.*);
                    try self.output.appendSlice(self.allocator, "]");
                }
            }
        },
        .slice => |slice_range| {
            // Slicing: a[start:end] or a[start:end:step]
            const has_step = slice_range.step != null;
            const needs_len = slice_range.upper == null;

            if (has_step) {
                // With step: use slice with step calculation
                // Need to check if this is string or list slicing
                const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

                if (value_type == .string) {
                    // String slicing with step (supports negative step for reverse iteration)
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.output.appendSlice(self.allocator, "; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true);
                        try self.output.appendSlice(self.allocator, ")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.output.appendSlice(self.allocator, "; var __result = std.ArrayList(u8){}; if (__step > 0) { var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) { try __result.append(std.heap.page_allocator, __s[__i]); } } else if (__step < 0) { var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) { try __result.append(std.heap.page_allocator, __s[@intCast(__i)]); } } break :blk try __result.toOwnedSlice(std.heap.page_allocator); }");
                } else if (value_type == .list) {
                    // List slicing with step (supports negative step for reverse iteration)
                    // Get element type to generate proper ArrayList
                    const elem_type = value_type.list.*;

                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.output.appendSlice(self.allocator, "; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true);
                        try self.output.appendSlice(self.allocator, ")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.output.appendSlice(self.allocator, "; var __result = std.ArrayList(");

                    // Generate element type
                    try elem_type.toZigType(self.allocator, &self.output);

                    try self.output.appendSlice(self.allocator, "){}; if (__step > 0) { var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) { try __result.append(std.heap.page_allocator, __s[__i]); } } else if (__step < 0) { var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) { try __result.append(std.heap.page_allocator, __s[@intCast(__i)]); } } break :blk try __result.toOwnedSlice(std.heap.page_allocator); }");
                } else {
                    // Unknown type - generate error
                    try self.output.appendSlice(self.allocator, "@compileError(\"Slicing with step requires string or list type\")");
                }
            } else if (needs_len) {
                // Need length for upper bound - use block expression with bounds checking
                try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, "; const __start = @min(");

                if (slice_range.lower) |lower| {
                    try genSliceIndex(self, lower.*, true);
                } else {
                    try self.output.appendSlice(self.allocator, "0");
                }

                try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start <= __s.len) __s[__start..__s.len] else \"\"; }");
            } else {
                // Simple slice with both bounds known - need to check for negative indices
                const has_negative = blk: {
                    if (slice_range.lower) |lower| {
                        if (isNegativeConstant(lower.*)) break :blk true;
                    }
                    if (slice_range.upper) |upper| {
                        if (isNegativeConstant(upper.*)) break :blk true;
                    }
                    break :blk false;
                };

                if (has_negative) {
                    // Need block expression to handle negative indices with bounds checking
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __start = @min(");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        try self.output.appendSlice(self.allocator, "0");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); const __end = @min(");

                    if (slice_range.upper) |upper| {
                        try genSliceIndex(self, upper.*, true);
                    } else {
                        try self.output.appendSlice(self.allocator, "__s.len");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start < __end) __s[__start..__end] else \"\"; }");
                } else {
                    // No negative indices - but still need bounds checking for Python semantics
                    // Python allows out-of-bounds slices, Zig doesn't
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __start = @min(");

                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.output.appendSlice(self.allocator, "0");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); const __end = @min(");
                    try genExpr(self, slice_range.upper.?.*);
                    try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start < __end) __s[__start..__end] else \"\"; }");
                }
            }
        },
    }
}
