/// Built-in Python functions implemented in Zig
const std = @import("std");
const runtime_core = @import("../runtime.zig");
const pyint = @import("../Objects/intobject.zig");
const pylist = @import("../Objects/listobject.zig");
const pystring = @import("../Objects/unicodeobject.zig");
const pytuple = @import("../Objects/tupleobject.zig");
const dict_module = @import("../Objects/dictobject.zig");
const pycomplex = @import("../Objects/complexobject.zig");
const BigInt = @import("bigint").BigInt;

const PyObject = runtime_core.PyObject;
const PythonError = runtime_core.PythonError;
const PyInt = pyint.PyInt;
const PyList = pylist.PyList;
const PyString = pystring.PyString;
const PyTuple = pytuple.PyTuple;
const PyDict = dict_module.PyDict;
const PyComplex = pycomplex.PyComplex;
const incref = runtime_core.incref;
const decref = runtime_core.decref;

/// Result type for pow() that can be either float or complex
/// Python: pow(negative, non_integer) returns complex
pub const PyPowResult = union(enum) {
    float_val: f64,
    complex_val: struct { real: f64, imag: f64 },

    /// Check if this is a float result
    pub fn isFloat(self: PyPowResult) bool {
        return self == .float_val;
    }

    /// Check if this is a complex result
    pub fn isComplex(self: PyPowResult) bool {
        return self == .complex_val;
    }

    /// Get the float value (panics if complex)
    pub fn asFloat(self: PyPowResult) f64 {
        return self.float_val;
    }

    /// Get as f64 - returns float value or NaN for complex
    pub fn toFloat(self: PyPowResult) f64 {
        return switch (self) {
            .float_val => |v| v,
            .complex_val => std.math.nan(f64), // complex can't be converted to float
        };
    }

    /// Get the complex value as (real, imag) tuple
    pub fn asComplex(self: PyPowResult) struct { real: f64, imag: f64 } {
        return self.complex_val;
    }

    /// Get the type name for type() builtin
    pub fn typeName(self: PyPowResult) []const u8 {
        return switch (self) {
            .float_val => "float",
            .complex_val => "complex",
        };
    }

    /// Check if this is NaN (only possible for float variant)
    pub fn isNan(self: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| std.math.isNan(v),
            .complex_val => |c| std.math.isNan(c.real) or std.math.isNan(c.imag),
        };
    }

    /// Check if this is infinite
    pub fn isInf(self: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| std.math.isInf(v),
            .complex_val => |c| std.math.isInf(c.real) or std.math.isInf(c.imag),
        };
    }

    /// Equality comparison with f64
    pub fn eql(self: PyPowResult, other: f64) bool {
        return switch (self) {
            .float_val => |v| v == other,
            .complex_val => false, // complex != float
        };
    }

    /// Equality comparison with another PyPowResult
    pub fn eqlResult(self: PyPowResult, other: PyPowResult) bool {
        return switch (self) {
            .float_val => |v| switch (other) {
                .float_val => |ov| v == ov,
                .complex_val => false,
            },
            .complex_val => |c| switch (other) {
                .float_val => false,
                .complex_val => |oc| c.real == oc.real and c.imag == oc.imag,
            },
        };
    }
};

// =============================================================================
// LITERAL HELPERS - Hide type mapping complexity from codegen
// These functions provide a clean interface for creating Python literals
// Codegen calls these helpers instead of directly constructing types
// =============================================================================

/// PyBytes - Wrapper for Python bytes type
/// Preserves type information for repr() to correctly output b'...' format
/// Supports all operations that []const u8 supports via wrapper methods
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

    /// Slice bytes [start:end]
    pub fn sliceRange(self: PyBytes, start: usize, end: usize) PyBytes {
        const actual_end = @min(end, self.data.len);
        const actual_start = @min(start, actual_end);
        return PyBytes{ .data = self.data[actual_start..actual_end] };
    }

    /// Index into bytes
    pub fn get(self: PyBytes, index: usize) u8 {
        return self.data[index];
    }

    /// Iterator support
    pub fn iterator(self: PyBytes) []const u8 {
        return self.data;
    }
};

/// Create a bytes literal - preserves Python bytes type for repr()
/// Usage in codegen: runtime.builtins.bytesLiteral("...")
pub fn bytesLiteral(data: []const u8) PyBytes {
    return PyBytes.init(data);
}

/// Create a string literal - returns raw slice (no wrapper needed for strings)
/// Usage in codegen: runtime.strLiteral("...")
/// This is identity function but provides consistent API with bytesLiteral
pub fn strLiteral(data: []const u8) []const u8 {
    return data;
}

/// Format bytes as Python bytes repr: b'...' with non-printable bytes escaped
/// Examples: b'hello' -> "b'hello'", b'\xa0' -> "b'\\xa0'"
pub fn bytesRepr(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "b'");

    for (data) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\\' and byte != '\'') {
            // Printable ASCII (except backslash and quote)
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
            // Non-printable: escape as \xNN
            try buf.appendSlice(allocator, "\\x");
            const hex_chars = "0123456789abcdef";
            try buf.append(allocator, hex_chars[byte >> 4]);
            try buf.append(allocator, hex_chars[byte & 0xf]);
        }
    }

    try buf.append(allocator, '\'');
    return buf.toOwnedSlice(allocator);
}

/// Compute pow with complex number support
/// Returns float for most cases, complex when base < 0 and exp is non-integer
pub fn pyPow(base: f64, exp: f64) PythonError!PyPowResult {
    // Python: 0.0 ** negative raises ZeroDivisionError
    if (base == 0.0 and exp < 0.0) {
        return PythonError.ZeroDivisionError;
    }

    // Check if exponent is an integer
    const exp_is_int = exp == @trunc(exp);

    // If base is negative and exponent is non-integer, we need complex math
    if (base < 0.0 and !exp_is_int and !std.math.isNan(exp) and !std.math.isInf(exp)) {
        // Use complex exponentiation: (-a)^b = e^(b * ln(-a)) = e^(b * (ln(|a|) + i*pi))
        // = e^(b*ln(|a|)) * e^(i*b*pi) = |a|^b * (cos(b*pi) + i*sin(b*pi))
        const abs_base = @abs(base);
        const magnitude = std.math.pow(f64, abs_base, exp);
        const angle = exp * std.math.pi;
        const real = magnitude * @cos(angle);
        const imag = magnitude * @sin(angle);
        return PyPowResult{ .complex_val = .{ .real = real, .imag = imag } };
    }

    // Normal float pow
    return PyPowResult{ .float_val = std.math.pow(f64, base, exp) };
}

/// Create a list of integers from start to stop with step
pub fn range(allocator: std.mem.Allocator, start: i64, stop: i64, step: i64) !*PyObject {
    if (step == 0) {
        return PythonError.ValueError;
    }

    const result_list = try PyList.create(allocator);

    if (step > 0) {
        var i = start;
        while (i < stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result_list, item);
            decref(item, allocator); // List takes ownership
        }
    } else if (step < 0) {
        var i = start;
        while (i > stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result_list, item);
            decref(item, allocator); // List takes ownership
        }
    }

    return result_list;
}

/// Create a list of (index, item) tuples from an iterable
pub fn enumerate(allocator: std.mem.Allocator, iterable: *PyObject, start: i64) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    var index = start;
    for (source_list.items.items) |item| {
        // Create tuple (index, item)
        const result_tuple = try PyTuple.create(allocator, 2);
        const idx_obj = try PyInt.create(allocator, index);

        PyTuple.setItem(result_tuple, 0, idx_obj);
        decref(idx_obj, allocator); // Tuple takes ownership

        incref(item); // Tuple needs ownership
        PyTuple.setItem(result_tuple, 1, item);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator); // List takes ownership

        index += 1;
    }

    return result;
}

/// Zip two lists into a list of tuples
pub fn zip2(allocator: std.mem.Allocator, iter1: *PyObject, iter2: *PyObject) !*PyObject {
    std.debug.assert(iter1.type_id == .list);
    std.debug.assert(iter2.type_id == .list);

    const list1: *PyList = @ptrCast(@alignCast(iter1.data));
    const list2: *PyList = @ptrCast(@alignCast(iter2.data));

    const result = try PyList.create(allocator);
    const min_len = @min(list1.items.items.len, list2.items.items.len);

    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        const result_tuple = try PyTuple.create(allocator, 2);

        incref(list1.items.items[i]);
        PyTuple.setItem(result_tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(result_tuple, 1, list2.items.items[i]);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator); // List takes ownership
    }

    return result;
}

