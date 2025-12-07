/// structmember - Struct Member Access
/// Mirrors cpython/Python/structmember.c
///
/// This module provides struct member access descriptors:
/// - PyMemberDef for defining type members
/// - Get/set functions for different member types
/// - Support for readonly and optional members

const std = @import("std");

// ============================================================================
// Member Types
// ============================================================================

/// Member type codes (matches CPython's structmember.h)
pub const MemberType = enum(i32) {
    T_SHORT = 0,
    T_INT = 1,
    T_LONG = 2,
    T_FLOAT = 3,
    T_DOUBLE = 4,
    T_STRING = 5, // null-terminated string
    T_OBJECT = 6, // Python object pointer
    T_CHAR = 7, // single character
    T_BYTE = 8,
    T_UBYTE = 9,
    T_USHORT = 10,
    T_UINT = 11,
    T_ULONG = 12,
    T_STRING_INPLACE = 13, // fixed-size char array
    T_BOOL = 14,
    T_OBJECT_EX = 16, // like T_OBJECT but raises AttributeError if NULL
    T_LONGLONG = 17,
    T_ULONGLONG = 18,
    T_PYSSIZET = 19, // Py_ssize_t
    T_NONE = 20, // always None
};

/// Member flags
pub const MemberFlags = struct {
    pub const READONLY: i32 = 1;
    pub const PY_AUDIT_READ: i32 = 2;
    pub const RESTRICTED: i32 = 4; // Deprecated
};

// ============================================================================
// Member Definition
// ============================================================================

/// Member definition (matches PyMemberDef)
pub const PyMemberDef = struct {
    name: []const u8,
    type: MemberType,
    offset: usize,
    flags: i32 = 0,
    doc: ?[]const u8 = null,

    const Self = @This();

    /// Check if member is readonly
    pub fn isReadonly(self: Self) bool {
        return self.flags & MemberFlags.READONLY != 0;
    }

    /// Check if member requires audit on read
    pub fn requiresAuditRead(self: Self) bool {
        return self.flags & MemberFlags.PY_AUDIT_READ != 0;
    }
};

// ============================================================================
// Member Access
// ============================================================================

/// Generic value that can hold any member type
pub const MemberValue = union(enum) {
    short_val: i16,
    int_val: i32,
    long_val: i64,
    float_val: f32,
    double_val: f64,
    string_val: ?[]const u8,
    object_val: ?*anyopaque,
    char_val: u8,
    byte_val: i8,
    ubyte_val: u8,
    ushort_val: u16,
    uint_val: u32,
    ulong_val: u64,
    bool_val: bool,
    longlong_val: i64,
    ulonglong_val: u64,
    ssize_val: isize,
    none: void,
};

/// Get member value from object
pub fn getMember(obj: *anyopaque, member: PyMemberDef) !MemberValue {
    const base: [*]u8 = @ptrCast(obj);
    const ptr = base + member.offset;

    return switch (member.type) {
        .T_SHORT => .{ .short_val = @as(*align(1) i16, @ptrCast(ptr)).* },
        .T_INT => .{ .int_val = @as(*align(1) i32, @ptrCast(ptr)).* },
        .T_LONG => .{ .long_val = @as(*align(1) i64, @ptrCast(ptr)).* },
        .T_FLOAT => .{ .float_val = @as(*align(1) f32, @ptrCast(ptr)).* },
        .T_DOUBLE => .{ .double_val = @as(*align(1) f64, @ptrCast(ptr)).* },
        .T_STRING => .{ .string_val = readString(ptr) },
        .T_OBJECT => .{ .object_val = @as(*align(1) ?*anyopaque, @ptrCast(ptr)).* },
        .T_CHAR => .{ .char_val = ptr[0] },
        .T_BYTE => .{ .byte_val = @as(*align(1) i8, @ptrCast(ptr)).* },
        .T_UBYTE => .{ .ubyte_val = ptr[0] },
        .T_USHORT => .{ .ushort_val = @as(*align(1) u16, @ptrCast(ptr)).* },
        .T_UINT => .{ .uint_val = @as(*align(1) u32, @ptrCast(ptr)).* },
        .T_ULONG => .{ .ulong_val = @as(*align(1) u64, @ptrCast(ptr)).* },
        .T_BOOL => .{ .bool_val = ptr[0] != 0 },
        .T_OBJECT_EX => blk: {
            const obj_ptr = @as(*align(1) ?*anyopaque, @ptrCast(ptr)).*;
            if (obj_ptr == null) {
                return error.AttributeError;
            }
            break :blk .{ .object_val = obj_ptr };
        },
        .T_LONGLONG => .{ .longlong_val = @as(*align(1) i64, @ptrCast(ptr)).* },
        .T_ULONGLONG => .{ .ulonglong_val = @as(*align(1) u64, @ptrCast(ptr)).* },
        .T_PYSSIZET => .{ .ssize_val = @as(*align(1) isize, @ptrCast(ptr)).* },
        .T_NONE => .{ .none = {} },
        .T_STRING_INPLACE => .{ .string_val = readStringInplace(ptr) },
    };
}

