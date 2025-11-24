/// Async/await support - async def, await, asyncio
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for asyncio.run(main())
/// Maps to: initialize scheduler once, spawn main, wait for completion
pub fn genAsyncioRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "{\n");

    // Initialize scheduler once (global singleton)
    try self.output.appendSlice(self.allocator, "    if (!runtime.scheduler_initialized) {\n");
    try self.output.appendSlice(self.allocator, "        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
    try self.output.appendSlice(self.allocator, "        runtime.scheduler = try runtime.Scheduler.init(allocator, __num_threads);\n");
    try self.output.appendSlice(self.allocator, "        try runtime.scheduler.start();\n");
    try self.output.appendSlice(self.allocator, "        runtime.scheduler_initialized = true;\n");
    try self.output.appendSlice(self.allocator, "    }\n");

    // Spawn main coroutine
    try self.output.appendSlice(self.allocator, "    const __main_thread = ");
    try self.genExpr(args[0]); // This calls foo_async() which spawns
    try self.output.appendSlice(self.allocator, ";\n");

    // Wait for completion
    try self.output.appendSlice(self.allocator, "    try runtime.scheduler.wait(__main_thread);\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for asyncio.gather(*tasks)
/// Maps to: spawn all, wait for all
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "(blk: {\n");
    try self.output.appendSlice(self.allocator, "    var __threads = std.ArrayList(*runtime.GreenThread).init(allocator);\n");
    try self.output.appendSlice(self.allocator, "    defer __threads.deinit();\n");

    // Spawn all tasks
    for (args) |arg| {
        try self.output.appendSlice(self.allocator, "    try __threads.append(");
        try self.genExpr(arg);
        try self.output.appendSlice(self.allocator, ");\n");
    }

    // Wait for all and collect results
    try self.output.appendSlice(self.allocator, "    var __results = std.ArrayList(runtime.PyValue).init(allocator);\n");
    try self.output.appendSlice(self.allocator, "    for (__threads.items) |__t| {\n");
    try self.output.appendSlice(self.allocator, "        try runtime.scheduler.wait(__t);\n");
    try self.output.appendSlice(self.allocator, "        try __results.append(__t.result orelse runtime.PyValue{.none = {}});\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    break :blk __results.items;\n");
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
/// Maps to: sleep + yield to scheduler
pub fn genAsyncioSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.output.appendSlice(self.allocator, "{\n");
    try self.output.appendSlice(self.allocator, "    const __duration_ns = @as(i64, @intFromFloat(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, " * 1_000_000_000));\n");
    try self.output.appendSlice(self.allocator, "    std.time.sleep(@intCast(__duration_ns));\n");
    try self.output.appendSlice(self.allocator, "    runtime.scheduler.yield();\n");
    try self.output.appendSlice(self.allocator, "}");
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
/// Maps to: wait for green thread and extract result
pub fn genAwait(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.output.appendSlice(self.allocator, "(blk: {\n");
    try self.output.appendSlice(self.allocator, "    const __thread = ");
    try self.genExpr(expr);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    try runtime.scheduler.wait(__thread);\n");

    // Cast result to expected type
    // For now, assume i64 return type (TODO: infer from type system)
    try self.output.appendSlice(self.allocator, "    const __result = __thread.result orelse unreachable;\n");
    try self.output.appendSlice(self.allocator, "    break :blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
    try self.output.appendSlice(self.allocator, "})");
}

/// Check if a function is async (has 'async' keyword in decorator or name)
/// TODO: Implement proper async function detection from AST
pub fn isAsyncFunction(func_def: ast.Node.FunctionDef) bool {
    _ = func_def;
    // For now, assume functions with 'async' in name are async
    // Proper implementation: check AST for 'async def' syntax
    return false;
}
