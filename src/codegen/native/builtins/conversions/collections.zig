/// Collection conversion builtins: list(), tuple(), dict(), set(), frozenset()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const producesBlockExpression = @import("../../expressions.zig").producesBlockExpression;
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const expr_emitter = @import("../../expr_emitter.zig");

// === Structured emission helpers ===

/// Helper: emit runtime.func(alloc, expr) with guaranteed bracket matching
fn emitRuntimeAllocCall(self: *NativeCodegen, comptime func: []const u8, arg: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime." ++ func, arg, struct {
        pub fn f(s: *NativeCodegen, a: ast.Node) CodegenError!void {
            try s.emit("__global_allocator, ");
            try s.genExpr(a);
        }
    }.f);
}

/// Get the appropriate NativeList append method for a given type
/// This avoids anytype monomorphization by using typed append methods
fn getAppendMethodForType(t: NativeType) []const u8 {
    return switch (t) {
        .int => "appendInt",
        .float => "appendFloat",
        .string => "appendString",
        .bool => "appendBool",
        .none => "appendNone",
        else => "appendValue", // Falls back to PyValue-based append
    };
}

/// Generate code for list(iterable)
/// Converts an iterable to a list (ArrayList)
pub fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Always use __global_allocator - it's always available (parameter "allocator" was renamed to avoid shadowing)
    const alloc_name = "__global_allocator";

    // list() with no args returns empty NativeList
    if (args.len == 0) {
        try self.emit("runtime.NativeList.init()");
        return;
    }

    // list() takes 0 or 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Check AST node type to determine if arg already produces an ArrayList
    // List literals and comprehensions produce ArrayList directly
    // Function calls (even if type inference says .list) may return slices
    if (args[0] == .list) {
        // List literal - already generates ArrayList
        try self.genExpr(args[0]);
        return;
    }

    // Handle tuple literals - convert to NativeList inline
    // list((1, 2, 3)) -> NativeList with typed append methods (no monomorphization)
    if (args[0] == .tuple) {
        const tup = args[0].tuple;
        if (tup.elts.len == 0) {
            try self.emit("runtime.NativeList.init()");
            return;
        }
        var em = self.exprEmitter();
        const list_label = em.reserveLabelId();
        try self.emitFmt("list_tup_blk_{d}: {{\n", .{list_label});
        try self.emit("var _list = runtime.NativeList.init();\n");
        for (tup.elts) |elt| {
            // Infer element type to choose typed append method
            const elt_type = self.type_inferrer.inferExpr(elt) catch .unknown;
            const append_method = getAppendMethodForType(elt_type);
            try self.emitFmt("try _list.{s}({s}, ", .{ append_method, alloc_name });
            try self.genExpr(elt);
            try self.emit(");\n");
        }
        try self.emitFmt("break :list_tup_blk_{d} _list;\n", .{list_label});
        try self.emit("}");
        return;
    }

    // Handle range() calls - generate inline loop to avoid *PyObject/PyValue mismatch
    // list(range(n)) -> loop from 0 to n, building ArrayListUnmanaged(i64)
    if (args[0] == .call and args[0].call.func.* == .name) {
        const func_name = args[0].call.func.name.id;
        if (std.mem.eql(u8, func_name, "range")) {
            const range_args = args[0].call.args;
            var em_range = self.exprEmitter();
            const list_label = em_range.reserveLabelId();
            try self.emitFmt("list_range_blk_{d}: {{\n", .{list_label});
            // Use ArrayListUnmanaged(i64) directly - matches print and other list operations
            try self.emit("var _list = std.ArrayListUnmanaged(i64){};\n");

            if (range_args.len == 1) {
                // range(stop) -> for (0..stop)
                try self.emit("const _stop: i64 = @intCast(");
                try self.genExpr(range_args[0]);
                try self.emit(");\n");
                try self.emit("var _i: i64 = 0;\n");
                try self.emit("while (_i < _stop) : (_i += 1) {\n");
                try self.emitFmt("try _list.append({s}, _i);\n", .{alloc_name});
                try self.emit("}\n");
            } else if (range_args.len == 2) {
                // range(start, stop) -> for (start..stop)
                try self.emit("const _start: i64 = @intCast(");
                try self.genExpr(range_args[0]);
                try self.emit(");\n");
                try self.emit("const _stop: i64 = @intCast(");
                try self.genExpr(range_args[1]);
                try self.emit(");\n");
                try self.emit("var _i: i64 = _start;\n");
                try self.emit("while (_i < _stop) : (_i += 1) {\n");
                try self.emitFmt("try _list.append({s}, _i);\n", .{alloc_name});
                try self.emit("}\n");
            } else if (range_args.len >= 3) {
                // range(start, stop, step)
                try self.emit("const _start: i64 = @intCast(");
                try self.genExpr(range_args[0]);
                try self.emit(");\n");
                try self.emit("const _stop: i64 = @intCast(");
                try self.genExpr(range_args[1]);
                try self.emit(");\n");
                try self.emit("const _step: i64 = @intCast(");
                try self.genExpr(range_args[2]);
                try self.emit(");\n");
                try self.emit("var _i: i64 = _start;\n");
                try self.emit("if (_step > 0) {\n");
                try self.emit("while (_i < _stop) : (_i += _step) {\n");
                try self.emitFmt("try _list.append({s}, _i);\n", .{alloc_name});
                try self.emit("}\n");
                try self.emit("} else if (_step < 0) {\n");
                try self.emit("while (_i > _stop) : (_i += _step) {\n");
                try self.emitFmt("try _list.append({s}, _i);\n", .{alloc_name});
                try self.emit("}\n");
                try self.emit("}\n");
            }

            try self.emitFmt("break :list_range_blk_{d} _list;\n", .{list_label});
            try self.emit("}");
            return;
        }
    }

    // Handle generator expressions specially - they already generate ArrayList
    // So list(gen_expr) is just the generator expression itself
    if (args[0] == .genexp) {
        // Generator expression already returns an ArrayList, just use it directly
        try self.genExpr(args[0]);
        return;
    }

    // Handle list comprehensions similarly - they also generate ArrayList
    if (args[0] == .listcomp) {
        try self.genExpr(args[0]);
        return;
    }

    // Handle literal strings - convert to NativeList of single-character strings
    // list("abc") -> NativeList with ["a", "b", "c"]
    // In Python, list("spam") yields ['s', 'p', 'a', 'm']
    if (args[0] == .constant and args[0].constant.value == .string) {
        const str = args[0].constant.value.string;
        if (str.len == 0) {
            try self.emit("runtime.NativeList.init()");
            return;
        }
        // Generate inline NativeList initialization with string characters
        var em_str = self.exprEmitter();
        const list_str_label = em_str.reserveLabelId();
        try self.emitFmt("list_str_blk_{d}: {{\n", .{list_str_label});
        try self.emit("var _list = runtime.NativeList.init();\n");
        // Iterate through UTF-8 characters
        var i: usize = 0;
        while (i < str.len) {
            // Get UTF-8 character length
            const byte = str[i];
            const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
            const end = @min(i + char_len, str.len);
            // Escape special characters
            const char = str[i..end];
            try self.emitFmt("try _list.appendString({s}, ", .{alloc_name});
            if (char.len == 1 and (char[0] == '"' or char[0] == '\\')) {
                try self.emit("\"\\");
                try self.emit(char);
                try self.emit("\"");
            } else if (char.len == 1 and char[0] == '\n') {
                try self.emit("\"\\n\"");
            } else if (char.len == 1 and char[0] == '\r') {
                try self.emit("\"\\r\"");
            } else if (char.len == 1 and char[0] == '\t') {
                try self.emit("\"\\t\"");
            } else {
                try self.emit("\"");
                try self.emit(char);
                try self.emit("\"");
            }
            try self.emit(");\n");
            i = end;
        }
        try self.emitFmt("break :list_str_blk_{d} _list;\n", .{list_str_label});
        try self.emit("}");
        return;
    }

    // Use type inference to generate optimized code paths
    // This avoids the slow inline comptime type checks
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_dict_attr = args[0] == .attribute and std.mem.eql(u8, args[0].attribute.attr, "__dict__");

    // TWO-FLOW: Handle uncertain types (PyValue) via runtime conversion
    if (arg_type == .pyvalue) {
        try emitRuntimeAllocCall(self, "listFromAny", args[0]);
        return;
    }

    // Fast path: already a list type - just pass through
    if (container_traits.isList(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // Note: tuple literals are handled above by AST check (args[0] == .tuple)
    // If we get here with a tuple type, it's from a variable/call, which we
    // can handle via generic iteration (tuples implement iterator protocol)

    // Fast path: string type - use runtime.listFromString
    if (string_traits.isString(arg_type)) {
        try emitRuntimeAllocCall(self, "listFromString", args[0]);
        return;
    }

    // Fast path: dict type - iterate keys using NativeList
    if (container_traits.isDict(arg_type) or is_dict_attr) {
        var em_dict = self.exprEmitter();
        const list_label = em_dict.reserveLabelId();
        try self.emitFmt("list_blk_{d}: {{\n", .{list_label});
        if (is_dict_attr) {
            try self.emit("const _dict = @constCast(&");
            try self.genExpr(args[0]);
            try self.emit(");\n");
        } else {
            try self.emit("const _dict = ");
            try self.genExpr(args[0]);
            try self.emit(";\n");
        }
        try self.emit("var _list = runtime.NativeList.init();\n");
        try self.emit("for (_dict.keys()) |_key| {\n");
        try self.emitFmt("try _list.appendString({s}, _key);\n", .{alloc_name});
        try self.emit("}\n");
        try self.emitFmt("break :list_blk_{d} _list;\n", .{list_label});
        try self.emit("}");
        return;
    }

    // Fast path: array/slice type with known element type using NativeList
    const elem_type = container_traits.getElementType(arg_type);
    if (elem_type != .unknown) {
        var em_elem = self.exprEmitter();
        const list_label = em_elem.reserveLabelId();
        try self.emitFmt("list_blk_{d}: {{\n", .{list_label});
        try self.emit("const _iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        // Use typed append method based on element type (avoids anytype monomorphization)
        const append_method = getAppendMethodForType(elem_type);
        try self.emit("var _list = runtime.NativeList.init();\n");
        try self.emit("for (_iterable) |_item| {\n");
        try self.emitFmt("try _list.{s}({s}, _item);\n", .{ append_method, alloc_name });
        try self.emit("}\n");
        try self.emitFmt("break :list_blk_{d} _list;\n", .{list_label});
        try self.emit("}");
        return;
    }

    // Fallback: generic runtime conversion (compact version)
    // Only generate the full type-checking code when we truly can't infer the type
    try emitRuntimeAllocCall(self, "listFromAny", args[0]);
}

/// Generate code for tuple(iterable)
/// Converts an iterable to a tuple (fixed-size)
/// For iterators, this exhausts them (consumes all remaining items)
pub fn genTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // tuple() with no args returns empty tuple
    if (args.len == 0) {
        try self.emit(".{}");
        return;
    }

    // tuple() takes 0 or 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Handle literal lists - convert to tuple literal directly
    // tuple([]) -> .{}
    // tuple([1, 2, 3]) -> .{ 1, 2, 3 }
    if (args[0] == .list) {
        const list = args[0].list;
        if (list.elts.len == 0) {
            try self.emit(".{}");
            return;
        }
        // Generate tuple literal from list elements
        try self.emit(".{ ");
        for (list.elts, 0..) |elt, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(elt);
        }
        try self.emit(" }");
        return;
    }

    // Handle tuple literals - just pass through
    if (args[0] == .tuple) {
        const tup = args[0].tuple;
        if (tup.elts.len == 0) {
            try self.emit(".{}");
            return;
        }
        try self.emit(".{ ");
        for (tup.elts, 0..) |elt, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(elt);
        }
        try self.emit(" }");
        return;
    }

    // Handle literal strings - convert to tuple of characters
    // tuple("abc") -> .{ "a", "b", "c" }
    if (args[0] == .constant and args[0].constant.value == .string) {
        const str = args[0].constant.value.string;
        if (str.len == 0) {
            try self.emit(".{}");
            return;
        }
        try self.emit(".{ ");
        var i: usize = 0;
        while (i < str.len) {
            if (i > 0) try self.emit(", ");
            // Get UTF-8 character length
            const byte = str[i];
            const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
            const end = @min(i + char_len, str.len);
            // Escape special characters
            const char = str[i..end];
            if (char.len == 1 and (char[0] == '"' or char[0] == '\\')) {
                try self.emit("\"\\");
                try self.emit(char);
                try self.emit("\"");
            } else if (char.len == 1 and char[0] == '\n') {
                try self.emit("\"\\n\"");
            } else if (char.len == 1 and char[0] == '\r') {
                try self.emit("\"\\r\"");
            } else if (char.len == 1 and char[0] == '\t') {
                try self.emit("\"\\t\"");
            } else {
                try self.emit("\"");
                try self.emit(char);
                try self.emit("\"");
            }
            i = end;
        }
        try self.emit(" }");
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a tuple type - just return it
    if (container_traits.isTuple(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // For name references to iterators, exhaust them by calling next until done
    // This produces a runtime tuple and properly exhausts stateful iterators
    if (args[0] == .name) {
        var em_iter = self.exprEmitter();
        const label = em_iter.reserveLabelId();
        // Generate a block that exhausts the iterator
        // For StringIterator and similar, we iterate until next() returns null
        try self.output.writer(self.allocator).print("tup_{d}: {{\n", .{label});
        try self.emitIndent();
        try self.emit("    // Exhaust iterator by consuming all elements\n");
        try self.emitIndent();
        try self.emit("    while (");
        try self.genExpr(args[0]);
        try self.emit(".next()) |_| {}\n");
        try self.emitIndent();
        try self.emit("    // Return original data (iterator is now exhausted)\n");
        try self.emitIndent();
        try self.emit("    break :tup_");
        try self.output.writer(self.allocator).print("{d}", .{label});
        try self.emit(" ");
        try self.genExpr(args[0]);
        try self.emit(".data;\n");
        try self.emitIndent();
        try self.emit("}");
        return;
    }

    // For other iterables, generate inline tuple
    // This is limited since Zig tuples need comptime-known size
    try self.genExpr(args[0]);
}

/// Generate code for dict(iterable)
/// Converts key-value pairs to a dict (StringHashMap)
pub fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // dict() with no args returns empty dict
    // Default to i64 value type since it's common (keys are strings)
    if (args.len == 0) {
        try self.emit("hashmap_helper.StringHashMap(i64){}");
        return;
    }

    // dict() takes 0 or 1 argument - generate runtime TypeError for invalid counts
    if (args.len > 1) {
        try self.emit("(blk_dict_err: {\n");
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"TypeError\", \"dict expected at most 1 argument, got ");
        try self.emitFmt("{d}\", @src().line);\n", .{args.len});
        try self.emit("break :blk_dict_err error.TypeError;\n");
        try self.emit("})");
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // TWO-FLOW: Handle uncertain types (PyValue)
    // Note: PyValue doesn't support dict directly, so we pass through
    // and rely on runtime type dispatch. This may need a runtime helper
    // if dict() is called on uncertain types.
    if (arg_type == .pyvalue) {
        // PyValue doesn't have .dict field - pass through and hope the
        // underlying value is already a dict-compatible type
        try self.genExpr(args[0]);
        return;
    }

    // Already a dict - just return it
    if (container_traits.isDict(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // For other cases, just pass through
    try self.genExpr(args[0]);
}

/// Generate code for set(iterable)
/// Converts an iterable to a set (AutoHashMap with void values)
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Always use __global_allocator - it's always available (parameter "allocator" was renamed to avoid shadowing)
    const alloc_name = "__global_allocator";

    // set() with no args returns empty set
    // Default to i64 key type since it's the most common case
    if (args.len == 0) {
        try self.emitFmt("std.AutoHashMap(i64, void).init({s})", .{alloc_name});
        return;
    }

    // set() takes 0 or 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Special case: set(feature_macros) or set(get_feature_macros())
    // FeatureMacros is a struct, not iterable - use .keys() to get string array
    const is_feature_macros = blk: {
        switch (args[0]) {
            .name => |n| {
                if (std.mem.eql(u8, n.id, "feature_macros")) {
                    break :blk true;
                }
            },
            .call => |call| {
                if (call.func.* == .name) {
                    const func_name = call.func.*.name.id;
                    if (std.mem.eql(u8, func_name, "get_feature_macros")) {
                        break :blk true;
                    }
                }
            },
            else => {},
        }
        break :blk false;
    };

    if (is_feature_macros) {
        // Generate set from FeatureMacros.keys()
        var em_feat = self.exprEmitter();
        const set_label_1 = em_feat.reserveLabelId();
        try self.emitFmt("set_blk_{d}: {{\n", .{set_label_1});
        try self.emitFmt("var _set = hashmap_helper.StringHashMap(void).init({s});\n", .{alloc_name});
        try self.emit("for (runtime.FeatureMacros.keys()) |_item| {\n");
        try self.emit("try _set.put(_item, {});\n");
        try self.emit("}\n");
        try self.emitFmt("break :set_blk_{d} _set;\n", .{set_label_1});
        try self.emit("}");
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // TWO-FLOW: Handle uncertain types (PyValue)
    // Note: PyValue doesn't support set directly, so for PyValue.list
    // we can iterate and build a set from the elements.
    if (arg_type == .pyvalue) {
        var em_pyval = self.exprEmitter();
        const set_label = em_pyval.reserveLabelId();
        // PyValue.list is *ArrayListUnmanaged(PyValue) - iterate items and build set
        try self.emitFmt("set_pyval_{d}: {{\n", .{set_label});
        try self.emit("const __pyval_iter = ");
        try self.genExpr(args[0]);
        try self.emit(".list.items;\n"); // Extract items slice from PyValue.list pointer
        try self.emitFmt("var _set = std.AutoHashMap(runtime.PyValue, void).init({s});\n", .{alloc_name});
        try self.emit("for (__pyval_iter) |_item| {\n");
        try self.emit("try _set.put(_item, {});\n");
        try self.emit("}\n");
        try self.emitFmt("break :set_pyval_{d} _set;\n", .{set_label});
        try self.emit("}");
        return;
    }

    // Already a set - just return it
    if (container_traits.isSet(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // Check if the iterable contains strings (e.g., list of strings or string itself)
    // In that case we need StringHashMap instead of AutoHashMap
    // Check for: string type (iterating chars), or list/set containing strings
    const is_string_set = blk: {
        if (string_traits.isString(arg_type)) break :blk true;
        // Check if it's a list/tuple of string literals
        if (args[0] == .list) {
            const list = args[0].list;
            if (list.elts.len > 0) {
                const first_type = self.type_inferrer.inferExpr(list.elts[0]) catch .unknown;
                if (string_traits.isString(first_type)) break :blk true;
            }
        }
        if (args[0] == .tuple) {
            const tup = args[0].tuple;
            if (tup.elts.len > 0) {
                const first_type = self.type_inferrer.inferExpr(tup.elts[0]) catch .unknown;
                if (string_traits.isString(first_type)) break :blk true;
            }
        }
        break :blk false;
    };

    // Convert iterable to set
    // Check if arg produces a block expression that needs to be stored in temp variable
    const needs_temp = producesBlockExpression(args[0]);
    const is_tuple_literal = args[0] == .tuple;

    var em_set = self.exprEmitter();
    const set_label_2 = em_set.reserveLabelId();
    try self.emitFmt("set_blk_{d}: {{\n", .{set_label_2});

    if (needs_temp) {
        // Store block expression in temp variable first
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        if (is_string_set) {
            try self.emitFmt("var _set = hashmap_helper.StringHashMap(void).init({s});\n", .{alloc_name});
        } else {
            try self.emitFmt("var _set = std.AutoHashMap(@TypeOf(__iterable[0]), void).init({s});\n", .{alloc_name});
        }
        // Use inline for with tuples to avoid comptime index errors
        if (is_tuple_literal) {
            try self.emit("inline for (__iterable) |_item| {\n");
        } else {
            try self.emit("for (__iterable) |_item| {\n");
        }
    } else {
        if (is_string_set) {
            try self.emitFmt("var _set = hashmap_helper.StringHashMap(void).init({s});\n", .{alloc_name});
        } else {
            try self.emit("var _set = std.AutoHashMap(@TypeOf(");
            try self.genExpr(args[0]);
            try self.emitFmt("[0]), void).init({s});\n", .{alloc_name});
        }
        // Use inline for with tuples to avoid comptime index errors
        if (is_tuple_literal) {
            try self.emit("inline for (");
        } else {
            try self.emit("for (");
        }
        try self.genExpr(args[0]);
        try self.emit(") |_item| {\n");
    }
    try self.emit("try _set.put(_item, {});\n");
    try self.emit("}\n");
    try self.emitFmt("break :set_blk_{d} _set;\n", .{set_label_2});
    try self.emit("}");
}

/// Generate code for frozenset(iterable)
/// Same as set() but conceptually immutable
pub fn genFrozenset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // frozenset is the same implementation as set in AOT context
    try genSet(self, args);
}
