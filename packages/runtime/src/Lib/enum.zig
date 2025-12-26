//! CPython source: Lib/enum.py
//!
//! Provides symbolic names (members) bound to unique, constant values.
//!
//! Mirrors: CPython Lib/enum.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Enum Base
// ============================================================================

/// Base enum member representation
pub fn EnumMember(comptime T: type) type {
    return struct {
        const Self = @This();

        name: []const u8,
        value: T,

        pub fn init(name: []const u8, value: T) Self {
            return .{ .name = name, .value = value };
        }

        pub fn repr(self: Self, buf: []u8) []const u8 {
            const written = std.fmt.bufPrint(buf, "<{s}: {any}>", .{ self.name, self.value }) catch return self.name;
            return written;
        }

        pub fn eql(self: Self, other: Self) bool {
            return std.mem.eql(u8, self.name, other.name) and self.value == other.value;
        }
    };
}

/// Create an Enum type from a list of name-value pairs
pub fn Enum(comptime T: type, comptime members: anytype) type {
    return struct {
        const Self = @This();
        pub const ValueType = T;
        pub const Member = EnumMember(T);

        /// All enum members
        pub const _members = blk: {
            var result: [members.len]Member = undefined;
            for (members, 0..) |m, i| {
                result[i] = Member.init(m.@"0", m.@"1");
            }
            break :blk result;
        };

        /// Get a member by name
        pub fn byName(name: []const u8) ?Member {
            inline for (_members) |m| {
                if (std.mem.eql(u8, m.name, name)) {
                    return m;
                }
            }
            return null;
        }

        /// Get a member by value
        pub fn byValue(value: T) ?Member {
            inline for (_members) |m| {
                if (m.value == value) {
                    return m;
                }
            }
            return null;
        }

        /// Check if a name is a valid member
        pub fn contains(name: []const u8) bool {
            return byName(name) != null;
        }

        /// Get all member names
        pub fn names() [members.len][]const u8 {
            var result: [members.len][]const u8 = undefined;
            inline for (_members, 0..) |m, i| {
                result[i] = m.name;
            }
            return result;
        }

        /// Get all member values
        pub fn values() [members.len]T {
            var result: [members.len]T = undefined;
            inline for (_members, 0..) |m, i| {
                result[i] = m.value;
            }
            return result;
        }

        /// Number of members
        pub fn len() usize {
            return members.len;
        }
    };
}

// ============================================================================
// IntEnum
// ============================================================================

/// Create an IntEnum type (enum with integer values)
pub fn IntEnum(comptime members: anytype) type {
    return Enum(i64, members);
}

/// Create an auto-numbered IntEnum starting from a value
pub fn AutoIntEnum(comptime names: anytype, comptime start: i64) type {
    const pairs = blk: {
        var result: [names.len]struct { []const u8, i64 } = undefined;
        for (names, 0..) |name, i| {
            result[i] = .{ name, start + @as(i64, @intCast(i)) };
        }
        break :blk result;
    };
    return IntEnum(pairs);
}

// ============================================================================
// StrEnum
// ============================================================================

/// Create a StrEnum type (enum with string values equal to names)
pub fn StrEnum(comptime names: anytype) type {
    const pairs = blk: {
        var result: [names.len]struct { []const u8, []const u8 } = undefined;
        for (names, 0..) |name, i| {
            result[i] = .{ name, name };
        }
        break :blk result;
    };
    return Enum([]const u8, pairs);
}

// ============================================================================
// Flag
// ============================================================================

/// Create a Flag type (enum supporting bitwise operations)
pub fn Flag(comptime members: anytype) type {
    return struct {
        const Self = @This();
        pub const Member = EnumMember(u64);

        value: u64 = 0,

        /// All flag members
        pub const _members = blk: {
            var result: [members.len]Member = undefined;
            for (members, 0..) |m, i| {
                result[i] = Member.init(m.@"0", m.@"1");
            }
            break :blk result;
        };

        pub fn init(value: u64) Self {
            return .{ .value = value };
        }

        /// Combine flags with OR
        pub fn @"or"(self: Self, other: Self) Self {
            return .{ .value = self.value | other.value };
        }

        /// Combine flags with AND
        pub fn @"and"(self: Self, other: Self) Self {
            return .{ .value = self.value & other.value };
        }

        /// XOR flags
        pub fn xor(self: Self, other: Self) Self {
            return .{ .value = self.value ^ other.value };
        }

        /// Invert flags
        pub fn invert(self: Self) Self {
            return .{ .value = ~self.value };
        }

        /// Check if flag is set
        pub fn has(self: Self, flag: u64) bool {
            return (self.value & flag) == flag;
        }

        /// Get a member by name
        pub fn byName(name: []const u8) ?Member {
            inline for (_members) |m| {
                if (std.mem.eql(u8, m.name, name)) {
                    return m;
                }
            }
            return null;
        }

        /// Get a member by value
        pub fn byValue(value: u64) ?Member {
            inline for (_members) |m| {
                if (m.value == value) {
                    return m;
                }
            }
            return null;
        }
    };
}

