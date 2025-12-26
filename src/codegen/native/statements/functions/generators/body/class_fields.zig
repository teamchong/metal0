/// Class field generation from __init__ and other methods
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const signature = @import("../signature.zig");
const zig_keywords = @import("utils.zig_keywords");
const type_traits = @import("../../../../../../analysis/traits/type_traits.zig");
const container_traits = @import("../../../../../../analysis/traits/container_traits.zig");
const builder_mod = @import("codegen.builder");

/// Generate struct fields from __init__ method
pub fn genClassFields(self: *NativeCodegen, class_name: []const u8, init: ast.Node.FunctionDef) CodegenError!void {
    try genClassFieldsImpl(self, class_name, init);

    // Add __dict__ for dynamic attributes (always enabled)
    const b = try self.getBuilder();
    try b.write("\n");
    try b.writeIndent();
    try b.write("// Dynamic attributes dictionary\n");
    try b.writeIndent();
    try b.write("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
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
        // This type is widened across ALL calls, so .unknown means incompatible types
        var found_kwarg_type = false;
        if (type_traits.isUnknown(param_type)) {
            var kwarg_key_buf: [256]u8 = undefined;
            const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, arg.name }) catch null;
            if (kwarg_key) |key| {
                if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
                    param_type = kwarg_type;
                    found_kwarg_type = true; // Widened type is authoritative, don't fall through
                }
            }
        }

        // Method 3: Fall back to positional constructor arg type (only if no kwarg type found)
        // Skip if Method 2 found a type (even .unknown) - widened types are authoritative
        if (!found_kwarg_type and type_traits.isUnknown(param_type)) {
            if (constructor_arg_types) |arg_types| {
                const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                if (arg_idx < arg_types.len) {
                    param_type = arg_types[arg_idx];
                }
            }
        }

        if (!type_traits.isUnknown(param_type)) {
            // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
            self.type_inferrer.putScopedVar(arg.name, param_type) catch {};
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

                    // Skip __dict__ - it's always added separately
                    if (std.mem.eql(u8, field_name, "__dict__")) continue;

                    // FIRST: Check if value is a parameter name - parameters shadow outer variables
                    // This must be checked BEFORE inferExpr to avoid picking up outer variables
                    // with the same name as parameters
                    var inferred: @import("../../../../../../analysis/native_types/core.zig").NativeType = .unknown;
                    var is_param_reference = false;
                    if (assign.value.* == .name) {
                        const value_name = assign.value.name.id;
                        for (init.args, 0..) |arg, param_idx| {
                            if (std.mem.eql(u8, arg.name, value_name)) {
                                is_param_reference = true;
                                // Value is a parameter - use parameter's type, not outer variable
                                // Try annotation first
                                inferred = signature.pythonTypeToNativeType(arg.type_annotation);
                                // Try keyword arg lookup
                                if (type_traits.isUnknown(inferred)) {
                                    var kwarg_key_buf: [256]u8 = undefined;
                                    const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, arg.name }) catch null;
                                    if (kwarg_key) |key| {
                                        if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
                                            inferred = kwarg_type;
                                        }
                                    }
                                }
                                // Try positional constructor arg
                                if (type_traits.isUnknown(inferred)) {
                                    if (constructor_arg_types) |arg_types| {
                                        const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                                        if (arg_idx < arg_types.len) {
                                            inferred = arg_types[arg_idx];
                                        }
                                    }
                                }
                                // Note: Keep inferred as .unknown if param type couldn't be determined
                                // This avoids picking up outer variables with the same name
                                break;
                            }
                        }
                    }

                    // If value wasn't a parameter reference, try general type inference
                    if (!is_param_reference) {
                        inferred = try self.type_inferrer.inferExpr(assign.value.*);
                    }

                    // Check if inferred type is a class instance of a nested class or self-referential
                    // Nested classes (defined inside this method) are not visible at struct scope
                    // Self-referential classes need pointer type (*@This()) since struct is incomplete
                    // So we use *runtime.PyObject for dynamic typing instead
                    var is_self_referential = false;
                    if (type_traits.isClassInstance(inferred)) {
                        const nested_class_name = inferred.class_instance;
                        // Check if this is a self-referential field (same class)
                        if (std.mem.eql(u8, nested_class_name, class_name)) {
                            is_self_referential = true;
                        }
                        // Check if this class is defined inside the current method body
                        else if (isNestedClassInBody(init.body, nested_class_name)) {
                            inferred = .unknown; // Force dynamic typing
                        }
                    }

                    // Use nativeTypeToZigType for proper type conversion (handles dict, list, etc.)
                    // For unknown types, use runtime.PyValue for dynamic typing
                    // For self-referential, use *@This() (pointer to self)
                    const field_type_str = if (is_self_referential)
                        try self.arena.allocator().dupe(u8, "*@This()")
                    else if (type_traits.isUnknown(inferred))
                        try self.arena.allocator().dupe(u8, "runtime.PyValue")
                    else
                        try self.nativeTypeToZigType(inferred);
                    defer self.allocator.free(field_type_str);

                    const b = try self.getBuilder();
                    try b.writeIndent();
                    // Escape field name if it's a Zig keyword (e.g., "test")
                    const writer = b.body.writer(b.allocator);
                    try zig_keywords.writeEscapedIdent(writer, field_name);
                    if (with_defaults) {
                        // Add default value for fields set at runtime (e.g., setUp)
                        const default_val = if (is_self_referential)
                            "undefined" // Self-referential pointer is undefined
                        else switch (inferred) {
                            .int, .usize => "0",
                            .float => "0.0",
                            .bool => "false",
                            .string => "\"\"",
                            // Zig 0.15: HashMap-based types (dict, set) can't use .{} for empty init
                            // - they require allocator. Use undefined and initialize in setUp/init.
                            // ArrayListUnmanaged (list) CAN use .{} for empty init.
                            .dict, .set => "undefined",
                            .list => ".{}",
                            else => "undefined",
                        };
                        try b.writeFmt(": {s} = {s},\n", .{ field_type_str, default_val });
                    } else {
                        try b.writeFmt(": {s},\n", .{field_type_str});
                    }
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
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
                const field_type_str = if (type_traits.isUnknown(inferred))
                    try self.arena.allocator().dupe(u8, "runtime.PyValue")
                else
                    try self.nativeTypeToZigType(inferred);
                defer self.allocator.free(field_type_str);

                const b = try self.getBuilder();
                try b.writeIndent();
                try b.write("// Class-level attribute\n");
                try b.writeIndent();
                const writer = b.body.writer(b.allocator);
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
                try b.writeFmt(": {s} = {s},\n", .{ field_type_str, default_val });
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
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
        return try self.arena.allocator().dupe(u8, "anytype");
    }

    // Method 1: Try widened keyword arg type FIRST (authoritative, stored as "ClassName.param_name")
    // This type is widened across ALL constructor calls, so .unknown means incompatible types
    var kwarg_key_buf: [256]u8 = undefined;
    const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, param_name }) catch null;
    if (kwarg_key) |key| {
        if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
            // Widened type is authoritative - if .unknown, use anytype for params
            if (type_traits.isUnknown(kwarg_type)) {
                return try self.arena.allocator().dupe(u8, "anytype");
            }
            return try self.nativeTypeToZigType(kwarg_type);
        }
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

    // Method 2: Try to use constructor call arg types (non-widened, last call only)
    if (constructor_arg_types) |arg_types| {
        if (param_idx < arg_types.len) {
            const inferred = arg_types[param_idx];
            // For unknown types, use anytype to accept any value
            if (type_traits.isUnknown(inferred)) {
                return try self.arena.allocator().dupe(u8, "anytype");
            }
            return try self.nativeTypeToZigType(inferred);
        }
    }

    // Method 3: Look for assignments like self.field = param_name
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.value.* == .name and std.mem.eql(u8, assign.value.name.id, param_name)) {
                // Found usage - infer type from the value
                const inferred = try self.type_inferrer.inferExpr(assign.value.*);
                // For unknown types, use anytype to accept any value
                if (type_traits.isUnknown(inferred)) {
                    return try self.arena.allocator().dupe(u8, "anytype");
                }
                return try self.nativeTypeToZigType(inferred);
            }
        }
    }
    // Fallback: use anytype for maximum flexibility (must allocate since caller frees)
    return try self.arena.allocator().dupe(u8, "anytype");
}

