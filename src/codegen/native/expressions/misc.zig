/// Miscellaneous expression code generation (tuple, attribute, subscript)
///
/// MIGRATION STATUS: Using ZigBuilder for structured code generation
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Emits using emitZigValue() for type-safe output
/// - Uses nextNameId() for unique block labels
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const subscript_mod = @import("subscript.zig");
const zig_keywords = @import("utils.zig_keywords");
const expressions_mod = @import("../expressions.zig");
const producesBlockExpression = expressions_mod.producesBlockExpression;
const self_analyzer = @import("../statements/functions/self_analyzer.zig");
const UnittestAssertions = self_analyzer.unittest_assertion_methods;
const expr_emitter = @import("../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const CallArg = builder_mod.ZigBuilder.CallArg;

// MIGRATED TO ZIGBUILDER

/// Check if an expression resolves to a C extension module attribute access
/// Used to detect nested attribute access patterns like np._core._multiarray_umath
fn isCExtAttrAccess(self: *NativeCodegen, node: ast.Node) bool {
    switch (node) {
        .name => |n| {
            // Check if this is a C extension module (direct or via TryHelper local)
            if (self.isCExtensionModule(n.id)) return true;
            // TryHelper pattern: __local_VARNAME_N -> check if VARNAME is C extension
            if (std.mem.startsWith(u8, n.id, "__local_")) {
                const after_prefix = n.id["__local_".len..];
                if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_underscore| {
                    const original_name = after_prefix[0..last_underscore];
                    return self.isCExtensionModule(original_name);
                }
            }
            return false;
        },
        .attribute => |a| {
            // Recursively check if the base is a C extension access
            return isCExtAttrAccess(self, a.value.*);
        },
        else => return false,
    }
}

/// Generate a raw C extension attribute chain without PyValue.from() wrapping
/// Returns ?*PyObject that can be used for further attribute access or wrapped at the end
/// For np._core._multiarray_umath generates:
///   c_interop.getAttr(c_interop.getAttr((np orelse @panic("...")), "_core") orelse @panic("..."), "_multiarray_umath")
fn genCExtAttrChainRaw(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Base case: module name (direct or TryHelper local)
            // Use orelse @panic instead of .? for safer null handling with clear error message
            try self.emit("(");
            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), n.id);
            try self.emitFmt(" orelse @panic(\"C extension module '{s}' not loaded\"))", .{n.id});
        },
        .attribute => |a| {
            // Recursive: chain.attr -> c_interop.getAttr(chain, "attr") orelse @panic(...)
            // Use orelse @panic instead of .? for safer null handling
            try self.emit("(c_interop.getAttr(");
            try genCExtAttrChainRaw(self, a.value.*);
            try self.emit(", \"");
            try self.emit(a.attr);
            try self.emitFmt("\") orelse @panic(\"Attribute '{s}' not found on C extension object\"))", .{a.attr});
        },
        else => {
            // Fallback for unexpected nodes
            try expressions_mod.genExpr(self, node);
        },
    }
}

/// Emit runtime.pyTypeName(expr) using builder pattern
fn emitPyTypeName(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    const expr_val = try self.captureExpr(expr);
    try b.emitCallExpr("runtime.pyTypeName", &[_]CallArg{.{ .value = expr_val }});
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.PyFile.getClosed(expr) using builder pattern
fn emitPyFileGetClosed(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    const expr_val = try self.captureExpr(expr);
    try b.emitCallExpr("runtime.PyFile.getClosed", &[_]CallArg{.{ .value = expr_val }});
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Check if a string is all uppercase (for detecting constants)
fn isAllUppercase(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        // Allow underscores in constant names
        if (c == '_') continue;
        // Must be uppercase letter or digit
        if (c >= 'A' and c <= 'Z') continue;
        if (c >= '0' and c <= '9') continue;
        return false;
    }
    // Must have at least one uppercase letter
    for (s) |c| {
        if (c >= 'A' and c <= 'Z') return true;
    }
    return false;
}

// ============================================
// Misc expression helpers - auto-closing patterns
// ============================================

/// Emit @as(i64, operand) for integer constant wrapping
fn emitAsI64(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emitCallCtx("@as", operand, struct {
        pub fn f(s: *NativeCodegen, op: ZigValue) CodegenError!void {
            try s.emit("i64, ");
            try s.emitZigValue(op);
        }
    }.f);
}

/// Emit @as(f64, operand) for float constant wrapping
fn emitAsF64(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emitCallCtx("@as", operand, struct {
        pub fn f(s: *NativeCodegen, op: ZigValue) CodegenError!void {
            try s.emit("f64, ");
            try s.emitZigValue(op);
        }
    }.f);
}

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");

const FloatClassMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "fromhex", "runtime.floatFromHex" },
    .{ "hex", "runtime.floatToHex" },
    .{ "__getformat__", "runtime.floatGetFormat" },
});

