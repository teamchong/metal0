//! test.test_pydoc.test_functions - Tests for function documentation
//! Tests extracting and rendering documentation from Python functions.

const std = @import("std");
const testing = std.testing;

/// Function kinds
pub const FunctionKind = enum {
    regular,
    builtin,
    lambda,
    generator,
    async_func,
    async_generator,
    coroutine,

    pub fn displayName(self: FunctionKind) []const u8 {
        return switch (self) {
            .regular => "function",
            .builtin => "built-in function",
            .lambda => "lambda",
            .generator => "generator function",
            .async_func => "async function",
            .async_generator => "async generator",
            .coroutine => "coroutine function",
        };
    }

    pub fn isAsync(self: FunctionKind) bool {
        return self == .async_func or self == .async_generator or self == .coroutine;
    }

    pub fn isGenerator(self: FunctionKind) bool {
        return self == .generator or self == .async_generator;
    }
};

/// Function signature parameter
pub const FuncParam = struct {
    name: []const u8,
    annotation: ?[]const u8 = null,
    default: ?[]const u8 = null,
    kind: ParamKind = .positional_or_keyword,

    pub const ParamKind = enum {
        positional_only,
        positional_or_keyword,
        var_positional,
        keyword_only,
        var_keyword,

        pub fn marker(self: ParamKind) ?[]const u8 {
            return switch (self) {
                .var_positional => "*",
                .var_keyword => "**",
                else => null,
            };
        }
    };

    pub fn init(name: []const u8) FuncParam {
        return .{ .name = name };
    }

    pub fn withAnnotation(self: FuncParam, annotation: []const u8) FuncParam {
        var result = self;
        result.annotation = annotation;
        return result;
    }

    pub fn withDefault(self: FuncParam, default: []const u8) FuncParam {
        var result = self;
        result.default = default;
        return result;
    }

    pub fn asVarPositional(self: FuncParam) FuncParam {
        var result = self;
        result.kind = .var_positional;
        return result;
    }

    pub fn asVarKeyword(self: FuncParam) FuncParam {
        var result = self;
        result.kind = .var_keyword;
        return result;
    }

    pub fn asKeywordOnly(self: FuncParam) FuncParam {
        var result = self;
        result.kind = .keyword_only;
        return result;
    }

    pub fn isRequired(self: FuncParam) bool {
        return self.default == null and
            self.kind != .var_positional and
            self.kind != .var_keyword;
    }

    pub fn toSignatureString(self: FuncParam, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        if (self.kind.marker()) |m| {
            try writer.writeAll(m);
        }
        try writer.writeAll(self.name);
        if (self.annotation) |ann| {
            try writer.print(": {s}", .{ann});
        }
        if (self.default) |def| {
            try writer.print(" = {s}", .{def});
        }

        return result.toOwnedSlice();
    }
};

/// Function signature
pub const FuncSignature = struct {
    params: std.ArrayList(FuncParam),
    return_annotation: ?[]const u8 = null,
    has_positional_only_sep: bool = false,
    has_keyword_only_sep: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FuncSignature {
        return .{
            .params = std.ArrayList(FuncParam).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FuncSignature) void {
        self.params.deinit();
    }

    pub fn addParam(self: *FuncSignature, param: FuncParam) !void {
        try self.params.append(param);
    }

    pub fn withReturn(self: *FuncSignature, ret: []const u8) *FuncSignature {
        self.return_annotation = ret;
        return self;
    }

    pub fn paramCount(self: FuncSignature) usize {
        return self.params.items.len;
    }

    pub fn requiredCount(self: FuncSignature) usize {
        var count: usize = 0;
        for (self.params.items) |p| {
            if (p.isRequired()) count += 1;
        }
        return count;
    }

    pub fn toString(self: FuncSignature) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.writeByte('(');
        for (self.params.items, 0..) |p, i| {
            if (i > 0) try writer.writeAll(", ");
            const ps = try p.toSignatureString(self.allocator);
            defer self.allocator.free(ps);
            try writer.writeAll(ps);
        }
        try writer.writeByte(')');

        if (self.return_annotation) |ret| {
            try writer.print(" -> {s}", .{ret});
        }

        return result.toOwnedSlice();
    }
};

/// Complete function documentation
pub const FunctionDoc = struct {
    name: []const u8,
    module: ?[]const u8,
    kind: FunctionKind,
    signature: ?FuncSignature,
    docstring: ?[]const u8,
    decorators: []const []const u8,
    source_file: ?[]const u8,
    line_number: ?u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) FunctionDoc {
        return .{
            .name = name,
            .module = null,
            .kind = .regular,
            .signature = null,
            .docstring = null,
            .decorators = &.{},
            .source_file = null,
            .line_number = null,
            .allocator = allocator,
        };
    }

    pub fn withKind(self: FunctionDoc, kind: FunctionKind) FunctionDoc {
        var result = self;
        result.kind = kind;
        return result;
    }

    pub fn withDocstring(self: FunctionDoc, doc: []const u8) FunctionDoc {
        var result = self;
        result.docstring = doc;
        return result;
    }

    pub fn withModule(self: FunctionDoc, module: []const u8) FunctionDoc {
        var result = self;
        result.module = module;
        return result;
    }

    pub fn qualifiedName(self: FunctionDoc) []const u8 {
        // Would combine module.name
        return self.name;
    }

    pub fn shortDoc(self: FunctionDoc) ?[]const u8 {
        if (self.docstring) |doc| {
            var lines = std.mem.splitScalar(u8, doc, '\n');
            return lines.first();
        }
        return null;
    }

    pub fn hasAnnotations(self: FunctionDoc) bool {
        if (self.signature) |sig| {
            if (sig.return_annotation != null) return true;
            for (sig.params.items) |p| {
                if (p.annotation != null) return true;
            }
        }
        return false;
    }
};

