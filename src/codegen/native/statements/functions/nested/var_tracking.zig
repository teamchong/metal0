/// Variable tracking for closures - finding captured vars, analyzing usage patterns
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

/// Collect variable names from an assignment target (handles name, tuple, list)
fn collectTargetVarsToList(allocator: std.mem.Allocator, node: ast.Node, list: *std.ArrayList([]const u8)) !void {
    switch (node) {
        .name => |n| {
            try addUniqueVar(allocator, list, n.id);
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try collectTargetVarsToList(allocator, elt, list);
            }
        },
        .list => |l| {
            for (l.elts) |elt| {
                try collectTargetVarsToList(allocator, elt, list);
            }
        },
        .starred => |s| {
            try collectTargetVarsToList(allocator, s.value.*, list);
        },
        else => {}, // Ignore attribute, subscript, etc.
    }
}

/// Find variables captured from outer scope by nested function
/// outer_func_params: optional parameters of the outer function (when called during pre-scan)
pub fn findCapturedVars(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError![][]const u8 {
    return findCapturedVarsWithOuter(self, func, null);
}

/// Find variables captured from outer scope by nested function, with explicit outer params
pub fn findCapturedVarsWithOuter(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    outer_func_params: ?[]ast.Arg,
) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Collect all variables referenced in function body
    var referenced = std.ArrayList([]const u8){};
    defer referenced.deinit(self.allocator);

    try collectReferencedVars(self, func.body, &referenced);

    // Collect all variables that are locally assigned in function body
    // These shadow outer scope and should NOT be captured
    var locally_assigned = std.ArrayList([]const u8){};
    defer locally_assigned.deinit(self.allocator);
    collectLocallyAssignedVars(self.allocator, func.body, &locally_assigned) catch {};

    // Check which referenced vars are in outer scope (not params or local)
    for (referenced.items) |var_name| {
        // Skip if it's a function parameter
        var is_param = false;
        for (func.args) |arg| {
            if (std.mem.eql(u8, arg.name, var_name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;

        // Skip if it's locally assigned (shadows outer scope)
        var is_local = false;
        for (locally_assigned.items) |local_var| {
            if (std.mem.eql(u8, local_var, var_name)) {
                is_local = true;
                break;
            }
        }
        if (is_local) continue;

        // Check if variable is in outer scope (symbol table OR outer function's params)
        const in_symbol_table = self.symbol_table.lookup(var_name) != null;
        const in_outer_params = if (outer_func_params) |params| blk: {
            for (params) |param| {
                if (std.mem.eql(u8, param.name, var_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;

        if (in_symbol_table or in_outer_params) {
            // Add to captured list (avoid duplicates)
            var already_captured = false;
            for (captured.items) |captured_var| {
                if (std.mem.eql(u8, captured_var, var_name)) {
                    already_captured = true;
                    break;
                }
            }
            if (!already_captured) {
                try captured.append(self.allocator, var_name);
            }
        }
    }

    return captured.toOwnedSlice(self.allocator);
}

/// Collect all variable names that are assigned (as targets) in statements
/// These are local variables that shadow outer scope
fn collectLocallyAssignedVars(allocator: std.mem.Allocator, stmts: []ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    for (stmts) |stmt| {
        try collectLocallyAssignedVarsInNode(allocator, stmt, assigned);
    }
}

fn collectLocallyAssignedVarsInNode(allocator: std.mem.Allocator, node: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    switch (node) {
        .assign => |a| {
            for (a.targets) |target| {
                try collectAssignTargetVars(allocator, target, assigned);
            }
        },
        .aug_assign => |a| {
            try collectAssignTargetVars(allocator, a.target.*, assigned);
        },
        .for_stmt => |f| {
            // for loop target is a local variable
            try collectAssignTargetVars(allocator, f.target.*, assigned);
            for (f.body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
            for (i.else_body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
            for (t.handlers) |h| {
                // Exception variable is local
                if (h.name) |name| {
                    try addUniqueVar(allocator, assigned, name);
                }
                for (h.body) |s| {
                    try collectLocallyAssignedVarsInNode(allocator, s, assigned);
                }
            }
            for (t.else_body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
            for (t.finalbody) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
        },
        .with_stmt => |w| {
            // with ... as target: introduces local var(s)
            if (w.optional_vars) |target| {
                try collectTargetVarsToList(allocator, target.*, assigned);
            }
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNode(allocator, s, assigned);
            }
        },
        else => {},
    }
}

fn collectAssignTargetVars(allocator: std.mem.Allocator, target: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    switch (target) {
        .name => |n| {
            try addUniqueVar(allocator, assigned, n.id);
        },
        .tuple => |t| {
            for (t.elts) |elem| {
                try collectAssignTargetVars(allocator, elem, assigned);
            }
        },
        .list => |l| {
            for (l.elts) |elem| {
                try collectAssignTargetVars(allocator, elem, assigned);
            }
        },
        else => {},
    }
}

fn addUniqueVar(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), name: []const u8) !void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, name)) return;
    }
    try list.append(allocator, name);
}

/// Collect all variable names referenced in statements
fn collectReferencedVars(
    self: *NativeCodegen,
    stmts: []ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    for (stmts) |stmt| {
        try collectReferencedVarsInNode(self, stmt, referenced);
    }
}

/// Check if a parameter name is used in a list of statements
pub fn isParamUsedInStmts(param_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isParamUsedInNode(param_name, stmt)) return true;
    }
    return false;
}

/// Check if a parameter is reassigned in a list of statements
pub fn isParamReassignedInStmts(param_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isParamReassignedInNode(param_name, stmt)) return true;
    }
    return false;
}

