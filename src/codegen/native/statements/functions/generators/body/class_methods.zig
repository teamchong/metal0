/// Class method generation (init, regular methods, inherited methods)
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const signature = @import("../signature.zig");
const class_fields = @import("class_fields.zig");
const function_traits = @import("analysis.function_traits");
const zig_keywords = @import("utils.zig_keywords");
const generators = @import("../../generators.zig");
const native_types = @import("../../../../../../analysis/native_types/core.zig");
const type_traits = @import("../../../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../../../analysis/traits/string_traits.zig");

// Import from parent for methodMutatesSelf and genMethodBody
const body = @import("../body.zig");
const usage_analysis = @import("usage_analysis.zig");
const function_gen = @import("function_gen.zig");
const param_analyzer = @import("../../param_analyzer.zig");
const local_class_hoisting = @import("local_class_hoisting.zig");

// Re-export from local_class_hoisting for backward compatibility
pub const hoistAllLocalClassesFromMethods = local_class_hoisting.hoistAllLocalClassesFromMethods;
pub const hasSelfAttrAssign = local_class_hoisting.hasSelfAttrAssign;

/// Check if a function body can raise an exception (contains raise statements)
/// This is used to determine if init() should return !@This() instead of @This()
fn bodyCanRaise(stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .raise_stmt => return true,
            .if_stmt => |if_stmt| {
                if (bodyCanRaise(if_stmt.body)) return true;
                if (bodyCanRaise(if_stmt.else_body)) return true;
            },
            .for_stmt => |for_stmt| {
                if (bodyCanRaise(for_stmt.body)) return true;
                if (for_stmt.orelse_body) |orelse_body| {
                    if (bodyCanRaise(orelse_body)) return true;
                }
            },
            .while_stmt => |while_stmt| {
                if (bodyCanRaise(while_stmt.body)) return true;
                if (while_stmt.orelse_body) |orelse_body| {
                    if (bodyCanRaise(orelse_body)) return true;
                }
            },
            .with_stmt => |with_stmt| {
                if (bodyCanRaise(with_stmt.body)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (bodyCanRaise(case.body)) return true;
                }
            },
            // Don't recurse into nested try blocks - their raise is handled locally
            // Don't recurse into nested functions - their raise is local to them
            else => {},
        }
    }
    return false;
}

