const std = @import("std");
const ast = @import("../../ast.zig");
const core = @import("core.zig");
const hashmap_helper = @import("../../utils/hashmap_helper.zig");
const calls = @import("calls.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);

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
        .call => |c| try calls.inferCall(allocator, var_types, class_fields, func_return_types, c),
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
            // Special case: module attributes (sys.platform, math.pi, etc.)
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
            }

            // Handle chained attribute access: sys.version_info.major
            if (a.value.* == .attribute) {
                const inner_attr = a.value.attribute;
                if (inner_attr.value.* == .name) {
                    const module_name = inner_attr.value.name.id;
                    if (std.mem.eql(u8, module_name, "sys") and
                        std.mem.eql(u8, inner_attr.attr, "version_info"))
                    {
                        // sys.version_info.major/minor/micro are all i32
                        if (std.mem.eql(u8, a.attr, "major") or
                            std.mem.eql(u8, a.attr, "minor") or
                            std.mem.eql(u8, a.attr, "micro"))
                        {
                            break :blk .int;
                        }
                    }
                }
            }

            // Handle module attributes (continued for name-based modules)
            if (a.value.* == .name) {
                const module_name = a.value.name.id;

                // math module constants
                if (std.mem.eql(u8, module_name, "math")) {
                    if (std.mem.eql(u8, a.attr, "pi") or
                        std.mem.eql(u8, a.attr, "e") or
                        std.mem.eql(u8, a.attr, "tau") or
                        std.mem.eql(u8, a.attr, "inf") or
                        std.mem.eql(u8, a.attr, "nan"))
                    {
                        break :blk .float;
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
        .listcomp => |lc| blk: {
            // Infer element type from the comprehension expression
            const elem_type = try inferExpr(allocator, var_types, class_fields, func_return_types, lc.elt.*);

            // List comprehensions produce slices ([]T) via toOwnedSlice
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
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
        .set => |s| blk: {
            // Infer element type from set elements
            const elem_type = if (s.elts.len > 0)
                try inferExpr(allocator, var_types, class_fields, func_return_types, s.elts[0])
            else
                .unknown;

            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .set = elem_ptr };
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
        .named_expr => |ne| blk: {
            // Named expression (walrus operator): (x := value)
            // The type of the named expression is the type of the value
            break :blk try inferExpr(allocator, var_types, class_fields, func_return_types, ne.value.*);
        },
        .if_expr => |ie| blk: {
            // Conditional expression (ternary): body if condition else orelse_value
            // Return the wider type of body and orelse_value (they should match in Python)
            const body_type = try inferExpr(allocator, var_types, class_fields, func_return_types, ie.body.*);
            const orelse_type = try inferExpr(allocator, var_types, class_fields, func_return_types, ie.orelse_value.*);
            break :blk body_type.widen(orelse_type);
        },
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
        .unaryop => |u| blk: {
            const operand_type = try inferExpr(allocator, var_types, class_fields, func_return_types, u.operand.*);
            // In Python, +bool and -bool convert to int
            switch (u.op) {
                .UAdd, .USub => {
                    if (operand_type == .bool) {
                        break :blk .int;
                    }
                    break :blk operand_type;
                },
                .Not => break :blk .bool, // not x always returns bool
                .Invert => break :blk .int, // ~x always returns int
            }
        },
        .boolop => .bool, // and/or expressions return bool
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
