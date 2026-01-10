//! test.test_capi.test_module5 - C API Module Tests Part 5 - Argument Parsing
const std = @import("std");

/// Argument parser for C API functions
pub const ArgParser = struct {
    args: []const Arg,
    kwargs: std.StringHashMap(Arg),
    allocator: std.mem.Allocator,

    pub const Arg = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        none: void,
        object: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) ArgParser {
        return .{
            .args = &[_]Arg{},
            .kwargs = std.StringHashMap(Arg).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ArgParser) void {
        self.kwargs.deinit();
    }

    pub fn set_args(self: *ArgParser, args: []const Arg) void {
        self.args = args;
    }

    pub fn set_kwarg(self: *ArgParser, name: []const u8, value: Arg) !void {
        try self.kwargs.put(name, value);
    }

    pub fn get_arg(self: *const ArgParser, index: usize) ?Arg {
        if (index < self.args.len) {
            return self.args[index];
        }
        return null;
    }

    pub fn get_kwarg(self: *const ArgParser, name: []const u8) ?Arg {
        return self.kwargs.get(name);
    }

    pub fn num_args(self: *const ArgParser) usize {
        return self.args.len;
    }

    pub fn num_kwargs(self: *const ArgParser) usize {
        return self.kwargs.count();
    }
};

/// Format specifier for PyArg_ParseTuple
pub const FormatSpec = struct {
    format: []const u8,
    required: usize = 0,
    optional: usize = 0,

    pub fn parse(format: []const u8) FormatSpec {
        var spec = FormatSpec{ .format = format };
        var in_optional = false;

        for (format) |c| {
            switch (c) {
                '|' => in_optional = true,
                'i', 'l', 'L', 'n', 'c' => { // integers
                    if (in_optional) spec.optional += 1 else spec.required += 1;
                },
                'f', 'd' => { // floats
                    if (in_optional) spec.optional += 1 else spec.required += 1;
                },
                's', 'z', 'y', 'u', 'U' => { // strings
                    if (in_optional) spec.optional += 1 else spec.required += 1;
                },
                'O', 'S', 'N' => { // objects
                    if (in_optional) spec.optional += 1 else spec.required += 1;
                },
                'p' => { // bool
                    if (in_optional) spec.optional += 1 else spec.required += 1;
                },
                else => {},
            }
        }

        return spec;
    }

    pub fn total_args(self: *const FormatSpec) usize {
        return self.required + self.optional;
    }

    pub fn validate_count(self: *const FormatSpec, count: usize) bool {
        return count >= self.required and count <= self.total_args();
    }
};

/// Keyword argument parser
pub const KeywordParser = struct {
    keywords: []const []const u8,
    values: std.StringHashMap(ArgParser.Arg),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, keywords: []const []const u8) KeywordParser {
        return .{
            .keywords = keywords,
            .values = std.StringHashMap(ArgParser.Arg).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KeywordParser) void {
        self.values.deinit();
    }

    pub fn set(self: *KeywordParser, name: []const u8, value: ArgParser.Arg) !void {
        // Check if keyword is valid
        for (self.keywords) |kw| {
            if (std.mem.eql(u8, kw, name)) {
                try self.values.put(name, value);
                return;
            }
        }
        return error.InvalidKeyword;
    }

    pub fn get(self: *const KeywordParser, name: []const u8) ?ArgParser.Arg {
        return self.values.get(name);
    }
};

/// Build value from format
pub fn Py_BuildValue(format: []const u8, values: []const ArgParser.Arg) ![]ArgParser.Arg {
    _ = format;
    return values;
}

test "ArgParser basic" {
    const allocator = std.testing.allocator;
    var parser = ArgParser.init(allocator);
    defer parser.deinit();

    const args = [_]ArgParser.Arg{ .{ .int = 42 }, .{ .string = "hello" } };
    parser.set_args(&args);

    try std.testing.expectEqual(@as(usize, 2), parser.num_args());

    const arg0 = parser.get_arg(0);
    try std.testing.expectEqual(@as(i64, 42), arg0.?.int);

    const arg1 = parser.get_arg(1);
    try std.testing.expectEqualStrings("hello", arg1.?.string);
}

test "ArgParser kwargs" {
    const allocator = std.testing.allocator;
    var parser = ArgParser.init(allocator);
    defer parser.deinit();

    try parser.set_kwarg("name", .{ .string = "test" });
    try parser.set_kwarg("value", .{ .int = 100 });

    try std.testing.expectEqual(@as(usize, 2), parser.num_kwargs());
    try std.testing.expectEqualStrings("test", parser.get_kwarg("name").?.string);
}

test "FormatSpec parsing" {
    const spec1 = FormatSpec.parse("ii");
    try std.testing.expectEqual(@as(usize, 2), spec1.required);
    try std.testing.expectEqual(@as(usize, 0), spec1.optional);

    const spec2 = FormatSpec.parse("i|is");
    try std.testing.expectEqual(@as(usize, 1), spec2.required);
    try std.testing.expectEqual(@as(usize, 2), spec2.optional);

    try std.testing.expect(spec2.validate_count(1));
    try std.testing.expect(spec2.validate_count(2));
    try std.testing.expect(spec2.validate_count(3));
    try std.testing.expect(!spec2.validate_count(0));
    try std.testing.expect(!spec2.validate_count(4));
}

test "KeywordParser" {
    const allocator = std.testing.allocator;
    const keywords = [_][]const u8{ "name", "value", "flag" };
    var parser = KeywordParser.init(allocator, &keywords);
    defer parser.deinit();

    try parser.set("name", .{ .string = "test" });
    try parser.set("value", .{ .int = 42 });

    try std.testing.expectEqualStrings("test", parser.get("name").?.string);
    try std.testing.expectError(error.InvalidKeyword, parser.set("invalid", .{ .none = {} }));
}
