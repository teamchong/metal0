/// Collection conversion builtins: list(), tuple(), dict(), set(), frozenset()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const producesBlockExpression = @import("../../expressions.zig").producesBlockExpression;

/// Generate code for list(iterable)
/// Converts an iterable to a list (ArrayList)
pub fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // list() with no args returns empty list
    // Default to i64 element type since it's the most common case
    if (args.len == 0) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    if (args.len != 1) return;

    // Check AST node type to determine if arg already produces an ArrayList
    // List literals and comprehensions produce ArrayList directly
    // Function calls (even if type inference says .list) may return slices
    if (args[0] == .list) {
        // List literal - already generates ArrayList
        try self.genExpr(args[0]);
        return;
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

    // Convert iterable to ArrayList
    // Special handling for:
    // 1. Tuples: use PyValue tagged union for heterogeneous elements
    // 2. PyValue: extract the list/tuple inside and convert
    // 3. Dicts (ArrayHashMap): iterate over keys
    // For homogeneous iterables: infer element type from first element
    //
    // IMPORTANT: For dict attribute access (o.__dict__), we need to use @constCast
    // because the dict may have been mutated via @constCast (e.g., by setattr).
    // Copying a const dict after @constCast mutation gives stale data.
    const is_dict_attr = args[0] == .attribute and std.mem.eql(u8, args[0].attribute.attr, "__dict__");
    try self.emit("list_blk: {\n");
    if (is_dict_attr) {
        // Use pointer access to see @constCast mutations
        try self.emit("const _raw_iterable = @constCast(&");
        try self.genExpr(args[0]);
        try self.emit(");\n");
    } else {
        try self.emit("const _raw_iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    // For __dict__ attribute access, _raw_iterable is a pointer (from @constCast)
    // Handle this specially to avoid type-checking issues with .* on non-pointers
    if (is_dict_attr) {
        // _raw_iterable is a pointer to the dict - iterate directly via pointer
        try self.emit("var _list = std.ArrayList([]const u8){};\n");
        try self.emit("for (_raw_iterable.keys()) |_key| {\n");
        try self.emitFmt("try _list.append({s}, _key);\n", .{alloc_name});
        try self.emit("}\n");
        try self.emit("break :list_blk _list;\n");
        try self.emit("}"); // Close list_blk block
        return;
    }
    try self.emit("const _iterable = if (@typeInfo(@TypeOf(_raw_iterable)) == .error_union) try _raw_iterable else _raw_iterable;\n");
    try self.emit("const _IterType = @TypeOf(_iterable);\n");
    // Check if input is already a PyValue (from heterogeneous list element access)
    try self.emit("const _is_pyvalue = _IterType == runtime.PyValue;\n");
    try self.emit("if (_is_pyvalue) {\n");
    // For PyValue input, extract contents and wrap result back as PyValue
    try self.emit("const _result_list: runtime.PyValue = switch (_iterable) {\n");
    try self.emit(".list => |_pv_items| .{ .list = _pv_items },\n"); // Already a list, keep as PyValue
    try self.emit(".tuple => |_pv_items| .{ .list = _pv_items },\n"); // Tuple to list
    try self.emit("else => .{ .list = &[_]runtime.PyValue{} },\n"); // Empty list for other types
    try self.emit("};\n");
    try self.emit("break :list_blk _result_list;\n");
    try self.emit("} else {\n");
    try self.emit("const _type_info = @typeInfo(_IterType);\n");
    // Check for dict types (ArrayHashMap) - they have keys() method
    try self.emit("const _is_dict = _type_info == .@\"struct\" and @hasDecl(_IterType, \"keys\");\n");
    try self.emit("const _is_tuple = _type_info == .@\"struct\" and _type_info.@\"struct\".is_tuple;\n");
    // Handle dict by iterating keys
    try self.emit("if (_is_dict) {\n");
    try self.emit("var _list = std.ArrayList([]const u8){};\n");
    try self.emit("for (_iterable.keys()) |_key| {\n");
    try self.emitFmt("try _list.append({s}, _key);\n", .{alloc_name});
    try self.emit("}\n");
    try self.emit("break :list_blk _list;\n");
    try self.emit("} else {\n");
    // Tuples use PyValue for heterogeneous elements; others infer from first element
    try self.emit("const _ElemType = if (_is_tuple) runtime.PyValue else if (_type_info == .@\"struct\" and @hasField(_IterType, \"items\")) @TypeOf(_iterable.items[0]) else @TypeOf(_iterable[0]);\n");
    try self.emit("var _list = std.ArrayList(_ElemType){};\n");
    try self.emit("if (_is_tuple) {\n");
    try self.emit("inline for (0.._type_info.@\"struct\".fields.len) |_i| {\n");
    try self.emitFmt("try _list.append({s}, try runtime.PyValue.fromAlloc({s}, _iterable[_i]));\n", .{ alloc_name, alloc_name });
    try self.emit("}\n");
    try self.emit("} else {\n");
    try self.emit("const _slice = if (_type_info == .@\"struct\" and @hasField(_IterType, \"items\")) _iterable.items else _iterable;\n");
    try self.emit("for (_slice) |_item| {\n");
    try self.emitFmt("try _list.append({s}, _item);\n", .{alloc_name});
    try self.emit("}\n");
    try self.emit("}\n");
    try self.emit("break :list_blk _list;\n");
    try self.emit("}\n");
    try self.emit("}\n");
    try self.emit("}");
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

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a tuple - just return it
    switch (arg_type) {
        .tuple => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // For name references to iterators, exhaust them by calling next until done
    // This produces a runtime tuple and properly exhausts stateful iterators
    if (args[0] == .name) {
        const label = self.block_label_counter;
        self.block_label_counter += 1;
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
        try self.emit("std.StringHashMap(i64){}");
        return;
    }

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a dict - just return it
    switch (arg_type) {
        .dict => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // For other cases, just pass through
    try self.genExpr(args[0]);
}

/// Generate code for set(iterable)
/// Converts an iterable to a set (AutoHashMap with void values)
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // set() with no args returns empty set
    // Default to i64 key type since it's the most common case
    if (args.len == 0) {
        try self.emitFmt("std.AutoHashMap(i64, void).init({s})", .{alloc_name});
        return;
    }

    if (args.len != 1) return;

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
        try self.emit("set_blk: {\n");
        try self.emitFmt("var _set = hashmap_helper.StringHashMap(void).init({s});\n", .{alloc_name});
        try self.emit("for (runtime.FeatureMacros.keys()) |_item| {\n");
        try self.emit("try _set.put(_item, {});\n");
        try self.emit("}\n");
        try self.emit("break :set_blk _set;\n");
        try self.emit("}");
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a set - just return it
    switch (arg_type) {
        .set => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // Check if the iterable contains strings (e.g., list of strings or string itself)
    // In that case we need StringHashMap instead of AutoHashMap
    // Check for: string type (iterating chars), or list/set containing strings
    const is_string_set = blk: {
        if (arg_type == .string) break :blk true;
        // Check if it's a list/tuple of string literals
        if (args[0] == .list) {
            const list = args[0].list;
            if (list.elts.len > 0) {
                const first_type = self.type_inferrer.inferExpr(list.elts[0]) catch .unknown;
                if (first_type == .string) break :blk true;
            }
        }
        if (args[0] == .tuple) {
            const tup = args[0].tuple;
            if (tup.elts.len > 0) {
                const first_type = self.type_inferrer.inferExpr(tup.elts[0]) catch .unknown;
                if (first_type == .string) break :blk true;
            }
        }
        break :blk false;
    };

    // Convert iterable to set
    // Check if arg produces a block expression that needs to be stored in temp variable
    const needs_temp = producesBlockExpression(args[0]);

    try self.emit("set_blk: {\n");

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
        try self.emit("for (__iterable) |_item| {\n");
    } else {
        if (is_string_set) {
            try self.emitFmt("var _set = hashmap_helper.StringHashMap(void).init({s});\n", .{alloc_name});
        } else {
            try self.emit("var _set = std.AutoHashMap(@TypeOf(");
            try self.genExpr(args[0]);
            try self.emitFmt("[0]), void).init({s});\n", .{alloc_name});
        }
        try self.emit("for (");
        try self.genExpr(args[0]);
        try self.emit(") |_item| {\n");
    }
    try self.emit("try _set.put(_item, {});\n");
    try self.emit("}\n");
    try self.emit("break :set_blk _set;\n");
    try self.emit("}");
}

/// Generate code for frozenset(iterable)
/// Same as set() but conceptually immutable
pub fn genFrozenset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // frozenset is the same implementation as set in AOT context
    try genSet(self, args);
}
