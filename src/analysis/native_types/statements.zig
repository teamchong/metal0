const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const hashmap_helper = @import("hashmap_helper");
const inferrer_mod = @import("inferrer.zig");
const TypeInferrer = inferrer_mod.TypeInferrer;

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);
const FnvArgsMap = hashmap_helper.StringHashMap([]const NativeType);

/// Visit and analyze statement nodes to infer variable types
/// Uses function-scoped variable tracking to prevent cross-function type pollution
pub fn visitStmt(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    class_constructor_args: *FnvArgsMap,
    inferExprFn: *const fn (allocator: std.mem.Allocator, var_types: *FnvHashMap, class_fields: *FnvClassMap, func_return_types: *FnvHashMap, node: ast.Node) InferError!NativeType,
    node: ast.Node,
) InferError!void {
    // Call the scoped version with null inferrer (legacy mode - uses global var_types)
    return visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, node, null);
}

/// Visit statement with optional TypeInferrer for scoped variable tracking
pub fn visitStmtScoped(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    class_constructor_args: *FnvArgsMap,
    inferExprFn: *const fn (allocator: std.mem.Allocator, var_types: *FnvHashMap, class_fields: *FnvClassMap, func_return_types: *FnvHashMap, node: ast.Node) InferError!NativeType,
    node: ast.Node,
    type_inferrer: ?*inferrer_mod.TypeInferrer,
) InferError!void {
    switch (node) {
        .assign => |assign| {
            const value_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, assign.value.*);
            for (assign.targets) |target| {
                if (target == .name) {
                    const var_name = target.name.id;

                    // Use scoped variable tracking if available
                    if (type_inferrer) |ti| {
                        // Check if variable exists in CURRENT scope
                        if (ti.getScopedVar(var_name)) |_| {
                            // Widen type in current scope
                            try ti.widenScopedVar(var_name, value_type);
                        } else {
                            // First assignment in this scope
                            try ti.putScopedVar(var_name, value_type);
                        }
                    } else {
                        // Legacy mode: use global var_types with widening
                        if (var_types.get(var_name)) |existing_type| {
                            if (existing_type == .unknown and value_type != .unknown) {
                                try var_types.put(var_name, value_type);
                            } else if (existing_type != .unknown and value_type == .unknown) {
                                // Keep existing specific type over unknown
                            } else {
                                const widened = existing_type.widen(value_type);
                                try var_types.put(var_name, widened);
                            }
                        } else {
                            try var_types.put(var_name, value_type);
                        }
                    }
                }
            }
        },
        .ann_assign => |ann_assign| {
            var var_type: NativeType = .unknown;

            // 1. Parse annotation if provided (PRIORITY)
            const annot_node = ann_assign.annotation.*;
            var_type = try core.parseTypeAnnotation(annot_node, allocator);

            // 2. Fall back to value inference
            if (var_type == .unknown and ann_assign.value != null) {
                var_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, ann_assign.value.?.*);
            }

            // 3. Store type
            if (ann_assign.target.* == .name) {
                try var_types.put(ann_assign.target.name.id, var_type);
            }
        },
        .class_def => |class_def| {
            // Track class field types from __init__ parameters
            var fields = FnvHashMap.init(allocator);
            var methods = FnvHashMap.init(allocator);
            var property_methods = FnvHashMap.init(allocator);
            const hm_helper = @import("hashmap_helper");
            var property_getters = hm_helper.StringHashMap([]const u8).init(allocator);

            // Get constructor arg types if available
            const constructor_arg_types = class_constructor_args.get(class_def.name);

            // Extract class-level attributes (before __init__ parsing)
            // These are assignments directly in the class body, not inside methods
            for (class_def.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .name) {
                        const field_name = assign.targets[0].name.id;

                        // Check if this is a property() assignment: num = property(_get_num, None)
                        if (assign.value.* == .call and assign.value.call.func.* == .name) {
                            if (std.mem.eql(u8, assign.value.call.func.name.id, "property")) {
                                // This is a property descriptor - register it as a property method
                                // The first argument is the getter function name
                                if (assign.value.call.args.len > 0 and assign.value.call.args[0] == .name) {
                                    const getter_name = assign.value.call.args[0].name.id;
                                    // Store the getter name for this property
                                    try property_getters.put(field_name, getter_name);
                                    // Find the getter method and use its return type
                                    for (class_def.body) |method_stmt| {
                                        if (method_stmt == .function_def and std.mem.eql(u8, method_stmt.function_def.name, getter_name)) {
                                            const getter = method_stmt.function_def;
                                            // Infer return type from getter
                                            var return_type: NativeType = .unknown;
                                            if (getter.return_type) |type_str| {
                                                return_type = try core.pythonTypeHintToNative(type_str, allocator);
                                            }
                                            if (return_type == .unknown) {
                                                for (getter.body) |body_stmt| {
                                                    if (body_stmt == .return_stmt and body_stmt.return_stmt.value != null) {
                                                        return_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, body_stmt.return_stmt.value.?.*);
                                                        break;
                                                    }
                                                }
                                            }
                                            try property_methods.put(field_name, return_type);
                                            break;
                                        }
                                    }
                                }
                                continue; // Don't add to fields
                            }
                        }

                        // Infer type from value
                        const field_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, assign.value.*);
                        try fields.put(field_name, field_type);
                    }
                }
            }

            // Extract field types from __init__ method
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

                                    // Determine field type from value
                                    var field_type: NativeType = .unknown;

                                    if (assign.value.* == .name) {
                                        // If assigning from a parameter, use type hint or constructor arg types
                                        const value_name = assign.value.name.id;
                                        for (init_fn.args, 0..) |arg, param_idx| {
                                            if (std.mem.eql(u8, arg.name, value_name)) {
                                                // Method 1: Use type annotation if available
                                                field_type = try core.pythonTypeHintToNative(arg.type_annotation, allocator);

                                                // Method 2: Try keyword arg lookup first (has proper type widening)
                                                // Stored as "ClassName.param_name" in var_types, widened across all calls
                                                var found_kwarg_type = false;
                                                if (field_type == .unknown) {
                                                    var kwarg_key_buf: [256]u8 = undefined;
                                                    const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ class_def.name, arg.name }) catch null;
                                                    if (kwarg_key) |key| {
                                                        if (var_types.get(key)) |kwarg_type| {
                                                            field_type = kwarg_type;
                                                            found_kwarg_type = true;
                                                        }
                                                    }
                                                }

                                                // Method 3: If keyword lookup didn't find anything, use positional constructor call arg types
                                                // Note: Don't overwrite if Method 2 found .unknown (means widened incompatible types)
                                                if (!found_kwarg_type and field_type == .unknown) {
                                                    if (constructor_arg_types) |arg_types| {
                                                        // param_idx includes 'self', so subtract 1 for arg index
                                                        const arg_idx = if (param_idx > 0) param_idx - 1 else 0;
                                                        if (arg_idx < arg_types.len) {
                                                            field_type = arg_types[arg_idx];
                                                        }
                                                    }
                                                }
                                                break;
                                            }
                                        }
                                    } else if (assign.value.* == .constant) {
                                        // If assigning a constant, infer from literal
                                        field_type = try inferConstant(assign.value.constant.value);
                                    } else if (assign.value.* == .dict) {
                                        // Infer dict type
                                        field_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, assign.value.*);
                                    } else if (assign.value.* == .call) {
                                        // If assigning from a call, infer type (handles class constructors)
                                        field_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, assign.value.*);
                                    } else {
                                        // For all other expressions (binop, unaryop, etc.), use generic inference
                                        field_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, assign.value.*);
                                    }

                                    try fields.put(field_name, field_type);
                                }
                            }
                        }
                    }
                    break;
                }
            }

            // Register class fields early so self.field lookups work during method return type inference
            try class_fields.put(class_def.name, .{ .fields = fields, .methods = methods, .property_methods = property_methods, .property_getters = property_getters });

            // Register 'self' as class_instance so expressions like self.val can be inferred
            try var_types.put("self", .{ .class_instance = class_def.name });

            // Extract method return types from all methods
            for (class_def.body) |stmt| {
                if (stmt == .function_def) {
                    const method = stmt.function_def;
                    // Skip __init__ - it doesn't have a useful return type
                    if (std.mem.eql(u8, method.name, "__init__")) continue;

                    // Get return type from annotation first
                    var return_type = try core.pythonTypeHintToNative(method.return_type, allocator);

                    // If no annotation (unknown), infer from return statements
                    if (return_type == .unknown) {
                        for (method.body) |body_stmt| {
                            if (body_stmt == .return_stmt and body_stmt.return_stmt.value != null) {
                                return_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, body_stmt.return_stmt.value.?.*);
                                break;
                            }
                        }
                    }

                    try methods.put(method.name, return_type);

                    // Check for @property decorator
                    for (method.decorators) |decorator| {
                        if (decorator == .name and std.mem.eql(u8, decorator.name.id, "property")) {
                            try property_methods.put(method.name, return_type);
                            break;
                        }
                    }
                }
            }

            try class_fields.put(class_def.name, .{ .fields = fields, .methods = methods, .property_methods = property_methods, .property_getters = property_getters });

            // Visit method bodies to register local variable types
            // Each method gets its own named scope to prevent cross-method type pollution
            for (class_def.body) |stmt| {
                if (stmt == .function_def) {
                    const method = stmt.function_def;

                    // Create named scope: "ClassName.method_name"
                    var scope_name_buf: [256]u8 = undefined;
                    const scope_name = std.fmt.bufPrint(&scope_name_buf, "{s}.{s}", .{ class_def.name, method.name }) catch class_def.name;
                    const old_scope = if (type_inferrer) |ti| ti.enterScope(scope_name) else null;
                    defer if (type_inferrer) |ti| ti.exitScope(old_scope);

                    // Register method parameter types
                    for (method.args) |arg| {
                        // Register 'self' as a class instance type
                        if (std.mem.eql(u8, arg.name, "self")) {
                            if (type_inferrer) |ti| {
                                try ti.putScopedVar("self", .{ .class_instance = class_def.name });
                            } else {
                                try var_types.put("self", .{ .class_instance = class_def.name });
                            }
                        } else {
                            const param_type = try core.pythonTypeHintToNative(arg.type_annotation, allocator);
                            if (type_inferrer) |ti| {
                                try ti.putScopedVar(arg.name, param_type);
                            } else {
                                try var_types.put(arg.name, param_type);
                            }
                        }
                    }
                    // Visit method body statements with scoped tracking
                    for (method.body) |body_stmt| {
                        try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, body_stmt, type_inferrer);
                    }
                }
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
            for (if_stmt.else_body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
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
                                else
                                    .unknown;
                                try var_types.put(targets[1].name.id, elem_type);
                            }
                        }
                    } else if (std.mem.eql(u8, func_name, "zip")) {
                        // zip(list1, list2, ...) - infer from each list
                        for (for_stmt.iter.call.args, 0..) |arg, i| {
                            if (i < targets.len and targets[i] == .name) {
                                // Infer element type from the arg (could be name or list literal)
                                const arg_type = inferExprFn(allocator, var_types, class_fields, func_return_types, arg) catch .unknown;
                                const elem_type = switch (arg_type) {
                                    .list => |l| l.*,
                                    .array => |a| a.element_type.*,
                                    else => .unknown,
                                };
                                try var_types.put(targets[i].name.id, elem_type);
                            }
                        }
                    }
                } else if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
                    // Generic tuple unpacking from method calls like dict.items()
                    // for k, v in dict.items(): ...
                    const iter_type = inferExprFn(allocator, var_types, class_fields, func_return_types, for_stmt.iter.*) catch .unknown;

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
                } else if (for_stmt.iter.* == .list and for_stmt.iter.list.elts.len > 0) {
                    // Tuple unpacking from list literal: for f, ratio in [(0.875, (7, 8)), ...]
                    // Infer element types from first tuple in the list
                    const first_elem = for_stmt.iter.list.elts[0];
                    if (first_elem == .tuple and first_elem.tuple.elts.len >= targets.len) {
                        // Infer type of each target from corresponding tuple element
                        for (targets, 0..) |target, i| {
                            if (target == .name) {
                                const elem_type = inferExprFn(allocator, var_types, class_fields, func_return_types, first_elem.tuple.elts[i]) catch .unknown;
                                try var_types.put(target.name.id, elem_type);
                            }
                        }
                    }
                }
            } else if (for_stmt.target.* == .name) {
                // Single loop var: for item in items or for i in range(...)
                const target_name = for_stmt.target.name.id;

                // Helper to store var type - uses scoped storage if inside function, else global
                const putForVarType = struct {
                    fn put(vt: *FnvHashMap, ti: ?*TypeInferrer, name: []const u8, var_type: NativeType) !void {
                        if (ti) |inferrer| {
                            try inferrer.putScopedVar(name, var_type);
                        } else {
                            try vt.put(name, var_type);
                        }
                    }
                }.put;

                // Check for range() pattern - indices should be usize
                if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
                    const func_name = for_stmt.iter.call.func.name.id;
                    if (std.mem.eql(u8, func_name, "range")) {
                        // range() produces indices → type as usize
                        try putForVarType(var_types, type_inferrer, target_name, .usize);
                    }
                } else if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
                    // Handle method calls like dict.keys(), dict.values()
                    const method_name = for_stmt.iter.call.func.attribute.attr;
                    const obj = for_stmt.iter.call.func.attribute.value.*;

                    if (std.mem.eql(u8, method_name, "keys")) {
                        // dict.keys() always returns strings for StringHashMap
                        try putForVarType(var_types, type_inferrer, target_name, .{ .string = .runtime });
                    } else if (std.mem.eql(u8, method_name, "values")) {
                        // dict.values() - get value type from dict
                        if (obj == .name) {
                            const dict_type = var_types.get(obj.name.id) orelse .unknown;
                            if (dict_type == .dict) {
                                try putForVarType(var_types, type_inferrer, target_name, dict_type.dict.value.*);
                            }
                        }
                    } else {
                        // Generic method call - try to infer from return type
                        const iter_type = inferExprFn(allocator, var_types, class_fields, func_return_types, for_stmt.iter.*) catch .unknown;
                        const elem_type = switch (iter_type) {
                            .list => |l| l.*,
                            .array => |a| a.element_type.*,
                            .sqlite_rows => .sqlite_row, // []sqlite3.Row -> sqlite3.Row
                            else => .unknown,
                        };
                        try putForVarType(var_types, type_inferrer, target_name, elem_type);
                    }
                } else if (for_stmt.iter.* == .name) {
                    const iter_type = var_types.get(for_stmt.iter.name.id) orelse .unknown;
                    const elem_type = switch (iter_type) {
                        .list => |l| l.*,
                        .array => |a| a.element_type.*,
                        .sqlite_rows => .sqlite_row, // []sqlite3.Row -> sqlite3.Row
                        // If iterator is typed as .int (common when param has no annotation),
                        // it's likely actually a list of ints. Use .int for elements.
                        .int => |kind| NativeType{ .int = kind },
                        // Iterating over a tuple variable: widen all element types to get common type
                        .tuple => |tuple_types| blk: {
                            if (tuple_types.len == 0) break :blk .unknown;
                            var widened = tuple_types[0];
                            for (tuple_types[1..]) |t| {
                                widened = widened.widen(t);
                            }
                            break :blk widened;
                        },
                        else => .unknown,
                    };
                    try putForVarType(var_types, type_inferrer, target_name, elem_type);
                } else if (for_stmt.iter.* == .list and for_stmt.iter.list.elts.len > 0) {
                    // Iterating over list literal: for sign in ["", "+", "-"]
                    // Widen across all elements for heterogeneous lists like ['illegal', -1, 1 << 32]
                    var elem_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, for_stmt.iter.list.elts[0]);
                    for (for_stmt.iter.list.elts[1..]) |elem| {
                        const this_type = inferExprFn(allocator, var_types, class_fields, func_return_types, elem) catch .unknown;
                        elem_type = elem_type.widen(this_type);
                    }
                    try putForVarType(var_types, type_inferrer, target_name, elem_type);
                } else if (for_stmt.iter.* == .tuple and for_stmt.iter.tuple.elts.len > 0) {
                    // Iterating over tuple literal: for sign in "", "+", "-"
                    // Widen across all elements for heterogeneous tuples
                    var elem_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, for_stmt.iter.tuple.elts[0]);
                    for (for_stmt.iter.tuple.elts[1..]) |elem| {
                        const this_type = inferExprFn(allocator, var_types, class_fields, func_return_types, elem) catch .unknown;
                        elem_type = elem_type.widen(this_type);
                    }
                    try putForVarType(var_types, type_inferrer, target_name, elem_type);
                }
            }

            for (for_stmt.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
        },
        .function_def => |func_def| {
            // Enter named scope for this function
            const old_scope = if (type_inferrer) |ti| ti.enterScope(func_def.name) else null;
            defer if (type_inferrer) |ti| ti.exitScope(old_scope);

            // Register function return type from annotation
            // BUT don't overwrite if we already have a better inferred type from 4th pass
            var return_type = try core.pythonTypeHintToNative(func_def.return_type, allocator);

            // Register function parameter types from type annotations FIRST
            // This allows return type inference to see parameter types
            // Only store if we have an actual type annotation - don't overwrite
            // the int defaults set by inferFunctionReturnTypes
            for (func_def.args) |arg| {
                const param_type = try core.pythonTypeHintToNative(arg.type_annotation, allocator);
                if (param_type == .unknown) continue; // Don't overwrite existing types with unknown
                if (type_inferrer) |ti| {
                    try ti.putScopedVar(arg.name, param_type);
                } else {
                    try var_types.put(arg.name, param_type);
                }
            }

            // Visit function body FIRST to register local variable types with scoping
            for (func_def.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);

            // If no annotation (unknown), infer from return statements AFTER visiting body
            if (return_type == .unknown) {
                for (func_def.body) |body_stmt| {
                    if (body_stmt == .return_stmt and body_stmt.return_stmt.value != null) {
                        return_type = try inferExprFn(allocator, var_types, class_fields, func_return_types, body_stmt.return_stmt.value.?.*);
                        break;
                    }
                }
            }

            const existing = func_return_types.get(func_def.name);
            if (existing == null or existing.? == .unknown) {
                // Only set if no existing type or existing is unknown
                try func_return_types.put(func_def.name, return_type);
            }
        },
        .try_stmt => |try_stmt| {
            // Visit try body
            for (try_stmt.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
            // Visit except handlers
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
            }
            // Visit else body
            for (try_stmt.else_body) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
            // Visit finally body
            for (try_stmt.finalbody) |s| try visitStmtScoped(allocator, var_types, class_fields, func_return_types, class_constructor_args, inferExprFn, s, type_inferrer);
        },
        else => {},
    }
}

/// Infer type from constant literal
fn inferConstant(value: ast.Value) InferError!NativeType {
    return switch (value) {
        .int => .{ .int = .bounded },
        .bigint => .bigint, // Large integers are BigInt
        .float => .float,
        .string => .{ .string = .literal }, // String literals are compile-time constants
        .bytes => .{ .string = .literal }, // Bytes literals are also []const u8
        .bool => .bool,
        .none => .none,
        .complex => .complex, // Complex number literals
    };
}
