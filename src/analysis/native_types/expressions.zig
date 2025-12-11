const std = @import("std");
const ast = @import("analysis.ast");
const core = @import("core.zig");
const hashmap_helper = @import("utils.hashmap_helper");
const calls = @import("calls.zig");
const inferrer_mod = @import("inferrer.zig");
const string_traits = @import("../traits/string_traits.zig");
const container_traits = @import("../traits/container_traits.zig");
const type_traits = @import("../traits/type_traits.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const FnvHashMap = hashmap_helper.StringHashMap(NativeType);

/// Parse a type annotation string into a NativeType
/// Supports common Python type hints like "int", "str", "list[int]", etc.
fn parseTypeAnnotation(annotation: []const u8) NativeType {
    // Handle basic types
    if (std.mem.eql(u8, annotation, "int")) return .{ .int = .bounded };
    if (std.mem.eql(u8, annotation, "float")) return .{ .float = {} };
    if (std.mem.eql(u8, annotation, "str")) return .{ .string = .runtime };
    if (std.mem.eql(u8, annotation, "bool")) return .{ .bool = {} };
    if (std.mem.eql(u8, annotation, "bytes")) return .{ .bytes = {} };
    if (std.mem.eql(u8, annotation, "None") or std.mem.eql(u8, annotation, "NoneType")) return .{ .none = {} };
    if (std.mem.eql(u8, annotation, "Any")) return .{ .unknown = {} };

    // Handle generic types like list[int], dict[str, int], etc.
    // For now, return unknown pointer since we can't allocate for element type here
    if (std.mem.startsWith(u8, annotation, "list[")) {
        return .{ .unknown = {} }; // Would need allocator for .list payload
    }
    if (std.mem.startsWith(u8, annotation, "dict[")) {
        return .{ .unknown = {} }; // Would need allocator for .dict payload
    }
    if (std.mem.startsWith(u8, annotation, "set[")) {
        return .{ .unknown = {} }; // Would need allocator for .set payload
    }
    if (std.mem.startsWith(u8, annotation, "tuple[")) {
        return .{ .tuple = &[_]NativeType{} };
    }
    if (std.mem.startsWith(u8, annotation, "Optional[")) {
        return .{ .unknown = {} };
    }
    if (std.mem.startsWith(u8, annotation, "Union[")) {
        return .{ .unknown = {} };
    }
    if (std.mem.startsWith(u8, annotation, "Callable[")) {
        return .{ .callable = {} };
    }

    // Handle List, Dict, Set, Tuple (capitalized versions from typing)
    if (std.mem.eql(u8, annotation, "List") or std.mem.startsWith(u8, annotation, "List[")) {
        return .{ .unknown = {} };
    }
    if (std.mem.eql(u8, annotation, "Dict") or std.mem.startsWith(u8, annotation, "Dict[")) {
        return .{ .unknown = {} };
    }
    if (std.mem.eql(u8, annotation, "Set") or std.mem.startsWith(u8, annotation, "Set[")) {
        return .{ .unknown = {} };
    }
    if (std.mem.eql(u8, annotation, "Tuple") or std.mem.startsWith(u8, annotation, "Tuple[")) {
        return .{ .tuple = &[_]NativeType{} };
    }

    // Unknown type - might be a user-defined class
    return .{ .unknown = {} };
}
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
            // Check scoped variables first if TypeInferrer is available
            // This ensures function-local variables like `result` in `return result` are found
            if (type_inferrer) |ti| {
                if (ti.getScopedVar(n.id)) |scoped_type| {
                    break :blk scoped_type;
                }
            }
            // Check if name is in global var_types
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
            const obj_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, s.value.*, type_inferrer);

            switch (s.slice) {
                .index => |idx| {
                    // Single index access
                    // string[i] -> u8 (but we treat as string for printing)
                    // bytes[i] -> u8 (integer)
                    // list[i] -> element type
                    // dict[key] -> value type
                    // tuple[i] -> element type at index i
                    if (string_traits.isString(obj_type)) {
                        // String indexing returns a single character
                        // For now, treat as string for simplicity
                        break :blk .{ .string = .slice };
                    } else if (string_traits.isBytes(obj_type)) {
                        // Bytes indexing returns a single byte (u8/int)
                        break :blk .{ .int = .bounded };
                    } else if (obj_type == .array) {
                        break :blk obj_type.array.element_type.*;
                    } else if (container_traits.isList(obj_type)) {
                        break :blk obj_type.list.*;
                    } else if (container_traits.isDict(obj_type)) {
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
                    if (string_traits.isString(obj_type)) {
                        break :blk .{ .string = .slice };
                    } else if (string_traits.isBytes(obj_type)) {
                        // Bytes slicing returns bytes
                        break :blk .bytes;
                    } else if (obj_type == .array) {
                        // Array slices become lists (dynamic)
                        break :blk .{ .list = obj_type.array.element_type };
                    } else if (container_traits.isList(obj_type)) {
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
            const obj_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, a.value.*, type_inferrer);

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
                const fnv_hash = @import("utils.fnv_hash");
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

            // http Response attribute access
            if (obj_type == .http_response) {
                if (std.mem.eql(u8, a.attr, "status") or std.mem.eql(u8, a.attr, "status_code")) {
                    break :blk .{ .int = .bounded }; // u16 status code
                }
                if (std.mem.eql(u8, a.attr, "body") or std.mem.eql(u8, a.attr, "text") or std.mem.eql(u8, a.attr, "content")) {
                    break :blk .{ .string = .runtime }; // Response body as string
                }
            }

            break :blk .unknown;
        },
        .list => |l| blk: {
            // Infer element type by widening across ALL elements
            var elem_type: NativeType = if (l.elts.len > 0)
                try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, l.elts[0], type_inferrer)
            else
                .unknown;

            // Widen type to accommodate all elements
            if (l.elts.len > 1) {
                for (l.elts[1..]) |elem| {
                    const this_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, elem, type_inferrer);
                    elem_type = elem_type.widen(this_type);
                }
            }

            // Type inference MUST match codegen output:
            // - Codegen produces array [N]T for: constant, homogeneous, non-nested lists
            // - Codegen produces ArrayList for: everything else
            //
            // Check if list has nested lists (which force ArrayList)
            const has_nested_lists = blk_nested: {
                for (l.elts) |elem| {
                    if (elem == .list) break :blk_nested true;
                }
                break :blk_nested false;
            };

            // Check if this is a constant, homogeneous list eligible for array optimization
            // Must mirror the logic in genList (collections.zig line ~228)
            const is_constant = core.isConstantList(l);
            const is_homogeneous = core.allSameType(l.elts);
            const elem_tag = @as(std.meta.Tag(NativeType), elem_type);
            // Only primitive types (not list/pyvalue/unknown) can be array elements
            const elem_is_primitive = elem_tag != .list and elem_tag != .pyvalue and elem_tag != .unknown;

            // Use array type if: constant, homogeneous, primitive elements, no nested lists
            if (is_constant and is_homogeneous and elem_is_primitive and !has_nested_lists) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = elem_type;
                break :blk .{ .array = .{
                    .element_type = elem_ptr,
                    .length = l.elts.len,
                } };
            }

            // Otherwise use ArrayList
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
                    const unpacked_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, d.values[0], type_inferrer);
                    if (container_traits.isDict(unpacked_type)) {
                        val_type = unpacked_type.dict.value.*;
                    } else {
                        val_type = .unknown;
                    }
                } else {
                    val_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, d.values[0], type_inferrer);
                }

                // Check if all values have same type
                for (d.keys[1..], d.values[1..]) |key, value| {
                    var this_type: NativeType = undefined;
                    if (key == .constant and key.constant.value == .none) {
                        // Dict unpacking
                        const unpacked_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, value, type_inferrer);
                        if (container_traits.isDict(unpacked_type)) {
                            this_type = unpacked_type.dict.value.*;
                        } else {
                            this_type = .unknown;
                        }
                    } else {
                        this_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, value, type_inferrer);
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
                        const vt = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, value, type_inferrer);
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
                    key_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, key, type_inferrer);
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
            // Track loop variables we add so we can restore scope after inference
            // Comprehension variables are scoped and should not affect outer variables
            // Use TypeInferrer's putTempVar/restoreTempVar for proper scoping
            var saved_types: [8]struct { name: []const u8, old_type: ?NativeType } = undefined;
            var saved_count: usize = 0;

            // First, type the loop variables from generators so they're available for elt inference
            for (lc.generators) |gen| {
                if (gen.target.* == .name) {
                    // Check if iterator is range() - gives i64 loop variable
                    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                        const func_name = gen.iter.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "range")) {
                            const var_name = gen.target.name.id;
                            // Use TypeInferrer's temp var system if available, else manual save/restore
                            if (type_inferrer) |ti| {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = ti.putTempVar(var_name, .{ .int = .bounded }) catch null };
                                    saved_count += 1;
                                }
                            } else {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = var_types.get(var_name) };
                                    saved_count += 1;
                                }
                                try var_types.put(var_name, .{ .int = .bounded });
                            }
                        }
                    }
                }
            }

            // Infer element type from the comprehension expression
            var elem_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, lc.elt.*, type_inferrer);

            // Restore original types using TypeInferrer if available
            if (type_inferrer) |ti| {
                for (saved_types[0..saved_count]) |saved| {
                    ti.restoreTempVar(saved.name, saved.old_type);
                }
            } else {
                for (saved_types[0..saved_count]) |saved| {
                    if (saved.old_type) |old| {
                        try var_types.put(saved.name, old);
                    } else {
                        _ = var_types.swapRemove(saved.name);
                    }
                }
            }

            // Lambda elements become closures (Closure0 struct) when stored in lists
            // because each instance captures different values from the loop
            if (lc.elt.* == .lambda) {
                elem_type = .{ .closure = "__ListClosureType" };
            }

            // List comprehensions produce ArrayList(T)
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
        },
        .dictcomp => |dc| blk: {
            // Track loop variables we add so we can restore scope after inference
            // Comprehension variables are scoped and should not affect outer variables
            // Use TypeInferrer's putTempVar/restoreTempVar for proper scoping
            var saved_types: [8]struct { name: []const u8, old_type: ?NativeType } = undefined;
            var saved_count: usize = 0;

            // First, type the loop variables from generators so they're available for key/value inference
            for (dc.generators) |gen| {
                if (gen.target.* == .name) {
                    const var_name = gen.target.name.id;

                    // Check if iterator yields i64 elements:
                    // 1. Direct range() call: for i in range(n)
                    // 2. Starred range in list: for i in [*range(n)]
                    // 3. Starred range in tuple: for i in (*range(n),)
                    // 4. List literal with int elements: for j in [i+1] where i is int
                    const yields_int = yields_int_blk: {
                        // Pattern 1: for i in range(n)
                        if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                            if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
                                break :yields_int_blk true;
                            }
                        }
                        // Pattern 2: for i in [*range(n)]
                        if (gen.iter.* == .list) {
                            const list = gen.iter.list;
                            if (list.elts.len == 1 and list.elts[0] == .starred) {
                                const starred_val = list.elts[0].starred.value;
                                if (starred_val.* == .call and starred_val.call.func.* == .name and
                                    std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                                {
                                    break :yields_int_blk true;
                                }
                            }
                            // Pattern 4: for j in [i+1] - list literal with elements
                            // Infer element type from first element
                            if (list.elts.len > 0 and list.elts[0] != .starred) {
                                const elem_type = inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, list.elts[0], type_inferrer) catch .unknown;
                                if (type_traits.isIntegral(elem_type)) {
                                    break :yields_int_blk true;
                                }
                            }
                        }
                        // Pattern 3: for i in (*range(n),)
                        if (gen.iter.* == .tuple) {
                            const tup = gen.iter.tuple;
                            if (tup.elts.len == 1 and tup.elts[0] == .starred) {
                                const starred_val = tup.elts[0].starred.value;
                                if (starred_val.* == .call and starred_val.call.func.* == .name and
                                    std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                                {
                                    break :yields_int_blk true;
                                }
                            }
                        }
                        break :yields_int_blk false;
                    };

                    if (yields_int) {
                        // Use TypeInferrer's temp var system if available, else manual save/restore
                        if (type_inferrer) |ti| {
                            if (saved_count < saved_types.len) {
                                saved_types[saved_count] = .{ .name = var_name, .old_type = ti.putTempVar(var_name, .{ .int = .bounded }) catch null };
                                saved_count += 1;
                            }
                        } else {
                            if (saved_count < saved_types.len) {
                                saved_types[saved_count] = .{ .name = var_name, .old_type = var_types.get(var_name) };
                                saved_count += 1;
                            }
                            try var_types.put(var_name, .{ .int = .bounded });
                        }
                    }
                }
                // Handle tuple unpacking: for j, k in [(i+1, i+2)]
                else if (gen.target.* == .tuple or gen.target.* == .list) {
                    const target_elts = if (gen.target.* == .tuple) gen.target.tuple.elts else gen.target.list.elts;

                    // Get first element of iterator to infer tuple element types
                    // For [(i+1, i+2)], we infer from (i+1, i+2)
                    if (gen.iter.* == .list and gen.iter.list.elts.len > 0) {
                        const first_elem = gen.iter.list.elts[0];
                        // If first element is a tuple, type each target var from corresponding tuple element
                        if (first_elem == .tuple) {
                            const tuple_elts = first_elem.tuple.elts;
                            for (target_elts, 0..) |target_elt, idx| {
                                if (target_elt == .name and idx < tuple_elts.len) {
                                    const t_var_name = target_elt.name.id;
                                    const elem_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, tuple_elts[idx], type_inferrer);
                                    const loop_var_type: NativeType = if (type_traits.isIntegral(elem_type))
                                        .{ .int = .bounded }
                                    else
                                        elem_type;

                                    if (type_inferrer) |ti| {
                                        if (saved_count < saved_types.len) {
                                            saved_types[saved_count] = .{ .name = t_var_name, .old_type = ti.putTempVar(t_var_name, loop_var_type) catch null };
                                            saved_count += 1;
                                        }
                                    } else {
                                        if (saved_count < saved_types.len) {
                                            saved_types[saved_count] = .{ .name = t_var_name, .old_type = var_types.get(t_var_name) };
                                            saved_count += 1;
                                        }
                                        try var_types.put(t_var_name, loop_var_type);
                                    }
                                }
                            }
                        }
                    }
                    // Handle zip() unpacking: for k, v in zip(list1, list2)
                    // Type each target variable from the corresponding zip argument's element type
                    else if (gen.iter.* == .call and gen.iter.call.func.* == .name and
                        std.mem.eql(u8, gen.iter.call.func.name.id, "zip"))
                    {
                        for (gen.iter.call.args, 0..) |arg, idx| {
                            if (idx < target_elts.len and target_elts[idx] == .name) {
                                const t_var_name = target_elts[idx].name.id;
                                // Infer element type from the zip argument
                                const arg_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, arg, type_inferrer);
                                const elem_type: NativeType = switch (arg_type) {
                                    .list => |l| l.*,
                                    .array => |a| a.element_type.*,
                                    // Iterating over a string yields single-char strings (u8 in Zig)
                                    .string => .{ .int = .bounded },
                                    .bytes => .{ .int = .bounded },
                                    else => .unknown,
                                };

                                if (type_inferrer) |ti| {
                                    if (saved_count < saved_types.len) {
                                        saved_types[saved_count] = .{ .name = t_var_name, .old_type = ti.putTempVar(t_var_name, elem_type) catch null };
                                        saved_count += 1;
                                    }
                                } else {
                                    if (saved_count < saved_types.len) {
                                        saved_types[saved_count] = .{ .name = t_var_name, .old_type = var_types.get(t_var_name) };
                                        saved_count += 1;
                                    }
                                    try var_types.put(t_var_name, elem_type);
                                }
                            }
                        }
                    }
                }
            }

            // Infer types from key and value expressions
            const key_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, dc.key.*, type_inferrer);
            const val_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, dc.value.*, type_inferrer);

            // Restore original types using TypeInferrer if available
            if (type_inferrer) |ti| {
                for (saved_types[0..saved_count]) |saved| {
                    ti.restoreTempVar(saved.name, saved.old_type);
                }
            } else {
                for (saved_types[0..saved_count]) |saved| {
                    if (saved.old_type) |old| {
                        try var_types.put(saved.name, old);
                    } else {
                        _ = var_types.swapRemove(saved.name);
                    }
                }
            }

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
                try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, s.elts[0], type_inferrer)
            else
                .unknown;

            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .set = elem_ptr };
        },
        .genexp => |ge| blk: {
            // Track loop variables we add so we can restore scope after inference
            // Comprehension variables are scoped and should not affect outer variables
            // Use TypeInferrer's putTempVar/restoreTempVar for proper scoping
            var saved_types: [8]struct { name: []const u8, old_type: ?NativeType } = undefined;
            var saved_count: usize = 0;

            // Generator expressions are treated as list comprehensions (eager evaluation)
            // First, type the loop variables from generators so they're available for elt inference
            for (ge.generators) |gen| {
                if (gen.target.* == .name) {
                    const var_name = gen.target.name.id;
                    // Check if iterator is range() - gives i64 loop variable
                    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                        const func_name = gen.iter.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "range")) {
                            // Use TypeInferrer's temp var system if available, else manual save/restore
                            if (type_inferrer) |ti| {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = ti.putTempVar(var_name, .{ .int = .bounded }) catch null };
                                    saved_count += 1;
                                }
                            } else {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = var_types.get(var_name) };
                                    saved_count += 1;
                                }
                                try var_types.put(var_name, .{ .int = .bounded });
                            }
                        }
                    }
                    // Check if iterator is a list/array variable - loop var gets element type
                    if (gen.iter.* == .name) {
                        const iter_name = gen.iter.name.id;
                        if (var_types.get(iter_name)) |iter_type| {
                            const elem_type_inner: NativeType = switch (iter_type) {
                                .list => |elem| elem.*,
                                .array => |arr| arr.element_type.*,
                                else => NativeType{ .int = .bounded },
                            };
                            // Use TypeInferrer's temp var system if available, else manual save/restore
                            if (type_inferrer) |ti| {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = ti.putTempVar(var_name, elem_type_inner) catch null };
                                    saved_count += 1;
                                }
                            } else {
                                if (saved_count < saved_types.len) {
                                    saved_types[saved_count] = .{ .name = var_name, .old_type = var_types.get(var_name) };
                                    saved_count += 1;
                                }
                                try var_types.put(var_name, elem_type_inner);
                            }
                        }
                    }
                }
            }

            // Infer element type from the generator expression
            const elem_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, ge.elt.*, type_inferrer);

            // Restore original types using TypeInferrer if available
            if (type_inferrer) |ti| {
                for (saved_types[0..saved_count]) |saved| {
                    ti.restoreTempVar(saved.name, saved.old_type);
                }
            } else {
                for (saved_types[0..saved_count]) |saved| {
                    if (saved.old_type) |old| {
                        try var_types.put(saved.name, old);
                    } else {
                        _ = var_types.swapRemove(saved.name);
                    }
                }
            }

            // Generator expressions produce ArrayList(T) (evaluated eagerly in AOT compilation)
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = elem_type;
            break :blk .{ .list = elem_ptr };
        },
        .tuple => |t| blk: {
            // Infer types of all tuple elements
            var elem_types = try allocator.alloc(NativeType, t.elts.len);
            for (t.elts, 0..) |elt, i| {
                elem_types[i] = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, elt, type_inferrer);
            }
            break :blk .{ .tuple = elem_types };
        },
        .compare => .bool, // Comparison returns bool
        .named_expr => |ne| blk: {
            // Named expression (walrus operator): (x := value)
            // The type of the named expression is the type of the value
            break :blk try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, ne.value.*, type_inferrer);
        },
        .if_expr => |ie| blk: {
            // Conditional expression (ternary): body if condition else orelse_value
            // Return the wider type of body and orelse_value (they should match in Python)
            const body_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, ie.body.*, type_inferrer);
            const orelse_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, ie.orelse_value.*, type_inferrer);
            break :blk body_type.widen(orelse_type);
        },
        .lambda => |lam| blk: {
            // Infer function type from lambda
            // 1. Parameter types from annotations, or default to unknown
            const param_types = try allocator.alloc(NativeType, lam.args.len);
            for (lam.args, 0..) |arg, i| {
                if (arg.type_annotation) |annotation| {
                    // Parse type annotation string
                    param_types[i] = parseTypeAnnotation(annotation);
                } else {
                    // Without annotation, infer from common patterns or default to unknown
                    param_types[i] = .unknown;
                }
            }

            // 2. Return type from lambda body expression
            // Create temporary scope with param types for inference
            var temp_var_types = hashmap_helper.StringHashMap(NativeType).init(allocator);
            defer temp_var_types.deinit();

            // Add param types to temp scope
            for (lam.args, 0..) |arg, i| {
                temp_var_types.put(arg.name, param_types[i]) catch {};
            }

            // Infer body type with params in scope
            const body_type = inferExprWithInferrer(allocator, &temp_var_types, class_fields, func_return_types, lam.body.*, type_inferrer) catch .unknown;

            const return_ptr = try allocator.create(NativeType);
            return_ptr.* = body_type;

            break :blk .{ .function = .{
                .params = param_types,
                .return_type = return_ptr,
            } };
        },
        .unaryop => |u| blk: {
            const operand_type = try inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, u.operand.*, type_inferrer);
            // In Python, +bool and -bool convert to int
            switch (u.op) {
                .UAdd, .USub => {
                    if (type_traits.isBoolean(operand_type)) {
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
                const first_type = inferExprWithInferrer(allocator, var_types, class_fields, func_return_types, boolop.values[0], type_inferrer) catch .unknown;
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

    // Get type tags for special cases not handled by trait
    const left_tag = @as(std.meta.Tag(NativeType), left_type);
    const right_tag = @as(std.meta.Tag(NativeType), right_type);

    // Class instances with dunder methods may return class type, not standard result
    // E.g., Rat.__truediv__ returns Rat, not float - must be handled before trait
    if (left_tag == .class_instance or right_tag == .class_instance) {
        if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult or binop.op == .Div) {
            // If both operands are the SAME class type, assume result is also that class
            // This handles common patterns like: Rat + Rat -> Rat
            if (left_tag == .class_instance and right_tag == .class_instance) {
                const left_class = left_type.class_instance;
                const right_class = right_type.class_instance;
                if (std.mem.eql(u8, left_class, right_class)) {
                    return left_type; // Same class, return same type
                }
            }
            // Mixed class types or class + primitive: fall back to unknown
            return .unknown;
        }
    }

    // Build operation hints from AST for comptime-known values
    var hints: type_traits.OperationHints = .{};

    // Extract shift amount for LShift if comptime-known
    if (binop.op == .LShift) {
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            hints.shift_amount = binop.right.constant.value.int;
        }
        // If shift_amount is null, trait will return bigint for safety
    }

    // Extract exponent for Pow if comptime-known
    if (binop.op == .Pow) {
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            hints.exponent = binop.right.constant.value.int;
        }
    }

    // Convert AST op to trait BinOp
    const trait_op: type_traits.BinOp = switch (binop.op) {
        .Add => .Add,
        .Sub => .Sub,
        .Mult => .Mult,
        .Div => .Div,
        .FloorDiv => .FloorDiv,
        .Mod => .Mod,
        .Pow => .Pow,
        .BitAnd => .BitAnd,
        .BitOr => .BitOr,
        .BitXor => .BitXor,
        .LShift => .LShift,
        .RShift => .RShift,
        else => return left_type.widen(right_type), // Comparison ops etc use widening
    };

    // Use centralized trait for type inference
    const trait_result = type_traits.binaryResultTypeWithHints(trait_op, left_type, right_type, hints);

    // If trait returned a concrete type, use it
    if (trait_result != .unknown) {
        return trait_result;
    }

    // Special case: usize mixed with int preserves int's boundedness
    if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult) {
        if (left_tag == .usize and right_tag == .int) {
            return right_type;
        }
        if (left_tag == .int and right_tag == .usize) {
            return left_type;
        }
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
