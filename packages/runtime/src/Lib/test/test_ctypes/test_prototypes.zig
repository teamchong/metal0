//! test.test_ctypes.test_prototypes - Tests for function prototypes
//! Reference: cpython/Lib/test/test_ctypes/test_prototypes.py
//!
//! Tests for ctypes function prototype definitions and validation.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Function Prototype
// ============================================================================

pub const Prototype = struct {
    const Self = @This();

    name: []const u8,
    return_type: TypeSpec,
    arg_types: []const TypeSpec,
    variadic: bool = false,
    calling_conv: CallingConv = .c,

    pub fn init(name: []const u8, ret: TypeSpec, args: []const TypeSpec) Self {
        return .{
            .name = name,
            .return_type = ret,
            .arg_types = args,
        };
    }

    pub fn argCount(self: *const Self) usize {
        return self.arg_types.len;
    }

    pub fn isVariadic(self: *const Self) bool {
        return self.variadic;
    }
};

pub const TypeSpec = struct {
    name: []const u8,
    size: usize,
    is_pointer: bool = false,
    is_const: bool = false,
};

pub const CallingConv = enum {
    c,
    stdcall,
    fastcall,
    thiscall,
};

// ============================================================================
// Type Specifications
// ============================================================================

pub const TYPE_VOID = TypeSpec{ .name = "void", .size = 0 };
pub const TYPE_INT = TypeSpec{ .name = "int", .size = 4 };
pub const TYPE_UINT = TypeSpec{ .name = "unsigned int", .size = 4 };
pub const TYPE_LONG = TypeSpec{ .name = "long", .size = 8 };
pub const TYPE_DOUBLE = TypeSpec{ .name = "double", .size = 8 };
pub const TYPE_CHAR_P = TypeSpec{ .name = "char*", .size = 8, .is_pointer = true };
pub const TYPE_VOID_P = TypeSpec{ .name = "void*", .size = 8, .is_pointer = true };
pub const TYPE_SIZE_T = TypeSpec{ .name = "size_t", .size = 8 };

// ============================================================================
// Prototype Registry
// ============================================================================

pub fn PrototypeRegistry(comptime max_protos: usize) type {
    return struct {
        const Self = @This();

        protos: [max_protos]?Prototype = [_]?Prototype{null} ** max_protos,
        count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn register(self: *Self, proto: Prototype) !usize {
            if (self.count >= max_protos) return error.RegistryFull;
            const idx = self.count;
            self.protos[idx] = proto;
            self.count += 1;
            return idx;
        }

        pub fn get(self: *const Self, idx: usize) ?Prototype {
            if (idx >= max_protos) return null;
            return self.protos[idx];
        }

        pub fn findByName(self: *const Self, name: []const u8) ?Prototype {
            for (self.protos[0..self.count]) |maybe_proto| {
                if (maybe_proto) |proto| {
                    if (std.mem.eql(u8, proto.name, name)) {
                        return proto;
                    }
                }
            }
            return null;
        }
    };
}

// ============================================================================
// Common Function Prototypes
// ============================================================================

pub const strlen_proto = Prototype.init(
    "strlen",
    TYPE_SIZE_T,
    &.{TYPE_CHAR_P},
);

pub const strcmp_proto = Prototype.init(
    "strcmp",
    TYPE_INT,
    &.{ TYPE_CHAR_P, TYPE_CHAR_P },
);

pub const memcpy_proto = Prototype.init(
    "memcpy",
    TYPE_VOID_P,
    &.{ TYPE_VOID_P, TYPE_VOID_P, TYPE_SIZE_T },
);

pub const malloc_proto = Prototype.init(
    "malloc",
    TYPE_VOID_P,
    &.{TYPE_SIZE_T},
);

pub const free_proto = Prototype.init(
    "free",
    TYPE_VOID,
    &.{TYPE_VOID_P},
);

// ============================================================================
// Prototype Validation
// ============================================================================

pub fn validateArgCount(proto: *const Prototype, arg_count: usize) bool {
    if (proto.variadic) {
        return arg_count >= proto.arg_types.len;
    }
    return arg_count == proto.arg_types.len;
}

