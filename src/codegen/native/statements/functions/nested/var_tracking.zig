/// Variable tracking for closures - finding captured vars, analyzing usage patterns
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

/// Find variables captured from outer scope by nested function
pub fn findCapturedVars(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
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
    collectLocallyAssignedVars(func.body, &locally_assigned) catch {};

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

        // Check if variable is in outer scope
        if (self.symbol_table.lookup(var_name) != null) {
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
fn collectLocallyAssignedVars(stmts: []ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    for (stmts) |stmt| {
        try collectLocallyAssignedVarsInNode(stmt, assigned);
    }
}

fn collectLocallyAssignedVarsInNode(node: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    switch (node) {
        .assign => |a| {
            for (a.targets) |target| {
                try collectAssignTargetVars(target, assigned);
            }
        },
        .aug_assign => |a| {
            try collectAssignTargetVars(a.target.*, assigned);
        },
        .for_stmt => |f| {
            // for loop target is a local variable
            try collectAssignTargetVars(f.target.*, assigned);
            for (f.body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
            for (i.else_body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
        },
        .while_stmt => |w| {
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
            for (t.handlers) |h| {
                // Exception variable is local
                if (h.name) |name| {
                    try addUniqueVar(assigned, name);
                }
                for (h.body) |s| {
                    try collectLocallyAssignedVarsInNode(s, assigned);
                }
            }
            for (t.else_body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
            for (t.finalbody) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
        },
        .with_stmt => |w| {
            // with ... as var: introduces local var
            if (w.optional_var) |var_node| {
                try collectAssignTargetVars(var_node.*, assigned);
            }
            for (w.body) |s| {
                try collectLocallyAssignedVarsInNode(s, assigned);
            }
        },
        else => {},
    }
}

fn collectAssignTargetVars(target: ast.Node, assigned: *std.ArrayList([]const u8)) !void {
    switch (target) {
        .name => |n| {
            try addUniqueVar(assigned, n.id);
        },
        .tuple => |t| {
            for (t.elements) |elem| {
                try collectAssignTargetVars(elem, assigned);
            }
        },
        .list => |l| {
            for (l.elements) |elem| {
                try collectAssignTargetVars(elem, assigned);
            }
        },
        else => {},
    }
}

fn addUniqueVar(list: *std.ArrayList([]const u8), name: []const u8) !void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, name)) return;
    }
    try list.append(list.allocator, name);
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
                if (isParamUsedInNode(param_name, arg)) break :blk true;
            }
            for (c.keyword_args) |kw| {
                if (isParamUsedInNode(param_name, kw.value)) break :blk true;
            }
            break :blk false;
        },
        .return_stmt => |ret| if (ret.value) |val| isParamUsedInNode(param_name, val.*) else false,
        .assign => |assign| isParamUsedInNode(param_name, assign.value.*),
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
        .boolop => |bo| blk: {
            for (bo.values) |v| {
                if (isParamUsedInNode(param_name, v)) break :blk true;
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