/// Zip three lists into a list of tuples
pub fn zip3(allocator: std.mem.Allocator, iter1: *PyObject, iter2: *PyObject, iter3: *PyObject) !*PyObject {
    std.debug.assert(iter1.type_id == .list);
    std.debug.assert(iter2.type_id == .list);
    std.debug.assert(iter3.type_id == .list);

    const list1: *PyList = @ptrCast(@alignCast(iter1.data));
    const list2: *PyList = @ptrCast(@alignCast(iter2.data));
    const list3: *PyList = @ptrCast(@alignCast(iter3.data));

    const result = try PyList.create(allocator);
    const min_len = @min(@min(list1.items.items.len, list2.items.items.len), list3.items.items.len);

    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        const result_tuple = try PyTuple.create(allocator, 3);

        incref(list1.items.items[i]);
        PyTuple.setItem(result_tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(result_tuple, 1, list2.items.items[i]);

        incref(list3.items.items[i]);
        PyTuple.setItem(result_tuple, 2, list3.items.items[i]);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator); // List takes ownership
    }

    return result;
}

/// Check if all elements in iterable are truthy
pub fn all(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (src_list.items.items) |item| {
        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value == 0) return false;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            if (str_obj.data.len == 0) return false;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            if (list_obj.items.items.len == 0) return false;
        } else if (item.type_id == .dict) {
            if (PyDict.len(item) == 0) return false;
        }
        // For other types, assume truthy
    }
    return true;
}

/// Check if any element in iterable is truthy
pub fn any(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (src_list.items.items) |item| {
        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value != 0) return true;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            if (str_obj.data.len > 0) return true;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            if (list_obj.items.items.len > 0) return true;
        } else if (item.type_id == .dict) {
            if (PyDict.len(item) > 0) return true;
        }
        // For other types, assume truthy
    }
    return false;
}

/// Absolute value of a number
pub fn abs(value: i64) i64 {
    if (value < 0) {
        return -value;
    }
    return value;
}

/// Minimum value from a list
pub fn minList(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));
    std.debug.assert(list.items.items.len > 0);

    var min_val: i64 = std.math.maxInt(i64);
    for (src_list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value < min_val) {
                min_val = int_obj.value;
            }
        }
    }
    return min_val;
}

/// Minimum value from varargs
pub fn minVarArgs(values: []const i64) i64 {
    std.debug.assert(values.len > 0);
    var min_val = values[0];
    for (values[1..]) |value| {
        if (value < min_val) {
            min_val = value;
        }
    }
    return min_val;
}

/// Maximum value from a list
pub fn maxList(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));
    std.debug.assert(list.items.items.len > 0);

    var max_val: i64 = std.math.minInt(i64);
    for (src_list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value > max_val) {
                max_val = int_obj.value;
            }
        }
    }
    return max_val;
}

/// Maximum value from varargs
pub fn maxVarArgs(values: []const i64) i64 {
    std.debug.assert(values.len > 0);
    var max_val = values[0];
    for (values[1..]) |value| {
        if (value > max_val) {
            max_val = value;
        }
    }
    return max_val;
}

/// Minimum value from any iterable (generic)
pub fn minIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (T == *PyObject) {
        return minList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        // Custom sequence class with __getitem__ method
        var min_val: i64 = std.math.maxInt(i64);
        var i: i64 = 0;
        while (true) {
            const item = iterable.__getitem__(i) catch break;
            if (item < min_val) {
                min_val = item;
            }
            i += 1;
        }
        return min_val;
    } else if (@typeInfo(T) == .pointer and @typeInfo(std.meta.Child(T)) == .@"struct") {
        // Struct with items field (tuples, arrays)
        if (@hasField(std.meta.Child(T), "items")) {
            var min_val: i64 = std.math.maxInt(i64);
            for (iterable.items) |item| {
                if (item < min_val) {
                    min_val = item;
                }
            }
            return min_val;
        }
    }
    // Fallback for slices
    var min_val: i64 = std.math.maxInt(i64);
    for (iterable) |item| {
        if (item < min_val) {
            min_val = item;
        }
    }
    return min_val;
}

/// Get next item from an iterator (takes pointer for mutation)
pub fn next(iterator: anytype) IteratorItem(@TypeOf(iterator)) {
    const T = @TypeOf(iterator);
    const info = @typeInfo(T);

    // Handle pointer to iterator struct
    if (info == .pointer) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        // Only check for decls on struct/enum/union/opaque types
        if (child_info == .@"struct" or child_info == .@"enum" or child_info == .@"union" or child_info == .@"opaque") {
            if (@hasDecl(Child, "next")) {
                if (iterator.next()) |item| {
                    return item;
                }
                return error.StopIteration;
            }
            if (@hasDecl(Child, "__next__")) {
                return iterator.__next__();
            }
        }
        // Non-iterator pointer type (e.g., *bool) - return TypeError
        return error.TypeError;
    }

    const type_info = @typeInfo(T);
    if (type_info == .@"struct" or type_info == .@"enum" or type_info == .@"union" or type_info == .@"opaque") {
        // Handle iterator struct directly (legacy)
        if (@hasDecl(T, "__next__")) {
            return iterator.__next__();
        }
        if (@hasDecl(T, "next")) {
            if (iterator.next()) |item| {
                return item;
            }
            return error.StopIteration;
        }
    }

    // Non-iterator type - return TypeError at runtime
    return error.TypeError;
}

/// Helper to get the item type from an iterator
fn IteratorItem(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        // Only check for decls on struct/enum/union/opaque types
        if (child_info == .@"struct" or child_info == .@"enum" or child_info == .@"union" or child_info == .@"opaque") {
            if (@hasDecl(Child, "Item")) {
                return error{StopIteration}!Child.Item;
            }
            if (@hasDecl(Child, "next")) {
                const next_fn = @typeInfo(@TypeOf(@field(Child, "next")));
                if (next_fn == .@"fn") {
                    const ReturnType = next_fn.@"fn".return_type.?;
                    if (@typeInfo(ReturnType) == .optional) {
                        return error{StopIteration}!@typeInfo(ReturnType).optional.child;
                    }
                }
            }
        }
        // Non-iterator pointer types - return void with error
        return error{StopIteration, TypeError}!void;
    }
    if (info == .@"struct" or info == .@"enum" or info == .@"union" or info == .@"opaque") {
        if (@hasDecl(T, "Item")) {
            return error{StopIteration}!T.Item;
        }
    }
    // Non-iterator types
    if (@hasDecl(T, "Item")) {
        return error{StopIteration}!T.Item;
    }
    return error{StopIteration}!void;
}

/// iter() for strings - creates a stateful StringIterator
pub fn strIterator(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// iter() - return iterator over iterable (identity for already-iterable types)
pub fn iter(iterable: anytype) @TypeOf(iterable) {
    return iterable;
}

/// RangeIterator struct - lightweight lazy range iterator
pub const RangeIterator = struct {
    start: i64,
    stop: i64,
    step: i64,
    current: i64,

    pub fn init(start: i64, stop: i64, step: i64) RangeIterator {
        return .{ .start = start, .stop = stop, .step = step, .current = start };
    }

    pub fn next(self: *RangeIterator) ?i64 {
        if (self.step > 0) {
            if (self.current >= self.stop) return null;
        } else {
            if (self.current <= self.stop) return null;
        }
        const result = self.current;
        self.current += self.step;
        return result;
    }

    pub fn len(self: RangeIterator) usize {
        if (self.step > 0) {
            if (self.stop <= self.start) return 0;
            return @intCast(@divFloor(self.stop - self.start + self.step - 1, self.step));
        } else {
            if (self.stop >= self.start) return 0;
            return @intCast(@divFloor(self.start - self.stop - self.step - 1, -self.step));
        }
    }
};

/// rangeLazy(start, stop, step) - creates a lightweight range iterator
pub fn rangeLazy(start: i64, stop: i64, step: i64) RangeIterator {
    return RangeIterator.init(start, stop, step);
}

/// StringIterator struct - stateful iterator over string characters (Unicode codepoints)
/// This matches Python's iter(str) behavior where the iterator tracks its position
pub const StringIterator = struct {
    data: []const u8,
    pos: usize,

    pub const Item = []const u8;

    pub fn init(s: []const u8) StringIterator {
        return .{ .data = s, .pos = 0 };
    }

    /// Get next Unicode character as a string slice
    /// Returns null when exhausted (signals StopIteration)
    pub fn next(self: *StringIterator) ?[]const u8 {
        if (self.pos >= self.data.len) return null;

        // Decode UTF-8 codepoint length
        const byte = self.data[self.pos];
        const cp_len: usize = if (byte < 0x80)
            1
        else if (byte < 0xE0)
            2
        else if (byte < 0xF0)
            3
        else
            4;

        // Safety check
        if (self.pos + cp_len > self.data.len) {
            self.pos = self.data.len;
            return null;
        }

        const start = self.pos;
        self.pos += cp_len;
        return self.data[start..self.pos];
    }

    /// Check if iterator is exhausted
    pub fn isExhausted(self: StringIterator) bool {
        return self.pos >= self.data.len;
    }
};

/// strIter(s) - creates a stateful string iterator
pub fn strIter(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// Generic iterator wrapper that can wrap different types
/// This provides a uniform interface for iter() on various types
pub fn GenericIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Item = switch (@typeInfo(T)) {
            .pointer => |ptr| if (ptr.size == .slice) ptr.child else T,
            else => T,
        };

        data: T,
        pos: usize,

        pub fn init(data: T) Self {
            return .{ .data = data, .pos = 0 };
        }

        pub fn next(self: *Self) ?Item {
            const info = @typeInfo(T);
            if (info == .pointer and info.pointer.size == .slice) {
                if (self.pos >= self.data.len) return null;
                const item = self.data[self.pos];
                self.pos += 1;
                return item;
            }
            // For other types, just return the data once
            if (self.pos == 0) {
                self.pos = 1;
                return self.data;
            }
            return null;
        }
    };
}

