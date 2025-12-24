const std = @import("std");

// Trait imports for type checking
const string_traits = @import("../traits/string_traits.zig");
const container_traits = @import("../traits/container_traits.zig");
const type_traits = @import("../traits/type_traits.zig");

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

/// Callable return type behavior - tracks how a callable's return type relates to inputs
/// Used for type inference when calling variables of callable type (e.g., loop over pow, operator.pow)
pub const CallableReturnKind = enum {
    /// Returns the same type as the (first) input argument
    /// Examples: pow, abs, min, max, operator.pow, operator.add, etc.
    same_as_input,

    /// Always returns string ([]const u8)
    /// Examples: str, repr, format
    fixed_string,

    /// Always returns int (i64)
    /// Examples: len, ord, hash, int
    fixed_int,

    /// Always returns float (f64)
    /// Examples: float
    fixed_float,

    /// Always returns bool
    /// Examples: bool, all, any, callable, isinstance
    fixed_bool,

    /// Unknown return type - fallback to PyObject
    unknown,

    /// Combine two return kinds for widening
    /// If both are same, return that; otherwise return unknown
    pub fn combine(self: CallableReturnKind, other: CallableReturnKind) CallableReturnKind {
        if (self == other) return self;
        return .unknown;
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

/// Type inference confidence level
/// Determines whether to use raw Zig types (fast) or PyValue (safe)
pub const TypeConfidence = enum {
    /// 100% provable at compile time - use raw Zig types
    /// Sources: literals, type annotations, known builtins
    certain,

    /// Cannot prove type at compile time - use PyValue for safety
    /// Sources: user functions without annotations, dict/list subscript, external input
    uncertain,

    /// Combine confidences - uncertain taints the result
    pub fn combine(self: TypeConfidence, other: TypeConfidence) TypeConfidence {
        if (self == .uncertain or other == .uncertain) {
            return .uncertain;
        }
        return .certain;
    }

    /// Degrade confidence (for operations that add uncertainty)
    pub fn degrade(self: TypeConfidence) TypeConfidence {
        _ = self;
        return .uncertain;
    }
};

/// Source of type inference (for debugging and documentation)
pub const TypeSource = enum {
    literal, // From literal value: x = 42
    annotation, // From type hint: x: int = ...
    builtin, // From known builtin: len(s)
    inferred, // From expression analysis
    widened, // From type widening (multiple assignments)
    external, // From external source (user func, file, network)
};

/// Type with confidence metadata
/// Used to track both the inferred type AND how certain we are about it
pub const TypedValue = struct {
    native_type: NativeType,
    confidence: TypeConfidence,
    source: TypeSource = .inferred,

    /// Create a certain typed value (for literals, annotations, builtins)
    pub fn certain(native_type: NativeType, source: TypeSource) TypedValue {
        return .{
            .native_type = native_type,
            .confidence = .certain,
            .source = source,
        };
    }

    /// Create an uncertain typed value (for user funcs, external input)
    pub fn uncertain(native_type: NativeType, source: TypeSource) TypedValue {
        return .{
            .native_type = native_type,
            .confidence = .uncertain,
            .source = source,
        };
    }

    /// Create from existing NativeType (defaults to uncertain for safety)
    pub fn fromNativeType(native_type: NativeType) TypedValue {
        return .{
            .native_type = native_type,
            .confidence = .uncertain,
            .source = .inferred,
        };
    }

    /// Combine with another typed value (for binary ops)
    pub fn combineWith(self: TypedValue, other: TypedValue) TypedValue {
        return .{
            .native_type = self.native_type.widen(other.native_type),
            .confidence = self.confidence.combine(other.confidence),
            .source = .inferred,
        };
    }

    /// Check if safe to use raw Zig type
    pub fn isSafe(self: TypedValue) bool {
        return self.confidence == .certain;
    }

    /// Check if should use PyValue for safety
    pub fn usePyValue(self: TypedValue) bool {
        return self.confidence == .uncertain;
    }
};

/// Native Zig types inferred from Python code
pub const NativeType = union(enum) {
    // Primitives - stack allocated, zero overhead
    int: IntKind, // i64 (bounded) or BigInt (unbounded)
    bigint: void, // runtime.BigInt - arbitrary precision integer (always)
    unified_int: void, // runtime.UnifiedInt - tagged union (i64 fast path, BigInt fallback)
    usize: void, // usize (for array indices, always bounded)
    float: void, // f64
    bool: void, // bool
    string: StringKind, // []const u8 - tracks allocation/optimization hint
    bytes: void, // runtime.builtins.PyBytes - Python bytes type (preserves type info for repr)
    complex: void, // runtime.PyComplex - complex number
    int_result: void, // runtime.IntResult - tagged union (i64 small, BigInt big) from float rounding
    pow_result: void, // runtime.builtins.PyPowResult - tagged union (float_val or complex_val) from pow with float exponent

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
    callable: CallableReturnKind, // Type-erased callable with return type hint

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

    // http module types
    http_response: void, // http.Response - runtime.http.Response struct

    // Iterator types
    list_iterator: void, // iter() on list - SequenceIterator(i64)

    /// Check if this is a simple type (int, bigint, unified_int, float, bool, string, class_instance, optional)
    /// Simple types can be const even if semantic analyzer reports them as mutated
    /// (workaround for semantic analyzer false positives)
    pub fn isSimpleType(self: NativeType) bool {
        return switch (self) {
            .int => true,
            .bigint, .unified_int, .usize, .float, .bool, .string, .class_instance, .optional, .none, .int_result => true,
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
            .bigint, .unified_int, .usize, .int_result => "{d}",
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
            .unified_int => "runtime.UnifiedInt",
            .int_result => "runtime.IntResult",
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
        const hashmap_helper = @import("utils.hashmap_helper");
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
            .unified_int => try buf.appendSlice(allocator, "runtime.UnifiedInt"),
            .int_result => try buf.appendSlice(allocator, "runtime.IntResult"),
            .pow_result => try buf.appendSlice(allocator, "runtime.builtins.PyPowResult"),
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
                // Generate std.ArrayListUnmanaged(ElementType) for typed lists
                // This preserves element type information for proper codegen
                try buf.appendSlice(allocator, "std.ArrayListUnmanaged(");
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
            .unknown => try buf.appendSlice(allocator, "runtime.PyValue"),
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
            .callable => |_| try buf.appendSlice(allocator, "runtime.builtins.PyCallable"),
            .cdll => try buf.appendSlice(allocator, "runtime.ctypes.CDLL"),
            .c_func => try buf.appendSlice(allocator, "*const fn() callconv(.c) anyopaque"),
            .pyobject => try buf.appendSlice(allocator, "*runtime.cpython.PyObject"),
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
            // http module types
            .http_response => try buf.appendSlice(allocator, "runtime.http.Response"),
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
        if (type_traits.isUnknown(self) and !type_traits.isUnknown(other)) return other;
        if (type_traits.isUnknown(other) and !type_traits.isUnknown(self)) return self;
        if (type_traits.isUnknown(self) and type_traits.isUnknown(other)) return .unknown;

        // PyValue absorbs everything - once heterogeneous, stays heterogeneous
        if (self_tag == .pyvalue or other_tag == .pyvalue) return .pyvalue;

        // If types match, no widening needed (except for tuples, arrays, and ints which need special handling)
        if (self_tag == other_tag) {
            // Special handling for tuple types - widen element-wise
            if (container_traits.isTuple(self)) {
                // Tuples with different lengths -> use unknown (becomes PyObject in codegen)
                // This handles Python's dynamic tuple sizing (e.g., bases=() vs bases=(cls,))
                if (self.tuple.len != other.tuple.len) return .unknown;
                // Note: Can't allocate here, so we return self if all elements match
                // Element-wise widening would need an allocator
                // For now, return self if same length (codegen will handle it)
                return self;
            }
            // Special handling for array types - different lengths need list type
            if (container_traits.isArray(self)) {
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
            if (container_traits.isList(self)) {
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
            // Only combine .int payloads if both are .int (not usize/bigint)
            if (self_tag == .int and other_tag == .int) {
                const combined_kind = self.int.combine(other.int);
                return .{ .int = combined_kind };
            }
            // usize + int -> int (more general)
            if (self_tag == .usize and other_tag == .int) {
                return other;
            }
            if (self_tag == .int and other_tag == .usize) {
                return self;
            }
            return self;
        }

        // Handle array + list widening: array meets list -> list wins
        // This handles nested lists where some have arrays of different lengths
        if ((container_traits.isArray(self) and container_traits.isList(other)) or
            (container_traits.isList(self) and container_traits.isArray(other)))
        {
            // The list type is more general, use it
            // But we might need to widen the element types
            if (container_traits.isList(self)) {
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
        if (string_traits.isString(self) and string_traits.isString(other)) return .{ .string = .runtime };
        if (string_traits.isString(self) or string_traits.isString(other)) {
            // String + numeric (int/float/usize/bigint) = pyvalue (heterogeneous)
            // String + bool = pyvalue (heterogeneous)
            const other_is_numeric = type_traits.isNumeric(other);
            const self_is_numeric = type_traits.isNumeric(self);
            if (self_is_numeric or other_is_numeric) return .pyvalue;
            // String + other non-numeric types still defaults to pyvalue
            return .pyvalue;
        }

        // BigInt + int/usize -> unified_int (to handle both small and large values)
        // This ensures lists like [324, 2**100] use UnifiedInt instead of raw BigInt
        if ((self_tag == .bigint and other_tag == .int) or
            (self_tag == .int and other_tag == .bigint)) return .unified_int;
        if ((self_tag == .bigint and other_tag == .usize) or
            (self_tag == .usize and other_tag == .bigint)) return .unified_int;

        // UnifiedInt widening: unified_int + int/bigint/usize = unified_int (it can hold both)
        if (self_tag == .unified_int or other_tag == .unified_int) {
            // unified_int + float = float (Python numeric promotion)
            if (self_tag == .float or other_tag == .float) return .float;
            // unified_int with any other integer type stays unified_int
            if ((self_tag == .unified_int and (other_tag == .int or other_tag == .bigint or other_tag == .usize)) or
                (other_tag == .unified_int and (self_tag == .int or self_tag == .bigint or self_tag == .usize)))
            {
                return .unified_int;
            }
            // unified_int + unified_int = unified_int
            return .unified_int;
        }

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
        // When both are callable, combine return kinds
        if (self_tag == .callable and other_tag == .callable) {
            return .{ .callable = self.callable.combine(other.callable) };
        }
        if (self_tag == .callable or other_tag == .callable) {
            // One is callable, other is function/closure - return callable with unknown
            return .{ .callable = .unknown };
        }
        if (self_tag == .function or other_tag == .function) return .{ .callable = .unknown };
        if (self_tag == .closure or other_tag == .closure) return .{ .callable = .unknown };

        // Different incompatible types (e.g., array + dict) → use unknown to let Zig infer
        // The codegen handles shadowing when types are incompatible
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

/// Convert Zig type string to NativeType (for reverse lookup)
/// Used when codegen determines parameter type from call sites and needs to register it
pub fn zigTypeStringToNative(zig_type: []const u8) NativeType {
    if (std.mem.eql(u8, zig_type, "i64")) return .{ .int = .bounded };
    if (std.mem.eql(u8, zig_type, "f64")) return .float;
    if (std.mem.eql(u8, zig_type, "bool")) return .bool;
    if (std.mem.eql(u8, zig_type, "[]const u8")) return .{ .string = .runtime };
    if (std.mem.eql(u8, zig_type, "usize")) return .usize;
    if (std.mem.eql(u8, zig_type, "runtime.BigInt")) return .bigint;
    if (std.mem.eql(u8, zig_type, "runtime.UnifiedInt")) return .unified_int;
    if (std.mem.eql(u8, zig_type, "runtime.IntResult")) return .int_result;
    if (std.mem.eql(u8, zig_type, "runtime.PyValue")) return .pyvalue;
    // For types we can't reverse-map, return unknown
    return .unknown;
}
