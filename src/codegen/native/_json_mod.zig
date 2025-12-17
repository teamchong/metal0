/// Python _json module - C accelerator for json (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode_basestring", genEncodeBasestring },
    .{ "encode_basestring_ascii", genEncodeBasestringAscii },
    .{ "scanstring", genScanstring },
    .{ "make_encoder", h.c(".{}") }, .{ "make_scanner", h.c(".{}") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genEncodeBasestring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\\\"\\\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_eb: {{ const s = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var result: std.ArrayList(u8) = .{{}}; result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); for (s) |c| {{ switch (c) {{ '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch @panic(\"json encode OOM\"), '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch @panic(\"json encode OOM\"), '\\n' => result.appendSlice(__global_allocator, \"\\\\n\") catch @panic(\"json encode OOM\"), '\\r' => result.appendSlice(__global_allocator, \"\\\\r\") catch @panic(\"json encode OOM\"), '\\t' => result.appendSlice(__global_allocator, \"\\\\t\") catch @panic(\"json encode OOM\"), else => result.append(__global_allocator, c) catch @panic(\"json encode OOM\"), }} }} result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); break :__m{d}_eb result.items; }})", .{id});
}

fn genEncodeBasestringAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\\\"\\\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_eba: {{ const s = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; var result: std.ArrayList(u8) = .{}; result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); for (s) |c| { if (c < 0x20 or c > 0x7e) { result.appendSlice(__global_allocator, \"\\\\u\") catch @panic(\"json encode OOM\"); var buf: [4]u8 = undefined; _ = std.fmt.bufPrint(&buf, \"{x:0>4}\", .{c}) catch unreachable; result.appendSlice(__global_allocator, &buf) catch @panic(\"json encode OOM\"); } else { switch (c) { '\"' => result.appendSlice(__global_allocator, \"\\\\\\\"\") catch @panic(\"json encode OOM\"), '\\\\' => result.appendSlice(__global_allocator, \"\\\\\\\\\") catch @panic(\"json encode OOM\"), else => result.append(__global_allocator, c) catch @panic(\"json encode OOM\"), } } } result.append(__global_allocator, '\"') catch @panic(\"json encode OOM\"); break :__m");
    try self.emitFmt("{d}_eba result.items; }})", .{id});
}

fn genScanstring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit(".{ \"\", 0 }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_ss: {{ const string = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const end_idx = "); try self.genExpr(args[1]);
    try self.emitFmt("; _ = string; break :__m{d}_ss .{{ \"\", end_idx }}; }})", .{id});
}