/// Maximum value from any iterable (generic)
pub fn maxIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (T == *PyObject) {
        return maxList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        // Custom sequence class with __getitem__ method
        var max_val: i64 = std.math.minInt(i64);
        var i: i64 = 0;
        while (true) {
            const item = iterable.__getitem__(i) catch break;
            if (item > max_val) {
                max_val = item;
            }
            i += 1;
        }
        return max_val;
    } else if (@typeInfo(T) == .pointer and @typeInfo(std.meta.Child(T)) == .@"struct") {
        // Struct with items field (tuples, arrays)
        if (@hasField(std.meta.Child(T), "items")) {
            var max_val: i64 = std.math.minInt(i64);
            for (iterable.items) |item| {
                if (item > max_val) {
                    max_val = item;
                }
            }
            return max_val;
        }
    }
    // Fallback for slices and ArrayLists - use runtime.iterSlice for universal handling
    const rt = @import("../runtime.zig");
    const slice = rt.iterSlice(iterable);
    var max_val: i64 = std.math.minInt(i64);
    for (slice) |item| {
        if (item > max_val) {
            max_val = item;
        }
    }
    return max_val;
}

/// Python round() - rounds a number to given precision
/// For integers, returns the integer unchanged
/// For floats, returns @round result
pub fn pyRound(value: anytype) i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    if (info == .int or info == .comptime_int) {
        return @as(i64, @intCast(value));
    } else if (info == .float or info == .comptime_float) {
        return @intFromFloat(@round(value));
    }
    // For other types (structs with __round__ method), not handled here
    return 0;
}

/// Sum of all numeric values in a list
pub fn sum(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    var total: i64 = 0;
    for (src_list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            total += int_obj.value;
        }
    }
    return total;
}

/// Return a new sorted list from an iterable
pub fn sorted(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    // Create new list
    const result = try PyList.create(allocator);

    // Copy all items
    for (source_list.items.items) |item| {
        incref(item);
        try PyList.append(result, item);
    }

    // Sort in place using PyList.sort
    PyList.sort(result);

    return result;
}

/// Return a new reversed list from an iterable
pub fn reversed(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    // Append items in reverse order
    var i: usize = source_list.items.items.len;
    while (i > 0) {
        i -= 1;
        incref(source_list.items.items[i]);
        try PyList.append(result, source_list.items.items[i]);
    }

    return result;
}

/// Filter out falsy values from an iterable
pub fn filterTruthy(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    for (source_list.items.items) |item| {
        var is_truthy = true;

        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            is_truthy = int_obj.value != 0;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            is_truthy = str_obj.data.len > 0;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            is_truthy = list_obj.items.items.len > 0;
        } else if (item.type_id == .dict) {
            is_truthy = PyDict.len(item) > 0;
        }

        if (is_truthy) {
            incref(item);
            try PyList.append(result, item);
        }
    }

    return result;
}

/// callable() builtin - returns true if object is callable
/// Works with: functions, function pointers, PyObjects with __call__
pub fn callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    // Check if it's a function type
    if (@typeInfo(T) == .@"fn") return true;
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (@typeInfo(child) == .@"fn") return true;
    }
    // Check for PyObject with __call__
    if (T == *PyObject) {
        // For now, return false for PyObjects (no callable detection yet)
        // TODO: check for __call__ attribute
        return false;
    }
    return false;
}

/// len() builtin as a first-class function value
/// For use in contexts like callable(len)
pub fn len(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return runtime_core.pyLen(obj);
    } else if (comptime isSlice(T)) {
        // Check slice before pointer since slices are also pointers
        return obj.len;
    } else if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        const child_info = @typeInfo(Child);
        // Only check @hasField on struct types
        if (child_info == .@"struct" and @hasField(Child, "items")) {
            return obj.items.len;
        } else if (child_info == .@"struct" and @hasDecl(Child, "len")) {
            return obj.len;
        }
    } else if (@typeInfo(T) == .array) {
        return @typeInfo(T).array.len;
    }
    return 0;
}

/// id() builtin - returns object identity (pointer address)
pub fn id(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .pointer) {
        return @intFromPtr(obj);
    }
    return 0;
}

/// hash() builtin - returns hash of object
/// Implements Python's hash algorithm for compatibility
pub fn hash(obj: anytype) i64 {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return @intCast(runtime_core.pyHash(obj));
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @intCast(obj);
    } else if (T == []const u8 or T == []u8) {
        var h: u64 = 0;
        for (obj) |c| h = h *% 31 +% c;
        return @intCast(h);
    } else if (@typeInfo(T) == .@"struct") {
        // Tuple/struct hash - use Python's tuple hash algorithm
        // xxHash-based algorithm matching CPython 3.8+
        return tupleHash(obj);
    }
    return 0;
}

/// Python-compatible tuple hash using xxHash algorithm (CPython 3.8+)
/// This matches Python's tuplehash() in Objects/tupleobject.c
fn tupleHash(tup: anytype) i64 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return 0;

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    // Python's xxHash constants
    const XXPRIME_1: u64 = 11400714785074694791;
    const XXPRIME_2: u64 = 14029467366897019727;
    const XXPRIME_5: u64 = 2870177450012600261;

    var acc: u64 = XXPRIME_5;

    // Hash each element
    inline for (fields) |field| {
        const elem = @field(tup, field.name);
        const elem_hash: u64 = @bitCast(hash(elem));
        acc +%= elem_hash *% XXPRIME_2;
        acc = (acc << 31) | (acc >> 33); // rotate left 31
        acc *%= XXPRIME_1;
    }

    // Final mix
    acc +%= @as(u64, num_fields) ^ (XXPRIME_5 ^ 3527539);

    if (acc == @as(u64, @bitCast(@as(i64, -1)))) {
        return 1546275796;
    }

    return @bitCast(acc);
}

