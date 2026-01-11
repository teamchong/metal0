/// Expression-level code generation - Re-exports from submodules
/// MIGRATED TO ZIGBUILDER
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");
const type_traits = @import("../../analysis/traits/type_traits.zig");
const string_traits = @import("../../analysis/traits/string_traits.zig");
const container_traits = @import("../../analysis/traits/container_traits.zig");

/// Check if a name is defined in any known scope
/// Returns true if the name is a known variable, builtin, import, or type
/// Public for use in expr_stmt.zig to detect undefined bare name expressions
pub fn isNameDefined(self: *NativeCodegen, name: []const u8) bool {
    // Check function local variables
    if (self.func_local_vars.contains(name)) return true;
    // Check var_renames (parameters, shadows, etc.)
    if (self.var_renames.contains(name)) return true;
    // Check hoisted classes
    if (self.hoisted_local_classes.contains(name)) return true;
    if (self.nested_class_aliases.contains(name)) return true;
    // Check Python builtins and types
    if (PyTypeNames.get(name) != null) return true;
    if (isPythonExceptionType(name)) return true;
    if (isBuiltinFunction(name)) return true;
    // Check closure variables
    if (self.closure_vars.contains(name)) return true;
    // Check imported modules
    if (self.imported_modules.contains(name)) return true;
    if (self.local_from_imports.contains(name)) return true;
    // Check nested class names
    if (self.nested_class_names.contains(name)) return true;
    // Check if captured by current class
    if (isCapturedByCurrentClass(self, name)) return true;
    // Check type inference - if type is known, variable is defined
    if (self.getVarType(name)) |_| return true;
    // Check forward declared vars
    if (self.forward_declared_vars.contains(name)) return true;
    // Not found in any known scope
    return false;
}

/// Helper: emit runtime.pyTruthy(expr) with guaranteed bracket matching
fn emitPyTruthy(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.pyTruthy", expr, struct {
        pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try genExpr(s, e);
        }
    }.f);
}

/// Helper: emit (expr)suffix with guaranteed bracket matching
fn emitParensSuffix(self: *NativeCodegen, expr: ast.Node, suffix: []const u8) CodegenError!void {
    const Ctx = struct { e: ast.Node, suf: []const u8 };
    try self.withParensCtx(Ctx{ .e = expr, .suf = suffix }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try genExpr(s, ctx.e);
        }
    }.f);
    try self.emit(suffix);
}

/// Python type/constant names to Zig code
/// IMPORTANT: These are TYPE references, not constructor calls.
/// Constructor calls like `complex(1, 2)` are handled by genCall -> builtins.genComplex
/// This map handles bare name references like `for T in (int, float, complex):`
const PyTypeNames = std.StaticStringMap([]const u8).initComptime(.{
    // Numeric types - used in isinstance checks and type tuples
    // Note: int maps to i64 (the Zig type), NOT runtime.builtins.int_factory
    .{ "int", "i64" },
    .{ "float", "f64" },
    .{ "bool", "bool" },
    .{ "complex", "runtime.PyComplex" }, // Type, not constructor
    // Boolean constants
    .{ "True", "true" },
    .{ "False", "false" },
    // Python builtin constants
    .{ "__debug__", "true" }, // True unless running with -O flag
    // Factories for mutable types (create empty instances)
    .{ "list", "runtime.builtins.list" },
    .{ "dict", "runtime.builtins.dict" },
    .{ "set", "runtime.builtins.set" },
    .{ "tuple", "runtime.builtins.tuple" },
    .{ "str", "runtime.builtins.str_factory" },
    .{ "bytes", "runtime.builtins.bytes_factory" },
    .{ "bytearray", "runtime.builtins.bytearray_factory" },
    .{ "memoryview", "runtime.builtins.memoryview_factory" },
    // Special values
    .{ "None", "null" },
    .{ "NoneType", "null" },
    .{ "NotImplemented", "runtime.Lib.types.NotImplemented" },
    .{ "Ellipsis", "runtime.Lib.types.Ellipsis" },
    .{ "object", "runtime.builtins.object" },
});

// Import submodules
const constants = @import("expressions/constants.zig");
const operators = @import("expressions/operators.zig");
const subscript_mod = @import("expressions/subscript.zig");
const collections = @import("expressions/collections.zig");
const dict_mod = @import("expressions/dict.zig");
const lambda_mod = @import("expressions/lambda.zig");
const calls = @import("expressions/calls.zig");
const comprehensions = @import("expressions/comprehensions.zig");
const misc = @import("expressions/misc.zig");

/// Check if an expression produces a Zig block expression that needs parentheses
/// Block expressions (blk: {...}) cannot have methods called on them directly
pub fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript, .list, .dict, .set, .listcomp, .dictcomp, .genexp, .if_expr, .call, .attribute, .compare => true,
        else => false,
    };
}

/// Emit object expression, wrapping in parens if it's a block expression.
/// Use this when calling methods on expressions that may produce blocks.
/// DRY: Consolidates identical helpers from list.zig, dict.zig, set.zig
pub fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try self.emitParens(obj);
    } else {
        try self.genExpr(obj);
    }
}

// Re-export functions from submodules
pub const genConstant = constants.genConstant;
pub const genBinOp = operators.genBinOp;
pub const genUnaryOp = operators.genUnaryOp;
pub const genCompare = operators.genCompare;
pub const genBoolOp = operators.genBoolOp;
pub const genList = collections.genList;
pub const genDict = dict_mod.genDict;
pub const genCall = calls.genCall;
pub const genListComp = comprehensions.genListComp;
pub const genDictComp = comprehensions.genDictComp;
pub const genTuple = misc.genTuple;
pub const genSubscript = misc.genSubscript;
pub const genSubscriptLHS = misc.genSubscriptLHS;
pub const genAttribute = misc.genAttribute;