/// Check if an expression references self.attr (meaning it depends on other fields)
/// This is used to detect computed fields that can't be initialized inline in struct literal
fn exprReferencesSelfAttr(expr: ast.Node) bool {
    return switch (expr) {
        .attribute => |attr| blk: {
            // Check if this is self.attr
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                break :blk true;
            }
            // Recurse on value
            break :blk exprReferencesSelfAttr(attr.value.*);
        },
        .binop => |b| exprReferencesSelfAttr(b.left.*) or exprReferencesSelfAttr(b.right.*),
        .unaryop => |u| exprReferencesSelfAttr(u.operand.*),
        .boolop => |bo| blk: {
            for (bo.values) |v| if (exprReferencesSelfAttr(v)) break :blk true;
            break :blk false;
        },
        .compare => |c| blk: {
            if (exprReferencesSelfAttr(c.left.*)) break :blk true;
            for (c.comparators) |comp| if (exprReferencesSelfAttr(comp)) break :blk true;
            break :blk false;
        },
        .call => |c| blk: {
            if (exprReferencesSelfAttr(c.func.*)) break :blk true;
            for (c.args) |arg| if (exprReferencesSelfAttr(arg)) break :blk true;
            for (c.keyword_args) |kw| if (exprReferencesSelfAttr(kw.value)) break :blk true;
            break :blk false;
        },
        .subscript => |s| blk: {
            if (exprReferencesSelfAttr(s.value.*)) break :blk true;
            // Check slice - it's a Slice union type, not a Node
            switch (s.slice) {
                .index => |idx| if (exprReferencesSelfAttr(idx.*)) break :blk true,
                .slice => |sr| {
                    if (sr.lower) |l| if (exprReferencesSelfAttr(l.*)) break :blk true;
                    if (sr.upper) |u| if (exprReferencesSelfAttr(u.*)) break :blk true;
                    if (sr.step) |st| if (exprReferencesSelfAttr(st.*)) break :blk true;
                },
            }
            break :blk false;
        },
        .if_expr => |ie| exprReferencesSelfAttr(ie.condition.*) or
            exprReferencesSelfAttr(ie.body.*) or
            exprReferencesSelfAttr(ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |el| if (exprReferencesSelfAttr(el)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |el| if (exprReferencesSelfAttr(el)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys, d.values) |k, v| {
                if (exprReferencesSelfAttr(k) or exprReferencesSelfAttr(v)) break :blk true;
            }
            break :blk false;
        },
        .set => |s| blk: {
            for (s.elts) |el| if (exprReferencesSelfAttr(el)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

// Type alias for builtin base info
const BuiltinBaseInfo = generators.BuiltinBaseInfo;

/// Extract the transformation expression from __new__ body for builtin subclasses.
/// Searches for patterns like:
/// - `return float.__new__(cls, expr)` - returns expr
/// - `return super().__new__(cls, expr)` - returns expr
/// - `obj = float.__new__(cls, expr)` - returns expr
/// Returns null if no such pattern is found (fallback to first param).
fn extractBuiltinNewExpr(new_method: ast.Node.FunctionDef) ?ast.Node {
    for (new_method.body) |stmt| {
        // Pattern 1: return <parent>.__new__(cls, expr)
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |return_val| {
                if (extractNewCallExpr(return_val)) |expr| {
                    return expr;
                }
            }
        }
        // Pattern 2: obj = <parent>.__new__(cls, expr)
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (extractNewCallExpr(assign.value)) |expr| {
                return expr;
            }
        }
    }
    return null;
}

/// Extract the second argument (after cls) from a __new__ call.
/// Matches: float.__new__(cls, expr), super().__new__(cls, expr), int.__new__(cls, expr), etc.
fn extractNewCallExpr(node: *ast.Node) ?ast.Node {
    if (node.* != .call) return null;
    const call = node.call;

    // Check if it's a __new__ method call
    if (call.func.* != .attribute) return null;
    const attr = call.func.attribute;
    if (!std.mem.eql(u8, attr.attr, "__new__")) return null;

    // __new__ call found - extract second argument (first is cls)
    // float.__new__(cls, expr) or super().__new__(cls, expr)
    if (call.args.len >= 2) {
        return call.args[1]; // The transformation expression (after cls)
    }
    return null;
}

/// Emit comptime type guard for anytype params (DRY helper)
fn emitComptimeTypeGuard(self: *NativeCodegen, checks: []const function_gen.TypeCheckInfo) CodegenError!void {
    if (checks.len == 0) return;
    try self.emitIndent();
    try self.emit("if (comptime ");
    for (checks, 0..) |check, i| {
        if (i > 0) try self.emit(" and ");
        try self.emit("runtime.istype(@TypeOf(");
        // Use renamed param if available (handles shadowing)
        const param_name = self.var_renames.get(check.param_name) orelse check.param_name;
        try self.emit(param_name);
        try self.emit("), \"");
        try self.emit(check.check_type);
        try self.emit("\")");
    }
    try self.emit(") {\n");
    self.indent();
}

/// Emit captured variable pointer parameters (DRY helper)
fn emitCapturedVarParams(self: *NativeCodegen, class_name: []const u8, captured_vars: ?[][]const u8) CodegenError!void {
    const vars = captured_vars orelse return;
    for (vars) |var_name| {
        try self.emit(", ");
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        const var_type: ?native_types.NativeType = self.type_inferrer.getScopedVar(var_name) orelse
            self.type_inferrer.var_types.get(var_name);
        var zig_type: []const u8 = if (var_type) |vt| blk: {
            vt.toZigType(self.allocator, &type_buf) catch {};
            break :blk if (type_buf.items.len > 0) type_buf.items else "i64";
        } else "i64";
        // Fix empty list type: type inferrer may detect PyObject for mixed/string lists
        if (std.mem.indexOf(u8, zig_type, "std.ArrayList(*runtime.PyObject)") != null) {
            zig_type = "std.ArrayList([]const u8)";
        }
        // Check if zig_type contains a nested class name (self-referential/recursive types)
        var has_nested_class_ref = std.mem.indexOf(u8, zig_type, class_name) != null;
        if (!has_nested_class_ref) {
            var nc_iter = self.nested_class_names.iterator();
            while (nc_iter.next()) |entry| {
                if (std.mem.indexOf(u8, zig_type, entry.key_ptr.*) != null) {
                    has_nested_class_ref = true;
                    break;
                }
            }
        }
        if (has_nested_class_ref) zig_type = "*anyopaque";
        // Check if this captured variable is mutated - use * instead of *const if so
        var mutation_key_buf: [256]u8 = undefined;
        const mutation_key = std.fmt.bufPrint(&mutation_key_buf, "{s}.{s}", .{ class_name, var_name }) catch var_name;
        const is_mutated = self.mutated_captures.contains(mutation_key);
        const ptr_type: []const u8 = if (is_mutated) "*" else "*const";
        try self.output.writer(self.allocator).print("__cap_{s}: {s} {s}", .{ var_name, ptr_type, zig_type });
    }
}

/// Check if a parameter name would shadow a method name in the class
/// Python allows `def __init__(self, real):` and `def real(self):` in the same class,
/// but in Zig these would conflict. We rename params that shadow methods or class attrs.
fn wouldShadowMethodInClass(param_name: []const u8, class_body: []const ast.Node) bool {
    for (class_body) |stmt| {
        // Check for method definitions
        if (stmt == .function_def) {
            const method_name = stmt.function_def.name;
            // Skip __init__ and __new__ - those are the methods we're checking params FOR
            if (std.mem.eql(u8, method_name, "__init__") or std.mem.eql(u8, method_name, "__new__")) {
                continue;
            }
            if (std.mem.eql(u8, param_name, method_name)) {
                return true;
            }
        }
        // Check for class-level assignments (become lazy attrs like `num = property(...)`)
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .name) {
                    if (std.mem.eql(u8, target.name.id, param_name)) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

/// Write init parameter name, renaming if it would shadow a method in the class
fn writeInitParamName(
    self: *NativeCodegen,
    param_name: []const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // First check Zig keywords
    if (zig_keywords.isZigKeyword(param_name)) {
        try self.output.writer(self.allocator).print("@\"{s}\"", .{param_name});
    }
    // Then check if it would shadow a method in this class
    else if (wouldShadowMethodInClass(param_name, class_body)) {
        try self.output.writer(self.allocator).print("{s}_param", .{param_name});
    }
    // Finally check common method names from zig_keywords
    else if (zig_keywords.wouldShadowMethod(param_name)) {
        try self.output.writer(self.allocator).print("{s}_arg", .{param_name});
    } else {
        try self.output.writer(self.allocator).writeAll(param_name);
    }
}

/// Generate default init() method for classes without __init__
/// Nested classes (in nested_class_names) are heap-allocated for Python reference semantics
pub fn genDefaultInitMethod(self: *NativeCodegen, class_name: []const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Check if class is nested (defined inside a function/method)
    // Nested classes need heap allocation for Python reference semantics
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();

    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics (y = x makes y an alias)
        try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator) !*@This() {{\n", .{alloc_name});
        self.indent();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
        self.indent();

        // Initialize __dict__ for dynamic attributes
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    } else {
        // Top-level classes: value semantics (existing behavior)
        try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator) @This() {{\n", .{alloc_name});
        self.indent();

        try self.emitIndent();
        try self.emit("return @This(){\n");
        self.indent();

        // Initialize __dict__ for dynamic attributes
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate default init() method with builtin/complex parent type support
pub fn genDefaultInitMethodWithBuiltinBase(self: *NativeCodegen, class_name: []const u8, builtin_base: ?BuiltinBaseInfo, complex_parent: ?generators.ComplexParentInfo, captured_vars: ?[][]const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();

    // Generate function signature with builtin base args if present
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});
    try emitCapturedVarParams(self, class_name, captured_vars);

    // Add builtin base constructor args
    if (builtin_base) |base_info| {
        for (base_info.init_args) |arg| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
        }
    }

    // Add complex parent constructor args
    if (complex_parent) |parent_info| {
        for (parent_info.init_args) |arg| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
        }
    }

    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Initialize captured variable pointers first
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
        }
    }

    // Initialize builtin base value first
    if (builtin_base) |base_info| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__base_value__ = {s},\n", .{base_info.zig_init});
    }

    // Initialize complex parent fields using field_init (uses constructor args)
    if (complex_parent) |parent_info| {
        for (parent_info.field_init) |fi| {
            try self.emitIndent();
            try self.emit(".");
            try self.emit(fi.field_name);
            try self.emit(" = ");
            // Replace {alloc} with allocator name in init_code
            var i: usize = 0;
            while (i < fi.init_code.len) {
                if (i + 7 <= fi.init_code.len and std.mem.eql(u8, fi.init_code[i .. i + 7], "{alloc}")) {
                    try self.emit(alloc_name);
                    i += 7;
                } else {
                    try self.output.append(self.allocator, fi.init_code[i]);
                    i += 1;
                }
            }
            try self.emit(",\n");
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__
pub fn genInitMethod(
    self: *NativeCodegen,
    class_name: []const u8,
    init_def: ast.Node.FunctionDef,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Track renamed parameters: original name -> renamed name
    // needs_mutable_copy: true if param is reassigned in body, needs a mutable local copy
    const RenamedParam = struct { original: []const u8, renamed: []const u8, needs_mutable_copy: bool };
    var renamed_params: std.ArrayList(RenamedParam) = .{};
    defer {
        // Clean up var_renames for renamed params (only those that were put in var_renames)
        for (renamed_params.items) |entry| {
            if (!entry.needs_mutable_copy) {
                _ = self.var_renames.swapRemove(entry.original);
            }
        }
        renamed_params.deinit(self.allocator);
    }

    // Parameters (skip 'self')
    for (init_def.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        try self.emit(", ");

        // Check if parameter name shadows a class method or class-level attribute
        // e.g., `def real(self)` method or `num = property(...)` class attr conflicts with param of same name
        // Uses the same helper as genInitMethodWithBuiltinBase() for consistency
        const shadows_class_member = if (self.current_class_body) |class_body|
            wouldShadowMethodInClass(arg.name, class_body)
        else
            false;

        // Check if parameter shadows module-level declaration (var, function, import)
        const shadows_module_level = self.module_level_funcs.contains(arg.name) or
            self.module_level_vars.contains(arg.name) or
            self.imported_modules.contains(arg.name);

        // Check if parameter name is assigned in the init body (local var shadows param)
        // e.g., `def __init__(self, d): if not d: d = {}` - the `d = {}` would shadow param
        const shadows_local_assign = param_analyzer.isNameAssignedInInitBody(init_def.body, arg.name);

        // Check if parameter is used in init body (excluding parent __init__ calls)
        // Parent calls are skipped in codegen, so params only used there are unused
        const is_used = param_analyzer.isNameUsedInInitBody(init_def.body, arg.name);
        if (!is_used) {
            // Zig requires unused params to be named just "_", not "_name"
            try self.emit("_: ");
        } else if (shadows_class_member or shadows_module_level or shadows_local_assign) {
            // Rename parameter to avoid shadowing using NameGen
            const renamed = try self.name_gen.param(arg.name);
            try self.emit(renamed);
            try self.emit(": ");
            // Track for var_renames setup later (store both original and renamed)
            // If param is reassigned in body, we'll create a mutable copy instead
            // of putting in var_renames. This allows: var d = __m2_p_d; d = {};
            try renamed_params.append(self.allocator, .{ .original = arg.name, .renamed = renamed, .needs_mutable_copy = shadows_local_assign });
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");
        }

        // Type annotation: prefer type hints, fallback to inference
        if (arg.type_annotation) |_| {
            try self.emit(signature.pythonTypeToZig(arg.type_annotation));
        } else {
            const param_type = try class_fields.inferParamType(self, class_name, init_def, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);

            // Track anytype params for comptime type guard detection
            if (std.mem.eql(u8, param_type, "anytype")) {
                try self.anytype_params.put(arg.name, {});
            }
        }
    }

    // Use @This() for self-referential return type - heap-allocate for nested classes
    // Add error union if __init__ body can raise exceptions
    const can_raise = bodyCanRaise(init_def.body);

    // Track class as having error-returning init for `try` in instantiation calls
    if (can_raise) {
        try self.error_init_classes.put(class_name, {});
    }

    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else if (can_raise) {
        try self.emit(") !@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    // Note: allocator is always used for __dict__ initialization, so no discard needed

    // Add var_renames for parameters that were renamed to avoid shadowing
    // Use the same renamed name from signature generation
    // Skip params with needs_mutable_copy - they get a mutable local copy instead
    for (renamed_params.items) |entry| {
        if (!entry.needs_mutable_copy) {
            try self.var_renames.put(entry.original, entry.renamed);
        }
    }

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, init_def);

    // Generate mutable local copies for params that are reassigned in the body
    // e.g., def __init__(self, d=None): if not d: d = {}
    // Generates: var d: @TypeOf(__m2_p_d) = __m2_p_d;
    for (renamed_params.items) |entry| {
        if (entry.needs_mutable_copy) {
            try self.emitIndent();
            try self.emit("var ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), entry.original);
            try self.emit(": @TypeOf(");
            try self.emit(entry.renamed);
            try self.emit(") = ");
            try self.emit(entry.renamed);
            try self.emit(";\n");
            // Mark as declared so assignment code doesn't try to redeclare
            try self.declareVar(entry.original);
        }
    }

    // Detect type-check-raise patterns at the start of the function body for anytype params
    // These need comptime branching to prevent invalid type instantiations from being analyzed
    const type_checks = try function_gen.detectTypeCheckRaisePatterns(init_def.body, self.anytype_params, self.allocator);
    const body_start_idx = type_checks.start_idx;
    const has_type_checks = type_checks.checks.len > 0;

    if (has_type_checks) try emitComptimeTypeGuard(self, type_checks.checks);

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created
    // Skip the type-check statements that were already handled with comptime branching
    for (init_def.body[body_start_idx..]) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // Generate non-field statements (local var assignments, if statements, etc.)
        if (!is_field_assign) {
            try self.generateStmt(stmt);
        }
    }

    // Check if init body has an unconditional raise/return at top level
    // This makes subsequent code unreachable
    const has_terminating_stmt = blk: {
        for (init_def.body[body_start_idx..]) |stmt| {
            // Check for unconditional raise or return at top level (not in field assignments)
            const is_field_assign = if (stmt == .assign) fa: {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :fa true;
                    }
                }
                break :fa false;
            } else false;

            if (!is_field_assign) {
                if (stmt == .raise_stmt or stmt == .return_stmt) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };

    // If __init__ has unconditional raise/return, skip struct creation (unreachable code)
    if (has_terminating_stmt) {
        // Suppress unused allocator parameter warning
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = {s};\n", .{alloc_name});
        // Close comptime type guard if we opened one
        if (has_type_checks) {
            self.dedent();
            try self.emitIndent();
            try self.emit("} else {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("return error.TypeError;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Generate return statement with field initializers
    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Second pass: extract field assignments from __init__ body
    // Skip the type-check statements that were already handled with comptime branching
    // Also collect deferred assignments (fields that reference self.attr) to emit after struct init
    var deferred_assigns = std.ArrayListUnmanaged(ast.Node){};
    defer deferred_assigns.deinit(self.allocator);

    for (init_def.body[body_start_idx..]) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    // Check if value references self.attr (computed from other fields)
                    // These must be deferred until after struct initialization
                    if (exprReferencesSelfAttr(assign.value.*)) {
                        try deferred_assigns.append(self.allocator, stmt);
                        // Initialize with undefined for now - will be set after struct init
                        try self.emitIndent();
                        try self.emit(".");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                        try self.emit(" = undefined,\n");
                        continue;
                    }

                    try self.emitIndent();
                    // Escape field name if it's a Zig keyword (e.g., "test")
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");
                    // Check if value is an anytype param - wrap with runtime.PyValue.from()
                    // BUT only if the field type is unknown (runtime.PyValue), not a primitive
                    const is_anytype_param = if (assign.value.* == .name)
                        self.anytype_params.contains(assign.value.name.id)
                    else
                        false;

                    // Infer the field type using same logic as class_fields.zig
                    // For parameter references, look up constructor arg types
                    const field_type = blk: {
                        if (assign.value.* == .name) {
                            const value_name = assign.value.name.id;
                            // Check if it's a parameter reference
                            for (init_def.args, 0..) |arg, param_idx| {
                                if (std.mem.eql(u8, arg.name, value_name)) {
                                    // Try type annotation first
                                    var inferred = signature.pythonTypeToNativeType(arg.type_annotation);
                                    std.debug.print("DEBUG class_methods: class={s} field={s} param={s} param_idx={d} annotation_type={}\n", .{ class_name, field_name, arg.name, param_idx, inferred });
                                    // Try keyword arg lookup (stored as "ClassName.param_name")
                                    if (type_traits.isUnknown(inferred)) {
                                        var kwarg_key_buf: [256]u8 = undefined;
                                        const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_name, arg.name }) catch null;
                                        if (kwarg_key) |key| {
                                            if (self.type_inferrer.var_types.get(key)) |kwarg_type| {
                                                inferred = kwarg_type;
                                                std.debug.print("DEBUG class_methods: found kwarg type key={s} type={}\n", .{ key, kwarg_type });
                                            }
                                        }
                                    }
                                    // Try positional constructor arg
                                    if (type_traits.isUnknown(inferred)) {
                                        if (self.type_inferrer.class_constructor_args.get(class_name)) |arg_types| {
                                            const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                                            std.debug.print("DEBUG class_methods: found constructor_args arg_idx={d} len={d}\n", .{ arg_idx, arg_types.len });
                                            if (arg_idx < arg_types.len) {
                                                inferred = arg_types[arg_idx];
                                                std.debug.print("DEBUG class_methods: using constructor_arg type={}\n", .{inferred});
                                            }
                                        } else {
                                            std.debug.print("DEBUG class_methods: NO constructor_args for class={s}\n", .{class_name});
                                        }
                                    }
                                    std.debug.print("DEBUG class_methods: final inferred={}\n", .{inferred});
                                    break :blk inferred;
                                }
                            }
                        }
                        break :blk self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
                    };
                    const is_primitive_field = type_traits.isIntegral(field_type) or
                        type_traits.isFloating(field_type) or
                        field_type == .bool or
                        string_traits.isString(field_type);

                    if (is_anytype_param and !is_primitive_field) {
                        try self.emit("runtime.PyValue.from(");
                        try self.genExpr(assign.value.*);
                        try self.emit(")");
                    } else {
                        try self.genExpr(assign.value.*);
                    }
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Emit deferred field assignments (fields that reference self.attr)
    // For nested classes, use __ptr; for top-level, we're inside return so this shouldn't happen
    if (is_nested and deferred_assigns.items.len > 0) {
        for (deferred_assigns.items) |stmt| {
            const assign = stmt.assign;
            const attr = assign.targets[0].attribute;
            const field_name = attr.attr;

            try self.emitIndent();
            try self.emit("__ptr.");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
            try self.emit(" = ");
            // Temporarily add var_rename for self -> __ptr for this expression
            try self.var_renames.put("self", "__ptr");
            try self.genExpr(assign.value.*);
            _ = self.var_renames.swapRemove("self");
            try self.emit(";\n");
        }
    }

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    // Close comptime type guard if we opened one
    if (has_type_checks) {
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return error.TypeError;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__ with builtin/complex parent type support
pub fn genInitMethodWithBuiltinBase(
    self: *NativeCodegen,
    class_name: []const u8,
    init: ast.Node.FunctionDef,
    builtin_base: ?BuiltinBaseInfo,
    complex_parent: ?generators.ComplexParentInfo,
    captured_vars: ?[][]const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    // Track renamed params for cleanup at end (params that shadow methods or module-level decls)
    // needs_mutable_copy: true if param is reassigned in body, needs a mutable local copy
    const RenamedParamBuiltin = struct { original: []const u8, renamed: []const u8, needs_mutable_copy: bool };
    var renamed_params = std.ArrayList(RenamedParamBuiltin){};
    defer {
        // Clean up var_renames for renamed params (only those that were put in var_renames)
        for (renamed_params.items) |entry| {
            if (!entry.needs_mutable_copy) {
                _ = self.var_renames.swapRemove(entry.original);
            }
        }
        renamed_params.deinit(self.allocator);
    }

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});
    try emitCapturedVarParams(self, class_name, captured_vars);

    // For builtin bases without __init__ body, add the builtin's constructor args
    // Otherwise, use the __init__ parameters
    const has_user_params = init.args.len > 1; // More than just 'self'

    // Don't add builtin base params if the __init__ body just raises (no actual usage)
    const init_only_raises = param_analyzer.isInitBodyOnlyRaises(init.body);

    if (builtin_base != null and !has_user_params and !init_only_raises) {
        // Class inherits from builtin but has no custom __init__ params
        // Use the builtin's constructor args
        if (builtin_base) |base_info| {
            for (base_info.init_args) |arg| {
                try self.emit(", ");
                try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
            }
        }
    } else {
        // Use user-defined __init__ parameters (skip 'self')
        var is_first_param = true;
        for (init.args) |arg| {
            if (std.mem.eql(u8, arg.name, "self")) continue;

            try self.emit(", ");

            // Check if parameter is used in init body (excluding parent __init__ calls)
            // Parent calls are skipped in codegen, so params only used there are unused
            // EXCEPTION: For builtin subclasses, the first parameter is always used for __base_value__
            const is_base_value_param = is_first_param and builtin_base != null;
            const is_used = is_base_value_param or param_analyzer.isNameUsedInInitBody(init.body, arg.name);
            if (!is_used) {
                // Zig requires unused params to be named just "_", not "_name"
                try self.emit("_: ");
            } else {
                // Check if param would shadow a method in the class
                const shadows_class_method = wouldShadowMethodInClass(arg.name, class_body);
                // Check if param would shadow module-level declaration
                const shadows_module_level = self.module_level_funcs.contains(arg.name) or
                    self.module_level_vars.contains(arg.name) or
                    self.imported_modules.contains(arg.name);
                // Check if param would shadow a local variable assignment in init body
                const shadows_local_assign = param_analyzer.isNameAssignedInInitBody(init.body, arg.name);

                if (shadows_class_method or shadows_module_level or shadows_local_assign) {
                    // Rename parameter using NameGen for unique naming
                    const renamed = try self.name_gen.param(arg.name);
                    // If param is reassigned in body, we'll create a mutable copy instead
                    // of putting in var_renames. This allows: var d = __m2_p_d; d = {};
                    if (!shadows_local_assign) {
                        try self.var_renames.put(arg.name, renamed);
                    }
                    try renamed_params.append(self.allocator, .{ .original = arg.name, .renamed = renamed, .needs_mutable_copy = shadows_local_assign });
                    try self.emit(renamed);
                } else {
                    try writeInitParamName(self, arg.name, class_body);
                }
                try self.emit(": ");
            }
            is_first_param = false;

            // Type annotation: prefer type hints, fallback to inference
            if (arg.type_annotation) |_| {
                try self.emit(signature.pythonTypeToZig(arg.type_annotation));
            } else if (is_base_value_param and builtin_base != null) {
                // For builtin subclass, first param type matches the builtin type
                try self.emit(builtin_base.?.zig_type);
            } else {
                const param_type = try class_fields.inferParamType(self, class_name, init, arg.name);
                defer self.allocator.free(param_type);
                try self.emit(param_type);

                // Track anytype params for comptime type guard detection
                if (std.mem.eql(u8, param_type, "anytype")) {
                    try self.anytype_params.put(arg.name, {});
                }
            }
        }
    }

    // Detect type-check-raise patterns at the start of the function body for anytype params
    // These need comptime branching to prevent invalid type instantiations from being analyzed
    // Do this BEFORE emitting return type since it affects whether we need error union
    const type_checks = try function_gen.detectTypeCheckRaisePatterns(init.body, self.anytype_params, self.allocator);
    const body_start_idx = type_checks.start_idx;
    const has_type_checks = type_checks.checks.len > 0;

    // Check if __init__ body can raise exceptions
    const can_raise = bodyCanRaise(init.body);

    // Track class as having error-returning init for `try` in instantiation calls
    if (has_type_checks or can_raise) {
        try self.error_init_classes.put(class_name, {});
    }

    // Use @This() or !@This() for self-referential return type
    // Use error union if we have type checks that may return error.TypeError
    // or if __init__ body can raise exceptions
    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else if (has_type_checks or can_raise) {
        try self.emit(") !@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    // Save and restore control_flow_terminated for init method scope.
    // This is CRITICAL: hoisted local classes or prior method bodies may have set this flag.
    // Without this reset, the First pass loop would skip all statements.
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated;

    // Save and restore pending_discards for init method scope.
    // This prevents variables declared in __init__ from leaking discards into sibling functions.
    const saved_pending_discards = self.pending_discards;
    self.pending_discards = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer {
        self.pending_discards.deinit();
        self.pending_discards = saved_pending_discards;
    }

    // Set captured vars context for expression generation
    // In init, captured vars are accessed via __cap_* params, not self.__captured_*
    self.current_class_captures = captured_vars;
    self.inside_init_method = true;
    defer self.current_class_captures = null;
    defer self.inside_init_method = false;

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, init);

    // Generate mutable local copies for params that are reassigned in the body
    // e.g., def __init__(self, d=None): if not d: d = {}
    // Generates: var d: @TypeOf(__m2_p_d) = __m2_p_d;
    for (renamed_params.items) |entry| {
        if (entry.needs_mutable_copy) {
            try self.emitIndent();
            try self.emit("var ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), entry.original);
            try self.emit(": @TypeOf(");
            try self.emit(entry.renamed);
            try self.emit(") = ");
            try self.emit(entry.renamed);
            try self.emit(";\n");
            // Mark as declared so assignment code doesn't try to redeclare
            try self.declareVar(entry.original);
        }
    }

    if (has_type_checks) try emitComptimeTypeGuard(self, type_checks.checks);

    // Check if init body has an unconditional raise/return at top level
    // This makes subsequent code unreachable
    const has_terminating_stmt = blk: {
        for (init.body[body_start_idx..]) |stmt| {
            // Check for unconditional raise or return at top level (not in field assignments)
            const is_field_assign_check = if (stmt == .assign) fa: {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :fa true;
                    }
                }
                break :fa false;
            } else false;

            if (!is_field_assign_check) {
                if (stmt == .raise_stmt or stmt == .return_stmt) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };

    // If __init__ has unconditional raise/return, emit suppression BEFORE generating statements
    if (has_terminating_stmt) {
        // Suppress unused allocator parameter warning
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = {s};\n", .{alloc_name});
        // Also suppress captured var params
        if (captured_vars) |vars| {
            for (vars) |var_name| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = __cap_{s};\n", .{var_name});
            }
        }
    }

    // Check if nested class has control flow with self.attr assignments inside
    // If so, we need to create __ptr and __self BEFORE processing body statements
    const needs_early_ptr = if (is_nested) blk: {
        for (init.body[body_start_idx..]) |stmt| {
            if (stmt == .if_stmt or stmt == .for_stmt or stmt == .while_stmt or stmt == .try_stmt) {
                // Control flow may contain self.attr assignments that need __self
                if (hasSelfAttrAssign(stmt)) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    } else false;

    if (needs_early_ptr) {
        // Create __ptr and __self early so body statements can use them
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
        self.indent();
        // Initialize captured variable pointers
        if (captured_vars) |vars| {
            for (vars) |var_name| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
            }
        }
        try self.emitIndent();
        try self.emit(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(");
        try self.emit(alloc_name);
        try self.emit("),\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
        try self.emitIndent();
        try self.emit("const __self = __ptr;\n");
    }

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created (unless we did early __ptr)
    // Skip type-check statements if we're using comptime branching
    for (init.body[body_start_idx..]) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // Generate non-field statements (local var assignments, if statements, etc.)
        if (!is_field_assign) {
            try self.generateStmt(stmt);
        }
    }

    // If __init__ has unconditional raise/return, skip struct creation (unreachable code)
    if (has_terminating_stmt) {
        // Close comptime type guard if we opened one
        if (has_type_checks) {
            self.dedent();
            try self.emitIndent();
            try self.emit("} else {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("return error.TypeError;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Generate return statement with field initializers
    // Skip if we already created __ptr early (needs_early_ptr)
    if (is_nested and !needs_early_ptr) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
        self.indent();
        // Initialize captured variable pointers first
        if (captured_vars) |vars| {
            for (vars) |var_name| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
            }
        }
    } else if (!is_nested) {
        try self.emitIndent();
        try self.emit("return @This(){\n");
        self.indent();
        // Initialize captured variable pointers first
        if (captured_vars) |vars| {
            for (vars) |var_name| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
            }
        }
    }

    // Skip struct field initialization when we used early __ptr (already initialized)
    if (needs_early_ptr) {
        // Just return the already-initialized __ptr
        try self.emitIndent();
        try self.emit("return __ptr;\n");

        // Close comptime type guard if we opened one
        if (has_type_checks) {
            self.dedent();
            try self.emitIndent();
            try self.emit("} else {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("return error.TypeError;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Initialize builtin base value first if present
    // Skip if __init__ only raises - no actual initialization happens
    if (builtin_base != null and !init_only_raises) {
        try self.emitIndent();
        // For user-defined __init__, use the first non-self parameter as the base value
        // (e.g., class MyFloat(float): def __init__(self, arg): ... -> use arg as base value)
        // For default init without user params, use the builtin's zig_init (e.g., "value")
        if (has_user_params) {
            // Find first non-self parameter
            for (init.args) |arg| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                // Use the escaped parameter name (handles Zig keywords)
                // Check if param was renamed (e.g., d -> __m2_p_d to avoid shadowing)
                try self.emit(".__base_value__ = ");
                if (self.var_renames.get(arg.name)) |renamed| {
                    try self.emit(renamed);
                } else {
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
                }
                try self.emit(",\n");
                break;
            }
        } else {
            try self.output.writer(self.allocator).print(".__base_value__ = {s},\n", .{builtin_base.?.zig_init});
        }
    }

    // Initialize complex parent fields (e.g., array.array fields)
    if (complex_parent) |parent_info| {
        for (parent_info.fields) |field| {
            // Check if this field is being initialized in __init__ body
            // If so, skip the default - user's init will handle it
            const is_user_initialized = for (init.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            if (std.mem.eql(u8, attr.attr, field.name)) {
                                break true;
                            }
                        }
                    }
                }
            } else false;

            if (!is_user_initialized) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".{s} = {s},\n", .{ field.name, field.default });
            }
        }
    }

    // Second pass: extract field assignments from __init__ body
    // Skip type-check statements if we're using comptime branching
    // Track deferred fields that reference self.attr (can't be initialized inline)
    var deferred_fields: std.ArrayList(struct { name: []const u8, value: *ast.Node, is_anytype: bool }) = .{};
    defer deferred_fields.deinit(self.allocator);

    for (init.body[body_start_idx..]) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    // Check if value references self.attr - these must be deferred
                    const needs_deferral = exprReferencesSelfAttr(assign.value.*);

                    try self.emitIndent();
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");

                    if (needs_deferral) {
                        // Initialize with undefined, will assign after struct is created
                        try self.emit("undefined");
                        // Check if value is an anytype param
                        const is_anytype_param = if (assign.value.* == .name)
                            self.anytype_params.contains(assign.value.name.id)
                        else
                            false;
                        try deferred_fields.append(self.allocator, .{
                            .name = field_name,
                            .value = assign.value,
                            .is_anytype = is_anytype_param,
                        });
                    } else {
                        // Check if value is an anytype param - wrap with runtime.PyValue.from()
                        // BUT only if the field type is unknown (runtime.PyValue), not a primitive
                        const is_anytype_param = if (assign.value.* == .name)
                            self.anytype_params.contains(assign.value.name.id)
                        else
                            false;

                        // Infer the field type to determine if wrapping is needed
                        const field_type = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
                        const is_primitive_field = type_traits.isIntegral(field_type) or
                            type_traits.isFloating(field_type) or
                            field_type == .bool or
                            string_traits.isString(field_type);

                        if (is_anytype_param and !is_primitive_field) {
                            try self.emit("runtime.PyValue.from(");
                            try self.genExpr(assign.value.*);
                            try self.emit(")");
                        } else {
                            try self.genExpr(assign.value.*);
                        }
                    }
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Handle deferred field assignments (fields that reference self.attr)
    // These must be assigned after the struct is created
    if (deferred_fields.items.len > 0) {
        // For non-nested classes, we need to capture the return value
        if (!is_nested) {
            // We emitted "return @This(){...};" but need "const __ptr = @This(){...};"
            // This requires restructuring - for now, use nested class pattern
            // Actually, for non-nested we can't easily change the return to a local
            // Let's use a different approach: __ptr pattern for all cases with deferred fields
            // But that would require changing earlier code...
            // For now, emit a warning that this pattern isn't supported for non-nested
            // TODO: Restructure to support deferred fields in non-nested classes
        }
        // For nested classes, __ptr is available
        if (is_nested) {
            // Set up var_rename: self -> __ptr for expression generation
            // Also temporarily disable nested class "self" -> "__self" transformation
            // by setting method_nesting_depth = 0 and removing "self" from func_local_vars
            try self.var_renames.put("self", "__ptr");
            const saved_nesting_depth = self.method_nesting_depth;
            self.method_nesting_depth = 0;
            const self_was_local = self.func_local_vars.contains("self");
            _ = self.func_local_vars.swapRemove("self");

            for (deferred_fields.items) |field| {
                try self.emitIndent();
                try self.emit("__ptr.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field.name);
                try self.emit(" = ");
                if (field.is_anytype) {
                    try self.emit("runtime.PyValue.from(");
                    try self.genExpr(field.value.*);
                    try self.emit(")");
                } else {
                    try self.genExpr(field.value.*);
                }
                try self.emit(";\n");
            }

            // Restore state
            self.method_nesting_depth = saved_nesting_depth;
            if (self_was_local) {
                try self.func_local_vars.put("self", {});
            }
            _ = self.var_renames.swapRemove("self");
        }
    }

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    // Close comptime type guard if we opened one
    if (has_type_checks) {
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return error.TypeError;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __new__ when no __init__ exists
/// Python's __new__ is a class method that creates the instance, but metal0 needs
/// a regular init() function. We use __new__'s parameters (skipping cls) for init.
pub fn genInitMethodFromNew(
    self: *NativeCodegen,
    class_name: []const u8,
    new_method: ast.Node.FunctionDef,
    builtin_base: ?BuiltinBaseInfo,
    complex_parent: ?generators.ComplexParentInfo,
    captured_vars: ?[][]const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    // Track renamed params for cleanup at end (params that shadow methods or module-level decls)
    // needs_mutable_copy: true if param is reassigned in body, needs a mutable local copy
    const RenamedParamNew = struct { original: []const u8, renamed: []const u8, needs_mutable_copy: bool };
    var renamed_params = std.ArrayList(RenamedParamNew){};
    defer {
        // Clean up var_renames for renamed params (only those that were put in var_renames)
        for (renamed_params.items) |entry| {
            if (!entry.needs_mutable_copy) {
                _ = self.var_renames.swapRemove(entry.original);
            }
        }
        renamed_params.deinit(self.allocator);
    }

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});
    try emitCapturedVarParams(self, class_name, captured_vars);

    // Use __new__ parameters (skip 'cls' - first param)
    // __new__ signature: def __new__(cls, arg, newarg=None): ...
    // init signature should be: init(allocator, arg, newarg)
    var is_first_non_cls = true;
    for (new_method.args) |arg| {
        // Skip 'cls' or 'self' (first param of __new__ represents the class, not an instance value)
        if (std.mem.eql(u8, arg.name, "cls") or std.mem.eql(u8, arg.name, "self")) continue;

        try self.emit(", ");

        // For builtin subclass, the first non-cls parameter is the base value
        const is_base_value_param = is_first_non_cls and builtin_base != null;
        // For __new__, only field assignments (self.x = param) count as "used" for init()
        // Return statements like `return meta(name, bases, d)` don't translate to init() body
        const is_used = is_base_value_param or param_analyzer.isNameUsedInNewForInit(new_method.body, arg.name);
        if (!is_used) {
            // Zig requires unused params to be named just "_", not "_name"
            try self.emit("_: ");
        } else {
            // Check if param would shadow a method in the class
            const shadows_class_method = wouldShadowMethodInClass(arg.name, class_body);
            // Check if param would shadow module-level declaration
            const shadows_module_level = self.module_level_funcs.contains(arg.name) or
                self.module_level_vars.contains(arg.name) or
                self.imported_modules.contains(arg.name);
            // Check if param is 'self' in nested class (would shadow outer method's self)
            const shadows_outer_self = is_nested and std.mem.eql(u8, arg.name, "self");
            // Check if param would shadow a local variable assignment in __new__ body
            const shadows_local_assign = param_analyzer.isNameAssignedInInitBody(new_method.body, arg.name);

            if (shadows_class_method or shadows_module_level or shadows_outer_self or shadows_local_assign) {
                // Rename parameter using NameGen for unique naming
                const renamed = try self.name_gen.param(arg.name);
                // If param is reassigned in body, we'll create a mutable copy instead
                // of putting in var_renames. This allows: var d = __m2_p_d; d = {};
                if (!shadows_local_assign) {
                    try self.var_renames.put(arg.name, renamed);
                }
                try renamed_params.append(self.allocator, .{ .original = arg.name, .renamed = renamed, .needs_mutable_copy = shadows_local_assign });
                try self.emit(renamed);
            } else {
                try writeInitParamName(self, arg.name, class_body);
            }
            try self.emit(": ");
        }
        is_first_non_cls = false;

        // Type annotation: prefer type hints, fallback to inference
        if (arg.type_annotation) |_| {
            try self.emit(signature.pythonTypeToZig(arg.type_annotation));
        } else if (is_base_value_param and builtin_base != null) {
            // For builtin subclass, first param type matches the builtin type
            try self.emit(builtin_base.?.zig_type);
        } else {
            const param_type = try class_fields.inferParamType(self, class_name, new_method, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);
        }
    }

    // Use @This() for self-referential return type
    // Nested classes need error union with pointer for heap allocation
    // Also check if __new__ body can raise exceptions
    const can_raise = bodyCanRaise(new_method.body);

    // Track class as having error-returning init for `try` in instantiation calls
    if (can_raise) {
        try self.error_init_classes.put(class_name, {});
    }

    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else if (can_raise) {
        try self.emit(") !@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    // Set captured vars context for expression generation
    self.current_class_captures = captured_vars;
    self.inside_init_method = true;
    defer self.current_class_captures = null;
    defer self.inside_init_method = false;

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, new_method);

    // Generate mutable local copies for params that are reassigned in the body
    // e.g., def __new__(cls, d=None): if not d: d = {}
    // Generates: var d: @TypeOf(__m2_p_d) = __m2_p_d;
    for (renamed_params.items) |entry| {
        if (entry.needs_mutable_copy) {
            try self.emitIndent();
            try self.emit("var ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), entry.original);
            try self.emit(": @TypeOf(");
            try self.emit(entry.renamed);
            try self.emit(") = ");
            try self.emit(entry.renamed);
            try self.emit(";\n");
            // Mark as declared so assignment code doesn't try to redeclare
            try self.declareVar(entry.original);
        }
    }

    // Find the variable name used to receive super().__new__() result
    // Common patterns: obj = super().__new__(cls, ...) or self = super().__new__(cls, ...)
    var instance_var_name: []const u8 = "self"; // default fallback
    for (new_method.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                // Check if RHS is super().__new__() call
                if (assign.value.* == .call) {
                    const call = assign.value.call;
                    if (call.func.* == .attribute) {
                        const attr = call.func.attribute;
                        if (std.mem.eql(u8, attr.attr, "__new__")) {
                            // Found it! Get the variable name
                            instance_var_name = assign.targets[0].name.id;
                            break;
                        }
                    }
                }
            }
        }
    }

    // First pass: generate non-field statements from __new__ body
    // Skip super().__new__() calls, instance var assignments, and return statements
    for (new_method.body) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    // Check for obj.x = ... where obj is the instance variable
                    if (attr.value.* == .name) {
                        const target_name = attr.value.name.id;
                        // Match against the detected instance variable name (obj, self, etc.)
                        if (std.mem.eql(u8, target_name, instance_var_name)) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };

        const is_super_new_or_return = blk: {
            // Skip: obj = super().__new__(cls, arg) or self = super().__new__(...)
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .name) {
                    const var_name = assign.targets[0].name.id;
                    // Skip assignment to instance variable (obj = super().__new__(...))
                    if (std.mem.eql(u8, var_name, instance_var_name)) {
                        break :blk true;
                    }
                }
            }
            // Skip: return obj or return self
            if (stmt == .return_stmt) {
                break :blk true;
            }
            break :blk false;
        };

        // Generate non-field, non-super-new statements
        if (!is_field_assign and !is_super_new_or_return) {
            try self.generateStmt(stmt);
        }
    }

    // Generate return statement with field initializers
    // Nested classes use heap allocation for Python reference semantics
    if (is_nested) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Initialize captured variable pointers first
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
        }
    }

    // Initialize builtin base value first if present
    // For __new__ methods that transform the value (e.g., float.__new__(cls, 2*value)),
    // we extract the transformation expression instead of using the raw parameter.
    if (builtin_base) |_| {
        try self.emitIndent();
        try self.emit(".__base_value__ = ");
        // Extract transformation expr from float.__new__(cls, expr) or super().__new__(cls, expr)
        if (extractBuiltinNewExpr(new_method)) |expr| {
            try self.genExpr(expr);
        } else {
            // Fallback: use first non-cls parameter
            for (new_method.args) |arg| {
                if (std.mem.eql(u8, arg.name, "cls")) continue;
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
                break;
            }
        }
        try self.emit(",\n");
    }

    // Initialize complex parent fields
    if (complex_parent) |parent_info| {
        for (parent_info.fields) |field| {
            const is_user_initialized = for (new_method.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        // Use detected instance variable name (obj, self, etc.)
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, instance_var_name)) {
                            if (std.mem.eql(u8, attr.attr, field.name)) {
                                break true;
                            }
                        }
                    }
                }
            } else false;

            if (!is_user_initialized) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".{s} = {s},\n", .{ field.name, field.default });
            }
        }
    }

    // Second pass: extract field assignments from __new__ body (obj.x = value or self.x = value)
    for (new_method.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                // Use detected instance variable name (obj, self, etc.)
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, instance_var_name)) {
                    const field_name = attr.attr;

                    try self.emitIndent();
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");
                    // Check if value is an anytype param - wrap with runtime.PyValue.from()
                    // BUT only if the field type is unknown (runtime.PyValue), not a primitive
                    const is_anytype_param = if (assign.value.* == .name)
                        self.anytype_params.contains(assign.value.name.id)
                    else
                        false;

                    // Infer the field type to determine if wrapping is needed
                    const field_type = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
                    const is_primitive_field = type_traits.isIntegral(field_type) or
                        type_traits.isFloating(field_type) or
                        field_type == .bool or
                        string_traits.isString(field_type);

                    if (is_anytype_param and !is_primitive_field) {
                        try self.emit("runtime.PyValue.from(");
                        try self.genExpr(assign.value.*);
                        try self.emit(")");
                    } else {
                        try self.genExpr(assign.value.*);
                    }
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate regular class methods (non-__init__)
pub fn genClassMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    captured_vars: ?[][]const u8,
) CodegenError!void {
    // Save previous class context (for nested classes inside methods)
    const prev_class_name = self.current_class_name;
    const prev_captures = self.current_class_captures;
    const prev_parent = self.current_class_parent;

    // Set current class name for super() support and self.method() allocator detection
    self.current_class_name = class.name;
    defer self.current_class_name = prev_class_name;

    // Set current class's captured variables for expression generation
    // This allows the expression generator to convert `var_name` to `self.__captured_var_name.*`
    self.current_class_captures = captured_vars;
    defer self.current_class_captures = prev_captures;

    // Set current class parent for parent method call resolution (e.g., array.array.__getitem__(self, i))
    if (class.bases.len > 0) {
        self.current_class_parent = class.bases[0];
    }
    defer self.current_class_parent = prev_parent;

    // Check if __init__ exists - if not, __new__ is used to generate init() and shouldn't be emitted as a method
    var has_init = false;
    for (class.body) |stmt| {
        if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__")) {
            has_init = true;
            break;
        }
    }

    // In Python, methods can be "overridden" within the same class (e.g., @property + @foo.setter)
    // Zig doesn't allow duplicate struct member names, so we find the LAST occurrence of each method
    // and only generate that one (Python semantics: later definition shadows earlier ones)
    var last_method_indices = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer last_method_indices.deinit();

    // First pass: find the last index for each method name
    for (class.body, 0..) |stmt, idx| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;
            try last_method_indices.put(method.name, idx);
        }
    }

    // Note: hoisting of local classes is now done in genClassDef via hoistAllLocalClassesFromMethods
    // This ensures hoisted classes appear before ALL methods (including init)

    // Second pass: only generate methods at their last occurrence index
    for (class.body, 0..) |stmt, idx| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;
            // Skip __new__ if there's no __init__ - __new__ was used to generate init()
            if (std.mem.eql(u8, method.name, "__new__") and !has_init) continue;

            // Skip if this is not the last occurrence of this method name
            if (last_method_indices.get(method.name)) |last_idx| {
                if (idx != last_idx) continue;
            }

            const mutates_self = body.methodMutatesSelf(method);
            // Use analyzeNeedsAllocator to detect same-class constructor calls like Rat(x)
            const needs_allocator = function_traits.analyzeNeedsAllocator(method, class.name);
            const actually_uses_allocator = function_traits.analyzeUsesAllocatorParam(method, class.name);

            // Track allocator needs for nested class methods so call sites know whether to pass allocator
            // This is needed because nested classes are not in the class_registry
            if (self.nested_class_names.contains(class.name) and needs_allocator) {
                const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                try self.nested_class_method_needs_alloc.put(method_key, {});
            }

            // Note: hoisting of local classes is done in the pre-hoist pass above

            // Generate method signature
            // Note: method_nesting_depth tracks whether we're inside a NESTED class inside a method
            // It's incremented when we enter a class inside a method body, not when we enter a method itself
            try signature.genMethodSignatureWithSkip(self, class.name, method, mutates_self, needs_allocator, false, actually_uses_allocator);

            // Track method signature for default parameter handling at call sites
            // Count non-self params and how many have defaults
            var required_count: usize = 0;
            var total_count: usize = 0;
            // Also extract non-self parameter names for keyword argument mapping
            var param_name_list = std.ArrayList([]const u8){};
            defer param_name_list.deinit(self.allocator);
            for (method.args) |arg| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                total_count += 1;
                if (arg.default == null) required_count += 1;
                try param_name_list.append(self.allocator, arg.name);
            }
            // Store as "ClassName.method_name" for method call lookup
            if (total_count > required_count) {
                const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                const param_names = try param_name_list.toOwnedSlice(self.allocator);
                try self.function_signatures.put(method_key, .{
                    .total_params = total_count,
                    .required_params = required_count,
                    .param_names = param_names,
                });
            }

            // Check if this method returns a lambda that captures self (closure)
            // Register it so that callers can mark the variable as a closure
            if (signature.getReturnedLambda(method.body)) |lambda| {
                if (signature.lambdaCapturesSelf(lambda.body.*)) {
                    // Register as "ClassName.method_name"
                    const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                    try self.closure_returning_methods.put(key, {});
                }
            }

            // Set current function name for comparisons in method body
            // (used for detecting optional parameter comparisons like "base is None")
            const prev_func_name = self.current_function_name;
            self.current_function_name = method.name;
            defer self.current_function_name = prev_func_name;

            // Set current function body for lookahead-based type inference
            // (e.g., inferring dict key type from subsequent subscript assignments)
            const prev_func_body = self.current_function_body;
            self.current_function_body = method.body;
            defer self.current_function_body = prev_func_body;

            // Track whether self is mutable for return dereference handling
            // When method mutates self and returns self, we need: return __self.*;
            const prev_self_mutable = self.method_self_is_mutable;
            self.method_self_is_mutable = mutates_self;
            defer self.method_self_is_mutable = prev_self_mutable;

            // Track whether we're inside __new__ method (uses __cls, not __self)
            const is_new_method = std.mem.eql(u8, method.name, "__new__");
            const prev_inside_new = self.inside_new_method;
            if (is_new_method) self.inside_new_method = true;
            defer self.inside_new_method = prev_inside_new;

            // Track whether we're inside a classmethod (no self/__self, captured vars need special access)
            // Both explicit @classmethod and implicit classmethods like __init_subclass__/__class_getitem__
            const is_implicit_classmethod = std.mem.eql(u8, method.name, "__init_subclass__") or
                std.mem.eql(u8, method.name, "__class_getitem__");
            const is_classmethod = signature.hasClassmethodDecorator(method.decorators) or is_implicit_classmethod;
            const prev_inside_classmethod = self.inside_classmethod;
            if (is_classmethod) self.inside_classmethod = true;
            defer self.inside_classmethod = prev_inside_classmethod;

            // IMPORTANT: We preserve var_renames here rather than clearing them.
            // Outer closure parameter renames (e.g., meta -> __p_meta_23) need to
            // remain visible so nested class methods can reference outer scope params.
            // The concern about builtin shadowing (e.g., object -> object__123) is
            // handled by the fact that param_renames only contains actual parameters,
            // not arbitrary shadowed names.

            try body.genMethodBodyWithAllocatorInfo(self, method, needs_allocator, actually_uses_allocator);
        }
    }
}


