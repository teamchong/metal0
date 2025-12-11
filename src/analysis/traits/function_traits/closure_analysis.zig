/// Closure return type analysis - Infer proper return types for nested functions
/// Common patterns: returns context manager, self method, literal, or nothing
const std = @import("std");
const ast = @import("analysis.ast");
const method_dispatch = @import("method_dispatch.zig");

/// Closure return type categories
pub const ClosureReturnType = enum {
    void, // No return or return without value
    context_manager, // Returns a context manager (for with statements)
    integer, // Returns int literal or int expression
    float, // Returns float
    string, // Returns string
    boolean, // Returns bool
    list, // Returns list
    dict, // Returns dict
    tuple, // Returns tuple
    callable, // Returns another function/lambda
    self_type, // Returns self (for method chaining)
    unknown, // Can't determine - use anytype or PyValue
};

/// Analyze a nested function's return type from its AST
/// Returns the inferred return type category
pub fn analyzeClosureReturnType(func_body: []const ast.Node) ClosureReturnType {
    // First pass: collect variable types from assignments
    var var_types: [32]VarTypeEntry = undefined;
    var var_count: usize = 0;
    collectVarTypes(func_body, &var_types, &var_count);

    // Second pass: find return statements and infer type
    for (func_body) |stmt| {
        if (stmt == .return_stmt) {
            const ret = stmt.return_stmt;
            if (ret.value) |val_ptr| {
                return inferExprReturnTypeWithVars(val_ptr.*, var_types[0..var_count]);
            } else {
                return .void;
            }
        }
    }
    // No explicit return found
    return .void;
}

/// Entry for tracking variable types
const VarTypeEntry = struct {
    name: []const u8,
    var_type: ClosureReturnType,
};

/// Collect variable types from assignments in function body
fn collectVarTypes(body: []const ast.Node, var_types: *[32]VarTypeEntry, count: *usize) void {
    for (body) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Get the assigned value type
                const value_type = inferExprReturnType(assign.value.*);
                // Track all target variables
                for (assign.targets) |target| {
                    if (target == .name) {
                        const name = target.name.id;
                        if (count.* < 32) {
                            var_types[count.*] = .{ .name = name, .var_type = value_type };
                            count.* += 1;
                        }
                    }
                }
            },
            .aug_assign => |aug| {
                // Augmented assignment (+=, -= etc) preserves or promotes type
                // For now, assume it keeps the type based on the operand
                const value_type = inferExprReturnType(aug.value.*);
                if (aug.target.* == .name) {
                    const name = aug.target.name.id;
                    // Update existing or add new
                    for (var_types[0..count.*]) |*entry| {
                        if (std.mem.eql(u8, entry.name, name)) {
                            // Keep existing type or promote to unknown if different
                            if (entry.var_type != value_type and value_type != .unknown) {
                                entry.var_type = .unknown;
                            }
                            return;
                        }
                    }
                    // Add new entry
                    if (count.* < 32) {
                        var_types[count.*] = .{ .name = name, .var_type = value_type };
                        count.* += 1;
                    }
                }
            },
            .for_stmt => |for_stmt| {
                // Recurse into for body
                collectVarTypes(for_stmt.body, var_types, count);
                if (for_stmt.orelse_body) |orelse_body| {
                    collectVarTypes(orelse_body, var_types, count);
                }
            },
            .while_stmt => |while_stmt| {
                collectVarTypes(while_stmt.body, var_types, count);
                if (while_stmt.orelse_body) |orelse_body| {
                    collectVarTypes(orelse_body, var_types, count);
                }
            },
            .if_stmt => |if_stmt| {
                collectVarTypes(if_stmt.body, var_types, count);
                collectVarTypes(if_stmt.else_body, var_types, count);
            },
            .try_stmt => |try_stmt| {
                collectVarTypes(try_stmt.body, var_types, count);
                collectVarTypes(try_stmt.else_body, var_types, count);
                collectVarTypes(try_stmt.finalbody, var_types, count);
            },
            .with_stmt => |with_stmt| {
                collectVarTypes(with_stmt.body, var_types, count);
            },
            else => {},
        }
    }
}

/// Infer return type with variable type lookup
fn inferExprReturnTypeWithVars(expr: ast.Node, var_types: []const VarTypeEntry) ClosureReturnType {
    return switch (expr) {
        .name => |n| {
            if (std.mem.eql(u8, n.id, "self")) return .self_type;
            if (std.mem.eql(u8, n.id, "True") or std.mem.eql(u8, n.id, "False")) return .boolean;
            if (std.mem.eql(u8, n.id, "None")) return .void;
            // Look up variable type
            for (var_types) |entry| {
                if (std.mem.eql(u8, entry.name, n.id)) {
                    return entry.var_type;
                }
            }
            return .unknown;
        },
        else => inferExprReturnType(expr),
    };
}

/// Infer return type from an expression
fn inferExprReturnType(expr: ast.Node) ClosureReturnType {
    return switch (expr) {
        .constant => |c| switch (c.value) {
            .int => .integer,
            .float => .float,
            .string => .string,
            .bool => .boolean,
            .none => .void,
            else => .unknown,
        },
        .list => .list,
        .dict => .dict,
        .tuple => .tuple,
        .set => .unknown, // Set type
        .name => |n| {
            if (std.mem.eql(u8, n.id, "self")) return .self_type;
            if (std.mem.eql(u8, n.id, "True") or std.mem.eql(u8, n.id, "False")) return .boolean;
            if (std.mem.eql(u8, n.id, "None")) return .void;
            return .unknown;
        },
        .call => |call| {
            // Check if calling a known context manager method
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (method_dispatch.ContextManagerMethods.has(attr.attr)) {
                    return .context_manager;
                }
            }
            // Check if calling a known context manager function
            if (call.func.* == .name) {
                if (method_dispatch.ContextManagerMethods.has(call.func.name.id)) {
                    return .context_manager;
                }
            }
            return .unknown;
        },
        .lambda => .callable,
        .binop => |op| {
            // Arithmetic ops typically return numeric
            return switch (op.op) {
                .Add, .Sub, .Mult, .Div, .FloorDiv, .Mod, .Pow => .unknown, // Could be int or float
                .BitOr, .BitXor, .BitAnd, .LShift, .RShift => .integer,
                else => .unknown,
            };
        },
        .compare => .boolean,
        .boolop => .boolean,
        .unaryop => |op| {
            if (op.op == .Not) return .boolean;
            return .unknown;
        },
        else => .unknown,
    };
}

/// Get the Zig type string for a closure return type
/// NOTE: anytype cannot be used as return type in Zig - use concrete types or PyValue
pub fn closureReturnTypeToZig(ret_type: ClosureReturnType) []const u8 {
    return switch (ret_type) {
        .void => "void",
        .context_manager => "runtime.PyValue", // Context managers resolved separately
        .integer => "i64",
        .float => "f64",
        .string => "[]const u8",
        .boolean => "bool",
        .list => "runtime.PyValue", // List element type varies
        .dict => "runtime.PyValue", // Dict key/value types vary
        .tuple => "runtime.PyValue", // Tuple field types vary
        .callable => "runtime.PyValue", // Function types vary
        .self_type => "runtime.PyValue", // Self type varies by class
        .unknown => "runtime.PyValue", // Fallback to dynamic type
    };
}
