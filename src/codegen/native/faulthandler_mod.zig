/// Python faulthandler module - Dump Python tracebacks on fault signals
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate faulthandler.enable(file=sys.stderr, all_threads=True)
pub fn genEnable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.disable()
pub fn genDisable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.is_enabled()
pub fn genIsEnabled(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate faulthandler.dump_traceback(file=sys.stderr, all_threads=True)
pub fn genDumpTraceback(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.dump_traceback_later(timeout, repeat=False, file=sys.stderr, exit=False)
pub fn genDumpTracebackLater(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.cancel_dump_traceback_later()
pub fn genCancelDumpTracebackLater(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.register(signum, file=sys.stderr, all_threads=True, chain=False)
pub fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate faulthandler.unregister(signum)
pub fn genUnregister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
