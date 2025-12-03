//! Python typing module types
//!
//! Provides runtime representations of typing module constructs.
//! Most typing constructs are compile-time in Zig and handled in codegen,
//! but some need runtime representations for introspection and tests.

const std = @import("std");

/// Runtime typing type info - used for type introspection
pub const TypeInfo = struct {
    name: []const u8,
    origin: ?*const TypeInfo = null,
    args: []const *const TypeInfo = &[_]*const TypeInfo{},
};

/// Any type - accepts any value
pub const Any = struct {
    pub fn __getitem__(_: type) type {
        return @This();
    }
};

/// NoReturn type - function never returns (always raises or loops forever)
pub const NoReturn = struct {
    pub fn __getitem__(_: type) type {
        return @This();
    }
};

/// Never type - alias for NoReturn in Python 3.11+
pub const Never = NoReturn;

/// Self type - represents the class itself in type annotations
pub const Self = struct {
    pub fn __getitem__(_: type) type {
        return @This();
    }
};

/// TypeVar - generic type variable
pub fn TypeVar(comptime name: []const u8) type {
    _ = name;
    return struct {
        pub fn __getitem__(_: type) type {
            return @This();
        }
    };
}

/// Union type - one of several types
pub fn Union(comptime types: anytype) type {
    _ = types;
    return struct {};
}

/// Optional type - T or None
pub fn Optional(comptime T: type) type {
    _ = T;
    return struct {};
}

/// List type annotation
pub fn List(comptime T: type) type {
    _ = T;
    return struct {};
}

/// Dict type annotation
pub fn Dict(comptime K: type, comptime V: type) type {
    _ = K;
    _ = V;
    return struct {};
}

/// Tuple type annotation
pub fn Tuple(comptime types: anytype) type {
    _ = types;
    return struct {};
}

/// Callable type annotation
pub fn Callable(comptime args: anytype, comptime ret: type) type {
    _ = args;
    _ = ret;
    return struct {};
}

/// Generic base class
pub fn Generic(comptime type_vars: anytype) type {
    _ = type_vars;
    return struct {};
}

/// ClassVar - class variable annotation
pub fn ClassVar(comptime T: type) type {
    _ = T;
    return struct {};
}

/// Final - cannot be overridden/reassigned
pub fn Final(comptime T: type) type {
    _ = T;
    return struct {};
}

/// final decorator stub - no-op at runtime
pub fn final(comptime T: type) type {
    return T;
}

/// Literal type - specific literal values
pub fn Literal(comptime values: anytype) type {
    _ = values;
    return struct {};
}

/// Annotated type with metadata
pub fn Annotated(comptime T: type, comptime metadata: anytype) type {
    _ = T;
    _ = metadata;
    return struct {};
}

/// ForwardRef for forward reference strings
pub const ForwardRef = struct {
    arg: []const u8,

    pub fn init(arg: []const u8) ForwardRef {
        return .{ .arg = arg };
    }
};

/// LiteralString type
pub const LiteralString = struct {};

/// TypeAlias marker
pub const TypeAlias = struct {};

/// ParamSpec for parameter specification variables
pub fn ParamSpec(comptime name: []const u8) type {
    _ = name;
    return struct {
        pub const args = struct {};
        pub const kwargs = struct {};
    };
}

/// Protocol base class
pub const Protocol = struct {};

/// TypedDict base
pub const TypedDict = struct {};

/// NamedTuple base
pub const NamedTuple = struct {};

/// Pattern type (from re)
pub const Pattern = struct {};

/// Match type (from re)
pub const Match = struct {};

/// IO base types
pub const IO = struct {};
pub const TextIO = struct {};
pub const BinaryIO = struct {};

/// Type type (for Type[X])
pub fn Type(comptime T: type) type {
    _ = T;
    return struct {};
}

/// Concatenate for ParamSpec
pub fn Concatenate(comptime types: anytype) type {
    _ = types;
    return struct {};
}

/// TypeGuard for narrowing
pub fn TypeGuard(comptime T: type) type {
    _ = T;
    return struct {};
}

/// TypeIs for type narrowing
pub fn TypeIs(comptime T: type) type {
    _ = T;
    return struct {};
}

/// NoDefault sentinel
pub const NoDefault = struct {};

/// NotRequired for TypedDict
pub fn NotRequired(comptime T: type) type {
    _ = T;
    return struct {};
}

/// Required for TypedDict
pub fn Required(comptime T: type) type {
    _ = T;
    return struct {};
}

/// ReadOnly for TypedDict
pub fn ReadOnly(comptime T: type) type {
    _ = T;
    return struct {};
}

/// NoExtraItems marker
pub const NoExtraItems = struct {};

/// Unpack for TypeVarTuple
pub fn Unpack(comptime T: type) type {
    _ = T;
    return struct {};
}

/// TypeVarTuple
pub fn TypeVarTuple(comptime name: []const u8) type {
    _ = name;
    return struct {};
}

/// AnyStr type variable
pub const AnyStr = struct {};

/// T type variable (common)
pub const T_var = struct {};

/// KT type variable (key type)
pub const KT_var = struct {};

/// VT type variable (value type)
pub const VT_var = struct {};

// Introspection functions

/// Get origin type (e.g., list from List[int])
pub fn get_origin(_: anytype) ?type {
    return null;
}

/// Get type arguments
pub fn get_args(_: anytype) []const type {
    return &[_]type{};
}

/// Get protocol members
pub fn get_protocol_members(_: type) []const []const u8 {
    return &[_][]const u8{};
}

/// Type assertion (no-op at runtime)
pub fn assert_type(val: anytype, comptime _: type) @TypeOf(val) {
    return val;
}

/// Cast (no-op at runtime)
pub fn cast(comptime _: type, val: anytype) @TypeOf(val) {
    return val;
}

/// assert_never - should never be called
pub fn assert_never(_: anytype) void {
    @panic("assert_never called - this code path should be unreachable");
}

/// runtime_checkable decorator (no-op)
pub fn runtime_checkable(comptime T: type) type {
    return T;
}

/// overload decorator (no-op)
pub fn overload(comptime func: anytype) @TypeOf(func) {
    return func;
}

/// get_overloads stub
pub fn get_overloads(_: anytype) []const fn () void {
    return &[_]fn () void{};
}

/// clear_overloads stub
pub fn clear_overloads() void {}

/// get_type_hints stub
pub fn get_type_hints(_: anytype) std.StringHashMap([]const u8) {
    return std.StringHashMap([]const u8).init(std.heap.page_allocator);
}

/// override decorator (no-op)
pub fn override(comptime func: anytype) @TypeOf(func) {
    return func;
}

/// is_typeddict check
pub fn is_typeddict(_: type) bool {
    return false;
}

/// is_protocol check
pub fn is_protocol(_: type) bool {
    return false;
}

/// reveal_type - prints type at compile time (no-op at runtime)
pub fn reveal_type(val: anytype) @TypeOf(val) {
    return val;
}

/// dataclass_transform decorator (no-op)
pub fn dataclass_transform(comptime T: type) type {
    return T;
}

/// no_type_check decorator (no-op)
pub fn no_type_check(comptime func: anytype) @TypeOf(func) {
    return func;
}

/// MutableMapping type
pub const MutableMapping = struct {};

/// ParamSpecArgs
pub const ParamSpecArgs = struct {};

/// ParamSpecKwargs
pub const ParamSpecKwargs = struct {};