pub fn validateArgTypes(proto: *const Prototype, arg_types: []const TypeSpec) bool {
    if (arg_types.len < proto.arg_types.len) return false;

    for (proto.arg_types, 0..) |expected, i| {
        if (!std.mem.eql(u8, expected.name, arg_types[i].name)) {
            return false;
        }
    }
    return true;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testPrototypeInit() !void {
    const proto = Prototype.init("test", TYPE_INT, &.{TYPE_INT});

    try std.testing.expectEqualStrings("test", proto.name);
    try std.testing.expectEqual(@as(usize, 1), proto.argCount());
    try std.testing.expect(!proto.isVariadic());
}

fn testPrototypeVariadic() !void {
    var proto = Prototype.init("printf", TYPE_INT, &.{TYPE_CHAR_P});
    proto.variadic = true;

    try std.testing.expect(proto.isVariadic());
}

fn testTypeSpec() !void {
    try std.testing.expectEqual(@as(usize, 4), TYPE_INT.size);
    try std.testing.expectEqual(@as(usize, 8), TYPE_DOUBLE.size);
    try std.testing.expect(TYPE_CHAR_P.is_pointer);
    try std.testing.expect(!TYPE_INT.is_pointer);
}

fn testPrototypeRegistry() !void {
    var registry = PrototypeRegistry(10).init();

    const idx = try registry.register(strlen_proto);
    try std.testing.expectEqual(@as(usize, 0), idx);

    const proto = registry.get(idx);
    try std.testing.expect(proto != null);
    try std.testing.expectEqualStrings("strlen", proto.?.name);
}

fn testRegistryFindByName() !void {
    var registry = PrototypeRegistry(10).init();

    _ = try registry.register(strlen_proto);
    _ = try registry.register(strcmp_proto);

    const found = registry.findByName("strcmp");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 2), found.?.argCount());

    const not_found = registry.findByName("nonexistent");
    try std.testing.expect(not_found == null);
}

fn testValidateArgCount() !void {
    try std.testing.expect(validateArgCount(&strlen_proto, 1));
    try std.testing.expect(!validateArgCount(&strlen_proto, 0));
    try std.testing.expect(!validateArgCount(&strlen_proto, 2));
}

fn testValidateArgCountVariadic() !void {
    var proto = Prototype.init("printf", TYPE_INT, &.{TYPE_CHAR_P});
    proto.variadic = true;

    try std.testing.expect(validateArgCount(&proto, 1));
    try std.testing.expect(validateArgCount(&proto, 5));
    try std.testing.expect(!validateArgCount(&proto, 0));
}

fn testValidateArgTypes() !void {
    const args = [_]TypeSpec{TYPE_CHAR_P};
    try std.testing.expect(validateArgTypes(&strlen_proto, &args));

    const wrong_args = [_]TypeSpec{TYPE_INT};
    try std.testing.expect(!validateArgTypes(&strlen_proto, &wrong_args));
}

fn testCallingConv() !void {
    var proto = Prototype.init("test", TYPE_INT, &.{});
    proto.calling_conv = .stdcall;

    try std.testing.expectEqual(CallingConv.stdcall, proto.calling_conv);
}

fn testCommonPrototypes() !void {
    try std.testing.expectEqual(@as(usize, 1), strlen_proto.argCount());
    try std.testing.expectEqual(@as(usize, 2), strcmp_proto.argCount());
    try std.testing.expectEqual(@as(usize, 3), memcpy_proto.argCount());
    try std.testing.expectEqual(@as(usize, 1), malloc_proto.argCount());
    try std.testing.expectEqual(@as(usize, 1), free_proto.argCount());
}

fn testRegistryFull() !void {
    var registry = PrototypeRegistry(2).init();

    _ = try registry.register(strlen_proto);
    _ = try registry.register(strcmp_proto);
    try std.testing.expectError(error.RegistryFull, registry.register(malloc_proto));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "prototype_init" {
    try testPrototypeInit();
}

test "prototype_variadic" {
    try testPrototypeVariadic();
}

test "type_spec" {
    try testTypeSpec();
}

test "prototype_registry" {
    try testPrototypeRegistry();
}

test "registry_find_by_name" {
    try testRegistryFindByName();
}

test "validate_arg_count" {
    try testValidateArgCount();
}

test "validate_arg_count_variadic" {
    try testValidateArgCountVariadic();
}

test "validate_arg_types" {
    try testValidateArgTypes();
}

test "calling_conv" {
    try testCallingConv();
}

test "common_prototypes" {
    try testCommonPrototypes();
}

test "registry_full" {
    try testRegistryFull();
}