/// Python-compatible tuple repr - returns "(a, b, c)" format
/// For single element tuples, returns "(a,)" with trailing comma
pub fn tupleRepr(allocator: std.mem.Allocator, tup: anytype) ![]const u8 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return "()";

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    // Empty tuple
    if (num_fields == 0) return "()";

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '(');

    inline for (fields, 0..) |field, i| {
        const elem = @field(tup, field.name);
        const elem_str = try valueRepr(allocator, elem);
        try result.appendSlice(allocator, elem_str);

        // Add comma: always between elements, and after single element
        if (i < num_fields - 1) {
            try result.appendSlice(allocator, ", ");
        } else if (num_fields == 1) {
            // Single element tuple needs trailing comma: (a,)
            try result.append(allocator, ',');
        }
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

/// Python-compatible float repr/str
/// Python's float repr always includes a decimal point (e.g., "0.0", "1.0", not "0", "1")
/// Also handles special values: inf, -inf, nan
/// Python uses scientific notation for very large (>=1e16) or very small (<=1e-4) numbers
fn pythonFloatRepr(allocator: std.mem.Allocator, value: f64) ![]const u8 {
    // Handle special values
    if (std.math.isNan(value)) {
        return "nan";
    }
    if (std.math.isInf(value)) {
        return if (value < 0) "-inf" else "inf";
    }

    // Python uses scientific notation for very large or very small numbers
    const abs_value = @abs(value);
    const use_scientific = value != 0 and (abs_value >= 1e16 or abs_value < 1e-4);

    if (use_scientific) {
        // Use scientific notation - Python format:
        // 1. Explicit + sign for positive exponents
        // 2. At least 2 digits in exponent (e.g., e-05 not e-5)
        const formatted = try std.fmt.allocPrint(allocator, "{e}", .{value});
        var result = std.ArrayList(u8){};
        var i: usize = 0;
        while (i < formatted.len) : (i += 1) {
            try result.append(allocator, formatted[i]);
            if (formatted[i] == 'e' and i + 1 < formatted.len) {
                // After 'e', handle sign and padding
                const next_char = formatted[i + 1];
                if (next_char == '-') {
                    // Has minus sign - check if exponent needs padding
                    try result.append(allocator, '-');
                    i += 1;
                    // Check remaining chars to see if it's single digit
                    const exp_start = i + 1;
                    const exp_len = formatted.len - exp_start;
                    if (exp_len == 1) {
                        // Single digit exponent - pad with 0
                        try result.append(allocator, '0');
                    }
                } else if (std.ascii.isDigit(next_char)) {
                    // Positive exponent without sign - add +
                    try result.append(allocator, '+');
                    // Check if single digit
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

    // Format the float
    const formatted = try std.fmt.allocPrint(allocator, "{d}", .{value});

    // Check if it already has a decimal point or exponent
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

    // If no decimal, add ".0" suffix for integer-valued floats
    if (!has_decimal and !has_exponent) {
        var result = std.ArrayList(u8){};
        try result.appendSlice(allocator, formatted);
        try result.appendSlice(allocator, ".0");
        allocator.free(formatted);
        return result.toOwnedSlice(allocator);
    }

    // Has decimal - trim trailing zeros (but keep at least one digit after decimal)
    if (has_decimal and !has_exponent) {
        var end = formatted.len;
        // Find trailing zeros
        while (end > decimal_pos + 2 and formatted[end - 1] == '0') {
            end -= 1;
        }
        // Return trimmed string
        if (end < formatted.len) {
            const trimmed = try allocator.dupe(u8, formatted[0..end]);
            allocator.free(formatted);
            return trimmed;
        }
    }

    return formatted;
}

/// Convert a value to its repr string (for tuple elements)
fn valueRepr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    // PyBytes - format as b'...' with non-printable bytes escaped
    if (T == PyBytes) {
        return bytesRepr(allocator, value.data);
    }

    // String - wrap in quotes
    if (T == []const u8 or T == []u8) {
        var buf = std.ArrayList(u8){};
        try buf.append(allocator, '\'');
        try buf.appendSlice(allocator, value);
        try buf.append(allocator, '\'');
        return buf.toOwnedSlice(allocator);
    }

    // Bool - Python True/False
    if (T == bool) {
        return if (value) "True" else "False";
    }

    // Integer
    if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }

    // Float - Python always includes decimal point in repr
    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        return pythonFloatRepr(allocator, value);
    }

    // Nested tuple/struct - recursive repr
    if (@typeInfo(T) == .@"struct") {
        return tupleRepr(allocator, value);
    }

    // Slice (from tupleRepeat) - format as tuple (a, b, c)
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        return sliceAsTupleRepr(allocator, value);
    }

    // Fallback
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

/// Format a slice as a Python tuple: (a, b, c) or (a,) for single element
fn sliceAsTupleRepr(allocator: std.mem.Allocator, slice: anytype) ![]const u8 {
    if (slice.len == 0) return "()";

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '(');

    for (slice, 0..) |elem, i| {
        const elem_str = try valueRepr(allocator, elem);
        try result.appendSlice(allocator, elem_str);

        // Add comma: always between elements, and after single element
        if (i < slice.len - 1) {
            try result.appendSlice(allocator, ", ");
        } else if (slice.len == 1) {
            // Single element tuple needs trailing comma: (a,)
            try result.append(allocator, ',');
        }
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

/// Python-compatible repr for any value
/// Routes to appropriate repr function based on type at comptime
pub fn pyRepr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return valueRepr(allocator, value);
}

/// Python-compatible str for any value
/// For tuples, returns "(a, b, c)" format without quotes on strings
pub fn pyStr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return valueStr(allocator, value);
}

/// Convert a value to its str string (for tuple elements, without extra quotes)
fn valueStr(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    // String - no wrapping quotes (unlike repr)
    if (T == []const u8 or T == []u8) {
        return value;
    }

    // Bool - Python True/False
    if (T == bool) {
        return if (value) "True" else "False";
    }

    // Integer
    if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }

    // Float - Python always includes decimal point in str
    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        return pythonFloatRepr(allocator, value);
    }

    // Tuple/struct - same as repr
    if (@typeInfo(T) == .@"struct") {
        return tupleRepr(allocator, value);
    }

    // Slice (from tupleRepeat) - format as tuple
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        return sliceAsTupleRepr(allocator, value);
    }

    // Fallback
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

/// Helper to check if type is a slice
fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .slice,
        else => false,
    };
}

/// compile() builtin - compile source code
/// In AOT context, this raises an error since we can't compile at runtime
pub fn compile(source: []const u8, filename: []const u8, mode: []const u8) PythonError!void {
    _ = source;
    _ = filename;
    _ = mode;
    // In AOT context, compile() is not supported - it requires runtime compilation
    return PythonError.ValueError;
}

/// exec() builtin - execute compiled code
/// In AOT context, this raises an error
pub fn exec(code: anytype) PythonError!void {
    _ = code;
    return PythonError.ValueError;
}

/// int(base=N) without value argument - always raises TypeError
/// Python: int(base=10) → TypeError: int() missing required argument 'x' (pos 1)
pub fn intWithBaseOnly() PythonError!i128 {
    return PythonError.TypeError;
}

/// struct.pack() with no format string - raises TypeError
/// Python: struct.pack() takes no keyword arguments
pub fn structPackNoArgs() PythonError![]const u8 {
    return PythonError.TypeError;
}

/// struct.pack_into() with insufficient args - raises TypeError
pub fn structPackIntoNoArgs() PythonError!void {
    return PythonError.TypeError;
}

/// int(string, base) with runtime base validation
/// Used in assertRaises context where base might be invalid (negative, > 36, etc.)
pub fn intWithBase(allocator: std.mem.Allocator, string: anytype, base: anytype) PythonError!i128 {
    _ = allocator;

    // Get string value
    const str_val: []const u8 = blk: {
        const T = @TypeOf(string);
        if (T == []const u8 or T == []u8) break :blk string;
        if (@typeInfo(T) == .pointer) {
            const child = @typeInfo(T).pointer.child;
            if (@typeInfo(child) == .array) {
                const arr_info = @typeInfo(child).array;
                if (arr_info.child == u8) break :blk string;
            }
        }
        // For pointer to array type like *const [N:0]u8
        break :blk string;
    };

    // Validate base at runtime
    const base_int: i64 = switch (@typeInfo(@TypeOf(base))) {
        .int, .comptime_int => @intCast(base),
        // Float base is TypeError in Python
        .float, .comptime_float => return PythonError.TypeError,
        .@"struct" => blk: {
            // Check if it's a BigInt - try to convert to i64
            if (@hasDecl(@TypeOf(base), "toInt64")) {
                // It's a BigInt - try to get as i64
                if (base.toInt64()) |val| {
                    break :blk val;
                } else {
                    // BigInt too large for base - definitely out of range
                    return PythonError.ValueError;
                }
            }
            return PythonError.TypeError;
        },
        else => return PythonError.TypeError,
    };

    // Valid bases are 0 or 2-36
    if (base_int != 0 and (base_int < 2 or base_int > 36)) {
        return PythonError.ValueError;
    }

    // Use the validated base
    const actual_base: u8 = if (base_int == 0) 10 else @intCast(base_int);
    return std.fmt.parseInt(i128, str_val, actual_base) catch PythonError.ValueError;
}

// Type factory functions - callable versions of Python types
// These allow types like bytes, str to be used as first-class values

/// str() type factory - converts value to string (generic version)
pub fn str(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    // For other types, return empty string (proper implementation would format)
    return "";
}

