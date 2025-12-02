/// Nested class capture analysis for closure support
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

/// Analyze nested classes for captured outer variables
/// Populates func_local_vars with variables defined in function scope
/// Populates nested_class_captures with outer variables referenced by each nested class
pub fn analyzeNestedClassCaptures(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // First, collect all local variables defined in the function
    for (func.args) |arg| {
        try self.func_local_vars.put(arg.name, {});
    }
    try collectLocalVarsInStmts(self, func.body);

    // Then, for each nested class, find which local variables it references
    try findNestedClassCaptures(self, func.body);
}

/// Collect all local variables defined in statements
pub fn collectLocalVarsInStmts(self: *NativeCodegen, stmts: []ast.Node) CodegenError!void {
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
pub fn findNestedClassCaptures(self: *NativeCodegen, stmts: []ast.Node) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |class| {
                // Track all nested class names for constructor detection
                try self.nested_class_names.put(class.name, {});

                // Track full class definition for nested class inheritance
                try self.nested_class_defs.put(class.name, class);

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
pub fn findCapturedVarsInClass(
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
            // Also detect mutations on captured variables (e.g., output.append())
            try detectCapturedMutations(self, class.name, method.body, method.args);
        }
    }
}

/// Detect mutations on captured variables in method body
/// Mutating methods: append, extend, insert, pop, clear, remove, update, add, discard
fn detectCapturedMutations(
    self: *NativeCodegen,
    class_name: []const u8,
    stmts: []ast.Node,
    method_params: []ast.Arg,
) error{OutOfMemory}!void {
    for (stmts) |stmt| {
        try detectMutationInNode(self, class_name, stmt, method_params);
    }
}

/// Check if a node contains mutation of a captured variable
fn detectMutationInNode(
    self: *NativeCodegen,
    class_name: []const u8,
    node: ast.Node,
    method_params: []ast.Arg,
) error{OutOfMemory}!void {
    switch (node) {
        .call => |c| {
            // Check for method calls like var.append(), var.extend(), etc.
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                // Check if the receiver is a simple name (captured variable)
                if (attr.value.* == .name) {
                    const var_name = attr.value.name.id;
                    // Skip method params
                    var is_param = false;
                    for (method_params) |param| {
                        if (std.mem.eql(u8, param.name, var_name)) {
                            is_param = true;
                            break;
                        }
                    }
                    if (!is_param and self.func_local_vars.contains(var_name)) {
                        // Check if method name is a mutating method
                        const mutating_methods = [_][]const u8{
                            "append", "extend", "insert", "pop", "clear",
                            "remove", "update", "add", "discard", "sort", "reverse",
                        };
                        for (mutating_methods) |m| {
                            if (std.mem.eql(u8, attr.attr, m)) {
                                // Mark as mutated: "class_name.var_name"
                                const key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, var_name }) catch continue;
                                try self.mutated_captures.put(key, {});
                                break;
                            }
                        }
                    }
                }
            }
            // Recurse into args
            for (c.args) |arg| {
                try detectMutationInNode(self, class_name, arg, method_params);
            }
        },
        .expr_stmt => |e| try detectMutationInNode(self, class_name, e.value.*, method_params),
        .if_stmt => |i| {
            for (i.body) |s| try detectMutationInNode(self, class_name, s, method_params);
            for (i.else_body) |s| try detectMutationInNode(self, class_name, s, method_params);
        },
        .for_stmt => |f| {
            for (f.body) |s| try detectMutationInNode(self, class_name, s, method_params);
        },
        .while_stmt => |w| {
            for (w.body) |s| try detectMutationInNode(self, class_name, s, method_params);
        },
        .try_stmt => |t| {
            for (t.body) |s| try detectMutationInNode(self, class_name, s, method_params);
            for (t.handlers) |h| {
                for (h.body) |s| try detectMutationInNode(self, class_name, s, method_params);
            }
        },
        else => {},
    }
}

/// Find references to outer scope variables in statements
pub fn findOuterRefsInStmts(
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
pub fn findOuterRefsInNode(
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
pub fn isBuiltinName(name: []const u8) bool {
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

/// Analyze function for forward-referenced captured variables
/// Returns list of variables that are captured by nested classes before they're declared
/// These need to be forward-declared in the generated Zig code
pub fn findForwardReferencedCaptures(
    self: *NativeCodegen,
    stmts: []ast.Node,
) CodegenError!std.ArrayList([]const u8) {
    var forward_refs = std.ArrayList([]const u8){};
    var declared_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer declared_vars.deinit();

    // Track which variables are captured and which are declared, in order
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |class| {
                // Check if this class captures any variables not yet declared
                if (self.nested_class_captures.get(class.name)) |captures| {
                    for (captures) |cap_var| {
                        if (!declared_vars.contains(cap_var)) {
                            // This is a forward reference - captured before declared
                            // Check if we already added it
                            var already_added = false;
                            for (forward_refs.items) |existing| {
                                if (std.mem.eql(u8, existing, cap_var)) {
                                    already_added = true;
                                    break;
                                }
                            }
                            if (!already_added) {
                                try forward_refs.append(self.allocator, cap_var);
                            }
                        }
                    }
                }
            },
            .assign => |assign| {
                // Mark variables as declared
                for (assign.targets) |target| {
                    if (target == .name) {
                        try declared_vars.put(target.name.id, {});
                    }
                }
            },
            else => {},
        }
    }

    return forward_refs;
}