/// Check if a variable is captured by the current class from outer scope
pub fn isCapturedByCurrentClass(self: *NativeCodegen, var_name: []const u8) bool {
    // Check if we have captured variables for the current class
    // This is set by genClassMethods when entering a class with captures
    const captured_vars = self.current_class_captures orelse return false;

    // Check if this variable is in the captured list
    for (captured_vars) |captured| {
        if (std.mem.eql(u8, captured, var_name)) return true;
    }
    return false;
}

/// Main expression dispatcher
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    // Universal VM fallback: if native codegen can't handle this expression,
    // convert AST to Python source and execute via bytecode VM
    if (self.needsVMFallback(node)) {
        try self.emitVMFallback(node);
        return;
    }

    switch (node) {
        .constant => |c| {
            // BUILDER MIGRATION: Use exprToValue path for simple constants
            // Only for types that don't need captureExpr fallback (avoid circular dependency)
            switch (c.value) {
                .int, .float, .string, .bool, .none => {
                    const val = try self.exprToValue(node);
                    try self.emitZigValue(val);
                },
                // bytes, bigint, complex use legacy path - bytes has buffering issues with captureExpr
                .bytes, .bigint, .complex => {
                    try constants.genConstant(self, c);
                },
            }
        },
        .name => |n| {
            // Resolve the name to use, with proper scoping rules:
            // 1. Check hoisted_local_classes first (locally-defined classes hoisted to struct level)
            // 2. Check var_renames for comprehension loop variables (__comp_*) - these MUST shadow
            //    local variables due to Python 3 comprehension scope isolation
            // 3. Don't apply OTHER var_renames to local variables/parameters - they take precedence
            //    over class attribute lazy patterns from outer scopes
            // 4. Check var_renames for transformed names (class attributes, shadows, etc.)
            const name_to_use = blk: {
                // Check both hoisted_local_classes (method-level nested classes)
                // and nested_class_aliases (class-body-level nested classes)
                if (self.hoisted_local_classes.get(n.id)) |hoisted| break :blk hoisted;
                if (self.nested_class_aliases.get(n.id)) |aliased| break :blk aliased;
                // Comprehension loop variables (__comp_*) MUST shadow local vars (Python 3 scope isolation)
                // Parameter renames (__m*_p_*) MUST apply even for func_local_vars (zero-capture closure params)
                if (self.var_renames.get(n.id)) |renamed| {
                    if (std.mem.startsWith(u8, renamed, "__comp_")) break :blk renamed;
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_p_") != null) break :blk renamed;
                    // Also check for mutable param copies (__m*_v_*)
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_v_") != null) break :blk renamed;
                    // Closure captures (__m*_c_*) - e.g., f -> __m7_c_f for nested function references
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_c_") != null) break :blk renamed;
                    // Closure wrappers (__m*_closure_*) - e.g., f -> __m5_closure_f for zero-capture closures
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_closure_") != null) break :blk renamed;
                    // Shadow variables for type-changing assignments (__m*_s_*) - e.g., x /= 2 changes int to float
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_s_") != null) break :blk renamed;
                    // Local variable renames (__m*_l_*) - e.g., kwargs -> __m41_l_kwargs when local var is renamed to avoid shadowing
                    if (std.mem.startsWith(u8, renamed, "__m") and std.mem.indexOf(u8, renamed, "_l_") != null) break :blk renamed;
                    // Parameter renames with underscore suffix (e.g., stop -> stop_) for method/module shadowing
                    // These MUST apply even for func_local_vars to maintain consistency with signature
                    if (std.mem.endsWith(u8, renamed, "_") and renamed.len == n.id.len + 1) break :blk renamed;
                    // Parameter renames with _param suffix (e.g., stop -> stop_param) for default params
                    if (std.mem.endsWith(u8, renamed, "_param")) break :blk renamed;
                }
                // Check var_renames for "self" FIRST - explicit renames (e.g., self -> __ptr in deferred
                // __init__ statements) take precedence over the automatic self -> __self transformation
                if (std.mem.eql(u8, n.id, "self")) {
                    if (self.var_renames.get("self")) |renamed| break :blk renamed;
                }
                // Local vars/params take precedence - don't rename them with class attribute patterns
                // Use getZigName() to get Pass 2.5 name (which provides unique naming)
                if (self.func_local_vars.contains(n.id)) break :blk self.getZigName(n.id);
                // For module-level variables, use module scope lookup to get Pass 2.5 name.
                // This handles references to module-level vars from inside methods/classes.
                // For other variables, use current scope lookup - don't search up past
                // function boundaries because Zig doesn't allow accessing outer scope
                // variables across nested function definitions.
                if (self.module_level_vars.contains(n.id)) {
                    if (self.var_resolution) |resolution| {
                        if (resolution.getZigNameAtModuleScope(n.id)) |zig_name| {
                            break :blk zig_name;
                        }
                    }
                }
                break :blk self.getZigName(n.id);
            };

            // Check if this is a Python builtin type/constant that needs special translation
            // e.g., NotImplemented -> runtime.NotImplemented, Ellipsis -> runtime.Ellipsis
            if (PyTypeNames.get(name_to_use)) |replacement| {
                try self.emit(replacement);
                return;
            }

            // Disambiguate module-level references that conflict with module wrapper struct name
            // E.g., in version.py: `__version__ = version` needs to use `_version` (the renamed const)
            const final_name = if (self.current_function_name == null and self.isModuleNameConflict(name_to_use))
                self.getModuleLevelName(name_to_use)
            else
                name_to_use;

            // Handle 'self' -> '__self' in nested class methods to avoid shadowing
            // Only apply if var_renames doesn't have a more specific mapping
            if (std.mem.eql(u8, final_name, "self") and self.method_nesting_depth > 0) {
                try self.emit("__self");
                return;
            }

            // Handle nested class self-reference: when inside a class and referencing that class by name
            // This MUST happen before other checks because the class name might be in func_local_vars
            // (local classes are const declarations in the enclosing function)
            if (self.current_class_name) |class_name| {
                if (std.mem.eql(u8, name_to_use, class_name)) {
                    try self.emit("@This()");
                    return;
                }
            }

            // Note: name_to_use computation uses anonymous block (:blk) which is inline/comptime
            // and doesn't need unique ID - it's never generated as Zig code

            // Handle 'self' in methods - emit as-is, NOT as runtime.builtins.self
            if (std.mem.eql(u8, name_to_use, "self") and self.inside_method_with_self) {
                try self.emit("self");
                return;
            }

            // Handle 'cls' in metaclass instance methods - 'cls' is the first param (like 'self')
            // In metaclass methods, 'cls' maps to 'self'/'__self' in Zig
            // IMPORTANT: Only do this if 'cls' is actually the first parameter name,
            // not just a local variable named 'cls' (e.g., in __new__ methods)
            if (std.mem.eql(u8, name_to_use, "cls") and self.inside_method_with_self) {
                // Check if 'cls' is actually the first parameter name for this method
                const is_first_param = if (self.current_method_first_param) |fp|
                    std.mem.eql(u8, fp, "cls")
                else
                    false;

                if (is_first_param) {
                    if (self.method_nesting_depth > 0) {
                        try self.emit("__self");
                    } else {
                        try self.emit("self");
                    }
                    return;
                }
            }

            // Handle 'cls' in init generated from __new__ - 'cls' becomes @This()
            // When __new__(cls, ...) is converted to init(allocator, ...), 'cls' parameter is removed
            // Any reference to 'cls' in the body should become @This() (the struct type)
            if (std.mem.eql(u8, name_to_use, "cls") and self.inside_init_method) {
                try self.emit("@This()");
                return;
            }

            // Handle Python builtin constants
            if (std.mem.eql(u8, name_to_use, "Ellipsis")) {
                // Python Ellipsis constant - emit void value (like ellipsis_literal)
                try self.emit("@as(void, {})");
                return;
            }

            // Handle Python type names as type values
            if (PyTypeNames.get(name_to_use)) |zig_code| {
                try self.emit(zig_code);
                return;
            } else if (isPythonExceptionType(name_to_use)) {
                // Python exception types - emit as integer enum value for storage in lists/tuples
                // E.g., ValueError -> @intFromEnum(runtime.ExceptionTypeId.ValueError)
                try self.emitCallCtx("@intFromEnum", name_to_use, struct {
                    pub fn f(s: *NativeCodegen, name: []const u8) CodegenError!void {
                        try s.emit("runtime.ExceptionTypeId.");
                        try s.emit(name);
                    }
                }.f);
            } else if (isBuiltinFunction(name_to_use) and !self.func_local_vars.contains(name_to_use)) {
                // Builtin functions as first-class values: len, callable, etc.
                // For structs with .call() method (like pow), emit function pointer: &runtime.builtins.pow.call
                // This allows them to be used in tuples alongside regular functions like &operator.pow
                // For function-like builtins, emit as-is: runtime.builtins.len
                if (std.mem.eql(u8, name_to_use, "pow")) {
                    // pow is a struct with .call() method - emit function pointer
                    try self.emit("&runtime.builtins.pow.call");
                } else {
                    try self.emit("runtime.builtins.");
                    try self.emit(name_to_use);
                }
            } else if (self.closure_vars.contains(n.id)) {
                // Closure variable - use the renamed version (e.g., f -> __closure_f_0)
                // The closure was registered with original name, but we emit the renamed wrapper
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), name_to_use);
            } else if (isCapturedByCurrentClass(self, name_to_use)) {
                // Variable captured from outer scope by current nested class
                if (self.inside_init_method) {
                    // In __init__, access via __cap_* parameter (pointer dereference, no self yet)
                    try self.output.writer(self.allocator).print("__cap_{s}.*", .{name_to_use});
                } else if (self.inside_classmethod) {
                    // In classmethod (e.g., __init_subclass__), there's no self/__self instance.
                    // Access via static var that holds the captured pointer: @This().__static_xxx
                    // Cast the *anyopaque back to the proper type and dereference
                    try self.output.writer(self.allocator).print("@as(*hashmap_helper.StringHashMap(runtime.PyValue), @ptrCast(@alignCast(@This().__static_{s})))", .{name_to_use});
                } else {
                    // In regular method, access via self.__captured_* field (pointer dereference)
                    // Use __self for regular nested methods, __cls for __new__ methods
                    const self_name = if (self.method_nesting_depth > 0)
                        (if (self.inside_new_method) "__cls" else "__self")
                    else
                        "self";
                    try self.output.writer(self.allocator).print("{s}.__captured_{s}.*", .{ self_name, name_to_use });
                }
            } else if (self.current_class_name) |class_name| {
                // Inside a class: check if this name matches the current class name
                // In Zig, you can't refer to a struct by name from inside it - use @This() instead
                if (std.mem.eql(u8, name_to_use, class_name)) {
                    try self.emit("@This()");
                } else if (std.mem.eql(u8, name_to_use, "__class__")) {
                    // Python __class__ refers to the current class - use @This() in Zig
                    try self.emit("@This()");
                } else if (self.nested_class_names.contains(name_to_use) and std.mem.eql(u8, name_to_use, class_name)) {
                    // Nested class self-reference - also use @This()
                    try self.emit("@This()");
                } else {
                    // Check for undefined variable in NameError-catching context
                    // Only emit return error.NameError when inside a try block that catches NameError
                    // This avoids breaking expressions when undefined name is part of larger expr
                    if (self.in_nameerror_context and !isNameDefined(self, name_to_use)) {
                        try self.emit("return error.NameError");
                        return;
                    }
                    // For imported modules, use writeEscapedIdent (NOT writeLocalVarName which adds _ suffix)
                    // Only use writeEscapedIdent when there's an explicit var_renames entry (like from try-except hoisting)
                    // Regular local variables should use writeLocalVarName for consistent shadowing rename handling
                    if (self.imported_modules.contains(name_to_use)) {
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), final_name);
                    } else if (self.var_renames.get(n.id)) |renamed| {
                        // Has explicit rename - use the renamed name directly
                        // Use writeLocalVarName to handle capture field access like "__m22_cap_check.expected"
                        // which should be emitted as field access, not a single escaped identifier
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), renamed);
                    } else {
                        // Use writeLocalVarName to handle keywords AND method shadowing consistently
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), final_name);
                    }
                    if (self.nested_class_names.contains(name_to_use)) {
                        try self.nested_class_zig_refs.put(final_name, {});
                    }
                }
            } else {
                // Check for undefined variable in NameError-catching context
                // Only emit return error.NameError when inside a try block that catches NameError
                if (self.in_nameerror_context and !isNameDefined(self, name_to_use)) {
                    try self.emit("return error.NameError");
                    return;
                }
                // For imported modules, use writeEscapedIdent (NOT writeLocalVarName which adds _ suffix)
                // This ensures consistency with module import generation in generator.zig
                if (self.imported_modules.contains(name_to_use)) {
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), final_name);
                } else {
                    // Use writeLocalVarName to handle keywords AND method shadowing
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), final_name);
                }
                // Track that we referenced this nested class in generated Zig code
                // This is used to determine which classes need _ = ClassName; suppression
                if (self.nested_class_names.contains(name_to_use)) {
                    try self.nested_class_zig_refs.put(final_name, {});
                }
            }
        },
        .fstring => |f| try genFString(self, f),
        .binop => |b| try operators.genBinOp(self, b),
        .unaryop => |u| try operators.genUnaryOp(self, u),
        .compare => |c| try operators.genCompare(self, c),
        .boolop => |b| try operators.genBoolOp(self, b),
        .call => |c| try calls.genCall(self, c),
        .list => |l| try collections.genList(self, l),
        .listcomp => |lc| try comprehensions.genListComp(self, lc),
        .dict => |d| try dict_mod.genDict(self, d),
        .dictcomp => |dc| try comprehensions.genDictComp(self, dc),
        .set => |s| try collections.genSet(self, s),
        .tuple => |t| try misc.genTuple(self, t),
        .subscript => |s| try misc.genSubscript(self, s),
        .attribute => |a| try misc.genAttribute(self, a),
        .lambda => |lam| lambda_mod.genLambda(self, lam) catch |e| switch (e) {
            error.NotAClosure => return error.UnsupportedSyntax,
            else => |err| return err,
        },
        .await_expr => |a| try genAwait(self, a),
        .ellipsis_literal => {
            // Python Ellipsis literal (...)
            // Emit void value to avoid "unused variable" warnings
            try self.emit("@as(void, {})");
        },
        .starred => |s| {
            // Starred expression: *expr
            // Just generate the inner expression (unpacking is handled by call context)
            try genExpr(self, s.value.*);
        },
        .double_starred => |ds| {
            // Double starred expression: **expr
            // Just generate the inner expression (unpacking is handled by call context)
            try genExpr(self, ds.value.*);
        },
        .named_expr => |ne| try genNamedExpr(self, ne),
        .if_expr => |ie| try genIfExpr(self, ie),
        .yield_stmt => |y| try genYield(self, y),
        .yield_from_stmt => |yf| try genYieldFrom(self, yf),
        .genexp => |ge| try comprehensions.genGenExp(self, ge),
        .slice_expr => |sl| try genSliceExpr(self, sl),
        else => {
            // Statement node passed to expression dispatcher - this is a bug
            return error.UnsupportedSyntax;
        },
    }
}