/// bytes() type factory - converts value to bytes (generic version)
pub fn bytes(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// bytearray() type factory - converts value to bytearray (mutable bytes)
pub fn bytearray(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// memoryview() type factory - creates a memoryview of the value (generic version)
pub fn memoryview(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// PyCallable - Type-erased callable wrapper for storing heterogeneous callables in lists
/// Used when Python code creates lists of mixed callable types (functions, lambdas, type constructors)
pub const PyCallable = struct {
    /// Type-erased function pointer that takes bytes and returns bytes
    call_fn: *const fn ([]const u8) []const u8,
    /// Optional context for closures (null for simple functions)
    context: ?*anyopaque,

    /// Call this callable with the given argument
    pub fn call(self: PyCallable, arg: []const u8) []const u8 {
        return self.call_fn(arg);
    }

    /// Create a PyCallable from a function pointer
    pub fn fromFn(func: *const fn ([]const u8) []const u8) PyCallable {
        return .{ .call_fn = func, .context = null };
    }

    /// Create a PyCallable from any callable (type-erased)
    /// For class constructors that return structs with __base_value__, extracts the bytes
    pub fn fromAny(comptime T: type, comptime func: T) PyCallable {
        const type_info = @typeInfo(T);

        // Handle function pointers
        if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"fn") {
            const fn_info = @typeInfo(type_info.pointer.child).@"fn";
            const ReturnType = fn_info.return_type orelse void;

            const Wrapper = struct {
                fn thunk(arg: []const u8) []const u8 {
                    // Check number of parameters
                    if (fn_info.params.len == 1) {
                        // Single arg function (like lambda b: ...)
                        const result = func(arg);
                        return extractBytes(ReturnType, result);
                    } else if (fn_info.params.len == 2) {
                        // Two arg function (like CustomClass.init(allocator, bytes))
                        // Use global allocator - this is safe because we're in runtime context
                        const result = func(std.heap.page_allocator, arg);
                        return extractBytes(ReturnType, result);
                    }
                    return arg;
                }

                fn extractBytes(comptime R: type, value: R) []const u8 {
                    const r_info = @typeInfo(R);
                    // If return type is []const u8, return as-is
                    if (R == []const u8 or R == []u8) {
                        return value;
                    }
                    // If return type is a struct with __base_value__, extract it
                    if (r_info == .@"struct" and @hasField(R, "__base_value__")) {
                        return value.__base_value__;
                    }
                    // If return type is a struct with tobytes() method (like array.array), call it
                    if (r_info == .@"struct" and @hasDecl(R, "tobytes")) {
                        // tobytes takes *@This(), so we need to make it mutable
                        var mutable_value = value;
                        return mutable_value.tobytes();
                    }
                    // If return type is pointer to struct with __base_value__
                    if (r_info == .pointer and r_info.pointer.size == .one) {
                        const child_info = @typeInfo(r_info.pointer.child);
                        if (child_info == .@"struct" and @hasField(r_info.pointer.child, "__base_value__")) {
                            return value.__base_value__;
                        }
                    }
                    // Fallback - return empty
                    return "";
                }
            };
            return .{ .call_fn = &Wrapper.thunk, .context = null };
        }

        // Handle bound methods / struct functions
        if (type_info == .@"fn") {
            const fn_info = type_info.@"fn";
            const ReturnType = fn_info.return_type orelse void;

            const Wrapper = struct {
                fn thunk(arg: []const u8) []const u8 {
                    if (fn_info.params.len == 1) {
                        const result = func(arg);
                        return extractBytesFromResult(ReturnType, result);
                    } else if (fn_info.params.len == 2) {
                        const result = func(std.heap.page_allocator, arg);
                        return extractBytesFromResult(ReturnType, result);
                    }
                    return arg;
                }

                fn extractBytesFromResult(comptime R: type, value: R) []const u8 {
                    const r_info = @typeInfo(R);
                    if (R == []const u8 or R == []u8) {
                        return value;
                    }
                    if (r_info == .@"struct" and @hasField(R, "__base_value__")) {
                        return value.__base_value__;
                    }
                    // If return type is a struct with tobytes() method (like array.array), call it
                    if (r_info == .@"struct" and @hasDecl(R, "tobytes")) {
                        var mutable_value = value;
                        return mutable_value.tobytes();
                    }
                    if (r_info == .pointer and r_info.pointer.size == .one) {
                        const child_info = @typeInfo(r_info.pointer.child);
                        if (child_info == .@"struct" and @hasField(r_info.pointer.child, "__base_value__")) {
                            return value.__base_value__;
                        }
                    }
                    return "";
                }
            };
            return .{ .call_fn = &Wrapper.thunk, .context = null };
        }

        // Fallback - identity function
        const Wrapper = struct {
            fn thunk(arg: []const u8) []const u8 {
                return arg;
            }
        };
        return .{ .call_fn = &Wrapper.thunk, .context = null };
    }
};

// Concrete wrapper functions with fixed signatures for use in heterogeneous lists
// These can be stored as function pointers

/// bytes() as a concrete callable (fixed signature for list storage)
pub fn bytes_callable(value: []const u8) []const u8 {
    return value;
}

/// bytearray() as a concrete callable (fixed signature for list storage)
pub fn bytearray_callable(value: []const u8) []const u8 {
    return value;
}

/// str() as a concrete callable (fixed signature for list storage)
pub fn str_callable(value: []const u8) []const u8 {
    return value;
}

/// memoryview() as a concrete callable (fixed signature for list storage)
pub fn memoryview_callable(value: []const u8) []const u8 {
    return value;
}

/// BigInt-aware divmod - returns tuple of (quotient, remainder)
/// Handles BigInt, i64, and anytype parameters via comptime dispatch
pub fn bigIntDivmod(a: anytype, b: anytype, allocator: std.mem.Allocator) struct { @TypeOf(a), @TypeOf(a) } {
    const AT = @TypeOf(a);
    const BT = @TypeOf(b);

    // Both are BigInt
    if (@typeInfo(AT) == .@"struct" and @hasDecl(AT, "floorDiv") and
        @typeInfo(BT) == .@"struct" and @hasDecl(BT, "floorDiv"))
    {
        const q = a.floorDiv(&b, allocator) catch unreachable;
        const r = a.mod(&b, allocator) catch unreachable;
        return .{ q, r };
    }
    // a is BigInt, b is integer
    else if (@typeInfo(AT) == .@"struct" and @hasDecl(AT, "floorDiv")) {
        const b_big = BigInt.fromInt(allocator, @as(i64, @intCast(b))) catch unreachable;
        const q = a.floorDiv(&b_big, allocator) catch unreachable;
        const r = a.mod(&b_big, allocator) catch unreachable;
        return .{ q, r };
    }
    // Both are regular integers - use Zig builtins
    else {
        return .{ @divFloor(a, b), @rem(a, b) };
    }
}

/// Comparison operation enum for bigIntCompare
pub const CompareOp = enum { eq, ne, lt, le, gt, ge };

/// BigInt-aware comparison - handles BigInt vs BigInt, BigInt vs int, int vs int
pub fn bigIntCompare(a: anytype, b: anytype, op: CompareOp) bool {
    const AT = @TypeOf(a);
    const BT = @TypeOf(b);

    const a_is_bigint = @typeInfo(AT) == .@"struct" and @hasDecl(AT, "compare");
    const b_is_bigint = @typeInfo(BT) == .@"struct" and @hasDecl(BT, "compare");

    if (a_is_bigint and b_is_bigint) {
        // Both BigInt - use compare method
        const cmp = a.compare(&b);
        return switch (op) {
            .eq => cmp == 0,
            .ne => cmp != 0,
            .lt => cmp < 0,
            .le => cmp <= 0,
            .gt => cmp > 0,
            .ge => cmp >= 0,
        };
    } else if (a_is_bigint) {
        // a is BigInt, b is integer - compare by trying to convert BigInt to i128
        if (a.toInt128()) |a_val| {
            const b_val: i128 = @intCast(b);
            return switch (op) {
                .eq => a_val == b_val,
                .ne => a_val != b_val,
                .lt => a_val < b_val,
                .le => a_val <= b_val,
                .gt => a_val > b_val,
                .ge => a_val >= b_val,
            };
        } else {
            // BigInt too large for i128 - compare by sign
            // A huge positive is > any i128, huge negative is < any i128
            const is_neg = a.isNegative();
            return switch (op) {
                .eq => false,
                .ne => true,
                .lt => is_neg,
                .le => is_neg,
                .gt => !is_neg,
                .ge => !is_neg,
            };
        }
    } else if (b_is_bigint) {
        // b is BigInt, a is integer
        if (b.toInt128()) |b_val| {
            const a_val: i128 = @intCast(a);
            return switch (op) {
                .eq => a_val == b_val,
                .ne => a_val != b_val,
                .lt => a_val < b_val,
                .le => a_val <= b_val,
                .gt => a_val > b_val,
                .ge => a_val >= b_val,
            };
        } else {
            // BigInt too large for i128
            const is_neg = b.isNegative();
            return switch (op) {
                .eq => false,
                .ne => true,
                .lt => !is_neg,
                .le => !is_neg,
                .gt => is_neg,
                .ge => is_neg,
            };
        }
    } else {
        // Check if these are complex types (ArrayList, tuple, HashMap, etc.)
        const a_is_complex = @typeInfo(AT) == .@"struct";
        const b_is_complex = @typeInfo(BT) == .@"struct";

        if (a_is_complex or b_is_complex) {
            // Check if left operand has __eq__ method (Python class instance)
            if (@typeInfo(AT) == .@"struct" and @hasDecl(AT, "__eq__")) {
                // Use classInstanceEq which handles different method signatures
                const eq_result = classInstanceEq(a, b, std.heap.page_allocator);
                return switch (op) {
                    .eq => eq_result,
                    .ne => !eq_result,
                    .lt, .le, .gt, .ge => false, // Not comparable
                };
            }
            // Check right operand for __eq__
            if (@typeInfo(BT) == .@"struct" and @hasDecl(BT, "__eq__")) {
                const eq_result = classInstanceEq(b, a, std.heap.page_allocator);
                return switch (op) {
                    .eq => eq_result,
                    .ne => !eq_result,
                    .lt, .le, .gt, .ge => false, // Not comparable
                };
            }

            // For complex types without __eq__, only eq and ne are supported
            // If types don't match, they can't be equal
            if (AT != BT) {
                return switch (op) {
                    .eq => false,
                    .ne => true,
                    .lt, .le, .gt, .ge => false, // Not comparable
                };
            }
            const equal = std.meta.eql(a, b);
            return switch (op) {
                .eq => equal,
                .ne => !equal,
                .lt, .le, .gt, .ge => false, // Not comparable
            };
        }

        // Both are regular integers
        return switch (op) {
            .eq => a == b,
            .ne => a != b,
            .lt => a < b,
            .le => a <= b,
            .gt => a > b,
            .ge => a >= b,
        };
    }
}

// PyCallable instances for built-in type factories
pub const bytes_factory: PyCallable = PyCallable.fromFn(&bytes_callable);
pub const bytearray_factory: PyCallable = PyCallable.fromFn(&bytearray_callable);
pub const str_factory: PyCallable = PyCallable.fromFn(&str_callable);
pub const memoryview_factory: PyCallable = PyCallable.fromFn(&memoryview_callable);

/// issubclass builtin - callable struct for passing as first-class value
/// Used in: blowstack(issubclass, str, str) patterns
pub const issubclass = struct {
    pub fn call(_: @This(), cls: anytype, base: anytype) bool {
        _ = cls;
        _ = base;
        // Type checks are compile-time in native codegen
        // Return false as safe default for runtime checks
        return false;
    }
}{};

/// isinstance builtin - callable struct for passing as first-class value
/// Used in: blowstack(isinstance, '', str) patterns
pub const isinstance = struct {
    pub fn call(_: @This(), obj: anytype, cls: anytype) bool {
        _ = obj;
        _ = cls;
        // Type checks are compile-time in native codegen
        // Return false as safe default for runtime checks
        return false;
    }
}{};

// Operator module callable structs - these can be stored as values and called later
// Example: mod = operator.mod; mod(-1.0, 1.0)

/// operator.mod callable - Python modulo operation
/// Called as: OperatorMod{}.call(a, b) where self is ignored
/// Named 'call' to match callable_vars system
/// NOTE: Python uses floored division mod: a % b = a - floor(a/b) * b
/// This is different from C's fmod/Zig's @rem (truncated division)
/// Example: (-1.0) % 1.0 = 0.0 in Python, but fmod(-1.0, 1.0) = -0.0
pub const OperatorMod = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const T = @TypeOf(a);
        const BT = @TypeOf(b);
        // For floats, use Python's floored modulo: a - floor(a/b) * b
        if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
            const bf: T = if (@typeInfo(BT) == .float) b else @as(T, @floatFromInt(b));
            return pyFloatMod(a, bf);
        } else if (@typeInfo(BT) == .float or @typeInfo(BT) == .comptime_float) {
            return pyFloatMod(@as(BT, @floatFromInt(a)), b);
        } else {
            return @mod(a, b);
        }
    }

    /// Python floored modulo for floats: a % b = a - floor(a/b) * b
    fn pyFloatMod(a: anytype, b: anytype) @TypeOf(a) {
        const T = @TypeOf(a);
        // Python's floored division mod
        const quotient = @floor(a / b);
        const result = a - quotient * b;
        // Handle sign of zero result to match Python behavior
        // When result is zero, Python preserves sign based on operand signs
        // -1.0 % 1.0 = 0.0 (not -0.0), but 1.0 % -1.0 = -0.0
        if (result == 0.0) {
            // If b is negative, result should be -0.0
            // If b is positive, result should be 0.0
            return if (b < 0.0) -@as(T, 0.0) else @as(T, 0.0);
        }
        return result;
    }
};

