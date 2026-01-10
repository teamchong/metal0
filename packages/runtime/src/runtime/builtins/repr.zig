/// String representation functions (repr, str, etc.)
const std = @import("std");
const cpython = @import("../../cpython.zig");
const PyValue = @import("../../Objects/object.zig").PyValue;
const PyException = @import("../exceptions.zig").PyException;
const type_predicates = @import("../type_predicates.zig");

/// MultidimensionalView - Represents a memoryview with ndim > 1
/// This type is intentionally NOT compatible with []const u8 so that
/// passing it to functions expecting bytes will cause a compile error
/// (which assertRaises tests expect as TypeError)
pub const MultidimensionalView = struct {
    data: []const u8,
    format: []const u8,
    ndim: usize,

    /// Get underlying data (flattened)
    pub fn tobytes(self: MultidimensionalView) []const u8 {
        return self.data;
    }
};

/// PyBytes - Wrapper for Python bytes type
/// Preserves type information for repr() to correctly output b'...' format
pub const PyBytes = struct {
    data: []const u8,

    pub fn init(data: []const u8) PyBytes {
        return PyBytes{ .data = data };
    }

    /// Get the underlying data slice
    pub fn slice(self: PyBytes) []const u8 {
        return self.data;
    }

    /// Length of the bytes
    pub fn len(self: PyBytes) usize {
        return self.data.len;
    }

    /// Concatenate two PyBytes (allocates)
    pub fn concat(allocator: std.mem.Allocator, a: PyBytes, b: PyBytes) !PyBytes {
        const result = try allocator.alloc(u8, a.data.len + b.data.len);
        @memcpy(result[0..a.data.len], a.data);
        @memcpy(result[a.data.len..], b.data);
        return PyBytes{ .data = result };
    }

    /// Repeat bytes n times (allocates)
    pub fn repeat(allocator: std.mem.Allocator, self: PyBytes, n: usize) !PyBytes {
        if (n == 0) return PyBytes{ .data = "" };
        const result = try allocator.alloc(u8, self.data.len * n);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            @memcpy(result[i * self.data.len .. (i + 1) * self.data.len], self.data);
        }
        return PyBytes{ .data = result };
    }

    /// Create zero-filled bytes of length n (allocates)
    /// Used for bytes(n) constructor where n is an integer
    pub fn zeros(allocator: std.mem.Allocator, n: anytype) !PyBytes {
        const size: usize = @intCast(n);
        const result = try allocator.alloc(u8, size);
        @memset(result, 0);
        return PyBytes{ .data = result };
    }

    /// Slice bytes [start:end]
    pub fn sliceRange(self: PyBytes, start: usize, end: usize) PyBytes {
        const actual_end = @min(end, self.data.len);
        const actual_start = @min(start, actual_end);
        return PyBytes{ .data = self.data[actual_start..actual_end] };
    }

    /// Cast memoryview to different format (1D) - single arg version
    /// Returns MultidimensionalView which is not compatible with []const u8
    pub fn cast(self: PyBytes, format: []const u8) MultidimensionalView {
        return MultidimensionalView{
            .data = self.data,
            .format = format,
            .ndim = 1,
        };
    }

    /// Cast memoryview to different format/shape (multi-dimensional) - two arg version
    /// Returns MultidimensionalView which is not compatible with []const u8
    pub fn cast2(self: PyBytes, format: []const u8, shape: anytype) MultidimensionalView {
        return MultidimensionalView{
            .data = self.data,
            .format = format,
            .ndim = @intCast(std.meta.fields(@TypeOf(shape)).len),
        };
    }

    /// Index into bytes
    pub fn get(self: PyBytes, index: usize) u8 {
        return self.data[index];
    }

    /// Iterator support
    pub fn iterator(self: PyBytes) []const u8 {
        return self.data;
    }

    /// Extend bytearray with bytes from iterable (mutates in place)
    /// Note: For bytearray compatibility only (bytes are immutable in Python)
    pub fn extend(self: *PyBytes, allocator: std.mem.Allocator, iterable: anytype) !void {
        const IterType = @TypeOf(iterable);

        // Collect bytes to append
        var to_append = std.ArrayList(u8).init(allocator);
        defer to_append.deinit();

        if (@hasDecl(IterType, "__iter__")) {
            // Custom iterable with __iter__
            const iter_result = try iterable.__iter__();
            for (iter_result) |item| {
                try to_append.append(@intCast(item));
            }
        } else if (@hasField(IterType, "data")) {
            // Another PyBytes
            try to_append.appendSlice(iterable.data);
        } else {
            // Direct iteration
            for (iterable) |item| {
                try to_append.append(@intCast(item));
            }
        }

        // Allocate new buffer with combined data
        const new_data = try allocator.alloc(u8, self.data.len + to_append.items.len);
        @memcpy(new_data[0..self.data.len], self.data);
        @memcpy(new_data[self.data.len..], to_append.items);

        // Update self.data
        self.data = new_data;
    }
};

