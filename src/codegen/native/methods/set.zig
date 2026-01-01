/// Set methods - .add(), .remove(), .discard(), .clear(), .copy(), .update(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const expr_emitter = @import("../expr_emitter.zig");
const expressions = @import("../expressions.zig");
const producesBlockExpression = expressions.producesBlockExpression;
const emitObjExpr = expressions.emitObjExpr;

/// Helper: emit runtime.pySetAddPV(__global_allocator, &obj, runtime.PyValue.from(elem)) with bracket matching
/// Context-aware try: at module level uses `catch unreachable`, in functions uses `try`
fn emitPySetAddPV(self: *NativeCodegen, obj: ast.Node, elem: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    const Ctx = struct { o: ast.Node, e: ast.Node };
    try self.emitCallCtx("runtime.pySetAddPV", Ctx{ .o = obj, .e = elem }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try s.genExpr(ctx.o);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.e, struct {
                pub fn inner(ss: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try ss.genExpr(e);
                }
            }.inner);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
}

/// Helper: emit runtime.pySetRemovePV(__global_allocator, &obj, runtime.PyValue.from(elem)) with bracket matching
/// Context-aware try: at module level uses `catch unreachable`, in functions uses `try`
fn emitPySetRemovePV(self: *NativeCodegen, obj: ast.Node, elem: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    const Ctx = struct { o: ast.Node, e: ast.Node };
    try self.emitCallCtx("runtime.pySetRemovePV", Ctx{ .o = obj, .e = elem }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try s.genExpr(ctx.o);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.e, struct {
                pub fn inner(ss: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try ss.genExpr(e);
                }
            }.inner);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
}

/// Helper: emit runtime.pySetDiscardPV(__global_allocator, &obj, runtime.PyValue.from(elem)) with bracket matching
fn emitPySetDiscardPV(self: *NativeCodegen, obj: ast.Node, elem: ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, e: ast.Node };
    try self.emitCallCtx("runtime.pySetDiscardPV", Ctx{ .o = obj, .e = elem }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try s.genExpr(ctx.o);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.e, struct {
                pub fn inner(ss: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try ss.genExpr(e);
                }
            }.inner);
        }
    }.f);
}

/// Helper: emit runtime.pySetClearPV(&obj) with bracket matching
fn emitPySetClearPV(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.pySetClearPV", obj, struct {
        pub fn f(s: *NativeCodegen, o: ast.Node) CodegenError!void {
            try s.emit("&");
            try s.genExpr(o);
        }
    }.f);
}

/// Helper: emit try runtime.pySetPopPVFunc(__global_allocator, &obj) with bracket matching
/// Context-aware try: at module level uses `catch unreachable`, in functions uses `try`
fn emitPySetPopPVFunc(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    try self.emitCallCtx("runtime.pySetPopPVFunc", obj, struct {
        pub fn f(s: *NativeCodegen, o: ast.Node) CodegenError!void {
            try s.emit("__global_allocator, &");
            try s.genExpr(o);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
}

// isSetUncertain replaced by self.isExprUncertain() (DRY consolidation)

// emitObjExpr imported from expressions.zig (DRY consolidation)

/// Generate code for set.add(elem)
/// Adds element to set (no-op if already present)
/// Two-Flow: Certain sets use HashMap.put, uncertain use runtime.pySetAdd
pub fn genAdd(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.add() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (self.isExprUncertain(obj)) {
        // Route to runtime helper for PyValue sets
        try emitPySetAddPV(self, obj, args[0]);
        return;
    }

    // Generate: try set.put(elem, {})
    // Zig HashMap uses put(key, value) - for sets, value is void ({})
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".put(");
    try self.genExpr(args[0]);
    try self.emit(", {})");
}

/// Generate code for set.remove(elem)
/// Removes element, raises KeyError if not present
/// Two-Flow: Certain sets use runtime.set_ops, uncertain use runtime.pySetRemove
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.remove() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (self.isExprUncertain(obj)) {
        // Route to runtime helper for PyValue sets
        try emitPySetRemovePV(self, obj, args[0]);
        return;
    }

    // Use runtime helper to avoid comptime explosion from @hasDecl/@TypeOf inline checks
    // runtime.set_ops.SetOps(KeyType).remove(&set, key) handles AutoHashMap vs ArrayHashMap
    // Context-aware try: at module level uses `catch unreachable`, in functions uses `try`
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("runtime.set_ops.SetOps", Ctx{ .o = obj, .a = args[0] }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitCallCtx("@TypeOf", ctx.a, struct {
                pub fn g(s2: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s2.genExpr(e);
                }
            }.g);
            try s.emit(").remove(&");
            try emitObjExpr(s, ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.a);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
}

/// Generate code for set.discard(elem)
/// Removes element if present (no error if missing)
/// Two-Flow: Certain sets use runtime.set_ops, uncertain use runtime.pySetDiscard
pub fn genDiscard(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // set.discard() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (self.isExprUncertain(obj)) {
        // Route to runtime helper for PyValue sets
        try emitPySetDiscardPV(self, obj, args[0]);
        return;
    }

    // Use runtime helper to avoid comptime explosion from @hasDecl/@TypeOf inline checks
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("runtime.set_ops.SetOps", Ctx{ .o = obj, .a = args[0] }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitCallCtx("@TypeOf", ctx.a, struct {
                pub fn g(s2: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s2.genExpr(e);
                }
            }.g);
            try s.emit(").discard(&");
            try emitObjExpr(s, ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.a);
        }
    }.f);
}