/// Generate a standalone slice expression for multi-dim subscripts
/// This creates a Zig struct representing Python's slice(start, stop, step)
fn genSliceExpr(self: *NativeCodegen, sl: ast.Node.SliceRange) CodegenError!void {
    // For multi-dim subscripts like arr[1:, 2], generate a slice struct
    // We represent it as a struct with optional start/stop/step fields
    try self.emit(".{ .start = ");
    if (sl.lower) |l| {
        try genExpr(self, l.*);
    } else {
        try self.emit("null");
    }
    try self.emit(", .stop = ");
    if (sl.upper) |u| {
        try genExpr(self, u.*);
    } else {
        try self.emit("null");
    }
    try self.emit(", .step = ");
    if (sl.step) |s| {
        try genExpr(self, s.*);
    } else {
        try self.emit("null");
    }
    try self.emit(" }");
}

/// Generate yield expression - currently emits null as placeholder
/// Real generators use CPython at runtime
fn genYield(self: *NativeCodegen, y: ast.Node.Yield) CodegenError!void {
    // For AOT compilation, yield expressions are converted to returning the value
    // This allows tests that check syntax to compile (they won't run correctly though)
    if (y.value) |val| {
        try genExpr(self, val.*);
    } else {
        try self.emit("null");
    }
}