/// operator.pow callable - Python power operation
/// Called as: OperatorPow{}.call(a, b) where self is ignored
/// Named 'call' to match callable_vars system
/// Python: 0.0 ** negative raises ZeroDivisionError
/// Python: pow(negative, non_integer) returns complex
pub const OperatorPow = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) PythonError!PyPowResult {
        const af: f64 = switch (@typeInfo(@TypeOf(a))) {
            .float, .comptime_float => @as(f64, a),
            .int, .comptime_int => @as(f64, @floatFromInt(a)),
            else => 0.0,
        };
        const bf: f64 = switch (@typeInfo(@TypeOf(b))) {
            .float, .comptime_float => @as(f64, b),
            .int, .comptime_int => @as(f64, @floatFromInt(b)),
            else => 0.0,
        };
        return pyPow(af, bf);
    }
};

/// Builtin pow callable - for when pow is used as first-class value
/// This is the same as OperatorPow but named 'pow' for direct access
/// e.g., `for pow_op in pow, operator.pow:`
pub const pow = OperatorPow{};

/// operator.concat callable - sequence concatenation
/// Called as: OperatorConcat{}.call(a, b)
pub const OperatorConcat = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, a: anytype, b: anytype) ![]const u8 {
        // For strings, concatenate
        const T = @TypeOf(a);
        if (T == []const u8 or T == []u8) {
            return std.fmt.allocPrint(allocator, "{s}{s}", .{ a, b });
        }
        // For other sequences, we'd need list concatenation
        return std.fmt.allocPrint(allocator, "{any}{any}", .{ a, b });
    }
};

/// operator.lt callable - less than comparison
pub const OperatorLt = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a < b;
    }
};

/// operator.le callable - less than or equal comparison
pub const OperatorLe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a <= b;
    }
};

/// operator.eq callable - equality comparison
pub const OperatorEq = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return std.meta.eql(a, b);
    }
};

/// operator.ne callable - inequality comparison
pub const OperatorNe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return !std.meta.eql(a, b);
    }
};

/// operator.ge callable - greater than or equal comparison
pub const OperatorGe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a >= b;
    }
};

/// operator.gt callable - greater than comparison
pub const OperatorGt = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a > b;
    }
};

/// operator.abs callable - absolute value
pub const OperatorAbs = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return if (a < 0) -a else a;
    }
};

/// operator.add callable - addition
pub const OperatorAdd = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a + b;
    }
};

/// operator.and_ callable - bitwise and
pub const OperatorAnd = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a & b;
    }
};

/// operator.or_ callable - bitwise or
pub const OperatorOr = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a | b;
    }
};

/// operator.xor callable - bitwise xor
pub const OperatorXor = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a ^ b;
    }
};

/// operator.neg callable - negation
pub const OperatorNeg = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return -a;
    }
};

/// operator.pos callable - positive (identity for numbers)
pub const OperatorPos = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return a;
    }
};

/// operator.sub callable - subtraction
pub const OperatorSub = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a - b;
    }
};

/// operator.mul callable - multiplication
pub const OperatorMul = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a * b;
    }
};

/// operator.truediv callable - true division
pub const OperatorTruediv = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) f64 {
        const af: f64 = switch (@typeInfo(@TypeOf(a))) {
            .float, .comptime_float => @as(f64, a),
            .int, .comptime_int => @as(f64, @floatFromInt(a)),
            else => 0.0,
        };
        const bf: f64 = switch (@typeInfo(@TypeOf(b))) {
            .float, .comptime_float => @as(f64, b),
            .int, .comptime_int => @as(f64, @floatFromInt(b)),
            else => 1.0,
        };
        return af / bf;
    }
};

/// operator.floordiv callable - floor division
pub const OperatorFloordiv = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return @divFloor(a, b);
    }
};

/// operator.lshift callable - left shift
pub const OperatorLshift = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
        return a << shift;
    }
};

/// operator.rshift callable - right shift
pub const OperatorRshift = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
        return a >> shift;
    }
};

/// operator.invert callable - bitwise inversion
pub const OperatorInvert = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return ~a;
    }
};

/// Python type name constants for type() comparisons
/// These are used when comparing `type(x) == complex`, `type(x) == int`, etc.
/// They need to match the Zig type names returned by @typeName
pub const complex = "complex"; // Note: Zig doesn't have native complex; this is for API compatibility
pub const int = "i64";
pub const float = "f64";
pub const @"bool" = "bool";
pub const @"type" = "type";

