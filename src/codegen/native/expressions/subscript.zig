/// Subscript and slicing code generation
/// Handles array/dict indexing and slicing operations
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const zig_keywords = @import("zig_keywords");

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

/// Check if a node is a single-character string constant
/// Used to convert "a" to 'a' for Counter access when Counter has u8 keys
/// Note: String constants in AST include quotes, so "a" has len=3
fn isSingleCharString(node: ast.Node) bool {
    if (node == .constant and node.constant.value == .string) {
        const s = node.constant.value.string;
        // String includes quotes: "a" has len 3, 'a' has len 3
        return s.len == 3 and (s[0] == '"' or s[0] == '\'');
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
        try self.emitFmt("if ({s} >= {d}) {s} - {d} else 0", .{ len_expr, abs_val, len_expr, abs_val });
    } else if (node == .unaryop and node.unaryop.op == .USub) {
        // Unary minus: -x becomes saturating subtraction
        try self.emitFmt("{s} -| ", .{len_expr});
        try genExpr(self, node.unaryop.operand.*);
    } else {
        // Positive index - use as-is
        try genExpr(self, node);
    }
}

/// Generate array/dict subscript (a[b])
pub fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    // Check if the base expression produces a block expression (e.g., nested subscript)
    // Block expressions cannot be subscripted directly in Zig: blk: {...}[idx] is invalid
    // Need to wrap in another block with temp variable: blk: { const __base = blk: {...}; break :blk __base[idx]; }
    const base_is_block = producesBlockExpression(subscript.value.*);

    if (base_is_block) {
        // Wrap the entire subscript in a block with unique label
        const label_id = self.block_label_counter;
        self.block_label_counter += 1;
        try self.emit(try std.fmt.allocPrint(self.allocator, "sub_{d}: {{ const __base = ", .{label_id}));
        try genExpr(self, subscript.value.*);
        try self.emit(try std.fmt.allocPrint(self.allocator, "; break :sub_{d} ", .{label_id}));

        switch (subscript.slice) {
            .index => {
                // Simple index access on the temp variable
                const index = subscript.slice.index.*;
                const index_type = self.type_inferrer.inferExpr(index) catch .unknown;

                // Check if the index is a string constant - use field access for struct-like access
                // This handles patterns like locale.localeconv()['decimal_point'] -> __base.decimal_point
                if (index == .constant and index.constant.value == .string) {
                    const key_str = index.constant.value.string;
                    // Strip quotes from string literal: "field" -> field
                    const field_name = if (key_str.len >= 2 and (key_str[0] == '"' or key_str[0] == '\''))
                        key_str[1 .. key_str.len - 1]
                    else
                        key_str;
                    try self.emit("__base.");
                    // Escape field name if it's a Zig keyword (e.g., 'const', 'type', etc.)
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                } else {
                    // Check if the base is a tuple type - use .@"N" instead of [N]
                    const base_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
                    const is_tuple = @as(std.meta.Tag(@TypeOf(base_type)), base_type) == .tuple;

                    if (is_tuple and index == .constant and index.constant.value == .int) {
                        // Tuple indexing with constant integer: __base.@"0"
                        try self.output.writer(self.allocator).print("__base.@\"{d}\"", .{index.constant.value.int});
                    } else {
                        const needs_cast = (index_type == .int);

                        try self.emit("__base[");
                        if (needs_cast) {
                            try self.emit("@as(usize, @intCast(");
                        }
                        try genExpr(self, index);
                        if (needs_cast) {
                            try self.emit("))");
                        }
                        try self.emit("]");
                    }
                }
            },
            .slice => |slice| {
                // Slice access on temp variable
                try self.emit("__base[");
                if (slice.lower) |lower| {
                    const needs_cast = blk: {
                        const lt = self.type_inferrer.inferExpr(lower.*) catch .unknown;
                        break :blk (lt == .int);
                    };
                    if (needs_cast) try self.emit("@as(usize, @intCast(");
                    try genExpr(self, lower.*);
                    if (needs_cast) try self.emit("))");
                } else {
                    try self.emit("0");
                }
                try self.emit("..");
                if (slice.upper) |upper| {
                    const needs_cast = blk: {
                        const ut = self.type_inferrer.inferExpr(upper.*) catch .unknown;
                        break :blk (ut == .int);
                    };
                    if (needs_cast) try self.emit("@as(usize, @intCast(");
                    try genExpr(self, upper.*);
                    if (needs_cast) try self.emit("))");
                } else {
                    try self.emit("__base.len");
                }
                try self.emit("]");
            },
        }
        try self.emit("; }");
        return;
    }

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
                try self.emit(".__getitem__(");
                try genExpr(self, subscript.slice.index.*);
                try self.emit(")");
                return;
            }

            // Check if this is a dict, list subscript
            const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

            const is_dict = (value_type == .dict);
            const is_counter = (value_type == .counter);
            const is_unknown_pyobject = (value_type == .unknown);

            // Check if this variable is tracked as ArrayList (may have .array type but be ArrayList due to mutations)
            const is_tracked_arraylist_early = blk: {
                if (subscript.value.* == .name) {
                    break :blk self.isArrayListVar(subscript.value.name.id);
                }
                break :blk false;
            };

            // Check if this variable is tracked as a dict
            const is_tracked_dict = blk: {
                if (subscript.value.* == .name) {
                    break :blk self.isDictVar(subscript.value.name.id);
                }
                break :blk false;
            };

            // A variable is a list if type inference says .list OR if it's tracked as ArrayList
            const is_list = (value_type == .list) or is_tracked_arraylist_early;

            // For unknown PyObject types (like json.loads() result), check if index is string → dict access
            const index_type = try self.type_inferrer.inferExpr(subscript.slice.index.*);
            const is_likely_dict = is_unknown_pyobject and (index_type == .string);

            // Check if this is a FeatureMacros access (feature_macros['key'])
            const is_feature_macros = blk: {
                if (subscript.value.* == .name) {
                    break :blk std.mem.eql(u8, subscript.value.name.id, "feature_macros");
                }
                break :blk false;
            };

            if (is_feature_macros) {
                // FeatureMacros struct access
                // Use .index() for comptime keys, .get() for runtime keys
                const is_comptime_key = subscript.slice.index.* == .constant;
                try genExpr(self, subscript.value.*);
                if (is_comptime_key) {
                    try self.emit(".index(");
                } else {
                    try self.emit(".get(");
                }
                try genExpr(self, subscript.slice.index.*);
                try self.emit(")");
            } else if (is_likely_dict) {
                // PyObject dict access: runtime.PyDict.get(obj, key).?
                try self.emit("runtime.PyDict.get(");
                try genExpr(self, subscript.value.*);
                try self.emit(", ");
                try genExpr(self, subscript.slice.index.*);
                try self.emit(").?");
            } else if (is_unknown_pyobject and (index_type == .int)) {
                // PyObject list access: runtime.PyList.get(obj, index)
                try self.emit("(try runtime.PyList.get(");
                try genExpr(self, subscript.value.*);
                try self.emit(", ");
                try genExpr(self, subscript.slice.index.*);
                try self.emit("))");
            } else if (is_dict or is_counter or is_tracked_dict) {
                // Native dict/Counter access: dict.get(key).? for raw StringHashMap
                // Counter returns 0 for missing keys in Python
                try genExpr(self, subscript.value.*);
                try self.emit(".get(");

                // For Counter created from string, keys are u8 (chars)
                // If index is single-char string like "a", convert to 'a'
                const is_single_char_key = is_counter and isSingleCharString(subscript.slice.index.*);
                if (is_single_char_key) {
                    // Convert "a" to 'a' for u8-keyed Counter
                    // String includes quotes, so "a" -> str[1] is 'a'
                    const str = subscript.slice.index.constant.value.string;
                    try self.output.writer(self.allocator).print("'{c}'", .{str[1]});
                } else {
                    try genExpr(self, subscript.slice.index.*);
                }

                if (is_counter) {
                    // Counter returns 0 for missing keys, not None
                    try self.emit(") orelse 0");
                } else {
                    try self.emit(").?");
                }
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
                    // Array slice or generic array: use runtime check for ArrayList vs array
                    // This handles cases where type inference is stale (e.g., after list(tuple))
                    const needs_cast = (index_type == .int);
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;

                    try self.emitFmt("idx_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __idx = ");
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                    } else {
                        if (needs_cast) {
                            try self.emit("@as(usize, @intCast(");
                        }
                        try genExpr(self, subscript.slice.index.*);
                        if (needs_cast) {
                            try self.emit("))");
                        }
                    }
                    // Runtime check: if __s has .items field, use it; otherwise direct index
                    try self.emitFmt("; break :idx_{d} if (@hasField(@TypeOf(__s), \"items\")) __s.items[__idx] else __s[__idx]; }}", .{label_id});
                } else {
                    // ArrayList indexing - use .items with runtime bounds check
                    const needs_cast = (index_type == .int);

                    // Generate: idx_N: { const __s = list; const __idx = idx; if (__idx >= __s.items.len) return error.IndexError; break :idx_N __s.items[__idx]; }
                    // Note: We use __s to be consistent with genSliceIndex which expects __s variable name
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("idx_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __idx = ");
                    if (needs_cast) {
                        try self.emit("@as(usize, @intCast(");
                    }
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Negative index needs special handling
                        try genSliceIndex(self, subscript.slice.index.*, true, true);
                    } else {
                        try genExpr(self, subscript.slice.index.*);
                    }
                    if (needs_cast) {
                        try self.emit("))");
                    }
                    try self.emitFmt("; if (__idx >= __s.items.len) return error.IndexError; break :idx_{d} __s.items[__idx]; }}", .{label_id});
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
                        // Need: str_N: { const __s = s; const idx = __s.len - 1; break :str_N __s[idx..idx+1]; }
                        const label_id = self.block_label_counter;
                        self.block_label_counter += 1;
                        try self.emitFmt("str_{d}: {{ const __s = ", .{label_id});
                        try genExpr(self, subscript.value.*);
                        try self.emit("; const __idx = ");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try self.emitFmt("; break :str_{d} __s[__idx..__idx+1]; }}", .{label_id});
                    } else {
                        // Positive index: generate idx..idx+1
                        // Need @intCast since Python uses i64 but Zig slicing requires usize
                        const label_id = self.block_label_counter;
                        self.block_label_counter += 1;
                        try self.emitFmt("str_{d}: {{ const __idx = @as(usize, @intCast(", .{label_id});
                        try genExpr(self, subscript.slice.index.*);
                        try self.emitFmt(")); break :str_{d} ", .{label_id});
                        try genExpr(self, subscript.value.*);
                        try self.emit("[__idx..__idx+1]; }");
                    }
                } else {
                    // Array/slice (not string): use direct indexing
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Need block to access .len
                        const label_id = self.block_label_counter;
                        self.block_label_counter += 1;
                        try self.emitFmt("arr_{d}: {{ const __s = ", .{label_id});
                        try genExpr(self, subscript.value.*);
                        try self.emitFmt("; break :arr_{d} __s[", .{label_id});
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try self.emit("]; }");
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
                            const label_id = self.block_label_counter;
                            self.block_label_counter += 1;
                            try self.emitFmt("arr_{d}: {{ const __arr = ", .{label_id});
                            try genExpr(self, subscript.value.*);
                            try self.emit("; const __idx = ");
                            if (needs_cast) {
                                try self.emit("@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.emit("))");
                            }
                            try self.emitFmt("; if (__idx >= __arr.items.len) return error.IndexError; break :arr_{d} __arr.items[__idx]; }}", .{label_id});
                        } else {
                            // Array/slice: direct indexing (Zig provides safety in debug mode)
                            try genExpr(self, subscript.value.*);
                            try self.emit("[");
                            if (needs_cast) {
                                try self.emit("@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.emit("))");
                            }
                            try self.emit("]");
                        }
                    }
                }
            }
        },
        .slice => |slice_range| {
            // Slicing: a[start:end] or a[start:end:step]
            const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

            const has_step = slice_range.step != null;
            const needs_len = slice_range.upper == null;

            if (has_step) {
                // With step: use slice with step calculation
                if (value_type == .string) {
                    // String slicing with step (supports negative step for reverse iteration)
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit("; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true, false);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.emit("if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.emit("; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.emit("@intCast(");
                        try genSliceIndex(self, upper.*, true, false);
                        try self.emit(")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.emit("if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.emitFmt("; var __result = std.ArrayList(u8){{}}; if (__step > 0) {{ var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) {{ try __result.append(__global_allocator, __s[__i]); }} }} else if (__step < 0) {{ var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) {{ try __result.append(__global_allocator, __s[@intCast(__i)]); }} }} break :slice_{d} try __result.toOwnedSlice(__global_allocator); }}", .{label_id});
                } else if (value_type == .list) {
                    // List slicing with step (supports negative step for reverse iteration)
                    // Get element type to generate proper ArrayList
                    const elem_type = value_type.list.*;

                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit("; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.emit("if (__step > 0) 0 else if (__s.items.len > 0) __s.items.len - 1 else 0");
                    }

                    try self.emit("; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.emit("@intCast(");
                        try genSliceIndex(self, upper.*, true, true);
                        try self.emit(")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.emit("if (__step > 0) @as(i64, @intCast(__s.items.len)) else -1");
                    }

                    try self.emit("; var __result = std.ArrayList(");

                    // Generate element type
                    try elem_type.toZigType(self.allocator, &self.output);

                    try self.emitFmt("){{}}; if (__step > 0) {{ var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) {{ try __result.append(__global_allocator, __s.items[__i]); }} }} else if (__step < 0) {{ var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) {{ try __result.append(__global_allocator, __s.items[@intCast(__i)]); }} }} break :slice_{d} try __result.toOwnedSlice(__global_allocator); }}", .{label_id});
                } else if (value_type == .tuple) {
                    // Tuple slicing with step - convert to runtime array slice
                    // Python tuples are immutable but we can slice them
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit("; const __len = ");
                    // Get tuple length using inline for
                    try self.emit("comptime blk: { var count: usize = 0; inline for (std.meta.fields(@TypeOf(__s))) |_| count += 1; break :blk count; }");
                    try self.emit("; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try self.emit("@min(@as(usize, @intCast(");
                        try genExpr(self, lower.*);
                        try self.emit(")), __len)");
                    } else {
                        try self.emit("if (__step > 0) 0 else if (__len > 0) __len - 1 else 0");
                    }

                    try self.emit("; const __end: usize = ");

                    if (slice_range.upper) |upper| {
                        try self.emit("@min(@as(usize, @intCast(");
                        try genExpr(self, upper.*);
                        try self.emit(")), __len)");
                    } else {
                        try self.emit("if (__step > 0) __len else 0");
                    }

                    // For tuple step slicing, we need runtime array conversion
                    // This is a simplified version that works for common cases
                    try self.emitFmt("; var __result = std.ArrayList(@TypeOf(__s.@\"0\")){{}}; var __i: i64 = if (__step > 0) @intCast(__start) else @intCast(__start); const __end_i64: i64 = if (__step > 0) @intCast(__end) else -1; while (if (__step > 0) __i < __end_i64 else __i > __end_i64) : (__i += __step) {{ const __idx: usize = @intCast(__i); inline for (std.meta.fields(@TypeOf(__s)), 0..) |f, fi| {{ if (fi == __idx) try __result.append(__global_allocator, @field(__s, f.name)); }} }} break :slice_{d} __result; }}", .{label_id});
                } else {
                    // Unknown type - treat as generic slice (like raw []T)
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.emit("; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit("; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try self.emit("@min(@as(usize, @intCast(");
                        try genExpr(self, lower.*);
                        try self.emit(")), __s.len)");
                    } else {
                        try self.emit("if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.emit("; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.emit("@intCast(@min(@as(usize, @intCast(");
                        try genExpr(self, upper.*);
                        try self.emit(")), __s.len))");
                    } else {
                        try self.emit("if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.emitFmt("; var __result = std.ArrayList(@TypeOf(__s[0])){{}}; if (__step > 0) {{ var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) {{ try __result.append(__global_allocator, __s[__i]); }} }} else if (__step < 0) {{ var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) {{ try __result.append(__global_allocator, __s[@intCast(__i)]); }} }} break :slice_{d} try __result.toOwnedSlice(__global_allocator); }}", .{label_id});
                }
            } else if (needs_len) {
                // Need length for upper bound - use block expression with bounds checking
                const is_list = (value_type == .list);

                const label_id = self.block_label_counter;
                self.block_label_counter += 1;
                try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                try genExpr(self, subscript.value.*);
                try self.emit("; const __start = @min(");

                if (slice_range.lower) |lower| {
                    try genSliceIndex(self, lower.*, true, is_list);
                } else {
                    try self.emit("0");
                }

                if (is_list) {
                    // Get element type for empty array fallback
                    try self.emitFmt(", __s.items.len); break :slice_{d} if (__start <= __s.items.len) __s.items[__start..__s.items.len] else &[_]", .{label_id});
                    const elem_type = value_type.list.*;
                    try elem_type.toZigType(self.allocator, &self.output);
                    try self.emit("{}; }");
                } else {
                    try self.emitFmt(", __s.len); break :slice_{d} if (__start <= __s.len) __s[__start..__s.len] else \"\"; }}", .{label_id});
                }
            } else {
                // Simple slice with both bounds known - need to check for negative indices
                const is_list = (value_type == .list);

                const has_negative = check_neg: {
                    if (slice_range.lower) |lower| {
                        if (isNegativeConstant(lower.*)) break :check_neg true;
                    }
                    if (slice_range.upper) |upper| {
                        if (isNegativeConstant(upper.*)) break :check_neg true;
                    }
                    break :check_neg false;
                };

                if (has_negative) {
                    // Need block expression to handle negative indices with bounds checking
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);

                    if (is_list) {
                        try self.emit("; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genSliceIndex(self, lower.*, true, true);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.items.len); const __end = @min(");
                        if (slice_range.upper) |upper| {
                            try genSliceIndex(self, upper.*, true, true);
                        } else {
                            try self.emit("__s.items.len");
                        }
                        try self.emitFmt(", __s.items.len); break :slice_{d} if (__start < __end) __s.items[__start..__end] else &[_]i64{{}}; }}", .{label_id});
                    } else {
                        try self.emit("; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genSliceIndex(self, lower.*, true, false);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.len); const __end = @min(");
                        if (slice_range.upper) |upper| {
                            try genSliceIndex(self, upper.*, true, false);
                        } else {
                            try self.emit("__s.len");
                        }
                        try self.emitFmt(", __s.len); break :slice_{d} if (__start < __end) __s[__start..__end] else \"\"; }}", .{label_id});
                    }
                } else {
                    // No negative indices - but still need bounds checking for Python semantics
                    // Python allows out-of-bounds slices, Zig doesn't
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.emitFmt("slice_{d}: {{ const __s = ", .{label_id});
                    try genExpr(self, subscript.value.*);

                    if (is_list) {
                        try self.emit("; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genExpr(self, lower.*);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.items.len); const __end = @min(");
                        try genExpr(self, slice_range.upper.?.*);
                        try self.emitFmt(", __s.items.len); break :slice_{d} if (__start < __end) __s.items[__start..__end] else &[_]i64{{}}; }}", .{label_id});
                    } else {
                        try self.emit("; const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genExpr(self, lower.*);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.len); const __end = @min(");
                        try genExpr(self, slice_range.upper.?.*);
                        try self.emitFmt(", __s.len); break :slice_{d} if (__start < __end) __s[__start..__end] else \"\"; }}", .{label_id});
                    }
                }
            }
        },
    }
}

/// Generate a subscript expression without block wrapping - for use as assignment LHS
/// This recursively generates nested subscripts without labeled blocks, producing valid
/// lvalues like `arr[0][1][2]` instead of `sub_N: { ... }[1][2]`
pub fn genSubscriptLHS(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    // Recursively generate base without block wrapping
    if (subscript.value.* == .subscript) {
        // Nested subscript - recurse
        try genSubscriptLHS(self, subscript.value.subscript);
    } else {
        // Base case - just emit the expression
        try genExpr(self, subscript.value.*);
    }

    // Now emit the index access
    switch (subscript.slice) {
        .index => |index| {
            // Determine if we need .items for list access
            const container_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
            if (container_type == .list) {
                try self.emit(".items");
            }
            try self.emit("[@as(usize, @intCast(");
            try genExpr(self, index.*);
            try self.emit("))]");
        },
        .slice => {
            // Slice access as LHS is complex - for now just generate error
            // Slice assignment should be handled separately in assign.zig
            try self.emit("@compileError(\"Slice LHS not supported in this context\")");
        },
    }
}
