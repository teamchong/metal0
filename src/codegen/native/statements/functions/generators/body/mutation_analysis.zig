/// Mutation analysis for function/method bodies
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

/// Check if a method mutates self (assigns to self.field or self.field[key])
/// Also returns true if method returns self (needed for nested classes where returning self
/// requires mutable pointer since return type is *@This() not *const @This())
pub fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
    for (method.body) |stmt| {
        if (stmtMutatesSelf(stmt)) return true;
        // Check if method returns self - this requires mutable self for nested classes
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .name and std.mem.eql(u8, val.name.id, "self")) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if a statement mutates self (recursively)
fn stmtMutatesSelf(stmt: ast.Node) bool {
    switch (stmt) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (targetMutatesSelf(target)) return true;
            }
        },
        .aug_assign => |aug| {
            // Augmented assignment (+=, -=, etc.) to self.field
            if (targetMutatesSelf(aug.target.*)) return true;
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
            for (if_stmt.else_body) |else_stmt| {
                if (stmtMutatesSelf(else_stmt)) return true;
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    if (stmtMutatesSelf(body_stmt)) return true;
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
            for (try_stmt.finalbody) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |body_stmt| {
                if (stmtMutatesSelf(body_stmt)) return true;
            }
        },
        else => {},
    }
    return false;
}

/// Check if a target (LHS of assignment) mutates self
fn targetMutatesSelf(target: ast.Node) bool {
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
    return false;
}

/// Check if an AST node references a type attribute (e.g., self.int_class where int_class is a type attribute)
pub fn usesTypeAttribute(node: ast.Node, class_name: []const u8, class_type_attrs: anytype) bool {
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
pub fn usesRegularSelf(node: ast.Node, class_name: []const u8, class_type_attrs: anytype) bool {
    const self_analyzer = @import("../../self_analyzer.zig");

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

/// Analyze function body for mutated variables (variables assigned more than once in same scope)
///
/// Key insight: In Zig, each loop iteration creates a fresh block scope.
/// A variable declared inside a loop is NEW each iteration, so it should use `const`
/// unless it's mutated WITHIN THE SAME ITERATION (aug_assign or multiple assigns).
///
/// We track:
/// 1. aug_assign_vars: Variables with += -= etc. - ALWAYS need var
/// 2. Scope-aware assignment counts: Only count as "mutated" if assigned multiple times
///    at the SAME scope level (not across loop iterations)
pub fn analyzeFunctionLocalMutations(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Track variables that have aug_assign (+=, -=, etc.) - these always need var
    var aug_assign_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer aug_assign_vars.deinit();

    // Track assignment counts with scope awareness
    // Key: "varname:scope_depth", Value: count at that scope
    var scoped_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer scoped_counts.deinit();

    // Collect aug_assign vars and scoped assignment counts
    for (func.body) |stmt| {
        try countAssignmentsWithScope(&aug_assign_vars, &scoped_counts, stmt, 0, self.allocator);
    }

    // Mark aug_assign variables as mutated (with scope 0 - function level)
    // aug_assign means mutation regardless of scope
    // Also track separately for shadow variable detection
    var aug_iter = aug_assign_vars.iterator();
    while (aug_iter.next()) |entry| {
        try self.func_local_mutations.put(entry.key_ptr.*, {});
        try self.func_local_aug_assigns.put(entry.key_ptr.*, {});
    }

    // Mark variables with multiple assignments at same scope as mutated
    // Store the full scoped key so codegen can query by scope
    var scope_iter = scoped_counts.iterator();
    while (scope_iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            // Extract variable name from "varname:scope_id" key
            const key = entry.key_ptr.*;
            if (std.mem.lastIndexOf(u8, key, ":")) |colon_idx| {
                const var_name = key[0..colon_idx];
                // Mark the base variable name as mutated (for function-scope queries)
                try self.func_local_mutations.put(var_name, {});
                // Also store the scoped key for scope-aware queries
                try self.func_local_mutations.put(try self.allocator.dupe(u8, key), {});
            }
        }
    }
}

/// Analyze module-level code for mutated variables (for script mode main function)
/// This is similar to analyzeFunctionLocalMutations but works on module body
pub fn analyzeModuleLevelMutations(self: *NativeCodegen, module_body: []const ast.Node) !void {
    // Track variables that have aug_assign (+=, -=, etc.) - these always need var
    var aug_assign_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer aug_assign_vars.deinit();

    // Track assignment counts with scope awareness
    // Key: "varname:scope_depth", Value: count at that scope
    var scoped_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer scoped_counts.deinit();

    // Collect aug_assign vars and scoped assignment counts for module-level statements
    // Skip function_def, class_def, import_stmt, import_from (not executed in main)
    for (module_body) |stmt| {
        if (stmt != .function_def and stmt != .class_def and stmt != .import_stmt and stmt != .import_from) {
            try countAssignmentsWithScope(&aug_assign_vars, &scoped_counts, stmt, 0, self.allocator);
        }
    }

    // Mark aug_assign variables as mutated (with scope 0 - module level)
    // aug_assign means mutation regardless of scope
    var aug_iter = aug_assign_vars.iterator();
    while (aug_iter.next()) |entry| {
        try self.func_local_mutations.put(entry.key_ptr.*, {});
        try self.func_local_aug_assigns.put(entry.key_ptr.*, {});
    }

    // Mark variables with multiple assignments at same scope as mutated
    // Store the full scoped key so codegen can query by scope
    var scope_iter = scoped_counts.iterator();
    while (scope_iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            // Extract variable name from "varname:scope_id" key
            const key = entry.key_ptr.*;
            if (std.mem.lastIndexOf(u8, key, ":")) |colon_idx| {
                const var_name = key[0..colon_idx];
                // Mark the base variable name as mutated (for module-scope queries)
                try self.func_local_mutations.put(var_name, {});
                // Also store the scoped key for scope-aware queries
                try self.func_local_mutations.put(try self.allocator.dupe(u8, key), {});
            }
        }
    }
}