/// Builtin format callable - for when format is used as first-class value
/// format(value, format_spec) -> str
pub const FormatBuiltin = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, value: anytype, format_spec: anytype) PythonError![]const u8 {
        // Convert format_spec to slice if it's a single char
        const spec_slice: []const u8 = blk: {
            const SpecType = @TypeOf(format_spec);
            if (SpecType == []const u8 or SpecType == []u8) {
                break :blk format_spec;
            } else if (SpecType == u8) {
                // Single char - create a slice
                const buf = allocator.alloc(u8, 1) catch return PythonError.TypeError;
                buf[0] = format_spec;
                break :blk buf;
            } else {
                return PythonError.TypeError;
            }
        };

        // Check if format_spec is "s" but value is not a string
        // Python raises TypeError for format(3.0, "s")
        const T = @TypeOf(value);
        if (std.mem.eql(u8, spec_slice, "s")) {
            // "s" format is only valid for strings
            if (T != []const u8 and T != []u8) {
                return PythonError.TypeError;
            }
            return value;
        }
        // For numbers, format as string
        return std.fmt.allocPrint(allocator, "{any}", .{value}) catch return PythonError.TypeError;
    }
};
pub const format = FormatBuiltin{};

/// Python round() builtin - rounds a float to the nearest integer or to ndigits
/// For infinity or NaN, raises OverflowError like Python does
/// round(x) -> int, round(x, ndigits) -> float
/// This version handles both 1 and 2 argument cases via variadic args tuple
pub fn round(value: anytype, args: anytype) PythonError!f64 {
    const T = @TypeOf(value);
    const ArgsT = @TypeOf(args);

    // Get ndigits from args tuple (if provided)
    const digits: i64 = blk: {
        // Check if args is a tuple type with fields
        if (@typeInfo(ArgsT) == .@"struct" and @typeInfo(ArgsT).@"struct".fields.len > 0) {
            // Get the first field (ndigits)
            const ndigits = args.@"0";
            const NdigitsT = @TypeOf(ndigits);
            // TypeError for non-integer ndigits types (float, complex, string, etc.)
            if (@typeInfo(NdigitsT) == .float) {
                return PythonError.TypeError;
            } else if (NdigitsT == bool) {
                // Python treats bool as int: True=1, False=0
                break :blk @as(i64, @intFromBool(ndigits));
            } else if (@typeInfo(NdigitsT) == .int or @typeInfo(NdigitsT) == .comptime_int) {
                break :blk @as(i64, @intCast(ndigits));
            } else if (@typeInfo(NdigitsT) == .@"struct") {
                // Check for PyComplex or other non-integer types
                if (@hasField(NdigitsT, "real") and @hasField(NdigitsT, "imag")) {
                    return PythonError.TypeError; // complex
                }
                // Check for __int__ method on other struct types
                if (@hasDecl(NdigitsT, "__int__")) {
                    const int_result = ndigits.__int__();
                    break :blk @as(i64, @intCast(int_result));
                }
                return PythonError.TypeError;
            } else {
                return PythonError.TypeError;
            }
        } else {
            // No ndigits provided
            break :blk 0;
        }
    };

    // Check if ndigits was explicitly provided
    const has_ndigits = @typeInfo(ArgsT) == .@"struct" and @typeInfo(ArgsT).@"struct".fields.len > 0;

    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        // Check for special float values (only for no ndigits case)
        if (std.math.isNan(value)) {
            if (!has_ndigits) {
                return PythonError.ValueError;
            }
            // With ndigits, return NaN
            return value;
        }
        if (std.math.isInf(value)) {
            if (!has_ndigits) {
                return PythonError.OverflowError;
            }
            // With ndigits, return inf
            return value;
        }

        if (!has_ndigits or digits == 0) {
            // Round to nearest integer using banker's rounding (round half to even)
            return bankersRound(value);
        } else if (digits > 0) {
            // Round to ndigits decimal places using banker's rounding
            // For very large ndigits (> 308), the precision requested exceeds f64's
            // ~15-17 significant digits, so just return the original value unchanged.
            // Python: round(123.456, 324) == 123.456
            if (digits > 308) {
                return value;
            }
            const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(digits)));
            // Check for multiplier overflow (shouldn't happen with digits <= 308)
            if (std.math.isInf(multiplier)) {
                return value; // Can't round further than f64 precision
            }
            const scaled = value * multiplier;
            // Check for overflow in scaled value
            if (std.math.isInf(scaled)) {
                return value; // Value too large to scale, return unchanged
            }
            const rounded_scaled = bankersRound(scaled);
            const result = rounded_scaled / multiplier;
            // For very large numbers, avoid precision loss by checking if
            // the original value fits in the precision requested
            const diff = @abs(result - value);
            const epsilon = @abs(value) * 1e-14; // relative tolerance
            if (diff < epsilon) {
                return value;
            }
            return result;
        } else {
            // Negative ndigits - round to tens, hundreds, etc.
            // For very negative ndigits (< -308), the scale exceeds f64 range.
            // Python: round(123.456, -309) == 0.0 (preserves sign for -0.0)
            if (digits < -308) {
                // Result would be 0.0 (or -0.0 for negative values)
                return if (value < 0) -0.0 else 0.0;
            }
            const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-digits)));
            // Check for multiplier overflow
            if (std.math.isInf(multiplier)) {
                // Scale too large - result rounds to zero
                return if (value < 0) -0.0 else 0.0;
            }
            const scaled = value / multiplier;
            const result = bankersRound(scaled) * multiplier;
            // Check if result overflows
            if (std.math.isInf(result) and !std.math.isInf(value)) {
                return PythonError.OverflowError;
            }
            return result;
        }
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @as(f64, @floatFromInt(value));
    } else {
        return PythonError.TypeError;
    }
}

/// Python's banker's rounding: round half to even
/// This is different from Zig's @round which rounds away from zero
fn bankersRound(value: f64) f64 {
    // Handle edge cases
    if (std.math.isNan(value) or std.math.isInf(value)) {
        return value;
    }

    const floored = @floor(value);
    const frac = @abs(value - floored);

    if (frac < 0.5) {
        return floored;
    } else if (frac > 0.5) {
        return floored + 1.0;
    } else {
        // Exactly 0.5 - round to even
        const floored_int: i64 = @intFromFloat(floored);
        if (@mod(floored_int, 2) == 0) {
            return floored; // floored is even, stay there
        } else {
            return floored + 1.0; // floored is odd, go to even
        }
    }
}


/// Operator comparison functions that handle heterogeneous types
/// These are used when operator module functions are imported via "from operator import eq"
/// These handle both primitive types and user-defined classes with dunder methods.
/// For classes that don't return bool from comparison, we return false (TypeError behavior).

/// operator.eq - equality comparison for any two types
pub fn operatorEq(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // For same primitive types, use direct comparison
    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .bool or info == .comptime_int or info == .comptime_float) {
            return a == b;
        }
    }

    // For custom classes, check if __eq__ returns bool (not class instance)
    // Many test classes return self or raise TypeError - skip those
    // We can't call at comptime if return type varies, so just return false for different types
    return false;
}

/// operator.ne - inequality comparison
pub fn operatorNe(a: anytype, b: anytype) bool {
    return !operatorEq(a, b);
}

/// operator.lt - less than comparison
pub fn operatorLt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a < b;
        }
    }

    return false;
}

/// operator.le - less than or equal comparison
pub fn operatorLe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a <= b;
        }
    }

    return false;
}

/// operator.gt - greater than comparison
pub fn operatorGt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a > b;
        }
    }

    return false;
}

/// operator.ge - greater than or equal comparison
pub fn operatorGe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a >= b;
        }
    }

    return false;
}

/// Class instance equality comparison
/// Calls __eq__ method on the class instance, handling different method signatures:
/// - Some __eq__ take (self, other) - 2 args
/// - Some __eq__ take (self, allocator, other) - 3 args
/// The result can be bool or error union bool
pub fn classInstanceEq(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    // Check if type has __eq__ method
    if (type_info == .@"struct" and @hasDecl(TypeA, "__eq__")) {
        const eq_info = @typeInfo(@TypeOf(TypeA.__eq__));
        if (eq_info == .@"fn") {
            const params = eq_info.@"fn".params;
            // Call with appropriate number of arguments
            const result = if (params.len == 3)
                a.__eq__(allocator, b) // (self, allocator, other)
            else
                a.__eq__(b); // (self, other)

            // Handle error union
            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch false;
            } else if (ResultType == bool) {
                return result;
            }
        }
    }

    // Fallback: use identity comparison
    return false;
}

/// Class instance not-equal comparison
pub fn classInstanceNe(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    // Check if type has __ne__ method
    if (type_info == .@"struct" and @hasDecl(TypeA, "__ne__")) {
        const ne_info = @typeInfo(@TypeOf(TypeA.__ne__));
        if (ne_info == .@"fn") {
            const params = ne_info.@"fn".params;
            const result = if (params.len == 3)
                a.__ne__(allocator, b)
            else
                a.__ne__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch true; // On error, assume not equal
            } else if (ResultType == bool) {
                return result;
            }
        }
    }

    // Fallback: use negation of __eq__
    return !classInstanceEq(a, b, allocator);
}

