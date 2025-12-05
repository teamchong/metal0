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

/// Integer boundedness for overflow safety
/// Tracks whether an integer's range is known at compile time
pub const IntKind = enum {
    /// Bounded integer - proven to fit in i64 (constants, range() indices, etc.)
    /// Safe to use native i64 operations without overflow checking
    bounded,

    /// Unbounded integer - could be any value (user input, file read, network, etc.)
    /// Must use BigInt to prevent silent overflow
    unbounded,

    /// Check if this integer kind requires BigInt representation
    pub fn needsBigInt(self: IntKind) bool {
        return self == .unbounded;
    }

    /// Combine two int kinds - unbounded "taints" the result
    pub fn combine(self: IntKind, other: IntKind) IntKind {
        if (self == .unbounded or other == .unbounded) {
            return .unbounded;
        }
        return .bounded;
    }
};

/// Native Zig types inferred from Python code
pub const NativeType = union(enum) {
    // Primitives - stack allocated, zero overhead
    int: IntKind, // i64 (bounded) or BigInt (unbounded)
    bigint: void, // runtime.BigInt - arbitrary precision integer (always)
    usize: void, // usize (for array indices, always bounded)
    float: void, // f64
    bool: void, // bool
    string: StringKind, // []const u8 - tracks allocation/optimization hint
    bytes: void, // runtime.builtins.PyBytes - Python bytes type (preserves type info for repr)
    complex: void, // runtime.PyComplex - complex number

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
    callable: void, // Type-erased callable (PyCallable) - for heterogeneous callable lists

    // Class types
    class_instance: []const u8, // Instance of a custom class (stores class name)

    // Special
    optional: *const NativeType, // Optional[T] - Zig optional (?T)
    none: void, // void or ?T
    pyvalue: void, // runtime.PyValue - heterogeneous value (for tuple->list conversion)
    unknown: void, // Fallback to PyObject* (should be rare)
    path: void, // pathlib.Path
    usize_slice: void, // []const usize - used for slices
    slice: *const NativeType, // []const T - runtime-sized slice (from list * runtime_n)
    stringio: void, // io.StringIO in-memory text stream
    bytesio: void, // io.BytesIO in-memory binary stream
    file: void, // File object from open()
    hash_object: void, // hashlib hash object (md5, sha256, etc.)
    counter: void, // collections.Counter - hashmap_helper.StringHashMap(i64)
    deque: void, // collections.deque - std.ArrayList
    sqlite_connection: void, // sqlite3.Connection - database connection
    sqlite_cursor: void, // sqlite3.Cursor - database cursor
    sqlite_rows: void, // []sqlite3.Row - result from fetchall/fetchmany
    sqlite_row: void, // ?sqlite3.Row - result from fetchone
    exception: []const u8, // Exception type - stores exception name (RuntimeError, ValueError, etc.)
    cdll: []const u8, // ctypes.CDLL - stores library path for FFI
    c_func: struct {
        library: []const u8, // Library name (for lookup)
        func_name: []const u8, // Function name in the library
    }, // ctypes function pointer from CDLL attribute access
    pyobject: []const u8, // PyObject from C extension module (stores module name)

    // subprocess types
    subprocess_result: void, // subprocess.run() returns CompletedProcess-like struct
    subprocess_status_output: void, // subprocess.getstatusoutput() returns (int, str) tuple
    subprocess_popen: void, // subprocess.Popen object

    // csv types - iterator objects that yield rows
    csv_reader: void, // csv.reader() - yields [][]const u8 rows
    csv_writer: void, // csv.writer() - has writerow/writerows methods
    csv_dict_reader: void, // csv.DictReader() - yields StringHashMap rows
    csv_dict_writer: void, // csv.DictWriter() - has writerow/writeheader methods
    csv_row: void, // Single row from csv.reader - [][]const u8

    // datetime types
    datetime_datetime: void, // datetime.datetime - runtime.datetime.Datetime struct
    datetime_date: void, // datetime.date - runtime.datetime.Date struct
    datetime_time: void, // datetime.time - runtime.datetime.Time struct
    datetime_timedelta: void, // datetime.timedelta - runtime.datetime.Timedelta struct

    // re module types
    re_match: void, // re.Match - result of re.search/re.match
    re_pattern: void, // re.Pattern - compiled regex pattern

    // Iterator types
    list_iterator: void, // iter() on list - SequenceIterator(i64)

    /// Check if this is a simple type (int, bigint, float, bool, string, class_instance, optional)
    /// Simple types can be const even if semantic analyzer reports them as mutated
    /// (workaround for semantic analyzer false positives)
    pub fn isSimpleType(self: NativeType) bool {
        return switch (self) {
            .int => true,
            .bigint, .usize, .float, .bool, .string, .class_instance, .optional, .none => true,
            else => false,
        };
    }

    /// Comptime check if type is a native primitive (not PyObject)
    pub fn isNativePrimitive(self: NativeType) bool {
        return switch (self) {
            .int => |kind| !kind.needsBigInt(), // Only bounded ints are native primitives
            .usize, .float, .bool, .string => true,
            .bigint => false, // BigInt is heap-allocated
            else => false,
        };
    }

    /// Check if this is an unbounded integer that needs BigInt
    pub fn isUnboundedInt(self: NativeType) bool {
        return switch (self) {
            .int => |kind| kind.needsBigInt(),
            else => false,
        };
    }

    /// Get the IntKind if this is an int type
    pub fn getIntKind(self: NativeType) ?IntKind {
        return switch (self) {
            .int => |kind| kind,
            else => null,
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
            .int => "{d}",
            .bigint, .usize => "{d}",
            .float => "{d}",
            .bool => "{}",
            .string => "{s}",
            else => "{any}",
        };
    }

    /// Returns Zig type string for simple/primitive types (no allocation needed)
    pub fn toSimpleZigType(self: NativeType) []const u8 {
        return switch (self) {
            .int => |kind| if (kind.needsBigInt()) "runtime.BigInt" else "i64",
            .bigint => "runtime.BigInt",
            .float => "f64",
            .bool => "bool",
            .string => "[]const u8",
            .bytes => "runtime.builtins.PyBytes",
            .usize => "usize",
            .path => "*pathlib.Path",
            // Use *runtime.PyObject for class instances to avoid forward reference issues
            .class_instance => "*runtime.PyObject",
            else => "*runtime.PyObject",
        };
    }

    /// Convert to Zig type string
    pub fn toZigType(self: NativeType, allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
        const hashmap_helper = @import("hashmap_helper");
        _ = hashmap_helper;

        switch (self) {
            .int => |kind| {
                if (kind.needsBigInt()) {
                    try buf.appendSlice(allocator, "runtime.BigInt");
                } else {
                    try buf.appendSlice(allocator, "i64");
                }
            },
            .bigint => try buf.appendSlice(allocator, "runtime.BigInt"),
            .usize => try buf.appendSlice(allocator, "usize"),
            .float => try buf.appendSlice(allocator, "f64"),
            .bool => try buf.appendSlice(allocator, "bool"),
            .string => try buf.appendSlice(allocator, "[]const u8"),
            .bytes => try buf.appendSlice(allocator, "runtime.builtins.PyBytes"),
            .complex => try buf.appendSlice(allocator, "runtime.PyComplex"),
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
                const key_tag = @as(std.meta.Tag(NativeType), kv.key.*);
                if (key_tag == .string) {
                    try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(");
                    try kv.value.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ")");
                } else if (key_tag == .int) {
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
                // Generate Zig tuple type with positional fields (no names)
                // This matches the anonymous struct literal syntax: .{ val0, val1, ... }
                try buf.appendSlice(allocator, "struct { ");
                for (types) |t| {
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
            .class_instance => |_| {
                // For class instances, use *runtime.PyObject to avoid forward reference issues
                // with local classes and to handle dynamically-created types correctly.
                // All Python class instances are PyObjects at runtime.
                try buf.appendSlice(allocator, "*runtime.PyObject");
            },
            .optional => |inner_type| {
                try buf.appendSlice(allocator, "?");
                try inner_type.toZigType(allocator, buf);
            },
            .none => try buf.appendSlice(allocator, "?void"),
            .pyvalue => try buf.appendSlice(allocator, "runtime.PyValue"),
            .unknown => try buf.appendSlice(allocator, "*runtime.PyObject"),
            .path => try buf.appendSlice(allocator, "*pathlib.Path"),
            .usize_slice => try buf.appendSlice(allocator, "[]const usize"),
            .slice => |elem_type| {
                try buf.appendSlice(allocator, "[]const ");
                try elem_type.toZigType(allocator, buf);
            },
            .stringio => try buf.appendSlice(allocator, "*runtime.io.StringIO"),
            .bytesio => try buf.appendSlice(allocator, "*runtime.io.BytesIO"),
            .file => try buf.appendSlice(allocator, "*runtime.PyObject"),
            .hash_object => try buf.appendSlice(allocator, "hashlib.HashObject"),
            .counter => try buf.appendSlice(allocator, "hashmap_helper.StringHashMap(i64)"),
            .deque => try buf.appendSlice(allocator, "std.ArrayList(i64)"),
            .sqlite_connection => try buf.appendSlice(allocator, "sqlite3.Connection"),
            .sqlite_cursor => try buf.appendSlice(allocator, "sqlite3.Cursor"),
            .sqlite_rows => try buf.appendSlice(allocator, "[]sqlite3.Row"),
            .sqlite_row => try buf.appendSlice(allocator, "?sqlite3.Row"),
            .exception => |exc_name| {
                // Exception type: *runtime.RuntimeError, *runtime.ValueError, etc.
                try buf.appendSlice(allocator, "*runtime.");
                try buf.appendSlice(allocator, exc_name);
            },
            .callable => try buf.appendSlice(allocator, "runtime.builtins.PyCallable"),
            .cdll => try buf.appendSlice(allocator, "runtime.ctypes.CDLL"),
            .c_func => try buf.appendSlice(allocator, "*const fn() callconv(.c) anyopaque"),
            .pyobject => try buf.appendSlice(allocator, "*runtime.PyObject"),
            // subprocess types
            .subprocess_result => try buf.appendSlice(allocator, "struct { returncode: i64, stdout: []const u8, stderr: []const u8 }"),
            .subprocess_status_output => try buf.appendSlice(allocator, "struct { @\"0\": i64, @\"1\": []const u8 }"),
            .subprocess_popen => try buf.appendSlice(allocator, "std.process.Child"),
            // csv types
            .csv_reader, .csv_writer, .csv_dict_reader, .csv_dict_writer => try buf.appendSlice(allocator, "*anyopaque"),
            .csv_row => try buf.appendSlice(allocator, "[][]const u8"),
            // datetime types
            .datetime_datetime => try buf.appendSlice(allocator, "runtime.datetime.Datetime"),
            .datetime_date => try buf.appendSlice(allocator, "runtime.datetime.Date"),
            .datetime_time => try buf.appendSlice(allocator, "runtime.datetime.Time"),
            .datetime_timedelta => try buf.appendSlice(allocator, "runtime.datetime.Timedelta"),
            // re module types
            .re_match => try buf.appendSlice(allocator, "*runtime.re.PyMatch"),
            .re_pattern => try buf.appendSlice(allocator, "*runtime.PyObject"),
            // Iterator types
            .list_iterator => try buf.appendSlice(allocator, "runtime.iterators.SequenceIterator(i64)"),
        }
    }

    /// Promote/widen types for compatibility
    /// Follows Python's type promotion hierarchy: int < bigint < float < string < unknown
    pub fn widen(self: NativeType, other: NativeType) NativeType {
        // Get tags for comparison
        const self_tag = @as(std.meta.Tag(NativeType), self);
        const other_tag = @as(std.meta.Tag(NativeType), other);

        // If one is unknown but the other is known, prefer the known type
        if (self_tag == .unknown and other_tag != .unknown) return other;
        if (other_tag == .unknown and self_tag != .unknown) return self;
        if (self_tag == .unknown and other_tag == .unknown) return .unknown;

        // PyValue absorbs everything - once heterogeneous, stays heterogeneous
        if (self_tag == .pyvalue or other_tag == .pyvalue) return .pyvalue;

        // If types match, no widening needed (except for tuples, arrays, and ints which need special handling)
        if (self_tag == other_tag) {
            // Special handling for tuple types - widen element-wise
            if (self_tag == .tuple) {
                // Tuples with different lengths -> use unknown (becomes PyObject in codegen)
                // This handles Python's dynamic tuple sizing (e.g., bases=() vs bases=(cls,))
                if (self.tuple.len != other.tuple.len) return .unknown;
                // Note: Can't allocate here, so we return self if all elements match
                // Element-wise widening would need an allocator
                // For now, return self if same length (codegen will handle it)
                return self;
            }
            // Special handling for array types - different lengths need list type
            if (self_tag == .array) {
                // Arrays with different lengths but same element type -> use list (slice in Zig)
                // This matches InferListType behavior which produces []T for varying-length arrays
                if (self.array.length != other.array.length) {
                    // Same element type? -> list of that element type
                    // Different element types? -> pyvalue (heterogeneous)
                    return .{ .list = self.array.element_type };
                }
                return self;
            }
            // Special handling for list types - if element types differ, return pyvalue
            if (self_tag == .list) {
                const self_elem = self.list.*;
                const other_elem = other.list.*;
                const self_elem_tag = @as(std.meta.Tag(NativeType), self_elem);
                const other_elem_tag = @as(std.meta.Tag(NativeType), other_elem);
                // If element types are different tags, use pyvalue for flexibility
                if (self_elem_tag != other_elem_tag) {
                    return .pyvalue;
                }
                // If both are arrays with different lengths, use pyvalue
                if (self_elem_tag == .array) {
                    if (self_elem.array.length != other_elem.array.length) {
                        return .pyvalue;
                    }
                }
                return self;
            }
            // Special handling for int types - combine boundedness
            // unbounded + anything = unbounded (taint propagation)
            if (self_tag == .int) {
                const combined_kind = self.int.combine(other.int);
                return .{ .int = combined_kind };
            }
            return self;
        }

        // Handle array + list widening: array meets list -> list wins
        // This handles nested lists where some have arrays of different lengths
        if ((self_tag == .array and other_tag == .list) or
            (self_tag == .list and other_tag == .array))
        {
            // The list type is more general, use it
            // But we might need to widen the element types
            if (self_tag == .list) {
                return self;
            } else {
                return other;
            }
        }

        // Handle None/optional widening: None + T -> pyvalue (heterogeneous)
        // Note: We can't create .optional here because we don't have an allocator
        // to heap-allocate the inner type. Using pyvalue is safe and correct
        // for runtime type handling.
        if (self_tag == .none and other_tag != .none) {
            return .pyvalue;
        }
        if (other_tag == .none and self_tag != .none) {
            return .pyvalue;
        }

        // String + non-numeric types = PyValue (heterogeneous list)
        // Strings only "win" within the string hierarchy (literal vs runtime)
        // When mixing string with int/float/bool/etc., use pyvalue for type erasure
        if (self_tag == .string and other_tag == .string) return .{ .string = .runtime };
        if (self_tag == .string or other_tag == .string) {
            // String + numeric (int/float/usize/bigint) = pyvalue (heterogeneous)
            // String + bool = pyvalue (heterogeneous)
            const other_is_numeric = other_tag == .int or other_tag == .float or other_tag == .usize or other_tag == .bigint or other_tag == .bool;
            const self_is_numeric = self_tag == .int or self_tag == .float or self_tag == .usize or self_tag == .bigint or self_tag == .bool;
            if (self_is_numeric or other_is_numeric) return .pyvalue;
            // String + other non-numeric types still defaults to pyvalue
            return .pyvalue;
        }

        // BigInt can hold any int, so bigint "wins" over int/usize
        if ((self_tag == .bigint and other_tag == .int) or
            (self_tag == .int and other_tag == .bigint)) return .bigint;
        if ((self_tag == .bigint and other_tag == .usize) or
            (self_tag == .usize and other_tag == .bigint)) return .bigint;

        // Float can hold ints and bigints (with precision loss), so float "wins"
        if ((self_tag == .float and other_tag == .int) or
            (self_tag == .int and other_tag == .float)) return .float;
        if ((self_tag == .float and other_tag == .bigint) or
            (self_tag == .bigint and other_tag == .float)) return .float;

        // usize and int mix → promote to int (i64 can represent both)
        // Preserve the int's boundedness
        if (self_tag == .usize and other_tag == .int) {
            return other; // Keep int's boundedness
        }
        if (self_tag == .int and other_tag == .usize) {
            return self; // Keep int's boundedness
        }

        // usize and float → promote to float
        if ((self_tag == .usize and other_tag == .float) or
            (self_tag == .float and other_tag == .usize)) return .float;

        // IO and collection types stay as their own types (no widening)
        if (self_tag == .stringio or self_tag == .bytesio or self_tag == .file or self_tag == .hash_object or self_tag == .counter or self_tag == .deque) return self;
        if (other_tag == .stringio or other_tag == .bytesio or other_tag == .file or other_tag == .hash_object or other_tag == .counter or other_tag == .deque) return other;

        // Callable types: when mixing callables with functions/closures/unknown, widen to callable
        // This handles lists like [bytes, bytearray, lambda x: ...] -> all become PyCallable
        if (self_tag == .callable or other_tag == .callable) return .callable;
        if (self_tag == .function or other_tag == .function) return .callable;
        if (self_tag == .closure or other_tag == .closure) return .callable;

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