/// Create a bytes literal - preserves Python bytes type for repr()
pub fn bytesLiteral(data: []const u8) PyBytes {
    return PyBytes.init(data);
}

/// Create a string literal - returns raw slice (no wrapper needed for strings)
pub fn strLiteral(data: []const u8) []const u8 {
    return data;
}

/// Extract bytes data from either PyBytes or []const u8
/// This is a generic helper for codegen that handles both cases
pub fn extractBytesData(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == PyBytes) {
        return value.data;
    } else if (T == []const u8) {
        return value;
    } else if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
        // Pointer to array (e.g., *const [5]u8)
        return value[0..];
    } else {
        // Assume it's an array type
        return &value;
    }
}

/// Format bytes as Python bytes repr: b'...' with non-printable bytes escaped
pub fn bytesRepr(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "b'");

    for (data) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\\' and byte != '\'') {
            try buf.append(allocator, byte);
        } else if (byte == '\\') {
            try buf.appendSlice(allocator, "\\\\");
        } else if (byte == '\'') {
            try buf.appendSlice(allocator, "\\'");
        } else if (byte == '\n') {
            try buf.appendSlice(allocator, "\\n");
        } else if (byte == '\r') {
            try buf.appendSlice(allocator, "\\r");
        } else if (byte == '\t') {
            try buf.appendSlice(allocator, "\\t");
        } else {
            try buf.appendSlice(allocator, "\\x");
            const hex_chars = "0123456789abcdef";
            try buf.append(allocator, hex_chars[byte >> 4]);
            try buf.append(allocator, hex_chars[byte & 0xf]);
        }
    }

    try buf.append(allocator, '\'');
    return buf.toOwnedSlice(allocator);
}

/// Python string repr - wraps in quotes and escapes non-printable characters
pub fn stringRepr(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    try buf.append(allocator, '\'');

    for (data) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\\' and byte != '\'') {
            try buf.append(allocator, byte);
        } else if (byte == '\\') {
            try buf.appendSlice(allocator, "\\\\");
        } else if (byte == '\'') {
            try buf.appendSlice(allocator, "\\'");
        } else if (byte == '\n') {
            try buf.appendSlice(allocator, "\\n");
        } else if (byte == '\r') {
            try buf.appendSlice(allocator, "\\r");
        } else if (byte == '\t') {
            try buf.appendSlice(allocator, "\\t");
        } else {
            try buf.appendSlice(allocator, "\\x");
            const hex_chars = "0123456789abcdef";
            try buf.append(allocator, hex_chars[byte >> 4]);
            try buf.append(allocator, hex_chars[byte & 0xf]);
        }
    }

    try buf.append(allocator, '\'');
    return buf.toOwnedSlice(allocator);
}

