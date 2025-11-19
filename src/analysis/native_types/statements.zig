const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

/// Visit and analyze statement nodes to infer variable types
pub fn visitStmt(
    allocator: std.mem.Allocator,
    var_types: *std.StringHashMap(NativeType),
    class_fields: *std.StringHashMap(ClassInfo),
    inferExprFn: *const fn (allocator: std.mem.Allocator, var_types: *std.StringHashMap(NativeType), class_fields: *std.StringHashMap(ClassInfo), node: ast.Node) InferError!NativeType,
    node: ast.Node,
) InferError!void {
    switch (node) {
        .assign => |assign| {
            const value_type = try inferExprFn(allocator, var_types, class_fields, assign.value.*);
            for (assign.targets) |target| {
                if (target == .name) {
                    try var_types.put(target.name.id, value_type);
                }
            }
        },
        .class_def => |class_def| {
            // Track class field types from __init__ parameters
            var fields = std.StringHashMap(NativeType).init(allocator);

            // Find __init__ method
            for (class_def.body) |stmt| {
                if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__")) {
                    const init_fn = stmt.function_def;

                    // Extract field types from __init__ parameters
                    for (init_fn.body) |init_stmt| {
                        if (init_stmt == .assign) {
                            const assign = init_stmt.assign;
                            // Check if target is self.attribute
                            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                                const attr = assign.targets[0].attribute;
                                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                                    const field_name = attr.attr;

                                    // Determine field type from parameter type annotation
                                    if (assign.value.* == .name) {
                                        const value_name = assign.value.name.id;
                                        for (init_fn.args) |arg| {
                                            if (std.mem.eql(u8, arg.name, value_name)) {
                                                const field_type = try core.pythonTypeHintToNative(arg.type_annotation, allocator);
                                                try fields.put(field_name, field_type);
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    break;
                }
            }

            try class_fields.put(class_def.name, .{ .fields = fields });
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| try visitStmt(allocator, var_types, class_fields, inferExprFn, s);
            for (if_stmt.else_body) |s| try visitStmt(allocator, var_types, class_fields, inferExprFn, s);
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| try visitStmt(allocator, var_types, class_fields, inferExprFn, s);
        },
        .for_stmt => |for_stmt| {
            // Register loop variables before visiting body
            // This enables proper type inference for print statements inside loops
            if (for_stmt.target.* == .list) {
                // Multiple loop vars: for i, item in enumerate(items)
                // Parser uses .list for tuple unpacking
                const targets = for_stmt.target.list.elts;

                // Check for enumerate() pattern
                if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
                    const func_name = for_stmt.iter.call.func.name.id;

                    if (std.mem.eql(u8, func_name, "enumerate") and targets.len >= 2) {
                        // First var is always usize (index for array access)
                        if (targets[0] == .name) {
                            try var_types.put(targets[0].name.id, .usize);
                        }
                        // Second var type comes from the list being enumerated
                        if (targets[1] == .name and for_stmt.iter.call.args.len > 0) {
                            const arg = for_stmt.iter.call.args[0];
                            // Only handle simple cases to avoid side effects
                            if (arg == .name) {
                                    // Get type from variable
                                const list_type = var_types.get(arg.name.id) orelse .unknown;
                                const elem_type = switch (list_type) {
                                    .list => |l| l.*,
                                    .array => |a| a.element_type.*,
                                    else => .unknown,
                                };
                                try var_types.put(targets[1].name.id, elem_type);
                            } else if (arg == .list and arg.list.elts.len > 0) {
                                // Infer from first list element
                                const first_elem = arg.list.elts[0];
                                const elem_type = if (first_elem == .constant)
                                    inferConstant(first_elem.constant.value) catch .unknown
                                else .unknown;
                                try var_types.put(targets[1].name.id, elem_type);
                            }
                        }
                    } else if (std.mem.eql(u8, func_name, "zip")) {
                        // zip(list1, list2, ...) - infer from each list
                        for (for_stmt.iter.call.args, 0..) |arg, i| {
                            if (i < targets.len and targets[i] == .name) {
                                if (arg == .name) {
                                    const list_type = var_types.get(arg.name.id) orelse .unknown;
                                    const elem_type = switch (list_type) {
                                        .list => |l| l.*,
                                        .array => |a| a.element_type.*,
                                        else => .unknown,
                                    };
                                    try var_types.put(targets[i].name.id, elem_type);
                                }
                            }
                        }
                    }
                } else if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
                    // Generic tuple unpacking from method calls like dict.items()
                    // for k, v in dict.items(): ...
                    const iter_type = inferExprFn(allocator, var_types, class_fields, for_stmt.iter.*) catch .unknown;

                    // If method returns a list of tuples, unpack the tuple element types
                    if (iter_type == .list) {
                        const elem_type = iter_type.list.*;
                        if (elem_type == .tuple) {
                            // Unpack tuple element types to target variables
                            const tuple_types = elem_type.tuple;
                            for (targets, 0..) |target, i| {
                                if (target == .name and i < tuple_types.len) {
                                    try var_types.put(target.name.id, tuple_types[i]);
                                }
                            }
                        }
                    }
                }
            } else if (for_stmt.target.* == .name) {
                // Single loop var: for item in items or for i in range(...)
                const target_name = for_stmt.target.name.id;

                // Check for range() pattern - indices should be usize
                if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
                    const func_name = for_stmt.iter.call.func.name.id;
                    if (std.mem.eql(u8, func_name, "range")) {
                        // range() produces indices → type as usize
                        try var_types.put(target_name, .usize);
                    }
                } else if (for_stmt.iter.* == .name) {
                    const iter_type = var_types.get(for_stmt.iter.name.id) orelse .unknown;
                    const elem_type = switch (iter_type) {
                        .list => |l| l.*,
                        .array => |a| a.element_type.*,
                        else => .unknown,
                    };
                    try var_types.put(target_name, elem_type);
                }
            }

            for (for_stmt.body) |s| try visitStmt(allocator, var_types, class_fields, inferExprFn, s);
        },
        .function_def => |func_def| {
            // Register function parameter types from type annotations
            for (func_def.args) |arg| {
                const param_type = try core.pythonTypeHintToNative(arg.type_annotation, allocator);
                try var_types.put(arg.name, param_type);
            }
            // Visit function body
            for (func_def.body) |s| try visitStmt(allocator, var_types, class_fields, inferExprFn, s);
        },
        else => {},
    }
}

/// Infer type from constant literal
fn inferConstant(value: ast.Value) InferError!NativeType {
    return switch (value) {
        .int => .int,
        .float => .float,
        .string => .{ .string = .literal }, // String literals are compile-time constants
        .bool => .bool,
    };
}
