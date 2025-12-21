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

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// Misc expression helpers - auto-closing patterns
// ============================================

/// Emit @as(i64, operand) for integer constant wrapping
fn emitAsI64(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try emitConst(self, "@as(i64, ");
    try self.emitZigValue(operand);
    try emitConst(self, ")");
}

/// Emit @as(f64, operand) for float constant wrapping
fn emitAsF64(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try emitConst(self, "@as(f64, ");
    try self.emitZigValue(operand);
    try emitConst(self, ")");
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
                    try emitConst(self, zig_type);
                    try emitConst(self, ".init(__global_allocator)");
                    return;
                }
            }
        }
        try emitConst(self, ".{}");
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
            if (i > 0) try emitConst(self, "\n");
            const operand = try self.captureExpr(elem);
            try self.emitZigValue(operand);
        }
        return;
    }

    // Always generate anonymous tuple syntax for consistency with type inference
    // Type inference generates struct types: struct { @"0": T, @"1": T, ... }
    // So we must generate struct literals: .{ elem1, elem2, ... }
    // IMPORTANT: Integer constants must be cast to i64 to avoid comptime_int issues
    try emitConst(self, ".{ ");
    for (tuple.elts, 0..) |elem, i| {
        if (i > 0) try emitConst(self, ", ");

        // Handle void assertion calls inside mixed tuples by emitting {}
        if (isVoidAssertionCall(elem)) {
            // Emit the assertion as a statement block that produces void
            const label = try self.emitInlineBlockStart("void_assert");
            const operand = try self.captureExpr(elem);
            try self.emitZigValue(operand);
            try emitFmtConst(self, " break :{s} ", .{label});
            try emitConst(self, "{}; ");
            try self.emitInlineBlockEnd();
            continue;
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
    try emitConst(self, " }");
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
                    const label = try self.emitInlineBlockStart("typeerr");
                    try emitConst(self, "_ = &");
                    try genExpr(self, subscript.value.*);
                    try emitFmtConst(self, "; break :{s} try @as(anyerror!@TypeOf(", .{label});
                    try emitConst(self, "{}), error.TypeError); ");
                    try self.emitInlineBlockEnd();
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
            try emitConst(self, if (bool_val) "1" else "0");
            return;
        }
        if (std.mem.eql(u8, attr.attr, "imag")) {
            // True.imag = 0, False.imag = 0
            try emitConst(self, "0");
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
            try emitConst(self, "0");
            return;
        }
    }

    // Check if value produces a block expression - need to wrap in temp variable
    // Because Zig doesn't allow field access on block expressions: blk:{}.field is invalid
    // Wrap in parentheses to prevent "label:" from being parsed as named argument when used in fn calls
    if (producesBlockExpression(attr.value.*)) {
        var em = self.exprEmitter();
        var block = try em.labeledBlock("attr", "__obj", attr.value.*);
        try block.emit("break :");
        try block.emitFmt("{s}_{d} __obj.", .{ block.prefix, block.label_id });
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
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
            try emitConst(self, "(try ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
            try emitConst(self, ".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            try emitConst(self, "(__global_allocator))");
            return;
        }

        // Handle builtin type class methods (int.__new__, float.fromhex, float.hex, etc.)
        if (std.mem.eql(u8, module_name, "int")) {
            if (std.mem.eql(u8, attr_name, "__new__")) {
                // int.__new__(cls, value) - creates new int subclass instance
                try emitConst(self, "runtime.int__new__");
                return;
            }
        }

        if (std.mem.eql(u8, module_name, "float")) {
            if (FloatClassMethods.get(attr_name)) |runtime_func| {
                try emitConst(self, runtime_func);
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
                // Only return if something was actually emitted
                // Some handlers check args.len == 0 and return early without emitting
                if (self.output.items.len > output_before) {
                    return;
                }
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
                // emit a reference to the runtime function using the local import
                // e.g., operator.eq -> &operator.eq (operator is already imported)
                // The module is imported at file top, so just use its local name
                try emitConst(self, "&");
                // Use writeLocalVarName to handle renamed modules (e.g., copy -> copy_)
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), module_name);
                try emitConst(self, ".");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            } else {
                // For compiled Python modules, reference directly
                // e.g., _py_abc.ABCMeta -> _py_abc.ABCMeta (module @import gives direct access)
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), module_name);
                try emitConst(self, ".");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
            }
            return;
        }
    }

    // Check if this is a __code__ attribute access on a function
    // Python functions have a __code__ attribute that returns the code object
    // Since we compile to native code, we return a stub CodeObject
    if (std.mem.eql(u8, attr.attr, "__code__")) {
        // Return a stub code object
        try emitConst(self, "runtime.builtins.CodeObject{}");
        return;
    }

    // Check if this is a file property access
    const value_type = try self.type_inferrer.inferExpr(attr.value.*);
    if (value_type == .file) {
        if (std.mem.eql(u8, attr.attr, "closed")) {
            // File.closed property - call getClosed helper
            try emitConst(self, "runtime.PyFile.getClosed(");
            try genExpr(self, attr.value.*);
            try emitConst(self, ")");
            return;
        }
    }

    // Check if this is an http_response attribute access (response.status, response.body)
    if (value_type == .http_response) {
        if (std.mem.eql(u8, attr.attr, "status") or std.mem.eql(u8, attr.attr, "status_code")) {
            // Python expects integer status code - call statusCode() method
            try genExpr(self, attr.value.*);
            try emitConst(self, ".statusCode()");
            return;
        }
        if (std.mem.eql(u8, attr.attr, "text") or std.mem.eql(u8, attr.attr, "content")) {
            // text/content returns body as string
            try genExpr(self, attr.value.*);
            try emitConst(self, ".body");
            return;
        }
        // For other attributes (body, headers, etc.), use direct access
        try genExpr(self, attr.value.*);
        try emitConst(self, ".");
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
        try emitConst(self, ".lookup(*const fn() callconv(.c) isize, \"");
        try emitConst(self, attr.attr);
        try emitConst(self, "\")");
        return;
    }

    // Check if this is a Path property access using type inference
    if (value_type == .path) {
        if (PathProperties.has(attr.attr)) {
            try genExpr(self, attr.value.*);
            try emitConst(self, ".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try emitConst(self, "()"); // Call as method in Zig
            return;
        }
    }

    // Legacy check for Path.parent access (Python property -> Zig method)
    if (isPathProperty(attr)) {
        try genExpr(self, attr.value.*);
        try emitConst(self, ".");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        try emitConst(self, "()"); // Call as method in Zig
        return;
    }

    // Check if this is an array.array attribute access
    // The inline struct has direct fields (typecode, items) - use direct access
    if (type_traits.isClassInstance(value_type) and
        std.mem.eql(u8, value_type.class_instance, "array.array"))
    {
        try genExpr(self, attr.value.*);
        try emitConst(self, ".");
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
            try emitConst(self, "runtime.unittest.");
            try emitConst(self, attr.attr);
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
                        try emitConst(self, "(try @This().");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                        try emitConst(self, "(__global_allocator))");
                    } else {
                        // Return a reference to the static function: @This().attr_name
                        try emitConst(self, "@This().");
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
        try emitConst(self, ".");
        if (getter_name) |gn| {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), gn);
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        }
        try emitConst(self, "()");
    } else if (is_dynamic) {
        // Special case: __dict__ attribute is the dict itself, not a key in the dict
        if (std.mem.eql(u8, attr.attr, "__dict__")) {
            try genExpr(self, attr.value.*);
            try emitConst(self, ".__dict__");
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
            try emitConst(self, "runtime.list_ops.BoundListMethod(@typeInfo(@typeInfo(@TypeOf(");
            try genExpr(self, attr.value.*);
            try emitConst(self, ")).@\"struct\".fields[0].type).pointer.child).init(&");
            try genExpr(self, attr.value.*);
            try emitConst(self, ", __global_allocator)");
            return;
        }

        // Known attribute: direct field access
        // Escape attribute name if it's a Zig keyword (e.g., "test")
        try genExpr(self, attr.value.*);
        try emitConst(self, ".");

        // Handle Python name mangling for private attributes
        // Python mangles __attr to _ClassName__attr when accessed from outside
        // But Zig struct has the field as __attr (unmangled)
        // So we need to demangle: _Rat__num -> __num
        const attr_name = blk: {
            // Check if attr starts with underscore and contains __ later (mangled pattern)
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