/// Check if a class with given name is defined inside the method body
/// This detects nested class definitions like:
///   def setUp(self):
///       class CustomHTMLCal(HTMLCalendar): ...
///       self.cal = CustomHTMLCal()
fn isNestedClassInBody(body: []const ast.Node, class_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .class_def => |cls| {
                if (std.mem.eql(u8, cls.name, class_name)) {
                    return true;
                }
            },
            // Also check inside control flow blocks (if/for/while/try)
            .if_stmt => |if_stmt| {
                if (isNestedClassInBody(if_stmt.body, class_name)) return true;
                if (isNestedClassInBody(if_stmt.else_body, class_name)) return true;
            },
            .for_stmt => |for_stmt| {
                if (isNestedClassInBody(for_stmt.body, class_name)) return true;
                if (for_stmt.orelse_body) |orelse_body| {
                    if (isNestedClassInBody(orelse_body, class_name)) return true;
                }
            },
            .while_stmt => |while_stmt| {
                if (isNestedClassInBody(while_stmt.body, class_name)) return true;
                if (while_stmt.orelse_body) |orelse_body| {
                    if (isNestedClassInBody(orelse_body, class_name)) return true;
                }
            },
            .try_stmt => |try_stmt| {
                if (isNestedClassInBody(try_stmt.body, class_name)) return true;
                for (try_stmt.handlers) |handler| {
                    if (isNestedClassInBody(handler.body, class_name)) return true;
                }
                if (isNestedClassInBody(try_stmt.else_body, class_name)) return true;
                if (isNestedClassInBody(try_stmt.finalbody, class_name)) return true;
            },
            .with_stmt => |with_stmt| {
                if (isNestedClassInBody(with_stmt.body, class_name)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (isNestedClassInBody(case.body, class_name)) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

/// Check if a name is a Python builtin type (handled specially as methods)
fn isBuiltinTypeName(name: []const u8) bool {
    const builtin_types = [_][]const u8{
        "int", "float", "str", "bool", "list", "tuple", "dict", "set",
        "frozenset", "bytes", "bytearray", "object", "type", "complex",
    };
    for (builtin_types) |bt| {
        if (std.mem.eql(u8, name, bt)) return true;
    }
    return false;
}

/// Fix 35: Generate struct fields for class-level attributes
/// Class attributes are assignments at class body level (not inside methods)
/// Example: `all_comp_classes = (CompNone, CompEq, ...)` becomes a struct field
pub fn genClassAttributeFields(self: *NativeCodegen, class_body: []const ast.Node) CodegenError!void {
    // Build set of method names and already-seen attributes to avoid duplicates
    var seen_names = std.StringHashMap(void).init(self.allocator);
    defer seen_names.deinit();
    for (class_body) |stmt| {
        if (stmt == .function_def) {
            seen_names.put(stmt.function_def.name, {}) catch {};
        }
    }

    for (class_body) |stmt| {
        // Skip method definitions - only look at assignments
        if (stmt == .function_def) continue;
        if (stmt == .class_def) continue;
        if (stmt == .expr_stmt) continue; // Skip docstrings

        if (stmt == .assign) {
            const assign = stmt.assign;
            // Only handle simple name assignments (not attribute or subscript)
            if (assign.targets.len == 1 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;

                // Skip __slots__ and similar special attributes
                if (std.mem.startsWith(u8, attr_name, "__") and std.mem.endsWith(u8, attr_name, "__")) {
                    continue;
                }

                // Skip if there's a method or already-seen attribute with the same name
                if (seen_names.contains(attr_name)) {
                    continue;
                }

                // Skip ALL name references (variable assignments like `localhost = some_var`)
                // In generators.zig, .name values are considered "simple" (lines 768-769)
                // and are emitted as `pub const name = value;` (lines 1523-1533)
                // Generating struct fields here would cause duplicate member errors
                if (assign.value.* == .name) {
                    continue;
                }

                // Skip if the value is a call expression (like property(...))
                // These are handled as lazy-computed attributes in generators.zig
                if (assign.value.* == .call) {
                    continue;
                }

                // Skip if the value is a tuple literal - these are generated as pub const
                if (assign.value.* == .tuple) {
                    continue;
                }

                // Skip binary operations (like candidates = set1 + set2)
                // These are handled as lazy-computed attributes
                if (assign.value.* == .binop) {
                    continue;
                }

                // Skip boolean operations (like linux_alpha = foo() and bar())
                // These are handled as lazy-computed attributes
                if (assign.value.* == .boolop) {
                    continue;
                }

                // Skip comparison operations (like system_round_bug = round(5e15+1) != 5e15+1)
                // These are handled as lazy-computed attributes
                if (assign.value.* == .compare) {
                    continue;
                }

                // Skip list/set/dict literals - they may be handled elsewhere
                if (assign.value.* == .list or assign.value.* == .set or assign.value.* == .dict) {
                    continue;
                }

                // Skip constant literals (int, float, string, bool, None)
                // These are already handled as `pub const` in generators.zig (lines 1523-1533)
                // Generating struct fields here would cause "duplicate struct member" errors
                if (assign.value.* == .constant) {
                    continue;
                }

                // Skip unary ops on constants (like -1, +2, ~0)
                // These are handled as lazy-computed attributes or pub const
                if (assign.value.* == .unaryop) {
                    continue;
                }

                // Skip module attribute references (e.g., filename = os_helper.TESTFN)
                // These are handled as lazy-computed methods in generators.zig
                // because they require runtime evaluation of module.attribute
                if (assign.value.* == .attribute) {
                    continue;
                }

                // Mark this attribute as seen to avoid duplicates from multiple assignments
                seen_names.put(attr_name, {}) catch {};

                // Infer type from the value
                const inferred_type = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;

                const b = try self.getBuilder();
                try b.writeIndent();
                try b.write("// Class attribute: ");
                try b.write(attr_name);
                try b.write("\n");
                try b.writeIndent();

                // Escape Zig keywords using @"..." syntax
                if (zig_keywords.isZigKeyword(attr_name)) {
                    try b.write("@\"");
                    try b.write(attr_name);
                    try b.write("\"");
                } else {
                    try b.write(attr_name);
                }

                // For tuples of class references, use anytype
                // For other types, use inferred Zig type
                const type_tag = @as(std.meta.Tag(@TypeOf(inferred_type)), inferred_type);
                if (type_tag == .tuple or type_tag == .unknown or type_tag == .pyvalue) {
                    // Use anytype for complex types - will be set in comptime init
                    try b.write(": @TypeOf(.{}) = .{},\n");
                } else {
                    const zig_type = self.nativeTypeToZigType(inferred_type) catch "i64";
                    defer self.allocator.free(zig_type);
                    try b.write(": ");
                    try b.write(zig_type);
                    try b.write(" = ");
                    // Generate default value based on type
                    switch (type_tag) {
                        .int, .usize => try b.write("0"),
                        .float => try b.write("0.0"),
                        .bool => try b.write("false"),
                        .string => try b.write("\"\""),
                        else => try b.write(".{}"),
                    }
                    try b.write(",\n");
                }
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
    }
}
