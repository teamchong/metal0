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

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
        try emitConst(self,".get()");
        return;
    }

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        const default_val = if (args.len >= 2) args[1] else null;
        // Route to PyValue.pyDictGet
        if (default_val) |def| {
            try emitConst(self,"(");
            try self.genExpr(obj);
            try emitConst(self,".pyDictGet(");
            try self.genExpr(args[0]);
            try emitConst(self,") orelse ");
            try self.genExpr(def);
            try emitConst(self,")");
        } else {
            try self.genExpr(obj);
            try emitConst(self,".pyDictGet(");
            try self.genExpr(args[0]);
            try emitConst(self,").?");
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
        try emitConst(self,"const __dict_temp = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("break :dget_{d} ", .{label_id});

        if (default_val) |def| {
            try emitConst(self,"__dict_temp.get(");
            try self.genExpr(args[0]);
            try emitConst(self,") orelse ");
            try self.genExpr(def);
        } else {
            try emitConst(self,"__dict_temp.get(");
            try self.genExpr(args[0]);
            try emitConst(self,").?");
        }
        try emitConst(self,";\n");
        self.dedent();
        try self.emitIndent();
        try emitConst(self,"})");
    } else {
        if (default_val) |def| {
            // Generate: dict.get(key) orelse default
            try self.genExpr(obj);
            try emitConst(self,".get(");
            try self.genExpr(args[0]);
            try emitConst(self,") orelse ");
            try self.genExpr(def);
        } else {
            // Generate: dict.get(key).? (force unwrap - assumes key exists, like Python does)
            // Python's dict.get(key) without default returns None if key not found,
            // but in AOT context, we assume keys exist for typed access
            try self.genExpr(obj);
            try emitConst(self,".get(");
            try self.genExpr(args[0]);
            try emitConst(self,").?");
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
        try emitConst(self,"runtime.pyDictKeysPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try emitConst(self,"))");
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
        try emitConst(self,"const __dict_temp = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
    }

    try self.emitIndent();
    if (has_int_keys) {
        try emitConst(self,"var _keys_list = std.ArrayListUnmanaged(i64){};\n");
    } else {
        try emitConst(self,"var _keys_list = std.ArrayListUnmanaged([]const u8){};\n");
    }

    try self.emitIndent();
    try emitConst(self,"for (");
    if (needs_temp) {
        try emitConst(self,"__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try emitConst(self,".keys()) |key| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try emitConst(self,"try _keys_list.append(__global_allocator, key);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dkeys_{d} _keys_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for dict.values()
/// Returns list of values
/// Two-Flow: Certain dicts iterate HashMap.values, uncertain use runtime.pyDictValues
pub fn genValues(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // values() takes no arguments

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try emitConst(self,"runtime.pyDictValuesPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try emitConst(self,"))");
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
        try emitConst(self,"const __dict_temp = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
    }

    try self.emitIndent();
    try emitConst(self,"var _values_list = std.ArrayListUnmanaged(");
    try val_type.toZigType(self.allocator, &self.output);
    try emitConst(self,"){};\n");

    try self.emitIndent();
    try emitConst(self,"for (");
    if (needs_temp) {
        try emitConst(self,"__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try emitConst(self,".values()) |val| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try emitConst(self,"try _values_list.append(__global_allocator, val);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dvals_{d} _values_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for dict.items()
/// Returns list of tuples (key-value pairs)
/// Two-Flow: Certain dicts iterate HashMap, uncertain use runtime.pyDictItems
pub fn genItems(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // items() takes no arguments

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try emitConst(self,"runtime.pyDictItemsPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try emitConst(self,"))");
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
        try emitConst(self,"const __dict_temp = ");
        try self.genExpr(obj);
        try emitConst(self,";\n");
    }

    try self.emitIndent();
    try emitConst(self,"var _items_list = std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try emitConst(self,"})){};\n");

    try self.emitIndent();
    try emitConst(self,"var _iter = ");
    if (needs_temp) {
        try emitConst(self,"__dict_temp");
    } else {
        try self.genExpr(obj);
    }
    try emitConst(self,".iterator();\n");

    try self.emitIndent();
    try emitConst(self,"while (_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    try emitConst(self,"const _tuple = std.meta.Tuple(&[_]type{[]const u8, ");
    try val_type.toZigType(self.allocator, &self.output);
    try emitConst(self,"}){entry.key_ptr.*, entry.value_ptr.*};\n");

    try self.emitIndent();
    try emitConst(self,"try _items_list.append(__global_allocator, _tuple);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ditems_{d} _items_list;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try emitConst(self,"(");
        try self.genExpr(obj);
        try emitConst(self,")");
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
            try emitConst(self,"(runtime.pyDictPopPV(__global_allocator, &");
            try self.genExpr(obj);
            try emitConst(self,", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try emitConst(self,")) orelse ");
            try self.genExpr(def);
            try emitConst(self,")");
        } else {
            try emitConst(self,"(runtime.pyDictPopPV(__global_allocator, &");
            try self.genExpr(obj);
            try emitConst(self,", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try emitConst(self,")) orelse return error.KeyError)");
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
    try emitConst(self,"const __kv = ");
    try emitObjExpr(self, obj);
    try emitConst(self,".fetchSwapRemove(");
    try self.genExpr(args[0]);
    try emitConst(self,");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpop_{d} if (__kv) |kv| kv.value else ", .{label_id});
    if (default_val) |def| {
        try self.genExpr(def);
    } else {
        try emitConst(self,"return error.KeyError");
    }
    try emitConst(self,";\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
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
        try emitConst(self,"runtime.pyDictUpdatePV(__global_allocator, &");
        try self.genExpr(obj);
        try emitConst(self,", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that iterates and updates
    try self.output.writer(self.allocator).print("(dupdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store target dict as mutable pointer to enable put()
    try self.emitIndent();
    try emitConst(self,"var __target_dict = &");
    try self.genExpr(obj);
    try emitConst(self,";\n");

    // Assign to temp variable first to avoid block expression syntax issues
    try self.emitIndent();
    try emitConst(self,"const __other_dict = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");

    try self.emitIndent();
    try emitConst(self,"var __other_iter = __other_dict.iterator();\n");

    try self.emitIndent();
    try emitConst(self,"while (__other_iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    // Use the mutable pointer we stored above
    try emitConst(self,"try __target_dict.put(entry.key_ptr.*, entry.value_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dupdate_{d} {{}};\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for dict.clear()
/// Removes all items from dict
/// Two-Flow: Certain dicts use HashMap.clearRetainingCapacity, uncertain use runtime.pyDictClear
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try emitConst(self,"runtime.pyDictClearPV(&");
        try self.genExpr(obj);
        try emitConst(self,")");
        return;
    }

    try emitObjExpr(self, obj);
    try emitConst(self,".clearRetainingCapacity()");
}

/// Generate code for dict.copy()
/// Returns shallow copy of dict
/// Two-Flow: Certain dicts iterate and clone, uncertain use runtime.pyDictCopy
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try emitConst(self,"runtime.pyDictCopyPV(__global_allocator, runtime.PyValue.from(");
        try self.genExpr(obj);
        try emitConst(self,"))");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that clones the dict
    try self.output.writer(self.allocator).print("(dcopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store source dict in temp var to avoid block expression issues
    try self.emitIndent();
    try emitConst(self,"const __src_dict = ");
    try self.genExpr(obj);
    try emitConst(self,";\n");

    // ArrayHashMap needs .init(allocator), not {}
    try self.emitIndent();
    try emitConst(self,"var __copy = @TypeOf(__src_dict).init(__global_allocator);\n");

    try self.emitIndent();
    try emitConst(self,"var __iter = __src_dict.iterator();\n");

    try self.emitIndent();
    try emitConst(self,"while (__iter.next()) |entry| {\n");
    self.indent_level += 1;

    try self.emitIndent();
    // ArrayHashMap.put() doesn't take allocator - it uses the one stored internally
    try emitConst(self,"try __copy.put(entry.key_ptr.*, entry.value_ptr.*);\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dcopy_{d} __copy;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
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
        try emitConst(self,"runtime.pyDictSetdefault(__global_allocator, &");
        try self.genExpr(obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        if (args.len >= 2) {
            try emitConst(self,", ");
            try self.genExpr(args[1]);
        } else {
            try emitConst(self,", null");
        }
        try emitConst(self,")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block: if dict.get(key) return it, else put default and return
    try self.output.writer(self.allocator).print("(dsetdef_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try emitConst(self,"const __existing = ");
    try emitObjExpr(self, obj);
    try emitConst(self,".get(");
    try self.genExpr(args[0]);
    try emitConst(self,");\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (__existing) |v| break :dsetdef_{d} v;\n", .{label_id});

    try self.emitIndent();
    try emitConst(self,"const __default = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try emitConst(self,"null");
    }
    try emitConst(self,";\n");

    try self.emitIndent();
    try emitConst(self,"try ");
    try emitObjExpr(self, obj);
    // ArrayHashMap.put() doesn't take allocator
    try emitConst(self,".put(");
    try self.genExpr(args[0]);
    try emitConst(self,", __default);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dsetdef_{d} __default;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for dict.popitem()
/// Removes and returns arbitrary (key, value) pair. Raises KeyError if empty.
/// Two-Flow: Certain dicts iterate and remove, uncertain use runtime.pyDictPopitem
pub fn genPopitem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if dict is uncertain (PyValue or unknown type)
    if (isDictUncertain(self, obj)) {
        // Route to runtime helper for PyValue dicts
        try emitConst(self,"runtime.pyDictPopitem(__global_allocator, &");
        try self.genExpr(obj);
        try emitConst(self,")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate block that pops arbitrary item
    try self.output.writer(self.allocator).print("(dpopitem_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store dict in temp var to avoid block expression issues
    try self.emitIndent();
    try emitConst(self,"const __dict_ptr = &");
    try self.genExpr(obj);
    try emitConst(self,";\n");

    try self.emitIndent();
    try emitConst(self,"var __iter = __dict_ptr.iterator();\n");

    try self.emitIndent();
    try emitConst(self,"const __entry = __iter.next() orelse return error.KeyError;\n");

    try self.emitIndent();
    try emitConst(self,"const __key = __entry.key_ptr.*;\n");

    try self.emitIndent();
    try emitConst(self,"const __val = __entry.value_ptr.*;\n");

    try self.emitIndent();
    try emitConst(self,"_ = __dict_ptr.fetchSwapRemove(__key);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dpopitem_{d} .{{ __key, __val }};\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"})");
}
