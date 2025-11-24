const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");
const fnv_hash = @import("../../utils/fnv_hash.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvContext = fnv_hash.FnvHashContext([]const u8);
const FnvHashMap = std.HashMap([]const u8, NativeType, FnvContext, 80);
const FnvClassMap = std.HashMap([]const u8, ClassInfo, FnvContext, 80);

/// Infer the native type of an expression node
pub fn inferExpr(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    node: ast.Node,
) InferError!NativeType {
    return switch (node) {
        .constant => |c| inferConstant(c.value),
        .fstring => .{ .string = .runtime },
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
                        // Return the dict's value type
                        // Note: Codegen converts mixed-type dicts to string dicts
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
            // Special case: module attributes (sys.platform, sys.version_info)
            if (a.value.* == .name) {
                const module_name = a.value.name.id;
                if (std.mem.eql(u8, module_name, "sys")) {
                    if (std.mem.eql(u8, a.attr, "platform")) {
                        break :blk .{ .string = .literal };
                    } else if (std.mem.eql(u8, a.attr, "version_info")) {
                        break :blk .unknown; // struct type
                    } else if (std.mem.eql(u8, a.attr, "argv")) {
                        break :blk .unknown; // [][]const u8
                    }
                }

                // Heuristic: Check all known classes for a field with this name
                // This works when field names are unique across classes
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
            // Check if dict has mixed types - codegen converts mixed dicts to StringHashMap([]const u8)
            var val_type: NativeType = .unknown;
            var has_mixed_types = false;

            if (d.values.len > 0) {
                val_type = try inferExpr(allocator, var_types, class_fields, func_return_types, d.values[0]);

                // Check if all values have same type
                for (d.values[1..]) |value| {
                    const this_type = try inferExpr(allocator, var_types, class_fields, func_return_types, value);
                    // Compare type tags
                    const tag1 = @as(std.meta.Tag(NativeType), val_type);
                    const tag2 = @as(std.meta.Tag(NativeType), this_type);
                    if (tag1 != tag2) {
                        has_mixed_types = true;
                        break;
                    }
                }

                // If mixed types, codegen will convert all to strings
                if (has_mixed_types) {
                    val_type = .{ .string = .runtime };
                }
            }

            // Allocate on heap to avoid dangling pointer
            const val_ptr = try allocator.create(NativeType);
            val_ptr.* = val_type;

            // Allocate key type (always string for Python dicts)
            const key_ptr = try allocator.create(NativeType);
            key_ptr.* = .{ .string = .runtime };

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
        .none => .none,
    };
}

/// Infer type from binary operation
fn inferBinOp(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
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
        // Python's / operator ALWAYS returns float (true division)
        if (binop.op == .Div) {
            return .float; // Division always produces float
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
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    call: ast.Node.Call,
) InferError!NativeType {
    // Check if this is a registered function (lambda or regular function)
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Check if this is a class constructor (class_name matches a registered class)
        if (class_fields.get(func_name)) |class_info| {
            // Infer parameter types from call arguments and update class field types
            // This allows classes without type hints to infer types from usage
            _ = class_info; // Currently unused, but kept for future enhancements

            // TODO: Record argument types to improve __init__ parameter inference
            // For now, just return the class instance type
            return .{ .class_instance = func_name };
        }

        // Check for registered function return types (lambdas, etc.)
        if (func_return_types.get(func_name)) |return_type| {
            return return_type;
        }

        // Built-in type conversion functions

        if (std.mem.eql(u8, func_name, "len")) return .int; // len() returns int
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
        if (std.mem.eql(u8, func_name, "min")) return .int; // min() returns int
        if (std.mem.eql(u8, func_name, "max")) return .int; // max() returns int
        if (std.mem.eql(u8, func_name, "sum")) return .int; // sum() returns int
    }

    // Check if this is a method call (attribute access)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Helper to build full qualified name for nested attributes
        // e.g., testpkg.submod.sub_func -> "testpkg.submod.sub_func"
        const buildQualifiedName = struct {
            fn build(node: *const ast.Node, buf: []u8) []const u8 {
                if (node.* == .name) {
                    // Base case: just a name
                    const name = node.name.id;
                    if (name.len > buf.len) return &[_]u8{};
                    @memcpy(buf[0..name.len], name);
                    return buf[0..name.len];
                } else if (node.* == .attribute) {
                    // Recursive case: build prefix, then add .attr
                    const prefix = build(node.attribute.value, buf);
                    if (prefix.len == 0) return &[_]u8{};
                    const attr_name = node.attribute.attr;
                    const total_len = prefix.len + 1 + attr_name.len;
                    if (total_len > buf.len) return &[_]u8{};
                    buf[prefix.len] = '.';
                    @memcpy(buf[prefix.len + 1..total_len], attr_name);
                    return buf[0..total_len];
                }
                return &[_]u8{};
            }
        }.build;

        // Build full qualified name including the function
        var buf: [512]u8 = undefined;
        const prefix = buildQualifiedName(attr.value, buf[0..]);
        if (prefix.len > 0) {
            const total_len = prefix.len + 1 + attr.attr.len;
            if (total_len <= buf.len) {
                buf[prefix.len] = '.';
                @memcpy(buf[prefix.len + 1..total_len], attr.attr);
                const qualified_name = buf[0..total_len];

                // Look up in func_return_types (module.function -> return type)
                if (func_return_types.get(qualified_name)) |return_type| {
                    return return_type;
                }
            }
        }

        // Check for module function calls (module.function) - single level
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // json.loads() returns PyObject (dict)
            // Type is unknown at compile time, will use formatPyObject at runtime
            if (std.mem.eql(u8, module_name, "json") and std.mem.eql(u8, func_name, "loads")) {
                return .unknown;
            }

            // pandas.DataFrame() or pd.DataFrame()
            if ((std.mem.eql(u8, module_name, "pandas") or std.mem.eql(u8, module_name, "pd")) and
                std.mem.eql(u8, func_name, "DataFrame")) {
                return .dataframe;
            }

            // Check if this is a class instance method call
            // e.g., dog.speak() where dog is an instance of Dog class
            const var_type = var_types.get(module_name) orelse .unknown;
            if (var_type == .class_instance) {
                const class_name = var_type.class_instance;
                if (class_fields.get(class_name)) |class_info| {
                    if (class_info.methods.get(attr.attr)) |method_return_type| {
                        return method_return_type;
                    }
                }
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
            if (std.mem.eql(u8, attr.attr, "isdigit")) return .bool;
            if (std.mem.eql(u8, attr.attr, "isalpha")) return .bool;
            if (std.mem.eql(u8, attr.attr, "isalnum")) return .bool;
            if (std.mem.eql(u8, attr.attr, "isspace")) return .bool;
            if (std.mem.eql(u8, attr.attr, "islower")) return .bool;
            if (std.mem.eql(u8, attr.attr, "isupper")) return .bool;

            // Integer-returning methods
            if (std.mem.eql(u8, attr.attr, "find")) return .int;
            if (std.mem.eql(u8, attr.attr, "count")) return .int;

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
