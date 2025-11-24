/// Async/await support - async def, await, asyncio
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for asyncio.run(main())
/// Maps to: runtime.asyncio.run(allocator, main_coro)
pub fn genAsyncioRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.asyncio.run(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for asyncio.gather(*tasks)
/// Maps to: runtime.asyncio.gather(tasks)
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate array of tasks
    try self.output.appendSlice(self.allocator, "try runtime.asyncio.gather(&[_]*runtime.asyncio.Task{");

    for (args, 0..) |arg, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }

    try self.output.appendSlice(self.allocator, "})");
}

/// Generate code for asyncio.create_task(coro)
/// Maps to: runtime.asyncio.createTask(allocator, coro)
pub fn genAsyncioCreateTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.asyncio.createTask(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for asyncio.sleep(seconds)
/// Maps to: runtime.asyncio.sleep(seconds)
pub fn genAsyncioSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "try runtime.asyncio.sleep(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for asyncio.Queue(maxsize)
/// Maps to: runtime.asyncio.Queue(i64).init(allocator, maxsize)
pub fn genAsyncioQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate Queue instantiation
    // TODO: Infer element type from usage; for now use i64
    try self.output.appendSlice(self.allocator, "try runtime.asyncio.Queue(i64).init(allocator, ");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        // Default maxsize is 0 (unbuffered)
        try self.output.appendSlice(self.allocator, "0");
    }

    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for await expression
/// Maps to: try await expression
pub fn genAwait(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    // In Zig, async functions return !void or !T
    // We use 'try await' to handle errors
    try self.output.appendSlice(self.allocator, "try await ");
    try self.genExpr(expr);
}

/// Check if a function is async (has 'async' keyword in decorator or name)
/// TODO: Implement proper async function detection from AST
pub fn isAsyncFunction(func_def: ast.Node.FunctionDef) bool {
    _ = func_def;
    // For now, assume functions with 'async' in name are async
    // Proper implementation: check AST for 'async def' syntax
    return false;
}
