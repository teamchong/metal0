/// Dict methods - .get(), .keys(), .values(), .items(), .pop(), .update(), .clear(), .copy(),
/// .setdefault(), .popitem(), .fromkeys()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const expr_emitter = @import("../expr_emitter.zig");
const NativeType = @import("../../../analysis/native_types.zig").NativeType;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;
const container_traits = @import("../../../analysis/traits/container_traits.zig");

/// Check if a dict expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain dicts to runtime helpers
fn isDictUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

/// Generate code for dict.get(key, default)
/// Returns value if key exists, otherwise returns default (or null if no default)
/// If no args, generates generic method call (for custom class methods)
/// Two-Flow: Certain dicts use HashMap.get, uncertain dicts use PyValue.pyDictGet
pub fn genGet(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // Not a dict.get() - must be custom class method with no args
        // Generate generic method call: obj.get()
        try self.genExpr(obj);
        try self.emit(".get()");
        return;
    }

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        const default_val = if (args.len >= 2) args[1] else null;
        // Route to PyValue.pyDictGet
        if (default_val) |def| {
            try self.emit("(");
            try self.genExpr(obj);
            try self.emit(".pyDictGet(");
            try self.genExpr(args[0]);
            try self.emit(") orelse ");
            try self.genExpr(def);
            try self.emit(")");
        } else {
            try self.genExpr(obj);
            try self.emit(".pyDictGet(");
            try self.genExpr(args[0]);
            try self.emit(").?");
        }
        return;
    }

    const default_val = if (args.len >= 2) args[1] else null;

    // Check if obj produces a block/struct expression that can't have
    // methods called on them directly in Zig. Need to assign to intermediate variable.
    const is_dict_literal = producesBlockExpression(obj);

    if (is_dict_literal) {
        // Wrap in block with intermediate variable
        // Use parentheses to prevent "label:" from being parsed as named argument
        var em = self.exprEmitter();
        const label_id = em.reserveLabelId();
        try self.output.writer(self.allocator).print("(dget_{d}: {{\n", .{label_id});
        self.indent();
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("break :dget_{d} ", .{label_id});

        if (default_val) |def| {
            try self.emit("__dict_temp.get(");
            try self.genExpr(args[0]);
            try self.emit(") orelse ");
            try self.genExpr(def);
        } else {
            try self.emit("__dict_temp.get(");
            try self.genExpr(args[0]);
            try self.emit(").?");
        }
        try self.emit(";\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("})");
    } else {
        if (default_val) |def| {
            // Generate: dict.get(key) orelse default
            try self.genExpr(obj);
            try self.emit(".get(");
            try self.genExpr(args[0]);
            try self.emit(") orelse ");
            try self.genExpr(def);
        } else {
            // Generate: dict.get(key).? (force unwrap - assumes key exists, like Python does)
            // Python's dict.get(key) without default returns None if key not found,
            // but in AOT context, we assume keys exist for typed access
            try self.genExpr(obj);
            try self.emit(".get(");
            try self.genExpr(args[0]);
            try self.emit(").?");
        }
    }
}

