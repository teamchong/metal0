//! test.test_dataclasses - Dataclass implementation tests
const std = @import("std");

pub fn dataclass(comptime T: type) type {
    return struct {
        const Self = @This();
        const Fields = @typeInfo(T).@"struct".fields;
        
        data: T,
        
        pub fn init(args: T) Self {
            return .{ .data = args };
        }
        
        pub fn field(self: Self, comptime name: []const u8) @TypeOf(@field(self.data, name)) {
            return @field(self.data, name);
        }
        
        pub fn eql(self: Self, other: Self) bool {
            inline for (Fields) |f| {
                if (@field(self.data, f.name) != @field(other.data, f.name)) return false;
            }
            return true;
        }
        
        pub fn hash(self: Self) u64 {
            var h: u64 = 0;
            inline for (Fields) |f| {
                const val = @field(self.data, f.name);
                h ^= @as(u64, @intCast(@as(u32, @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&val))))));
            }
            return h;
        }
        
        pub fn asdict(self: Self) T {
            return self.data;
        }
        
        pub fn astuple(self: Self) FieldTuple(T) {
            var result: FieldTuple(T) = undefined;
            inline for (Fields, 0..) |f, i| {
                result[i] = @field(self.data, f.name);
            }
            return result;
        }
        
        pub fn replace(self: Self, updates: anytype) Self {
            var new_data = self.data;
            inline for (@typeInfo(@TypeOf(updates)).@"struct".fields) |f| {
                @field(new_data, f.name) = @field(updates, f.name);
            }
            return .{ .data = new_data };
        }
    };
}

fn FieldTuple(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    var types: [fields.len]type = undefined;
    for (fields, 0..) |f, i| {
        types[i] = f.type;
    }
    return std.meta.Tuple(&types);
}

pub const FieldInfo = struct {
    name: []const u8,
    type_name: []const u8,
    has_default: bool,
    default_value: ?[]const u8,
};

pub fn fields(comptime T: type) []const FieldInfo {
    const type_fields = @typeInfo(T).@"struct".fields;
    var result: [type_fields.len]FieldInfo = undefined;
    for (type_fields, 0..) |f, i| {
        result[i] = .{
            .name = f.name,
            .type_name = @typeName(f.type),
            .has_default = f.default_value_ptr != null,
            .default_value = null,
        };
    }
    return &result;
}

const Point = struct { x: i32, y: i32 };
const Person = struct { name: []const u8, age: u32 };

test "dataclass_init" {
    const DC = dataclass(Point);
    const p = DC.init(.{ .x = 10, .y = 20 });
    try std.testing.expectEqual(@as(i32, 10), p.field("x"));
    try std.testing.expectEqual(@as(i32, 20), p.field("y"));
}

test "dataclass_eql" {
    const DC = dataclass(Point);
    const p1 = DC.init(.{ .x = 1, .y = 2 });
    const p2 = DC.init(.{ .x = 1, .y = 2 });
    const p3 = DC.init(.{ .x = 3, .y = 4 });
    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(!p1.eql(p3));
}

test "dataclass_replace" {
    const DC = dataclass(Point);
    const p1 = DC.init(.{ .x = 1, .y = 2 });
    const p2 = p1.replace(.{ .x = 100 });
    try std.testing.expectEqual(@as(i32, 100), p2.field("x"));
    try std.testing.expectEqual(@as(i32, 2), p2.field("y"));
}

test "dataclass_asdict" {
    const DC = dataclass(Point);
    const p = DC.init(.{ .x = 5, .y = 10 });
    const d = p.asdict();
    try std.testing.expectEqual(@as(i32, 5), d.x);
    try std.testing.expectEqual(@as(i32, 10), d.y);
}