/// Generate yield from expression - currently emits null as placeholder
fn genYieldFrom(self: *NativeCodegen, yf: ast.Node.YieldFrom) CodegenError!void {
    // For AOT compilation, yield from expressions get the iterable
    try genExpr(self, yf.value.*);
}

/// Generate named expression (walrus operator): (x := value)
/// Assigns value to target and returns the value
fn genNamedExpr(self: *NativeCodegen, ne: ast.Node.NamedExpr) CodegenError!void {
    // Get the target name
    const target_name = switch (ne.target.*) {
        .name => |n| n.id,
        else => return error.UnsupportedSyntax, // Walrus target must be a name
    };

    // Generate: (label: { target = value; break :label target; })
    const Ctx = struct { name: []const u8, value: ast.Node };
    try self.withInlineBlock("walrus", Ctx{ .name = target_name, .value = ne.value.* }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit(" ");
            try s.emit(ctx.name);
            try s.emit(" = ");
            try genExpr(s, ctx.value);
            try s.emitFmt("; break :{s} ", .{label});
            try s.emit(ctx.name);
        }
    }.emit);
}

/// Generate conditional expression (ternary): body if condition else orelse_value
fn genIfExpr(self: *NativeCodegen, ie: ast.Node.IfExpr) CodegenError!void {
    // In Zig: if (condition) body else orelse_value
    // Check condition type - need to handle PyObject truthiness
    // Use inferExprScoped which checks local symbol table (includes function parameters)
    const cond_type = self.inferExprScoped(ie.condition.*) catch .unknown;

    // Check if condition is comptime-evaluable (determines if we need to cast branches)
    // If condition involves runtime values (function calls, runtime vars), branches must be concrete types
    const is_runtime_condition = isRuntimeCondition(ie.condition.*);

    // Check if branches are integer constants - need to cast to i64 for runtime conditions
    const body_is_int = ie.body.* == .constant and ie.body.constant.value == .int;
    const orelse_is_int = ie.orelse_value.* == .constant and ie.orelse_value.constant.value == .int;
    // Need int cast when: both branches are int constants, OR one is int constant and other is runtime variable
    // This handles patterns like: `10 if base is None else base` where 10 must be cast to match base's type
    const orelse_is_var = ie.orelse_value.* == .name;
    const body_is_var = ie.body.* == .name;
    const needs_int_cast = is_runtime_condition and (
        (body_is_int and orelse_is_int) or // Both constants
        (body_is_int and orelse_is_var) or // Constant body, variable orelse
        (body_is_var and orelse_is_int) // Variable body, constant orelse
    );

    // Check if one branch is None - need to wrap other in @as(?T, ...) for type unification
    // Pattern: `10 if base is None else base` needs both branches to be ?i64
    const body_is_none = ie.body.* == .constant and ie.body.constant.value == .none;
    const orelse_is_none = ie.orelse_value.* == .constant and ie.orelse_value.constant.value == .none;
    const needs_optional_wrap = (body_is_none or orelse_is_none) and !(body_is_none and orelse_is_none);

    // Infer types for optional wrapping
    const body_type = if (needs_optional_wrap and !body_is_none)
        self.inferExprScoped(ie.body.*) catch .unknown
    else
        .unknown;
    const orelse_type = if (needs_optional_wrap and !orelse_is_none)
        self.inferExprScoped(ie.orelse_value.*) catch .unknown
    else
        .unknown;

    // Check if condition is a boolop or compare - these always generate bool result
    const cond_is_boolop = ie.condition.* == .boolop;
    const cond_is_compare = ie.condition.* == .compare;

    try self.emit("(if (");
    if (cond_is_boolop or cond_is_compare) {
        // Boolean operations and comparisons generate bool directly, use as-is
        try genExpr(self, ie.condition.*);
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        try emitPyTruthy(self, ie.condition.*);
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try genExpr(self, ie.condition.*);
        try self.emit(" != null");
    } else if (type_traits.isIntegral(cond_type)) {
        // Integer type - Python truthiness: non-zero is true
        try emitParensSuffix(self, ie.condition.*, " != 0");
    } else if (type_traits.isFloating(cond_type)) {
        // Float type - Python truthiness: non-zero is true
        try emitParensSuffix(self, ie.condition.*, " != 0.0");
    } else if (string_traits.isString(cond_type)) {
        // String type - Python truthiness: non-empty is true
        try emitParensSuffix(self, ie.condition.*, ".len != 0");
    } else if (container_traits.isList(cond_type)) {
        // List type - Python truthiness: non-empty is true
        try emitParensSuffix(self, ie.condition.*, ".items.len != 0");
    } else if (container_traits.isDict(cond_type)) {
        // Dict type - Python truthiness: non-empty is true
        try emitParensSuffix(self, ie.condition.*, ".count() != 0");
    } else if (container_traits.isSet(cond_type)) {
        // Set type - Python truthiness: non-empty is true
        try emitParensSuffix(self, ie.condition.*, ".count() != 0");
    } else if (container_traits.isTuple(cond_type)) {
        // Tuple type - Python truthiness: non-empty is true
        try self.emit("@typeInfo(@TypeOf(");
        try genExpr(self, ie.condition.*);
        try self.emit(")).@\"struct\".fields.len != 0");
    } else if (string_traits.isBytes(cond_type)) {
        // Bytes type - Python truthiness: non-empty is true
        try emitParensSuffix(self, ie.condition.*, ".len != 0");
    } else {
        // Boolean or other type - use directly
        try genExpr(self, ie.condition.*);
    }
    try self.emit(") ");

    // Emit body branch
    if (needs_optional_wrap and body_is_none) {
        // Body is None - emit null, cast orelse_value to optional
        try self.emit("null");
    } else if (needs_optional_wrap and orelse_is_none) {
        // Orelse is None - cast body to optional
        try self.emit("@as(?");
        try self.emitZigTypeFor(body_type);
        try self.emit(", ");
        try genExpr(self, ie.body.*);
        try self.emit(")");
    } else {
        // Only cast int constants, not variables (variables already have concrete type)
        const cast_body = needs_int_cast and body_is_int;
        if (cast_body) try self.emit("@as(i64, ");
        try genExpr(self, ie.body.*);
        if (cast_body) try self.emit(")");
    }

    try self.emit(" else ");

    // Emit orelse branch
    if (needs_optional_wrap and orelse_is_none) {
        // Orelse is None - emit null
        try self.emit("null");
    } else if (needs_optional_wrap and body_is_none) {
        // Body was None - cast orelse to optional
        try self.emit("@as(?");
        try self.emitZigTypeFor(orelse_type);
        try self.emit(", ");
        try genExpr(self, ie.orelse_value.*);
        try self.emit(")");
    } else {
        // Only cast int constants, not variables (variables already have concrete type)
        const cast_orelse = needs_int_cast and orelse_is_int;
        if (cast_orelse) try self.emit("@as(i64, ");
        try genExpr(self, ie.orelse_value.*);
        if (cast_orelse) try self.emit(")");
    }

    try self.emit(")");
}

