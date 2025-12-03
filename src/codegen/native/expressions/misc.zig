/// Miscellaneous expression code generation (tuple, attribute, subscript)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const subscript_mod = @import("subscript.zig");
const zig_keywords = @import("zig_keywords");
const expressions_mod = @import("../expressions.zig");
const producesBlockExpression = expressions_mod.producesBlockExpression;
const self_analyzer = @import("../statements/functions/self_analyzer.zig");
const UnittestAssertions = self_analyzer.unittest_assertion_methods;

const FloatClassMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "fromhex", "runtime.floatFromHex" },
    .{ "hex", "runtime.floatToHex" },
    .{ "__getformat__", "runtime.floatGetFormat" },
});

const PathProperties = std.StaticStringMap(void).initComptime(.{
    .{ "parent", {} }, .{ "stem", {} }, .{ "suffix", {} }, .{ "name", {} },
});

/// Generate tuple literal as Zig anonymous struct
/// Always uses anonymous tuple syntax (.{ elem1, elem2 }) for type compatibility
/// This matches the type inference which generates struct types for tuples
pub fn genTuple(self: *NativeCodegen, tuple: ast.Node.Tuple) CodegenError!void {
    const genExpr = expressions_mod.genExpr;

    // Empty tuples become empty struct
    if (tuple.elts.len == 0) {
        try self.emit(".{}");
        return;
    }

    // Always generate anonymous tuple syntax for consistency with type inference
    // Type inference generates struct types: struct { @"0": T, @"1": T, ... }
    // So we must generate struct literals: .{ elem1, elem2, ... }
    try self.emit(".{ ");
    for (tuple.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");
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
        const value_type_tag = @as(std.meta.Tag(@TypeOf(value_type)), value_type);

        if (value_type_tag == .tuple) {
            // Tuple indexing: t[0] -> t.@"0" (field access for Zig tuples)
            // Only constant indices supported for tuples
            if (subscript.slice.index.* == .constant and subscript.slice.index.constant.value == .int) {
                const index = subscript.slice.index.constant.value.int;

                // Check if value produces a block expression - need to wrap
                const base_is_block = producesBlockExpression(subscript.value.*);
                if (base_is_block) {
                    // Wrap in block to allow field access on block result
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.output.writer(self.allocator).print("sub_{d}: {{ const __base = ", .{label_id});
                    try genExpr(self, subscript.value.*);
                    try self.output.writer(self.allocator).print("; break :sub_{d} __base.@\"{d}\"; }}", .{ label_id, index });
                } else {
                    // Direct field access
                    try genExpr(self, subscript.value.*);
                    try self.output.writer(self.allocator).print(".@\"{d}\"", .{index});
                }
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
    const genExpr = expressions_mod.genExpr;

    // Handle bool.real and bool.imag (True.real=1, True.imag=0, False.real=0, False.imag=0)
    // Python: bool inherits from int, so True/False have .real and .imag attributes
    if (attr.value.* == .constant and attr.value.constant.value == .bool) {
        const bool_val = attr.value.constant.value.bool;
        if (std.mem.eql(u8, attr.attr, "real")) {
            // True.real = 1, False.real = 0
            try self.emit(if (bool_val) "1" else "0");
            return;
        }
        if (std.mem.eql(u8, attr.attr, "imag")) {
            // True.imag = 0, False.imag = 0
            try self.emit("0");
            return;
        }
    }

    // Handle int.real and int.imag (e.g., (5).real = 5, (5).imag = 0)
    if (attr.value.* == .constant and attr.value.constant.value == .int) {
        if (std.mem.eql(u8, attr.attr, "real")) {
            // int.real = int value itself
            try genExpr(self, attr.value.*);
            return;
        }
        if (std.mem.eql(u8, attr.attr, "imag")) {
            // int.imag = 0
            try self.emit("0");
            return;
        }
    }

    // Check if value produces a block expression - need to wrap in temp variable
    // Because Zig doesn't allow field access on block expressions: blk:{}.field is invalid
    // Wrap in parentheses to prevent "label:" from being parsed as named argument when used in fn calls
    if (producesBlockExpression(attr.value.*)) {
        const attr_label_id = self.block_label_counter;
        self.block_label_counter += 1;
        try self.emitFmt("(attr_{d}: {{ const __obj = ", .{attr_label_id});
        try genExpr(self, attr.value.*);
        try self.emitFmt("; break :attr_{d} __obj.", .{attr_label_id});
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        try self.emit("; })");
        return;
    }

    // Check if this is a module attribute access (e.g., string.ascii_lowercase, math.pi)
    if (attr.value.* == .name) {
        const module_name = attr.value.name.id;
        const attr_name = attr.attr;

        // Handle builtin type class methods (int.__new__, float.fromhex, float.hex, etc.)
        if (std.mem.eql(u8, module_name, "int")) {
            if (std.mem.eql(u8, attr_name, "__new__")) {
                // int.__new__(cls, value) - creates new int subclass instance
                try self.emit("runtime.int__new__");
                return;
            }
        }

        if (std.mem.eql(u8, module_name, "float")) {
            if (FloatClassMethods.get(attr_name)) |runtime_func| {
                try self.emit(runtime_func);
                return;
            }
        }

        // Try module attribute dispatch FIRST (handles string.*, math.*, sys.*, etc.)
        // This correctly handles constants like math.pi, math.e which need inline values
        const module_functions = @import("../dispatch/module_functions.zig");
        // Create a fake call with no args to use the module dispatcher
        const empty_args: []ast.Node = &[_]ast.Node{};
        const fake_call = ast.Node.Call{
            .func = attr.value,
            .args = empty_args,
            .keyword_args = &[_]ast.Node.KeywordArg{},
        };

        // Track output length before dispatch to detect if anything was emitted
        const output_before = self.output.items.len;
        if (module_functions.tryDispatch(self, module_name, attr_name, fake_call) catch false) {
            // Only return if something was actually emitted
            // Some handlers check args.len == 0 and return early without emitting
            if (self.output.items.len > output_before) {
                return;
            }
        }

        // Check if this module is imported (fallback for function references)
        if (self.imported_modules.contains(module_name)) {
            // Check if this is a runtime module or a compiled Python module
            const is_runtime_module = if (self.import_registry.lookup(module_name)) |info|
                info.strategy == .zig_runtime or info.strategy == .c_library
            else
                false;

            if (is_runtime_module) {
                // For runtime module function references (used as values, not calls),
                // emit a reference to the runtime function
                // e.g., copy.copy -> &runtime.copy.copy, zlib.compress -> &runtime.zlib.compress
                try self.emit("&runtime.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
                try self.emit(".");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            } else {
                // For compiled Python modules, reference directly
                // e.g., _py_abc.ABCMeta -> _py_abc.ABCMeta (module @import gives direct access)
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
                try self.emit(".");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            }
            return;
        }
    }

    // Check if this is a file property access
    const value_type = try self.type_inferrer.inferExpr(attr.value.*);
    if (value_type == .file) {
        if (std.mem.eql(u8, attr.attr, "closed")) {
            // File.closed property - call getClosed helper
            try self.emit("runtime.PyFile.getClosed(");
            try genExpr(self, attr.value.*);
            try self.emit(")");
            return;
        }
    }

    // Check if this is a Path property access using type inference
    if (value_type == .path) {
        if (PathProperties.has(attr.attr)) {
            try genExpr(self, attr.value.*);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("()"); // Call as method in Zig
            return;
        }
    }

    // Legacy check for Path.parent access (Python property -> Zig method)
    if (isPathProperty(attr)) {
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        try self.emit("()"); // Call as method in Zig
        return;
    }

    // Check if this is a property method (decorated with @property)
    const is_property = try isPropertyMethod(self, attr);

    // Check if this is a known attribute or dynamic attribute
    const is_dynamic = try isDynamicAttribute(self, attr);

    // Check if this is a unittest assertion method reference (e.g., eq = self.assertEqual)
    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
        if (UnittestAssertions.has(attr.attr)) {
            try self.emit("runtime.unittest.");
            try self.emit(attr.attr);
            return;
        }

        // Check if this is a class-level type attribute reference (e.g., int_class = self.int_class)
        // Type attributes are static functions, so we return a function pointer via @This()
        if (self.current_class_name) |class_name| {
            const type_attr_key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, attr.attr }) catch null;
            if (type_attr_key) |key| {
                if (self.class_type_attrs.get(key)) |_| {
                    // Return a reference to the static function: @This().attr_name
                    try self.emit("@This().");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                    return;
                }
            }
        }
    }

    // For nested class instances (heap-allocated), x is already a pointer (*ClassName)
    // Zig auto-dereferences for field access on pointers, so x.val works directly

    if (is_property) {
        // Property method: call it automatically (Python @property semantics)
        // Check if there's a getter function name to use (for property() assignments)
        const getter_name = try getPropertyGetter(self, attr);
        try genExpr(self, attr.value.*);
        try self.emit(".");
        if (getter_name) |gn| {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), gn);
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        }
        try self.emit("()");
    } else if (is_dynamic) {
        // Special case: __dict__ attribute is the dict itself, not a key in the dict
        if (std.mem.eql(u8, attr.attr, "__dict__")) {
            try genExpr(self, attr.value.*);
            try self.emit(".__dict__");
        } else {
            // Dynamic attribute: use __dict__.get() and extract value
            // For now, assume int type. TODO: Add runtime type checking
            try genExpr(self, attr.value.*);
            try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.int", .{attr.attr});
        }
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
    if (PathProperties.has(attr.attr)) {
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

/// Get the getter function name for a property (if it was defined via property() call)
fn getPropertyGetter(self: *NativeCodegen, attr: ast.Node.Attribute) !?[]const u8 {
    // Get object type
    const obj_type = try self.type_inferrer.inferExpr(attr.value.*);
    if (obj_type != .class_instance) return null;

    const class_name = obj_type.class_instance;

    // Check if there's a getter function name registered
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        if (info.property_getters.get(attr.attr)) |getter_name| {
            return getter_name;
        }
    }

    return null;
}

/// Check if attribute is dynamic (not in class fields)
fn isDynamicAttribute(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Only check for class instance attributes (self.attr or obj.attr)
    if (attr.value.* != .name) return false;

    const obj_name = attr.value.name.id;

    // Get object type - first try type inferrer, then nested_class_instances
    var obj_type = try self.type_inferrer.inferExpr(attr.value.*);

    // If type is unknown, check nested_class_instances
    if (obj_type == .unknown) {
        if (self.nested_class_instances.get(obj_name)) |class_name| {
            obj_type = .{ .class_instance = class_name };
        }
    }

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if class has this field (including inherited fields)
    const has_field = blk: {
        // Check own class fields
        if (self.type_inferrer.class_fields.get(class_name)) |info| {
            if (info.fields.get(attr.attr)) |_| {
                break :blk true;
            }
        }
        // Check parent class fields for nested classes
        if (self.nested_class_bases.get(class_name)) |parent_name| {
            if (self.type_inferrer.class_fields.get(parent_name)) |parent_info| {
                if (parent_info.fields.get(attr.attr)) |_| {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };
    if (has_field) {
        return false; // Known field (own or inherited)
    }

    // Check if this is a class-level type attribute (e.g., int_class = int)
    const type_attr_key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, attr.attr }) catch return true;
    if (self.class_type_attrs.get(type_attr_key)) |_| {
        return false; // Known type attribute (a method)
    }

    // Check for special module attributes (sys.platform, etc.)
    if (std.mem.eql(u8, obj_name, "sys")) {
        return false; // Module attributes are not dynamic
    }

    // Check for unittest assertion methods (self.assertEqual, etc.)
    if (UnittestAssertions.has(attr.attr)) return false;

    // Unknown field - dynamic attribute
    return true;
}
