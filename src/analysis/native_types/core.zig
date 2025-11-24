const std = @import("std");
const ast = @import("../../ast.zig");

/// Check if a list contains only literal values (candidates for array optimization)
pub fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        // Check if element is a literal constant
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
pub fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// String type kinds for optimization and tracking
pub const StringKind = enum {
    literal, // Compile-time "hello" - can be optimized
    runtime, // Dynamically allocated (from methods, concat, etc.)
    slice,   // []const u8 slice from operations

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
    none: void, // void or ?T
    unknown: void, // Fallback to PyObject* (should be rare)

    /// Check if this is a simple type (int, float, bool, string, class_instance)
    /// Simple types can be const even if semantic analyzer reports them as mutated
    /// (workaround for semantic analyzer false positives)
    pub fn isSimpleType(self: NativeType) bool {
        return switch (self) {
            .int, .usize, .float, .bool, .string, .class_instance, .none => true,
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
            .unknown, .list, .dict, .tuple => true,
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

    /// Convert to Zig type string
    pub fn toZigType(self: NativeType, allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
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
                try buf.appendSlice(allocator, "std.StringHashMap(");
                try kv.value.toZigType(allocator, buf);
                try buf.appendSlice(allocator, ")");
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
            .none => try buf.appendSlice(allocator, "void"),
            .unknown => try buf.appendSlice(allocator, "*runtime.PyObject"),
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

        // Different incompatible types → fallback to unknown
        return .unknown;
    }
};

/// Error set for type inference
pub const InferError = error{
    OutOfMemory,
};

/// Convert Python type hint string to NativeType
/// For composite types like list, returns a marker that needs allocation
pub fn pythonTypeHintToNative(type_hint: ?[]const u8, allocator: std.mem.Allocator) InferError!NativeType {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return .int;
        if (std.mem.eql(u8, hint, "float")) return .float;
        if (std.mem.eql(u8, hint, "bool")) return .bool;
        if (std.mem.eql(u8, hint, "str")) return .{ .string = .runtime };
        if (std.mem.eql(u8, hint, "list")) {
            // For now, assume list[int] - most common case
            // TODO: Parse generic type hints like list[str], list[float]
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = .int;
            return .{ .list = elem_ptr };
        }
    }
    return .unknown;
}

/// Class field and method information
const fnv_hash = @import("../../utils/fnv_hash.zig");
const FnvContext = fnv_hash.FnvHashContext([]const u8);
const FnvTypeMap = std.HashMap([]const u8, NativeType, FnvContext, 80);

pub const ClassInfo = struct {
    fields: FnvTypeMap,
    methods: FnvTypeMap, // method_name -> return type
};

/// Comptime analysis: Does this type need allocator for operations?
/// Leverages Zig's comptime for zero-runtime-cost type analysis
/// - Analyzed at compile time, no runtime overhead
/// - Recursively checks composite types
/// - Used to determine if functions need allocator parameter
pub fn needsAllocator(self: NativeType) bool {
    return switch (self) {
        .string => true, // String operations allocate
        .list, .dict => true, // Collection operations allocate
        .array => |arr| arr.element_type.needsAllocator(), // Recursive
        .tuple => |types| blk: {
            for (types) |t| {
                if (t.needsAllocator()) break :blk true;
            }
            break :blk false;
        },
        .function => |f| f.return_type.needsAllocator(), // Check return type
        else => false,
    };
}

/// Comptime check: Is return type error union?
pub fn isErrorUnion(self: NativeType) bool {
    return switch (self) {
        .string, .list, .dict, .array => true, // These can fail allocation
        .function => |f| f.return_type.isErrorUnion(),
        else => false,
    };
}

/// Comptime function signature builder
/// Generates optimal function signature based on type analysis
pub const FunctionSignature = struct {
    params: []const NativeType,
    return_type: NativeType,
    needs_allocator: bool,
    is_error_union: bool,

    /// Comptime analysis of function requirements
    pub fn analyze(params: []const NativeType, ret: NativeType) FunctionSignature {
        // Check if any parameter or return needs allocator
        var needs_alloc = ret.needsAllocator();
        for (params) |p| {
            if (p.needsAllocator()) {
                needs_alloc = true;
                break;
            }
        }

        return .{
            .params = params,
            .return_type = ret,
            .needs_allocator = needs_alloc,
            .is_error_union = ret.isErrorUnion(),
        };
    }

    /// Generate Zig function signature string (comptime-optimized)
    pub fn toZigSignature(self: FunctionSignature, func_name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "pub fn ");
        try buf.appendSlice(allocator, func_name);
        try buf.appendSlice(allocator, "(");

        // Add allocator parameter if needed (comptime-determined)
        if (self.needs_allocator) {
            try buf.appendSlice(allocator, "allocator: std.mem.Allocator");
            if (self.params.len > 0) {
                try buf.appendSlice(allocator, ", ");
            }
        }

        // Add parameters
        for (self.params, 0..) |param, i| {
            const param_name = try std.fmt.allocPrint(allocator, "arg{d}: ", .{i});
            defer allocator.free(param_name);
            try buf.appendSlice(allocator, param_name);

            var type_buf = std.ArrayList(u8){};
            defer type_buf.deinit(allocator);
            try param.toZigType(allocator, &type_buf);
            try buf.appendSlice(allocator, type_buf.items);

            if (i < self.params.len - 1) {
                try buf.appendSlice(allocator, ", ");
            }
        }

        try buf.appendSlice(allocator, ") ");

        // Add error union if needed (comptime-determined)
        if (self.is_error_union) {
            try buf.appendSlice(allocator, "!");
        }

        // Add return type
        var ret_buf = std.ArrayList(u8){};
        defer ret_buf.deinit(allocator);
        try self.return_type.toZigType(allocator, &ret_buf);
        try buf.appendSlice(allocator, ret_buf.items);

        return buf.toOwnedSlice(allocator);
    }
};
