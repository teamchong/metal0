/// Python pipes module - Interface to shell pipelines (deprecated in 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pipes.Template()
pub fn genTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .steps = &[_][]const u8{}, .debugging = false }");
}

/// Generate Template.reset()
pub fn genReset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Template.clone()
pub fn genClone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .steps = &[_][]const u8{}, .debugging = false }");
}

/// Generate Template.debug(flag)
pub fn genDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Template.append(cmd, kind)
pub fn genAppend(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Template.prepend(cmd, kind)
pub fn genPrepend(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Template.open(file, rw)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Template.copy(infile, outfile)
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pipes.FILEIN_FILEOUT constant
pub fn genFileInFileOut(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ff\"");
}

/// Generate pipes.STDIN_FILEOUT constant
pub fn genStdinFileOut(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"-f\"");
}

/// Generate pipes.FILEIN_STDOUT constant
pub fn genFileInStdout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"f-\"");
}

/// Generate pipes.STDIN_STDOUT constant
pub fn genStdinStdout(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"--\"");
}

/// Generate pipes.quote(s)
pub fn genQuote(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const s = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = s; break :blk \"''\"; }");
    } else {
        try self.emit("\"''\"");
    }
}
