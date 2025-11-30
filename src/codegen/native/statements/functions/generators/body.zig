/// Function and class body generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const CodeBuilder = @import("../../../code_builder.zig").CodeBuilder;
const self_analyzer = @import("../self_analyzer.zig");
const param_analyzer = @import("../param_analyzer.zig");
const allocator_analyzer = @import("../allocator_analyzer.zig");
const signature = @import("signature.zig");
const hashmap_helper = @import("hashmap_helper");
const zig_keywords = @import("zig_keywords");

// Re-export from submodules
const class_fields = @import("body/class_fields.zig");
const class_methods = @import("body/class_methods.zig");

pub const genClassFields = class_fields.genClassFields;
pub const genClassFieldsNoDict = class_fields.genClassFieldsNoDict;
pub const inferParamType = class_fields.inferParamType;

pub const genDefaultInitMethod = class_methods.genDefaultInitMethod;
pub const genDefaultInitMethodWithBuiltinBase = class_methods.genDefaultInitMethodWithBuiltinBase;
pub const genInitMethod = class_methods.genInitMethod;
pub const genInitMethodWithBuiltinBase = class_methods.genInitMethodWithBuiltinBase;
pub const genClassMethods = class_methods.genClassMethods;
pub const genInheritedMethods = class_methods.genInheritedMethods;

