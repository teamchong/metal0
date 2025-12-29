/// Python _string module - Low-level string formatting (internal)
/// Ported from CPython's Objects/stringlib/unicode_format.h
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "formatter_field_name_split", genFormatterFieldNameSplit },
    .{ "formatter_parser", genFormatterParser },
});

fn genFormatterFieldNameSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emitCallCtx("runtime._string.formatterFieldNameSplit", args[0], struct {
            pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                try s.emit("__global_allocator, ");
                try s.genExpr(e);
            }
        }.f);
    } else {
        try self.emit("runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }");
    }
}

fn genFormatterParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withParensCtx(args[0], struct {
            pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                try s.emitCallCtx("runtime._string.formatterParser", e, struct {
                    pub fn g(s2: *NativeCodegen, e2: ast.Node) CodegenError!void {
                        try s2.emit("__global_allocator, ");
                        try s2.genExpr(e2);
                    }
                }.g);
            }
        }.f);
    } else {
        try self.emit("&[_]runtime._string.FormatterResult{}");
    }
}
