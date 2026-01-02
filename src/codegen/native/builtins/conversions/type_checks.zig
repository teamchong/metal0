/// Type checking and introspection builtins: type(), isinstance(), callable(), issubclass(), id(), delattr()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const shared = @import("../../shared_maps.zig");
const PythonBuiltinTypes = shared.PythonBuiltinTypes;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");

/// Helper: emit runtime.func(expr) - uses emitCallCtx for guaranteed bracket matching
fn emitRuntimeFunc(self: *NativeCodegen, func: []const u8, expr: ast.Node) CodegenError!void {
    try self.emit("runtime.");
    try self.emit(func);
    try self.emitCallCtx("", expr, struct {
        pub fn emit(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try s.genExpr(e);
        }
    }.emit);
}

/// Helper: emit runtime.func(expr1, expr2) - uses emitCallCtx for guaranteed bracket matching
fn emitRuntimeFunc2(self: *NativeCodegen, func: []const u8, expr1: ast.Node, expr2: ast.Node) CodegenError!void {
    try self.emit("runtime.");
    try self.emit(func);
    const Ctx = struct { e1: ast.Node, e2: ast.Node };
    try self.emitCallCtx("", Ctx{ .e1 = expr1, .e2 = expr2 }, struct {
        pub fn emit(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.e1);
            try s.emit(", ");
            try s.genExpr(ctx.e2);
        }
    }.emit);
}

/// Generate code for type(obj) or type(name, bases, dict)
/// For 1 arg: Returns compile-time type name as string
/// For 3 args: Dynamically creates a class (uses runtime.DynamicClass)
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 1) {
        // Generate: runtime.pyTypeName(obj)
        // Uses runtime dispatch to avoid comptime explosion (O(n²) compilation)
        // This handles PyPowResult (returns "float" or "complex" based on variant)
        // and other special types that need runtime type name resolution
        try emitRuntimeFunc(self, "pyTypeName", args[0]);
    } else if (args.len == 3) {
        // 3-argument form: type(name, bases, dict) - dynamic class creation
        // Generate: runtime.dynamicType(name, bases, dict)
        // At module level, 'try' is invalid - use catch unreachable instead
        const at_module_level = self.current_function_name == null;
        if (at_module_level) {
            try self.emit("(runtime.dynamicType(__global_allocator, ");
        } else {
            try self.emit("(try runtime.dynamicType(__global_allocator, ");
        }
        try self.genExpr(args[0]); // name
        try self.emit(", ");
        try self.genExpr(args[1]); // bases tuple
        try self.emit(", ");
        try self.genExpr(args[2]); // dict
        if (at_module_level) {
            try self.emit(") catch unreachable)");
        } else {
            try self.emit("))");
        }
    } else {
        // 0 args, 2 args, or 4+ args - TypeError in Python
        // Emit an expression that returns an error for assertRaises testing
        try self.emit("(return error.TypeError)");
    }
}

