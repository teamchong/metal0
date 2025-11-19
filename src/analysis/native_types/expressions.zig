const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

/// Infer the native type of an expression node
pub fn inferExpr(
    allocator: std.mem.Allocator,
    var_types: *std.StringHashMap(NativeType),
    class_fields: *std.StringHashMap(ClassInfo),
    func_return_types: *std.StringHashMap(NativeType),
    node: ast.Node,
) InferError!NativeType {
    return switch (node) {
        .constant => |c| inferConstant(c.value),
        .name => |n| var_types.get(n.id) orelse .unknown,
        .binop => |b| try inferBinOp(allocator, var_types, class_fields, func_return_types, b),
        .call => |c| try inferCall(allocator, var_types, class_fields, func_return_types, c),
        .subscript => |s| blk: {
            // Infer subscript type: obj[index] or obj[slice]
            const obj_type = try inferExpr(allocator, var_types, class_fields, func_return_types, s.value.*);

            switch (s.slice) {
                .index => |idx| {
                    // Single index access
                    // string[i] -> u8 (but we treat as string for printing)
                    // list[i] -> element type
                    // dict[key] -> value type
                    // tuple[i] -> element type at index i
                    if (obj_type == .string) {
                        // String indexing returns a single character
                        // For now, treat as string for simplicity
                        break :blk .{ .string = .slice };
                    } else if (obj_type == .array) {
                        break :blk obj_type.array.element_type.*;
                    } else if (obj_type == .list) {
                        break :blk obj_type.list.*;
                    } else if (obj_type == .dict) {
                        break :blk obj_type.dict.value.*;
                    } else if (obj_type == .tuple) {
                        // Try to get constant index
                        if (idx.* == .constant and idx.constant.value == .int) {
                            const index = @as(usize, @intCast(idx.constant.value.int));
                            if (index < obj_type.tuple.len) {
                                break :blk obj_type.tuple[index];
                            }
                        }
                        // If we can't determine constant index, return unknown
                        break :blk .unknown;
                    } else {
                        break :blk .unknown;
                    }
                },
                .slice => {
                    // Slice access always returns same type as container
                    // string[1:4] -> string
                    // array[1:4] -> slice (converted to list)
                    // list[1:4] -> list
                    if (obj_type == .string) {
                        break :blk .{ .string = .slice };
                    } else if (obj_type == .array) {
                        // Array slices become lists (dynamic)
                        break :blk .{ .list = obj_type.array.element_type };
                    } else if (obj_type == .list) {
                        break :blk obj_type;
                    } else {
                        break :blk .unknown;
                    }
                },
            }
        },
        .attribute => |a| blk: {
            // Infer attribute type: obj.attr
            // Heuristic: Check all known classes for a field with this name
            // This works when field names are unique across classes
            if (a.value.* == .name) {
                var class_it = class_fields.iterator();
                while (class_it.next()) |class_entry| {
                    if (class_entry.value_ptr.fields.get(a.attr)) |field_type| {
                        // Found a class with a field matching this attribute name
                        break :blk field_type;
                    }
                }
            }

            // Fallback: try to infer from object type (for future enhancements)
            const obj_type = try inferExpr(allocator, var_types, class_fields, func_return_types, a.value.*);
            _ = obj_type; // Currently unused, but kept for future use

            break :blk .unknown;
        },
        .list => |l| blk: {
            // Check if this is a constant, homogeneous list → use array type
            if (core.isConstantList(l) and core.allSameType(l.elts)) {
                const elem_type = if (l.elts.len > 0)
                    try inferExpr(allocator, var_types, class_fields, func_return_types, l.elts[0])
                else
                    .unknown;

                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = elem_type;
                break :blk .{ .array = .{
                    .element_type = elem_ptr,
                    .length = l.elts.len,
                } };
            }

            // Otherwise, use ArrayList for dynamic lists
            const elem_type = if (l.elts.len > 0)
                try inferExpr(allocator, var_types, class_fields, func_return_types, l.elts[0])
            else
                .unknown;

            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
        },
        .dict => |d| blk: {
            // Infer value type from first value if available
            const val_type = if (d.values.len > 0)
                try inferExpr(allocator, var_types, class_fields, func_return_types, d.values[0])
            else
                .unknown;

            // Allocate on heap to avoid dangling pointer
            const val_ptr = try allocator.create(NativeType);
            val_ptr.* = val_type;

            // Allocate key type (always string for Python dicts)
            const key_ptr = try allocator.create(NativeType);
            key_ptr.* = .{ .string = .runtime };

            // For now, always use string keys (most common case)
            break :blk .{ .dict = .{
                .key = key_ptr,
                .value = val_ptr,
            } };
        },
        .dictcomp => |dc| blk: {
            // Infer types from key and value expressions
            const key_type = try inferExpr(allocator, var_types, class_fields, func_return_types, dc.key.*);
            const val_type = try inferExpr(allocator, var_types, class_fields, func_return_types, dc.value.*);

            // Allocate key and value types on heap
            const key_ptr = try allocator.create(NativeType);
            key_ptr.* = key_type;
            const val_ptr = try allocator.create(NativeType);
            val_ptr.* = val_type;

            break :blk .{ .dict = .{
                .key = key_ptr,
                .value = val_ptr,
            } };
        },
        .tuple => |t| blk: {
            // Infer types of all tuple elements
            var elem_types = try allocator.alloc(NativeType, t.elts.len);
            for (t.elts, 0..) |elt, i| {
                elem_types[i] = try inferExpr(allocator, var_types, class_fields, func_return_types, elt);
            }
            break :blk .{ .tuple = elem_types };
        },
        .compare => .bool, // Comparison expressions always return bool
        .lambda => |lam| blk: {
            // Infer function type from lambda
            // For now, default all params and return to i64
            // TODO: Better type inference based on usage
            const param_types = try allocator.alloc(NativeType, lam.args.len);
            for (param_types) |*pt| {
                pt.* = .int; // Default to i64
            }
            const return_ptr = try allocator.create(NativeType);
            return_ptr.* = .int; // Default to i64
            break :blk .{ .function = .{
                .params = param_types,
                .return_type = return_ptr,
            } };
        },
        else => .unknown,
    };
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

/// Infer type from binary operation
fn inferBinOp(
    allocator: std.mem.Allocator,
    var_types: *std.StringHashMap(NativeType),
    class_fields: *std.StringHashMap(ClassInfo),
    func_return_types: *std.StringHashMap(NativeType),
    binop: ast.Node.BinOp,
) InferError!NativeType {
    const left_type = try inferExpr(allocator, var_types, class_fields, func_return_types, binop.left.*);
    const right_type = try inferExpr(allocator, var_types, class_fields, func_return_types, binop.right.*);

    // Get type tags for analysis
    const left_tag = @as(std.meta.Tag(NativeType), left_type);
    const right_tag = @as(std.meta.Tag(NativeType), right_type);

    // String concatenation: str + str → runtime string
    if (binop.op == .Add and left_tag == .string and right_tag == .string) {
        return .{ .string = .runtime }; // Concatenation produces runtime string
    }

    // Type promotion: int + float → float
    if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult or binop.op == .Div) {
        if (left_tag == .float or right_tag == .float) {
            return .float; // Any arithmetic with float produces float
        }
        // usize mixed with int → result is int (codegen casts both to i64)
        if ((left_tag == .usize and right_tag == .int) or (left_tag == .int and right_tag == .usize)) {
            return .int;
        }
        // usize op usize → usize
        if (left_tag == .usize and right_tag == .usize) {
            return .usize;
        }
        if (left_tag == .int and right_tag == .int) {
            return .int; // int op int produces int
        }
    }

    // Default: use widening logic
    return left_type.widen(right_type);
}

