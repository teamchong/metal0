/// Async/await support - async def, await, asyncio
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const async_complexity = @import("../../analysis/async_complexity.zig");
const bridge = @import("stdlib_bridge.zig");

/// Generate code for asyncio.run(main())
/// Maps to: initialize scheduler once, spawn main, wait for completion
pub fn genAsyncioRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.emit("{\n");

    // Initialize scheduler once (global singleton)
    try self.emit("    if (!runtime.scheduler_initialized) {\n");
    try self.emit("        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
    try self.emit("        runtime.scheduler = try runtime.Scheduler.init(__global_allocator, __num_threads);\n");
    try self.emit("        try runtime.scheduler.start();\n");
    try self.emit("        runtime.scheduler_initialized = true;\n");
    try self.emit("    }\n");

    // Spawn main coroutine
    try self.emit("    const __main_thread = ");
    try self.genExpr(args[0]); // This calls foo_async() which spawns
    try self.emit(";\n");

    // Wait for completion
    try self.emit("    runtime.scheduler.wait(__main_thread);\n");
    try self.emit("}");
}

/// Generate code for asyncio.gather(*tasks)
/// Maps to: spawn all, wait for all
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("(blk: {\n");
    try self.emit("    var __threads = std.ArrayList(*runtime.GreenThread).init(allocator);\n");
    try self.emit("    defer __threads.deinit();\n");

    // Spawn all tasks
    for (args) |arg| {
        try self.emit("    try __threads.append(");
        try self.genExpr(arg);
        try self.emit(");\n");
    }

    // Wait for all and collect results
    try self.emit("    var __results = std.ArrayList(runtime.PyValue).init(allocator);\n");
    try self.emit("    for (__threads.items) |__t| {\n");
    try self.emit("        runtime.scheduler.wait(__t);\n");
    try self.emit("        try __results.append(__t.result orelse runtime.PyValue{.none = {}});\n");
    try self.emit("    }\n");
    try self.emit("    break :blk __results.items;\n");
    try self.emit("})");
}

/// Generate code for asyncio.create_task(coro)
/// Maps to: runtime.asyncio.createTask(allocator, coro)
pub const genAsyncioCreateTask = bridge.genSimpleCall(.{ .runtime_path = "runtime.asyncio.createTask", .arg_count = 1 });

/// Generate code for asyncio.sleep(seconds)
/// Maps to: sleep + yield to scheduler
pub fn genAsyncioSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    try self.emit("{\n");
    try self.emit("    const __duration_ns = @as(i64, @intFromFloat(");
    try self.genExpr(args[0]);
    try self.emit(" * 1_000_000_000));\n");
    try self.emit("    std.time.sleep(@intCast(__duration_ns));\n");
    try self.emit("    runtime.scheduler.yield();\n");
    try self.emit("}");
}

/// Generate code for asyncio.Queue(maxsize)
/// Maps to: runtime.asyncio.Queue(i64).init(allocator, maxsize)
pub fn genAsyncioQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate Queue instantiation
    // TODO: Infer element type from usage; for now use i64
    try self.emit("try runtime.asyncio.Queue(i64).init(allocator, ");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        // Default maxsize is 0 (unbuffered)
        try self.emit("0");
    }

    try self.emit(")");
}

/// Generate code for await expression
/// Maps to: wait for green thread and extract result
/// Comptime optimizes simple functions by inlining instead of spawning
pub fn genAwait(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    // Check if this is a call to a simple async function that can be inlined
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .name) {
            const func_name = call.func.*.name.id;

            // Look up function definition to analyze complexity
            if (self.lookupAsyncFunction(func_name)) |func_def| {
                const complexity = async_complexity.analyzeFunction(func_def);

                // Inline trivial and simple functions
                if (complexity == .trivial or complexity == .simple) {
                    try self.emit("(blk: {\n");
                    try self.emit("    // Comptime inlined async function\n");
                    try self.emit("    break :blk ");
                    try self.emit(func_name);
                    try self.emit("_impl(");

                    // Generate args
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) {
                            try self.emit(", ");
                        }
                        try self.genExpr(arg);
                    }

                    try self.emit(");\n");
                    try self.emit("})");
                    return;
                }
            }
        }
    }

    // Fall back to full spawn for complex functions or unknown calls
    try self.emit("(blk: {\n");
    try self.emit("    const __thread = ");
    try self.genExpr(expr);
    try self.emit(";\n");
    try self.emit("    runtime.scheduler.wait(__thread);\n");

    // Cast result to expected type
    // For now, assume i64 return type (TODO: infer from type system)
    try self.emit("    const __result = __thread.result orelse unreachable;\n");
    try self.emit("    break :blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
    try self.emit("})");
}

/// Check if a function is async (has 'async' keyword in decorator or name)
/// TODO: Implement proper async function detection from AST
pub fn isAsyncFunction(func_def: ast.Node.FunctionDef) bool {
    _ = func_def;
    // For now, assume functions with 'async' in name are async
    // Proper implementation: check AST for 'async def' syntax
    return false;
}