const PathProperties = std.StaticStringMap(void).initComptime(.{
    .{ "parent", {} }, .{ "stem", {} }, .{ "suffix", {} }, .{ "name", {} },
});

/// List methods that can be used as callbacks (e.g., log.append passed to a function)
const ListMethodsAsCallbacks = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} },
});

/// Generate tuple literal as Zig anonymous struct
/// Always uses anonymous tuple syntax (.{ elem1, elem2 }) for type compatibility
/// This matches the type inference which generates struct types for tuples
/// Check if an expression is a call to a unittest assertion method (returns void)
fn isVoidAssertionCall(elem: ast.Node) bool {
    if (elem != .call) return false;
    const call = elem.call;
    if (call.func.* != .attribute) return false;
    const attr = call.func.attribute;
    // Check for self.assert* pattern
    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
        return UnittestAssertions.has(attr.attr);
    }
    return false;
}

pub fn genTuple(self: *NativeCodegen, tuple: ast.Node.Tuple) CodegenError!void {
    // Empty tuples become empty struct
    // BUT: if assigning to a conditionally hoisted set variable, generate empty set instead
    if (tuple.elts.len == 0) {
        if (self.current_assign_target) |target| {
            if (self.conditional_var_types.get(target)) |zig_type| {
                // Check if target is a set type (StringHashMap or AutoHashMap with void value)
                const is_set_type = std.mem.indexOf(u8, zig_type, "HashMap") != null and
                    std.mem.indexOf(u8, zig_type, "void)") != null;
                if (is_set_type) {
                    // Generate empty set init with the exact type
                    try self.emit(zig_type);
                    try self.emit(".init(__global_allocator)");
                    return;
                }
            }
        }
        try self.emit(".{}");
        return;
    }

    // Check if ALL elements are void assertion calls - if so, emit as statements, not tuple
    // This handles Python patterns like: self.assertEqual(x, y),  # trailing comma
    var all_void_assertions = true;
    for (tuple.elts) |elem| {
        if (!isVoidAssertionCall(elem)) {
            all_void_assertions = false;
            break;
        }
    }

    if (all_void_assertions) {
        // Emit each assertion as a statement followed by newline
        // Don't wrap in tuple literal - assertions generate if-statements
        for (tuple.elts, 0..) |elem, i| {
            if (i > 0) try self.emit("\n");
            const operand = try self.captureExpr(elem);
            try self.emitZigValue(operand);
        }
        return;
    }

    // Always generate anonymous tuple syntax for consistency with type inference
    // Type inference generates struct types: struct { @"0": T, @"1": T, ... }
    // So we must generate struct literals: .{ elem1, elem2, ... }
    // IMPORTANT: Integer constants must be cast to i64 to avoid comptime_int issues
    try self.emit(".{ ");
    for (tuple.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");

        // Handle void assertion calls inside mixed tuples by emitting {}
        if (isVoidAssertionCall(elem)) {
            // Emit the assertion as a statement block that produces void
            try self.withInlineBlock("void_assert", elem, struct {
                fn emit(s: *NativeCodegen, label: []const u8, e: ast.Node) CodegenError!void {
                    const operand = try s.captureExpr(e);
                    try s.emitZigValue(operand);
                    try s.emit(" break :");
                    try s.emit(label);
                    try s.emit(" {}; ");
                }
            }.emit);
            continue;
        }

        // Check if element is a local class type name - needs PyValue wrapping
        // In Python, class objects are values that can be passed around.
        // In Zig, types are not values, so we wrap with vtable pointer.
        if (elem == .name) {
            const name = elem.name.id;

            // Handle 'object' builtin explicitly - it's the base class of all Python classes
            // In MRO tuples like (D, A, B, object), 'object' needs to be runtime.builtins.object
            if (std.mem.eql(u8, name, "object")) {
                try self.emit("runtime.builtins.object");
                continue;
            }

            // Check all places where local class definitions are tracked:
            // 1. hoisted_local_classes - classes hoisted to module level
            // 2. nested_class_aliases - aliased class names
            // 3. nested_class_defs - inline class definitions within functions
            const is_local_class = self.hoisted_local_classes.contains(name) or
                self.nested_class_aliases.contains(name) or
                self.nested_class_defs.contains(name);
            if (is_local_class) {
                // Get the resolved Zig name (might be aliased)
                // For nested_class_defs, use the original name as Zig name
                const zig_name = self.hoisted_local_classes.get(name) orelse
                    self.nested_class_aliases.get(name) orelse
                    name;
                // Wrap as PyValue with vtable pointer
                // This allows class objects to be passed as values in Python
                // Use @constCast since __vtable__ is a pub const
                try self.emit("runtime.PyValue{ .ptr = @constCast(@ptrCast(&");
                try self.emit(zig_name);
                try self.emit(".__vtable__)) }");
                continue;
            }
        }

        // Capture the element expression
        const operand = try self.captureExpr(elem);

        // Wrap integer constants to avoid comptime_int at runtime
        if (elem == .constant and elem.constant.value == .int) {
            try emitAsI64(self, operand);
        } else if (elem == .unaryop and elem.unaryop.op == .USub and
            elem.unaryop.operand.* == .constant and elem.unaryop.operand.constant.value == .int)
        {
            // Negative integer: -1 -> @as(i64, -1)
            try emitAsI64(self, operand);
        } else if (elem == .constant and elem.constant.value == .float) {
            // Float constants to avoid comptime_float
            try emitAsF64(self, operand);
        } else {
            try self.emitZigValue(operand);
        }
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
                    var em = self.exprEmitter();
                    var block = try em.labeledBlock("sub", "__base", subscript.value.*);
                    try block.breakWithFmt("__base.@\"{d}\"", .{index});
                    try block.close();
                } else {
                    // Direct field access
                    try genExpr(self, subscript.value.*);
                    try self.output.writer(self.allocator).print(".@\"{d}\"", .{index});
                }
            } else {
                // Check if the index is a string - if so, generate runtime TypeError
                const index_type = try self.type_inferrer.inferExpr(subscript.slice.index.*);
                const index_is_string = string_traits.isString(index_type);

                if (index_is_string) {
                    // Generate code that raises TypeError at runtime
                    // In Python: t["a"] raises TypeError: tuple indices must be integers or slices, not str
                    // Use _ = on the tuple value to mark it as used, then return error
                    // This allows the error to be caught by assertRaisesRegex context
                    try self.withInlineBlock("typeerr", subscript.value.*, struct {
                        fn emit(s: *NativeCodegen, label: []const u8, value: ast.Node) CodegenError!void {
                            try s.emit("_ = &");
                            try genExpr(s, value);
                            try s.emit("; break :");
                            try s.emit(label);
                            try s.emit(" try @as(anyerror!@TypeOf({}), error.TypeError); ");
                        }
                    }.emit);
                } else {
                    // Non-constant tuple index - use runtime helper to avoid comptime explosion
                    // The inline for is still needed internally, but it's compiled once per tuple type
                    var em = self.exprEmitter();
                    var block = try em.labeledBlock("tup", "__t", subscript.value.*);
                    try block.emit("break :");
                    try block.emitFmt("{s}_{d} runtime.tuple_ops.TupleOps(@TypeOf(__t)).get(__t, @intCast(", .{ block.prefix, block.label_id });
                    try genExpr(self, subscript.slice.index.*);
                    try block.emit("))");
                    try block.close();
                }
            }
            return;
        }
    }

    // Delegate to subscript module for all other cases
    try subscript_mod.genSubscript(self, subscript);
}

