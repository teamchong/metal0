/// Class method generation (init, regular methods, inherited methods)
const std = @import("std");
const ast = @import("../../../../../../ast.zig");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("../../../../../../utils/hashmap_helper.zig");
const signature = @import("../signature.zig");
const class_fields = @import("class_fields.zig");
const allocator_analyzer = @import("../../allocator_analyzer.zig");

// Import from parent for methodMutatesSelf and genMethodBody
const body = @import("../body.zig");

/// Generate default init() method for classes without __init__
pub fn genDefaultInitMethod(self: *NativeCodegen, class_name: []const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init(allocator: std.mem.Allocator) {s} {{\n", .{class_name});
    self.indent();

    try self.emitIndent();
    try self.output.writer(self.allocator).print("return {s}{{\n", .{class_name});
    self.indent();

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.emit(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(allocator),\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__
pub fn genInitMethod(
    self: *NativeCodegen,
    class_name: []const u8,
    init: ast.Node.FunctionDef,
) CodegenError!void {
    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init(allocator: std.mem.Allocator", .{});

    // Parameters (skip 'self')
    for (init.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        try self.emit(", ");

        try self.output.writer(self.allocator).print("{s}: ", .{arg.name});

        // Type annotation: prefer type hints, fallback to inference
        if (arg.type_annotation) |_| {
            try self.emit(signature.pythonTypeToZig(arg.type_annotation));
        } else {
            const param_type = try class_fields.inferParamType(self, class_name, init, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);
        }
    }

    try self.output.writer(self.allocator).print(") {s} {{\n", .{class_name});
    self.indent();

    // Note: allocator is always used for __dict__ initialization, so no discard needed

    // Generate return statement with field initializers
    try self.emitIndent();
    try self.output.writer(self.allocator).print("return {s}{{\n", .{class_name});
    self.indent();

    // Extract field assignments from __init__ body
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    try self.emitIndent();
                    try self.output.writer(self.allocator).print(".{s} = ", .{field_name});
                    try self.genExpr(assign.value.*);
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.emit(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(allocator),\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate regular class methods (non-__init__)
pub fn genClassMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
) CodegenError!void {
    // Set current class name for super() support
    self.current_class_name = class.name;
    defer self.current_class_name = null;

    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;

            const mutates_self = body.methodMutatesSelf(method);
            const needs_allocator = allocator_analyzer.functionNeedsAllocator(method);
            try signature.genMethodSignature(self, class.name, method, mutates_self, needs_allocator);
            try body.genMethodBody(self, method);
        }
    }
}

/// Generate inherited methods from parent class
pub fn genInheritedMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    child_method_names: []const []const u8,
) CodegenError!void {
    for (parent.body) |parent_stmt| {
        if (parent_stmt == .function_def) {
            const parent_method = parent_stmt.function_def;
            if (std.mem.eql(u8, parent_method.name, "__init__")) continue;

            // Check if child overrides this method
            var is_overridden = false;
            for (child_method_names) |child_name| {
                if (std.mem.eql(u8, child_name, parent_method.name)) {
                    is_overridden = true;
                    break;
                }
            }

            if (!is_overridden) {
                // Copy parent method to child class
                const mutates_self = body.methodMutatesSelf(parent_method);
                const needs_allocator = allocator_analyzer.functionNeedsAllocator(parent_method);
                try signature.genMethodSignature(self, class.name, parent_method, mutates_self, needs_allocator);
                try body.genMethodBody(self, parent_method);
            }
        }
    }
}
