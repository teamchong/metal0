/// Subscript and slicing code generation
/// Handles array/dict indexing and slicing operations
///
/// MIGRATION STATUS: Using ZigBuilder for structured code generation
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Emits using emitZigValue() for type-safe output
/// - Uses nextNameId() for unique block labels
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const zig_keywords = @import("utils.zig_keywords");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

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
        var em = self.exprEmitter();
        var block = try em.labeledBlock("sub", "__base", subscript.value.*);
        try block.startBreak();

        switch (subscript.slice) {
            .index => {
                // Simple index access on the temp variable
                const index = subscript.slice.index.*;
                const index_type = self.type_inferrer.inferExpr(index) catch .unknown;

                // Check if the index is a string constant - use field access for struct-like access
                // This handles patterns like locale.localeconv()['decimal_point'] -> __base.decimal_point
                // But only if the string is a valid identifier (no spaces, special chars)
                if (index == .constant and index.constant.value == .string) {
                    const key_str = index.constant.value.string;
                    // Strip quotes from string literal: "field" -> field
                    const field_name = if (key_str.len >= 2 and (key_str[0] == '"' or key_str[0] == '\''))
                        key_str[1 .. key_str.len - 1]
                    else
                        key_str;
                    // Check if field_name is a valid Zig identifier (no spaces, special chars)
                    // Must NOT start with a digit - "1" is not a valid identifier even though it has no special chars
                    const is_valid_ident = blk: {
                        if (field_name.len == 0) break :blk false;
                        // First char cannot be a digit
                        const first = field_name[0];
                        if (first >= '0' and first <= '9') break :blk false;
                        for (field_name) |c| {
                            // Valid identifier chars: a-z, A-Z, 0-9, _ (but can't start with digit)
                            if (c == ' ' or c == '-' or c == '.' or c == '[' or c == ']' or
                                c == '(' or c == ')' or c == '{' or c == '}' or c == '/' or
                                c == '\\' or c == ':' or c == ';' or c == ',' or c == '!' or
                                c == '@' or c == '#' or c == '$' or c == '%' or c == '^' or
                                c == '&' or c == '*' or c == '+' or c == '=' or c == '|' or
                                c == '~' or c == '`' or c == '\'' or c == '"' or c == '<' or
                                c == '>' or c == '?' or c == '\n' or c == '\r' or c == '\t')
                            {
                                break :blk false;
                            }
                        }
                        break :blk true;
                    };
                    if (is_valid_ident) {
                        try self.emit("__base.");
                        // Escape field name if it's a Zig keyword (e.g., 'const', 'type', etc.)
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    } else {
                        // Invalid identifier (has spaces, etc.) - use .get() for dict access
                        try self.emit("__base.get(\"");
                        try self.emit(field_name);
                        try self.emit("\").?");
                    }
                } else {
                    // Check if the base is a tuple type - use .@"N" instead of [N]
                    const base_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
                    const base_tag = @as(std.meta.Tag(@TypeOf(base_type)), base_type);
                    const is_tuple = container_traits.isTuple(base_type);
                    const is_list = container_traits.isList(base_type);
                    const is_pyvalue = base_tag == .pyvalue;
                    const is_unknown = type_traits.isUnknown(base_type);
                    const is_bytes = string_traits.isBytes(base_type);
                    const index_tag = @as(std.meta.Tag(@TypeOf(index_type)), index_type);
                    const is_int_index = (index_tag == .int) or (index_tag == .usize);

                    if (is_tuple and index == .constant and index.constant.value == .int) {
                        // Tuple indexing with constant integer: __base.@"0"
                        try self.output.writer(self.allocator).print("__base.@\"{d}\"", .{index.constant.value.int});
                    } else if (is_bytes and is_int_index) {
                        // Bytes indexing: use .get() method
                        try self.emit("__base.get(@as(usize, @intCast(");
                        try genExpr(self, index);
                        try self.emit(")))");
                    } else if (is_list and is_int_index) {
                        // List (ArrayList) indexing: use .items[idx]
                        try self.emit("__base.items[@as(usize, @intCast(");
                        try genExpr(self, index);
                        try self.emit("))]");
                    } else if ((is_unknown or is_pyvalue) and is_int_index) {
                        // Unknown type or PyValue with int index - use PyValue.pyAt() method
                        // This handles PyValue containing tuple/list uniformly
                        try self.emit("if (@TypeOf(__base) == runtime.PyValue) __base.pyAt(@as(usize, @intCast(");
                        try genExpr(self, index);
                        try self.emit("))) else __base[@as(usize, @intCast(");
                        try genExpr(self, index);
                        try self.emit("))]");
                    } else {
                        const needs_cast = type_traits.isIntegral(index_type);

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
                // Check if base is bytes type - use .sliceRange() method
                const base_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
                const is_bytes = string_traits.isBytes(base_type);

                if (is_bytes) {
                    // Bytes slicing: __base.sliceRange(start, end)
                    try self.emit("__base.sliceRange(");
                    if (slice.lower) |lower| {
                        try self.emit("@as(usize, @intCast(");
                        try genExpr(self, lower.*);
                        try self.emit("))");
                    } else {
                        try self.emit("0");
                    }
                    try self.emit(", ");
                    if (slice.upper) |upper| {
                        try self.emit("@as(usize, @intCast(");
                        try genExpr(self, upper.*);
                        try self.emit("))");
                    } else {
                        try self.emit("__base.len()");
                    }
                    try self.emit(")");
                } else {
                    try self.emit("__base[");
                    if (slice.lower) |lower| {
                        const needs_cast = blk: {
                            const lt = self.type_inferrer.inferExpr(lower.*) catch .unknown;
                            break :blk type_traits.isIntegral(lt);
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
                            break :blk type_traits.isIntegral(ut);
                        };
                        if (needs_cast) try self.emit("@as(usize, @intCast(");
                        try genExpr(self, upper.*);
                        if (needs_cast) try self.emit("))");
                    } else {
                        try self.emit("__base.len");
                    }
                    try self.emit("]");
                }
            },
        }
        try block.close();
        return;
    }

    switch (subscript.slice) {
        .index => {
            // Check for array.array type - use __getitem__ method directly
            // The inline struct has items: ArrayListUnmanaged which needs .items.items access
            // It's simpler to use the __getitem__ method which handles this correctly
            const subscript_value_type = try self.type_inferrer.inferExpr(subscript.value.*);
            if (type_traits.isClassInstance(subscript_value_type) and
                std.mem.eql(u8, subscript_value_type.class_instance, "array.array"))
            {
                try genExpr(self, subscript.value.*);
                try self.emit(".__getitem__(");
                // Cast index to usize for __getitem__ method
                try self.emit("@as(usize, @intCast(");
                try genExpr(self, subscript.slice.index.*);
                try self.emit(")))");
                return;
            }

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

            const is_dict = container_traits.isDict(value_type);
            const is_counter = (value_type == .counter);
            // Two-Flow: Include .pyvalue for uncertain container subscript routing
            const is_unknown_pyobject = type_traits.isUnknown(value_type) or value_type == .pyvalue;

            // Check if value type is a slice (e.g., from [0] * n with runtime n)
            const is_slice = (value_type == .slice);

            // Check if this variable is tracked as ArrayList (may have .array type but be ArrayList due to mutations)
            // Note: Skip if type is .slice - slices use direct indexing, not .items
            const is_tracked_arraylist_early = blk: {
                if (is_slice) break :blk false; // Slices are not ArrayLists
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
            const is_list = container_traits.isList(value_type) or is_tracked_arraylist_early;

            // For unknown PyObject types (like json.loads() result), check if index is string → dict access
            const index_type = try self.type_inferrer.inferExpr(subscript.slice.index.*);
            const is_likely_dict = is_unknown_pyobject and string_traits.isString(index_type);

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
            } else if (is_unknown_pyobject and type_traits.isIntegral(index_type)) {
                // Unknown container with integer index - use container_dispatch which handles
                // both Zig tuples/structs AND ArrayLists at comptime via type inspection
                // This prevents type errors when anytype params receive tuples vs lists
                try self.emit("runtime.container_dispatch.getAt(@TypeOf(");
                try genExpr(self, subscript.value.*);
                try self.emit("), ");
                try genExpr(self, subscript.value.*);
                try self.emit(", @as(usize, @intCast(");
                try genExpr(self, subscript.slice.index.*);
                try self.emit(")))");
            } else if (is_dict or is_counter or is_tracked_dict) {
                // Native dict/Counter access: dict.get(key).? for raw StringHashMap
                // Counter returns 0 for missing keys in Python
                try genExpr(self, subscript.value.*);
                try self.emit(".get(");

                // Check if index is a PyValue - need to convert to string
                const key_type = try self.inferExprScoped(subscript.slice.index.*);

                // For Counter created from string, keys are u8 (chars)
                // If index is single-char string like "a", convert to 'a'
                const is_single_char_key = is_counter and isSingleCharString(subscript.slice.index.*);
                if (is_single_char_key) {
                    // Convert "a" to 'a' for u8-keyed Counter
                    // String includes quotes, so "a" -> str[1] is 'a'
                    const str = subscript.slice.index.constant.value.string;
                    try self.output.writer(self.allocator).print("'{c}'", .{str[1]});
                } else if (key_type == .pyvalue) {
                    // PyValue key - convert to string
                    try genExpr(self, subscript.slice.index.*);
                    try self.emit(".asString()");
                } else if (key_type == .unknown) {
                    // Unknown type - use runtime dispatch to handle PyValue
                    // Generate: pyval_key_blk: { const __k = key; break :pyval_key_blk if (@TypeOf(__k) == runtime.PyValue) __k.asString() else __k; }
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("pyval_key", "__k", subscript.slice.index.*);
                    try blk.breakWith("if (@TypeOf(__k) == runtime.PyValue) __k.asString() else __k");
                    try blk.close();
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
                    const needs_cast = type_traits.isIntegral(index_type);
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("idx", "__s", subscript.value.*);
                    try blk.emit("const __idx = ");
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
                    try blk.emit("; ");
                    try blk.breakWith("if (@hasField(@TypeOf(__s), \"items\")) __s.items[__idx] else __s[__idx]");
                    try blk.close();
                } else {
                    // ArrayList indexing - use .items with runtime bounds check
                    const needs_cast = type_traits.isIntegral(index_type);

                    // Generate: idx_N: { const __s = list; const __idx = idx; if (__idx >= __s.items.len) return error.IndexError; break :idx_N __s.items[__idx]; }
                    // Note: We use __s to be consistent with genSliceIndex which expects __s variable name
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("idx", "__s", subscript.value.*);
                    try blk.emit("const __idx = ");
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
                    try blk.emit("; if (__idx >= __s.items.len) return error.IndexError; ");
                    try blk.breakWith("__s.items[__idx]");
                    try blk.close();
                }
            } else if (string_traits.isBytes(value_type)) {
                // Bytes indexing: PyBytes uses .get() method, returns u8
                const needs_cast = type_traits.isIntegral(index_type);
                try genExpr(self, subscript.value.*);
                try self.emit(".get(");
                if (needs_cast) {
                    try self.emit("@as(usize, @intCast(");
                }
                try genExpr(self, subscript.slice.index.*);
                if (needs_cast) {
                    try self.emit("))");
                }
                try self.emit(")");
            } else {
                // Array/slice/string indexing: a[b]
                const is_string = string_traits.isString(value_type);

                // For strings: Python s[0] returns "h" (string), not 'h' (char)
                // Zig: s[0] returns u8, need s[0..1] for single-char slice
                if (is_string) {
                    // Generate: s[idx..idx+1] to return []const u8 slice
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Negative index: s[-1..-1+1] = s[-1..0] doesn't work
                        // Need: str_N: { const __s = s; const idx = __s.len - 1; break :str_N __s[idx..idx+1]; }
                        var em = self.exprEmitter();
                        var blk = try em.labeledBlock("str", "__s", subscript.value.*);
                        try blk.emit("const __idx = ");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try blk.emit("; ");
                        try blk.breakWith("__s[__idx..__idx+1]");
                        try blk.close();
                    } else {
                        // Positive index: generate idx..idx+1
                        // Need @intCast since Python uses i64 but Zig slicing requires usize
                        var em = self.exprEmitter();
                        var blk = try em.labeledBlockRaw("str");
                        try blk.emit("const __idx = @as(usize, @intCast(");
                        try genExpr(self, subscript.slice.index.*);
                        try blk.emit(")); ");
                        try blk.startBreak();
                        try genExpr(self, subscript.value.*);
                        try self.emit("[__idx..__idx+1]");
                        try blk.close();
                    }
                } else {
                    // Array/slice (not string): use direct indexing
                    if (isNegativeConstant(subscript.slice.index.*)) {
                        // Need block to access .len
                        var em = self.exprEmitter();
                        var blk = try em.labeledBlock("arr", "__s", subscript.value.*);
                        try blk.startBreak();
                        try self.emit("__s[");
                        try genSliceIndex(self, subscript.slice.index.*, true, false);
                        try self.emit("]");
                        try blk.close();
                    } else {
                        // Positive index
                        const needs_cast = type_traits.isIntegral(index_type);

                        // Get value type to check for slice
                        const val_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
                        const val_is_slice = (val_type == .slice);

                        // Check if this is an ArrayList (need .items[idx])
                        // Note: Skip if type is .slice - slices use direct indexing
                        const is_arraylist = blk: {
                            if (val_is_slice) break :blk false; // Slices are not ArrayLists
                            // Also check if type is .list - which means ArrayList in Zig
                            if (container_traits.isList(val_type)) break :blk true; // ArrayList confirmed by type inference
                            if (subscript.value.* == .name) {
                                break :blk self.isArrayListVar(subscript.value.name.id);
                            }
                            break :blk false;
                        };

                        if (is_arraylist) {
                            // ArrayList: use .items with runtime bounds check
                            var em = self.exprEmitter();
                            var blk = try em.labeledBlock("arr", "__arr", subscript.value.*);
                            try blk.emit("const __idx = ");
                            if (needs_cast) {
                                try self.emit("@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.emit("))");
                            }
                            try blk.emit("; if (__idx >= __arr.items.len) return error.IndexError; ");
                            try blk.breakWith("__arr.items[__idx]");
                            try blk.close();
                        } else {
                            // Unknown type: use runtime @hasField check to handle ArrayList vs array
                            var em = self.exprEmitter();
                            var blk = try em.labeledBlock("arr", "__s", subscript.value.*);
                            try blk.emit("const __idx = ");
                            if (needs_cast) {
                                try self.emit("@as(usize, @intCast(");
                            }
                            try genExpr(self, subscript.slice.index.*);
                            if (needs_cast) {
                                try self.emit("))");
                            }
                            try blk.emit("; ");
                            try blk.breakWith("if (@hasField(@TypeOf(__s), \"items\")) __s.items[__idx] else __s[__idx]");
                            try blk.close();
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

            // Handle bytes slicing: PyBytes uses .sliceRange() method
            if (string_traits.isBytes(value_type)) {
                var em = self.exprEmitter();
                var blk = try em.labeledBlock("slice", "__s", subscript.value.*);
                try blk.emit("const __start: usize = ");

                if (slice_range.lower) |lower| {
                    try self.emit("@as(usize, @intCast(");
                    try genExpr(self, lower.*);
                    try self.emit("))");
                } else {
                    try self.emit("0");
                }

                try blk.emit("; const __end: usize = ");

                if (slice_range.upper) |upper| {
                    try self.emit("@as(usize, @intCast(");
                    try genExpr(self, upper.*);
                    try self.emit("))");
                } else {
                    try self.emit("__s.len()");
                }

                try blk.emit("; ");
                try blk.breakWith("__s.sliceRange(__start, __end)");
                try blk.close();
                return;
            }

            if (has_step) {
                // With step: use runtime slice helpers (fixes comptime explosion)
                // Runtime helpers handle: negative indices, step=0 error, bounds clamping
                if (string_traits.isString(value_type)) {
                    // String slicing with step - use runtime helper
                    try self.emit("try runtime.slice_ops.stringSliceWithStep(__global_allocator, ");
                    try genExpr(self, subscript.value.*);
                    try self.emit(", ");

                    // Start (null = default based on step direction)
                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // End (null = default based on step direction)
                    if (slice_range.upper) |upper| {
                        try genExpr(self, upper.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // Step
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit(")");
                } else if (container_traits.isList(value_type)) {
                    // List slicing with step - use runtime helper
                    // Access .items from SliceResult to get raw slice for comparison compatibility
                    const elem_type = value_type.list.*;

                    try self.emit("(try runtime.slice_ops.sliceWithStep(");
                    // Element type as comptime parameter
                    try elem_type.toZigType(self.allocator, &self.output);
                    try self.emit(", __global_allocator, ");
                    try genExpr(self, subscript.value.*);
                    try self.emit(".items, ");

                    // Start
                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // End
                    if (slice_range.upper) |upper| {
                        try genExpr(self, upper.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // Step
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit(")).items");
                } else if (container_traits.isTuple(value_type)) {
                    // Tuple slicing with step - convert tuple to array then use runtime helper
                    // This avoids the exponential comptime from inline for inside loop
                    // Access .items from SliceResult
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("slice", "__t", subscript.value.*);
                    // Convert tuple to array using inline for (done ONCE, not per iteration)
                    try blk.emit("const __arr = comptime blk: { const fields = std.meta.fields(@TypeOf(__t)); var arr: [fields.len]@TypeOf(__t.@\"0\") = undefined; inline for (fields, 0..) |f, i| { arr[i] = @field(__t, f.name); } break :blk arr; }; ");
                    try blk.startBreak();
                    try self.emit("(try runtime.slice_ops.sliceWithStep(@TypeOf(__arr[0]), __global_allocator, &__arr, ");

                    // Start
                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // End
                    if (slice_range.upper) |upper| {
                        try genExpr(self, upper.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // Step
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit(")).items");
                    try blk.close();
                } else if (value_type == .pyvalue) {
                    // Two-Flow: PyValue container slicing with step
                    // Extract list/tuple items from PyValue, slice, return as slice of PyValue
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("pyslice", "__pv", subscript.value.*);
                    // Extract items from PyValue (list or tuple)
                    try blk.emit("const __items = switch (__pv) { .list => |l| l.items, .tuple => |t| t, else => &[_]runtime.PyValue{} }; ");
                    try blk.startBreak();
                    try self.emit("(try runtime.slice_ops.sliceWithStep(runtime.PyValue, __global_allocator, __items, ");

                    // Start
                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // End
                    if (slice_range.upper) |upper| {
                        try genExpr(self, upper.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // Step
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit(")).items");
                    try blk.close();
                } else {
                    // Unknown type - use runtime helper with generic element type detection
                    // Access .items from SliceResult
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("slice", "__s", subscript.value.*);
                    // Use container_dispatch helper - avoids inline @hasField monomorphization
                    try blk.emit("const __items = runtime.container_dispatch.getSlice(@TypeOf(__s), __s); ");
                    try blk.startBreak();
                    try self.emit("(try runtime.slice_ops.sliceWithStep(@TypeOf(__items[0]), __global_allocator, __items, ");

                    // Start
                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // End
                    if (slice_range.upper) |upper| {
                        try genExpr(self, upper.*);
                    } else {
                        try self.emit("null");
                    }
                    try self.emit(", ");

                    // Step
                    try genExpr(self, slice_range.step.?.*);
                    try self.emit(")).items");
                    try blk.close();
                }
            } else if (needs_len) {
                // Need length for upper bound - use block expression with bounds checking
                const is_list = container_traits.isList(value_type);

                var em = self.exprEmitter();
                var blk = try em.labeledBlock("slice", "__s", subscript.value.*);
                try blk.emit("const __start = @min(");

                if (slice_range.lower) |lower| {
                    try genSliceIndex(self, lower.*, true, is_list);
                } else {
                    try self.emit("0");
                }

                if (is_list) {
                    // Get element type for empty array fallback
                    try blk.emit(", __s.items.len); ");
                    try blk.startBreak();
                    try self.emit("if (__start <= __s.items.len) __s.items[__start..__s.items.len] else &[_]");
                    const elem_type = value_type.list.*;
                    try elem_type.toZigType(self.allocator, &self.output);
                    try self.emit("{}");
                    try blk.close();
                } else {
                    try blk.emit(", __s.len); ");
                    try blk.breakWith("if (__start <= __s.len) __s[__start..__s.len] else \"\"");
                    try blk.close();
                }
            } else {
                // Simple slice with both bounds known - need to check for negative indices
                const is_list = container_traits.isList(value_type);

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
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("slice", "__s", subscript.value.*);

                    if (is_list) {
                        try blk.emit("const __start = @min(");
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
                        try blk.emit(", __s.items.len); ");
                        try blk.breakWith("if (__start < __end) __s.items[__start..__end] else __s.items[0..0]");
                        try blk.close();
                    } else {
                        try blk.emit("const __start = @min(");
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
                        try blk.emit(", __s.len); ");
                        try blk.breakWith("if (__start < __end) __s[__start..__end] else \"\"");
                        try blk.close();
                    }
                } else {
                    // No negative indices - but still need bounds checking for Python semantics
                    // Python allows out-of-bounds slices, Zig doesn't
                    var em = self.exprEmitter();
                    var blk = try em.labeledBlock("slice", "__s", subscript.value.*);

                    if (is_list) {
                        try blk.emit("const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genExpr(self, lower.*);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.items.len); const __end = @min(");
                        try genExpr(self, slice_range.upper.?.*);
                        try blk.emit(", __s.items.len); ");
                        try blk.breakWith("if (__start < __end) __s.items[__start..__end] else __s.items[0..0]");
                        try blk.close();
                    } else {
                        try blk.emit("const __start = @min(");
                        if (slice_range.lower) |lower| {
                            try genExpr(self, lower.*);
                        } else {
                            try self.emit("0");
                        }
                        try self.emit(", __s.len); const __end = @min(");
                        try genExpr(self, slice_range.upper.?.*);
                        try blk.emit(", __s.len); ");
                        try blk.breakWith("if (__start < __end) __s[__start..__end] else \"\"");
                        try blk.close();
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
    // Check if we need block wrapping for unknown container type with string key
    // Must check BEFORE emitting base expression to avoid invalid syntax
    const container_type = self.type_inferrer.inferExpr(subscript.value.*) catch .unknown;
    const needs_block = blk: {
        switch (subscript.slice) {
            .index => |index| {
                const index_type = self.type_inferrer.inferExpr(index.*) catch .unknown;
                break :blk type_traits.isUnknown(container_type) and
                    (string_traits.isString(index_type) or index_type == .pyvalue or type_traits.isUnknown(index_type));
            },
            .slice => break :blk false,
        }
    };

    if (needs_block) {
        // Unknown container with string/pyvalue key - emit full block wrapper
        // Do NOT emit base first - include it inside the block to avoid double-emit
        const index = subscript.slice.index.*;
        const index_type = self.type_inferrer.inferExpr(index) catch .unknown;

        const id = self.nextNameId();
        try self.emitFmt("__m{d}_sub_lhs: {{{{ const __base = ", .{id});
        // Emit the base expression (could be nested subscript or simple name)
        if (subscript.value.* == .subscript) {
            try genSubscriptLHS(self, subscript.value.subscript);
        } else {
            try genExpr(self, subscript.value.*);
        }
        try self.emitFmt("; break :__m{d}_sub_lhs if (@TypeOf(__base) == runtime.PyValue) __base.pyDictGetPtr(", .{id});
        if (index_type == .pyvalue or type_traits.isUnknown(index_type)) {
            try genExpr(self, index);
            try self.emit(".asString()");
        } else {
            try genExpr(self, index);
        }
        try self.emit(").?.* else __base.getPtr(");
        if (index_type == .pyvalue or type_traits.isUnknown(index_type)) {
            try genExpr(self, index);
            try self.emit(".asString()");
        } else {
            try genExpr(self, index);
        }
        try self.emit(").?.*; }}}}");
        return;
    }

    // Standard path: emit base expression first, then append access
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
            const index_type = self.type_inferrer.inferExpr(index.*) catch .unknown;

            // Dict access with string key - use .getPtr() for mutable access
            if (container_traits.isDict(container_type)) {
                // Native dict (StringHashMap) - use .getPtr()
                try self.emit(".getPtr(");
                try genExpr(self, index.*);
                try self.emit(").?.*");
            } else if (container_type == .pyvalue and (string_traits.isString(index_type) or index_type == .pyvalue or type_traits.isUnknown(index_type))) {
                // PyValue wrapping a dict (ptr to StringHashMap) - use .pyDictGetPtr()
                // For PyValue keys, we need to convert to string first
                try self.emit(".pyDictGetPtr(");
                if (index_type == .pyvalue or type_traits.isUnknown(index_type)) {
                    try genExpr(self, index.*);
                    try self.emit(".asString()");
                } else {
                    try genExpr(self, index.*);
                }
                try self.emit(").?.*");
            } else if (container_traits.isList(container_type)) {
                try self.emit(".items[@as(usize, @intCast(");
                try genExpr(self, index.*);
                try self.emit("))]");
            } else {
                // Default array-style access for other types
                try self.emit("[@as(usize, @intCast(");
                try genExpr(self, index.*);
                try self.emit("))]");
            }
        },
        .slice => {
            // Slice access as LHS is complex - for now just generate error
            // Slice assignment should be handled separately in assign.zig
            try self.emit("@compileError(\"Slice LHS not supported in this context\")");
        },
    }
}
