/// Class field generation from __init__ and other methods
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const signature = @import("../signature.zig");
const zig_keywords = @import("zig_keywords");

/// Generate struct fields from __init__ method
pub fn genClassFields(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef) CodegenError!void {
    try genClassFieldsImpl(self, class_name, init);

    // Add __dict__ for dynamic attributes (always enabled)
    try self.emit("\n");
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");
}

/// Generate struct fields from a method without adding __dict__ (for additional methods like setUp)
/// Fields are declared with default values since they're set at runtime, not in init()
pub fn genClassFieldsNoDict(self: *NativeCodegen, class_name: []const u8, method: ast.Node.FunctionDef) CodegenError!void {
    try genClassFieldsImplWithDefaults(self, class_name, method);
}

/// Implementation of field extraction (shared by genClassFields and genClassFieldsNoDict)
fn genClassFieldsImpl(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef) CodegenError!void {
    try genClassFieldsCore(self, class_name, init, false);
}

/// Implementation of field extraction with default values (for setUp fields)
fn genClassFieldsImplWithDefaults(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef) CodegenError!void {
    try genClassFieldsCore(self, class_name, init, true);
}

/// Core implementation of field extraction
fn genClassFieldsCore(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef, with_defaults: bool) CodegenError!void {
    // Get constructor arg types from type inferrer (collected from call sites)
    const constructor_arg_types = self.type_inferrer.class_constructor_args.get(class_name);

    // Temporarily register constructor parameter types so expressions like `x + y` can be inferred
    // Priority: 1) annotation, 2) widened keyword arg type, 3) positional constructor arg type
    for (init.args, 0..) |arg, param_idx| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        // Method 1: Use type annotation if available
        var param_type = signature.pythonTypeToNativeType(arg.type_annotation);

        // Method 2: Try widened keyword arg type (stored as "ClassName.param_name")
        if (param_type == .unknown) {
            var kwarg_key_buf: [256]u8 = undefined;
            const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, arg.name }) catch null;
            if (kwarg_key) |key| {
                if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
                    param_type = kwarg_type;
                }
            }
        }

        // Method 3: Fall back to positional constructor arg type (only if no kwarg type found)
        if (param_type == .unknown) {
            if (constructor_arg_types) |arg_types| {
                const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                if (arg_idx < arg_types.len) {
                    param_type = arg_types[arg_idx];
                }
            }
        }

        if (param_type != .unknown) {
            self.type_inferrer.var_types.put(arg.name, param_type) catch {};
        }
    }

    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            // Check if target is self.attribute
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    // Found field: self.x = y
                    const field_name = attr.attr;

                    // Determine field type by inferring the value's type
                    var inferred = try self.type_inferrer.inferExpr(assign.value.*);
                    std.debug.print("DEBUG class_fields: field={s} inferred={}\n", .{ field_name, inferred });

                    // If unknown and value is a parameter reference, try different methods
                    if (inferred == .unknown and assign.value.* == .name) {
                        const param_name = assign.value.name.id;

                        // Find the parameter index and check annotation
                        for (init.args) |arg| {
                            if (std.mem.eql(u8, arg.name, param_name)) {
                                // Method 1: Use type annotation if available
                                inferred = signature.pythonTypeToNativeType(arg.type_annotation);

                                // Method 2: Try keyword arg lookup (has proper type widening)
                                // Stored as "ClassName.param_name" in var_types, widened across all calls
                                if (inferred == .unknown) {
                                    var kwarg_key_buf: [256]u8 = undefined;
                                    const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, arg.name }) catch null;
                                    if (kwarg_key) |key| {
                                        if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
                                            inferred = kwarg_type;
                                        }
                                    }
                                }
                                // Method 2's result is final - no fallback to positional args
                                // This ensures widened types (including .unknown from incompatible tuples) are preserved
                                break;
                            }
                        }
                    }

                    // Use nativeTypeToZigType for proper type conversion (handles dict, list, etc.)
                    // For unknown types, default to i64 (consistent with inferParamType fallback)
                    const field_type_str = if (inferred == .unknown)
                        try self.allocator.dupe(u8, "i64")
                    else
                        try self.nativeTypeToZigType(inferred);
                    defer self.allocator.free(field_type_str);

                    try self.emitIndent();
                    // Escape field name if it's a Zig keyword (e.g., "test")
                    const writer = self.output.writer(self.allocator);
                    try zig_keywords.writeEscapedIdent(writer, field_name);
                    if (with_defaults) {
                        // Add default value for fields set at runtime (e.g., setUp)
                        const default_val = switch (inferred) {
                            .int, .usize => "0",
                            .float => "0.0",
                            .bool => "false",
                            .string => "\"\"",
                            .dict, .list, .set => ".{}", // Empty struct init
                            else => "undefined",
                        };
                        try writer.print(": {s} = {s},\n", .{ field_type_str, default_val });
                    } else {
                        try writer.print(": {s},\n", .{field_type_str});
                    }
                }
            }
        }
    }
}

