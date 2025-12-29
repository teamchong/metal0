/// ZigType - Unified type system for structured Zig codegen
///
/// Provides type-safe representation of Zig types with:
/// - Deduplication via TypePool (generate each struct once)
/// - Fast equality checks
/// - Automatic type coercion for certain→uncertain
/// - Integration with NativeType from type inference
///
/// Key insight: Types are first-class values that know how to emit themselves.
/// This enables type-driven code generation where the type determines the code pattern.
///
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Represents a Zig type for code generation
pub const ZigType = union(enum) {
    // ============================================
    // Primitive types
    // ============================================

    void,
    bool,
    i8,
    i16,
    i32,
    i64,
    i128,
    u8,
    u16,
    u32,
    u64,
    usize,
    f32,
    f64,
    comptime_int,
    comptime_float,

    // ============================================
    // Metal0 runtime types
    // ============================================

    /// runtime.PyValue (dynamic type)
    pyvalue,

    /// runtime.BigInt (arbitrary precision)
    bigint,

    /// UnifiedInt (i64 or BigInt union)
    unified_int,

    /// runtime.PyException
    py_exception,

    /// runtime.PyCallable
    py_callable,

    /// runtime.DynamicClosure
    dynamic_closure,

    /// Inferred type (let Zig infer from value)
    inferred,

    // ============================================
    // Compound types
    // ============================================

    /// Fixed-size array: [N]T
    array: ArrayType,

    /// Slice: []T or []const T
    slice: SliceType,

    /// Pointer: *T or *const T
    pointer: PointerType,

    /// Optional: ?T
    optional: OptionalType,

    /// Error union: E!T
    error_union: ErrorUnionType,

    /// Tuple: struct { T0, T1, ... }
    tuple: TupleType,

    // ============================================
    // User-defined types
    // ============================================

    /// Named struct type (generated or imported)
    struct_type: []const u8,

    /// Named enum type
    enum_type: []const u8,

    /// Named union type
    union_type: []const u8,

    /// Python class instance
    class_instance: []const u8,

    /// ArrayList(T)
    arraylist: ArrayListType,

    /// AutoHashMap(K, V)
    hashmap: HashMapType,

    // ============================================
    // Special types
    // ============================================

    /// Type placeholder (for forward references)
    placeholder: []const u8,

    /// Any type (for generic contexts)
    any,

    /// Error type (for error returns)
    @"error": void,

    // ============================================
    // Type methods
    // ============================================

    /// Check if this type is void
    pub fn isVoid(self: ZigType) bool {
        return self == .void;
    }

    /// Check if this is a numeric type
    pub fn isNumeric(self: ZigType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128 => true,
            .u8, .u16, .u32, .u64, .usize => true,
            .f32, .f64 => true,
            .comptime_int, .comptime_float => true,
            .bigint, .unified_int => true,
            else => false,
        };
    }

    /// Check if this is an integer type
    pub fn isInteger(self: ZigType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128 => true,
            .u8, .u16, .u32, .u64, .usize => true,
            .comptime_int => true,
            .bigint, .unified_int => true,
            else => false,
        };
    }

    /// Check if this is a float type
    pub fn isFloat(self: ZigType) bool {
        return switch (self) {
            .f32, .f64, .comptime_float => true,
            else => false,
        };
    }

    /// Check if this is a signed integer type
    pub fn isSigned(self: ZigType) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .i128, .comptime_int => true,
            else => false,
        };
    }

    /// Check if this type requires runtime type checking (PyValue)
    pub fn isDynamic(self: ZigType) bool {
        return switch (self) {
            .pyvalue, .py_callable, .dynamic_closure => true,
            else => false,
        };
    }

    /// Check if this type can be null/optional
    pub fn isOptional(self: ZigType) bool {
        return self == .optional;
    }

    /// Check if this type is a container (array, slice, list, dict)
    pub fn isContainer(self: ZigType) bool {
        return switch (self) {
            .array, .slice, .arraylist, .hashmap, .tuple => true,
            else => false,
        };
    }

    /// Get the element type for containers
    pub fn elementType(self: ZigType) ?*const ZigType {
        return switch (self) {
            .array => |a| a.element,
            .slice => |s| s.element,
            .arraylist => |a| a.element,
            .optional => |o| o.child,
            .pointer => |p| p.child,
            else => null,
        };
    }

    /// Emit this type as Zig code
    pub fn emit(self: ZigType, writer: anytype) !void {
        switch (self) {
            // Primitives
            .void => try writer.writeAll("void"),
            .bool => try writer.writeAll("bool"),
            .i8 => try writer.writeAll("i8"),
            .i16 => try writer.writeAll("i16"),
            .i32 => try writer.writeAll("i32"),
            .i64 => try writer.writeAll("i64"),
            .i128 => try writer.writeAll("i128"),
            .u8 => try writer.writeAll("u8"),
            .u16 => try writer.writeAll("u16"),
            .u32 => try writer.writeAll("u32"),
            .u64 => try writer.writeAll("u64"),
            .usize => try writer.writeAll("usize"),
            .f32 => try writer.writeAll("f32"),
            .f64 => try writer.writeAll("f64"),
            .comptime_int => try writer.writeAll("comptime_int"),
            .comptime_float => try writer.writeAll("comptime_float"),

            // Runtime types
            .pyvalue => try writer.writeAll("runtime.PyValue"),
            .bigint => try writer.writeAll("runtime.BigInt"),
            .unified_int => try writer.writeAll("runtime.UnifiedInt"),
            .py_exception => try writer.writeAll("runtime.PyException"),
            .py_callable => try writer.writeAll("runtime.PyCallable"),
            .dynamic_closure => try writer.writeAll("runtime.DynamicClosure"),

            // Inferred type (no type annotation emitted)
            .inferred => {}, // Empty - caller should not emit ": type" prefix

            // Compound types
            .array => |a| {
                try writer.print("[{d}]", .{a.len});
                try a.element.emit(writer);
            },
            .slice => |s| {
                try writer.writeAll("[]");
                if (s.is_const) try writer.writeAll("const ");
                try s.element.emit(writer);
            },
            .pointer => |p| {
                try writer.writeAll("*");
                if (p.is_const) try writer.writeAll("const ");
                try p.child.emit(writer);
            },
            .optional => |o| {
                try writer.writeAll("?");
                try o.child.emit(writer);
            },
            .error_union => |e| {
                if (e.error_set) |es| {
                    try writer.writeAll(es);
                } else {
                    try writer.writeAll("anyerror");
                }
                try writer.writeAll("!");
                try e.payload.emit(writer);
            },
            .tuple => |t| {
                try writer.writeAll("struct { ");
                for (t.elements, 0..) |elem, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try elem.emit(writer);
                }
                try writer.writeAll(" }");
            },

            // User types
            .struct_type => |name| try writer.writeAll(name),
            .enum_type => |name| try writer.writeAll(name),
            .union_type => |name| try writer.writeAll(name),
            .class_instance => |name| try writer.writeAll(name),

            .arraylist => |a| {
                try writer.writeAll("std.ArrayList(");
                try a.element.emit(writer);
                try writer.writeAll(")");
            },
            .hashmap => |h| {
                try writer.writeAll("std.AutoHashMap(");
                try h.key.emit(writer);
                try writer.writeAll(", ");
                try h.value.emit(writer);
                try writer.writeAll(")");
            },

            // Special
            .placeholder => |name| try writer.writeAll(name),
            .any => try writer.writeAll("anytype"),
            .@"error" => try writer.writeAll("anyerror"),
        }
    }

    /// Convert to string (allocates)
    pub fn toString(self: ZigType, allocator: Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try self.emit(buf.writer(allocator));
        return buf.toOwnedSlice(allocator);
    }

    // ============================================
    // Constructors
    // ============================================

    /// Create a slice type
    pub fn sliceOf(element: *const ZigType, is_const: bool) ZigType {
        return .{ .slice = .{ .element = element, .is_const = is_const } };
    }

    /// Create an array type
    pub fn arrayOf(element: *const ZigType, len: usize) ZigType {
        return .{ .array = .{ .element = element, .len = len } };
    }

    /// Create an optional type
    pub fn optionalOf(child: *const ZigType) ZigType {
        return .{ .optional = .{ .child = child } };
    }

    /// Create a pointer type
    pub fn pointerTo(child: *const ZigType, is_const: bool) ZigType {
        return .{ .pointer = .{ .child = child, .is_const = is_const } };
    }

    /// Create an error union type
    pub fn errorUnionOf(payload: *const ZigType, error_set: ?[]const u8) ZigType {
        return .{ .error_union = .{ .payload = payload, .error_set = error_set } };
    }

    /// Create an ArrayList type
    pub fn arrayListOf(element: *const ZigType) ZigType {
        return .{ .arraylist = .{ .element = element } };
    }

    /// Create a HashMap type
    pub fn hashMapOf(key: *const ZigType, value: *const ZigType) ZigType {
        return .{ .hashmap = .{ .key = key, .value = value } };
    }
};

