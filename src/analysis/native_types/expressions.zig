const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const hashmap_helper = @import("hashmap_helper");
const calls = @import("calls.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);

// ComptimeStringMaps for module attribute lookups (DCE-friendly)
const SysAttrType = enum { platform, version_info, argv, version };
const SysAttrMap = std.StaticStringMap(SysAttrType).initComptime(.{
    .{ "platform", .platform },
    .{ "version_info", .version_info },
    .{ "argv", .argv },
    .{ "version", .version },
});

const VersionInfoAttrMap = std.StaticStringMap(void).initComptime(.{
    .{ "major", {} },
    .{ "minor", {} },
    .{ "micro", {} },
});

const MathConstMap = std.StaticStringMap(void).initComptime(.{
    .{ "pi", {} },
    .{ "e", {} },
    .{ "tau", {} },
    .{ "inf", {} },
    .{ "nan", {} },
});

// String module constants (all return strings)
const StringConstMap = std.StaticStringMap(void).initComptime(.{
    .{ "ascii_lowercase", {} },
    .{ "ascii_uppercase", {} },
    .{ "ascii_letters", {} },
    .{ "digits", {} },
    .{ "hexdigits", {} },
    .{ "octdigits", {} },
    .{ "punctuation", {} },
    .{ "whitespace", {} },
    .{ "printable", {} },
});

// OS module constants
const OsConstMap = std.StaticStringMap(void).initComptime(.{
    .{ "name", {} },
    .{ "sep", {} },
    .{ "linesep", {} },
    .{ "pathsep", {} },
});

const ModuleType = enum { sys, math, string, os };
const ModuleMap = std.StaticStringMap(ModuleType).initComptime(.{
    .{ "sys", .sys },
    .{ "math", .math },
    .{ "string", .string },
    .{ "os", .os },
});

/// Exception type names - when stored as values (e.g., in lists/tuples), treat as int
const ExceptionTypeNames = std.StaticStringMap(void).initComptime(.{
    .{ "TypeError", {} },
    .{ "ValueError", {} },
    .{ "KeyError", {} },
    .{ "IndexError", {} },
    .{ "ZeroDivisionError", {} },
    .{ "AttributeError", {} },
    .{ "NameError", {} },
    .{ "FileNotFoundError", {} },
    .{ "IOError", {} },
    .{ "RuntimeError", {} },
    .{ "StopIteration", {} },
    .{ "NotImplementedError", {} },
    .{ "AssertionError", {} },
    .{ "OverflowError", {} },
    .{ "ImportError", {} },
    .{ "ModuleNotFoundError", {} },
    .{ "OSError", {} },
    .{ "PermissionError", {} },
    .{ "TimeoutError", {} },
    .{ "ConnectionError", {} },
    .{ "RecursionError", {} },
    .{ "MemoryError", {} },
    .{ "LookupError", {} },
    .{ "ArithmeticError", {} },
    .{ "UnicodeError", {} },
    .{ "UnicodeDecodeError", {} },
    .{ "UnicodeEncodeError", {} },
    .{ "BlockingIOError", {} },
});

fn isExceptionTypeName(name: []const u8) bool {
    return ExceptionTypeNames.has(name);
}

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
        .name => |n| blk: {
            // Check if name is in var_types
            if (var_types.get(n.id)) |vt| break :blk vt;
            // Check if name is a Python exception type - treat as int (ExceptionTypeId)
            if (isExceptionTypeName(n.id)) break :blk .int;
            break :blk .unknown;
        },
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
                    } else if (obj_type == .counter) {
                        // Counter subscript returns int (the count)
                        break :blk .int;
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
                    } else if (obj_type == .numpy_array) {
                        // Check if index is a boolean array (boolean indexing)
                        const idx_type = try inferExpr(allocator, var_types, class_fields, func_return_types, idx.*);
                        if (idx_type == .bool_array) {
                            // Boolean indexing returns a numpy array
                            break :blk .numpy_array;
                        }
                        // Check for tuple index with slices: arr[:, 0] or arr[0, :]
                        if (idx.* == .tuple) {
                            const indices = idx.tuple.elts;
                            if (indices.len == 2) {
                                const first = indices[0];
                                const second = indices[1];
                                const first_is_slice = (first == .constant and first.constant.value == .none);
                                const second_is_slice = (second == .constant and second.constant.value == .none);
                                if (first_is_slice or second_is_slice) {
                                    // Row or column slicing returns numpy_array
                                    break :blk .numpy_array;
                                }
                            }
                        }
                        // Single index access returns float (f64)
                        break :blk .float;
                    } else {
                        break :blk .unknown;
                    }
                },
                .slice => {
                    // Slice access always returns same type as container
                    // string[1:4] -> string
                    // array[1:4] -> slice (converted to list)
                    // list[1:4] -> list
                    // numpy_array[1:4] -> numpy_array
                    if (obj_type == .string) {
                        break :blk .{ .string = .slice };
                    } else if (obj_type == .array) {
                        // Array slices become lists (dynamic)
                        break :blk .{ .list = obj_type.array.element_type };
                    } else if (obj_type == .list) {
                        break :blk obj_type;
                    } else if (obj_type == .numpy_array) {
                        // NumPy array slicing returns numpy_array
                        break :blk .numpy_array;
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
                if (ModuleMap.get(module_name)) |mod| {
                    switch (mod) {
                        .sys => {
                            if (SysAttrMap.get(a.attr)) |attr| {
                                switch (attr) {
                                    .platform, .version => break :blk .{ .string = .literal },
                                    .version_info => break :blk .int, // Access like int
                                    .argv => {
                                        // sys.argv is [][]const u8 - return as string array
                                        const str_type = try allocator.create(NativeType);
                                        str_type.* = .{ .string = .slice };
                                        break :blk .{ .array = .{ .element_type = str_type, .length = 0 } };
                                    },
                                }
                            }
                        },
                        .math => {
                            if (MathConstMap.has(a.attr)) {
                                break :blk .float;
                            }
                        },
                        .string => {
                            // string module constants return string literals
                            if (StringConstMap.has(a.attr)) {
                                break :blk .{ .string = .literal };
                            }
                        },
                        .os => {
                            // os module constants return string literals
                            if (OsConstMap.has(a.attr)) {
                                break :blk .{ .string = .literal };
                            }
                        },
                    }
                }

                // First, check if this variable is a known class instance
                // This ensures we look up the correct class's field type
                if (var_types.get(module_name)) |var_type| {
                    if (var_type == .class_instance) {
                        if (class_fields.get(var_type.class_instance)) |class_info| {
                            if (class_info.fields.get(a.attr)) |field_type| {
                                break :blk field_type;
                            }
                        }
                    }
                }

                // Heuristic fallback: Check all known classes for a field with this name
                // This works when field names are unique across classes
                var class_it = class_fields.iterator();
                while (class_it.next()) |class_entry| {
                    if (class_entry.value_ptr.fields.get(a.attr)) |field_type| {
                        // Found a class with a field matching this attribute name
                        break :blk field_type;
                    }
                }
            }

            // Handle chained attribute access: sys.version_info.major
            if (a.value.* == .attribute) {
                const inner_attr = a.value.attribute;
                if (inner_attr.value.* == .name) {
                    const module_name = inner_attr.value.name.id;
                    if (ModuleMap.get(module_name) == .sys and
                        SysAttrMap.get(inner_attr.attr) == .version_info)
                    {
                        // sys.version_info.major/minor/micro are all i32
                        if (VersionInfoAttrMap.has(a.attr)) {
                            break :blk .int;
                        }
                    }
                }
            }

            // Try to infer from object type
            const obj_type = try inferExpr(allocator, var_types, class_fields, func_return_types, a.value.*);

            // If object is a class instance, look up field type from class definition
            if (obj_type == .class_instance) {
                const class_name = obj_type.class_instance;
                if (class_fields.get(class_name)) |class_info| {
                    if (class_info.fields.get(a.attr)) |field_type| {
                        break :blk field_type;
                    }
                }
            }

            // Path properties
            if (obj_type == .path) {
                const fnv_hash = @import("fnv_hash");
                const attr_hash = fnv_hash.hash(a.attr);
                const PARENT_HASH = comptime fnv_hash.hash("parent");
                const NAME_HASH = comptime fnv_hash.hash("name");
                const STEM_HASH = comptime fnv_hash.hash("stem");
                const SUFFIX_HASH = comptime fnv_hash.hash("suffix");
                // parent property returns Path
                if (attr_hash == PARENT_HASH) break :blk .path;
                // name/stem/suffix properties return string
                if (attr_hash == NAME_HASH or attr_hash == STEM_HASH or attr_hash == SUFFIX_HASH) {
                    break :blk .{ .string = .runtime };
                }
            }

            // NumPy array properties
            if (obj_type == .numpy_array) {
                if (std.mem.eql(u8, a.attr, "shape") or
                    std.mem.eql(u8, a.attr, "strides"))
                {
                    // shape/strides return []const usize in Zig
                    break :blk .usize_slice;
                }
                if (std.mem.eql(u8, a.attr, "size") or
                    std.mem.eql(u8, a.attr, "ndim"))
                {
                    break :blk .usize;
                }
                if (std.mem.eql(u8, a.attr, "T")) {
                    // Transpose returns numpy_array
                    break :blk .numpy_array;
                }
                if (std.mem.eql(u8, a.attr, "data")) {
                    // data returns slice, treat as unknown
                    break :blk .unknown;
                }
            }

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
            // Widen element type across all elements for heterogeneous lists
            var elem_type: NativeType = if (l.elts.len > 0)
                try inferExpr(allocator, var_types, class_fields, func_return_types, l.elts[0])
            else
                .unknown;

            // Widen type to accommodate all elements
            for (l.elts[1..]) |elem| {
                const this_type = try inferExpr(allocator, var_types, class_fields, func_return_types, elem);
                elem_type = elem_type.widen(this_type);
            }

            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
        },
        .dict => |d| blk: {
            // Check if dict has mixed types - codegen converts mixed dicts to StringHashMap([]const u8)
            var val_type: NativeType = .unknown;
            var has_mixed_types = false;

            if (d.values.len > 0) {
                // Check first entry - may be dict unpacking (**d) signaled by None key
                if (d.keys[0] == .constant and d.keys[0].constant.value == .none) {
                    // Dict unpacking - get type from the unpacked dict
                    const unpacked_type = try inferExpr(allocator, var_types, class_fields, func_return_types, d.values[0]);
                    if (unpacked_type == .dict) {
                        val_type = unpacked_type.dict.value.*;
                    } else {
                        val_type = .unknown;
                    }
                } else {
                    val_type = try inferExpr(allocator, var_types, class_fields, func_return_types, d.values[0]);
                }

                // Check if all values have same type
                for (d.keys[1..], d.values[1..]) |key, value| {
                    var this_type: NativeType = undefined;
                    if (key == .constant and key.constant.value == .none) {
                        // Dict unpacking
                        const unpacked_type = try inferExpr(allocator, var_types, class_fields, func_return_types, value);
                        if (unpacked_type == .dict) {
                            this_type = unpacked_type.dict.value.*;
                        } else {
                            this_type = .unknown;
                        }
                    } else {
                        this_type = try inferExpr(allocator, var_types, class_fields, func_return_types, value);
                    }
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

            // Infer key type from first non-unpacking key
            var key_type: NativeType = .{ .string = .runtime };
            for (d.keys) |key| {
                if (key != .constant or key.constant.value != .none) {
                    key_type = try inferExpr(allocator, var_types, class_fields, func_return_types, key);
                    break;
                }
            }

            const key_ptr = try allocator.create(NativeType);
            key_ptr.* = key_type;

            break :blk .{ .dict = .{
                .key = key_ptr,
                .value = val_ptr,
            } };
        },
        .listcomp => |lc| blk: {
            // First, type the loop variables from generators so they're available for elt inference
            for (lc.generators) |gen| {
                if (gen.target.* == .name) {
                    // Check if iterator is range() - gives i64 loop variable
                    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                        const func_name = gen.iter.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "range")) {
                            try var_types.put(gen.target.name.id, .int);
                        }
                    }
                }
            }

            // Infer element type from the comprehension expression
            const elem_type = try inferExpr(allocator, var_types, class_fields, func_return_types, lc.elt.*);

            // List comprehensions produce ArrayList(T)
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
        },
        .dictcomp => |dc| blk: {
            // First, type the loop variables from generators so they're available for key/value inference
            for (dc.generators) |gen| {
                if (gen.target.* == .name) {
                    // Check if iterator is range() - gives i64 loop variable
                    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                        const func_name = gen.iter.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "range")) {
                            try var_types.put(gen.target.name.id, .int);
                        }
                    }
                }
            }

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
        .compare => |c| blk: {
            // NumPy array comparisons return bool_array (element-wise)
            const cmp_left_type = try inferExpr(allocator, var_types, class_fields, func_return_types, c.left.*);
            if (cmp_left_type == .numpy_array) {
                break :blk .bool_array;
            }
            break :blk .bool; // Regular comparison returns bool
        },
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

    // Path join: Path / string → Path
    if (binop.op == .Div and left_tag == .path) {
        return .path;
    }

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
