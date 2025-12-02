/// Python genericpath module - Common path operations (shared by os.path implementations)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genZeroF64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "exists", genExists }, .{ "isfile", genIsfile }, .{ "isdir", genIsdir },
    .{ "getsize", genGetsize }, .{ "getatime", genZeroF64 }, .{ "getmtime", genZeroF64 }, .{ "getctime", genZeroF64 },
    .{ "commonprefix", genEmptyStr }, .{ "samestat", genFalse }, .{ "samefile", genSamefile },
    .{ "sameopenfile", genFalse }, .{ "islink", genIslink },
});

fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }"); }
    else { try self.emit("false"); }
}

fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .file; }"); }
    else { try self.emit("false"); }
}

fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const dir = std.fs.cwd().openDir(path, .{}) catch break :blk false; dir.close(); break :blk true; }"); }
    else { try self.emit("false"); }
}

fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk @as(i64, 0); break :blk @intCast(stat.size); }"); }
    else { try self.emit("@as(i64, 0)"); }
}

fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const p1 = "); try self.genExpr(args[0]); try self.emit("; const p2 = "); try self.genExpr(args[1]); try self.emit("; break :blk std.mem.eql(u8, p1, p2); }"); }
    else { try self.emit("false"); }
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .sym_link; }"); }
    else { try self.emit("false"); }
}
