/// Python warnings module - Warning control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate warnings.warn(message, category=UserWarning, stacklevel=1) -> None
pub fn genWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    // Print warning to stderr
    try self.emit("std.debug.print(\"Warning: {s}\\n\", .{");
    try self.genExpr(args[0]);
    try self.emit("})");
}

/// Generate warnings.warn_explicit(message, category, filename, lineno, ...) -> None
pub fn genWarnExplicit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genWarn(self, args);
}

/// Generate warnings.showwarning(message, category, filename, lineno, file=None, line=None)
pub fn genShowwarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genWarn(self, args);
}

/// Generate warnings.formatwarning(message, category, filename, lineno, line=None) -> str
pub fn genFormatwarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate warnings.filterwarnings(action, message='', category=Warning, ...) -> None
pub fn genFilterwarnings(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate warnings.simplefilter(action, category=Warning, lineno=0, append=False) -> None
pub fn genSimplefilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate warnings.resetwarnings() -> None
pub fn genResetwarnings(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate warnings.catch_warnings context manager
pub fn genCatchWarnings(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("record: bool = false,\n");
    try self.emitIndent();
    try self.emit("log: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(allocator),\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// Warning category classes

/// Generate warnings.Warning base class
pub fn genWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Warning\"");
}

/// Generate warnings.UserWarning
pub fn genUserWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UserWarning\"");
}

/// Generate warnings.DeprecationWarning
pub fn genDeprecationWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"DeprecationWarning\"");
}

/// Generate warnings.PendingDeprecationWarning
pub fn genPendingDeprecationWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"PendingDeprecationWarning\"");
}

/// Generate warnings.SyntaxWarning
pub fn genSyntaxWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"SyntaxWarning\"");
}

/// Generate warnings.RuntimeWarning
pub fn genRuntimeWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"RuntimeWarning\"");
}

/// Generate warnings.FutureWarning
pub fn genFutureWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"FutureWarning\"");
}

/// Generate warnings.ImportWarning
pub fn genImportWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ImportWarning\"");
}

/// Generate warnings.UnicodeWarning
pub fn genUnicodeWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UnicodeWarning\"");
}

/// Generate warnings.BytesWarning
pub fn genBytesWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BytesWarning\"");
}

/// Generate warnings.ResourceWarning
pub fn genResourceWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ResourceWarning\"");
}

/// Generate warnings.filters list
pub fn genFilters(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}