/// Array type info
pub const ArrayType = struct {
    element: *const ZigType,
    len: usize,
};

/// Slice type info
pub const SliceType = struct {
    element: *const ZigType,
    is_const: bool,
};

/// Pointer type info
pub const PointerType = struct {
    child: *const ZigType,
    is_const: bool,
};

/// Optional type info
pub const OptionalType = struct {
    child: *const ZigType,
};

/// Error union type info
pub const ErrorUnionType = struct {
    payload: *const ZigType,
    error_set: ?[]const u8,
};

/// Tuple type info
pub const TupleType = struct {
    elements: []const *const ZigType,
};

/// ArrayList type info
pub const ArrayListType = struct {
    element: *const ZigType,
};

/// HashMap type info
pub const HashMapType = struct {
    key: *const ZigType,
    value: *const ZigType,
};

// ============================================
// Type Pool for deduplication
// ============================================

/// Pool for type deduplication and caching
/// Ensures each unique type is created only once
pub const TypePool = struct {
    allocator: Allocator,

    /// Pre-allocated common types (no allocation needed)
    primitives: PrimitiveTypes,

    /// Cached compound types (Zig 0.15: no allocator in ArrayList struct)
    slices: std.ArrayList(CachedSlice),
    arrays: std.ArrayList(CachedArray),
    optionals: std.ArrayList(CachedOptional),
    pointers: std.ArrayList(CachedPointer),
    structs: std.StringHashMap(*const ZigType),

    const PrimitiveTypes = struct {
        void_t: ZigType = .void,
        bool_t: ZigType = .bool,
        i8_t: ZigType = .i8,
        i16_t: ZigType = .i16,
        i32_t: ZigType = .i32,
        i64_t: ZigType = .i64,
        i128_t: ZigType = .i128,
        u8_t: ZigType = .u8,
        u16_t: ZigType = .u16,
        u32_t: ZigType = .u32,
        u64_t: ZigType = .u64,
        usize_t: ZigType = .usize,
        f32_t: ZigType = .f32,
        f64_t: ZigType = .f64,
        pyvalue_t: ZigType = .pyvalue,
        bigint_t: ZigType = .bigint,
        unified_int_t: ZigType = .unified_int,
        inferred_t: ZigType = .inferred,
        any_t: ZigType = .any,
        pyobject_ptr_t: ZigType = .{ .struct_type = "*runtime.PyObject" },
    };

    const CachedSlice = struct {
        element: *const ZigType,
        is_const: bool,
        result: ZigType,
    };

    const CachedArray = struct {
        element: *const ZigType,
        len: usize,
        result: ZigType,
    };

    const CachedOptional = struct {
        child: *const ZigType,
        result: ZigType,
    };

    const CachedPointer = struct {
        child: *const ZigType,
        is_const: bool,
        result: ZigType,
    };

    pub fn init(allocator: Allocator) TypePool {
        return .{
            .allocator = allocator,
            .primitives = .{},
            // Zig 0.15: ArrayList is empty struct, allocator passed to methods
            .slices = .{},
            .arrays = .{},
            .optionals = .{},
            .pointers = .{},
            .structs = std.StringHashMap(*const ZigType).init(allocator),
        };
    }

    pub fn deinit(self: *TypePool) void {
        // Zig 0.15: pass allocator to deinit
        self.slices.deinit(self.allocator);
        self.arrays.deinit(self.allocator);
        self.optionals.deinit(self.allocator);
        self.pointers.deinit(self.allocator);
        self.structs.deinit();
    }

    // Primitive type accessors (O(1), no allocation)
    pub fn void_(self: *TypePool) *const ZigType {
        return &self.primitives.void_t;
    }
    pub fn bool_(self: *TypePool) *const ZigType {
        return &self.primitives.bool_t;
    }
    pub fn i64_(self: *TypePool) *const ZigType {
        return &self.primitives.i64_t;
    }
    pub fn f64_(self: *TypePool) *const ZigType {
        return &self.primitives.f64_t;
    }
    pub fn usize_(self: *TypePool) *const ZigType {
        return &self.primitives.usize_t;
    }
    pub fn pyvalue_(self: *TypePool) *const ZigType {
        return &self.primitives.pyvalue_t;
    }
    pub fn bigint_(self: *TypePool) *const ZigType {
        return &self.primitives.bigint_t;
    }
    pub fn unified_int_(self: *TypePool) *const ZigType {
        return &self.primitives.unified_int_t;
    }
    pub fn u8_(self: *TypePool) *const ZigType {
        return &self.primitives.u8_t;
    }
    pub fn inferred_(self: *TypePool) *const ZigType {
        return &self.primitives.inferred_t;
    }
    pub fn any_(self: *TypePool) *const ZigType {
        return &self.primitives.any_t;
    }
    pub fn pyobject_ptr(self: *TypePool) *const ZigType {
        return &self.primitives.pyobject_ptr_t;
    }

    /// Get or create a slice type (deduplicated)
    pub fn slice(self: *TypePool, element: *const ZigType, is_const: bool) !*const ZigType {
        // Check cache
        for (self.slices.items) |*cached| {
            if (cached.element == element and cached.is_const == is_const) {
                return &cached.result;
            }
        }
        // Create new (Zig 0.15: pass allocator)
        const entry = try self.slices.addOne(self.allocator);
        entry.* = .{
            .element = element,
            .is_const = is_const,
            .result = .{ .slice = .{ .element = element, .is_const = is_const } },
        };
        return &entry.result;
    }

    /// Get or create an array type (deduplicated)
    pub fn array(self: *TypePool, element: *const ZigType, len: usize) !*const ZigType {
        // Check cache
        for (self.arrays.items) |*cached| {
            if (cached.element == element and cached.len == len) {
                return &cached.result;
            }
        }
        // Create new (Zig 0.15: pass allocator)
        const entry = try self.arrays.addOne(self.allocator);
        entry.* = .{
            .element = element,
            .len = len,
            .result = .{ .array = .{ .element = element, .len = len } },
        };
        return &entry.result;
    }

    /// Get or create an optional type (deduplicated)
    pub fn optional(self: *TypePool, child: *const ZigType) !*const ZigType {
        // Check cache
        for (self.optionals.items) |*cached| {
            if (cached.child == child) {
                return &cached.result;
            }
        }
        // Create new (Zig 0.15: pass allocator)
        const entry = try self.optionals.addOne(self.allocator);
        entry.* = .{
            .child = child,
            .result = .{ .optional = .{ .child = child } },
        };
        return &entry.result;
    }

    /// Get or create a pointer type (deduplicated)
    pub fn pointer(self: *TypePool, child: *const ZigType, is_const: bool) !*const ZigType {
        // Check cache
        for (self.pointers.items) |*cached| {
            if (cached.child == child and cached.is_const == is_const) {
                return &cached.result;
            }
        }
        // Create new (Zig 0.15: pass allocator)
        const entry = try self.pointers.addOne(self.allocator);
        entry.* = .{
            .child = child,
            .is_const = is_const,
            .result = .{ .pointer = .{ .child = child, .is_const = is_const } },
        };
        return &entry.result;
    }

    /// Convenience: []const u8 (string slice)
    pub fn string(self: *TypePool) !*const ZigType {
        return self.slice(self.u8_(), true);
    }
};