/// Check if an expression involves runtime values (not comptime-evaluable)
fn isRuntimeCondition(expr: ast.Node) bool {
    return switch (expr) {
        // Constants are comptime
        .constant => false,
        // Names could be either - assume runtime for safety
        .name => true,
        // Calls are runtime (function calls, method calls)
        .call => true,
        // Binary ops with any runtime operand are runtime
        .binop => |b| isRuntimeCondition(b.left.*) or isRuntimeCondition(b.right.*),
        // Unary ops inherit from operand
        .unaryop => |u| isRuntimeCondition(u.operand.*),
        // Comparisons with any runtime operand are runtime
        .compare => |c| blk: {
            if (isRuntimeCondition(c.left.*)) break :blk true;
            for (c.comparators) |cmp| {
                if (isRuntimeCondition(cmp)) break :blk true;
            }
            break :blk false;
        },
        // Boolean ops (and/or) are runtime if any operand is
        .boolop => |b| blk: {
            for (b.values) |v| {
                if (isRuntimeCondition(v)) break :blk true;
            }
            break :blk false;
        },
        // Everything else: assume runtime for safety
        else => true,
    };
}

/// Generate await expression
fn genAwait(self: *NativeCodegen, await_node: ast.Node.AwaitExpr) CodegenError!void {
    // Check if awaiting asyncio.gather or asyncio.sleep
    if (await_node.value.* == .call) {
        const call = await_node.value.*.call;
        if (call.func.* == .attribute) {
            const attr = call.func.*.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.*.name.id, "asyncio")) {
                if (std.mem.eql(u8, attr.attr, "gather")) {
                    // asyncio.gather returns results directly (no thread wrapping)
                    try genExpr(self, await_node.value.*);
                    return;
                }
                if (std.mem.eql(u8, attr.attr, "sleep")) {
                    // asyncio.sleep is inline - just emit the sleep, no thread
                    try genExpr(self, await_node.value.*);
                    return;
                }
            }
        }
    }

    // Infer the return type of the awaited coroutine
    // Default to i64, but try to infer actual type from call expression
    var result_type: []const u8 = "i64";
    if (await_node.value.* == .call) {
        const call = await_node.value.*.call;
        // Get function name to look up return type
        if (call.func.* == .name) {
            const func_name = call.func.*.name.id;
            if (self.type_inferrer.func_return_types.get(func_name)) |ret_type| {
                var type_buf = std.ArrayList(u8){};
                defer type_buf.deinit(self.allocator);
                ret_type.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    result_type = self.arena.allocator().dupe(u8, type_buf.items) catch "i64";
                }
            }
        }
    }

    // For regular coroutine calls: await expr → wait for green thread and get result
    const Ctx = struct { value: ast.Node, result_type: []const u8 };
    try self.withInlineBlock("await", Ctx{ .value = await_node.value.*, .result_type = result_type }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("\n");
            try s.emit("    const __thread = ");
            try genExpr(s, ctx.value);
            try s.emit(";\n");
            try s.emit("    runtime.scheduler.?.wait(__thread);\n");
            try s.emit("    const __result = __thread.result orelse unreachable;\n");
            try s.emitFmt("    break :{s} @as(*{s}, @ptrCast(@alignCast(__result))).*;\n", .{ label, ctx.result_type });
        }
    }.emit);
}