/// Infer type from function/method call
fn inferCall(
    allocator: std.mem.Allocator,
    var_types: *std.StringHashMap(NativeType),
    class_fields: *std.StringHashMap(ClassInfo),
    func_return_types: *std.StringHashMap(NativeType),
    call: ast.Node.Call,
) InferError!NativeType {
    // Check if this is a registered function (lambda or regular function)
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Check for registered function return types (lambdas, etc.)
        if (func_return_types.get(func_name)) |return_type| {
            return return_type;
        }

        // Built-in type conversion functions

        if (std.mem.eql(u8, func_name, "str")) return .{ .string = .runtime }; // str() produces runtime string
        if (std.mem.eql(u8, func_name, "int")) return .int;
        if (std.mem.eql(u8, func_name, "float")) return .float;
        if (std.mem.eql(u8, func_name, "bool")) return .bool;

        // Built-in math functions
        if (std.mem.eql(u8, func_name, "abs")) {
            // abs() returns same type as input
            if (call.args.len > 0) {
                return try inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            }
        }
        if (std.mem.eql(u8, func_name, "round")) return .int;
        if (std.mem.eql(u8, func_name, "chr")) return .{ .string = .runtime }; // chr() produces runtime string
        if (std.mem.eql(u8, func_name, "ord")) return .int;
    }

    // Check if this is a method call (attribute access)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Check for pandas.DataFrame() or pd.DataFrame()
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            if ((std.mem.eql(u8, module_name, "pandas") or std.mem.eql(u8, module_name, "pd")) and
                std.mem.eql(u8, attr.attr, "DataFrame")) {
                return .dataframe;
            }
        }

        const obj_type = try inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.*);

        // String methods that return strings
        if (obj_type == .string) {
            const str_methods = [_][]const u8{
                "upper", "lower", "strip", "lstrip", "rstrip",
                "capitalize", "title", "swapcase", "replace",
                "join", "center", "ljust", "rjust", "zfill",
            };

            for (str_methods) |method| {
                if (std.mem.eql(u8, attr.attr, method)) {
                    return .{ .string = .runtime }; // String methods produce runtime strings
                }
            }

            // Boolean-returning methods
            if (std.mem.eql(u8, attr.attr, "startswith")) return .bool;
            if (std.mem.eql(u8, attr.attr, "endswith")) return .bool;

            // Integer-returning methods
            if (std.mem.eql(u8, attr.attr, "find")) return .int;

            // split() returns list of runtime strings
            if (std.mem.eql(u8, attr.attr, "split")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime }; // Split produces list of runtime strings
                return .{ .list = elem_ptr };
            }
        }

        // Dict methods
        if (obj_type == .dict) {
            // keys() returns list of strings (dict keys are always strings)
            if (std.mem.eql(u8, attr.attr, "keys")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime }; // Dict keys are runtime strings
                return .{ .list = elem_ptr };
            }

            // values() returns list of dict value type
            if (std.mem.eql(u8, attr.attr, "values")) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = obj_type.dict.value.*;
                return .{ .list = elem_ptr };
            }

            // items() returns list of tuples (key, value)
            if (std.mem.eql(u8, attr.attr, "items")) {
                const tuple_types = try allocator.alloc(NativeType, 2);
                tuple_types[0] = .{ .string = .runtime }; // Dict keys are runtime strings
                tuple_types[1] = obj_type.dict.value.*; // value
                const tuple_ptr = try allocator.create(NativeType);
                tuple_ptr.* = .{ .tuple = tuple_types };
                return .{ .list = tuple_ptr };
            }
        }

        // DataFrame Column methods (when accessing df['col'].method())
        // Column methods return float (sum, mean, min, max, std)
        if (obj_type == .dataframe or
            (attr.value.* == .subscript and
             try inferExpr(allocator, var_types, class_fields, func_return_types, attr.value.subscript.value.*) == .dataframe)) {
            const column_methods = [_][]const u8{
                "sum", "mean", "min", "max", "std",
            };
            for (column_methods) |method| {
                if (std.mem.eql(u8, attr.attr, method)) {
                    return .float;
                }
            }
            // describe() returns a struct with stats (treat as unknown for now)
            if (std.mem.eql(u8, attr.attr, "describe")) {
                return .unknown;
            }
        }
    }

    // For other calls, return unknown
    return .unknown;
}
