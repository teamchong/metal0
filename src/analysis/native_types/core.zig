const std = @import("std");

// Re-export from split modules
pub const containers = @import("containers.zig");
pub const attributes = @import("attributes.zig");

// Re-export commonly used types and functions for backwards compatibility
pub const parseTypeAnnotation = containers.parseTypeAnnotation;
pub const pythonTypeHintToNative = containers.pythonTypeHintToNative;
pub const InferError = containers.InferError;

pub const isConstantList = attributes.isConstantList;
pub const allSameType = attributes.allSameType;
pub const ClassInfo = attributes.ClassInfo;
pub const FunctionSignature = attributes.FunctionSignature;
pub const needsAllocator = attributes.needsAllocator;
pub const isErrorUnion = attributes.isErrorUnion;

/// String type kinds for optimization and tracking
pub const StringKind = enum {
    literal, // Compile-time "hello" - can be optimized
    runtime, // Dynamically allocated (from methods, concat, etc.)
    slice, // []const u8 slice from operations

    /// All string kinds map to []const u8 in Zig
    pub fn toZigType(self: StringKind) []const u8 {
        _ = self;
        return "[]const u8";
    }
};

/// Native Zig types inferred from Python code
pub const NativeType = union(enum) {
    // Primitives - stack allocated, zero overhead
    int: void, // i64
    usize: void, // usize (for array indices)
    float: void, // f64
    bool: void, // bool
    string: StringKind, // []const u8 - tracks allocation/optimization hint

    // Composites
    array: struct {
        element_type: *const NativeType,
        length: usize, // Comptime-known length
    }, // [N]T - fixed-size array
    list: *const NativeType, // ArrayList(T) - dynamic list
    dict: struct {
        key: *const NativeType,
        value: *const NativeType,
    }, // StringHashMap(V)
    set: *const NativeType, // StringHashMap(void) or AutoHashMap(T, void)
    tuple: []const NativeType, // Zig tuple struct

    // Functions
    closure: []const u8, // Closure struct name (__Closure_N)
    function: struct {
        params: []const NativeType,
        return_type: *const NativeType,
    }, // Function pointer type: *const fn(T, U) R

    // Library types (DEPRECATED - remove after implementing Python classes properly)
    dataframe: void, // DEPRECATED: pandas.DataFrame - should be generic class type

    // Class types
    class_instance: []const u8, // Instance of a custom class (stores class name)

    // Special
    optional: *const NativeType, // Optional[T] - Zig optional (?T)
    none: void, // void or ?T
    unknown: void, // Fallback to PyObject* (should be rare)
    path: void, // pathlib.Path
    flask_app: void, // flask.Flask application instance
    numpy_array: void, // NumPy ndarray - wraps *runtime.PyObject with numpy_array type_id
    bool_array: void, // Boolean array - result of numpy comparison operations
    usize_slice: void, // []const usize - used for numpy shape/strides
    stringio: void, // io.StringIO in-memory text stream
    bytesio: void, // io.BytesIO in-memory binary stream
    file: void, // File object from open()
    hash_object: void, // hashlib hash object (md5, sha256, etc.)
    counter: void, // collections.Counter - hashmap_helper.StringHashMap(i64)
    deque: void, // collections.deque - std.ArrayList
    sqlite_connection: void, // sqlite3.Connection - database connection
    sqlite_cursor: void, // sqlite3.Cursor - database cursor

    /// Check if this is a simple type (int, float, bool, string, class_instance, optional)
    /// Simple types can be const even if semantic analyzer reports them as mutated
    /// (workaround for semantic analyzer false positives)
    pub fn isSimpleType(self: NativeType) bool {
        return switch (self) {
            .int, .usize, .float, .bool, .string, .class_instance, .optional, .none => true,
            else => false,
        };
    }

    /// Comptime check if type is a native primitive (not PyObject)
    pub fn isNativePrimitive(self: NativeType) bool {
        return switch (self) {
            .int, .usize, .float, .bool, .string => true,
            else => false,
        };
    }

    /// Comptime check if type needs PyObject wrapping
    pub fn needsPyObjectWrapper(self: NativeType) bool {
        return switch (self) {
            .unknown, .list, .dict, .set, .tuple => true,
            else => false,
        };
    }

    /// Get format specifier for std.debug.print
    pub fn getPrintFormat(self: NativeType) []const u8 {
        return switch (self) {
            .int, .usize => "{d}",
            .float => "{d}",
            .bool => "{}",
            .string => "{s}",
            else => "{any}",
        };
    }

    /// Returns Zig type string for simple/primitive types (no allocation needed)
    pub fn toSimpleZigType(self: NativeType) []const u8 {
        return switch (self) {
            .int => "i64",
            .float => "f64",
            .bool => "bool",
            .string => "[]const u8",
            .usize => "usize",
            .path => "*pathlib.Path",
            else => "*runtime.PyObject",
        };
    }

    /// Convert to Zig type string
    pub fn toZigType(self: NativeType, allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
        const hashmap_helper = @import("hashmap_helper");
        _ = hashmap_helper;

        switch (self) {
            .int => try buf.appendSlice(allocator, "i64"),
            .usize => try buf.appendSlice(allocator, "usize"),
            .float => try buf.appendSlice(allocator, "f64"),
            .bool => try buf.appendSlice(allocator, "bool"),
            .string => try buf.appendSlice(allocator, "[]const u8"),
            .array => |arr| {
                const len_str = try std.fmt.allocPrint(allocator, "[{d}]", .{arr.length});
                defer allocator.free(len_str);
                try buf.appendSlice(allocator, len_str);
                try arr.element_type.toZigType(allocator, buf);
            },
            .list => |elem_type| {
                try buf.appendSlice(allocator, "std.ArrayList(");
                try elem_type.toZigType(allocator, buf);
                try buf.appendSlice(allocator, ")");
            },
            .dict => |kv| {
                // Use StringHashMap for string keys, AutoHashMap for int keys
                if (kv.key.* == .string) {
                    try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(");
                    try kv.value.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ")");
                } else if (kv.key.* == .int) {
                    try buf.appendSlice(allocator, "std.AutoHashMap(i64, ");
                    try kv.value.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ")");
                } else {
                    // Default to StringHashMap for unknown key types
                    try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(");
                    try kv.value.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ")");
                }
            },
            .set => |elem_type| {
                // For string sets use StringHashMap, for others use AutoHashMap
                if (elem_type.* == .string) {
                    try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(void)");
                } else {
                    try buf.appendSlice(allocator, "std.AutoHashMap(");
                    try elem_type.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ", void)");
                }
            },
            .tuple => |types| {
                try buf.appendSlice(allocator, "struct { ");
                for (types, 0..) |t, i| {
                    const field_buf = try std.fmt.allocPrint(allocator, "@\"{d}\": ", .{i});
                    defer allocator.free(field_buf);
                    try buf.appendSlice(allocator, field_buf);
                    try t.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ", ");
                }
                try buf.appendSlice(allocator, "}");
            },
            .closure => |name| try buf.appendSlice(allocator, name),
            .function => |fn_type| {
                try buf.appendSlice(allocator, "*const fn (");
                for (fn_type.params, 0..) |param, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    try param.toZigType(allocator, buf);
                }
                try buf.appendSlice(allocator, ") ");
                try fn_type.return_type.toZigType(allocator, buf);
            },
            .dataframe => try buf.appendSlice(allocator, "pandas.DataFrame"),
            .class_instance => |class_name| {
                // For class instances, use the class name as the type (not pointer)
                try buf.appendSlice(allocator, class_name);
            },
            .optional => |inner_type| {
                try buf.appendSlice(allocator, "?");
                try inner_type.toZigType(allocator, buf);
            },
            .none => try buf.appendSlice(allocator, "?void"),
            .unknown => try buf.appendSlice(allocator, "*runtime.PyObject"),
            .path => try buf.appendSlice(allocator, "*pathlib.Path"),
            .flask_app => try buf.appendSlice(allocator, "*runtime.flask.Flask"),
            .numpy_array => try buf.appendSlice(allocator, "*runtime.PyObject"),
            .bool_array => try buf.appendSlice(allocator, "*runtime.PyObject"),
            .usize_slice => try buf.appendSlice(allocator, "[]const usize"),
            .stringio => try buf.appendSlice(allocator, "*runtime.io.StringIO"),
            .bytesio => try buf.appendSlice(allocator, "*runtime.io.BytesIO"),
            .file => try buf.appendSlice(allocator, "*runtime.PyFile"),
            .hash_object => try buf.appendSlice(allocator, "hashlib.HashObject"),
            .counter => try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(i64)"),
            .deque => try buf.appendSlice(allocator, "std.ArrayList(i64)"),
            .sqlite_connection => try buf.appendSlice(allocator, "sqlite3.Connection"),
            .sqlite_cursor => try buf.appendSlice(allocator, "sqlite3.Cursor"),
        }
    }

    /// Promote/widen types for compatibility
    /// Follows Python's type promotion hierarchy: int < float < string < unknown
    pub fn widen(self: NativeType, other: NativeType) NativeType {
        // Get tags for comparison
        const self_tag = @as(std.meta.Tag(NativeType), self);
        const other_tag = @as(std.meta.Tag(NativeType), other);

        // If either is unknown, result is unknown (fallback to PyObject)
        if (self_tag == .unknown or other_tag == .unknown) return .unknown;

        // If types match, no widening needed
        if (self_tag == other_tag) {
            return self;
        }

        // String "wins" over everything (str() is universal)
        // When one is string, result is runtime string (most general)
        if (self_tag == .string or other_tag == .string) return .{ .string = .runtime };

        // Float can hold ints, so float "wins"
        if ((self_tag == .float and other_tag == .int) or
            (self_tag == .int and other_tag == .float)) return .float;

        // usize and int mix → promote to int (i64 can represent both)
        if ((self_tag == .usize and other_tag == .int) or
            (self_tag == .int and other_tag == .usize)) return .int;

        // usize and float → promote to float
        if ((self_tag == .usize and other_tag == .float) or
            (self_tag == .float and other_tag == .usize)) return .float;

        // IO and collection types stay as their own types (no widening)
        if (self_tag == .stringio or self_tag == .bytesio or self_tag == .file or self_tag == .hash_object or self_tag == .counter or self_tag == .deque) return self;
        if (other_tag == .stringio or other_tag == .bytesio or other_tag == .file or other_tag == .hash_object or other_tag == .counter or other_tag == .deque) return other;

        // Different incompatible types → fallback to unknown
        return .unknown;
    }

    /// Comptime analysis: Does this type need allocator for operations?
    pub fn needsAllocator(self: NativeType) bool {
        return attributes.needsAllocator(self);
    }

    /// Comptime check: Is return type error union?
    pub fn isErrorUnion(self: NativeType) bool {
        return attributes.isErrorUnion(self);
    }
};
