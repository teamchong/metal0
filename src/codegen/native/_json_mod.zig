/// Python _json module - C accelerator for json (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode_basestring", genEncodeBase }, .{ "encode_basestring_ascii", genEncodeAscii }, .{ "scanstring", genScan }, .{ "make_encoder", genConst(".{}") }, .{ "make_scanner", genConst(".{}") },
});

fn genEncodeBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; var result: std.ArrayList(u8) = .{}; result.append('\"') catch {}; for (s) |c| { switch (c) { '\"' => result.appendSlice(\"\\\\\\\"\") catch {}, '\\\\' => result.appendSlice(\"\\\\\\\\\") catch {}, '\\n' => result.appendSlice(\"\\\\n\") catch {}, '\\r' => result.appendSlice(\"\\\\r\") catch {}, '\\t' => result.appendSlice(\"\\\\t\") catch {}, else => result.append(c) catch {}, } } result.append('\"') catch {}; break :blk result.items; }"); } else { try self.emit("\"\\\"\\\"\""); }
}

fn genEncodeAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const s = "); try self.genExpr(args[0]); try self.emit("; var result: std.ArrayList(u8) = .{}; result.append('\"') catch {}; for (s) |c| { if (c < 0x20 or c > 0x7e) { result.appendSlice(\"\\\\u\") catch {}; var buf: [4]u8 = undefined; _ = std.fmt.bufPrint(&buf, \"{x:0>4}\", .{c}) catch {}; result.appendSlice(&buf) catch {}; } else { switch (c) { '\"' => result.appendSlice(\"\\\\\\\"\") catch {}, '\\\\' => result.appendSlice(\"\\\\\\\\\") catch {}, else => result.append(c) catch {}, } } } result.append('\"') catch {}; break :blk result.items; }"); } else { try self.emit("\"\\\"\\\"\""); }
}

fn genScan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const string = "); try self.genExpr(args[0]); try self.emit("; const end_idx = "); try self.genExpr(args[1]); try self.emit("; _ = string; break :blk .{ \"\", end_idx }; }"); } else { try self.emit(".{ \"\", 0 }"); }
}