/// Python-compatible float repr/str
fn pythonFloatRepr(allocator: std.mem.Allocator, value: f64) ![]const u8 {
    if (std.math.isNan(value)) {
        return "nan";
    }
    if (std.math.isInf(value)) {
        return if (value < 0) "-inf" else "inf";
    }

    const abs_value = @abs(value);
    const use_scientific = value != 0 and (abs_value >= 1e16 or abs_value < 1e-4);

    if (use_scientific) {
        const formatted = try std.fmt.allocPrint(allocator, "{e}", .{value});
        var result = std.ArrayListUnmanaged(u8){};
        var i: usize = 0;
        while (i < formatted.len) : (i += 1) {
            try result.append(allocator, formatted[i]);
            if (formatted[i] == 'e' and i + 1 < formatted.len) {
                const next_char = formatted[i + 1];
                if (next_char == '-') {
                    try result.append(allocator, '-');
                    i += 1;
                    const exp_start = i + 1;
                    const exp_len = formatted.len - exp_start;
                    if (exp_len == 1) {
                        try result.append(allocator, '0');
                    }
                } else if (std.ascii.isDigit(next_char)) {
                    try result.append(allocator, '+');
                    const exp_len = formatted.len - (i + 1);
                    if (exp_len == 1) {
                        try result.append(allocator, '0');
                    }
                }
            }
        }
        allocator.free(formatted);
        return result.toOwnedSlice(allocator);
    }

    const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value});

    var has_decimal = false;
    var has_exponent = false;
    var decimal_pos: usize = 0;
    for (formatted, 0..) |c, i| {
        if (c == '.') {
            has_decimal = true;
            decimal_pos = i;
        }
        if (c == 'e' or c == 'E') has_exponent = true;
    }

    if (!has_decimal and !has_exponent) {
        var result = std.ArrayListUnmanaged(u8){};
        try result.appendSlice(allocator, formatted);
        try result.appendSlice(allocator, ".0");
        allocator.free(formatted);
        return result.toOwnedSlice(allocator);
    }

    if (has_decimal and !has_exponent) {
        var end = formatted.len;
        while (end > decimal_pos + 2 and formatted[end - 1] == '0') {
            end -= 1;
        }
        if (end < formatted.len) {
            const trimmed = try allocator.dupe(u8, formatted[0..end]);
            allocator.free(formatted);
            return trimmed;
        }
    }

    return formatted;
}

/// Helper to check if type is a pointer to u8 array (string literal type)
fn isStringPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            if (p.size != .one) break :blk false;
            const child = p.child;
            break :blk switch (@typeInfo(child)) {
                .array => |arr| arr.child == u8,
                else => false,
            };
        },
        else => false,
    };
}

