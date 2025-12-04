/// Builtin and complex parent type definitions for class inheritance
const std = @import("std");

/// Builtin types that can be inherited from
pub const BuiltinBaseInfo = struct {
    zig_type: []const u8,
    zig_init: []const u8,
    init_args: []const InitArg,

    pub const InitArg = struct {
        name: []const u8,
        zig_type: []const u8,
        default: ?[]const u8 = null,
    };
};

/// Get builtin base info if the class inherits from a builtin type
pub fn getBuiltinBaseInfo(base_name: []const u8) ?BuiltinBaseInfo {
    return builtin_bases.get(base_name);
}

const B = BuiltinBaseInfo;
const A = B.InitArg;
const builtin_bases = std.StaticStringMap(B).initComptime(.{
    .{ "complex", B{ .zig_type = "runtime.PyComplex", .zig_init = "runtime.PyComplex.create(real, imag)", .init_args = &[_]A{
        .{ .name = "real", .zig_type = "f64", .default = "0.0" },
        .{ .name = "imag", .zig_type = "f64", .default = "0.0" },
    } } },
    .{ "int", B{ .zig_type = "i64", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "i64", .default = "0" },
    } } },
    .{ "float", B{ .zig_type = "f64", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "f64", .default = "0.0" },
    } } },
    .{ "str", B{ .zig_type = "[]const u8", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "[]const u8", .default = "\"\"" },
    } } },
    .{ "bool", B{ .zig_type = "bool", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "bool", .default = "false" },
    } } },
    .{ "bytes", B{ .zig_type = "[]const u8", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "[]const u8", .default = "\"\"" },
    } } },
    .{ "bytearray", B{ .zig_type = "[]const u8", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "[]const u8", .default = "\"\"" },
    } } },
    // dict subclass - stores the dict value as PyValue (caller passes PyValue from fromAlloc)
    .{ "dict", B{ .zig_type = "runtime.PyValue", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "runtime.PyValue", .default = ".{ .list = &[_]runtime.PyValue{} }" },
    } } },
    // list subclass - stores the list value as PyValue (caller passes PyValue from fromAlloc)
    .{ "list", B{ .zig_type = "runtime.PyValue", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "runtime.PyValue", .default = ".{ .list = &[_]runtime.PyValue{} }" },
    } } },
    // tuple subclass - stores the tuple value as PyValue (caller passes PyValue from fromAlloc)
    .{ "tuple", B{ .zig_type = "runtime.PyValue", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "runtime.PyValue", .default = ".{ .tuple = &[_]runtime.PyValue{} }" },
    } } },
    // set subclass - stores the set value as PyValue (caller passes PyValue from fromAlloc)
    .{ "set", B{ .zig_type = "runtime.PyValue", .zig_init = "__value", .init_args = &[_]A{
        .{ .name = "__value", .zig_type = "runtime.PyValue", .default = ".{ .list = &[_]runtime.PyValue{} }" },
    } } },
});

/// Complex parent types with multiple fields (like array.array)
pub const ComplexParentInfo = struct {
    fields: []const FieldInfo,
    methods: []const MethodInfo,
    init_args: []const InitArg,
    field_init: []const FieldInit,

    pub const FieldInfo = struct { name: []const u8, zig_type: []const u8, default: []const u8 };
    pub const MethodInfo = struct { name: []const u8, inline_code: []const u8 };
    pub const InitArg = struct { name: []const u8, zig_type: []const u8 };
    pub const FieldInit = struct { field_name: []const u8, init_code: []const u8 };
};

/// Get complex parent info for module.class patterns
pub fn getComplexParentInfo(base_name: []const u8) ?ComplexParentInfo {
    return complex_parents.get(base_name);
}

const C = ComplexParentInfo;
const complex_parents = std.StaticStringMap(C).initComptime(.{
    .{ "array.array", C{
        .fields = &[_]C.FieldInfo{
            .{ .name = "typecode", .zig_type = "u8", .default = "'l'" },
            .{ .name = "__array_items", .zig_type = "std.ArrayList(i64)", .default = "std.ArrayList(i64){}" },
        },
        .methods = &[_]C.MethodInfo{
            .{ .name = "__getitem__", .inline_code = "{self}.__array_items.items[@as(usize, @intCast({0}))]" },
            .{ .name = "__setitem__", .inline_code = "{self}.__array_items.items[@as(usize, @intCast({0}))] = {1}" },
            .{ .name = "__len__", .inline_code = "{self}.__array_items.items.len" },
            .{ .name = "append", .inline_code = "try {self}.__array_items.append(__global_allocator, {0})" },
        },
        .init_args = &[_]C.InitArg{
            .{ .name = "typecode", .zig_type = "u8" },
            .{ .name = "data", .zig_type = "[]const i64" },
        },
        .field_init = &[_]C.FieldInit{
            .{ .field_name = "typecode", .init_code = "typecode" },
            .{ .field_name = "__array_items", .init_code = "blk: { var arr = std.ArrayList(i64){}; arr.appendSlice({alloc}, data) catch {}; break :blk arr; }" },
        },
    } },
});