/// Generate code for isinstance(obj, type)
/// Checks if object matches expected type at compile time
/// For native codegen, this is a compile-time type check
/// For anytype parameters, generates runtime type check
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("true");
        return;
    }

    // Get the type name being checked against
    const type_name = if (args[1] == .name) args[1].name.id else null;

    // Get the inferred type of the first argument
    const obj_type = self.inferExprScoped(args[0]) catch .unknown;

    // Check if argument has unknown/pyvalue type at inference time
    // This happens for anytype parameters or other dynamic types
    // TWO-FLOW: Both .unknown and .pyvalue need runtime type checking
    const is_unknown_type = (type_traits.isUnknown(obj_type) or obj_type == .pyvalue) and args[0] == .name;

    // Perform type check based on type name
    if (type_name) |tname| {
        if (std.mem.eql(u8, tname, "bool")) {
            if (is_unknown_type) {
                // Runtime check: @TypeOf(x) == bool
                try self.emit("(@TypeOf(");
                try self.genExpr(args[0]);
                try self.emit(") == bool)");
                return;
            }
            // isinstance(x, bool) - only true for actual bools
            // In Python: isinstance(True, bool) = True, isinstance(1, bool) = False
            // Reference argument to avoid unused parameter warning
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_blk: {{ _ = @TypeOf(", .{id});
            try self.genExpr(args[0]);
            if (type_traits.isBoolean(obj_type)) {
                try self.emitFmt("); break :__m{d}_blk true; }}", .{id});
            } else {
                try self.emitFmt("); break :__m{d}_blk false; }}", .{id});
            }
            return;
        } else if (std.mem.eql(u8, tname, "int")) {
            // Always use runtime check for int to handle anytype params correctly
            // isinstance(x, int) checks if @TypeOf(x) is an integer type or bool
            // Also handles PyValue.int and PyValue.bool for vtable dispatch
            const id = self.nextNameId();
            // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
            try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
            try self.genExpr(args[0]);
            try self.emitFmt("); break :__m{d}_blk if (__chk_type_{d} == runtime.PyValue) (", .{ id, id });
            try self.genExpr(args[0]);
            try self.emitFmt(" == .int or ", .{});
            try self.genExpr(args[0]);
            try self.emitFmt(" == .bool) else (@typeInfo(__chk_type_{d}) == .int or @typeInfo(__chk_type_{d}) == .comptime_int or __chk_type_{d} == bool); }}", .{ id, id, id });
            return;
        } else if (std.mem.eql(u8, tname, "float")) {
            // Also handles PyValue.float for vtable dispatch
            const id = self.nextNameId();
            // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
            try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
            try self.genExpr(args[0]);
            try self.emitFmt("); break :__m{d}_blk if (__chk_type_{d} == runtime.PyValue) (", .{ id, id });
            try self.genExpr(args[0]);
            try self.emitFmt(" == .float) else (@typeInfo(__chk_type_{d}) == .float or @typeInfo(__chk_type_{d}) == .comptime_float); }}", .{ id, id });
            return;
        } else if (std.mem.eql(u8, tname, "str")) {
            if (is_unknown_type) {
                try self.emit("(@TypeOf(");
                try self.genExpr(args[0]);
                try self.emit(") == []const u8)");
                return;
            }
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_blk: {{ _ = @TypeOf(", .{id});
            try self.genExpr(args[0]);
            if (string_traits.isString(obj_type)) {
                try self.emitFmt("); break :__m{d}_blk true; }}", .{id});
            } else {
                try self.emitFmt("); break :__m{d}_blk false; }}", .{id});
            }
            return;
        } else if (std.mem.eql(u8, tname, "list")) {
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_blk: {{ _ = @TypeOf(", .{id});
            try self.genExpr(args[0]);
            // Note: Use switch instead of container_traits since we need exact .list match
            if (container_traits.isList(obj_type)) {
                try self.emitFmt("); break :__m{d}_blk true; }}", .{id});
            } else {
                try self.emitFmt("); break :__m{d}_blk false; }}", .{id});
            }
            return;
        } else if (std.mem.eql(u8, tname, "dict")) {
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_blk: {{ _ = @TypeOf(", .{id});
            try self.genExpr(args[0]);
            // Note: Use switch instead of container_traits since we need exact .dict match
            if (container_traits.isDict(obj_type)) {
                try self.emitFmt("); break :__m{d}_blk true; }}", .{id});
            } else {
                try self.emitFmt("); break :__m{d}_blk false; }}", .{id});
            }
            return;
        }
    }

    // Check if it's a user-defined class by looking in the class registry
    if (type_name) |tname| {
        if (self.class_registry.classes.get(tname)) |class_def| {
            // Check if class has ABCMeta metaclass - requires runtime check for virtual subclasses
            const has_abc_metaclass = if (class_def.metaclass) |mc|
                std.mem.eql(u8, mc, "ABCMeta") or std.mem.eql(u8, mc, "abc.ABCMeta")
            else
                false;

            if (has_abc_metaclass) {
                // ABCMeta class - use runtime check to support virtual subclasses
                // isinstance(x, ABCClass) must check ABC registry for registered virtual subclasses
                const id = self.nextNameId();
                // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
                try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
                try self.genExpr(args[0]);
                try self.emitFmt("); break :__m{d}_blk runtime.isSubclass(__chk_type_{d}, ", .{ id, id });
                try self.emit(tname);
                try self.emit("); }");
                return;
            }

            // Regular class (no ABCMeta) - use fast compile-time check
            const id = self.nextNameId();
            // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
            try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
            try self.genExpr(args[0]);
            try self.emitFmt("); break :__m{d}_blk __chk_type_{d} == ", .{ id, id });
            try self.emit(tname);
            try self.emitFmt(" or __chk_type_{d} == *", .{id});
            try self.emit(tname);
            try self.emitFmt(" or __chk_type_{d} == *const ", .{id});
            try self.emit(tname);
            try self.emit("; }");
            return;
        }

        // Check if tname matches the current class - if so, use @This() instead
        // This handles isinstance(other, ClassName) checks inside the class's own methods
        // where ClassName isn't accessible yet (Zig doesn't allow self-references by name)
        // IMPORTANT: This must come BEFORE the type variable check to handle nested classes like Key3
        if (self.current_class_name) |class_name| {
            if (std.mem.eql(u8, tname, class_name)) {
                // Check if current class has ABCMeta metaclass
                const current_has_abc = if (self.class_registry.classes.get(class_name)) |cd|
                    if (cd.metaclass) |mc|
                        std.mem.eql(u8, mc, "ABCMeta") or std.mem.eql(u8, mc, "abc.ABCMeta")
                    else
                        false
                else
                    false;

                if (current_has_abc) {
                    // ABCMeta class - use runtime check
                    const id = self.nextNameId();
                    // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
                    try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
                    try self.genExpr(args[0]);
                    try self.emitFmt("); break :__m{d}_blk runtime.isSubclass(__chk_type_{d}, @This()); }}", .{ id, id });
                    return;
                }

                // Regular class - use fast compile-time check
                const id = self.nextNameId();
                try self.emitFmt("__m{d}_blk: {{ const __obj_type = @TypeOf(", .{id});
                try self.genExpr(args[0]);
                try self.emitFmt("); break :__m{d}_blk __obj_type == @This() or __obj_type == *@This() or __obj_type == *const @This(); }}", .{id});
                return;
            }
        }

        // Check if this is a type variable (loop variable iterating over types)
        // e.g., for T in (int, float, complex): isinstance(x, T)
        // Generate: @TypeOf(x) == T (comptime type comparison)
        // Type variables are typically single uppercase letters or short names
        // that aren't known builtins or classes
        if (tname.len <= 4 and !PythonBuiltinTypes.has(tname)) {
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_blk: {{ const __obj_type = @TypeOf(", .{id});
            try self.genExpr(args[0]);
            try self.emitFmt("); break :__m{d}_blk __obj_type == ", .{id});
            try self.emit(tname);
            // Also check for pointer variants
            try self.emit(" or __obj_type == *");
            try self.emit(tname);
            try self.emit(" or __obj_type == *const ");
            try self.emit(tname);
            try self.emit("; }");
            return;
        }

        // Check for numbers module ABC types (Complex, Real, Rational, Integral, Number)
        // These are abstract base classes that check for specific methods/fields
        if (isNumbersABCType(tname)) {
            try genNumbersABCIsinstance(self, args[0], tname);
            return;
        }
    }

    // Default: reference argument and return true for compile-time compatibility
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_blk: {{ _ = @TypeOf(", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("); break :__m{d}_blk true; }}", .{id});
}

/// Generate code for callable(obj)
/// Returns True if obj appears to be callable
pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("false");
        return;
    }

    // At compile time, we can check if something is a function type
    // For now, emit a runtime check or true for known callable types
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Two-Flow: Check for uncertain types first
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // Runtime check - use @typeInfo for uncertain types
        try emitRuntimeFunc(self, "isCallable", args[0]);
        return;
    }

    switch (arg_type) {
        .function, .callable => {
            try self.emit("true");
        },
        else => {
            // Check if it's a name referring to a callable
            if (args[0] == .name) {
                const name = args[0].name.id;

                // Check if it's a class (has __call__)
                if (self.classHasMethod(name, "__call__")) {
                    try self.emit("true");
                    return;
                }

                // Check if it's a module-level function
                if (self.module_level_funcs.contains(name)) {
                    try self.emit("true");
                    return;
                }

                // Check if it's a known builtin function
                const builtins = @import("../../dispatch/builtins.zig");
                if (builtins.BuiltinMap.get(name) != null) {
                    try self.emit("true");
                    return;
                }

                // Check if it's a class name (classes are callable as constructors)
                if (self.class_registry.classes.contains(name)) {
                    try self.emit("true");
                    return;
                }
            }

            // Most types are not callable
            try self.emit("false");
        },
    }
}

/// Collect all types from a union expression (e.g., int | str | float)
/// Returns the types as a list that can be generated as a tuple
fn collectUnionTypes(node: ast.Node, out: *std.ArrayList(ast.Node), allocator: std.mem.Allocator) !void {
    if (node == .binop and node.binop.op == .BitOr) {
        // Recursively collect from left and right
        try collectUnionTypes(node.binop.left.*, out, allocator);
        try collectUnionTypes(node.binop.right.*, out, allocator);
    } else {
        // Base case: add this type to the list
        try out.append(allocator, node);
    }
}

/// Generate code for issubclass(cls, classinfo)
/// Returns True if cls is a subclass of classinfo
pub fn genIssubclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }

    // For static types, we can sometimes determine at compile time
    // For runtime, we need to check type hierarchy

    // Handle common cases: issubclass(bool, int) -> true
    if (args[0] == .name and args[1] == .name) {
        const cls_name = args[0].name.id;
        const base_name = args[1].name.id;

        // Built-in type hierarchy
        if (std.mem.eql(u8, cls_name, "bool") and std.mem.eql(u8, base_name, "int")) {
            try self.emit("true");
            return;
        }
        if (std.mem.eql(u8, cls_name, base_name)) {
            try self.emit("true");
            return;
        }
    }

    // Handle numbers module ABC checks: issubclass(Decimal, numbers.Number)
    // The second argument is an attribute access on the 'numbers' module
    if (args[1] == .attribute) {
        const attr = args[1].attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "numbers")) {
            const abc_name = attr.attr;
            // Verify it's a valid numbers ABC
            const valid_abc = std.mem.eql(u8, abc_name, "Number") or
                std.mem.eql(u8, abc_name, "Complex") or
                std.mem.eql(u8, abc_name, "Real") or
                std.mem.eql(u8, abc_name, "Rational") or
                std.mem.eql(u8, abc_name, "Integral");

            if (valid_abc) {
                // Get the type name from the first argument
                const type_name: ?[]const u8 = blk: {
                    if (args[0] == .name) {
                        break :blk args[0].name.id;
                    } else if (args[0] == .attribute) {
                        // Handle module.Class (e.g., decimal.Decimal)
                        break :blk args[0].attribute.attr;
                    }
                    break :blk null;
                };

                if (type_name) |tname| {
                    // Emit: runtime.isNumbersSubclass("TypeName", runtime.NumbersABC.ABCName)
                    try self.emit("runtime.isNumbersSubclass(\"");
                    try self.emit(tname);
                    try self.emit("\", runtime.NumbersABC.");
                    try self.emit(abc_name);
                    try self.emit(")");
                    return;
                }
            }
        }
    }

    // Handle direct numbers ABC name (from numbers import Integral, Real, etc.)
    if (args[1] == .name) {
        const base_name = args[1].name.id;
        if (isNumbersABCType(base_name)) {
            // Get the type name from the first argument
            const type_name: ?[]const u8 = blk: {
                if (args[0] == .name) {
                    break :blk args[0].name.id;
                } else if (args[0] == .attribute) {
                    // Handle module.Class (e.g., decimal.Decimal)
                    break :blk args[0].attribute.attr;
                }
                break :blk null;
            };

            if (type_name) |tname| {
                // Map Python built-in type names to their ABC class names
                const cls_name = if (std.mem.eql(u8, tname, "int"))
                    "int"
                else if (std.mem.eql(u8, tname, "float"))
                    "float"
                else if (std.mem.eql(u8, tname, "complex"))
                    "complex"
                else
                    tname;

                // Emit: runtime.isNumbersSubclass("ClassName", runtime.NumbersABC.ABCName)
                try self.emit("runtime.isNumbersSubclass(\"");
                try self.emit(cls_name);
                try self.emit("\", runtime.NumbersABC.");
                try self.emit(base_name);
                try self.emit(")");
                return;
            }
        }
    }

    // Check if the second argument is a type union (e.g., int | str | float)
    // Python 3.10+ allows isinstance(x, int | str) which creates a union type
    // We need to convert this to a tuple for runtime.isSubclass
    if (args[1] == .binop and args[1].binop.op == .BitOr) {
        // Collect all types from the union
        var union_types = std.ArrayList(ast.Node){};
        defer union_types.deinit(self.allocator);
        collectUnionTypes(args[1], &union_types, self.allocator) catch {
            // Fallback to direct generation if collection fails
            try self.emit("runtime.isSubclass(");
            try self.genExpr(args[0]);
            try self.emit(", .{})");
            return;
        };

        // Generate: runtime.isSubclassMulti(cls, .{type1, type2, ...})
        try self.emit("runtime.isSubclassMulti(");
        try self.genExpr(args[0]);
        try self.emit(", .{");
        for (union_types.items, 0..) |type_node, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(type_node);
        }
        try self.emit("})");
        return;
    }

    // Runtime check
    try emitRuntimeFunc2(self, "isSubclass", args[0], args[1]);
}

/// Generate code for id(obj)
/// Returns the "identity" of an object (memory address as integer)
pub fn genId(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    // Two-Flow: Check if argument is uncertain
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // For PyValue/uncertain types, use runtime id function
        try emitRuntimeFunc(self, "builtins.id", args[0]);
        return;
    }

    // Return the pointer address as an integer
    try self.emit("@as(i64, @intCast(@intFromPtr(&(");
    try self.genExpr(args[0]);
    try self.emit("))))");
}

/// Generate code for delattr(obj, name)
/// Deletes an attribute from an object
pub fn genDelattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }

    // Two-Flow: Check if object is uncertain
    const obj_type = self.inferExprScoped(args[0]) catch .unknown;
    if (type_traits.isUnknown(obj_type) or obj_type == .pyvalue) {
        // For PyValue/uncertain types, use runtime delattr
        try emitRuntimeFunc2(self, "builtins.delattr", args[0], args[1]);
        return;
    }

    // For objects with __dict__, remove the key (use swapRemove for Zig 0.15 ArrayHashMap)
    // Need @constCast because object may be captured as const in assertRaises context
    // Need to handle str subclasses - extract __base_value__ if present
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_blk: {{ const __da_key = ", .{id});
    try self.genExpr(args[1]);
    try self.emit("; const __da_key_str = if (@hasField(@TypeOf(__da_key), \"__base_value__\")) __da_key.__base_value__ else __da_key; _ = @constCast(&");
    try self.genExpr(args[0]);
    try self.emitFmt(".__dict__).swapRemove(__da_key_str); break :__m{d}_blk {{}}; }}", .{id});
}

// ============================================================================
// Numbers module ABC type handling
// ============================================================================

/// Map of numbers module ABC type names
const numbers_abc_types = std.StaticStringMap(void).initComptime(.{
    .{ "Complex", {} },
    .{ "Real", {} },
    .{ "Rational", {} },
    .{ "Integral", {} },
    .{ "Number", {} },
});

/// Check if type name is a numbers module ABC
fn isNumbersABCType(tname: []const u8) bool {
    return numbers_abc_types.has(tname);
}

/// Generate isinstance check for numbers module ABC types
/// Uses structural typing: checks for required methods/fields at compile time
fn genNumbersABCIsinstance(self: *NativeCodegen, obj: ast.Node, abc_name: []const u8) CodegenError!void {
    const id = self.nextNameId();

    // Get the type to check its structure
    // Use __chk_type_{id} instead of T to avoid shadowing class methods named T
    try self.emitFmt("__m{d}_blk: {{ const __chk_type_{d} = @TypeOf(", .{ id, id });
    try self.genExpr(obj);
    try self.emitFmt("); const info = @typeInfo(__chk_type_{d}); ", .{id});

    // Check for pointer to struct (common case for class instances)
    try self.emitFmt("const ChildType = if (info == .pointer and info.pointer.size == .one) info.pointer.child else __chk_type_{d}; ", .{id});
    try self.emit("const child_info = @typeInfo(ChildType); ");
    try self.emit("if (child_info != .@\"struct\") { ");
    // For non-struct types, check if it's a numeric primitive
    try self.emit("break :__m");
    try self.emitFmt("{d}", .{id});
    try self.emit("_blk ");
    try genPrimitiveNumbersCheck(self, abc_name);
    try self.emit("; } ");

    // For struct types, check for required fields/methods based on ABC type
    try self.emit("break :__m");
    try self.emitFmt("{d}", .{id});
    try self.emit("_blk ");

    if (std.mem.eql(u8, abc_name, "Complex")) {
        // Complex requires real and imag (methods or fields)
        try self.emit("(@hasDecl(ChildType, \"real\") or @hasField(ChildType, \"real\")) and (@hasDecl(ChildType, \"imag\") or @hasField(ChildType, \"imag\"))");
    } else if (std.mem.eql(u8, abc_name, "Real")) {
        // Real requires real (and imag should be 0 or not exist, but we just check real)
        try self.emit("@hasDecl(ChildType, \"real\") or @hasField(ChildType, \"real\")");
    } else if (std.mem.eql(u8, abc_name, "Rational")) {
        // Rational requires numerator and denominator
        try self.emit("(@hasDecl(ChildType, \"numerator\") or @hasField(ChildType, \"numerator\")) and (@hasDecl(ChildType, \"denominator\") or @hasField(ChildType, \"denominator\"))");
    } else if (std.mem.eql(u8, abc_name, "Integral")) {
        // Integral is essentially int-like - check for __index__ or int-like behavior
        try self.emit("@hasDecl(ChildType, \"__index__\") or @hasDecl(ChildType, \"__int__\")");
    } else {
        // Number - base class, just check it's a struct (any numeric-like class)
        try self.emit("true");
    }

    try self.emit("; }");
}

/// Generate primitive type check for numbers ABC
fn genPrimitiveNumbersCheck(self: *NativeCodegen, abc_name: []const u8) CodegenError!void {
    // For primitive types, check type info
    if (std.mem.eql(u8, abc_name, "Complex")) {
        // Only complex type satisfies Complex ABC from primitives
        try self.emit("false");
    } else if (std.mem.eql(u8, abc_name, "Real")) {
        // float and int satisfy Real ABC
        try self.emit("(info == .float or info == .comptime_float or info == .int or info == .comptime_int)");
    } else if (std.mem.eql(u8, abc_name, "Rational")) {
        // int satisfies Rational (as n/1)
        try self.emit("(info == .int or info == .comptime_int)");
    } else if (std.mem.eql(u8, abc_name, "Integral")) {
        // int and bool satisfy Integral
        try self.emit("(info == .int or info == .comptime_int or T == bool)");
    } else {
        // Number - any numeric type
        try self.emit("(info == .float or info == .comptime_float or info == .int or info == .comptime_int or T == bool)");
    }
}
