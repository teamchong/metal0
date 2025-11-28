/// Miscellaneous expression code generation (tuple, attribute, subscript)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const subscript_mod = @import("subscript.zig");
const zig_keywords = @import("zig_keywords");

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
    const parent_module = @import("../expressions.zig");
    const genExpr = parent_module.genExpr;

    // Check if this is a module attribute access (e.g., string.ascii_lowercase, math.pi)
    if (attr.value.* == .name) {
        const module_name = attr.value.name.id;
        const attr_name = attr.attr;

        // Try module attribute dispatch (handles string.*, math.*, sys.*, etc.)
        const module_functions = @import("../dispatch/module_functions.zig");
        // Create a fake call with no args to use the module dispatcher
        const empty_args: []ast.Node = &[_]ast.Node{};
        const fake_call = ast.Node.Call{
            .func = attr.value,
            .args = empty_args,
            .keyword_args = &[_]ast.Node.KeywordArg{},
        };
        if (module_functions.tryDispatch(self, module_name, attr_name, fake_call) catch false) {
            return;
        }
    }

    // Check if this is a numpy array property access
    const value_type = try self.type_inferrer.inferExpr(attr.value.*);
    if (value_type == .numpy_array) {
        // NumPy array properties: .shape, .size, .T, .ndim, .dtype
        if (std.mem.eql(u8, attr.attr, "shape")) {
            // arr.shape -> extract array and get shape
            try self.emit("(try runtime.numpy_array.extractArray(");
            try genExpr(self, attr.value.*);
            try self.emit(")).shape");
            return;
        } else if (std.mem.eql(u8, attr.attr, "size")) {
            try self.emit("(try runtime.numpy_array.extractArray(");
            try genExpr(self, attr.value.*);
            try self.emit(")).size");
            return;
        } else if (std.mem.eql(u8, attr.attr, "ndim")) {
            try self.emit("(try runtime.numpy_array.extractArray(");
            try genExpr(self, attr.value.*);
            try self.emit(")).shape.len");
            return;
        } else if (std.mem.eql(u8, attr.attr, "T")) {
            // Transpose: arr.T
            try self.emit("try numpy.transpose(");
            try genExpr(self, attr.value.*);
            try self.emit(", allocator)");
            return;
        } else if (std.mem.eql(u8, attr.attr, "data")) {
            try self.emit("(try runtime.numpy_array.extractArray(");
            try genExpr(self, attr.value.*);
            try self.emit(")).data");
            return;
        }
    }

    // Check if this is a Path property access using type inference
    if (value_type == .path) {
        // Path properties that need to be called as methods in Zig
        const path_properties = [_][]const u8{ "parent", "stem", "suffix", "name" };
        for (path_properties) |prop| {
            if (std.mem.eql(u8, attr.attr, prop)) {
                try genExpr(self, attr.value.*);
                try self.emit(".");
                try self.emit(attr.attr);
                try self.emit("()"); // Call as method in Zig
                return;
            }
        }
    }

    // Legacy check for Path.parent access (Python property -> Zig method)
    if (isPathProperty(attr)) {
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try self.emit(attr.attr);
        try self.emit("()"); // Call as method in Zig
        return;
    }

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
        // Escape attribute name if it's a Zig keyword (e.g., "test")
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
    }
}

/// Check if attribute access is on a Path object accessing a property-like method
/// In Python, Path.parent is a property; in Zig runtime, it's a method
fn isPathProperty(attr: ast.Node.Attribute) bool {
    // Path properties that need to be called as methods
    const path_properties = [_][]const u8{ "parent", "stem", "suffix", "name" };

    for (path_properties) |prop| {
        if (std.mem.eql(u8, attr.attr, prop)) {
            // Check if value is a Path() call or chained Path access
            if (attr.value.* == .call) {
                if (attr.value.call.func.* == .name) {
                    if (std.mem.eql(u8, attr.value.call.func.name.id, "Path")) {
                        return true;
                    }
                }
            }
            // Check for chained access like Path(...).parent.parent
            if (attr.value.* == .attribute) {
                return isPathProperty(attr.value.attribute);
            }
        }
    }
    return false;
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