/// Count assignments with scope awareness
/// scope_id: unique identifier for each scope (using pointer address of the AST node)
/// parent_scope_id: the containing scope (for detecting cross-scope mutations)
pub fn countAssignmentsWithScope(
    aug_vars: *hashmap_helper.StringHashMap(void),
    scoped_counts: *hashmap_helper.StringHashMap(usize),
    stmt: ast.Node,
    scope_id: usize,
    allocator: std.mem.Allocator,
) !void {
    switch (stmt) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (target == .name) {
                    const name = target.name.id;
                    // Create scoped key: "varname:scope_id"
                    // Each unique scope (different loop) gets different ID
                    const scoped_key = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ name, scope_id });
                    defer allocator.free(scoped_key);
                    const current = scoped_counts.get(scoped_key) orelse 0;
                    try scoped_counts.put(try allocator.dupe(u8, scoped_key), current + 1);
                    // NOTE: We do NOT propagate nested scope assignments to function scope.
                    // In Python, `x = 1` inside a loop and `x = 2` outside share the same variable.
                    // But in generated Zig, each block scope creates a NEW variable declaration.
                    // So `const x = ...` inside loop and `const x = ...` outside are DIFFERENT vars.
                    // Cross-scope assignments are NOT mutations in Zig - they're fresh declarations.
                } else if (target == .subscript) {
                    // Subscript assignment: x[0] = value mutates x
                    const subscript = target.subscript;
                    if (subscript.value.* == .name) {
                        const name = subscript.value.name.id;
                        try aug_vars.put(name, {}); // subscript assign is mutation
                    }
                }
            }
        },
        .aug_assign => |aug| {
            // Augmented assignment (+=, -=, etc.) ALWAYS means mutation
            if (aug.target.* == .name) {
                try aug_vars.put(aug.target.name.id, {});
            } else if (aug.target.* == .subscript) {
                const subscript = aug.target.subscript;
                if (subscript.value.* == .name) {
                    try aug_vars.put(subscript.value.name.id, {});
                }
            }
        },
        .if_stmt => |if_stmt| {
            // if/else bodies are same scope level as containing block
            for (if_stmt.body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
            }
            for (if_stmt.else_body) |else_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, else_stmt, scope_id, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            // Loop body is a NEW scope - use pointer address as unique scope ID
            const new_scope_id = @intFromPtr(while_stmt.body.ptr);
            for (while_stmt.body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, new_scope_id, allocator);
            }
        },
        .for_stmt => |for_stmt| {
            // Loop variable itself is mutated (assigned each iteration in outer scope)
            if (for_stmt.target.* == .name) {
                try aug_vars.put(for_stmt.target.name.id, {});
            }
            // Loop body is a NEW scope - use pointer address as unique scope ID
            const new_scope_id = @intFromPtr(for_stmt.body.ptr);
            for (for_stmt.body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, new_scope_id, allocator);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
            }
            for (try_stmt.finalbody) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
            }
        },
        .with_stmt => |with_stmt| {
            for (with_stmt.body) |body_stmt| {
                try countAssignmentsWithScope(aug_vars, scoped_counts, body_stmt, scope_id, allocator);
            }
        },
        else => {},
    }
}
