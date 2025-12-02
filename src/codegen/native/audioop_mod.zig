/// Python audioop module - Audio operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "add", genConst("\"\"") }, .{ "alaw2lin", genConst("\"\"") }, .{ "bias", genConst("\"\"") }, .{ "byteswap", genConst("\"\"") },
    .{ "lin2alaw", genConst("\"\"") }, .{ "lin2lin", genConst("\"\"") }, .{ "lin2ulaw", genConst("\"\"") }, .{ "mul", genConst("\"\"") },
    .{ "reverse", genConst("\"\"") }, .{ "tomono", genConst("\"\"") }, .{ "tostereo", genConst("\"\"") }, .{ "ulaw2lin", genConst("\"\"") },
    .{ "avg", genConst("@as(i32, 0)") }, .{ "avgpp", genConst("@as(i32, 0)") }, .{ "cross", genConst("@as(i32, 0)") }, .{ "findmax", genConst("@as(i32, 0)") },
    .{ "getsample", genConst("@as(i32, 0)") }, .{ "max", genConst("@as(i32, 0)") }, .{ "maxpp", genConst("@as(i32, 0)") }, .{ "rms", genConst("@as(i32, 0)") },
    .{ "findfactor", genConst("@as(f64, 1.0)") }, .{ "minmax", genConst(".{ @as(i32, 0), @as(i32, 0) }") }, .{ "findfit", genConst(".{ @as(i32, 0), @as(f64, 1.0) }") },
    .{ "adpcm2lin", genConst(".{ \"\", .{ @as(i32, 0), @as(i32, 0) } }") }, .{ "lin2adpcm", genConst(".{ \"\", .{ @as(i32, 0), @as(i32, 0) } }") },
    .{ "ratecv", genConst(".{ \"\", .{ @as(i32, 0), .{} } }") }, .{ "error", genConst("error.AudioopError") },
});
