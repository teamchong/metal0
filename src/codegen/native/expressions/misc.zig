/// Miscellaneous expression code generation (tuple, attribute, subscript)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const subscript_mod = @import("subscript.zig");

/// Generate tuple literal as Zig struct with named fields
/// Uses named field syntax (.{ .@"0" = elem1, .@"1" = elem2 }) for compatibility
/// with declared tuple return types like struct { @"0": T, @"1": U }
pub fn genTuple(self: *NativeCodegen, tuple: ast.Node.Tuple) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Empty tuples become empty struct
    if (tuple.elts.len == 0) {
        try self.emit(".{}");
        return;
    }

    // Non-empty tuples: .{ .@"0" = elem1, .@"1" = elem2 }
    try self.emit(".{ ");

    for (tuple.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");
        // Use named field syntax for struct compatibility
        try self.output.writer(self.allocator).print(".@\"{d}\" = ", .{i});
        try genExpr(self, elem);
    }

    try self.emit(" }");
}

/// Generate array/dict subscript with tuple support (a[b])
/// Wraps subscript_mod.genSubscript but adds tuple indexing support
pub fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Check if this is tuple indexing (only for index, not slice)
    if (subscript.slice == .index) {
        const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

        if (value_type == .tuple) {
            // Tuple indexing: t[0] -> t.@"0"
            // Only constant indices supported for tuples
            if (subscript.slice.index.* == .constant and subscript.slice.index.constant.value == .int) {
                const index = subscript.slice.index.constant.value.int;
                try genExpr(self, subscript.value.*);
                try self.output.writer(self.allocator).print(".@\"{d}\"", .{index});
            } else {
                // Non-constant tuple index - error
                try self.emit("@compileError(\"Tuple indexing requires constant index\")");
            }
            return;
        }
    }

    // Delegate to subscript module for all other cases
    try subscript_mod.genSubscript(self, subscript);
}

/// Generate attribute access (obj.attr)
pub fn genAttribute(self: *NativeCodegen, attr: ast.Node.Attribute) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Check if this is a property method (decorated with @property)
    const is_property = try isPropertyMethod(self, attr);

    // Check if this is a known attribute or dynamic attribute
    const is_dynamic = try isDynamicAttribute(self, attr);

    if (is_property) {
        // Property method: call it automatically (Python @property semantics)
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try self.emit(attr.attr);
        try self.emit("()");
    } else if (is_dynamic) {
        // Dynamic attribute: use __dict__.get() and extract value
        // For now, assume int type. TODO: Add runtime type checking
        try genExpr(self, attr.value.*);
        try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.int", .{attr.attr});
    } else {
        // Known attribute: direct field access
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try self.emit(attr.attr);
    }
}

/// Check if attribute is a @property decorated method
fn isPropertyMethod(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Get object type - works for both names (c.x) and call results (C().x)
    const obj_type = try self.type_inferrer.inferExpr(attr.value.*);

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if this is a property method
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        if (info.property_methods.get(attr.attr)) |_| {
            return true; // This is a property method
        }
    }

    return false;
}

/// Check if attribute is dynamic (not in class fields)
fn isDynamicAttribute(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Only check for class instance attributes (self.attr or obj.attr)
    if (attr.value.* != .name) return false;

    const obj_name = attr.value.name.id;

    // Get object type
    const obj_type = try self.type_inferrer.inferExpr(attr.value.*);

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if class has this field
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        // Check if field exists in class
        if (info.fields.get(attr.attr)) |_| {
            return false; // Known field
        }
    }

    // Check for special module attributes (sys.platform, etc.)
    if (std.mem.eql(u8, obj_name, "sys")) {
        return false; // Module attributes are not dynamic
    }

    // Unknown field - dynamic attribute
    return true;
}
