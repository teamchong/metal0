/// File I/O builtins - open(), read, write, close
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate code for open(filename, mode)
/// Returns a file handle that supports .read(), .write(), .close()
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@compileError(\"open() requires at least 1 argument\")");
        return;
    }

    // Get filename argument
    const filename = args[0];

    // Get mode argument (default "r")
    const mode = if (args.len >= 2) args[1] else null;

    // Determine mode string
    var mode_str: []const u8 = "r";
    if (mode) |m| {
        if (m == .constant) {
            if (m.constant.value == .string) {
                mode_str = m.constant.value.string;
            }
        }
    }

    // Generate Zig code for file opening
    // Use a wrapper struct that provides Python-like file API
    try self.emit("blk: {\n");
    try self.emitIndent();
    try self.emit("    const __filename = ");
    try self.genExpr(filename);
    try self.emit(";\n");
    try self.emitIndent();

    // Determine if read or write mode
    const is_write = std.mem.indexOf(u8, mode_str, "w") != null or
        std.mem.indexOf(u8, mode_str, "a") != null;

    if (is_write) {
        try self.emit("    const __file = try std.fs.cwd().createFile(__filename, .{});\n");
    } else {
        try self.emit("    const __file = try std.fs.cwd().openFile(__filename, .{});\n");
    }

    try self.emitIndent();
    try self.emit("    break :blk try runtime.PyFile.create(__global_allocator, __file, ");
    if (mode) |m| {
        try self.genExpr(m);
    } else {
        try self.emit("\"r\"");
    }
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("}");
}
