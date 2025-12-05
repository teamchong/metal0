const std = @import("std");
const ast = @import("ast");
const core = @import("core.zig");
const hashmap_helper = @import("hashmap_helper");
const calls = @import("calls.zig");
const inferrer_mod = @import("inferrer.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);

// ComptimeStringMaps for module attribute lookups (DCE-friendly)
const SysAttrType = enum { platform, version_info, argv, version, maxsize };
const SysAttrMap = std.StaticStringMap(SysAttrType).initComptime(.{
    .{ "platform", .platform },
    .{ "version_info", .version_info },
    .{ "argv", .argv },
    .{ "version", .version },
    .{ "maxsize", .maxsize },
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
    .{ "curdir", {} },
    .{ "pardir", {} },
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

/// Deep equality check for NativeType, including nested types
fn typesEqual(a: NativeType, b: NativeType) bool {
    const tag_a = @as(std.meta.Tag(NativeType), a);
    const tag_b = @as(std.meta.Tag(NativeType), b);
    if (tag_a != tag_b) return false;

    return switch (a) {
        .array => |arr_a| blk: {
            const arr_b = b.array;
            if (arr_a.length != arr_b.length) break :blk false;
            break :blk typesEqual(arr_a.element_type.*, arr_b.element_type.*);
        },
        .list => |elem_a| typesEqual(elem_a.*, b.list.*),
        .dict => |dict_a| blk: {
            const dict_b = b.dict;
            if (!typesEqual(dict_a.key.*, dict_b.key.*)) break :blk false;
            break :blk typesEqual(dict_a.value.*, dict_b.value.*);
        },
        .tuple => |tuple_a| blk: {
            const tuple_b = b.tuple;
            if (tuple_a.len != tuple_b.len) break :blk false;
            for (tuple_a, tuple_b) |t1, t2| {
                if (!typesEqual(t1, t2)) break :blk false;
            }
            break :blk true;
        },
        .optional => |inner_a| typesEqual(inner_a.*, b.optional.*),
        // Primitives and other simple types - tag equality is sufficient
        else => true,
    };
}

/// Type names that represent callable type constructors (bytes, str, etc.)
/// When used as values (not called), these are PyCallable instances
const CallableTypeNames = std.StaticStringMap(void).initComptime(.{
    .{ "bytes", {} },
    .{ "bytearray", {} },
    .{ "str", {} },
    .{ "memoryview", {} },
    .{ "int", {} },
    .{ "float", {} },
    .{ "bool", {} },
    .{ "list", {} },
    .{ "dict", {} },
    .{ "set", {} },
    .{ "tuple", {} },
    .{ "frozenset", {} },
    .{ "type", {} },
    .{ "object", {} },
});

fn isCallableTypeName(name: []const u8) bool {
    return CallableTypeNames.has(name);
}

/// Infer the native type of an expression node
pub fn inferExpr(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    node: ast.Node,
) InferError!NativeType {
    return inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, node, null);
}

/// Infer the native type of an expression node with optional TypeInferrer for ctypes tracking
pub fn inferExprWithInferrer(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    node: ast.Node,
    type_inferrer: ?*inferrer_mod.TypeInferrer,
) InferError!NativeType {
    return switch (node) {
        .constant => |c| inferConstant(c.value),
        .fstring => .{ .string = .runtime },
        .name => |n| blk: {
            // Check if name is in var_types
            if (var_types.get(n.id)) |vt| break :blk vt;
            // Check if name is a Python exception type - treat as int (ExceptionTypeId)
            if (isExceptionTypeName(n.id)) break :blk .{ .int = .bounded };
            // Check if name is a type constructor used as a callable (bytes, str, etc.)
            if (isCallableTypeName(n.id)) break :blk .callable;
            break :blk .unknown;
        },
        .binop => |b| try inferBinOpWithInferrer(allocator, var_types, class_fields, func_return_types, b, type_inferrer),
        .call => |c| try calls.inferCallWithInferrer(allocator, var_types, class_fields, func_return_types, c, type_inferrer),
        .subscript => |s| blk: {
            // Infer subscript type: obj[index] or obj[slice]
            const obj_type = try inferExpr(allocator, var_types, class_fields, func_return_types, s.value.*);

            switch (s.slice) {
                .index => |idx| {
                    // Single index access
                    // string[i] -> u8 (but we treat as string for printing)
                    // bytes[i] -> u8 (integer)
                    // list[i] -> element type
                    // dict[key] -> value type
                    // tuple[i] -> element type at index i
                    if (obj_type == .string) {
                        // String indexing returns a single character
                        // For now, treat as string for simplicity
                        break :blk .{ .string = .slice };
                    } else if (obj_type == .bytes) {
                        // Bytes indexing returns a single byte (u8/int)
                        break :blk .{ .int = .bounded };
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
                        break :blk .{ .int = .bounded };
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
                    // bytes[1:4] -> bytes
                    // array[1:4] -> slice (converted to list)
                    // list[1:4] -> list
                    if (obj_type == .string) {
                        break :blk .{ .string = .slice };
                    } else if (obj_type == .bytes) {
                        // Bytes slicing returns bytes
                        break :blk .bytes;
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
            // Handle builtin type class methods first (float.fromhex, float.hex, etc.)
            if (a.value.* == .name) {
                const name = a.value.name.id;
                if (std.mem.eql(u8, name, "float")) {
                    // float.fromhex and float.hex are callable functions
                    if (std.mem.eql(u8, a.attr, "fromhex") or std.mem.eql(u8, a.attr, "hex")) {
                        break :blk .callable;
                    }
                }
            }

            // Special case: module attributes (sys.platform, math.pi, etc.)
            if (a.value.* == .name) {
                const module_name = a.value.name.id;
                if (ModuleMap.get(module_name)) |mod| {
                    switch (mod) {
                        .sys => {
                            if (SysAttrMap.get(a.attr)) |attr| {
                                switch (attr) {
                                    .platform, .version => break :blk .{ .string = .literal },
                                    .version_info => break :blk .{ .int = .bounded }, // Access like int
                                    .maxsize => break :blk .{ .int = .bounded }, // sys.maxsize uses i128 to allow arithmetic without overflow
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
                            break :blk .{ .int = .bounded };
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

            // ctypes CDLL attribute access - returns a c_func (foreign function pointer)
            if (obj_type == .cdll) {
                const lib_name = obj_type.cdll;
                const func_name_copy = allocator.dupe(u8, a.attr) catch a.attr;
                const lib_copy = allocator.dupe(u8, lib_name) catch lib_name;
                break :blk .{ .c_func = .{ .library = lib_copy, .func_name = func_name_copy } };
            }

            break :blk .unknown;
        },
        .list => |l| blk: {
            // Infer element type by widening across ALL elements
            var elem_type: NativeType = if (l.elts.len > 0)
                try inferExpr(allocator, var_types, class_fields, func_return_types, l.elts[0])
            else
                .unknown;

            // Widen type to accommodate all elements
            if (l.elts.len > 1) {
                for (l.elts[1..]) |elem| {
                    const this_type = try inferExpr(allocator, var_types, class_fields, func_return_types, elem);
                    elem_type = elem_type.widen(this_type);
                }
            }

            // Check if this is a constant, homogeneous list with array-compatible element type
            // → use array type for fixed-size arrays
            if (core.isConstantList(l) and core.allSameType(l.elts)) {
                const elem_tag = @as(std.meta.Tag(NativeType), elem_type);
                // Only use array type if element type is primitive or array (not list/pyvalue)
                if (elem_tag != .list and elem_tag != .pyvalue and elem_tag != .unknown) {
                    const elem_ptr = try allocator.create(NativeType);
                    elem_ptr.* = elem_type;
                    break :blk .{ .array = .{
                        .element_type = elem_ptr,
                        .length = l.elts.len,
                    } };
                }
            }

            // Otherwise, use ArrayList for dynamic lists
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
                    // For dict values, also compare nested dict types fully
                    // e.g., StringHashMap(i64) vs StringHashMap(PyValue) are different
                    if (tag1 == .dict and tag2 == .dict) {
                        const v1_tag = @as(std.meta.Tag(NativeType), val_type.dict.value.*);
                        const v2_tag = @as(std.meta.Tag(NativeType), this_type.dict.value.*);
                        if (v1_tag != v2_tag) {
                            has_mixed_types = true;
                            break;
                        }
                    }
                    // For tuple values, compare lengths and element types deeply
                    // e.g., (list_of_6, list_of_4) vs (list_of_1, list_of_1) are different
                    if (tag1 == .tuple and tag2 == .tuple) {
                        if (val_type.tuple.len != this_type.tuple.len) {
                            has_mixed_types = true;
                            break;
                        }
                        // Check if any element types differ (including nested array lengths)
                        for (val_type.tuple, this_type.tuple) |t1, t2| {
                            if (!typesEqual(t1, t2)) {
                                has_mixed_types = true;
                                break;
                            }
                        }
                    }
                }

                // If mixed types, use PyValue for heterogeneous values
                // (Note: codegen may further refine this if all values are actually string-convertible)
                if (has_mixed_types) {
                    val_type = .pyvalue;
                }

                // Also check for tuples with BigInt elements - these need PyValue at runtime
                if (val_type == .tuple) {
                    for (d.values) |value| {
                        const vt = try inferExpr(allocator, var_types, class_fields, func_return_types, value);
                        if (vt == .tuple) {
                            for (vt.tuple) |elem_type| {
                                if (elem_type == .bigint) {
                                    val_type = .pyvalue;
                                    break;
                                }
                            }
                        }
                        if (val_type == .pyvalue) break;
                    }
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
                            try var_types.put(gen.target.name.id, .{ .int = .bounded });
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
                            try var_types.put(gen.target.name.id, .{ .int = .bounded });
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
        .compare => .bool, // Comparison returns bool
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
                pt.* = .{ .int = .bounded }; // Default to i64
            }
            const return_ptr = try allocator.create(NativeType);
            return_ptr.* = .{ .int = .bounded }; // Default to i64
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
                        break :blk .{ .int = .bounded };
                    }
                    break :blk operand_type;
                },
                .Not => break :blk .bool, // not x always returns bool
                .Invert => {
                    // ~x always returns int - preserve operand's boundedness
                    if (@as(std.meta.Tag(NativeType), operand_type) == .int) {
                        break :blk operand_type; // Preserve boundedness
                    }
                    break :blk .{ .int = .bounded }; // Default to bounded
                },
            }
        },
        .boolop => |boolop| blk: {
            // Python's `a or b` and `a and b` return one of the operands, not a bool
            // Type is the type of the first operand (simplified inference)
            if (boolop.values.len > 0) {
                const first_type = inferExpr(allocator, var_types, class_fields, func_return_types, boolop.values[0]) catch .unknown;
                break :blk first_type;
            }
            break :blk .unknown;
        },
        else => .unknown,
    };
}

/// Infer type from constant literal
fn inferConstant(value: ast.Value) InferError!NativeType {
    return switch (value) {
        .int => .{ .int = .bounded }, // Integer literals are bounded
        .bigint => .bigint, // Large integers are BigInt
        .float => .float,
        .string => .{ .string = .literal }, // String literals are compile-time constants
        .bytes => .bytes, // Bytes literals use PyBytes wrapper
        .bool => .bool,
        .none => .none,
        .complex => .complex, // Complex number literals
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
    return inferBinOpWithInferrer(allocator, var_types, class_fields, func_return_types, binop, null);
}

/// Infer type from binary operation with optional TypeInferrer
fn inferBinOpWithInferrer(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    binop: ast.Node.BinOp,
    type_inferrer: ?*inferrer_mod.TypeInferrer,
) InferError!NativeType {
    const left_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, binop.left.*, type_inferrer);
    const right_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, binop.right.*, type_inferrer);

    // Get type tags for analysis
    const left_tag = @as(std.meta.Tag(NativeType), left_type);
    const right_tag = @as(std.meta.Tag(NativeType), right_type);

    // Large left shift produces BigInt (e.g., 1 << 100000)
    // Also use BigInt when shift amount is runtime (not comptime-known) for safety
    if (binop.op == .LShift) {
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            const shift_amount = binop.right.constant.value.int;
            if (shift_amount >= 63) {
                return .bigint;
            }
        } else {
            // Shift amount is not comptime-known - codegen uses BigInt for safety
            return .bigint;
        }
    }

    // Large power produces BigInt (e.g., 10 ** 30000, 2 ** 1000000)
    if (binop.op == .Pow) {
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            const exp = binop.right.constant.value.int;
            // If exponent is large enough to potentially overflow i64, use bigint
            // log2(i64_max) ≈ 63, so base^exp > 2^63 when exp * log2(base) > 63
            // For simplicity, use bigint if exp >= 20 for any base >= 2
            if (exp >= 20) {
                return .bigint;
            }
        }
    }

    // Helper to check if type needs BigInt (explicit bigint or unbounded int)
    const left_needs_bigint = left_tag == .bigint or
        (left_tag == .int and left_type.int.needsBigInt());
    const right_needs_bigint = right_tag == .bigint or
        (right_tag == .int and right_type.int.needsBigInt());

    // If either operand needs bigint, result is bigint (for arithmetic ops)
    if (left_needs_bigint or right_needs_bigint) {
        if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult or
            binop.op == .FloorDiv or binop.op == .Mod or binop.op == .Pow or
            binop.op == .LShift or binop.op == .RShift or
            binop.op == .BitAnd or binop.op == .BitOr or binop.op == .BitXor)
        {
            return .bigint;
        }
    }

    // Path join: Path / string → Path
    if (binop.op == .Div and left_tag == .path) {
        return .path;
    }

    // String concatenation: str + str → runtime string
    if (binop.op == .Add and left_tag == .string and right_tag == .string) {
        return .{ .string = .runtime }; // Concatenation produces runtime string
    }

    // Bytes concatenation: bytes + bytes → bytes
    if (binop.op == .Add and (left_tag == .bytes or right_tag == .bytes)) {
        return .bytes; // Bytes concatenation produces bytes
    }

    // String repetition: str * int or int * str → runtime string
    // Bytes repetition: bytes * int or int * bytes → bytes
    if (binop.op == .Mult) {
        const left_is_string = left_tag == .string;
        const right_is_string = right_tag == .string;
        const left_is_bytes = left_tag == .bytes;
        const right_is_bytes = right_tag == .bytes;
        const left_is_numeric = left_tag == .int or left_tag == .usize;
        const right_is_numeric = right_tag == .int or right_tag == .usize;

        if ((left_is_string and right_is_numeric) or (left_is_numeric and right_is_string)) {
            return .{ .string = .runtime }; // String repetition produces runtime string
        }
        if ((left_is_bytes and right_is_numeric) or (left_is_numeric and right_is_bytes)) {
            return .bytes; // Bytes repetition produces bytes
        }
    }

    // String formatting: str % value → runtime string (Python % formatting)
    if (binop.op == .Mod and left_tag == .string) {
        return .{ .string = .runtime }; // String formatting produces runtime string
    }

    // Type promotion: int + float → float
    if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult or binop.op == .Div) {
        // Class instances with dunder methods may return class type, not float
        // E.g., Rat.__truediv__ returns Rat, not float
        if (left_tag == .class_instance or right_tag == .class_instance) {
            return .unknown; // Class dunder method - type determined by method return
        }
        if (left_tag == .float or right_tag == .float) {
            return .float; // Any arithmetic with float produces float
        }
        // Python's / operator ALWAYS returns float (true division) for primitives
        if (binop.op == .Div) {
            return .float; // Division always produces float
        }
        // usize mixed with int → result is int, preserving int's boundedness
        if (left_tag == .usize and right_tag == .int) {
            return right_type; // Preserve int's boundedness
        }
        if (left_tag == .int and right_tag == .usize) {
            return left_type; // Preserve int's boundedness
        }
        // usize op usize → usize
        if (left_tag == .usize and right_tag == .usize) {
            return .usize;
        }
        // int op int → combine boundedness (unbounded taints result)
        if (left_tag == .int and right_tag == .int) {
            const combined_kind = left_type.int.combine(right_type.int);
            return .{ .int = combined_kind };
        }
    }

    // Default: use widening logic
    return left_type.widen(right_type);
}