/// Check if a parameter is reassigned in a node
fn isParamReassignedInNode(param_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .assign => |a| blk: {
            for (a.targets) |target| {
                if (target == .name and std.mem.eql(u8, target.name.id, param_name)) {
                    break :blk true;
                }
                // Handle tuple unpacking: a, b = ...
                if (target == .tuple) {
                    for (target.tuple.elts) |elt| {
                        if (elt == .name and std.mem.eql(u8, elt.name.id, param_name)) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        },
        .aug_assign => |a| blk: {
            if (a.target.* == .name and std.mem.eql(u8, a.target.name.id, param_name)) {
                break :blk true;
            }
            break :blk false;
        },
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            for (i.else_body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (isParamReassignedInNode(param_name, s)) break :blk true;
                }
            }
            for (t.finalbody) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Simple bounded array for local class names
const LocalClassArray = struct {
    items: [32][]const u8 = undefined,
    len: usize = 0,

    pub fn append(self: *@This(), item: []const u8) void {
        if (self.len < 32) {
            self.items[self.len] = item;
            self.len += 1;
        }
    }

    pub fn constSlice(self: *const @This()) []const []const u8 {
        return self.items[0..self.len];
    }
};

/// Check if all reassignments of a parameter are type-changing assignments (to constructors)
/// Type-changing pattern: param = ClassName(param, ...)
/// Returns true only if ALL reassignments match this pattern
pub fn areAllReassignmentsTypeChanging(param_name: []const u8, stmts: []ast.Node) bool {
    // First, collect all locally defined class names
    var local_classes = LocalClassArray{};
    collectLocalClassNames(stmts, &local_classes);

    for (stmts) |stmt| {
        if (!isReassignmentTypeChangingInNodeWithClasses(param_name, stmt, local_classes.constSlice())) {
            return false;
        }
    }
    return true;
}

/// Collect class names defined in statements
fn collectLocalClassNames(stmts: []ast.Node, classes: *LocalClassArray) void {
    for (stmts) |stmt| {
        collectLocalClassNamesInNode(stmt, classes);
    }
}

fn collectLocalClassNamesInNode(node: ast.Node, classes: *LocalClassArray) void {
    switch (node) {
        .class_def => |c| {
            classes.append(c.name);
        },
        .if_stmt => |i| {
            for (i.body) |s| collectLocalClassNamesInNode(s, classes);
            for (i.else_body) |s| collectLocalClassNamesInNode(s, classes);
        },
        .for_stmt => |f| {
            for (f.body) |s| collectLocalClassNamesInNode(s, classes);
        },
        .while_stmt => |w| {
            for (w.body) |s| collectLocalClassNamesInNode(s, classes);
        },
        .try_stmt => |t| {
            for (t.body) |s| collectLocalClassNamesInNode(s, classes);
            for (t.handlers) |h| {
                for (h.body) |s| collectLocalClassNamesInNode(s, classes);
            }
            for (t.else_body) |s| collectLocalClassNamesInNode(s, classes);
            for (t.finalbody) |s| collectLocalClassNamesInNode(s, classes);
        },
        else => {},
    }
}

/// Check if a node's reassignment (if any) is type-changing
/// Returns true if: no reassignment in this node, or the reassignment is type-changing
fn isReassignmentTypeChangingInNodeWithClasses(param_name: []const u8, node: ast.Node, local_classes: []const []const u8) bool {
    return switch (node) {
        .assign => |a| blk: {
            for (a.targets) |target| {
                if (target == .name and std.mem.eql(u8, target.name.id, param_name)) {
                    // Check if RHS is a constructor call (ClassName(...))
                    if (a.value.* == .call and a.value.call.func.* == .name) {
                        const func_name = a.value.call.func.name.id;
                        // Check if starts with uppercase (class constructor) OR is a locally defined class
                        if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                            break :blk true; // Conventional class name
                        }
                        // Check if it's a locally defined class (even lowercase)
                        for (local_classes) |class_name| {
                            if (std.mem.eql(u8, func_name, class_name)) {
                                break :blk true; // Local class constructor
                            }
                        }
                    }
                    // Not a type-changing assignment
                    break :blk false;
                }
                // Handle tuple unpacking: a, b = ...
                // Tuple reassignments are NOT type-changing (they assign raw values)
                if (target == .tuple) {
                    for (target.tuple.elts) |elt| {
                        if (elt == .name and std.mem.eql(u8, elt.name.id, param_name)) {
                            // Found our param in tuple - this is NOT a type-changing assignment
                            break :blk false;
                        }
                    }
                }
            }
            // This assignment doesn't target our param
            break :blk true;
        },
        .aug_assign => |a| blk: {
            // Aug assign (+=, etc.) can't be type-changing
            if (a.target.* == .name and std.mem.eql(u8, a.target.name.id, param_name)) {
                break :blk false;
            }
            break :blk true;
        },
        .if_stmt => |i| blk: {
            // Collect classes from if body
            var local_if_classes = LocalClassArray{};
            for (local_classes) |c| local_if_classes.append(c);
            collectLocalClassNames(i.body, &local_if_classes);
            collectLocalClassNames(i.else_body, &local_if_classes);

            for (i.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_if_classes.constSlice())) {
                    break :blk false;
                }
            }
            for (i.else_body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_if_classes.constSlice())) break :blk false;
            }
            break :blk true;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            break :blk true;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            break :blk true;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
                }
            }
            for (t.else_body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            for (t.finalbody) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            break :blk true;
        },
        else => true, // No assignment in this node type
    };
}

