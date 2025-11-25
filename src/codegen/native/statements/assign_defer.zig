/// Defer cleanup logic for assignments
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");

/// Get the allocator name based on current scope level
fn getAllocName(self: *NativeCodegen) []const u8 {
    // In main() (scope 0): use 'allocator' (local variable)
    // In functions (scope > 0): use '__global_allocator' (module-level)
    return if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
}

/// Add defer cleanup for string concatenation
pub fn emitStringConcatDefer(self: *NativeCodegen, var_name: []const u8, is_first_assignment: bool) CodegenError!void {
    if (is_first_assignment) {
        const alloc_name = getAllocName(self);
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {s}.free({s});\n", .{ alloc_name, var_name });
    }
}

/// Add defer cleanup for ArrayList
pub fn emitArrayListDefer(self: *NativeCodegen, var_name: []const u8) CodegenError!void {
    const alloc_name = getAllocName(self);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("defer {s}.deinit({s});\n", .{ var_name, alloc_name });
}

/// Add defer cleanup for list comprehensions (return slices, not ArrayLists)
pub fn emitListCompDefer(self: *NativeCodegen, var_name: []const u8) CodegenError!void {
    const alloc_name = getAllocName(self);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("defer {s}.free({s});\n", .{ alloc_name, var_name });
}

/// Check if dict needs complex cleanup (string values that were allocated)
fn needsValueCleanup(self: *NativeCodegen, dict: ast.Node.Dict, is_comptime_dict: bool) CodegenError!bool {
    if (is_comptime_dict) return false; // Comptime dicts never need value cleanup
    if (dict.values.len == 0) return false;

    // Check if values have different types (will be widened to string)
    const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
    for (dict.values[1..]) |value| {
        const this_type = try self.type_inferrer.inferExpr(value);
        // Direct enum tag comparison
        const first_tag = @as(std.meta.Tag(@TypeOf(first_type)), first_type);
        const this_tag = @as(std.meta.Tag(@TypeOf(this_type)), this_type);
        if (first_tag != this_tag) {
            // Different types → runtime path will allocate strings
            return true;
        }
    }

    // All same type → no value cleanup needed
    return false;
}

/// Add defer cleanup for dict (with value cleanup if needed)
pub fn emitDictDefer(self: *NativeCodegen, var_name: []const u8, assign_value: ast.Node) CodegenError!void {
    if (assign_value != .dict) {
        // Simple defer for non-dict literals
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {s}.deinit();\n", .{var_name});
        return;
    }

    const dict = assign_value.dict;

    // Check if dict will use comptime path (all constants AND compatible types)
    // Must match the logic in collections.zig to avoid mismatch!
    var is_comptime_dict = true;
    for (dict.keys) |key| {
        if (!helpers.isComptimeConstant(key)) {
            is_comptime_dict = false;
            break;
        }
    }
    if (is_comptime_dict) {
        for (dict.values) |value| {
            if (!helpers.isComptimeConstant(value)) {
                is_comptime_dict = false;
                break;
            }
        }
    }

    // Even if all constants, check type compatibility (matches collections.zig logic)
    if (is_comptime_dict and dict.values.len > 0) {
        const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            const tags_match = @as(std.meta.Tag(@TypeOf(first_type)), first_type) ==
                              @as(std.meta.Tag(@TypeOf(this_type)), this_type);
            const is_int_float_mix = (first_type == .int and this_type == .float) or
                                     (first_type == .float and this_type == .int);
            if (!tags_match and !is_int_float_mix) {
                // Mixed types → will use runtime path → NOT comptime!
                is_comptime_dict = false;
                break;
            }
        }
    }

    const needs_cleanup = try needsValueCleanup(self, dict, is_comptime_dict);
    const alloc_name = getAllocName(self);

    // If needs value cleanup, free all string values before deinit
    if (needs_cleanup) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {{\n", .{});
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var iter = {s}.valueIterator();\n", .{var_name});
        try self.emitIndent();
        try self.emit("while (iter.next()) |value| {\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{s}.free(value.*);\n", .{alloc_name});
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{s}.deinit();\n", .{var_name});
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    } else {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {s}.deinit();\n", .{var_name});
    }
}

/// Add defer cleanup for allocated strings (upper/lower/replace/sorted/reversed)
pub fn emitAllocatedStringDefer(self: *NativeCodegen, var_name: []const u8) CodegenError!void {
    const alloc_name = getAllocName(self);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("defer {s}.free({s});\n", .{ alloc_name, var_name });
}

/// Emit all appropriate defer cleanups based on assignment properties
pub fn emitDeferCleanups(
    self: *NativeCodegen,
    var_name: []const u8,
    is_first_assignment: bool,
    is_arraylist: bool,
    is_listcomp: bool,
    is_dict: bool,
    is_allocated_string: bool,
    assign_value: ast.Node,
) CodegenError!void {
    // Add defer cleanup for ArrayLists (only on first assignment)
    if (is_first_assignment and is_arraylist) {
        try emitArrayListDefer(self, var_name);
    }

    // Add defer cleanup for list comprehensions (return slices, not ArrayLists)
    if (is_first_assignment and is_listcomp) {
        try emitListCompDefer(self, var_name);
    }

    // Add defer cleanup for dicts (only on first assignment)
    if (is_first_assignment and is_dict) {
        try emitDictDefer(self, var_name, assign_value);
    }

    // Add defer cleanup for allocated strings (only on first assignment)
    if (is_first_assignment and is_allocated_string) {
        try emitAllocatedStringDefer(self, var_name);
    }
}