/// Check if a method mutates self (assigns to self.field or self.field[key])
pub fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
    for (method.body) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        return true; // Assigns to self.field
                    }
                } else if (target == .subscript) {
                    // Check if subscript base is self.something: self.routes[key] = value
                    const subscript = target.subscript;
                    if (subscript.value.* == .attribute) {
                        const attr = subscript.value.attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            return true; // Assigns to self.field[key]
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Check if an AST node references a type attribute (e.g., self.int_class where int_class is a type attribute)
fn usesTypeAttribute(node: ast.Node, class_name: []const u8, class_type_attrs: anytype) bool {
    switch (node) {
        .attribute => |attr| {
            // Check for self.attr_name where attr_name is a type attribute
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                var key_buf: [512]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch return false;
                if (class_type_attrs.get(key)) |_| {
                    return true;
                }
            }
            return usesTypeAttribute(attr.value.*, class_name, class_type_attrs);
        },
        .call => |call| {
            // Check function expression
            if (usesTypeAttribute(call.func.*, class_name, class_type_attrs)) return true;
            // Check arguments
            for (call.args) |arg| {
                if (usesTypeAttribute(arg, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .binop => |binop| {
            return usesTypeAttribute(binop.left.*, class_name, class_type_attrs) or
                usesTypeAttribute(binop.right.*, class_name, class_type_attrs);
        },
        .assign => |assign| {
            // Check value expression
            if (usesTypeAttribute(assign.value.*, class_name, class_type_attrs)) return true;
            // Check targets
            for (assign.targets) |target| {
                if (usesTypeAttribute(target, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .expr_stmt => |expr| {
            return usesTypeAttribute(expr.value.*, class_name, class_type_attrs);
        },
        .if_stmt => |if_stmt| {
            // Check condition
            if (usesTypeAttribute(if_stmt.condition.*, class_name, class_type_attrs)) return true;
            // Check body
            for (if_stmt.body) |stmt| {
                if (usesTypeAttribute(stmt, class_name, class_type_attrs)) return true;
            }
            for (if_stmt.else_body) |stmt| {
                if (usesTypeAttribute(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |stmt| {
                if (usesTypeAttribute(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .with_stmt => |with_stmt| {
            // Check context expression
            if (usesTypeAttribute(with_stmt.context_expr.*, class_name, class_type_attrs)) return true;
            // Check body
            for (with_stmt.body) |stmt| {
                if (usesTypeAttribute(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Check if an AST node uses `self` for non-type-attribute access
/// (e.g., self.check(), self.field where field is NOT a type attribute)
/// This is used to determine if `_ = self;` is needed
fn usesRegularSelf(node: ast.Node, class_name: []const u8, class_type_attrs: anytype) bool {
    switch (node) {
        .attribute => |attr| {
            // Check for self.attr_name where attr_name is NOT a type attribute
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                var key_buf: [512]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch return false;
                // If it's a type attribute, this is NOT a regular self usage
                if (class_type_attrs.get(key)) |_| {
                    return false;
                }
                // Skip unittest assertion methods that get transformed to runtime calls
                // These methods don't actually use `self` in the generated Zig code
                if (self_analyzer.unittest_assertion_methods.has(attr.attr)) {
                    return false;
                }
                // It's a regular self.something access
                return true;
            }
            return usesRegularSelf(attr.value.*, class_name, class_type_attrs);
        },
        .call => |call| {
            // Check function expression
            if (usesRegularSelf(call.func.*, class_name, class_type_attrs)) return true;
            // Check arguments
            for (call.args) |arg| {
                if (usesRegularSelf(arg, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .binop => |binop| {
            return usesRegularSelf(binop.left.*, class_name, class_type_attrs) or
                usesRegularSelf(binop.right.*, class_name, class_type_attrs);
        },
        .assign => |assign| {
            // Check value expression
            if (usesRegularSelf(assign.value.*, class_name, class_type_attrs)) return true;
            // Check targets
            for (assign.targets) |target| {
                if (usesRegularSelf(target, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .expr_stmt => |expr| {
            return usesRegularSelf(expr.value.*, class_name, class_type_attrs);
        },
        .if_stmt => |if_stmt| {
            // Check condition
            if (usesRegularSelf(if_stmt.condition.*, class_name, class_type_attrs)) return true;
            // Check body
            for (if_stmt.body) |stmt| {
                if (usesRegularSelf(stmt, class_name, class_type_attrs)) return true;
            }
            for (if_stmt.else_body) |stmt| {
                if (usesRegularSelf(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |stmt| {
                if (usesRegularSelf(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        .with_stmt => |with_stmt| {
            // Check context expression
            if (usesRegularSelf(with_stmt.context_expr.*, class_name, class_type_attrs)) return true;
            // Check body
            for (with_stmt.body) |stmt| {
                if (usesRegularSelf(stmt, class_name, class_type_attrs)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Analyze function body for mutated variables (variables assigned more than once)
fn analyzeFunctionLocalMutations(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Track how many times each variable is assigned
    var assign_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer assign_counts.deinit();

    // Count assignments in the function body
    for (func.body) |stmt| {
        try countAssignmentsInStmt(&assign_counts, stmt, self.allocator);
    }

    // Variables assigned more than once are mutated
    var iter = assign_counts.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            try self.func_local_mutations.put(entry.key_ptr.*, {});
        }
    }
}

/// Analyze function body for used variables (variables that are read, not just assigned)
/// This prevents false "unused variable" detection for variables used within function bodies
fn analyzeFunctionLocalUses(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    self.func_local_uses.clearRetainingCapacity();
    for (func.body) |stmt| {
        try collectUsesInNode(self, stmt);
    }
}

/// Recursively collect variable uses in an AST node
fn collectUsesInNode(self: *NativeCodegen, node: ast.Node) !void {
    switch (node) {
        .name => |name| {
            // A name reference is a use (unless it's on the left side of assignment, handled separately)
            try self.func_local_uses.put(name.id, {});
        },
        .call => |call| {
            // Function being called is a use
            try collectUsesInNode(self, call.func.*);
            for (call.args) |arg| {
                try collectUsesInNode(self, arg);
            }
            for (call.keyword_args) |kwarg| {
                try collectUsesInNode(self, kwarg.value);
            }
        },
        .binop => |binop| {
            try collectUsesInNode(self, binop.left.*);
            try collectUsesInNode(self, binop.right.*);
        },
        .unaryop => |unary| {
            try collectUsesInNode(self, unary.operand.*);
        },
        .compare => |compare| {
            try collectUsesInNode(self, compare.left.*);
            for (compare.comparators) |comp| {
                try collectUsesInNode(self, comp);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |value| {
                try collectUsesInNode(self, value);
            }
        },
        .subscript => |subscript| {
            try collectUsesInNode(self, subscript.value.*);
            switch (subscript.slice) {
                .index => |idx| try collectUsesInNode(self, idx.*),
                .slice => |slice| {
                    if (slice.lower) |lower| try collectUsesInNode(self, lower.*);
                    if (slice.upper) |upper| try collectUsesInNode(self, upper.*);
                    if (slice.step) |step| try collectUsesInNode(self, step.*);
                },
            }
        },
        .attribute => |attr| {
            try collectUsesInNode(self, attr.value.*);
        },
        .list => |list| {
            for (list.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try collectUsesInNode(self, key);
            }
            for (dict.values) |value| {
                try collectUsesInNode(self, value);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .set => |set| {
            for (set.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .if_expr => |if_expr| {
            try collectUsesInNode(self, if_expr.condition.*);
            try collectUsesInNode(self, if_expr.body.*);
            try collectUsesInNode(self, if_expr.orelse_value.*);
        },
        .lambda => |lambda| {
            try collectUsesInNode(self, lambda.body.*);
        },
        .listcomp => |listcomp| {
            try collectUsesInNode(self, listcomp.elt.*);
            for (listcomp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        .dictcomp => |dictcomp| {
            try collectUsesInNode(self, dictcomp.key.*);
            try collectUsesInNode(self, dictcomp.value.*);
            for (dictcomp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        .genexp => |genexp| {
            try collectUsesInNode(self, genexp.elt.*);
            for (genexp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        // Statements
        .assign => |assign| {
            // Value is a use, targets are assignments (not uses)
            try collectUsesInNode(self, assign.value.*);
        },
        .ann_assign => |ann_assign| {
            if (ann_assign.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .aug_assign => |aug| {
            // Both target and value are uses (target is read then written)
            try collectUsesInNode(self, aug.target.*);
            try collectUsesInNode(self, aug.value.*);
        },
        .expr_stmt => |expr| {
            try collectUsesInNode(self, expr.value.*);
        },
        .return_stmt => |ret| {
            if (ret.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .if_stmt => |if_stmt| {
            try collectUsesInNode(self, if_stmt.condition.*);
            for (if_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (if_stmt.else_body) |else_stmt| {
                try collectUsesInNode(self, else_stmt);
            }
        },
        .while_stmt => |while_stmt| {
            try collectUsesInNode(self, while_stmt.condition.*);
            for (while_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .for_stmt => |for_stmt| {
            try collectUsesInNode(self, for_stmt.iter.*);
            for (for_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try collectUsesInNode(self, body_stmt);
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (try_stmt.finalbody) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .with_stmt => |with_stmt| {
            try collectUsesInNode(self, with_stmt.context_expr.*);
            for (with_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .assert_stmt => |assert_stmt| {
            try collectUsesInNode(self, assert_stmt.condition.*);
            if (assert_stmt.msg) |msg| {
                try collectUsesInNode(self, msg.*);
            }
        },
        .raise_stmt => |raise| {
            if (raise.exc) |exc| {
                try collectUsesInNode(self, exc.*);
            }
            if (raise.cause) |cause| {
                try collectUsesInNode(self, cause.*);
            }
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |expr| try collectUsesInNode(self, expr.*),
                    .format_expr => |fmt| try collectUsesInNode(self, fmt.expr.*),
                    .conv_expr => |conv| try collectUsesInNode(self, conv.expr.*),
                    .literal => {},
                }
            }
        },
        .named_expr => |named| {
            try collectUsesInNode(self, named.value.*);
        },
        .await_expr => |await_expr| {
            try collectUsesInNode(self, await_expr.value.*);
        },
        .yield_stmt => |yield| {
            if (yield.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .yield_from_stmt => |yield_from| {
            try collectUsesInNode(self, yield_from.value.*);
        },
        // Skip these - they don't contain variable uses
        .constant, .pass, .break_stmt, .continue_stmt, .ellipsis_literal,
        .import_stmt, .import_from, .global_stmt, .nonlocal_stmt,
        .function_def, .class_def, .del_stmt => {},
        // Catch-all for other node types
        else => {},
    }
}

/// Count assignments in a statement (recursive)
fn countAssignmentsInStmt(counts: *hashmap_helper.StringHashMap(usize), stmt: ast.Node, allocator: std.mem.Allocator) !void {
    switch (stmt) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (target == .name) {
                    const name = target.name.id;
                    const current = counts.get(name) orelse 0;
                    try counts.put(name, current + 1);
                } else if (target == .subscript) {
                    // Subscript assignment: x[0] = value mutates x
                    const subscript = target.subscript;
                    if (subscript.value.* == .name) {
                        const name = subscript.value.name.id;
                        const current = counts.get(name) orelse 0;
                        try counts.put(name, current + 2); // Mark as mutated
                    }
                }
            }
        },
        .aug_assign => |aug| {
            // Augmented assignment (+=, -=, etc.) counts as a mutation
            if (aug.target.* == .name) {
                const name = aug.target.name.id;
                const current = counts.get(name) orelse 0;
                // Count as 2 (initial + mutation) to ensure it's marked as mutated
                try counts.put(name, current + 2);
            } else if (aug.target.* == .subscript) {
                // Subscript mutation: x[0] += 1 mutates x
                const subscript = aug.target.subscript;
                if (subscript.value.* == .name) {
                    const name = subscript.value.name.id;
                    const current = counts.get(name) orelse 0;
                    try counts.put(name, current + 2);
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
            for (if_stmt.else_body) |else_stmt| {
                try countAssignmentsInStmt(counts, else_stmt, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        .for_stmt => |for_stmt| {
            // Loop variable is assigned each iteration
            if (for_stmt.target.* == .name) {
                const name = for_stmt.target.name.id;
                try counts.put(name, 2); // Mark as mutated
            }
            for (for_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try countAssignmentsInStmt(counts, body_stmt, allocator);
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
            for (try_stmt.finalbody) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        else => {},
    }
}

/// Analyze nested classes for captured outer variables
/// Populates func_local_vars with variables defined in function scope
/// Populates nested_class_captures with outer variables referenced by each nested class
fn analyzeNestedClassCaptures(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // First, collect all local variables defined in the function
    for (func.args) |arg| {
        try self.func_local_vars.put(arg.name, {});
    }
    try collectLocalVarsInStmts(self, func.body);

    // Then, for each nested class, find which local variables it references
    try findNestedClassCaptures(self, func.body);
}

/// Collect all local variables defined in statements
fn collectLocalVarsInStmts(self: *NativeCodegen, stmts: []ast.Node) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try self.func_local_vars.put(target.name.id, {});
                    }
                }
            },
            .aug_assign => |aug| {
                if (aug.target.* == .name) {
                    try self.func_local_vars.put(aug.target.name.id, {});
                }
            },
            .if_stmt => |if_stmt| {
                try collectLocalVarsInStmts(self, if_stmt.body);
                try collectLocalVarsInStmts(self, if_stmt.else_body);
            },
            .for_stmt => |for_stmt| {
                // For loop target is a local var
                if (for_stmt.target.* == .name) {
                    try self.func_local_vars.put(for_stmt.target.name.id, {});
                }
                try collectLocalVarsInStmts(self, for_stmt.body);
                if (for_stmt.orelse_body) |orelse_body| {
                    try collectLocalVarsInStmts(self, orelse_body);
                }
            },
            .while_stmt => |while_stmt| {
                try collectLocalVarsInStmts(self, while_stmt.body);
                if (while_stmt.orelse_body) |orelse_body| {
                    try collectLocalVarsInStmts(self, orelse_body);
                }
            },
            .try_stmt => |try_stmt| {
                try collectLocalVarsInStmts(self, try_stmt.body);
                for (try_stmt.handlers) |handler| {
                    if (handler.name) |exc_name| {
                        try self.func_local_vars.put(exc_name, {});
                    }
                    try collectLocalVarsInStmts(self, handler.body);
                }
                try collectLocalVarsInStmts(self, try_stmt.else_body);
                try collectLocalVarsInStmts(self, try_stmt.finalbody);
            },
            .with_stmt => |with_stmt| {
                // with_stmt.optional_vars is ?[]const u8 - just a string var name
                if (with_stmt.optional_vars) |var_name| {
                    try self.func_local_vars.put(var_name, {});
                }
                try collectLocalVarsInStmts(self, with_stmt.body);
            },
            else => {},
        }
    }
}

/// Find nested classes and their captured variables
fn findNestedClassCaptures(self: *NativeCodegen, stmts: []ast.Node) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |class| {
                // Track all nested class names for constructor detection
                try self.nested_class_names.put(class.name, {});

                // Track base class for nested classes (for default constructor args)
                if (class.bases.len > 0) {
                    try self.nested_class_bases.put(class.name, class.bases[0]);
                }

                // Find outer variables referenced by this class
                var captured = std.ArrayList([]const u8){};
                try findCapturedVarsInClass(self, class, &captured);

                if (captured.items.len > 0) {
                    // Store captured vars for this class
                    const slice = try captured.toOwnedSlice(self.allocator);
                    try self.nested_class_captures.put(class.name, slice);
                } else {
                    captured.deinit(self.allocator);
                }
            },
            .if_stmt => |if_stmt| {
                try findNestedClassCaptures(self, if_stmt.body);
                try findNestedClassCaptures(self, if_stmt.else_body);
            },
            .for_stmt => |for_stmt| {
                try findNestedClassCaptures(self, for_stmt.body);
                if (for_stmt.orelse_body) |orelse_body| {
                    try findNestedClassCaptures(self, orelse_body);
                }
            },
            .while_stmt => |while_stmt| {
                try findNestedClassCaptures(self, while_stmt.body);
                if (while_stmt.orelse_body) |orelse_body| {
                    try findNestedClassCaptures(self, orelse_body);
                }
            },
            .try_stmt => |try_stmt| {
                try findNestedClassCaptures(self, try_stmt.body);
                for (try_stmt.handlers) |handler| {
                    try findNestedClassCaptures(self, handler.body);
                }
                try findNestedClassCaptures(self, try_stmt.else_body);
                try findNestedClassCaptures(self, try_stmt.finalbody);
            },
            .with_stmt => |with_stmt| {
                try findNestedClassCaptures(self, with_stmt.body);
            },
            else => {},
        }
    }
}

/// Find variables from outer scope referenced by a class's methods
fn findCapturedVarsInClass(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    captured: *std.ArrayList([]const u8),
) CodegenError!void {
    // Collect variables referenced in class methods (excluding self)
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            // Collect all variable names referenced in method body
            try findOuterRefsInStmts(self, method.body, method.args, captured);
        }
    }
}

/// Find references to outer scope variables in statements
fn findOuterRefsInStmts(
    self: *NativeCodegen,
    stmts: []ast.Node,
    method_params: []ast.Arg,
    captured: *std.ArrayList([]const u8),
) error{OutOfMemory}!void {
    for (stmts) |stmt| {
        try findOuterRefsInNode(self, stmt, method_params, captured);
    }
}

/// Find references to outer scope variables in a single node
fn findOuterRefsInNode(
    self: *NativeCodegen,
    node: ast.Node,
    method_params: []ast.Arg,
    captured: *std.ArrayList([]const u8),
) error{OutOfMemory}!void {
    switch (node) {
        .name => |n| {
            // Skip if it's a method parameter
            for (method_params) |param| {
                if (std.mem.eql(u8, param.name, n.id)) return;
            }
            // Skip built-in names
            if (isBuiltinName(n.id)) return;
            // Check if it's a local variable from outer function scope
            // Capture ALL referenced outer variables (not just mutable ones)
            // because Zig doesn't allow any access across struct namespace boundary
            if (self.func_local_vars.contains(n.id)) {
                // Add to captured list (avoid duplicates)
                for (captured.items) |existing| {
                    if (std.mem.eql(u8, existing, n.id)) return;
                }
                try captured.append(self.allocator, n.id);
            }
        },
        .binop => |b| {
            try findOuterRefsInNode(self, b.left.*, method_params, captured);
            try findOuterRefsInNode(self, b.right.*, method_params, captured);
        },
        .unaryop => |u| {
            try findOuterRefsInNode(self, u.operand.*, method_params, captured);
        },
        .call => |c| {
            try findOuterRefsInNode(self, c.func.*, method_params, captured);
            for (c.args) |arg| {
                try findOuterRefsInNode(self, arg, method_params, captured);
            }
            for (c.keyword_args) |kw| {
                try findOuterRefsInNode(self, kw.value, method_params, captured);
            }
        },
        .compare => |cmp| {
            try findOuterRefsInNode(self, cmp.left.*, method_params, captured);
            for (cmp.comparators) |comp| {
                try findOuterRefsInNode(self, comp, method_params, captured);
            }
        },
        .attribute => |attr| {
            try findOuterRefsInNode(self, attr.value.*, method_params, captured);
        },
        .subscript => |sub| {
            try findOuterRefsInNode(self, sub.value.*, method_params, captured);
            if (sub.slice == .index) {
                try findOuterRefsInNode(self, sub.slice.index.*, method_params, captured);
            }
        },
        .list => |l| {
            for (l.elts) |elem| {
                try findOuterRefsInNode(self, elem, method_params, captured);
            }
        },
        .tuple => |t| {
            for (t.elts) |elem| {
                try findOuterRefsInNode(self, elem, method_params, captured);
            }
        },
        .dict => |d| {
            // Dict keys are not optional in the AST
            for (d.keys) |dict_key| {
                try findOuterRefsInNode(self, dict_key, method_params, captured);
            }
            for (d.values) |val| {
                try findOuterRefsInNode(self, val, method_params, captured);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try findOuterRefsInNode(self, val, method_params, captured);
            }
        },
        .if_expr => |ie| {
            try findOuterRefsInNode(self, ie.condition.*, method_params, captured);
            try findOuterRefsInNode(self, ie.body.*, method_params, captured);
            try findOuterRefsInNode(self, ie.orelse_value.*, method_params, captured);
        },
        // Statements
        .assign => |assign| {
            try findOuterRefsInNode(self, assign.value.*, method_params, captured);
        },
        .aug_assign => |aug| {
            try findOuterRefsInNode(self, aug.target.*, method_params, captured);
            try findOuterRefsInNode(self, aug.value.*, method_params, captured);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| try findOuterRefsInNode(self, val.*, method_params, captured);
        },
        .expr_stmt => |es| {
            try findOuterRefsInNode(self, es.value.*, method_params, captured);
        },
        .if_stmt => |if_stmt| {
            try findOuterRefsInNode(self, if_stmt.condition.*, method_params, captured);
            try findOuterRefsInStmts(self, if_stmt.body, method_params, captured);
            try findOuterRefsInStmts(self, if_stmt.else_body, method_params, captured);
        },
        .for_stmt => |for_stmt| {
            try findOuterRefsInNode(self, for_stmt.iter.*, method_params, captured);
            try findOuterRefsInStmts(self, for_stmt.body, method_params, captured);
            if (for_stmt.orelse_body) |orelse_body| {
                try findOuterRefsInStmts(self, orelse_body, method_params, captured);
            }
        },
        .while_stmt => |while_stmt| {
            try findOuterRefsInNode(self, while_stmt.condition.*, method_params, captured);
            try findOuterRefsInStmts(self, while_stmt.body, method_params, captured);
            if (while_stmt.orelse_body) |orelse_body| {
                try findOuterRefsInStmts(self, orelse_body, method_params, captured);
            }
        },
        .try_stmt => |try_stmt| {
            try findOuterRefsInStmts(self, try_stmt.body, method_params, captured);
            for (try_stmt.handlers) |handler| {
                try findOuterRefsInStmts(self, handler.body, method_params, captured);
            }
            try findOuterRefsInStmts(self, try_stmt.else_body, method_params, captured);
            try findOuterRefsInStmts(self, try_stmt.finalbody, method_params, captured);
        },
        else => {},
    }
}

/// Check if a name is a Python builtin
fn isBuiltinName(name: []const u8) bool {
    const builtins = [_][]const u8{
        "True", "False", "None", "int", "float", "str", "bool", "list", "dict",
        "set", "tuple", "len", "print", "range", "type", "isinstance", "hasattr",
        "getattr", "setattr", "delattr", "callable", "iter", "next", "enumerate",
        "zip", "map", "filter", "sorted", "reversed", "min", "max", "sum", "abs",
        "round", "pow", "divmod", "hex", "oct", "bin", "ord", "chr", "repr",
        "NotImplemented", "Exception", "ValueError", "TypeError", "KeyError",
        "IndexError", "AttributeError", "RuntimeError", "AssertionError",
        "StopIteration", "object", "super", "self", "__name__", "__file__",
    };
    for (builtins) |b| {
        if (std.mem.eql(u8, name, b)) return true;
    }
    return false;
}

/// Generate function body with scope management
pub fn genFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    _: bool, // has_allocator_param - unused, handled in signature.zig
    _: bool, // actually_uses_allocator - unused, handled in signature.zig
) CodegenError!void {
    // For async functions, generate task spawn wrapper
    if (func.is_async) {
        try genAsyncFunctionBody(self, func);
        return;
    }

    // Analyze function body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.hoisted_vars.clearRetainingCapacity();
    try analyzeFunctionLocalMutations(self, func);

    // Analyze function body for used variables (prevents false "unused" detection)
    try analyzeFunctionLocalUses(self, func);

    // Track local variables and analyze nested class captures for closure support
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    try analyzeNestedClassCaptures(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Note: Unused parameters are handled in signature.zig with "_" prefix
    // (e.g., unused param "op" becomes "_op" in signature)
    // No need to emit "_ = param;" here since "_" prefix already suppresses the warning

    // Generate default parameter initialization (before declaring them in scope)
    // When default value references the same name as the parameter (e.g., def foo(x=x):),
    // we need to use a different local name to avoid shadowing the module-level variable
    for (func.args) |arg| {
        if (arg.default) |default_expr| {
            const expressions = @import("../../../expressions.zig");

            // Check if default expression is a name that matches the parameter name
            // This would cause shadowing in Zig, so we rename the local variable
            const needs_rename = if (default_expr.* == .name)
                std.mem.eql(u8, default_expr.name.id, arg.name)
            else
                false;

            if (needs_rename) {
                // Rename local variable to avoid shadowing module-level variable
                // Use __local_X and add to var_renames so all references use the new name
                const renamed = try std.fmt.allocPrint(self.allocator, "__local_{s}", .{arg.name});
                try self.var_renames.put(arg.name, renamed);

                try self.emitIndent();
                try self.emit("const ");
                try self.emit(renamed);
                try self.emit(" = ");
                try self.emit(arg.name);
                try self.emit("_param orelse ");
                // Reference the original module-level variable (arg.name), not the renamed one
                try self.emit(arg.name);
                try self.emit(";\n");
            } else {
                try self.emitIndent();
                try self.emit("const ");
                try self.emit(arg.name);
                try self.emit(" = ");
                try self.emit(arg.name);
                try self.emit("_param orelse ");
                try expressions.genExpr(self, default_expr.*);
                try self.emit(";\n");
            }
        }
    }

    // Declare function parameters in the scope so closures can capture them
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    // Generate function body
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    // Clear function-local state after exiting function
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_vars.clearRetainingCapacity();
    // Clear nested_class_captures (free the slices first)
    var cap_iter = self.nested_class_captures.iterator();
    while (cap_iter.next()) |entry| {
        self.allocator.free(entry.value_ptr.*);
    }
    self.nested_class_captures.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting function
    // This prevents class name collisions between different functions
    // BUT: Don't clear if we're inside a nested class (class_nesting_depth > 1)
    // because the parent scope needs to retain nested class info
    if (self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
    }

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate async function body (implementation function for green thread scheduler)
fn genAsyncFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Async impl functions use __global_allocator directly in generated code (e.g., createTask).
    // The `allocator` alias is provided for consistency but often unused.
    // Always suppress warning since analysis can't distinguish direct vs aliased use.
    try self.emitIndent();
    try self.emit("const allocator = __global_allocator; _ = allocator;\n");

    // Declare function parameters in the scope
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    // Generate function body directly (no task wrapping needed)
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate method body with self-usage detection
pub fn genMethodBody(self: *NativeCodegen, method: ast.Node.FunctionDef) CodegenError!void {
    // genMethodBodyWithAllocatorInfo with automatic detection
    const needs_allocator = allocator_analyzer.functionNeedsAllocator(method);
    const actually_uses = allocator_analyzer.functionActuallyUsesAllocatorParam(method);
    try genMethodBodyWithAllocatorInfo(self, method, needs_allocator, actually_uses);
}

/// Check if method body contains a super() call
fn hasSuperCall(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (stmtHasSuperCall(stmt)) return true;
    }
    return false;
}

fn stmtHasSuperCall(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasSuperCall(e.value.*),
        .assign => |a| exprHasSuperCall(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprHasSuperCall(v.*) else false,
        .if_stmt => |i| hasSuperCall(i.body) or hasSuperCall(i.else_body),
        .while_stmt => |w| hasSuperCall(w.body),
        .for_stmt => |f| hasSuperCall(f.body),
        .try_stmt => |t| blk: {
            if (hasSuperCall(t.body)) break :blk true;
            for (t.handlers) |h| {
                if (hasSuperCall(h.body)) break :blk true;
            }
            break :blk hasSuperCall(t.finalbody);
        },
        else => false,
    };
}

fn exprHasSuperCall(expr: ast.Node) bool {
    return switch (expr) {
        .call => |c| blk: {
            // Check if this is super() or super().method()
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "super")) {
                break :blk true;
            }
            // Check if func is attr access on super() call: super().method()
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .call) {
                    const inner_call = attr.value.call;
                    if (inner_call.func.* == .name and std.mem.eql(u8, inner_call.func.name.id, "super")) {
                        break :blk true;
                    }
                }
            }
            // Check arguments
            for (c.args) |arg| {
                if (exprHasSuperCall(arg)) break :blk true;
            }
            break :blk false;
        },
        .binop => |b| exprHasSuperCall(b.left.*) or exprHasSuperCall(b.right.*),
        .attribute => |a| exprHasSuperCall(a.value.*),
        else => false,
    };
}

/// Generate method body with explicit allocator info
pub fn genMethodBodyWithAllocatorInfo(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    _: bool, // has_allocator_param - unused, handled in signature.zig
    _: bool, // actually_uses_allocator - unused, handled in signature.zig
) CodegenError!void {
    // Track whether we're inside a method with 'self' parameter.
    // This is used by generators.zig to know if a nested class should use __self.
    const has_self = for (method.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) break true;
    } else false;
    const was_inside_method = self.inside_method_with_self;
    if (has_self) self.inside_method_with_self = true;
    defer self.inside_method_with_self = was_inside_method;

    // Analyze method body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.hoisted_vars.clearRetainingCapacity();
    try analyzeFunctionLocalMutations(self, method);

    // Analyze method body for used variables (prevents false "unused" detection)
    try analyzeFunctionLocalUses(self, method);

    // Track local variables and analyze nested class captures for closure support
    // Note: We only clear func_local_vars here, not nested_class_captures
    // because nested_class_captures may already contain info from parent scope
    // that we need for class instantiation code
    self.func_local_vars.clearRetainingCapacity();
    try analyzeNestedClassCaptures(self, method);

    self.indent();

    // Push new scope for method body (symbol table)
    try self.pushScope();

    // Enter named type inferrer scope to match analysis phase
    // Use "ClassName.method_name" for methods or "func_name" for standalone functions
    // This enables scoped variable type lookup during codegen
    var scope_name_buf: [256]u8 = undefined;
    const scope_name = if (self.current_class_name) |class_name|
        std.fmt.bufPrint(&scope_name_buf, "{s}.{s}", .{ class_name, method.name }) catch method.name
    else
        method.name;
    const old_type_scope = self.type_inferrer.enterScope(scope_name);
    defer self.type_inferrer.exitScope(old_type_scope);

    // Note: We removed the "_ = self;" emission for super() calls
    // This was causing "pointless discard of function parameter" errors when
    // self IS actually used in the method body beyond super() calls.
    // If self is truly unused, signature.zig should handle it with "_" prefix.

    // However, if the method uses type attributes (e.g., self.int_class), the generated
    // code uses @This().int_class which doesn't reference self, causing "unused parameter" error.
    // Detect this case and emit _ = self; to suppress the warning.
    // BUT: only emit _ = self; if the method ONLY uses type attributes and not regular self methods.
    // If the method uses BOTH type attributes AND regular self (e.g., self.check()), then self IS used.
    if (self.current_class_name) |class_name| {
        const uses_type_attrs = blk: {
            for (method.body) |stmt| {
                if (usesTypeAttribute(stmt, class_name, self.class_type_attrs)) {
                    break :blk true;
                }
            }
            break :blk false;
        };
        const uses_regular_self = blk2: {
            for (method.body) |stmt| {
                if (usesRegularSelf(stmt, class_name, self.class_type_attrs)) {
                    break :blk2 true;
                }
            }
            break :blk2 false;
        };
        // Only emit _ = self if we use type attrs but DON'T use regular self
        if (uses_type_attrs and !uses_regular_self) {
            try self.emitIndent();
            try self.emit("_ = self;\n");
        }
    }

    // Note: Unused allocator param is handled in signature.zig with "_:" prefix
    // No need to emit "_ = allocator;" here

    // Clear local variable types (new method scope)
    self.clearLocalVarTypes();

    // Track parameters that were renamed to avoid method shadowing (e.g., init -> init_arg)
    // We'll restore these when exiting the method
    var renamed_params = std.ArrayList([]const u8){};
    defer renamed_params.deinit(self.allocator);

    // Declare method parameters in the scope (skip 'self')
    // This prevents variable shadowing when reassigning parameters
    for (method.args) |arg| {
        if (!std.mem.eql(u8, arg.name, "self")) {
            // Check if this param would shadow a method name and needs renaming
            if (zig_keywords.wouldShadowMethod(arg.name)) {
                // Add rename mapping: original -> renamed
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}_arg", .{arg.name});
                try self.var_renames.put(arg.name, renamed);
                try renamed_params.append(self.allocator, arg.name);
            }
            try self.declareVar(arg.name);
        }
    }

    // Generate method body
    for (method.body) |method_stmt| {
        try self.generateStmt(method_stmt);
    }

    // Remove parameter renames when exiting method scope
    for (renamed_params.items) |param_name| {
        if (self.var_renames.fetchSwapRemove(param_name)) |entry| {
            self.allocator.free(entry.value);
        }
    }

    // Pop scope when exiting method
    self.popScope();

    // Clear function-local mutations after exiting method
    self.func_local_mutations.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting method
    // This prevents class name collisions between different methods
    // (e.g., both test_foo and test_bar may have a nested class named BadIndex)
    // BUT: Don't clear if we're inside a nested class (class_nesting_depth > 1)
    // because the parent scope needs to retain nested class info for constructor calls
    // that appear AFTER the nested class definition
    if (self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}