/// Generate subscript LHS without block wrapping - for assignment targets
/// Needed for chained subscript assignments like arr[0][1][2] = value
pub fn genSubscriptLHS(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    try subscript_mod.genSubscriptLHS(self, subscript);
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

    // Handle .real, .imag, .numerator, .denominator on numeric expressions
    // Python: int and float objects have these attributes
    // - .real (returns self for int/float)
    // - .imag (returns 0 for int, 0.0 for float)
    // - .numerator (returns self for int)
    // - .denominator (returns 1 for int)
    const is_numeric_attr = std.mem.eql(u8, attr.attr, "real") or
        std.mem.eql(u8, attr.attr, "imag") or
        std.mem.eql(u8, attr.attr, "numerator") or
        std.mem.eql(u8, attr.attr, "denominator");

    if (is_numeric_attr) {
        // Check if the value expression evaluates to a numeric type
        const expr_type = self.type_inferrer.inferExpr(attr.value.*) catch null;
        const is_numeric = expr_type != null and (type_traits.isNumeric(expr_type.?) or type_traits.isIntegral(expr_type.?) or type_traits.isFloating(expr_type.?));
        if (is_numeric) {
            if (std.mem.eql(u8, attr.attr, "real") or std.mem.eql(u8, attr.attr, "numerator")) {
                // x.real -> x (the value itself)
                // x.numerator -> x (for integers)
                try genExpr(self, attr.value.*);
                return;
            } else if (std.mem.eql(u8, attr.attr, "imag")) {
                // x.imag -> 0 (for int) or 0.0 (for float)
                if (type_traits.isFloating(expr_type.?)) {
                    try self.emit("@as(f64, 0.0)");
                } else {
                    try self.emit("0");
                }
                return;
            } else if (std.mem.eql(u8, attr.attr, "denominator")) {
                // x.denominator -> 1 (for integers)
                try self.emit("1");
                return;
            }
        }
    }

    // Special case: type(x).__name__ -> runtime.pyTypeName(x)
    // runtime.pyTypeName already returns the type name as a string, so accessing .__name__ is redundant
    // This handles both regular Python types and PyPowResult (which returns "float" or "complex")
    if (std.mem.eql(u8, attr.attr, "__name__") and attr.value.* == .call) {
        const call = attr.value.call;
        if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "type") and call.args.len == 1) {
            // type(x).__name__ -> runtime.pyTypeName(x) (builder pattern)
            try emitPyTypeName(self, call.args[0]);
            return;
        }
    }

    // Special case: exception_type_var.__name__ -> "ExceptionTypeName"
    // When a variable holds an exception type (e.g., context = IndexError),
    // accessing .__name__ should return the type name as a string literal
    if (std.mem.eql(u8, attr.attr, "__name__") and attr.value.* == .name) {
        const var_name = attr.value.name.id;
        if (self.exception_type_vars.get(var_name)) |exc_type_name| {
            try self.emit("\"");
            try self.emit(exc_type_name);
            try self.emit("\"");
            return;
        }
    }

    // EARLY CHECK: traceback field access (tb_next, tb_frame, tb_lineno, tb_lasti)
    // In AOT compilation, tracebacks are PyValue stubs - use runtime.traceback_stub
    // to access their fields (returns null/0 for AOT compatibility)
    // This check must happen BEFORE block expression handling to intercept all cases
    const tb_fields_early = [_][]const u8{ "tb_next", "tb_frame", "tb_lineno", "tb_lasti" };
    const is_tb_field_early = for (tb_fields_early) |field| {
        if (std.mem.eql(u8, attr.attr, field)) break true;
    } else false;
    if (is_tb_field_early) {
        // Generate: runtime.traceback_stub.tb_next(value)
        try self.emit("runtime.traceback_stub.");
        try self.emit(attr.attr);
        try self.emit("(");
        try genExpr(self, attr.value.*);
        try self.emit(")");
        return;
    }

    // Check if value produces a block expression - need to wrap in temp variable
    // Because Zig doesn't allow field access on block expressions: blk:{}.field is invalid
    // Wrap in parentheses to prevent "label:" from being parsed as named argument when used in fn calls
    if (producesBlockExpression(attr.value.*)) {
        // Check if the base expression resolves to a C extension module attribute
        // If so, we need to use c_interop.getAttr for the nested access
        const base_is_c_ext = isCExtAttrAccess(self, attr.value.*);
        if (base_is_c_ext) {
            // C extension nested attribute: np._core._multiarray_umath.__file__
            // Generate the entire chain without intermediate PyValue conversions:
            //   runtime.PyValue.from(c_interop.getAttr(...) orelse @panic("..."))
            // The genCExtAttrChainRaw generates the raw chain, we wrap the final result
            // Use orelse @panic instead of .? for safer null handling with clear error message
            try self.emit("runtime.PyValue.from((c_interop.getAttr(");
            try genCExtAttrChainRaw(self, attr.value.*);
            try self.emit(", \"");
            try self.emit(attr.attr);
            try self.emitFmt("\") orelse @panic(\"Attribute '{s}' not found on C extension object\")))", .{attr.attr});
            return;
        }
        // Check if this is an ABC property on a class instance - need method call
        const abc_properties_block = [_][]const u8{ "real", "imag", "conjugate", "numerator", "denominator" };
        const is_abc_property_block = for (abc_properties_block) |prop| {
            if (std.mem.eql(u8, attr.attr, prop)) break true;
        } else false;

        // Check if this is a call to a class constructor (ClassName(args))
        const is_class_call = blk: {
            if (attr.value.* == .call) {
                const call_func = attr.value.call.func.*;
                if (call_func == .name) {
                    const name = call_func.name.id;
                    // Check if known class or looks like a class (starts with uppercase)
                    if (self.type_inferrer.class_fields.get(name)) |_| break :blk true;
                    if (name.len > 0 and name[0] >= 'A' and name[0] <= 'Z') break :blk true;
                }
            }
            break :blk false;
        };

        var em = self.exprEmitter();
        var block = try em.labeledBlock("attr", "__obj", attr.value.*);
        try block.emit("break :");
        try block.emitFmt("{s}_{d} __obj.", .{ block.prefix, block.label_id });
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        // For ABC properties on class instances, call as method
        if (is_abc_property_block and is_class_call) {
            try self.emit("()");
        }
        try block.close();
        return;
    }

    // Check if this is a module attribute access (e.g., string.ascii_lowercase, math.pi)
    if (attr.value.* == .name) {
        const raw_name = attr.value.name.id;
        // Apply var_renames if this name has been renamed (e.g., cls -> @This() for implicit classmethods)
        const module_name = self.var_renames.get(raw_name) orelse raw_name;
        const attr_name = attr.attr;

        // Check if this is a lazy class attribute access (C.items, C.y)
        // Lazy attrs are methods, so C.attr becomes (try C.attr(__global_allocator))
        // Use __global_allocator since the calling context may not have __alloc in scope
        var lazy_key_buf: [256]u8 = undefined;
        const lazy_key = std.fmt.bufPrint(&lazy_key_buf, "{s}.{s}", .{ module_name, attr_name }) catch module_name;
        if (self.lazy_class_attrs.contains(lazy_key)) {
            try self.emit("(try ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            try self.emit("(__global_allocator))");
            return;
        }

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
        // EXCEPTION: Skip dispatch for `operator` module when getting function references
        // (e.g., operator.eq passed as callback). The operator functions are meant to be
        // CALLED with 2 args, not used as values. Passing them to fake_call with 0 args
        // would emit default values like "false" instead of the function reference.
        const is_operator_module = std.mem.eql(u8, module_name, "operator") or std.mem.eql(u8, module_name, "_operator");
        if (!is_operator_module) {
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
                // Flush builder to output - dispatch handlers emit to builder, not output directly
                try self.flushBuilder();
                // Only return if something was actually emitted
                // Some handlers check args.len == 0 and return early without emitting
                if (self.output.items.len > output_before) {
                    return;
                }
            }
        }

        // Check if this is a C extension module (numpy, pandas, etc.)
        // np.__version__ -> c_interop.getAttr(np.?, "__version__")
        // Also check for TryHelper local copies: __local_np_2 -> np is a C extension module
        const is_c_extension = self.isCExtensionModule(module_name) or blk: {
            // TryHelper pattern: __local_VARNAME_N -> check if VARNAME is C extension
            if (std.mem.startsWith(u8, module_name, "__local_")) {
                const after_prefix = module_name["__local_".len..];
                // Find last underscore (before the number suffix)
                if (std.mem.lastIndexOf(u8, after_prefix, "_")) |last_underscore| {
                    const original_name = after_prefix[0..last_underscore];
                    break :blk self.isCExtensionModule(original_name);
                }
            }
            break :blk false;
        };
        if (is_c_extension) {
            // Resolve alias to actual module name for error messages
            const actual_module = self.c_extension_modules.get(module_name) orelse module_name;
            // Use orelse @panic for both module and attribute access for safe null handling
            try self.emit("runtime.PyValue.from(c_interop.getAttr((");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
            try self.emitFmt(" orelse @panic(\"C extension module '{s}' not loaded\")), \"", .{actual_module});
            try self.emit(attr_name);
            try self.emitFmt("\") orelse @panic(\"Failed to get attribute '{s}' from C extension module '{s}'\"))", .{ attr_name, actual_module });
            return;
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
                // emit a reference to the runtime function using the local import
                // e.g., operator.eq -> &operator.eq (operator is already imported)
                // The module is imported at file top, so just use its local name
                //
                // EXCEPTION: Constants (uppercase names starting with CO_, all caps names)
                // should NOT have & prefix since they're values, not function pointers.
                // e.g., __future__.CO_FUTURE_BARRY_AS_BDFL -> __future__.CO_FUTURE_BARRY_AS_BDFL
                const is_constant = std.mem.startsWith(u8, attr_name, "CO_") or
                    isAllUppercase(attr_name);
                if (!is_constant) {
                    try self.emit("&");
                }
                // Use writeEscapedIdent (not writeLocalVarName) to match module import generation
                // Module imports use writeEscapedIdent: const operator = runtime.Lib.operator;
                // So we must also use writeEscapedIdent: &operator.mod (not &operator_.mod)
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

        // Check if this is a from-import symbol (e.g., from test.support import os_helper)
        // In this case, module_name is "os_helper" and we need to resolve os_helper.TESTFN
        if (self.local_from_imports.get(module_name)) |source_module| {
            // Resolve the full module path (e.g., test.support.os_helper)
            const full_module = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ source_module, module_name }) catch module_name;

            // Check if this full module has a Zig runtime implementation
            if (self.import_registry.lookup(full_module)) |info| {
                if (info.zig_import) |zig_path| {
                    // Generate runtime path: runtime.test_support.os_helper.TESTFN
                    try self.emit(zig_path);
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                    return;
                }
            }

            // Fallback: use the local module name directly
            // The from-import should have generated a local import for the module
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            return;
        }
    }

    // Check if this is a __code__ attribute access on a function
    // Python functions have a __code__ attribute that returns the code object
    // Since we compile to native code, we return a stub CodeObject
    if (std.mem.eql(u8, attr.attr, "__code__")) {
        // Return a stub code object
        try self.emit("runtime.builtins.CodeObject{}");
        return;
    }

    // Check if this is an exception attribute access (e.__traceback__, e.__context__, etc.)
    // Exception variables from `except X as e:` are typed as runtime.PyException
    // and have direct field access for __traceback__, __context__, __cause__, args
    if (attr.value.* == .name) {
        const exc_var_name = attr.value.name.id;
        if (self.exception_vars.contains(exc_var_name)) {
            const exc_attrs = [_][]const u8{ "__traceback__", "__context__", "__cause__", "__suppress_context__", "args", "type_name", "message" };
            for (exc_attrs) |exc_attr| {
                if (std.mem.eql(u8, attr.attr, exc_attr)) {
                    // Direct field access on PyException struct
                    // IMPORTANT: Check var_renames first - inside TryHelper structs,
                    // exception variables are renamed to pointer dereferences (e.g., p_exc_16.*)
                    if (self.var_renames.get(exc_var_name)) |renamed| {
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), renamed);
                    } else {
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), exc_var_name);
                    }
                    try self.emit(".");
                    try self.emit(attr.attr);
                    return;
                }
            }
        }
    }

    // Check if this is a file property access
    const value_type = try self.type_inferrer.inferExpr(attr.value.*);
    if (value_type == .file) {
        if (std.mem.eql(u8, attr.attr, "closed")) {
            // File.closed property (builder pattern)
            try emitPyFileGetClosed(self, attr.value.*);
            return;
        }
    }

    // Check if this is an http_response attribute access (response.status, response.body)
    if (value_type == .http_response) {
        if (std.mem.eql(u8, attr.attr, "status") or std.mem.eql(u8, attr.attr, "status_code")) {
            // Python expects integer status code - call statusCode() method
            try genExpr(self, attr.value.*);
            try self.emit(".statusCode()");
            return;
        }
        if (std.mem.eql(u8, attr.attr, "text") or std.mem.eql(u8, attr.attr, "content")) {
            // text/content returns body as string
            try genExpr(self, attr.value.*);
            try self.emit(".body");
            return;
        }
        // For other attributes (body, headers, etc.), use direct access
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        return;
    }

    // Check if this is a ctypes CDLL attribute access (lib.func_name)
    // Returns a function pointer lookup from the dynamic library
    if (value_type == .cdll) {
        // Generate: lib.lookup(*const fn(...) callconv(.c) T, "func_name")
        // For now, we emit a placeholder that will be resolved at runtime
        // The actual signature would need to be determined from argtypes/restype
        try genExpr(self, attr.value.*);
        try self.emit(".lookup(*const fn() callconv(.c) isize, \"");
        try self.emit(attr.attr);
        try self.emit("\")");
        return;
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

    // Check if this is an array.array attribute access
    // The inline struct has direct fields (typecode, items) - use direct access
    if (type_traits.isClassInstance(value_type) and
        std.mem.eql(u8, value_type.class_instance, "array.array"))
    {
        try genExpr(self, attr.value.*);
        try self.emit(".");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
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
                if (self.class_type_attrs.get(key)) |attr_type| {
                    // Check if this is a lazy attribute (needs function call) or regular type attr
                    if (std.mem.eql(u8, attr_type, "__lazy__")) {
                        // Lazy attribute: call it with allocator
                        // (try @This().attr_name(__global_allocator))
                        // Use __global_allocator since method may have unnamed allocator param
                        try self.emit("(try @This().");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                        try self.emit("(__global_allocator))");
                    } else {
                        // Return a reference to the static function: @This().attr_name
                        try self.emit("@This().");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                    }
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
            // Determine the appropriate PyValue field from class field types if available
            const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch .unknown;
            var value_field: []const u8 = "int"; // Default to int
            if (type_traits.isClassInstance(obj_type)) {
                const class_name = obj_type.class_instance;
                if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                    if (class_info.fields.get(attr.attr)) |field_type| {
                        // Map NativeType to PyValue field name
                        const field_tag = @as(std.meta.Tag(@TypeOf(field_type)), field_type);
                        value_field = switch (field_tag) {
                            .int => "int",
                            .float => "float",
                            .bool => "bool",
                            .string => "string",
                            .bytes => "bytes",
                            .none => "none",
                            .list => "list",
                            .dict => "dict",
                            .set => "set",
                            .tuple => "tuple",
                            else => "int", // Fallback to int for unknown types
                        };
                    }
                }
            }
            try genExpr(self, attr.value.*);
            try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.{s}", .{ attr.attr, value_field });
        }
    } else {
        // Check if this is a list method being used as a callback (e.g., log.append)
        // In Python, list.append returns a bound method. In Zig, we need a closure wrapper.
        if (value_type == .list and ListMethodsAsCallbacks.has(attr.attr)) {
            // Generate a closure wrapper that captures the list and allocator
            // Get element type from ArrayListUnmanaged(T):
            // - @TypeOf(list) = ArrayListUnmanaged(T) which is a struct
            // - fields[0].type = items field type = []T (slice)
            // - @typeInfo([]T).pointer.child = T
            try self.emit("runtime.list_ops.BoundListMethod(@typeInfo(@typeInfo(@TypeOf(");
            try genExpr(self, attr.value.*);
            try self.emit(")).@\"struct\".fields[0].type).pointer.child).init(&");
            try genExpr(self, attr.value.*);
            try self.emit(", __global_allocator)");
            return;
        }

        // Check if the value is a renamed variable (e.g., other -> other_converted for type dispatch)
        // If so, use the renamed variable directly for field access instead of going through genExpr
        // which might not apply the rename due to func_local_vars precedence
        if (attr.value.* == .name) {
            const original_name = attr.value.name.id;
            if (self.var_renames.get(original_name)) |renamed| {
                // Use writeLocalVarName instead of writeEscapedIdent to handle field access notation
                // e.g., "__m22_cap_check.expected" should be output as __m22_cap_check.expected (not @"...")
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), renamed);
                try self.emit(".");
                // Apply name demangling for private attributes
                // Skip demangling for true dunder attributes (starting with __)
                const attr_name = blk: {
                    if (std.mem.startsWith(u8, attr.attr, "__")) {
                        break :blk attr.attr;
                    }
                    if (std.mem.startsWith(u8, attr.attr, "_") and attr.attr.len > 2) {
                        if (std.mem.indexOf(u8, attr.attr[1..], "__")) |pos| {
                            break :blk attr.attr[1 + pos ..];
                        }
                    }
                    break :blk attr.attr;
                };
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                return;
            }
        }

        // Check if this is an attribute access on an anytype parameter
        // For anytype params, we don't know if the attribute is a field or method at compile time
        // Generate a comptime check: if @hasDecl then call as method(), else access as field
        if (attr.value.* == .name) {
            const param_name = attr.value.name.id;

            // Check if param is type-narrowed (inside `if isClassName(param):` block)
            // If so, and attr is a known field of that class, use direct field access
            // This preserves the correct type (i64, f64, etc.) instead of f64 from getAttrDynamic
            if (self.narrowed_type_params.get(param_name)) |class_name| {
                if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                    if (class_info.fields.get(attr.attr)) |_| {
                        // Known field of narrowed class - use direct field access
                        try genExpr(self, attr.value.*);
                        try self.emit(".");
                        // Handle Python name mangling for private attributes
                        const attr_name = blk: {
                            if (std.mem.startsWith(u8, attr.attr, "__")) {
                                break :blk attr.attr;
                            }
                            if (std.mem.startsWith(u8, attr.attr, "_") and attr.attr.len > 2) {
                                if (std.mem.indexOf(u8, attr.attr[1..], "__")) |pos| {
                                    break :blk attr.attr[1 + pos ..];
                                }
                            }
                            break :blk attr.attr;
                        };
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                        return;
                    }
                    // Not a known field - fall through to getAttrDynamic for methods
                }
            }

            if (self.anytype_params.contains(param_name)) {
                // Generate: runtime.getAttrDynamic(obj, "attr") which handles field/method/primitive
                const id = self.nextNameId();
                try self.emitFmt("(__m{d}_anytype_blk: {{ const __at_obj = ", .{id});
                try genExpr(self, attr.value.*);
                try self.emitFmt("; break :__m{d}_anytype_blk runtime.getAttrDynamic(__at_obj, \"{s}\"); }})", .{ id, attr.attr });
                return;
            }
        }

        // Check if this is an ABC property access on a class instance
        // ABC properties (real, imag, conjugate, numerator, denominator) are methods, not fields
        const abc_properties = [_][]const u8{ "real", "imag", "conjugate", "numerator", "denominator" };
        const is_abc_property = for (abc_properties) |prop| {
            if (std.mem.eql(u8, attr.attr, prop)) break true;
        } else false;

        // Detect class instance from value_type OR from call expression to known class
        const is_class_instance = blk: {
            if (value_type == .class_instance) break :blk true;
            // Check if attr.value is a call to a class constructor: ClassName(args) -> ClassName.init(alloc, args)
            if (attr.value.* == .call) {
                const call_func = attr.value.call.func.*;
                if (call_func == .name) {
                    const class_name = call_func.name.id;
                    // Check if this name is a known class
                    if (self.type_inferrer.class_fields.get(class_name)) |_| {
                        break :blk true;
                    }
                    // Also check nested_class_instances map for classes defined in current scope
                    if (self.nested_class_instances.contains(class_name)) {
                        break :blk true;
                    }
                    // Also check if this matches current class being generated (for nested classes)
                    if (self.current_class_name) |current| {
                        if (std.mem.eql(u8, class_name, current)) {
                            break :blk true;
                        }
                    }
                    // Heuristic: If the name starts with uppercase, it's likely a class constructor
                    // This handles nested classes that aren't yet registered in class_fields
                    if (class_name.len > 0 and class_name[0] >= 'A' and class_name[0] <= 'Z') {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // If accessing an ABC property on a class instance, generate method call
        if (is_abc_property and is_class_instance) {
            try genExpr(self, attr.value.*);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("()");
            return;
        }

        // Known attribute: direct field access
        // Escape attribute name if it's a Zig keyword (e.g., "test")
        try genExpr(self, attr.value.*);
        try self.emit(".");

        // Handle Python name mangling for private attributes
        // Python mangles __attr to _ClassName__attr when accessed from outside
        // But Zig struct has the field as __attr (unmangled)
        // So we need to demangle: _Rat__num -> __num
        // EXCEPTION: True dunder attributes (starting with __) should NOT be demangled
        // e.g., __func__, __wrapped__, __name__ are valid dunder attrs, not mangled names
        const attr_name = blk: {
            // Skip demangling for true dunder attributes (start with __)
            if (std.mem.startsWith(u8, attr.attr, "__")) {
                break :blk attr.attr;
            }
            // Check if attr starts with underscore and contains __ later (mangled pattern)
            // Pattern: _ClassName__privateattr where ClassName doesn't start with _
            if (std.mem.startsWith(u8, attr.attr, "_") and attr.attr.len > 2) {
                // Find the double underscore after class name prefix
                if (std.mem.indexOf(u8, attr.attr[1..], "__")) |pos| {
                    // Return the part after the class name prefix (includes __)
                    // e.g., _Rat__num -> __num
                    break :blk attr.attr[1 + pos ..];
                }
            }
            break :blk attr.attr;
        };
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
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
    if (!type_traits.isClassInstance(obj_type)) return false;

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
    if (!type_traits.isClassInstance(obj_type)) return null;

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
    if (type_traits.isUnknown(obj_type)) {
        if (self.nested_class_instances.get(obj_name)) |class_name| {
            obj_type = .{ .class_instance = class_name };
        }
    }

    // Check if it's a class instance
    if (!type_traits.isClassInstance(obj_type)) return false;

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