/// Set member value on object
pub fn setMember(obj: *anyopaque, member: PyMemberDef, value: MemberValue) !void {
    if (member.isReadonly()) {
        return error.ReadonlyMember;
    }

    const base: [*]u8 = @ptrCast(obj);
    const ptr = base + member.offset;

    switch (member.type) {
        .T_SHORT => @as(*align(1) i16, @ptrCast(ptr)).* = value.short_val,
        .T_INT => @as(*align(1) i32, @ptrCast(ptr)).* = value.int_val,
        .T_LONG => @as(*align(1) i64, @ptrCast(ptr)).* = value.long_val,
        .T_FLOAT => @as(*align(1) f32, @ptrCast(ptr)).* = value.float_val,
        .T_DOUBLE => @as(*align(1) f64, @ptrCast(ptr)).* = value.double_val,
        .T_OBJECT, .T_OBJECT_EX => @as(*align(1) ?*anyopaque, @ptrCast(ptr)).* = value.object_val,
        .T_CHAR => ptr[0] = value.char_val,
        .T_BYTE => @as(*align(1) i8, @ptrCast(ptr)).* = value.byte_val,
        .T_UBYTE => ptr[0] = value.ubyte_val,
        .T_USHORT => @as(*align(1) u16, @ptrCast(ptr)).* = value.ushort_val,
        .T_UINT => @as(*align(1) u32, @ptrCast(ptr)).* = value.uint_val,
        .T_ULONG => @as(*align(1) u64, @ptrCast(ptr)).* = value.ulong_val,
        .T_BOOL => ptr[0] = if (value.bool_val) 1 else 0,
        .T_LONGLONG => @as(*align(1) i64, @ptrCast(ptr)).* = value.longlong_val,
        .T_ULONGLONG => @as(*align(1) u64, @ptrCast(ptr)).* = value.ulonglong_val,
        .T_PYSSIZET => @as(*align(1) isize, @ptrCast(ptr)).* = value.ssize_val,
        .T_STRING, .T_STRING_INPLACE, .T_NONE => return error.CannotSetMember,
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn readString(ptr: [*]u8) ?[]const u8 {
    const str_ptr = @as(*align(1) ?[*:0]const u8, @ptrCast(ptr)).*;
    if (str_ptr) |s| {
        return std.mem.sliceTo(s, 0);
    }
    return null;
}

fn readStringInplace(ptr: [*]u8) []const u8 {
    // Find null terminator
    var len: usize = 0;
    while (ptr[len] != 0) {
        len += 1;
        if (len > 1024) break; // Safety limit
    }
    return ptr[0..len];
}

// ============================================================================
// Member Table Operations
// ============================================================================

/// Find member by name in member table
pub fn findMember(members: []const PyMemberDef, name: []const u8) ?PyMemberDef {
    for (members) |m| {
        if (std.mem.eql(u8, m.name, name)) {
            return m;
        }
    }
    return null;
}

/// Get size of member type in bytes
pub fn memberSize(member_type: MemberType) usize {
    return switch (member_type) {
        .T_SHORT => 2,
        .T_INT => 4,
        .T_LONG => 8,
        .T_FLOAT => 4,
        .T_DOUBLE => 8,
        .T_STRING => @sizeOf(*anyopaque),
        .T_OBJECT, .T_OBJECT_EX => @sizeOf(*anyopaque),
        .T_CHAR => 1,
        .T_BYTE => 1,
        .T_UBYTE => 1,
        .T_USHORT => 2,
        .T_UINT => 4,
        .T_ULONG => 8,
        .T_BOOL => 1,
        .T_LONGLONG => 8,
        .T_ULONGLONG => 8,
        .T_PYSSIZET => @sizeOf(isize),
        .T_STRING_INPLACE => 0, // Variable
        .T_NONE => 0,
    };
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "member types" {
    try std.testing.expectEqual(@as(usize, 4), memberSize(.T_INT));
    try std.testing.expectEqual(@as(usize, 8), memberSize(.T_DOUBLE));
    try std.testing.expectEqual(@as(usize, 1), memberSize(.T_BOOL));
}

test "find member" {
    const members = [_]PyMemberDef{
        .{ .name = "x", .type = .T_INT, .offset = 0 },
        .{ .name = "y", .type = .T_INT, .offset = 4 },
        .{ .name = "name", .type = .T_STRING, .offset = 8 },
    };

    const found = findMember(&members, "y");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 4), found.?.offset);

    const not_found = findMember(&members, "z");
    try std.testing.expect(not_found == null);
}

test "member flags" {
    const readonly_member = PyMemberDef{
        .name = "readonly",
        .type = .T_INT,
        .offset = 0,
        .flags = MemberFlags.READONLY,
    };

    try std.testing.expect(readonly_member.isReadonly());

    const normal_member = PyMemberDef{
        .name = "normal",
        .type = .T_INT,
        .offset = 0,
    };

    try std.testing.expect(!normal_member.isReadonly());
}

test "get and set member" {
    const TestStruct = struct {
        x: i32 = 0,
        y: f64 = 0.0,
        flag: u8 = 0,
    };

    var obj = TestStruct{};
    const obj_ptr: *anyopaque = @ptrCast(&obj);

    const x_member = PyMemberDef{
        .name = "x",
        .type = .T_INT,
        .offset = @offsetOf(TestStruct, "x"),
    };

    // Set
    try setMember(obj_ptr, x_member, .{ .int_val = 42 });

    // Get
    const value = try getMember(obj_ptr, x_member);
    try std.testing.expectEqual(@as(i32, 42), value.int_val);
}
