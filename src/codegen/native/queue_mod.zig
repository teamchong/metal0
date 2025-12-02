/// Python queue module - Synchronized queue classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Queue", genQueue },
    .{ "LifoQueue", genLifoQueue },
    .{ "PriorityQueue", genPriorityQueue },
    .{ "SimpleQueue", genSimpleQueue },
    .{ "Empty", genEmpty },
    .{ "Full", genFull },
});

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
    try self.emit("pub fn put(__self: *@This(), item: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer __self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("__self.items.append(__global_allocator, item) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This()) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer __self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("if (__self.items.items.len == 0) return null;\n");
    try self.emitIndent();
    try self.emit("return __self.items.orderedRemove(0);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn put_nowait(__self: *@This(), item: []const u8) void { __self.put(item); }\n");
    try self.emitIndent();
    try self.emit("pub fn get_nowait(__self: *@This()) ?[]const u8 { return __self.get(); }\n");
    try self.emitIndent();
    try self.emit("pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn full(__self: *@This()) bool { return __self.maxsize > 0 and @as(i64, @intCast(__self.items.items.len)) >= __self.maxsize; }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(__self: *@This()) i64 { return @as(i64, @intCast(__self.items.items.len)); }\n");
    try self.emitIndent();
    try self.emit("pub fn task_done(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn join(__self: *@This()) void { }\n");
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
    try self.emit("pub fn put(__self: *@This(), item: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer __self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("__self.items.append(__global_allocator, item) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This()) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.mutex.lock();\n");
    try self.emitIndent();
    try self.emit("defer __self.mutex.unlock();\n");
    try self.emitIndent();
    try self.emit("return __self.items.popOrNull();\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn empty(__self: *@This()) bool { return __self.items.items.len == 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn qsize(__self: *@This()) i64 { return @as(i64, @intCast(__self.items.items.len)); }\n");
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
