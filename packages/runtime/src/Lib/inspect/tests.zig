//! Tests for the inspect module

const std = @import("std");
const predicates = @import("predicates.zig");
const signature = @import("signature.zig");
const source = @import("source.zig");
const members = @import("members.zig");

test "isclass" {
    const MyStruct = struct {
        x: i32,
        y: i32,
    };

    try std.testing.expect(predicates.isclass(MyStruct));
    try std.testing.expect(!predicates.isclass(i32));
}

test "isfunction" {
    const myFunc = struct {
        fn call(x: i32) i32 {
            return x + 1;
        }
    }.call;

    try std.testing.expect(predicates.isfunction(@TypeOf(myFunc)));
}

test "callable" {
    const Callable = struct {
        pub fn call(self: @This()) void {
            _ = self;
        }
    };

    try std.testing.expect(predicates.callable(Callable));
}

test "hasattr" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    try std.testing.expect(predicates.hasattr(Point, "x"));
    try std.testing.expect(predicates.hasattr(Point, "y"));
    try std.testing.expect(!predicates.hasattr(Point, "z"));
}

test "getmethods" {
    const Calculator = struct {
        pub fn add(a: i32, b: i32) i32 {
            return a + b;
        }
        pub fn sub(a: i32, b: i32) i32 {
            return a - b;
        }
    };

    const methods = members.getmethods(Calculator);
    try std.testing.expectEqual(@as(usize, 2), methods.len);
}

test "formatargspec" {
    const allocator = std.testing.allocator;

    const params = [_]signature.Parameter{
        .{ .name = "x", .annotation = "i32" },
        .{ .name = "y", .annotation = "i32", .default = "0" },
    };

    const sig = signature.Signature.init(&params).withReturn("i32");
    const formatted = try signature.formatargspec(sig, allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "x: i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "y: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "-> i32") != null);
}

test "cleandoc" {
    const allocator = std.testing.allocator;

    const doc =
        \\    This is a docstring.
        \\    It has multiple lines.
        \\    With consistent indentation.
    ;

    const cleaned = try source.cleandoc(allocator, doc);
    defer allocator.free(cleaned);

    try std.testing.expect(std.mem.startsWith(u8, cleaned, "This is a docstring."));
}