/// Generate struct fields for class-level attributes (not in __init__)
/// e.g., class Foo:
///           candidates = set1 + set2  # This is a class attribute
pub fn genClassLevelFields(self: *NativeCodegen, class_body: []const ast.Node) CodegenError!void {
    for (class_body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            // Class-level assignments have simple name targets (not self.attr)
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const field_name = assign.targets[0].name.id;

                // Skip type references (int_class = int) - these are handled as methods
                if (assign.value.* == .name) {
                    const type_name = assign.value.name.id;
                    if (std.mem.eql(u8, type_name, "int") or
                        std.mem.eql(u8, type_name, "float") or
                        std.mem.eql(u8, type_name, "str") or
                        std.mem.eql(u8, type_name, "bool") or
                        std.mem.eql(u8, type_name, "list") or
                        std.mem.eql(u8, type_name, "dict"))
                    {
                        continue;
                    }
                }

                // Skip None assignments (__bool__ = None, __len__ = None)
                if (assign.value.* == .constant and assign.value.constant.value == .none) {
                    continue;
                }

                // Infer type from value
                const inferred = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;

                // Use nativeTypeToZigType for proper type conversion
                // For unknown types, use runtime.PyValue for dynamic dispatch
                const field_type_str = if (inferred == .unknown)
                    try self.allocator.dupe(u8, "runtime.PyValue")
                else
                    try self.nativeTypeToZigType(inferred);
                defer self.allocator.free(field_type_str);

                try self.emitIndent();
                try self.emit("// Class-level attribute\n");
                try self.emitIndent();
                const writer = self.output.writer(self.allocator);
                try zig_keywords.writeEscapedIdent(writer, field_name);
                // Class-level attributes need default initialization
                // Use .{} for structs/arrays/lists, or specific default for primitives
                const default_val = switch (inferred) {
                    .int, .usize => "0",
                    .float => "0.0",
                    .bool => "false",
                    .string => "\"\"",
                    else => ".{}",
                };
                try writer.print(": {s} = {s},\n", .{ field_type_str, default_val });
            }
        }
    }
}

/// Check if a parameter has runtime type checking (isinstance followed by raise TypeError)
/// Pattern: if not isinstance(param, type): raise TypeError(...)
/// Such parameters should use anytype to accept any value and check at runtime
fn hasRuntimeTypeCheck(init: ast.Node.FunctionDef, param_name: []const u8) bool {
    for (init.body) |stmt| {
        // Look for: if not isinstance(param, type): raise TypeError
        if (stmt == .if_stmt) {
            const if_test = stmt.if_stmt.condition.*;
            // Check for "not isinstance(param, type)" or "not isint(param)" patterns
            if (if_test == .unaryop and if_test.unaryop.op == .Not) {
                const operand = if_test.unaryop.operand.*;
                if (operand == .call) {
                    const func = operand.call.func.*;
                    if (func == .name) {
                        const func_name = func.name.id;
                        // isinstance(x, int) or isint(x) or similar type check functions
                        if (std.mem.eql(u8, func_name, "isinstance") or
                            std.mem.eql(u8, func_name, "isint") or
                            std.mem.eql(u8, func_name, "isnum") or
                            std.mem.eql(u8, func_name, "isRat"))
                        {
                            // Check if first arg matches param_name
                            if (operand.call.args.len > 0) {
                                if (operand.call.args[0] == .name and
                                    std.mem.eql(u8, operand.call.args[0].name.id, param_name))
                                {
                                    // Check if body contains raise TypeError
                                    for (stmt.if_stmt.body) |body_stmt| {
                                        if (body_stmt == .raise_stmt) {
                                            return true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Infer parameter type by looking at how it's used in __init__ or constructor call args
pub fn inferParamType(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef, param_name: []const u8) ![]const u8 {
    // Check if parameter has runtime type checking - use anytype to accept any value
    // Pattern: if not isinstance(param, int): raise TypeError(...)
    if (hasRuntimeTypeCheck(init, param_name)) {
        return try self.allocator.dupe(u8, "anytype");
    }

    // Get constructor arg types from type inferrer
    const constructor_arg_types = self.type_inferrer.class_constructor_args.get(class_name);

    // Find parameter index (excluding 'self')
    var param_idx: usize = 0;
    for (init.args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg.name, param_name)) {
            // Subtract 1 to account for 'self' parameter
            param_idx = if (i > 0) i - 1 else 0;
            break;
        }
    }

    // Method 1: Try to use constructor call arg types
    if (constructor_arg_types) |arg_types| {
        if (param_idx < arg_types.len) {
            const inferred = arg_types[param_idx];
            // For unknown types, default to i64 (consistent with fallback)
            if (inferred == .unknown) {
                return try self.allocator.dupe(u8, "i64");
            }
            return try self.nativeTypeToZigType(inferred);
        }
    }

    // Method 2: Look for assignments like self.field = param_name
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.value.* == .name and std.mem.eql(u8, assign.value.name.id, param_name)) {
                // Found usage - infer type from the value
                const inferred = try self.type_inferrer.inferExpr(assign.value.*);
                // For unknown types, default to i64 (consistent with fallback)
                if (inferred == .unknown) {
                    return try self.allocator.dupe(u8, "i64");
                }
                return try self.nativeTypeToZigType(inferred);
            }
        }
    }
    // Fallback: use i64 as default (must allocate since caller frees)
    return try self.allocator.dupe(u8, "i64");
}