/// Convert a value to its repr string (for tuple elements)
pub fn valueRepr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    // PyValue - handle all variants
    if (T == PyValue) {
        return switch (value) {
            .string => |s| stringRepr(allocator, s),
            .int => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| pythonFloatRepr(allocator, f),
            .bool => |b| if (b) "True" else "False",
            .none => "None",
            .not_implemented => "NotImplemented",
            .list => |list| std.fmt.allocPrint(allocator, "[<{d} items>]", .{list.items.len}),
            .tuple => |tup| std.fmt.allocPrint(allocator, "(<{d} items>)", .{tup.len}),
            .bigint => |bi| std.fmt.allocPrint(allocator, "{d}", .{bi}),
            .complex => |c| blk: {
                if (c.real == 0) break :blk std.fmt.allocPrint(allocator, "{d}j", .{c.imag});
                break :blk std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ c.real, c.imag });
            },
            .bytes => |b| bytesRepr(allocator, b.data),
            .type_obj => |t| std.fmt.allocPrint(allocator, "<class '{s}'>", .{t.name}),
            .object => |obj| blk: {
                if (obj.vtable.class_name) |name| {
                    break :blk std.fmt.allocPrint(allocator, "<{s} instance>", .{name});
                }
                break :blk "<object instance>";
            },
            .pylist => |pylist| blk: {
                const size: usize = @intCast(pylist.ob_base.ob_size);
                break :blk std.fmt.allocPrint(allocator, "[<{d} items>]", .{size});
            },
            .ptr => "<PyObject>",
            // VM-specific types
            .dict => |d| std.fmt.allocPrint(allocator, "{{<{d} items>}}", .{d.count()}),
            .code => |c| std.fmt.allocPrint(allocator, "<code object '{s}'>", .{c.name}),
            .function => |f| std.fmt.allocPrint(allocator, "<function '{s}'>", .{f.code.name}),
            .builtin_fn => "<built-in function>",
            .iterator => "<iterator>",
            .range => |r| std.fmt.allocPrint(allocator, "range({d}, {d}, {d})", .{ r.start, r.stop, r.step }),
            .exception => |e| std.fmt.allocPrint(allocator, "{s}('{s}')", .{ e.exc_type, e.message }),
            .generator => "<generator object>",
        };
    }

    // PyBytes - format as b'...'
    if (T == PyBytes or (@typeInfo(T) == .@"struct" and @hasField(T, "data") and @hasDecl(T, "slice"))) {
        return bytesRepr(allocator, value.data);
    }

    // String slices
    if (T == []const u8 or T == []u8) {
        return stringRepr(allocator, value);
    }
    if (comptime isStringPointer(T)) {
        const slice: []const u8 = value;
        return stringRepr(allocator, slice);
    }

    // Bool
    if (T == bool) {
        return if (value) "True" else "False";
    }

    // Integer
    if (type_predicates.isInt(T)) {
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }

    // Float
    if (type_predicates.isFloat(T)) {
        return pythonFloatRepr(allocator, value);
    }

    // Nested tuple/struct
    if (@typeInfo(T) == .@"struct") {
        return tupleRepr(allocator, value);
    }

    // Slice - format as tuple
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        return sliceAsTupleRepr(allocator, value);
    }

    // CPython PyObject pointer - extract value and format appropriately
    if (T == *cpython.PyObject) {
        if (cpython.PyFloat_Check(value)) {
            const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(value));
            return pythonFloatRepr(allocator, float_obj.ob_fval);
        } else if (cpython.PyLong_Check(value)) {
            const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(value));
            return std.fmt.allocPrint(allocator, "{d}", .{int_obj.getValue()});
        } else if (cpython.PyBool_Check(value)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(value));
            return if (bool_obj.getValue()) "True" else "False";
        } else if (cpython.PyUnicode_Check(value)) {
            const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(value));
            const len: usize = @intCast(str_obj.length);
            return stringRepr(allocator, str_obj.data[0..len]);
        }
        return std.fmt.allocPrint(allocator, "<PyObject@{*}>", .{value});
    }

    // Fallback
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

/// Format a slice as a Python tuple: (a, b, c) or (a,) for single element
fn sliceAsTupleRepr(allocator: std.mem.Allocator, slice: anytype) ![]const u8 {
    if (slice.len == 0) return "()";

    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '(');

    for (slice, 0..) |elem, i| {
        const elem_str = try valueRepr(allocator, elem);
        try result.appendSlice(allocator, elem_str);

        if (i < slice.len - 1) {
            try result.appendSlice(allocator, ", ");
        } else if (slice.len == 1) {
            try result.append(allocator, ',');
        }
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

/// Python-compatible tuple repr
pub fn tupleRepr(allocator: std.mem.Allocator, tup: anytype) ![]const u8 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return "()";

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    if (num_fields == 0) return "()";

    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '(');

    inline for (fields, 0..) |field, i| {
        const elem = @field(tup, field.name);
        const elem_str = try valueRepr(allocator, elem);
        try result.appendSlice(allocator, elem_str);

        if (i < num_fields - 1) {
            try result.appendSlice(allocator, ", ");
        } else if (num_fields == 1) {
            try result.append(allocator, ',');
        }
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

/// Python-compatible repr for any value
pub fn pyRepr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return valueRepr(allocator, value);
}

