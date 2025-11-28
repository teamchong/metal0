/// Python queue module - Synchronized queue classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate queue.Queue(maxsize=0) -> Queue
pub fn genQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("items: std.ArrayList([]const u8),\n");
    try self.emitIndent();
    try self.emit("maxsize: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn init(maxsize: i64) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .items = std.ArrayList([]const u8){}, .maxsize = maxsize };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put(self: *@This(), item: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("self.items.append(__global_allocator, item) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This()) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("if (self.items.items.len == 0) return null;\n");
    try self.emitIndent();
    try self.emit("return self.items.orderedRemove(0);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put_nowait(self: *@This(), item: []const u8) void { self.put(item); }\n");
    try self.emitIndent();
    try self.emit("pub fn get_nowait(self: *@This()) ?[]const u8 { return self.get(); }\n");
    try self.emitIndent();
    try self.emit("pub fn empty(self: *@This()) bool { return self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn full(self: *@This()) bool { return self.maxsize > 0 and @as(i64, @intCast(self.items.items.len)) >= self.maxsize; }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(self: *@This()) i64 { return @as(i64, @intCast(self.items.items.len)); }\n");
    try self.emitIndent();
    try self.emit("pub fn task_done(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn join(self: *@This()) void { _ = self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init(0)");
}

/// Generate queue.LifoQueue(maxsize=0) -> LifoQueue (stack)
pub fn genLifoQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("items: std.ArrayList([]const u8),\n");
    try self.emitIndent();
    try self.emit("maxsize: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("mutex: std.Thread.Mutex = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn init(maxsize: i64) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .items = std.ArrayList([]const u8){}, .maxsize = maxsize };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put(self: *@This(), item: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("self.items.append(__global_allocator, item) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This()) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("return self.items.popOrNull();\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn empty(self: *@This()) bool { return self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(self: *@This()) i64 { return @as(i64, @intCast(self.items.items.len)); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init(0)");
}

/// Generate queue.PriorityQueue(maxsize=0) -> PriorityQueue
pub fn genPriorityQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Simplified - same as Queue for now
    try genQueue(self, args);
}

/// Generate queue.SimpleQueue() -> SimpleQueue
pub fn genSimpleQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genQueue(self, args);
}

/// Generate queue.Empty exception
pub fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Empty\"");
}

/// Generate queue.Full exception
pub fn genFull(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Full\"");
}
