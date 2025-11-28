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

                    // If unknown and value is a parameter reference, try different methods
                    if (inferred == .unknown and assign.value.* == .name) {
                        const param_name = assign.value.name.id;

                        // Find the parameter index and check annotation
                        for (init.args, 0..) |arg, param_idx| {
                            if (std.mem.eql(u8, arg.name, param_name)) {
                                // Method 1: Use type annotation if available
                                inferred = signature.pythonTypeToNativeType(arg.type_annotation);

                                // Method 2: If still unknown, use constructor call arg types
                                if (inferred == .unknown) {
                                    if (constructor_arg_types) |arg_types| {
                                        // param_idx includes 'self', so subtract 1 for arg index
                                        const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                                        if (arg_idx < arg_types.len) {
                                            inferred = arg_types[arg_idx];
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }

                    // Use nativeTypeToZigType for proper type conversion (handles dict, list, etc.)
                    const field_type_str = try self.nativeTypeToZigType(inferred);
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

/// Infer parameter type by looking at how it's used in __init__ or constructor call args
pub fn inferParamType(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef, param_name: []const u8) ![]const u8 {
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
                return try self.nativeTypeToZigType(inferred);
            }
        }
    }
    // Fallback: use i64 as default (must allocate since caller frees)
    return try self.allocator.dupe(u8, "i64");
}