/// Function documentation extractor
pub const FunctionExtractor = struct {
    include_signature: bool = true,
    include_source_info: bool = true,
    parse_docstring: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FunctionExtractor {
        return .{ .allocator = allocator };
    }

    pub fn extract(self: FunctionExtractor, name: []const u8) !FunctionDoc {
        // Would introspect actual function
        return FunctionDoc.init(self.allocator, name);
    }

    pub fn extractBuiltin(self: FunctionExtractor, name: []const u8) !FunctionDoc {
        return FunctionDoc.init(self.allocator, name).withKind(.builtin);
    }
};

/// Function signature parser
pub const SignatureParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SignatureParser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: SignatureParser, sig_str: []const u8) !FuncSignature {
        // Simplified: would parse actual signature
        _ = sig_str;
        return FuncSignature.init(self.allocator);
    }

    pub fn parseAnnotation(self: SignatureParser, ann_str: []const u8) []const u8 {
        _ = self;
        return ann_str;
    }
};

// Tests
test "function_kind_display_name" {
    try testing.expectEqualStrings("function", FunctionKind.regular.displayName());
    try testing.expectEqualStrings("async function", FunctionKind.async_func.displayName());
    try testing.expectEqualStrings("generator function", FunctionKind.generator.displayName());
}

test "function_kind_is_async" {
    try testing.expect(FunctionKind.async_func.isAsync());
    try testing.expect(FunctionKind.async_generator.isAsync());
    try testing.expect(!FunctionKind.regular.isAsync());
}

test "function_kind_is_generator" {
    try testing.expect(FunctionKind.generator.isGenerator());
    try testing.expect(FunctionKind.async_generator.isGenerator());
    try testing.expect(!FunctionKind.regular.isGenerator());
}

test "func_param_init" {
    const param = FuncParam.init("x");
    try testing.expectEqualStrings("x", param.name);
    try testing.expect(param.isRequired());
}

test "func_param_with_annotation" {
    const param = FuncParam.init("x").withAnnotation("int");
    try testing.expectEqualStrings("int", param.annotation.?);
}

test "func_param_with_default" {
    const param = FuncParam.init("x").withDefault("0");
    try testing.expect(!param.isRequired());
}

test "func_param_var_positional" {
    const param = FuncParam.init("args").asVarPositional();
    try testing.expectEqual(FuncParam.ParamKind.var_positional, param.kind);
    try testing.expect(!param.isRequired());
}

test "func_param_var_keyword" {
    const param = FuncParam.init("kwargs").asVarKeyword();
    try testing.expectEqual(FuncParam.ParamKind.var_keyword, param.kind);
}

test "func_param_to_string" {
    const param = FuncParam.init("x").withAnnotation("int").withDefault("0");
    const s = try param.toSignatureString(testing.allocator);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("x: int = 0", s);
}

test "func_signature_init" {
    var sig = FuncSignature.init(testing.allocator);
    defer sig.deinit();
    try testing.expectEqual(@as(usize, 0), sig.paramCount());
}

test "func_signature_add_param" {
    var sig = FuncSignature.init(testing.allocator);
    defer sig.deinit();
    try sig.addParam(FuncParam.init("x"));
    try testing.expectEqual(@as(usize, 1), sig.paramCount());
}

test "func_signature_required_count" {
    var sig = FuncSignature.init(testing.allocator);
    defer sig.deinit();
    try sig.addParam(FuncParam.init("x"));
    try sig.addParam(FuncParam.init("y").withDefault("1"));
    try testing.expectEqual(@as(usize, 1), sig.requiredCount());
}

test "func_signature_to_string" {
    var sig = FuncSignature.init(testing.allocator);
    defer sig.deinit();
    try sig.addParam(FuncParam.init("x"));
    _ = sig.withReturn("int");
    const s = try sig.toString();
    defer testing.allocator.free(s);
    try testing.expect(std.mem.indexOf(u8, s, "x") != null);
    try testing.expect(std.mem.indexOf(u8, s, "-> int") != null);
}

test "function_doc_init" {
    const doc = FunctionDoc.init(testing.allocator, "my_func");
    try testing.expectEqualStrings("my_func", doc.name);
    try testing.expectEqual(FunctionKind.regular, doc.kind);
}

test "function_doc_with_kind" {
    const doc = FunctionDoc.init(testing.allocator, "gen").withKind(.generator);
    try testing.expectEqual(FunctionKind.generator, doc.kind);
}

test "function_doc_with_docstring" {
    const doc = FunctionDoc.init(testing.allocator, "f").withDocstring("Does something.");
    try testing.expectEqualStrings("Does something.", doc.docstring.?);
}

test "function_doc_short_doc" {
    const doc = FunctionDoc.init(testing.allocator, "f")
        .withDocstring("First line.\n\nMore details.");
    try testing.expectEqualStrings("First line.", doc.shortDoc().?);
}

test "function_extractor_init" {
    const extractor = FunctionExtractor.init(testing.allocator);
    try testing.expect(extractor.include_signature);
    try testing.expect(extractor.parse_docstring);
}

test "signature_parser_init" {
    const parser = SignatureParser.init(testing.allocator);
    _ = parser.parseAnnotation("int");
}
