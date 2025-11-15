/// Async/await support - async def, await, asyncio
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for asyncio.run(main())
/// Maps to: runtime.async_runtime.run(allocator, main)
pub fn genAsyncioRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Use runtime const (already imported in header)
    try self.output.appendSlice(self.allocator, "runtime.async_runtime.run(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for asyncio.gather(*tasks)
/// Maps to: runtime.async_runtime.gather(allocator, tasks)
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate array of tasks
    try self.output.appendSlice(self.allocator, "runtime.async_runtime.gather(allocator, &[_]runtime.async_runtime.Task{");

    for (args, 0..) |arg, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }

    try self.output.appendSlice(self.allocator, "})");
}

/// Generate code for asyncio.create_task(coro)
/// Maps to: runtime.async_runtime.spawn(allocator, coro)
pub fn genAsyncioCreateTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "runtime.async_runtime.spawn(allocator, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for asyncio.sleep(seconds)
/// Maps to: runtime.async_runtime.sleepAsync(seconds)
pub fn genAsyncioSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "runtime.async_runtime.sleepAsync(");
    try self.genExpr(args[0]);
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
