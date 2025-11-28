/// Python genericpath module - Common path operations (shared by os.path implementations)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Generic path functions (used by both posixpath and ntpath)
// ============================================================================

/// Generate genericpath.exists(path)
pub fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

/// Generate genericpath.isfile(path)
pub fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .file; }");
    } else {
        try self.emit("false");
    }
}

/// Generate genericpath.isdir(path)
pub fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.cwd().openDir(path, .{}) catch break :blk false; dir.close(); break :blk true; }");
    } else {
        try self.emit("false");
    }
}

/// Generate genericpath.getsize(filename)
pub fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk @as(i64, 0); break :blk @intCast(stat.size); }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

/// Generate genericpath.getatime(filename)
pub fn genGetatime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate genericpath.getmtime(filename)
pub fn genGetmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate genericpath.getctime(filename)
pub fn genGetctime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate genericpath.commonprefix(m)
pub fn genCommonprefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate genericpath.samestat(s1, s2)
pub fn genSamestat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate genericpath.samefile(f1, f2)
pub fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const p1 = ");
        try self.genExpr(args[0]);
        try self.emit("; const p2 = ");
        try self.genExpr(args[1]);
        try self.emit("; break :blk std.mem.eql(u8, p1, p2); }");
    } else {
        try self.emit("false");
    }
}

/// Generate genericpath.sameopenfile(fp1, fp2)
pub fn genSameopenfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate genericpath.islink(path)
pub fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .sym_link; }");
    } else {
        try self.emit("false");
    }
}
