/// Python string module - string constants and utilities
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

// Public exports for use in builtins.zig
pub const genAsciiLowercase = h.c("\"abcdefghijklmnopqrstuvwxyz\"");
pub const genAsciiUppercase = h.c("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genAsciiLetters = h.c("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genDigits = h.c("\"0123456789\"");
pub const genPunctuation = h.c("\"!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~\"");

const tmpl = "struct { template: []const u8, pub fn substitute(__self: @This(), _: anytype) []const u8 { return __self.template; } pub fn safe_substitute(__self: @This(), _: anytype) []const u8 { return __self.template; } }";

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

/// Generate string.capwords(s) - capitalize first letter of each word
/// Emits: capwords_{id}: { const _s = arg; var _result: std.ArrayList(u8) = .{}; ... break :capwords_{id} _result.items; }
pub fn genCapwords(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitRaw("\"\"");
        try self.flushBuilder();
        return;
    }
    const s_val = try self.captureExpr(args[0]);
    try b.withLabeledBlock("__capwords", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
            try bld.emitConstWithValue("_s", "", ctx, "");
            try bld.emitVarRaw("_result", "std.ArrayList(u8)", ".{}");
            try bld.emitVarRaw("_cap_next", null, "true");
            try bld.emitRawLine("for (_s) |ch| { if (ch == ' ') { _result.append(__global_allocator, ' ') catch continue; _cap_next = true; } else if (_cap_next and ch >= 'a' and ch <= 'z') { _result.append(__global_allocator, ch - 32) catch continue; _cap_next = false; } else { _result.append(__global_allocator, ch) catch continue; _cap_next = false; } }");
            try scope.breakWithRaw("_result.items");
        }
    }.emit, s_val);
    try self.flushBuilder();
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ascii_lowercase", genAsciiLowercase }, .{ "ascii_uppercase", genAsciiUppercase },
    .{ "ascii_letters", genAsciiLetters }, .{ "digits", genDigits },
    .{ "hexdigits", h.c("\"0123456789abcdefABCDEF\"") }, .{ "octdigits", h.c("\"01234567\"") },
    .{ "punctuation", genPunctuation }, .{ "whitespace", h.c("\" \\t\\n\\r\\x0b\\x0c\"") },
    .{ "printable", h.c("\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \\t\\n\\r\\x0b\\x0c\"") },
    .{ "capwords", genCapwords },
    .{ "Formatter", h.c("struct { format: []const u8 = \"\", pub fn vformat(__self: @This(), s: []const u8, _: anytype, _: anytype) []const u8 { _ = &__self; return s; } }{}") },
    .{ "Template", h.wrap(tmpl ++ "{ .template = ", " }", tmpl ++ "{ .template = \"\" }") },
});
