/// File methods - read(), write(), close()
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate code for file.read()
pub fn genFileRead(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // read() takes no args (or optional n)
    try self.emit("try runtime.PyFile.read(");
    try self.genExpr(obj);
    try self.emit(", __global_allocator)");
}

/// Generate code for file.write(content)
pub fn genFileWrite(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@compileError(\"write() requires 1 argument\")");
        return;
    }
    try self.emit("try runtime.PyFile.write(");
    try self.genExpr(obj);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for file.close()
pub fn genFileClose(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.PyFile.close(");
    try self.genExpr(obj);
    try self.emit(")");
}