// ============================================================================
// Type constructor callables - for use as first-class values in lists
// These allow patterns like: for constructor in list, tuple, set: ...
// ============================================================================

/// list() type constructor - creates a new list from an iterable
/// Used as first-class value in patterns like: constructors = [list, tuple, set]
pub const list = struct {
    /// Call as list() or list(iterable)
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        // If no arg (void), return empty list
        if (T == void) {
            return try PyList.create(allocator);
        }
        // If arg is a PyObject list, clone it
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyList.create(allocator);
                for (source.items.items) |item| {
                    incref(item);
                    try PyList.append(result, item);
                }
                return result;
            }
        }
        // Return empty list for unsupported types
        return try PyList.create(allocator);
    }
}{};

/// tuple() type constructor - creates a new tuple from an iterable
pub const tuple = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) {
            return try PyTuple.create(allocator, 0);
        }
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyTuple.create(allocator, source.items.items.len);
                for (source.items.items, 0..) |item, i| {
                    incref(item);
                    PyTuple.setItem(result, i, item);
                }
                return result;
            }
        }
        return try PyTuple.create(allocator, 0);
    }
}{};

/// set() type constructor - creates a new set from an iterable
pub const set = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        _ = arg;
        // For now, return an empty list as placeholder (set not fully implemented)
        return try PyList.create(allocator);
    }
}{};

/// frozenset() type constructor - creates an immutable set
pub const frozenset = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        _ = arg;
        // For now, return an empty list as placeholder
        return try PyList.create(allocator);
    }
}{};

/// deque() type constructor - creates a double-ended queue
pub const deque = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        _ = arg;
        // For now, use a list as deque (same underlying structure)
        return try PyList.create(allocator);
    }
}{};

// ============================================================================
// Basic I/O builtins - hex, oct, bin, input, breakpoint, print
// ============================================================================

/// hex(x) - convert integer to hexadecimal string with "0x" prefix
/// For negative numbers, produces "-0x..." format
pub fn hex(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            // BigInt
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0x{x}", .{@as(u64, @intCast(int_val))}) catch "0x0";
    } else {
        return std.fmt.allocPrint(allocator, "-0x{x}", .{@as(u64, @intCast(-int_val))}) catch "-0x0";
    }
}

/// oct(x) - convert integer to octal string with "0o" prefix
pub fn oct(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0o{o}", .{@as(u64, @intCast(int_val))}) catch "0o0";
    } else {
        return std.fmt.allocPrint(allocator, "-0o{o}", .{@as(u64, @intCast(-int_val))}) catch "-0o0";
    }
}

/// bin(x) - convert integer to binary string with "0b" prefix
pub fn bin(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0b{b}", .{@as(u64, @intCast(int_val))}) catch "0b0";
    } else {
        return std.fmt.allocPrint(allocator, "-0b{b}", .{@as(u64, @intCast(-int_val))}) catch "-0b0";
    }
}

/// input([prompt]) - read line from stdin
/// Returns the line without trailing newline
pub fn input(allocator: std.mem.Allocator, prompt: []const u8) []const u8 {
    // Print prompt to stdout
    if (prompt.len > 0) {
        _ = std.posix.write(std.posix.STDOUT_FILENO, prompt) catch {};
    }

    // Read line from stdin
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    var stdin_buf: [4096]u8 = undefined;
    const stdin = stdin_file.reader(&stdin_buf);
    const line = stdin.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |err| {
        if (err == error.EndOfStream) {
            return "";
        }
        return "";
    };

    // Strip trailing \r if present (Windows line endings)
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

/// breakpoint() - drop into debugger
/// In release builds, this is a no-op. In debug builds, triggers @breakpoint
pub fn breakpoint() void {
    if (@import("builtin").mode == .Debug) {
        @breakpoint();
    }
}

/// print(*args) - print values to stdout with space separator and newline
pub fn print(allocator: std.mem.Allocator, args: anytype) void {
    // Build the output string first, then write to stdout
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    // Handle tuple/array of args
    if (args_info == .pointer and args_info.pointer.size == .slice) {
        for (args, 0..) |arg, i| {
            if (i > 0) output.append(allocator, ' ') catch {};
            printValueToList(&output, arg, allocator);
        }
    } else if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
        inline for (args_info.@"struct".fields, 0..) |field, i| {
            if (i > 0) output.append(allocator, ' ') catch {};
            printValueToList(&output, @field(args, field.name), allocator);
        }
    }
    output.append(allocator, '\n') catch {};
    _ = std.posix.write(std.posix.STDOUT_FILENO, output.items) catch {};
}

fn printValueToList(output: *std.ArrayList(u8), value: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (T == []const u8 or T == []u8) {
        output.appendSlice(allocator, value) catch {};
    } else if (info == .int or info == .comptime_int) {
        var buf: [32]u8 = undefined;
        const int_len = std.fmt.formatIntBuf(&buf, value, 10, .lower, .{});
        output.appendSlice(allocator, buf[0..int_len]) catch {};
    } else if (info == .float or info == .comptime_float) {
        // Python convention: nan never has sign
        if (std.math.isNan(value)) {
            output.appendSlice(allocator, "nan") catch {};
        } else if (std.math.isInf(value)) {
            output.appendSlice(allocator, if (value < 0) "-inf" else "inf") catch {};
        } else {
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            output.appendSlice(allocator, formatted) catch {};
        }
    } else if (info == .bool) {
        output.appendSlice(allocator, if (value) "True" else "False") catch {};
    } else if (T == *PyObject) {
        // Use PyObject string representation
        if (value.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(value.data));
            output.appendSlice(allocator, str_obj.data) catch {};
        } else if (value.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(value.data));
            var buf: [32]u8 = undefined;
            const pyint_len = std.fmt.formatIntBuf(&buf, int_obj.value, 10, .lower, .{});
            output.appendSlice(allocator, buf[0..pyint_len]) catch {};
        } else {
            output.appendSlice(allocator, "<object>") catch {};
        }
    } else {
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch {};
    }
}

// Legacy function kept for compatibility
fn printValue(writer: anytype, value: anytype, allocator: std.mem.Allocator) void {
    _ = allocator;
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (T == []const u8 or T == []u8) {
        writer.print("{s}", .{value}) catch {};
    } else if (info == .int or info == .comptime_int) {
        writer.print("{d}", .{value}) catch {};
    } else if (info == .float or info == .comptime_float) {
        writer.print("{d}", .{value}) catch {};
    } else if (info == .bool) {
        writer.print("{s}", .{if (value) "True" else "False"}) catch {};
    } else if (T == *PyObject) {
        // Use PyObject string representation
        if (value.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(value.data));
            writer.print("{s}", .{str_obj.data}) catch {};
        } else if (value.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(value.data));
            writer.print("{d}", .{int_obj.value}) catch {};
        } else {
            writer.print("<object>", .{}) catch {};
        }
    } else {
        writer.print("{any}", .{value}) catch {};
    }
}

/// dict namespace - for dict.fromkeys and other class methods
/// Note: dict is a namespace struct (type), not an instance, so dict.fromkeys works
/// For dict() constructor calls, codegen should emit PyDict.create() directly
pub const dict = struct {
    /// dict.fromkeys(keys, value=None) - create dict with keys from iterable
    pub const fromkeys = struct {
        /// Create a None PyObject
        fn makeNone(allocator: std.mem.Allocator) !*PyObject {
            const obj = try allocator.create(PyObject);
            obj.* = .{
                .ref_count = 1,
                .type_id = .none,
                .data = undefined,
            };
            return obj;
        }

        pub fn call(_: @This(), allocator: std.mem.Allocator, keys: anytype, value: anytype) !*PyObject {
            const result = try PyDict.create(allocator);
            const KeysType = @TypeOf(keys);

            // Handle different key sources
            if (KeysType == *PyObject) {
                if (keys.type_id == .list) {
                    const src_list: *PyList = @ptrCast(@alignCast(keys.data));
                    for (src_list.items.items) |key| {
                        // Use value if provided, otherwise None
                        const val = blk: {
                            const ValType = @TypeOf(value);
                            if (ValType == void or ValType == @TypeOf(null)) {
                                break :blk try makeNone(allocator);
                            }
                            break :blk value;
                        };
                        try PyDict.setItem(result, key, val);
                    }
                } else if (keys.type_id == .tuple) {
                    const src_tuple: *PyTuple = @ptrCast(@alignCast(keys.data));
                    for (src_tuple.items) |key| {
                        const val = blk: {
                            const ValType = @TypeOf(value);
                            if (ValType == void or ValType == @TypeOf(null)) {
                                break :blk try makeNone(allocator);
                            }
                            break :blk value;
                        };
                        try PyDict.setItem(result, key, val);
                    }
                }
            }

            return result;
        }
    }{};
};