/// Check if any of the captured variables are actually used in the function body
pub fn areCapturedVarsUsed(captured_vars: [][]const u8, stmts: []ast.Node) bool {
    for (captured_vars) |var_name| {
        if (isParamUsedInStmts(var_name, stmts)) return true;
    }
    return false;
}

/// Check if a function is recursive (calls itself by name)
pub fn isRecursiveFunction(func_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isRecursiveCall(func_name, stmt)) return true;
    }
    return false;
}

/// Check if a node contains a recursive call to func_name
fn isRecursiveCall(func_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .call => |c| blk: {
            // Check if the function being called is the recursive function
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, func_name)) {
                break :blk true;
            }
            // Also check arguments for nested recursive calls
            for (c.args) |arg| {
                if (isRecursiveCall(func_name, arg)) break :blk true;
            }
            break :blk false;
        },
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            for (i.else_body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .expr_stmt => |e| isRecursiveCall(func_name, e.value.*),
        .return_stmt => |r| if (r.value) |v| isRecursiveCall(func_name, v.*) else false,
        .assign => |a| isRecursiveCall(func_name, a.value.*),
        .binop => |b| isRecursiveCall(func_name, b.left.*) or isRecursiveCall(func_name, b.right.*),
        .unaryop => |u| isRecursiveCall(func_name, u.operand.*),
        .if_expr => |ie| isRecursiveCall(func_name, ie.condition.*) or
            isRecursiveCall(func_name, ie.body.*) or
            isRecursiveCall(func_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isRecursiveCall(func_name, elt)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if a parameter name is used in a single node
fn isParamUsedInNode(param_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .name => |n| std.mem.eql(u8, n.id, param_name),
        .binop => |b| isParamUsedInNode(param_name, b.left.*) or isParamUsedInNode(param_name, b.right.*),
        .unaryop => |u| isParamUsedInNode(param_name, u.operand.*),
        .call => |c| blk: {
            if (isParamUsedInNode(param_name, c.func.*)) break :blk true;
            for (c.args) |arg| {
                // Handle starred (*args) and double_starred (**kwargs) unpacking
                if (arg == .starred) {
                    if (isParamUsedInNode(param_name, arg.starred.value.*)) break :blk true;
                } else if (arg == .double_starred) {
                    if (isParamUsedInNode(param_name, arg.double_starred.value.*)) break :blk true;
                } else if (isParamUsedInNode(param_name, arg)) {
                    break :blk true;
                }
            }
            for (c.keyword_args) |kw| {
                if (isParamUsedInNode(param_name, kw.value)) break :blk true;
            }
            break :blk false;
        },
        .return_stmt => |ret| if (ret.value) |val| isParamUsedInNode(param_name, val.*) else false,
        .assign => |assign| blk: {
            // Check the value
            if (isParamUsedInNode(param_name, assign.value.*)) break :blk true;
            // Also check targets for subscript/attribute assignments (e.g., d['b'] = 5 uses d)
            for (assign.targets) |target| {
                if (target == .subscript) {
                    if (isParamUsedInNode(param_name, target.subscript.value.*)) break :blk true;
                } else if (target == .attribute) {
                    if (isParamUsedInNode(param_name, target.attribute.value.*)) break :blk true;
                }
            }
            break :blk false;
        },
        .compare => |cmp| blk: {
            if (isParamUsedInNode(param_name, cmp.left.*)) break :blk true;
            for (cmp.comparators) |comp| {
                if (isParamUsedInNode(param_name, comp)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| isParamUsedInNode(param_name, sub.value.*) or
            (if (sub.slice == .index) isParamUsedInNode(param_name, sub.slice.index.*) else false),
        .attribute => |attr| isParamUsedInNode(param_name, attr.value.*),
        .if_stmt => |i| blk: {
            if (isParamUsedInNode(param_name, i.condition.*)) break :blk true;
            if (isParamUsedInStmts(param_name, i.body)) break :blk true;
            if (isParamUsedInStmts(param_name, i.else_body)) break :blk true;
            break :blk false;
        },
        .if_expr => |ie| isParamUsedInNode(param_name, ie.condition.*) or
            isParamUsedInNode(param_name, ie.body.*) or
            isParamUsedInNode(param_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isParamUsedInNode(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |elt| {
                if (isParamUsedInNode(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |key| {
                if (isParamUsedInNode(param_name, key)) break :blk true;
            }
            for (d.values) |val| {
                if (isParamUsedInNode(param_name, val)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (isParamUsedInNode(param_name, f.iter.*)) break :blk true;
            if (isParamUsedInStmts(param_name, f.body)) break :blk true;
            if (f.orelse_body) |ob| {
                if (isParamUsedInStmts(param_name, ob)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (isParamUsedInNode(param_name, w.condition.*)) break :blk true;
            if (isParamUsedInStmts(param_name, w.body)) break :blk true;
            break :blk false;
        },
        .expr_stmt => |e| isParamUsedInNode(param_name, e.value.*),
        .aug_assign => |a| blk: {
            // Check both target and value: a *= b uses both a and b
            if (isParamUsedInNode(param_name, a.target.*)) break :blk true;
            if (isParamUsedInNode(param_name, a.value.*)) break :blk true;
            break :blk false;
        },
        .boolop => |bo| blk: {
            for (bo.values) |v| {
                if (isParamUsedInNode(param_name, v)) break :blk true;
            }
            break :blk false;
        },
        .class_def => |cls| blk: {
            // Check if param is used in nested class body (methods, etc.)
            if (isParamUsedInStmts(param_name, cls.body)) break :blk true;
            break :blk false;
        },
        .function_def => |func| blk: {
            // Check if param is used in nested function body
            // But NOT if it's shadowed by a parameter with the same name
            for (func.args) |arg| {
                if (std.mem.eql(u8, arg.name, param_name)) {
                    // Shadowed by nested function's parameter
                    break :blk false;
                }
            }
            if (isParamUsedInStmts(param_name, func.body)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            if (isParamUsedInStmts(param_name, t.body)) break :blk true;
            for (t.handlers) |h| {
                if (isParamUsedInStmts(param_name, h.body)) break :blk true;
            }
            if (isParamUsedInStmts(param_name, t.else_body)) break :blk true;
            if (isParamUsedInStmts(param_name, t.finalbody)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| blk: {
            if (isParamUsedInNode(param_name, w.context_expr.*)) break :blk true;
            if (isParamUsedInStmts(param_name, w.body)) break :blk true;
            break :blk false;
        },
        .lambda => |lam| blk: {
            // Check if param is used in lambda body
            // But NOT if it's shadowed by a lambda parameter with the same name
            for (lam.args) |arg| {
                if (std.mem.eql(u8, arg.name, param_name)) {
                    // Shadowed by lambda's parameter
                    break :blk false;
                }
            }
            if (isParamUsedInNode(param_name, lam.body.*)) break :blk true;
            break :blk false;
        },
        .listcomp => |lc| blk: {
            // Check element expression and generators
            if (isParamUsedInNode(param_name, lc.elt.*)) break :blk true;
            for (lc.generators) |gen| {
                // Check iterator expression (NOT loop target - that shadows)
                if (isParamUsedInNode(param_name, gen.iter.*)) break :blk true;
                for (gen.ifs) |if_node| {
                    if (isParamUsedInNode(param_name, if_node)) break :blk true;
                }
            }
            break :blk false;
        },
        .dictcomp => |dc| blk: {
            if (isParamUsedInNode(param_name, dc.key.*)) break :blk true;
            if (isParamUsedInNode(param_name, dc.value.*)) break :blk true;
            for (dc.generators) |gen| {
                if (isParamUsedInNode(param_name, gen.iter.*)) break :blk true;
                for (gen.ifs) |if_node| {
                    if (isParamUsedInNode(param_name, if_node)) break :blk true;
                }
            }
            break :blk false;
        },
        .genexp => |ge| blk: {
            if (isParamUsedInNode(param_name, ge.elt.*)) break :blk true;
            for (ge.generators) |gen| {
                if (isParamUsedInNode(param_name, gen.iter.*)) break :blk true;
                for (gen.ifs) |if_node| {
                    if (isParamUsedInNode(param_name, if_node)) break :blk true;
                }
            }
            break :blk false;
        },
        // f-string support: f"{tag}..." uses the variable 'tag'
        .fstring => |fstr| blk: {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (isParamUsedInNode(param_name, e.node.*)) break :blk true,
                    .format_expr => |fe| if (isParamUsedInNode(param_name, fe.expr.*)) break :blk true,
                    .conv_expr => |ce| if (isParamUsedInNode(param_name, ce.expr.*)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Collect variable names from a single node
fn collectReferencedVarsInNode(
    self: *NativeCodegen,
    node: ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    switch (node) {
        .name => |n| {
            try referenced.append(self.allocator, n.id);
        },
        .binop => |b| {
            try collectReferencedVarsInNode(self, b.left.*, referenced);
            try collectReferencedVarsInNode(self, b.right.*, referenced);
        },
        .call => |c| {
            try collectReferencedVarsInNode(self, c.func.*, referenced);
            for (c.args) |arg| {
                try collectReferencedVarsInNode(self, arg, referenced);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectReferencedVarsInNode(self, val.*, referenced);
            }
        },
        .assign => |assign| {
            try collectReferencedVarsInNode(self, assign.value.*, referenced);
        },
        .compare => |cmp| {
            try collectReferencedVarsInNode(self, cmp.left.*, referenced);
            for (cmp.comparators) |comp| {
                try collectReferencedVarsInNode(self, comp, referenced);
            }
        },
        else => {},
    }
}

/// Collect all variable names used in statements (for func_local_uses tracking)
pub fn collectUsedNames(stmts: []ast.Node, uses: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    for (stmts) |stmt| {
        try collectUsedNamesFromNode(stmt, uses);
    }
}

/// Check if function body has any return statements with values
/// Returns true if there's at least one `return expr` (not just `return`)
pub fn hasReturnWithValue(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (hasReturnWithValueInNode(stmt)) return true;
    }
    return false;
}

/// Check if function body can produce errors (has try-worthy operations)
/// Used to determine if closure return type should be error union
pub fn canProduceErrors(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (canProduceErrorsInNode(stmt)) return true;
    }
    return false;
}

fn canProduceErrorsInNode(node: ast.Node) bool {
    return switch (node) {
        // Operations that generate try in Zig
        .call => true, // All Python calls can potentially error
        .attribute => true, // Attribute access can fail
        .subscript => true, // Subscript can fail
        .expr_stmt => |e| canProduceErrorsInNode(e.value.*),
        .assign => |a| canProduceErrorsInNode(a.value.*),
        .if_stmt => |i| blk: {
            if (canProduceErrors(i.body)) break :blk true;
            if (canProduceErrors(i.else_body)) break :blk true;
            break :blk canProduceErrorsInNode(i.condition.*);
        },
        .for_stmt => |f| blk: {
            if (canProduceErrors(f.body)) break :blk true;
            if (f.orelse_body) |ob| if (canProduceErrors(ob)) break :blk true;
            break :blk canProduceErrorsInNode(f.iter.*);
        },
        .while_stmt => |w| blk: {
            if (canProduceErrors(w.body)) break :blk true;
            break :blk canProduceErrorsInNode(w.condition.*);
        },
        .try_stmt => true, // try/except can error
        .with_stmt => |w| blk: {
            if (canProduceErrors(w.body)) break :blk true;
            break :blk canProduceErrorsInNode(w.context_expr.*);
        },
        .return_stmt => |r| if (r.value) |v| canProduceErrorsInNode(v.*) else false,
        .binop => |b| canProduceErrorsInNode(b.left.*) or canProduceErrorsInNode(b.right.*),
        .unaryop => |u| canProduceErrorsInNode(u.operand.*),
        .compare => |c| blk: {
            if (canProduceErrorsInNode(c.left.*)) break :blk true;
            for (c.comparators) |comp| {
                if (canProduceErrorsInNode(comp)) break :blk true;
            }
            break :blk false;
        },
        .if_expr => |ie| canProduceErrorsInNode(ie.condition.*) or
            canProduceErrorsInNode(ie.body.*) or
            canProduceErrorsInNode(ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| if (canProduceErrorsInNode(elt)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |elt| if (canProduceErrorsInNode(elt)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| if (canProduceErrorsInNode(k)) break :blk true;
            for (d.values) |v| if (canProduceErrorsInNode(v)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn hasReturnWithValueInNode(node: ast.Node) bool {
    return switch (node) {
        .return_stmt => |r| r.value != null,
        .if_stmt => |i| blk: {
            if (hasReturnWithValue(i.body)) break :blk true;
            if (hasReturnWithValue(i.else_body)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (hasReturnWithValue(f.body)) break :blk true;
            if (f.orelse_body) |ob| {
                if (hasReturnWithValue(ob)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (hasReturnWithValue(w.body)) break :blk true;
            if (w.orelse_body) |ob| {
                if (hasReturnWithValue(ob)) break :blk true;
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            if (hasReturnWithValue(t.body)) break :blk true;
            for (t.handlers) |h| {
                if (hasReturnWithValue(h.body)) break :blk true;
            }
            if (hasReturnWithValue(t.else_body)) break :blk true;
            if (hasReturnWithValue(t.finalbody)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| hasReturnWithValue(w.body),
        else => false,
    };
}

fn collectUsedNamesFromNode(node: ast.Node, uses: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    switch (node) {
        .name => |n| {
            try uses.put(n.id, {});
        },
        .assign => |a| {
            // Collect target names (assigned variables should be marked as used)
            for (a.targets) |target| {
                try collectUsedNamesFromNode(target, uses);
            }
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .aug_assign => |a| {
            try collectUsedNamesFromNode(a.target.*, uses);
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .binop => |b| {
            try collectUsedNamesFromNode(b.left.*, uses);
            try collectUsedNamesFromNode(b.right.*, uses);
        },
        .unaryop => |u| {
            try collectUsedNamesFromNode(u.operand.*, uses);
        },
        .call => |c| {
            try collectUsedNamesFromNode(c.func.*, uses);
            for (c.args) |arg| {
                try collectUsedNamesFromNode(arg, uses);
            }
        },
        .attribute => |a| {
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .subscript => |s| {
            try collectUsedNamesFromNode(s.value.*, uses);
            switch (s.slice) {
                .index => |idx| try collectUsedNamesFromNode(idx.*, uses),
                .slice => |sl| {
                    if (sl.lower) |l| try collectUsedNamesFromNode(l.*, uses);
                    if (sl.upper) |upper| try collectUsedNamesFromNode(upper.*, uses);
                    if (sl.step) |st| try collectUsedNamesFromNode(st.*, uses);
                },
            }
        },
        .if_stmt => |i| {
            try collectUsedNamesFromNode(i.condition.*, uses);
            try collectUsedNames(i.body, uses);
            try collectUsedNames(i.else_body, uses);
        },
        .if_expr => |ie| {
            try collectUsedNamesFromNode(ie.condition.*, uses);
            try collectUsedNamesFromNode(ie.body.*, uses);
            try collectUsedNamesFromNode(ie.orelse_value.*, uses);
        },
        .for_stmt => |f| {
            try collectUsedNamesFromNode(f.target.*, uses);
            try collectUsedNamesFromNode(f.iter.*, uses);
            try collectUsedNames(f.body, uses);
            if (f.orelse_body) |else_body| {
                try collectUsedNames(else_body, uses);
            }
        },
        .while_stmt => |w| {
            try collectUsedNamesFromNode(w.condition.*, uses);
            try collectUsedNames(w.body, uses);
            if (w.orelse_body) |else_body| {
                try collectUsedNames(else_body, uses);
            }
        },
        .return_stmt => |r| {
            if (r.value) |v| try collectUsedNamesFromNode(v.*, uses);
        },
        .expr_stmt => |e| {
            try collectUsedNamesFromNode(e.value.*, uses);
        },
        .compare => |c| {
            try collectUsedNamesFromNode(c.left.*, uses);
            for (c.comparators) |cmp| {
                try collectUsedNamesFromNode(cmp, uses);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try collectUsedNamesFromNode(elt, uses);
            }
        },
        .list => |l| {
            for (l.elts) |elt| {
                try collectUsedNamesFromNode(elt, uses);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try collectUsedNamesFromNode(key, uses);
            }
            for (d.values) |val| {
                try collectUsedNamesFromNode(val, uses);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try collectUsedNamesFromNode(val, uses);
            }
        },
        .function_def => |f| {
            // For nested functions, collect names used in the body
            try collectUsedNames(f.body, uses);
        },
        else => {
            // Other node types don't contain name references we need to track
        },
    }
}