/// Generate inherited methods from parent class (recursively includes grandparents)
pub fn genInheritedMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    child_method_names: []const []const u8,
) CodegenError!void {
    // Track methods we've already generated to avoid duplicates from grandparents
    var generated_methods = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_methods.deinit();

    // Add all child method names to avoid re-inheriting overridden methods
    for (child_method_names) |name| {
        try generated_methods.put(name, {});
    }

    // Also check for class attribute assignments that block inheritance (e.g., __iadd__ = None)
    for (class.body) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .name) {
                    try generated_methods.put(target.name.id, {});
                }
            }
        }
    }

    // Recursively inherit from parent chain
    try inheritMethodsFromClass(self, class, parent, &generated_methods);
}

/// Generate PolymorphicReturn__ helper functions for methods that need them
/// These functions compute return type at comptime based on the input parameter type
pub fn genPolymorphicReturnHelpers(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
) CodegenError!void {
    // First pass: collect all method parameter types we'll need
    // We need to detect which methods have polymorphic return patterns
    for (class.body) |stmt| {
        if (stmt != .function_def) continue;
        const method = stmt.function_def;
        if (std.mem.eql(u8, method.name, "__init__")) continue;

        // Check if this method has the polymorphic pattern
        if (!hasPolymorphicReturnPatternForClass(method, class.name)) continue;

        // Generate the PolymorphicReturn__ helper function
        try self.emit("\n");
        try self.emitIndent();
        try self.emit("// Comptime return type for polymorphic method\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("fn PolymorphicReturn__{s}(comptime T: type) type {{\n", .{method.name});
        self.indent();

        // Generate comptime type dispatch
        // All branches return error union for consistency (self.__float__() can fail)
        try self.emitIndent();
        try self.emit("if (comptime @typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return anyerror!f64;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return anyerror!@This();\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }
}

/// Check if a method has polymorphic return pattern (for class context)
/// This detects methods that return different types based on input:
/// - Rat for int/Rat inputs
/// - f64 for float inputs
fn hasPolymorphicReturnPatternForClass(method: ast.Node.FunctionDef, class_name: []const u8) bool {
    _ = class_name;
    // Look for pattern: if isnum(other): return float(self) + other <- returns f64
    // when other branches return Rat via Rat.init() or @This().init()

    var has_class_return = false;
    var has_float_return = false;

    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;
        const func_name = call.func.name.id;

        // Check for isint/isRat returning class instance
        if (std.mem.eql(u8, func_name, "isint") or std.mem.eql(u8, func_name, "isRat") or std.mem.eql(u8, func_name, "isinstance")) {
            for (if_stmt.body) |body_stmt| {
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        // Check if returning class constructor call
                        if (val.* == .call and val.call.func.* == .name) {
                            has_class_return = true;
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, func_name, "isnum")) {
            // Check if body returns float operation
            for (if_stmt.body) |body_stmt| {
                if (body_stmt != .return_stmt) continue;
                if (body_stmt.return_stmt.value) |val| {
                    if (val.* == .binop or val.* == .call) {
                        // float(self) + other or runtime.divideFloat(...) or similar
                        has_float_return = true;
                    }
                }
            }
        }
    }

    // Polymorphic pattern: both class return AND float return paths exist
    return has_class_return and has_float_return;
}

/// Recursively inherit methods from a class and its parents
fn inheritMethodsFromClass(
    self: *NativeCodegen,
    child: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    generated_methods: *hashmap_helper.StringHashMap(void),
) CodegenError!void {
    // First, recursively inherit from grandparents (so grandparent methods come first)
    if (parent.bases.len > 0) {
        const grandparent_name = parent.bases[0];
        // Look up grandparent class
        var grandparent = self.class_registry.getClass(grandparent_name);
        if (grandparent == null) {
            grandparent = self.nested_class_defs.get(grandparent_name);
        }
        if (grandparent) |gp| {
            try inheritMethodsFromClass(self, child, gp, generated_methods);
        }
    }

    // Now inherit methods from this parent
    for (parent.body) |parent_stmt| {
        if (parent_stmt == .function_def) {
            const parent_method = parent_stmt.function_def;
            if (std.mem.eql(u8, parent_method.name, "__init__")) continue;

            // Skip if already generated (from child or earlier in chain)
            if (generated_methods.contains(parent_method.name)) continue;

            // Mark as generated
            try generated_methods.put(parent_method.name, {});

            // Copy parent method to child class
            const mutates_self = body.methodMutatesSelf(parent_method);
            // Use analyzeNeedsAllocator with parent class name for inherited methods
            const needs_allocator = function_traits.analyzeNeedsAllocator(parent_method, parent.name);
            const actually_uses_allocator = function_traits.analyzeUsesAllocatorParam(parent_method, parent.name);

            // Before generating signature, add parent to nested_class_names for return type detection
            // (e.g., aug_test.__add__ returns aug_test(...) which needs parent to be known)
            try self.nested_class_names.put(parent.name, {});

            // For inherited methods that use captured variables, set current_class_captures
            // BEFORE signature generation so signature knows to use __self instead of _
            const child_captures = self.nested_class_captures.get(child.name);
            const prev_captures = self.current_class_captures;
            if (child_captures) |captures| {
                self.current_class_captures = captures;
            }
            defer self.current_class_captures = prev_captures;

            // Use genMethodSignatureWithSkip to properly pass actually_uses_allocator flag
            try signature.genMethodSignatureWithSkip(self, child.name, parent_method, mutates_self, needs_allocator, false, actually_uses_allocator);

            // Track whether self is mutable for return dereference handling
            const prev_self_mutable = self.method_self_is_mutable;
            self.method_self_is_mutable = mutates_self;
            defer self.method_self_is_mutable = prev_self_mutable;

            // Track whether we're inside a classmethod for inherited methods
            const is_implicit_classmethod = std.mem.eql(u8, parent_method.name, "__init_subclass__") or
                std.mem.eql(u8, parent_method.name, "__class_getitem__");
            const is_classmethod = signature.hasClassmethodDecorator(parent_method.decorators) or is_implicit_classmethod;
            const prev_inside_classmethod = self.inside_classmethod;
            if (is_classmethod) self.inside_classmethod = true;
            defer self.inside_classmethod = prev_inside_classmethod;

            // For inherited methods, pass the parent class name so method body can call its constructor
            // (e.g., aug_test.__add__ returns aug_test(...) - when inherited to aug_test4,
            // the method body needs to know aug_test is a nested class for allocator handling)
            try body.genMethodBodyWithContext(self, parent_method, &[_][]const u8{parent.name});
        }
    }
}