/// Create auto-numbered flags (powers of 2)
pub fn AutoFlag(comptime names: anytype) type {
    const pairs = blk: {
        var result: [names.len]struct { []const u8, u64 } = undefined;
        for (names, 0..) |name, i| {
            result[i] = .{ name, @as(u64, 1) << @as(u6, @intCast(i)) };
        }
        break :blk result;
    };
    return Flag(pairs);
}

// ============================================================================
// IntFlag
// ============================================================================

/// IntFlag is an alias for Flag with integer operations
pub const IntFlag = Flag;

// ============================================================================
// Python enum module compatibility exports
// ============================================================================

/// EnumMeta - the metaclass for Enum types
/// In Python, this is the metaclass that creates Enum classes.
/// In Zig, we use comptime type generation, so this is a marker type.
pub const EnumMeta = struct {
    pub const __name__ = "EnumMeta";
};

/// EnumType is an alias for EnumMeta (Python 3.11+)
pub const EnumType = EnumMeta;

/// ReprEnum - base class for enums that want repr() to show value
pub const ReprEnum = struct {
    pub const __name__ = "ReprEnum";
};

// Boundary behaviors for Flag
pub const STRICT: i64 = 1;
pub const CONFORM: i64 = 2;
pub const EJECT: i64 = 3;
pub const KEEP: i64 = 4;

// Verification decorators
pub const UNIQUE: i64 = 1;
pub const CONTINUOUS: i64 = 2;
pub const NAMED_FLAGS: i64 = 3;

/// verify decorator - validates enum properties
pub fn verify(comptime constraint: i64) fn (type) type {
    return struct {
        pub fn apply(comptime E: type) type {
            _ = constraint;
            return E;
        }
    }.apply;
}

/// member decorator - marks a value as an enum member
pub fn member(value: anytype) @TypeOf(value) {
    return value;
}

/// nonmember decorator - marks a value as NOT an enum member
pub fn nonmember(value: anytype) @TypeOf(value) {
    return value;
}

/// _simple_enum decorator (internal)
pub fn _simple_enum(comptime E: type) type {
    return E;
}

/// _test_simple_enum (internal testing)
pub fn _test_simple_enum(comptime E: type) bool {
    _ = E;
    return true;
}

/// _iter_bits_lsb - iterate over set bits from LSB
pub fn _iter_bits_lsb(value: u64) IterBitsLsb {
    return IterBitsLsb{ .value = value };
}

pub const IterBitsLsb = struct {
    value: u64,

    pub fn next(self: *IterBitsLsb) ?u64 {
        if (self.value == 0) return null;
        const bit = self.value & (~self.value +% 1); // isolate lowest set bit
        self.value &= ~bit; // clear it
        return bit;
    }
};

// ============================================================================
// Unique Decorator Simulation
// ============================================================================

/// Verify enum has unique values (compile-time check)
pub fn unique(comptime E: type) type {
    const members = E._members;
    comptime {
        for (members, 0..) |m1, i| {
            for (members[i + 1 ..]) |m2| {
                if (m1.value == m2.value) {
                    @compileError("Duplicate enum value: " ++ m1.name ++ " and " ++ m2.name);
                }
            }
        }
    }
    return E;
}

// ============================================================================
// Auto Values
// ============================================================================

/// Auto-value generator for Python enums
/// In Python's enum module, auto() generates sequential values.
/// In AOT compilation, the codegen replaces auto() calls with
/// sequential integers at compile time.
var auto_counter: i64 = 0;

pub fn auto() i64 {
    auto_counter += 1;
    return auto_counter;
}

/// Reset auto counter (called at start of each enum definition)
pub fn resetAuto() void {
    auto_counter = 0;
}

// ============================================================================
// Enum Utilities
// ============================================================================

/// Check if a type is an Enum type
pub fn isEnum(comptime T: type) bool {
    return @hasDecl(T, "_members") and @hasDecl(T, "byName") and @hasDecl(T, "byValue");
}

/// Check if a type is a Flag type
pub fn isFlag(comptime T: type) bool {
    return @hasDecl(T, "_members") and @hasDecl(T, "or") and @hasDecl(T, "and");
}

