//! test.test_inspect - Runtime introspection tests
const std = @import("std");

pub fn isfunction(obj: anytype) bool {
    return @typeInfo(@TypeOf(obj)) == .@"fn" or @typeInfo(@TypeOf(obj)) == .pointer;
}

pub fn ismethod(obj: anytype) bool {
    _ = obj;
    return false;
}

pub fn isclass(obj: anytype) bool {
    return @typeInfo(@TypeOf(obj)) == .type;
}

pub fn ismodule(obj: anytype) bool {
    _ = obj;
    return @typeInfo(@TypeOf(obj)) == .@"struct";
}

pub fn getmembers(comptime T: type) []const Member {
    const info = @typeInfo(T);
    if (info != .@"struct") return &.{};
    const decls = info.@"struct".decls;
    var result: [decls.len]Member = undefined;
    for (decls, 0..) |d, i| {
        result[i] = .{ .name = d.name, .kind = .field };
    }
    return &result;
}

pub const Member = struct {
    name: []const u8,
    kind: Kind,
    
    pub const Kind = enum { field, method, property };
};

pub const Signature = struct {
    parameters: []const Parameter,
    return_annotation: ?[]const u8 = null,
    
    pub fn init(params: []const Parameter) @This() {
        return .{ .parameters = params };
    }
};

pub const Parameter = struct {
    name: []const u8,
    kind: Kind = .positional_or_keyword,
    default: ?[]const u8 = null,
    annotation: ?[]const u8 = null,
    
    pub const Kind = enum {
        positional_only,
        positional_or_keyword,
        var_positional,
        keyword_only,
        var_keyword,
    };
};

pub fn signature(comptime func: anytype) Signature {
    const info = @typeInfo(@TypeOf(func));
    if (info != .@"fn") return .{ .parameters = &.{} };
    var params: [info.@"fn".params.len]Parameter = undefined;
    for (info.@"fn".params, 0..) |p, i| {
        params[i] = .{
            .name = if (p.name) |n| n else "",
            .annotation = @typeName(p.type.?),
        };
    }
    return .{ .parameters = &params };
}

pub fn getsource(comptime _: anytype) ?[]const u8 {
    return null;
}

pub fn getfile(comptime _: anytype) ?[]const u8 {
    return null;
}

pub fn getmodule(comptime _: anytype) ?[]const u8 {
    return null;
}

pub const FrameInfo = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    code_context: ?[]const []const u8 = null,
    index: ?usize = null,
};

test "isfunction" {
    const f = struct { fn func() void {} }.func;
    try std.testing.expect(isfunction(f));
}

test "isclass" {
    const MyStruct = struct {};
    try std.testing.expect(isclass(MyStruct));
}

test "parameter_kinds" {
    const p1 = Parameter{ .name = "arg1", .kind = .positional_only };
    const p2 = Parameter{ .name = "arg2", .kind = .keyword_only };
    try std.testing.expectEqual(Parameter.Kind.positional_only, p1.kind);
    try std.testing.expectEqual(Parameter.Kind.keyword_only, p2.kind);
}

test "signature_init" {
    const params = [_]Parameter{
        .{ .name = "a" },
        .{ .name = "b" },
    };
    const sig = Signature.init(&params);
    try std.testing.expectEqual(@as(usize, 2), sig.parameters.len);
}