/// Convert a value to its str string (without extra quotes on strings)
pub fn valueStr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    // PyValue - handle all variants
    if (T == PyValue) {
        return switch (value) {
            .string => |s| s,
            .int => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| pythonFloatRepr(allocator, f),
            .bool => |b| if (b) "True" else "False",
            .none => "None",
            .not_implemented => "NotImplemented",
            .list => |list| std.fmt.allocPrint(allocator, "[<{d} items>]", .{list.items.len}),
            .tuple => |tup| std.fmt.allocPrint(allocator, "(<{d} items>)", .{tup.len}),
            .bigint => |bi| std.fmt.allocPrint(allocator, "{d}", .{bi}),
            .complex => |c| blk: {
                if (c.real == 0) break :blk std.fmt.allocPrint(allocator, "{d}j", .{c.imag});
                break :blk std.fmt.allocPrint(allocator, "({d}+{d}j)", .{ c.real, c.imag });
            },
            .bytes => |b| blk: {
                break :blk std.fmt.allocPrint(allocator, "b'{s}'", .{b.data});
            },
            .type_obj => |t| std.fmt.allocPrint(allocator, "<class '{s}'>", .{t.name}),
            .object => |obj| blk: {
                if (obj.vtable.class_name) |name| {
                    break :blk std.fmt.allocPrint(allocator, "<{s} instance>", .{name});
                }
                break :blk "<object instance>";
            },
            .pylist => |pylist| blk: {
                const size: usize = @intCast(pylist.ob_base.ob_size);
                break :blk std.fmt.allocPrint(allocator, "[<{d} items>]", .{size});
            },
            .ptr => "<PyObject>",
            // VM-specific types (SINGLE SOURCE OF TRUTH - must match valueRepr and PyValue.format)
            .dict => |d| std.fmt.allocPrint(allocator, "{{<{d} items>}}", .{d.count()}),
            .code => |c| std.fmt.allocPrint(allocator, "<code object '{s}'>", .{c.name}),
            .function => |f| std.fmt.allocPrint(allocator, "<function '{s}'>", .{f.code.name}),
            .builtin_fn => "<built-in function>",
            .iterator => "<iterator>",
            .range => |r| std.fmt.allocPrint(allocator, "range({d}, {d}, {d})", .{ r.start, r.stop, r.step }),
            .exception => |e| std.fmt.allocPrint(allocator, "{s}('{s}')", .{ e.exc_type, e.message }),
            .generator => "<generator object>",
        };
    }

    // PyException - return just the message (like Python's str(e))
    if (T == PyException) {
        return value.message;
    }

    // String - no wrapping quotes
    if (T == []const u8 or T == []u8) {
        return value;
    }

    // Bool
    if (T == bool) {
        return if (value) "True" else "False";
    }

    // Integer
    if (type_predicates.isInt(T)) {
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }

    // Float
    if (type_predicates.isFloat(T)) {
        return pythonFloatRepr(allocator, value);
    }

    // Struct with toStr method
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toStr")) {
        return value.toStr(allocator);
    }

    // Tuple/struct
    if (@typeInfo(T) == .@"struct") {
        return tupleRepr(allocator, value);
    }

    // Slice
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        return sliceAsTupleRepr(allocator, value);
    }

    // Pointer to struct with __base_value__
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
        const child_type = @typeInfo(T).pointer.child;
        if (@typeInfo(child_type) == .@"struct") {
            if (@hasDecl(child_type, "__str__")) {
                return value.__str__(allocator);
            }
            if (@hasField(child_type, "__base_value__")) {
                const base_val = value.__base_value__;
                return valueStr(allocator, base_val);
            }
        }
    }

    // Fallback
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

/// Python-compatible str for any value
pub fn pyStr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return valueStr(allocator, value);
}
