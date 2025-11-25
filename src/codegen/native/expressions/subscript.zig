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
/// If in_slice_context is true and we have __s available, convert negatives to __s.items.len - abs(index) for lists
/// Note: This assumes __s is available in the current scope (from the enclosing blk: { const __s = ... })
/// For lists, __s.items.len is used; for strings/arrays, __s.len is used
pub fn genSliceIndex(self: *NativeCodegen, node: ast.Node, in_slice_context: bool, is_list: bool) CodegenError!void {
    if (!in_slice_context) {
        try genExpr(self, node);
        return;
    }

    const len_expr = if (is_list) "__s.items.len" else "__s.len";

    // Check for negative constant or unary minus
    if (node == .constant and node.constant.value == .int and node.constant.value.int < 0) {
        // Negative constant: -2 becomes max(0, __s.len - 2) to prevent underflow
        const abs_val = if (node.constant.value.int < 0) -node.constant.value.int else node.constant.value.int;
        try self.output.writer(self.allocator).print("if ({s} >= {d}) {s} - {d} else 0", .{ len_expr, abs_val, len_expr, abs_val });
    } else if (node == .unaryop and node.unaryop.op == .USub) {
        // Unary minus: -x becomes saturating subtraction
        try self.output.writer(self.allocator).print("{s} -| ", .{len_expr});
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
            // Check if the object has __getitem__ magic method (custom class support)
            // For now, use heuristic: check if value is a name that matches a class name
            const has_magic_method = blk: {
                if (subscript.value.* == .name) {
                    // Check all registered classes to see if any have __getitem__
                    var class_iter = self.class_registry.iterator();
                    while (class_iter.next()) |entry| {
                        if (self.classHasMethod(entry.key_ptr.*, "__getitem__")) {
                            // Found a class with __getitem__ - we'll generate the call
                            // Note: This is a heuristic - ideally we'd track exact types
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };

            // If we found a __getitem__ method, generate method call instead of direct subscript
            if (has_magic_method and subscript.value.* == .name) {
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, ".__getitem__(");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, ")");
                return;
            }

            // Check if this is a dict, list, or dataframe subscript
            const value_type = try self.type_inferrer.inferExpr(subscript.value.*);
            const is_dict = (value_type == .dict);
            const is_dataframe = (value_type == .dataframe);
            const is_unknown_pyobject = (value_type == .unknown);

            // Check if this variable is tracked as ArrayList (may have .array type but be ArrayList due to mutations)
            const is_tracked_arraylist_early = blk: {
                if (subscript.value.* == .name) {
                    break :blk self.isArrayListVar(subscript.value.name.id);
                }
                break :blk false;
            };

            // A variable is a list if type inference says .list OR if it's tracked as ArrayList
            const is_list = (value_type == .list) or is_tracked_arraylist_early;

            // For unknown PyObject types (like json.loads() result), check if index is string → dict access
            const index_type = try self.type_inferrer.inferExpr(subscript.slice.index.*);
            const is_likely_dict = is_unknown_pyobject and (index_type == .string);

            if (is_dataframe) {
                // DataFrame column access: df['col'] → df.getColumn("col").?
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, ".getColumn(");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, ").?");
            } else if (is_likely_dict) {
                // PyObject dict access: runtime.PyDict.get(obj, key).?
                try self.output.appendSlice(self.allocator, "runtime.PyDict.get(");
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, ").?");
            } else if (is_dict) {
                // Native dict access: dict.get(key).? for raw StringHashMap
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, ".get(");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, ").?");
            } else if (is_list) {
                // Check if this is an array slice variable (not ArrayList)
                const is_array_slice = blk: {
                    if (subscript.value.* == .name) {
                        break :blk self.isArraySliceVar(subscript.value.name.id);
                    }
                    break :blk false;
                };

                // Use the early check for ArrayList tracking
                const is_tracked_arraylist = is_tracked_arraylist_early;

                if (is_array_slice or !is_tracked_arraylist) {
                    // Array slice or generic array: direct indexing without bounds check
                    const needs_cast = (index_type == .int);

                    if (isNegativeConstant(subscript.slice.index.*)) {
                        try self.output.appendSlice(self.allocator, "blk: { const __list = ");
                        try genExpr(self, subscript.value.*);
                        try self.output.appendSlice(self.allocator, "; const __idx = ");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        // No bounds check for arrays (Zig provides safety in debug mode)
                        try self.output.appendSlice(self.allocator, "; break :blk __list[__idx]; }");
                    } else {
                        // Runtime bounds check for positive index (skip for parameters)
                        try self.output.appendSlice(self.allocator, "blk: { const __list = ");
                        try genExpr(self, subscript.value.*);
                        try self.output.appendSlice(self.allocator, "; const __idx = ");
                        if (needs_cast) {
                            try self.output.appendSlice(self.allocator, "@as(usize, @intCast(");
                        }
                        try genExpr(self, subscript.slice.index.*);
                        if (needs_cast) {
                            try self.output.appendSlice(self.allocator, "))");
                        }
                        // No bounds check for arrays (Zig provides safety in debug mode)
                        try self.output.appendSlice(self.allocator, "; break :blk __list[__idx]; }");
                    }
                } else {
                    // ArrayList indexing - use .items with runtime bounds check
                    const needs_cast = (index_type == .int);

                    // Generate: blk: { const __s = list; const __idx = idx; if (__idx >= __s.items.len) return error.IndexError; break :blk __s.items[__idx]; }
                    // Note: We use __s to be consistent with genSliceIndex which expects __s variable name
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __idx = ");
                    if (needs_cast) {
                        try self.output.appendSlice(self.allocator, "@as(usize, @intCast(");
                    }
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Negative index needs special handling
                        try genSliceIndex(self, subscript.slice.index.*, true, true);
                    } else {
                        try genExpr(self, subscript.slice.index.*);
                    }
                    if (needs_cast) {
                        try self.output.appendSlice(self.allocator, "))");
                    }
                    try self.output.appendSlice(self.allocator, "; if (__idx >= __s.items.len) return error.IndexError; break :blk __s.items[__idx]; }");
                }
            } else {
                // Array/slice/string indexing: a[b]
                const is_string = (value_type == .string);

                // For strings: Python s[0] returns "h" (string), not 'h' (char)
                // Zig: s[0] returns u8, need s[0..1] for single-char slice
                if (is_string) {
                    // Generate: s[idx..idx+1] to return []const u8 slice
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Negative index: s[-1..-1+1] = s[-1..0] doesn't work
                        // Need: blk: { const __s = s; const idx = __s.len - 1; break :blk __s[idx..idx+1]; }
                        try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                        try genExpr(self, subscript.value.*);
                        try self.output.appendSlice(self.allocator, "; const __idx = ");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try self.output.appendSlice(self.allocator, "; break :blk __s[__idx..__idx+1]; }");
                    } else {
                        // Positive index: generate idx..idx+1
                        // Need @intCast since Python uses i64 but Zig slicing requires usize
                        try self.output.appendSlice(self.allocator, "blk: { const __idx = @as(usize, @intCast(");
                        try genExpr(self, subscript.slice.index.*);
                        try self.output.appendSlice(self.allocator, ")); break :blk ");
                        try genExpr(self, subscript.value.*);
                        try self.output.appendSlice(self.allocator, "[__idx..__idx+1]; }");
                    }
                } else {
                    // Array/slice (not string): use direct indexing
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Need block to access .len
                        try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                        try genExpr(self, subscript.value.*);
                        try self.output.appendSlice(self.allocator, "; break :blk __s[");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try self.output.appendSlice(self.allocator, "]; }");
                    } else {
                        // Positive index
                        const needs_cast = (index_type == .int);

                        // Check if this is an ArrayList (need .items[idx])
                        const is_arraylist = blk: {
                            if (subscript.value.* == .name) {
                                break :blk self.isArrayListVar(subscript.value.name.id);
                            }
                            break :blk false;
                        };

                        if (is_arraylist) {
                            // ArrayList: use .items with runtime bounds check
                            try self.output.appendSlice(self.allocator, "blk: { const __arr = ");
                            try genExpr(self, subscript.value.*);
                            try self.output.appendSlice(self.allocator, "; const __idx = ");
                            if (needs_cast) {
                                try self.output.appendSlice(self.allocator, "@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.output.appendSlice(self.allocator, "))");
                            }
                            try self.output.appendSlice(self.allocator, "; if (__idx >= __arr.items.len) return error.IndexError; break :blk __arr.items[__idx]; }");
                        } else {
                            // Array/slice: direct indexing (Zig provides safety in debug mode)
                            try genExpr(self, subscript.value.*);
                            try self.output.appendSlice(self.allocator, "[");
                            if (needs_cast) {
                                try self.output.appendSlice(self.allocator, "@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.output.appendSlice(self.allocator, "))");
                            }
                            try self.output.appendSlice(self.allocator, "]");
                        }
                    }
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
                        try genSliceIndex(self, lower.*, true, false);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true, false);
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
                        try genSliceIndex(self, lower.*, true, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.items.len > 0) __s.items.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true, true);
                        try self.output.appendSlice(self.allocator, ")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) @as(i64, @intCast(__s.items.len)) else -1");
                    }

                    try self.output.appendSlice(self.allocator, "; var __result = std.ArrayList(");

                    // Generate element type
                    try elem_type.toZigType(self.allocator, &self.output);

                    try self.output.appendSlice(self.allocator, "){}; if (__step > 0) { var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) { try __result.append(std.heap.page_allocator, __s.items[__i]); } } else if (__step < 0) { var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) { try __result.append(std.heap.page_allocator, __s.items[@intCast(__i)]); } } break :blk try __result.toOwnedSlice(std.heap.page_allocator); }");
                } else {
                    // Unknown type - generate error
                    try self.output.appendSlice(self.allocator, "@compileError(\"Slicing with step requires string or list type\")");
                }
            } else if (needs_len) {
                // Need length for upper bound - use block expression with bounds checking
                const value_type = try self.type_inferrer.inferExpr(subscript.value.*);
                const is_list = (value_type == .list);

                try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, "; const __start = @min(");

                if (slice_range.lower) |lower| {
                    try genSliceIndex(self, lower.*, true, is_list);
                } else {
                    try self.output.appendSlice(self.allocator, "0");
                }

                if (is_list) {
                    try self.output.appendSlice(self.allocator, ", __s.items.len); break :blk if (__start <= __s.items.len) __s.items[__start..__s.items.len] else &[_]i64{}; }");
                } else {
                    try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start <= __s.len) __s[__start..__s.len] else \"\"; }");
                }
            } else {
                // Simple slice with both bounds known - need to check for negative indices
                const value_type = try self.type_inferrer.inferExpr(subscript.value.*);
                const is_list = (value_type == .list);

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

                    if (is_list) {
                        try self.output.appendSlice(self.allocator, "; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genSliceIndex(self, lower.*, true, true);
                        } else {
                            try self.output.appendSlice(self.allocator, "0");
                        }
                        try self.output.appendSlice(self.allocator, ", __s.items.len); const __end = @min(");
                        if (slice_range.upper) |upper| {
                            try genSliceIndex(self, upper.*, true, true);
                        } else {
                            try self.output.appendSlice(self.allocator, "__s.items.len");
                        }
                        try self.output.appendSlice(self.allocator, ", __s.items.len); break :blk if (__start < __end) __s.items[__start..__end] else &[_]i64{}; }");
                    } else {
                        try self.output.appendSlice(self.allocator, "; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genSliceIndex(self, lower.*, true, false);
                        } else {
                            try self.output.appendSlice(self.allocator, "0");
                        }
                        try self.output.appendSlice(self.allocator, ", __s.len); const __end = @min(");
                        if (slice_range.upper) |upper| {
                            try genSliceIndex(self, upper.*, true, false);
                        } else {
                            try self.output.appendSlice(self.allocator, "__s.len");
                        }
                        try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start < __end) __s[__start..__end] else \"\"; }");
                    }
                } else {
                    // No negative indices - but still need bounds checking for Python semantics
                    // Python allows out-of-bounds slices, Zig doesn't
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);

                    if (is_list) {
                        try self.output.appendSlice(self.allocator, "; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genExpr(self, lower.*);
                        } else {
                            try self.output.appendSlice(self.allocator, "0");
                        }
                        try self.output.appendSlice(self.allocator, ", __s.items.len); const __end = @min(");
                        try genExpr(self, slice_range.upper.?.*);
                        try self.output.appendSlice(self.allocator, ", __s.items.len); break :blk if (__start < __end) __s.items[__start..__end] else &[_]i64{}; }");
                    } else {
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
            }
        },
    }
}
