/// Return statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Check if a return value is a tail-recursive call to the current function
/// A tail call is: return func_name(args) where func_name == current function
fn isTailRecursiveCall(self: *NativeCodegen, value: ast.Node) ?ast.Node.Call {
    // Must be inside a function
    const current_func = self.current_function_name orelse return null;

    // Must be a call expression
    if (value != .call) return null;
    const call = value.call;

    // Function must be a simple name (not attribute/method call)
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Must be calling the current function
    if (!std.mem.eql(u8, func_name, current_func)) return null;

    return call;
}

/// Magic method return conversion info
const MagicMethodConversion = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Get conversion wrapper for magic method return values
/// Some dunder methods have fixed return types that require conversion
fn getMagicMethodConversion(method_name: []const u8) ?MagicMethodConversion {
    const converters = std.StaticStringMap(MagicMethodConversion).initComptime(.{
        // Python 3: __bool__ must return exactly bool, not converted from other types
        .{ "__bool__", MagicMethodConversion{ .prefix = "runtime.validateBoolReturn(", .suffix = ")" } },
        // Use runtime.pyToInt for __len__/__hash__/__int__/__index__ to handle both int and PyValue
        .{ "__len__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__hash__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__int__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__index__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        // Python 3: __float__ must return exactly float, not int - raises TypeError otherwise
        .{ "__float__", MagicMethodConversion{ .prefix = "runtime.validateFloatReturn(", .suffix = ")" } },
    });
    return converters.get(method_name);
}

/// Comparison magic methods that return bool
const ComparisonMagicMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__eq__", {} },
    .{ "__ne__", {} },
    .{ "__lt__", {} },
    .{ "__le__", {} },
    .{ "__gt__", {} },
    .{ "__ge__", {} },
});

/// Generate return statement with tail-call optimization
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    // Emit pending discards BEFORE the return statement
    // This handles unused local variables in closures that return early
    // e.g., def f(): msg = "..."; return self.assertRaisesRegex(...) -> msg unused
    try self.emitPendingDiscards();

    // Mark control flow as terminated on any exit path
    defer self.control_flow_terminated = true;

    // Return inside defer block is not allowed in Zig
    // Just skip the return - defer cleanup will still run
    if (self.inside_defer and !self.inside_finally_block) {
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.write("// return inside defer - skipped (cleanup continues)\n");
        const output = b.getBody();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Return inside finally block - use break to exit the labeled block
    // The actual return will happen after finally block cleanup
    if (self.inside_finally_block) {
        const b = try self.getBuilder();
        try b.writeIndent();
        // Store the return value and break out of finally block
        // The return will be handled after the finally block
        try b.writeFmt("break :__finally_blk_{d} null; // return from finally\n", .{self.current_finally_id});
        const output = b.getBody();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE return
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        const b = try self.getBuilder();

        // Store return value first (to avoid multiple evaluation)
        if (ret.value) |value| {
            const val = try self.captureExpr(value.*);
            try b.writeIndent();
            try b.write("const __return_value = ");
            try b.emitValue(val, .{});
            try b.write(";\n");
        }

        const output1 = b.getBody();
        try self.output.appendSlice(self.allocator, output1);

        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();

        // Now emit the actual return
        const b2 = try self.getBuilder();
        try b2.writeIndent();
        if (ret.value != null) {
            try b2.write("return __return_value;\n");
        } else {
            try b2.write("return;\n");
        }
        const output2 = b2.getBody();
        try self.output.appendSlice(self.allocator, output2);
        return;
    }

    const b = try self.getBuilder();
    try b.writeIndent();

    if (ret.value) |value| {
        // Check if returning NotImplemented from a comparison method
        // In Python, comparison methods can return NotImplemented to signal fallback
        // But in our compiled code, these methods return bool, so convert to false
        if (value.* == .name and std.mem.eql(u8, value.name.id, "NotImplemented")) {
            if (self.current_function_name) |fn_name| {
                if (ComparisonMagicMethods.has(fn_name)) {
                    try b.write("return false;\n");
                    const output = b.getBody();
                    try self.output.appendSlice(self.allocator, output);
                    return;
                }
            }
        }

        // Check if returning a pre-generated closure (e.g., return with_metaclass where with_metaclass is a nested function)
        if (value.* == .name) {
            const name = value.name.id;
            if (self.pending_closure_types.get(name)) |type_name| {
                // Return an instance of the pre-generated closure type
                try b.writeFmt("return {s}{{}};\n", .{type_name});
                const output = b.getBody();
                try self.output.appendSlice(self.allocator, output);
                return;
            }
        }

        // Check for tail-recursive call
        if (isTailRecursiveCall(self, value.*)) |call| {
            // Emit: return @call(.always_tail, func_name, .{args})
            try b.write("return @call(.always_tail, ");
            try b.write(call.func.name.id);
            try b.write(", .{");

            // Generate arguments
            for (call.args, 0..) |arg, i| {
                if (i > 0) try b.write(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValue(arg_val, .{});
            }

            try b.write("});\n");
            const output = b.getBody();
            try self.output.appendSlice(self.allocator, output);
            return;
        }

        // Normal return - check if inside a magic method that needs conversion
        try b.write("return ");

        // Check if returning self from a method (with either *@This() or *const @This())
        // When method signature returns !@This() and we return self,
        // we need: return __self.*; (dereference the pointer)
        // This applies to both mutable (*@This()) and immutable (*const @This()) methods
        const is_self_return = self.current_class_name != null and
            value.* == .name and
            std.mem.eql(u8, value.name.id, "self");
        // For methods that return self, always dereference when inside a nested method
        // (where self is renamed to __self) or when method_self_is_mutable
        const needs_self_deref = is_self_return and (self.method_self_is_mutable or self.method_nesting_depth > 0);

        // Check if we're inside a magic method that needs return value conversion
        const conversion = if (self.current_function_name) |fn_name|
            getMagicMethodConversion(fn_name)
        else
            null;

        // Magic method conversion ALWAYS takes precedence (e.g., __bool__ must validate return type)
        if (conversion) |conv| {
            try b.write(conv.prefix);
            if (needs_self_deref) {
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
                if (current_class_is_nested) {
                    try b.write(self_name);
                } else {
                    try b.writeFmt("{s}.*", .{self_name});
                }
            } else {
                const val = try self.captureExpr(value.*);
                try b.emitValue(val, .{});
            }
            try b.write(conv.suffix);
        } else if (needs_self_deref) {
            // For nested classes, return the pointer directly
            // since init() returns *@This() and methods returning self also return *@This()
            // For top-level classes, dereference to return @This() value
            const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
            const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
            if (current_class_is_nested) {
                // Nested class: return pointer directly
                try b.write(self_name);
            } else {
                // Top-level class: dereference to get value
                try b.writeFmt("{s}.*", .{self_name});
            }
        } else {
            // Two-Flow: Box return values when function returns PyValue
            // This handles isinstance narrowing where local vars become raw types
            // inside if blocks but function still returns PyValue
            if (self.current_function_returns_pyvalue) {
                const val = try self.captureExpr(value.*);
                try b.write("runtime.PyValue.from(");
                try b.emitValue(val, .{});
                try b.write(")");
            } else {
                const val = try self.captureExpr(value.*);
                try b.emitValue(val, .{});
            }
        }
    } else {
        try b.write("return ");
    }
    try b.write(";\n");

    const output = b.getBody();
    try self.output.appendSlice(self.allocator, output);
}