/// Generate code for dict.keys()
/// Returns list of keys (type depends on dict key type - []const u8 or i64)
/// Two-Flow: Certain dicts iterate HashMap.keys, uncertain use runtime.pyDictKeys
pub fn genKeys(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // keys() takes no arguments

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictKeysPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try self.emit("))");
        return;
    }

    // Infer dict type to get key type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const type_traits = @import("../../../analysis/traits/type_traits.zig");
    const has_int_keys = if (container_traits.isDict(dict_type))
        type_traits.isIntegral(dict_type.dict.key.*)
    else
        false;

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that builds list of keys using .keys() slice
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(dkeys_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    if (has_int_keys) {
        try self.emit("var _keys_list = std.ArrayListUnmanaged(i64){};\n");
    } else {
        try self.emit("var _keys_list = std.ArrayListUnmanaged([]const u8){};\n");
    }

    try self.emitIndent();
    try self.emit("for (");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".keys()) |key| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("try _keys_list.append(__global_allocator, key);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dkeys_{d} _keys_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.values()
/// Returns list of values
/// Two-Flow: Certain dicts iterate HashMap.values, uncertain use runtime.pyDictValues
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictValuesPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try self.emit("))");
        return;
    }

    // Infer dict type to get value type
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (container_traits.isDict(dict_type)) dict_type.dict.value.* else NativeType{ .int = .bounded };

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that builds list of values
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(dvals_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _values_list = std.ArrayListUnmanaged(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    try self.emitIndent();
    try self.emit("for (");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".values()) |val| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("try _values_list.append(__global_allocator, val);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dvals_{d} _values_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
/// Two-Flow: Certain dicts iterate HashMap, uncertain use runtime.pyDictItems
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictItemsPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try self.emit("))");
        return;
    }

    // Infer dict type to get value type (keys are always []const u8)
    const dict_type = try self.type_inferrer.inferExpr(obj);
    const val_type = if (container_traits.isDict(dict_type)) dict_type.dict.value.* else NativeType{ .int = .bounded };

    const needs_temp = producesBlockExpression(obj);

    // Generate unique label for block
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that builds list of tuples
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.output.writer(self.allocator).print("(ditems_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store block expression in temp variable if needed
    if (needs_temp) {
        try self.emitIndent();
        try self.emit("const __dict_temp = ");
        try self.genExpr(obj);
        try self.emit(";\n");
    }

    try self.emitIndent();
    try self.emit("var _items_list = std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("})){};\n");

    try self.emitIndent();
    try self.emit("var _iter = ");
    if (needs_temp) {
        try self.emit("__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.emit("while (_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const _tuple = std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit("}){entry.key_ptr.*, entry.value_ptr.*};\n");

    try self.emitIndent();
    try self.emit("try _items_list.append(__global_allocator, _tuple);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ditems_{d} _items_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try self.emitParens(obj);
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for dict.pop(key, default?)
/// Removes key and returns value, or returns default if key not present
/// Raises KeyError if key not present and no default given
/// Two-Flow: Certain dicts use HashMap.fetchSwapRemove, uncertain use runtime.pyDictPop
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // dict.pop() requires at least 1 argument (key), second (default) is optional
    if (args.len == 0) return error.UnsupportedSyntax;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        const default_val = if (args.len >= 2) args[1] else null;
        // Route to runtime helper for PyValue dicts
        if (default_val) |def| {
            try self.emit("(runtime.pyDictPopPV(__global_allocator, &");
            try self.genExpr(obj);
            try self.emit(", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try self.emit(")) orelse ");
            try self.genExpr(def);
            try self.emit(")");
        } else {
            try self.emit("(runtime.pyDictPopPV(__global_allocator, &");
            try self.genExpr(obj);
            try self.emit(", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try self.emit(")) orelse return error.KeyError)");
        }
        return;
    }

    const default_val = if (args.len >= 2) args[1] else null;

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block: { const val = dict.fetchSwapRemove(key); if (val) |v| v.value else default/error }
    try self.output.writer(self.allocator).print("(dpop_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const __kv = ");
    try emitObjExpr(self, obj);
    try self.emit(".fetchSwapRemove(");
    try self.genExpr(args[0]);
    try self.emit(");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpop_{d} if (__kv) |kv| kv.value else ", .{label_id});
    if (default_val) |def| {
        try self.genExpr(def);
    } else {
        try self.emit("return error.KeyError");
    }
    try self.emit(";\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.update(other)
/// Updates dict with key/value pairs from other dict or iterable of pairs
/// Two-Flow: Certain dicts iterate and put, uncertain use runtime.pyDictUpdate
pub fn genUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // dict.update() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictUpdatePV(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that iterates and updates
    try self.output.writer(self.allocator).print("(dupdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store target dict as mutable pointer to enable put()
    try self.emitIndent();
    try self.emit("var __target_dict = &");
    try self.genExpr(obj);
    try self.emit(";\n");

    // Assign to temp variable first to avoid block expression syntax issues
    try self.emitIndent();
    try self.emit("const __other_dict = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("var __other_iter = __other_dict.iterator();\n");

    try self.emitIndent();
    try self.emit("while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    // Use the mutable pointer we stored above
    try self.emit("try __target_dict.put(entry.key_ptr.*, entry.value_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dupdate_{d} {{}};\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.clear()
/// Removes all items from dict
/// Two-Flow: Certain dicts use HashMap.clearRetainingCapacity, uncertain use runtime.pyDictClear
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictClearPV(&");
        try self.genExpr(obj);
        try self.emit(")");
        return;
    }

    try emitObjExpr(self, obj);
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for dict.copy()
/// Returns shallow copy of dict
/// Two-Flow: Certain dicts iterate and clone, uncertain use runtime.pyDictCopy
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictCopyPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try self.emit("))");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const src_dict = try self.name_gen.temp();
    const copy = try self.name_gen.temp();
    const iter = try self.name_gen.temp();

    // Generate block that clones the dict
    try self.output.writer(self.allocator).print("(dcopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store source dict in temp var to avoid block expression issues
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{src_dict});
    try self.genExpr(obj);
    try self.emit(";\n");

    // ArrayHashMap needs .init(allocator), not {}
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf({s}).init(__global_allocator);\n", .{ copy, src_dict });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ iter, src_dict });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{iter});
    self.indent_level += 1;

    try self.emitIndent();
    // ArrayHashMap.put() doesn't take allocator - it uses the one stored internally
    try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, entry.value_ptr.*);\n", .{copy});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dcopy_{d} {s};\n", .{ label_id, copy });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.setdefault(key, default?)
/// Returns value for key if present, otherwise sets key to default and returns it
/// Two-Flow: Certain dicts use get/put, uncertain use runtime.pyDictSetdefault
pub fn genSetdefault(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // dict.setdefault() requires at least 1 argument (key)
    if (args.len == 0) return error.UnsupportedSyntax;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictSetdefault(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        if (args.len >= 2) {
            try self.emit(", ");
            try self.genExpr(args[1]);
        } else {
            try self.emit(", null");
        }
        try self.emit(")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block: if dict.get(key) return it, else put default and return
    try self.output.writer(self.allocator).print("(dsetdef_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("const __existing = ");
    try emitObjExpr(self, obj);
    try self.emit(".get(");
    try self.genExpr(args[0]);
    try self.emit(");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (__existing) |v| break :dsetdef_{d} v;\n", .{label_id});

    try self.emitIndent();
    try self.emit("const __default = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("null");
    }
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("try ");
    try emitObjExpr(self, obj);
    // ArrayHashMap.put() doesn't take allocator
    try self.emit(".put(");
    try self.genExpr(args[0]);
    try self.emit(", __default);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dsetdef_{d} __default;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for dict.popitem()
/// Removes and returns arbitrary (key, value) pair. Raises KeyError if empty.
/// Two-Flow: Certain dicts iterate and remove, uncertain use runtime.pyDictPopitem
pub fn genPopitem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try self.emit("runtime.pyDictPopitem(__global_allocator, &");
        try self.genExpr(obj);
        try self.emit(")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const dict_ptr = try self.name_gen.temp();
    const iter = try self.name_gen.temp();
    const entry = try self.name_gen.temp();
    const key = try self.name_gen.temp();
    const val = try self.name_gen.temp();

    // Generate block that pops arbitrary item
    try self.output.writer(self.allocator).print("(dpopitem_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store dict in temp var to avoid block expression issues
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = &", .{dict_ptr});
    try self.genExpr(obj);
    try self.emit(";\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ iter, dict_ptr });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = {s}.next() orelse return error.KeyError;\n", .{ entry, iter });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = {s}.key_ptr.*;\n", .{ key, entry });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = {s}.value_ptr.*;\n", .{ val, entry });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("_ = {s}.fetchSwapRemove({s});\n", .{ dict_ptr, key });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpopitem_{d} .{{ {s}, {s} }};\n", .{ label_id, key, val });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}