// ============================================
// Tests
// ============================================

test "ZigType primitive properties" {
    const i64_type: ZigType = .i64;
    try std.testing.expect(i64_type.isNumeric());
    try std.testing.expect(i64_type.isInteger());
    try std.testing.expect(!i64_type.isFloat());
    try std.testing.expect(i64_type.isSigned());

    const f64_type: ZigType = .f64;
    try std.testing.expect(f64_type.isNumeric());
    try std.testing.expect(!f64_type.isInteger());
    try std.testing.expect(f64_type.isFloat());

    const bool_type: ZigType = .bool;
    try std.testing.expect(!bool_type.isNumeric());

    const void_type: ZigType = .void;
    try std.testing.expect(void_type.isVoid());
}

test "ZigType runtime types" {
    const pyvalue_type: ZigType = .pyvalue;
    try std.testing.expect(pyvalue_type.isDynamic());

    const pycallable_type: ZigType = .py_callable;
    try std.testing.expect(pycallable_type.isDynamic());

    const i64_type: ZigType = .i64;
    try std.testing.expect(!i64_type.isDynamic());
}

test "ZigType emit" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    const i64_type: ZigType = .i64;
    try i64_type.emit(buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("i64", buf.items);

    buf.clearRetainingCapacity();
    const pyvalue_type: ZigType = .pyvalue;
    try pyvalue_type.emit(buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("runtime.PyValue", buf.items);
}

test "TypePool primitives" {
    var pool = TypePool.init(std.testing.allocator);
    defer pool.deinit();

    const i64_1 = pool.i64_();
    const i64_2 = pool.i64_();
    try std.testing.expectEqual(i64_1, i64_2); // Same pointer

    try std.testing.expect(i64_1.* == .i64);
}

test "TypePool slice deduplication" {
    var pool = TypePool.init(std.testing.allocator);
    defer pool.deinit();

    const u8_type = pool.u8_();
    const slice1 = try pool.slice(u8_type, true);
    const slice2 = try pool.slice(u8_type, true);
    try std.testing.expectEqual(slice1, slice2); // Same pointer

    const slice3 = try pool.slice(u8_type, false);
    try std.testing.expect(slice1 != slice3); // Different (const vs non-const)
}

test "TypePool string convenience" {
    var pool = TypePool.init(std.testing.allocator);
    defer pool.deinit();

    const str_type = try pool.string();
    try std.testing.expect(str_type.* == .slice);
    try std.testing.expect(str_type.slice.is_const);
    try std.testing.expect(str_type.slice.element.* == .u8);
}
