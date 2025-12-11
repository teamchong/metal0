/// Tuple operations for Python tuple semantics
/// Handles tuple concatenation, multiplication, and repetition
const std = @import("std");

/// Concatenate two tuples (Python tuple + tuple)
/// Returns a new tuple struct with all elements from both tuples
/// Uses comptime to create the correct result type
pub fn tupleConcat(a: anytype, b: anytype) TupleConcatResult(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_fields = @typeInfo(A).@"struct".fields;
    const b_fields = @typeInfo(B).@"struct".fields;
    const Result = TupleConcatResult(A, B);

    // Build result tuple using comptime field initialization
    var result: Result = undefined;
    inline for (a_fields, 0..) |field, i| {
        @field(result, std.fmt.comptimePrint("{d}", .{i})) = @field(a, field.name);
    }
    inline for (b_fields, 0..) |field, i| {
        @field(result, std.fmt.comptimePrint("{d}", .{a_fields.len + i})) = @field(b, field.name);
    }

    return result;
}

/// Helper type for tuple concatenation result
/// Returns an anonymous struct (tuple) type with fields named "0", "1", etc.
pub fn TupleConcatResult(comptime A: type, comptime B: type) type {
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);
    if (a_info != .@"struct" or b_info != .@"struct") {
        @compileError("tupleConcat expects two tuple/struct types");
    }

    const a_fields = a_info.@"struct".fields;
    const b_fields = b_info.@"struct".fields;
    const total_len = a_fields.len + b_fields.len;

    // Build struct field definitions
    var fields: [total_len]std.builtin.Type.StructField = undefined;
    inline for (a_fields, 0..) |afield, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = afield.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(afield.type),
        };
    }
    inline for (b_fields, 0..) |bfield, i| {
        fields[a_fields.len + i] = .{
            .name = std.fmt.comptimePrint("{d}", .{a_fields.len + i}),
            .type = bfield.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(bfield.type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Repeat tuple n times at comptime (Python tuple * n where n is known at compile time)
/// Returns a new tuple struct with elements repeated n times
pub fn tupleMultiply(comptime n: usize, tuple: anytype) TupleMultiplyResult(@TypeOf(tuple), n) {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("tupleMultiply expects a tuple/struct");

    const src_fields = info.@"struct".fields;
    const tuple_len = src_fields.len;
    const Result = TupleMultiplyResult(T, n);

    var result: Result = undefined;
    inline for (0..n) |rep| {
        inline for (src_fields, 0..) |field, i| {
            @field(result, std.fmt.comptimePrint("{d}", .{rep * tuple_len + i})) = @field(tuple, field.name);
        }
    }
    return result;
}

/// Helper type for tuple multiplication result
/// Returns an anonymous struct (tuple) type with fields named "0", "1", etc.
pub fn TupleMultiplyResult(comptime T: type, comptime n: usize) type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("TupleMultiplyResult expects a tuple/struct type");
    const src_fields = info.@"struct".fields;
    const total_len = src_fields.len * n;

    // Build struct field definitions
    var fields: [total_len]std.builtin.Type.StructField = undefined;
    inline for (0..n) |rep| {
        inline for (src_fields, 0..) |sfield, i| {
            fields[rep * src_fields.len + i] = .{
                .name = std.fmt.comptimePrint("{d}", .{rep * src_fields.len + i}),
                .type = sfield.type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(sfield.type),
            };
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Repeat tuple n times (Python tuple * n) - dynamic version
/// Takes a Zig tuple (anonymous struct) and returns a slice with elements repeated
pub fn tupleRepeat(allocator: std.mem.Allocator, tuple: anytype, n: usize) []const @typeInfo(@TypeOf(tuple)).@"struct".fields[0].type {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("tupleRepeat expects a tuple/struct");

    const fields = info.@"struct".fields;
    const tuple_len = fields.len;
    const ElemType = fields[0].type;
    const total_len = tuple_len * n;

    if (n == 0) return &[_]ElemType{};

    const result = allocator.alloc(ElemType, total_len) catch return &[_]ElemType{};
    var idx: usize = 0;
    for (0..n) |_| {
        inline for (fields) |field| {
            result[idx] = @field(tuple, field.name);
            idx += 1;
        }
    }
    return result;
}

/// Repeat list/slice/array n times dynamically (Python list * n with runtime n)
/// Accepts arrays, slices, or pointers to arrays
pub fn sliceRepeatDynamic(allocator: std.mem.Allocator, list: anytype, n: usize) []const getElemType(@TypeOf(list)) {
    const T = @TypeOf(list);
    const ElemType = getElemType(T);

    // Get as slice for uniform handling
    const as_slice: []const ElemType = if (@typeInfo(T) == .array)
        &list
    else if (@typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .array)
        list
    else
        list;

    const list_len = as_slice.len;
    const total_len = list_len * n;

    if (n == 0) return &[_]ElemType{};

    const result = allocator.alloc(ElemType, total_len) catch return &[_]ElemType{};
    for (0..n) |i| {
        @memcpy(result[i * list_len ..][0..list_len], as_slice);
    }
    return result;
}

/// Get element type from array, slice, or pointer to array
pub fn getElemType(comptime T: type) type {
    const info = @typeInfo(T);
    return switch (info) {
        .array => |a| a.child,
        .pointer => |p| switch (@typeInfo(p.child)) {
            .array => |a| a.child,
            else => p.child,
        },
        else => @compileError("Expected array, slice, or pointer to array"),
    };
}