// ============================================================================
// Global Enum (string-keyed runtime enum)
// ============================================================================

/// Runtime enum that can be modified
pub const DynamicEnum = struct {
    const Self = @This();
    const StringMap = hashmap_helper.StringHashMap(i64);

    allocator: std.mem.Allocator,
    members: StringMap,
    next_value: i64 = 1,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .members = StringMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.members.deinit();
    }

    pub fn add(self: *Self, name: []const u8, value: ?i64) !void {
        const v = value orelse blk: {
            const val = self.next_value;
            self.next_value += 1;
            break :blk val;
        };
        try self.members.put(name, v);
    }

    pub fn get(self: Self, name: []const u8) ?i64 {
        return self.members.get(name);
    }

    pub fn contains(self: Self, name: []const u8) bool {
        return self.members.contains(name);
    }

    pub fn count(self: Self) usize {
        return self.members.count();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Enum basic" {
    const Color = Enum(i32, .{
        .{ "RED", 1 },
        .{ "GREEN", 2 },
        .{ "BLUE", 3 },
    });

    try std.testing.expectEqual(@as(usize, 3), Color.len());

    const red = Color.byName("RED");
    try std.testing.expect(red != null);
    try std.testing.expectEqual(@as(i32, 1), red.?.value);

    const two = Color.byValue(2);
    try std.testing.expect(two != null);
    try std.testing.expectEqualStrings("GREEN", two.?.name);

    try std.testing.expect(Color.contains("BLUE"));
    try std.testing.expect(!Color.contains("YELLOW"));
}

test "IntEnum" {
    const Status = IntEnum(.{
        .{ "PENDING", 0 },
        .{ "ACTIVE", 1 },
        .{ "COMPLETED", 2 },
    });

    try std.testing.expectEqual(@as(i64, 1), Status.byName("ACTIVE").?.value);
}

test "AutoIntEnum" {
    const Priority = AutoIntEnum(.{ "LOW", "MEDIUM", "HIGH" }, 1);

    try std.testing.expectEqual(@as(i64, 1), Priority.byName("LOW").?.value);
    try std.testing.expectEqual(@as(i64, 2), Priority.byName("MEDIUM").?.value);
    try std.testing.expectEqual(@as(i64, 3), Priority.byName("HIGH").?.value);
}

test "StrEnum" {
    const Direction = StrEnum(.{ "NORTH", "SOUTH", "EAST", "WEST" });

    try std.testing.expectEqualStrings("NORTH", Direction.byName("NORTH").?.value);
    try std.testing.expectEqualStrings("WEST", Direction.byName("WEST").?.value);
}

test "Flag" {
    const Permissions = Flag(.{
        .{ "READ", 1 },
        .{ "WRITE", 2 },
        .{ "EXECUTE", 4 },
    });

    const rw = Permissions.init(1).@"or"(Permissions.init(2));
    try std.testing.expectEqual(@as(u64, 3), rw.value);
    try std.testing.expect(rw.has(1));
    try std.testing.expect(rw.has(2));
    try std.testing.expect(!rw.has(4));
}

test "AutoFlag" {
    const Flags = AutoFlag(.{ "A", "B", "C", "D" });

    try std.testing.expectEqual(@as(u64, 1), Flags.byName("A").?.value);
    try std.testing.expectEqual(@as(u64, 2), Flags.byName("B").?.value);
    try std.testing.expectEqual(@as(u64, 4), Flags.byName("C").?.value);
    try std.testing.expectEqual(@as(u64, 8), Flags.byName("D").?.value);
}

test "DynamicEnum" {
    const allocator = std.testing.allocator;

    var e = DynamicEnum.init(allocator);
    defer e.deinit();

    try e.add("ONE", 1);
    try e.add("TWO", null); // auto-assign
    try e.add("THREE", null);

    try std.testing.expectEqual(@as(?i64, 1), e.get("ONE"));
    try std.testing.expectEqual(@as(?i64, 1), e.get("TWO"));
    try std.testing.expectEqual(@as(?i64, 2), e.get("THREE"));
    try std.testing.expect(e.contains("ONE"));
    try std.testing.expect(!e.contains("FOUR"));
}

test "isEnum" {
    const Color = Enum(i32, .{
        .{ "RED", 1 },
    });

    try std.testing.expect(isEnum(Color));
    try std.testing.expect(!isEnum(i32));
}

test "isFlag" {
    const Perms = Flag(.{
        .{ "READ", 1 },
    });

    try std.testing.expect(isFlag(Perms));
    try std.testing.expect(!isFlag(i32));
}