/// Convert Python format specifier to Zig format specifier
fn convertFormatSpec(allocator: std.mem.Allocator, python_spec: []const u8) ![]const u8 {
    // Python: .2f  -> Zig: d:.2
    // Python: d    -> Zig: d
    // Python: s    -> Zig: s
    // Python: .3f  -> Zig: d:.3
    // Python: 10.2f -> Zig: d:10.2

    if (std.mem.indexOf(u8, python_spec, "f") != null) {
        // Float format: .2f, 10.2f, etc.
        // Remove 'f' and prepend 'd:'
        var buf = std.ArrayList(u8){};
        try buf.writer(allocator).writeAll("d:");
        for (python_spec) |c| {
            if (c != 'f') try buf.append(allocator, c);
        }
        return buf.toOwnedSlice(allocator);
    }

    // Return as-is for other specs
    return allocator.dupe(u8, python_spec);
}

/// Escape special characters for Zig string literals
/// Handles double quotes, backslashes, and braces (for format strings)
fn escapeForZigString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            '{' => try buf.appendSlice(allocator, "{{"),
            '}' => try buf.appendSlice(allocator, "}}"),
            else => try buf.append(allocator, c),
        }
    }
}

/// Generate f-string code
fn genFString(self: *NativeCodegen, fstring: ast.Node.FString) CodegenError!void {
    // For now, generate a compile-time concatenation if possible
    // or use std.fmt.allocPrint for runtime formatting

    // Check if we're at module level (not inside a function)
    // Module-level const initializers can't use 'try' - must use 'catch unreachable'
    const at_module_level = self.current_function_name == null;

    // Check if all parts are literals (simple case)
    var all_literals = true;
    for (fstring.parts) |part| {
        if (part != .literal) {
            all_literals = false;
            break;
        }
    }

    if (all_literals) {
        // Simple case: just concatenate literals (but process Python escape sequences)
        try self.emit("\"");
        for (fstring.parts) |part| {
            const lit = part.literal;
            // Process Python escape sequences like \N{name}, \xNN, \uNNNN
            try constants.emitPythonEscapedString(self, lit);
        }
        try self.emit("\"");
        return;
    }

    // Complex case: has expressions, need runtime formatting
    // Build format string and arguments list
    var format_buf = std.ArrayList(u8){};
    defer format_buf.deinit(self.allocator);

    var args_list = std.ArrayList([]const u8){};
    defer {
        for (args_list.items) |item| {
            self.allocator.free(item);
        }
        args_list.deinit(self.allocator);
    }

    for (fstring.parts) |part| {
        switch (part) {
            .literal => |lit| {
                // Process Python escape sequences like \N{name}, \xNN, \uNNNN
                // and escape braces for Zig format strings
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};
                try constants.emitPythonEscapedStringExt(self, lit, true);
                const escaped = try self.output.toOwnedSlice(self.allocator);
                defer self.allocator.free(escaped);
                self.output = saved_output;
                try format_buf.appendSlice(self.allocator, escaped);
            },
            .expr => |e| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=}"
                if (e.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

                // Determine format specifier based on inferred type
                var expr_type = try self.type_inferrer.inferExpr(e.node.*);

                // Check pyvalue_vars override - VM fallback variables are typed as PyValue at runtime
                // even if static analysis inferred a specific type (e.g., string for x[1:])
                if (e.node.* == .name) {
                    if (self.pyvalue_vars.contains(e.node.name.id)) {
                        expr_type = .pyvalue;
                    }
                }

                // Generate expression code and capture it
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                try genExpr(self, e.node.*);
                // Flush builder to ensure any pending output from builder pattern
                // (e.g., genSimpleBinOp) is written to self.output before capture
                try self.flushBuilder();
                const expr_code = try self.output.toOwnedSlice(self.allocator);

                self.output = saved_output;

                // Handle based on type - must check pyvalue explicitly before falling through
                if (expr_type == .pyvalue) {
                    // For PyValue types, use runtime.builtins.pyStr to convert to string first
                    try format_buf.writer(self.allocator).writeAll("{s}");
                    const new_expr = if (at_module_level)
                        try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyStr(__global_allocator, {s}) catch unreachable)", .{expr_code})
                    else
                        try std.fmt.allocPrint(self.allocator, "(try runtime.builtins.pyStr(__global_allocator, {s}))", .{expr_code});
                    try args_list.append(self.allocator, new_expr);
                    self.allocator.free(expr_code);
                } else if (expr_type == .int) {
                    try format_buf.writer(self.allocator).writeAll("{d}");
                    try args_list.append(self.allocator, expr_code);
                } else if (expr_type == .float) {
                    try format_buf.writer(self.allocator).writeAll("{d}");
                    try args_list.append(self.allocator, expr_code);
                } else if (string_traits.isString(expr_type)) {
                    try format_buf.writer(self.allocator).writeAll("{s}");
                    try args_list.append(self.allocator, expr_code);
                } else if (expr_type == .bool) {
                    try format_buf.writer(self.allocator).writeAll("{}");
                    try args_list.append(self.allocator, expr_code);
                } else {
                    // For uncertain/other types, also use runtime.builtins.pyStr
                    try format_buf.writer(self.allocator).writeAll("{s}");
                    const new_expr = if (at_module_level)
                        try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyStr(__global_allocator, {s}) catch unreachable)", .{expr_code})
                    else
                        try std.fmt.allocPrint(self.allocator, "(try runtime.builtins.pyStr(__global_allocator, {s}))", .{expr_code});
                    try args_list.append(self.allocator, new_expr);
                    self.allocator.free(expr_code);
                }
            },
            .format_expr => |fe| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=:...}"
                if (fe.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

                // Use runtime.pyFormat for ALL format specs to handle Python's format mini-language
                // Python format specs like #10x, 08b, .2f are different from Zig's format specs
                try format_buf.writer(self.allocator).writeAll("{s}");

                // Generate: runtime.pyFormat(__global_allocator, <expr>, "<format_spec>")
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                if (at_module_level) {
                    try self.emit("(runtime.pyFormat(__global_allocator, ");
                } else {
                    try self.emit("(try runtime.pyFormat(__global_allocator, ");
                }
                try genExpr(self, fe.expr.*);
                try self.emit(", ");

                // Check if format spec has nested expressions (PEP 701)
                if (fe.format_spec_parts) |spec_parts| {
                    // Build format spec dynamically from parts
                    // We need to use type-appropriate format specifiers
                    if (at_module_level) {
                        try self.emit("(std.fmt.allocPrint(__global_allocator, \"");
                    } else {
                        try self.emit("(try std.fmt.allocPrint(__global_allocator, \"");
                    }
                    // Build format string for the parts with type-aware specifiers
                    for (spec_parts) |spec_part| {
                        switch (spec_part) {
                            .literal => |lit| {
                                for (lit) |c| {
                                    switch (c) {
                                        '"' => try self.emit("\\\""),
                                        '\\' => try self.emit("\\\\"),
                                        '{' => try self.emit("{{"),
                                        '}' => try self.emit("}}"),
                                        else => try self.output.append(self.allocator, c),
                                    }
                                }
                            },
                            .expr => |e| {
                                // Determine format specifier based on expression type
                                const expr_type = try self.type_inferrer.inferExpr(e.*);
                                switch (expr_type) {
                                    .string => try self.emit("{s}"),
                                    .int => try self.emit("{d}"),
                                    .float => try self.emit("{d}"),
                                    else => try self.emit("{}"),
                                }
                            },
                        }
                    }
                    try self.emit("\", .{");
                    // Now generate the expression values
                    var first = true;
                    for (spec_parts) |spec_part| {
                        switch (spec_part) {
                            .literal => {},
                            .expr => |e| {
                                if (!first) try self.emit(", ");
                                first = false;
                                try genExpr(self, e.*);
                            },
                        }
                    }
                    if (at_module_level) {
                        try self.emit("}) catch unreachable)");
                    } else {
                        try self.emit("}))");
                    }
                } else {
                    // Simple format spec - use literal string
                    try self.emit("\"");
                    for (fe.format_spec) |c| {
                        switch (c) {
                            '"' => try self.emit("\\\""),
                            '\\' => try self.emit("\\\\"),
                            '\n' => try self.emit("\\\\n"), // double-escape for Zig literal
                            '\r' => try self.emit("\\\\r"),
                            '\t' => try self.emit("\\\\t"),
                            else => try self.output.append(self.allocator, c),
                        }
                    }
                    try self.emit("\"");
                }
                if (at_module_level) {
                    try self.emit(") catch unreachable)");
                } else {
                    try self.emit("))");
                }

                // Flush builder before capturing output
                try self.flushBuilder();
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);
                self.output = saved_output;
            },
            .conv_expr => |ce| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=!r}"
                if (ce.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

                // Expression with conversion specifier (!r, !s, !a)
                var expr_type = try self.type_inferrer.inferExpr(ce.expr.*);

                // Check pyvalue_vars override - VM fallback variables are typed as PyValue at runtime
                // even if static analysis inferred a specific type (e.g., string for x[1:])
                if (ce.expr.* == .name) {
                    if (self.pyvalue_vars.contains(ce.expr.name.id)) {
                        expr_type = .pyvalue;
                    }
                }

                // Generate expression code first
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};
                try genExpr(self, ce.expr.*);
                // Flush builder before capturing output
                try self.flushBuilder();
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                self.output = saved_output;

                // Handle conversion: !r = repr, !s = str, !a = ascii
                if (ce.conversion == 'r') {
                    // repr() - for strings, wrap in quotes
                    if (string_traits.isString(expr_type)) {
                        try format_buf.writer(self.allocator).writeAll("'{s}'");
                        try args_list.append(self.allocator, expr_code);
                    } else if (expr_type == .int or expr_type == .float or expr_type == .bool) {
                        // For known primitives, use Zig's format
                        const format_spec: []const u8 = switch (expr_type) {
                            .int => "d",
                            .float => "d",
                            .bool => "any",
                            else => unreachable,
                        };
                        try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});
                        try args_list.append(self.allocator, expr_code);
                    } else if (expr_type == .pyvalue) {
                        // For PyValue types, use runtime.builtins.pyRepr
                        try format_buf.writer(self.allocator).writeAll("{s}");
                        const new_expr = try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyRepr(__global_allocator, {s}) catch unreachable)", .{expr_code});
                        try args_list.append(self.allocator, new_expr);
                        self.allocator.free(expr_code);
                    } else {
                        // For other uncertain types, use runtime.builtins.pyRepr
                        try format_buf.writer(self.allocator).writeAll("{s}");
                        const new_expr = try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyRepr(__global_allocator, {s}) catch unreachable)", .{expr_code});
                        try args_list.append(self.allocator, new_expr);
                        self.allocator.free(expr_code);
                    }
                } else {
                    // !s (str) and !a (ascii) - just convert to string
                    if (string_traits.isString(expr_type)) {
                        try format_buf.writer(self.allocator).writeAll("{s}");
                        try args_list.append(self.allocator, expr_code);
                    } else if (expr_type == .int or expr_type == .float) {
                        const format_spec: []const u8 = if (expr_type == .int) "d" else "d";
                        try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});
                        try args_list.append(self.allocator, expr_code);
                    } else if (expr_type == .bool) {
                        try format_buf.writer(self.allocator).writeAll("{}");
                        try args_list.append(self.allocator, expr_code);
                    } else if (expr_type == .pyvalue) {
                        // For PyValue types, use runtime.builtins.pyStr
                        try format_buf.writer(self.allocator).writeAll("{s}");
                        const new_expr = if (at_module_level)
                            try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyStr(__global_allocator, {s}) catch unreachable)", .{expr_code})
                        else
                            try std.fmt.allocPrint(self.allocator, "(try runtime.builtins.pyStr(__global_allocator, {s}))", .{expr_code});
                        try args_list.append(self.allocator, new_expr);
                        self.allocator.free(expr_code);
                    } else {
                        // For other uncertain types, use runtime.builtins.pyStr
                        try format_buf.writer(self.allocator).writeAll("{s}");
                        const new_expr = if (at_module_level)
                            try std.fmt.allocPrint(self.allocator, "(runtime.builtins.pyStr(__global_allocator, {s}) catch unreachable)", .{expr_code})
                        else
                            try std.fmt.allocPrint(self.allocator, "(try runtime.builtins.pyStr(__global_allocator, {s}))", .{expr_code});
                        try args_list.append(self.allocator, new_expr);
                        self.allocator.free(expr_code);
                    }
                }
            },
        }
    }

    // Build args tuple string
    var args_buf = std.ArrayList(u8){};
    defer args_buf.deinit(self.allocator);

    for (args_list.items, 0..) |arg, i| {
        if (i > 0) try args_buf.writer(self.allocator).writeAll(", ");
        try args_buf.writer(self.allocator).writeAll(arg);
    }

    // Generate std.fmt.allocPrint call wrapped in a comptime or runtime block
    if (at_module_level) {
        try self.output.writer(self.allocator).print(
            "(std.fmt.allocPrint(__global_allocator, \"{s}\", .{{ {s} }}) catch unreachable)",
            .{ format_buf.items, args_buf.items },
        );
    } else {
        try self.output.writer(self.allocator).print(
            "(try std.fmt.allocPrint(__global_allocator, \"{s}\", .{{ {s} }}))",
            .{ format_buf.items, args_buf.items },
        );
    }
}

const shared = @import("shared_maps.zig");
const BuiltinFunctions = shared.PythonBuiltinNames;
const PythonExceptions = shared.RuntimeExceptions;

/// Module-level constants that should NOT be prefixed with runtime.builtins.
/// These are defined as local constants in the generated code
const ModuleLevelConstants = std.StaticStringMap(void).initComptime(.{
    .{ "__name__", {} },
    .{ "__file__", {} },
    .{ "__doc__", {} },
    .{ "__package__", {} },
    .{ "__loader__", {} },
    .{ "__spec__", {} },
});

/// Check if a name is a Python builtin function that can be passed as first-class value
fn isBuiltinFunction(name: []const u8) bool {
    // Exclude module-level constants - they're defined locally, not in runtime.builtins
    if (ModuleLevelConstants.has(name)) return false;
    return BuiltinFunctions.has(name);
}

/// Check if a name is a Python exception type
pub fn isPythonExceptionType(name: []const u8) bool {
    return PythonExceptions.has(name);
}