/// Generate code for set.clear()
/// Two-Flow: Certain sets use clearRetainingCapacity, uncertain use runtime.pySetClear
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (self.isExprUncertain(obj)) {
        // Route to runtime helper for PyValue sets
        try emitPySetClearPV(self, obj);
        return;
    }

    try emitObjExpr(self, obj);
    // std.AutoHashMap uses clearRetainingCapacity() or clearAndFree()
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for set.pop()
/// Remove and return arbitrary element, raises KeyError if empty
/// Two-Flow: Certain sets use runtime.set_ops.pop, uncertain use runtime.pySetPop
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Two-Flow: Check if set is uncertain (PyValue or unknown type)
    if (self.isExprUncertain(obj)) {
        // Route to runtime helper for PyValue sets
        try emitPySetPopPVFunc(self, obj);
        return;
    }

    // Use runtime helper to avoid comptime explosion
    // Get key type from set's KV struct
    // Context-aware try: at module level uses `catch unreachable`, in functions uses `try`
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    try self.emitCallCtx("runtime.set_ops.SetOps", obj, struct {
        pub fn f(s: *NativeCodegen, o: ast.Node) CodegenError!void {
            try s.emit("std.meta.fieldInfo(");
            try s.emitCallCtx("@TypeOf", o, struct {
                pub fn g(s2: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try emitObjExpr(s2, e);
                }
            }.g);
            try s.emit(".Unmanaged.KV, .key).type).pop(&");
            try emitObjExpr(s, o);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
}

/// Generate code for set.copy()
/// Returns shallow copy of set
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const copy = try self.name_gen.temp();
    const iter = try self.name_gen.temp();

    // Generate a block that creates new set and copies elements
    try self.output.writer(self.allocator).print("(scopy_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{copy});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{iter});
    self.indent_level += 1;
    try self.emitIndent();
    // Check inside_defer - can't use try inside defer blocks
    if (self.inside_defer) {
        try self.output.writer(self.allocator).print("{s}.put(entry.key_ptr.*, {{}}) catch {{}};\n", .{copy});
    } else {
        try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{copy});
    }
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :scopy_{d} {s};\n", .{ label_id, copy });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.update(*others)
/// Adds all elements from all other iterables (in-place)
/// Returns None in Python
/// - No args: no-op (but valid Python)
/// - One or more args: add elements from each
pub fn genUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: no-op, return null
        try self.emit("null");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try self.output.writer(self.allocator).print("(supdate_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each arg, iterate and add elements
    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
        self.indent_level += 1;
        try self.emitIndent();
        // Check inside_defer - can't use try inside defer blocks
        if (self.inside_defer) {
            try emitObjExpr(self, obj);
            try self.emit(".put(entry.key_ptr.*, {}) catch {};\n");
        } else {
            try self.emit("try ");
            try emitObjExpr(self, obj);
            try self.emit(".put(entry.key_ptr.*, {});\n");
        }
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :supdate_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.union(*others)
/// Returns new set with elements from self and all others
/// - No args: returns copy of self
/// - One or more args: union with each
pub fn genUnion(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sunion_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set and copy self into it
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from each arg
    for (args, 0..) |arg, i| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
        self.indent_level += 1;
        try self.emitIndent();
        try self.output.writer(self.allocator).print("try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
        _ = i;
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sunion_{d} {s};\n", .{ label_id, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.intersection(*others)
/// Returns new set with elements common to self and all others
/// - No args: returns copy of self
/// - One or more args: keep only elements that exist in all
pub fn genIntersection(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_all = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sinter_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that exist in all others
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    // Check if element exists in all other sets
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{in_all});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {s} = false;\n", .{ other_set, in_all });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}) try {s}.put(entry.key_ptr.*, {{}});\n", .{ in_all, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sinter_{d} {s};\n", .{ label_id, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.difference(*others)
/// Returns new set with elements in self but not in any other
/// - No args: returns copy of self
/// - One or more args: keep only elements not in any other
pub fn genDifference(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // No args: return a copy of self
        try genCopy(self, obj, args);
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_any = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set - only add elements from self that don't exist in any other
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    // Check if element exists in any other set
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = false;\n", .{in_any});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) {s} = true;\n", .{ other_set, in_any });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}) try {s}.put(entry.key_ptr.*, {{}});\n", .{ in_any, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sdiff_{d} {s};\n", .{ label_id, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.symmetric_difference(other)
/// Returns new set with elements in either set but not both
/// Requires exactly one argument
pub fn genSymmetricDifference(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"symmetric_difference requires exactly one argument\")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const result = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(ssymdiff_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Create result set
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = @TypeOf(", .{result});
    try emitObjExpr(self, obj);
    try self.emit(").init(__global_allocator);\n");

    // Store other set in a variable first
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Add elements from self that are NOT in other
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) try {s}.put(entry.key_ptr.*, {{}});\n", .{ other_set, result });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Add elements from other that are NOT in self
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) try {s}.put(entry.key_ptr.*, {{}});\n", .{result});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiff_{d} {s};\n", .{ label_id, result });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.issubset(other)
pub fn genIssubset(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"issubset requires exactly one argument\")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_subset = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sissubset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_subset});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{ other_set, is_subset });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissubset_{d} {s};\n", .{ label_id, is_subset });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.issuperset(other)
pub fn genIssuperset(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"issuperset requires exactly one argument\")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_superset = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sissuperset_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_superset});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{is_superset});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sissuperset_{d} {s};\n", .{ label_id, is_superset });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.isdisjoint(other)
pub fn genIsdisjoint(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"isdisjoint requires exactly one argument\")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const is_disjoint = try self.name_gen.temp();
    const other_set = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sisdisjoint_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{is_disjoint});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) {{ {s} = false; break; }}\n", .{ other_set, is_disjoint });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sisdisjoint_{d} {s};\n", .{ label_id, is_disjoint });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.intersection_update(*others)
/// Modifies set in-place, keeping only elements found in all others
/// Returns None in Python
pub fn genIntersectionUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("null");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const to_remove = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const in_all = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(sinterupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Collect keys to remove (can't modify while iterating)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = true;\n", .{in_all});

    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("if (!{s}.contains(entry.key_ptr.*)) {s} = false;\n", .{ other_set, in_all });
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("if (!{s}) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{ in_all, to_remove });

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Remove collected keys - use runtime helper to avoid comptime explosion
    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ runtime.set_ops.SetOps(@TypeOf(key)).discard(&", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(", key); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sinterupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.difference_update(*others)
/// Modifies set in-place, removing elements found in any other
/// Returns None in Python
pub fn genDifferenceUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("null");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try self.output.writer(self.allocator).print("(sdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // For each other set, remove its elements from self
    for (args) |arg| {
        const other_set = try self.name_gen.temp();
        const other_iter = try self.name_gen.temp();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
        try self.genExpr(arg);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
        self.indent_level += 1;
        try self.emitIndent();
        // Use runtime helper to avoid comptime explosion
        try self.emit("runtime.set_ops.SetOps(@TypeOf(entry.key_ptr.*)).discard(&");
        try emitObjExpr(self, obj);
        try self.emit(", entry.key_ptr.*);\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :sdiffupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for set.symmetric_difference_update(other)
/// Modifies set in-place, keeping elements in either but not both
/// Returns None in Python
pub fn genSymmetricDifferenceUpdate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"symmetric_difference_update requires exactly one argument\")");
        return;
    }

    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate unique temp names to avoid variable collisions
    const other_set = try self.name_gen.temp();
    const to_remove = try self.name_gen.temp();
    const to_add = try self.name_gen.temp();
    const self_iter = try self.name_gen.temp();
    const other_iter = try self.name_gen.temp();

    try self.output.writer(self.allocator).print("(ssymdiffupd_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store other set first
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = ", .{other_set});
    try self.genExpr(args[0]);
    try self.emit(";\n");

    // Collect keys to remove (in both sets)
    // Use std.meta.fieldInfo to get key type from KV struct (works with const)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = std.ArrayListUnmanaged(std.meta.fieldInfo(@TypeOf(", .{to_add});
    try emitObjExpr(self, obj);
    try self.emit(").Unmanaged.KV, .key).type){};\n");

    // Find elements in self that are in other (to remove)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = ", .{self_iter});
    try emitObjExpr(self, obj);
    try self.emit(".iterator();\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{self_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("if ({s}.contains(entry.key_ptr.*)) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{ other_set, to_remove });
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Find elements in other that are not in self (to add)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var {s} = {s}.iterator();\n", .{ other_iter, other_set });

    try self.emitIndent();
    try self.output.writer(self.allocator).print("while ({s}.next()) |entry| {{\n", .{other_iter});
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("if (!");
    try emitObjExpr(self, obj);
    try self.output.writer(self.allocator).print(".contains(entry.key_ptr.*)) try {s}.append(__global_allocator, entry.key_ptr.*);\n", .{to_add});
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    // Apply changes - use runtime helper to avoid comptime explosion
    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ runtime.set_ops.SetOps(@TypeOf(key)).discard(&", .{to_remove});
    try emitObjExpr(self, obj);
    try self.emit(", key); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("for ({s}.items) |key| {{ try ", .{to_add});
    try emitObjExpr(self, obj);
    try self.emit(".put(key, {}); }\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :ssymdiffupd_{d} null;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}
