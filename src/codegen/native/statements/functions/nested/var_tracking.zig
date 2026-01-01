/// Variable tracking for closures - finding captured vars, analyzing usage patterns
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");

/// Check if a variable is declared as `nonlocal` in a function body.
/// Used to determine if a captured variable needs pointer-based capture.
pub fn isNonlocalVar(var_name: []const u8, stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        if (isNonlocalVarInNode(var_name, stmt)) return true;
    }
    return false;
}

fn isNonlocalVarInNode(var_name: []const u8, node: ast.Node) bool {
    switch (node) {
        .nonlocal_stmt => |n| {
            for (n.names) |name| {
                if (std.mem.eql(u8, name, var_name)) return true;
            }
        },
        // Recurse into compound statements (but NOT nested functions - they have their own scope)
        .if_stmt => |i| {
            for (i.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            for (i.else_body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        .for_stmt => |f| {
            for (f.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            if (f.orelse_body) |ob| for (ob) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        .while_stmt => |w| {
            for (w.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            if (w.orelse_body) |ob| for (ob) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        .try_stmt => |t| {
            for (t.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            for (t.handlers) |h| for (h.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            for (t.else_body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
            for (t.finalbody) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        .with_stmt => |w| {
            for (w.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        .match_stmt => |m| {
            for (m.cases) |c| for (c.body) |s| if (isNonlocalVarInNode(var_name, s)) return true;
        },
        else => {},
    }
    return false;
}

/// Collect all `nonlocal` variable declarations from a function body.
/// Returns a set of variable names that are declared as nonlocal.
/// These variables should NOT be treated as local assignments.
pub fn collectNonlocalVars(allocator: std.mem.Allocator, stmts: []const ast.Node) !hashmap_helper.StringHashMap(void) {
    var nonlocals = hashmap_helper.StringHashMap(void).init(allocator);
    for (stmts) |stmt| {
        try collectNonlocalVarsInNode(allocator, stmt, &nonlocals);
    }
    return nonlocals;
}

fn collectNonlocalVarsInNode(allocator: std.mem.Allocator, node: ast.Node, nonlocals: *hashmap_helper.StringHashMap(void)) !void {
    switch (node) {
        .nonlocal_stmt => |n| {
            for (n.names) |name| {
                try nonlocals.put(name, {});
            }
        },
        // Recurse into compound statements (but NOT nested functions - they have their own scope)
        .if_stmt => |i| {
            for (i.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            for (i.else_body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        .for_stmt => |f| {
            for (f.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            if (f.orelse_body) |ob| for (ob) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        .while_stmt => |w| {
            for (w.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            if (w.orelse_body) |ob| for (ob) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        .try_stmt => |t| {
            for (t.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            for (t.handlers) |h| for (h.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            for (t.else_body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
            for (t.finalbody) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        .with_stmt => |w| {
            for (w.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        .match_stmt => |m| {
            for (m.cases) |c| for (c.body) |s| try collectNonlocalVarsInNode(allocator, s, nonlocals);
        },
        else => {},
    }
}

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
    return findCapturedVarsWithSpecialParams(self, func, outer_func_params, null, null);
}

/// Extended version that also considers outer *args and **kwargs parameters
pub fn findCapturedVarsWithSpecialParams(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    outer_func_params: ?[]ast.Arg,
    outer_vararg: ?[]const u8,
    outer_kwarg: ?[]const u8,
) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Collect all variables referenced in function body
    var referenced = std.ArrayList([]const u8){};
    defer referenced.deinit(self.allocator);

    try collectReferencedVars(self, func.body, &referenced);

    // FIRST: Collect nonlocal declarations in this function body
    // Nonlocal variables reference the enclosing scope and should NOT be treated as local
    var nonlocals = collectNonlocalVars(self.allocator, func.body) catch hashmap_helper.StringHashMap(void).init(self.allocator);
    defer nonlocals.deinit();

    // Collect all variables that are locally assigned in function body
    // These shadow outer scope and should NOT be captured
    // IMPORTANT: Exclude nonlocal vars - they reference outer scope, not local
    var locally_assigned = std.ArrayList([]const u8){};
    defer locally_assigned.deinit(self.allocator);
    collectLocallyAssignedVarsExcludingNonlocal(self.allocator, func.body, &locally_assigned, &nonlocals) catch {};

    // EXPLICITLY add nonlocal vars to the captured list
    // `nonlocal x` declares intent to modify outer scope's x, even if only assigned
    for (nonlocals.keys()) |nonlocal_var| {
        // Check if variable is in outer scope
        const in_symbol_table = self.symbol_table.lookup(nonlocal_var) != null;
        const in_outer_params = if (outer_func_params) |params| blk: {
            for (params) |param| {
                if (std.mem.eql(u8, param.name, nonlocal_var)) {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;
        const in_outer_vararg = if (outer_vararg) |varg| std.mem.eql(u8, varg, nonlocal_var) else false;
        const in_outer_kwarg = if (outer_kwarg) |kwarg| std.mem.eql(u8, kwarg, nonlocal_var) else false;

        if (in_symbol_table or in_outer_params or in_outer_vararg or in_outer_kwarg) {
            try captured.append(self.allocator, nonlocal_var);
        }
    }

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

        // Check if variable is in outer scope (symbol table OR outer function's params/vararg/kwarg)
        const in_symbol_table = self.symbol_table.lookup(var_name) != null;
        const in_outer_params = if (outer_func_params) |params| blk: {
            for (params) |param| {
                if (std.mem.eql(u8, param.name, var_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;

        // Check if it's the outer function's *args parameter
        const in_outer_vararg = if (outer_vararg) |varg|
            std.mem.eql(u8, varg, var_name)
        else
            false;

        // Check if it's the outer function's **kwargs parameter
        const in_outer_kwarg = if (outer_kwarg) |kwarg|
            std.mem.eql(u8, kwarg, var_name)
        else
            false;

        if (in_symbol_table or in_outer_params or in_outer_vararg or in_outer_kwarg) {
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
    // No nonlocal exclusions - backward compatible version
    try collectLocallyAssignedVarsExcludingNonlocal(allocator, stmts, assigned, null);
}

/// Collect locally assigned vars, but exclude variables declared as `nonlocal`
/// nonlocal variables are NOT local - they reference the enclosing scope
fn collectLocallyAssignedVarsExcludingNonlocal(
    allocator: std.mem.Allocator,
    stmts: []ast.Node,
    assigned: *std.ArrayList([]const u8),
    nonlocals: ?*const hashmap_helper.StringHashMap(void),
) !void {
    for (stmts) |stmt| {
        try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, stmt, assigned, nonlocals);
    }
}

fn collectLocallyAssignedVarsInNode(allocator: std.mem.Allocator, node: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, node, assigned, null);
}

fn collectLocallyAssignedVarsInNodeExcludingNonlocal(
    allocator: std.mem.Allocator,
    node: ast.Node,
    assigned: *std.ArrayList([]const u8),
    nonlocals: ?*const hashmap_helper.StringHashMap(void),
) !void {
    switch (node) {
        .assign => |a| {
            for (a.targets) |target| {
                try collectAssignTargetVarsExcludingNonlocal(allocator, target, assigned, nonlocals);
            }
        },
        .aug_assign => |a| {
            try collectAssignTargetVarsExcludingNonlocal(allocator, a.target.*, assigned, nonlocals);
        },
        .for_stmt => |f| {
            // for loop target is a local variable
            try collectAssignTargetVarsExcludingNonlocal(allocator, f.target.*, assigned, nonlocals);
            for (f.body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
                }
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
            for (i.else_body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
                }
            }
        },
        .match_stmt => |m| {
            for (m.cases) |case| {
                for (case.body) |s| {
                    try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
                }
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
            for (t.handlers) |h| {
                // Exception variable is local (unless declared nonlocal, which is rare)
                if (h.name) |name| {
                    if (nonlocals == null or !nonlocals.?.contains(name)) {
                        try addUniqueVar(allocator, assigned, name);
                    }
                }
                for (h.body) |s| {
                    try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
                }
            }
            for (t.else_body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
            for (t.finalbody) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
        },
        .with_stmt => |w| {
            // with ... as target: introduces local var(s)
            if (w.optional_vars) |target| {
                try collectAssignTargetVarsExcludingNonlocal(allocator, target.*, assigned, nonlocals);
            }
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNodeExcludingNonlocal(allocator, s, assigned, nonlocals);
            }
        },
        else => {},
    }
}

fn collectAssignTargetVars(allocator: std.mem.Allocator, target: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    try collectAssignTargetVarsExcludingNonlocal(allocator, target, assigned, null);
}

fn collectAssignTargetVarsExcludingNonlocal(
    allocator: std.mem.Allocator,
    target: ast.Node,
    assigned: *std.ArrayList([]const u8),
    nonlocals: ?*const hashmap_helper.StringHashMap(void),
) !void {
    switch (target) {
        .name => |n| {
            // Skip if this variable is declared as nonlocal
            if (nonlocals == null or !nonlocals.?.contains(n.id)) {
                try addUniqueVar(allocator, assigned, n.id);
            }
        },
        .tuple => |t| {
            for (t.elts) |elem| {
                try collectAssignTargetVarsExcludingNonlocal(allocator, elem, assigned, nonlocals);
            }
        },
        .list => |l| {
            for (l.elts) |elem| {
                try collectAssignTargetVarsExcludingNonlocal(allocator, elem, assigned, nonlocals);
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

/// Check if a variable is mutated via method calls in a list of statements
/// This detects patterns like: var.append(x), var.extend(y), var[k] = v
/// Used to determine if captured variables need to be captured by pointer
pub fn isVarMutatedInStmts(var_name: []const u8, stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        if (isVarMutatedInNode(var_name, stmt)) return true;
    }
    return false;
}

/// List mutation methods that require mutable access
const MutatingMethods = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} },
    .{ "extend", {} },
    .{ "insert", {} },
    .{ "remove", {} },
    .{ "pop", {} },
    .{ "clear", {} },
    .{ "sort", {} },
    .{ "reverse", {} },
    .{ "add", {} }, // set.add()
    .{ "discard", {} }, // set.discard()
    .{ "update", {} }, // dict/set.update()
    .{ "setdefault", {} }, // dict.setdefault()
    .{ "popitem", {} }, // dict.popitem()
});

/// Check if a variable is mutated in a single node
fn isVarMutatedInNode(var_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        // Check for mutating method calls: var.append(x)
        .expr_stmt => |e| isVarMutatedInExpr(var_name, e.value.*),
        // Check for subscript assignment: var[k] = v
        .assign => |a| blk: {
            for (a.targets) |target| {
                if (target == .subscript) {
                    const sub = target.subscript;
                    if (sub.value.* == .name and std.mem.eql(u8, sub.value.name.id, var_name)) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        },
        // Check for augmented assignment: var += x
        .aug_assign => |a| blk: {
            if (a.target.* == .name and std.mem.eql(u8, a.target.name.id, var_name)) {
                break :blk true;
            }
            break :blk false;
        },
        // Recurse into compound statements
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            for (i.else_body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isVarMutatedInNode(var_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isVarMutatedInNode(var_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (isVarMutatedInNode(var_name, s)) break :blk true;
                }
            }
            for (t.else_body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (isVarMutatedInNode(var_name, s)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (isVarMutatedInNode(var_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if expression contains a mutating call on the variable
fn isVarMutatedInExpr(var_name: []const u8, expr: ast.Node) bool {
    return switch (expr) {
        // Check for method calls: var.method(...)
        .call => |c| blk: {
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                // Check if it's a call on our variable
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, var_name)) {
                    // Check if the method is mutating
                    if (MutatingMethods.has(attr.attr)) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        },
        else => false,
    };
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
                // Handle list unpacking: [a, b] = ... or a, b = ... (when parsed as list)
                if (target == .list) {
                    for (target.list.elts) |elt| {
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
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isParamReassignedInNode(param_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isParamReassignedInNode(param_name, s)) break :blk true;
                }
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
            for (t.else_body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (isParamReassignedInNode(param_name, s)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (isParamReassignedInNode(param_name, s)) break :blk true;
                }
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
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| collectLocalClassNamesInNode(s, classes);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| collectLocalClassNamesInNode(s, classes);
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| collectLocalClassNamesInNode(s, classes);
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| collectLocalClassNamesInNode(s, classes);
            for (t.handlers) |h| {
                for (h.body) |s| collectLocalClassNamesInNode(s, classes);
            }
            for (t.else_body) |s| collectLocalClassNamesInNode(s, classes);
            for (t.finalbody) |s| collectLocalClassNamesInNode(s, classes);
        },
        .with_stmt => |w| {
            for (w.body) |s| collectLocalClassNamesInNode(s, classes);
        },
        .match_stmt => |m| {
            for (m.cases) |case| {
                for (case.body) |s| collectLocalClassNamesInNode(s, classes);
            }
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
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
                }
            }
            break :blk true;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
                }
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
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
            }
            break :blk true;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (!isReassignmentTypeChangingInNodeWithClasses(param_name, s, local_classes)) break :blk false;
                }
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

/// Check if a function is self-referential (accesses itself via attribute, e.g., f.x)
/// This requires the recursive closure pattern because the function name must be
/// defined before the body can access it.
pub fn isSelfReferential(func_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isSelfReference(func_name, stmt)) return true;
    }
    return false;
}

/// Check if a node contains a self-reference to func_name (via attribute access)
fn isSelfReference(func_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .attribute => |a| blk: {
            // Check if the attribute's object is the function name (e.g., f.x where f is func_name)
            if (a.value.* == .name and std.mem.eql(u8, a.value.name.id, func_name)) {
                break :blk true;
            }
            // Recurse into the value
            break :blk isSelfReference(func_name, a.value.*);
        },
        .call => |c| blk: {
            // Check the function expression
            if (isSelfReference(func_name, c.func.*)) break :blk true;
            // Check arguments
            for (c.args) |arg| {
                if (isSelfReference(func_name, arg)) break :blk true;
            }
            break :blk false;
        },
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            for (i.else_body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isSelfReference(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isSelfReference(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (isSelfReference(func_name, s)) break :blk true;
                }
            }
            for (t.else_body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (isSelfReference(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (isSelfReference(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .expr_stmt => |e| isSelfReference(func_name, e.value.*),
        .return_stmt => |r| if (r.value) |v| isSelfReference(func_name, v.*) else false,
        .assign => |a| isSelfReference(func_name, a.value.*),
        .aug_assign => |a| isSelfReference(func_name, a.value.*),
        .binop => |b| isSelfReference(func_name, b.left.*) or isSelfReference(func_name, b.right.*),
        .unaryop => |u| isSelfReference(func_name, u.operand.*),
        .if_expr => |ie| isSelfReference(func_name, ie.condition.*) or
            isSelfReference(func_name, ie.body.*) or
            isSelfReference(func_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isSelfReference(func_name, elt)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
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
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isRecursiveCall(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (isRecursiveCall(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (isRecursiveCall(func_name, s)) break :blk true;
                }
            }
            for (t.else_body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (isRecursiveCall(func_name, s)) break :blk true;
                }
            }
            break :blk false;
        },
        .expr_stmt => |e| isRecursiveCall(func_name, e.value.*),
        .return_stmt => |r| if (r.value) |v| isRecursiveCall(func_name, v.*) else false,
        .assign => |a| isRecursiveCall(func_name, a.value.*),
        .aug_assign => |a| isRecursiveCall(func_name, a.value.*),
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
                    // Check the subscript value (e.g., b in b[i])
                    if (isParamUsedInNode(param_name, target.subscript.value.*)) break :blk true;
                    // Also check the subscript index (e.g., i in b[i])
                    if (target.subscript.slice == .index) {
                        if (isParamUsedInNode(param_name, target.subscript.slice.index.*)) break :blk true;
                    }
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
            if (w.orelse_body) |ob| {
                if (isParamUsedInStmts(param_name, ob)) break :blk true;
            }
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
        // raise statement: raise ValueError(v) uses v
        .raise_stmt => |r| blk: {
            if (r.exc) |exc| {
                if (isParamUsedInNode(param_name, exc.*)) break :blk true;
            }
            if (r.cause) |cause| {
                if (isParamUsedInNode(param_name, cause.*)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            if (isParamUsedInNode(param_name, m.subject.*)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    if (isParamUsedInNode(param_name, guard.*)) break :blk true;
                }
                if (isParamUsedInStmts(param_name, case.body)) break :blk true;
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
        .unaryop => |u| {
            try collectReferencedVarsInNode(self, u.operand.*, referenced);
        },
        .call => |c| {
            try collectReferencedVarsInNode(self, c.func.*, referenced);
            for (c.args) |arg| {
                if (arg == .starred) {
                    try collectReferencedVarsInNode(self, arg.starred.value.*, referenced);
                } else if (arg == .double_starred) {
                    try collectReferencedVarsInNode(self, arg.double_starred.value.*, referenced);
                } else {
                    try collectReferencedVarsInNode(self, arg, referenced);
                }
            }
            for (c.keyword_args) |kw| {
                try collectReferencedVarsInNode(self, kw.value, referenced);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectReferencedVarsInNode(self, val.*, referenced);
            }
        },
        .assign => |assign| {
            try collectReferencedVarsInNode(self, assign.value.*, referenced);
            // Also check targets for subscript/attribute assignments
            for (assign.targets) |target| {
                if (target == .subscript) {
                    try collectReferencedVarsInNode(self, target.subscript.value.*, referenced);
                } else if (target == .attribute) {
                    try collectReferencedVarsInNode(self, target.attribute.value.*, referenced);
                }
            }
        },
        .aug_assign => |a| {
            try collectReferencedVarsInNode(self, a.target.*, referenced);
            try collectReferencedVarsInNode(self, a.value.*, referenced);
        },
        .compare => |cmp| {
            try collectReferencedVarsInNode(self, cmp.left.*, referenced);
            for (cmp.comparators) |comp| {
                try collectReferencedVarsInNode(self, comp, referenced);
            }
        },
        .subscript => |sub| {
            try collectReferencedVarsInNode(self, sub.value.*, referenced);
            switch (sub.slice) {
                .index => |idx| try collectReferencedVarsInNode(self, idx.*, referenced),
                .slice => |range| {
                    if (range.lower) |lower| try collectReferencedVarsInNode(self, lower.*, referenced);
                    if (range.upper) |upper| try collectReferencedVarsInNode(self, upper.*, referenced);
                    if (range.step) |step| try collectReferencedVarsInNode(self, step.*, referenced);
                },
            }
        },
        .attribute => |attr| {
            try collectReferencedVarsInNode(self, attr.value.*, referenced);
        },
        .if_expr => |ie| {
            try collectReferencedVarsInNode(self, ie.condition.*, referenced);
            try collectReferencedVarsInNode(self, ie.body.*, referenced);
            try collectReferencedVarsInNode(self, ie.orelse_value.*, referenced);
        },
        .list => |l| {
            for (l.elts) |elt| {
                try collectReferencedVarsInNode(self, elt, referenced);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try collectReferencedVarsInNode(self, elt, referenced);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try collectReferencedVarsInNode(self, key, referenced);
            }
            for (d.values) |val| {
                try collectReferencedVarsInNode(self, val, referenced);
            }
        },
        .boolop => |bo| {
            for (bo.values) |v| {
                try collectReferencedVarsInNode(self, v, referenced);
            }
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| try collectReferencedVarsInNode(self, e.node.*, referenced),
                    .format_expr => |fe| try collectReferencedVarsInNode(self, fe.expr.*, referenced),
                    .conv_expr => |ce| try collectReferencedVarsInNode(self, ce.expr.*, referenced),
                    .literal => {},
                }
            }
        },
        .listcomp => |lc| {
            try collectReferencedVarsInNode(self, lc.elt.*, referenced);
            for (lc.generators) |gen| {
                try collectReferencedVarsInNode(self, gen.iter.*, referenced);
                for (gen.ifs) |cond| {
                    try collectReferencedVarsInNode(self, cond, referenced);
                }
            }
        },
        .dictcomp => |dc| {
            try collectReferencedVarsInNode(self, dc.key.*, referenced);
            try collectReferencedVarsInNode(self, dc.value.*, referenced);
            for (dc.generators) |gen| {
                try collectReferencedVarsInNode(self, gen.iter.*, referenced);
                for (gen.ifs) |cond| {
                    try collectReferencedVarsInNode(self, cond, referenced);
                }
            }
        },
        .genexp => |ge| {
            try collectReferencedVarsInNode(self, ge.elt.*, referenced);
            for (ge.generators) |gen| {
                try collectReferencedVarsInNode(self, gen.iter.*, referenced);
                for (gen.ifs) |cond| {
                    try collectReferencedVarsInNode(self, cond, referenced);
                }
            }
        },
        .lambda => |lam| {
            try collectReferencedVarsInNode(self, lam.body.*, referenced);
        },
        .starred => |s| {
            try collectReferencedVarsInNode(self, s.value.*, referenced);
        },
        // Statement-level nodes
        .expr_stmt => |e| {
            try collectReferencedVarsInNode(self, e.value.*, referenced);
        },
        .if_stmt => |i| {
            try collectReferencedVarsInNode(self, i.condition.*, referenced);
            try collectReferencedVars(self, i.body, referenced);
            try collectReferencedVars(self, i.else_body, referenced);
        },
        .for_stmt => |f| {
            try collectReferencedVarsInNode(self, f.iter.*, referenced);
            try collectReferencedVars(self, f.body, referenced);
            if (f.orelse_body) |ob| {
                try collectReferencedVars(self, ob, referenced);
            }
        },
        .while_stmt => |w| {
            try collectReferencedVarsInNode(self, w.condition.*, referenced);
            try collectReferencedVars(self, w.body, referenced);
            if (w.orelse_body) |ob| {
                try collectReferencedVars(self, ob, referenced);
            }
        },
        .try_stmt => |t| {
            try collectReferencedVars(self, t.body, referenced);
            for (t.handlers) |h| {
                try collectReferencedVars(self, h.body, referenced);
            }
            try collectReferencedVars(self, t.else_body, referenced);
            try collectReferencedVars(self, t.finalbody, referenced);
        },
        .with_stmt => |w| {
            try collectReferencedVarsInNode(self, w.context_expr.*, referenced);
            try collectReferencedVars(self, w.body, referenced);
        },
        .raise_stmt => |r| {
            if (r.exc) |exc| try collectReferencedVarsInNode(self, exc.*, referenced);
            if (r.cause) |cause| try collectReferencedVarsInNode(self, cause.*, referenced);
        },
        .match_stmt => |m| {
            try collectReferencedVarsInNode(self, m.subject.*, referenced);
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    try collectReferencedVarsInNode(self, guard.*, referenced);
                }
                try collectReferencedVars(self, case.body, referenced);
            }
        },
        // IMPORTANT: Nested function definitions need special handling.
        // If a nested function references a variable from outside its own scope,
        // that variable needs to be captured by the CURRENT function too.
        // For example:
        //   def outer(x):
        //       def inner():
        //           return x  # x is referenced by inner, but outer needs to capture x too
        //       return inner
        .function_def => |f| {
            // Collect all variables referenced in the nested function body
            var nested_refs = std.ArrayList([]const u8){};
            defer nested_refs.deinit(self.allocator);
            try collectReferencedVars(self, f.body, &nested_refs);

            // Filter out the nested function's own parameters - they shadow outer scope
            for (nested_refs.items) |ref_name| {
                var is_nested_param = false;
                for (f.args) |arg| {
                    if (std.mem.eql(u8, arg.name, ref_name)) {
                        is_nested_param = true;
                        break;
                    }
                }
                // Skip if it's a parameter of the nested function
                if (is_nested_param) continue;

                // Also check vararg and kwarg
                if (f.vararg) |varg| {
                    if (std.mem.eql(u8, varg, ref_name)) continue;
                }
                if (f.kwarg) |kwarg| {
                    if (std.mem.eql(u8, kwarg, ref_name)) continue;
                }

                // Check if this var is locally assigned in the nested function (shadows)
                var locally_assigned_in_nested = std.ArrayList([]const u8){};
                defer locally_assigned_in_nested.deinit(self.allocator);
                collectLocallyAssignedVars(self.allocator, f.body, &locally_assigned_in_nested) catch {};
                var is_local_in_nested = false;
                for (locally_assigned_in_nested.items) |local_var| {
                    if (std.mem.eql(u8, local_var, ref_name)) {
                        is_local_in_nested = true;
                        break;
                    }
                }
                if (is_local_in_nested) continue;

                // This variable is referenced by nested function but not local to it
                // So the current function needs to pass it through
                try referenced.append(self.allocator, ref_name);
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
            if (w.orelse_body) |ob| if (canProduceErrors(ob)) break :blk true;
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
        .match_stmt => |m| blk: {
            if (canProduceErrorsInNode(m.subject.*)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    if (canProduceErrorsInNode(guard.*)) break :blk true;
                }
                if (canProduceErrors(case.body)) break :blk true;
            }
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
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                if (hasReturnWithValue(case.body)) break :blk true;
            }
            break :blk false;
        },
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
                if (arg == .starred) {
                    try collectUsedNamesFromNode(arg.starred.value.*, uses);
                } else if (arg == .double_starred) {
                    try collectUsedNamesFromNode(arg.double_starred.value.*, uses);
                } else {
                    try collectUsedNamesFromNode(arg, uses);
                }
            }
            for (c.keyword_args) |kw| {
                try collectUsedNamesFromNode(kw.value, uses);
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
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| try collectUsedNamesFromNode(e.node.*, uses),
                    .format_expr => |fe| try collectUsedNamesFromNode(fe.expr.*, uses),
                    .conv_expr => |ce| try collectUsedNamesFromNode(ce.expr.*, uses),
                    .literal => {},
                }
            }
        },
        .listcomp => |lc| {
            try collectUsedNamesFromNode(lc.elt.*, uses);
            for (lc.generators) |gen| {
                try collectUsedNamesFromNode(gen.iter.*, uses);
                for (gen.ifs) |cond| {
                    try collectUsedNamesFromNode(cond, uses);
                }
            }
        },
        .dictcomp => |dc| {
            try collectUsedNamesFromNode(dc.key.*, uses);
            try collectUsedNamesFromNode(dc.value.*, uses);
            for (dc.generators) |gen| {
                try collectUsedNamesFromNode(gen.iter.*, uses);
                for (gen.ifs) |cond| {
                    try collectUsedNamesFromNode(cond, uses);
                }
            }
        },
        .genexp => |ge| {
            try collectUsedNamesFromNode(ge.elt.*, uses);
            for (ge.generators) |gen| {
                try collectUsedNamesFromNode(gen.iter.*, uses);
                for (gen.ifs) |cond| {
                    try collectUsedNamesFromNode(cond, uses);
                }
            }
        },
        .lambda => |lam| {
            try collectUsedNamesFromNode(lam.body.*, uses);
        },
        .try_stmt => |t| {
            try collectUsedNames(t.body, uses);
            for (t.handlers) |h| {
                try collectUsedNames(h.body, uses);
            }
            try collectUsedNames(t.else_body, uses);
            try collectUsedNames(t.finalbody, uses);
        },
        .with_stmt => |w| {
            try collectUsedNamesFromNode(w.context_expr.*, uses);
            try collectUsedNames(w.body, uses);
        },
        .raise_stmt => |r| {
            if (r.exc) |exc| try collectUsedNamesFromNode(exc.*, uses);
            if (r.cause) |cause| try collectUsedNamesFromNode(cause.*, uses);
        },
        .starred => |s| {
            try collectUsedNamesFromNode(s.value.*, uses);
        },
        .match_stmt => |m| {
            try collectUsedNamesFromNode(m.subject.*, uses);
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    try collectUsedNamesFromNode(guard.*, uses);
                }
                try collectUsedNames(case.body, uses);
            }
        },
        else => {
            // Other node types don't contain name references we need to track
        },
    }
}
