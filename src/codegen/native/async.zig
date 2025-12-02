/// Async/await support - async def, await, asyncio
/// Compiles Python asyncio to state machine frames for true non-blocking I/O
///
/// Strategy: Transform async functions into pollable state machines:
///   async def worker(id):        ->  const WorkerFrame = struct { ... };
///       await asyncio.sleep(x)       fn worker_poll(frame) -> ?i64 { ... }
///       return id                    fn worker_async(id) -> *WorkerFrame { ... }
///
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");
const state_machine = @import("async_state_machine.zig");

// NOTE: Async strategy is now determined per-function via function_traits
// We default to state machine for asyncio module functions (I/O bound)

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "run", genAsyncioRun },
    .{ "gather", genAsyncioGather },
    .{ "create_task", genAsyncioCreateTask },
    .{ "sleep", genAsyncioSleep },
    .{ "Queue", genAsyncioQueue },
});

/// Generate code for asyncio.run(main())
/// Maps to: initialize scheduler, spawn main, wait
pub fn genAsyncioRun(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("{}");
        return;
    }

    // Check if it's a call expression (asyncio.run(main()))
    if (args[0] == .call) {
        const call = args[0].call;
        if (call.func.* == .name) {
            const func_name = call.func.*.name.id;
            // Rename "main" to "__user_main" to match function generation
            const actual_name = if (std.mem.eql(u8, func_name, "main")) "__user_main" else func_name;

            // Use state machine if ANY async function has I/O (for consistency)
            if (self.anyAsyncHasIO()) {
                // State machine approach: create frame and poll until done
                try self.emit("__asyncio_run: {\n");
                try self.emit("    const __main_frame = try ");
                try self.emit(actual_name);
                try self.emit("_async();\n");
                try self.emit("    defer __global_allocator.destroy(__main_frame);\n");
                try self.emit("    while (");
                try self.emit(actual_name);
                try self.emit("_poll(__main_frame) == null) {\n");
                try self.emit("        // Yield to allow other work\n");
                try self.emit("        std.Thread.yield() catch {};\n");
                try self.emit("    }\n");
                try self.emit("    break :__asyncio_run;\n");
                try self.emit("}");
            } else {
                // Thread-based approach: spawn and wait
                try self.emit("__asyncio_run: {\n");
                try self.emit("    if (!runtime.scheduler_initialized) {\n");
                try self.emit("        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
                try self.emit("        runtime.scheduler = try runtime.Scheduler.init(__global_allocator, __num_threads);\n");
                try self.emit("        try runtime.scheduler.start();\n");
                try self.emit("        runtime.scheduler_initialized = true;\n");
                try self.emit("    }\n");
                try self.emit("    const __main_thread = try ");
                try self.emit(actual_name);
                try self.emit("_async();\n");
                try self.emit("    runtime.scheduler.wait(__main_thread);\n");
                try self.emit("    break :__asyncio_run;\n");
                try self.emit("}");
            }
            return;
        }
    }

    try self.emit("{}");
}

/// Generate code for asyncio.gather(*tasks)
/// When passed a list, spawn all items as goroutines and collect results
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Use state machine for I/O-bound (high concurrency, single thread)
    // Use thread pool for CPU-bound (parallel execution across cores)
    if (self.anyAsyncHasIO()) { // State machine for I/O operations
        // State machine: poll all frames concurrently using netpoller
        try self.emit("__gather_blk: {\n");
        try self.emit("    var __results: std.ArrayList(i64) = .{};\n");

        // Handle starred expression (asyncio.gather(*tasks))
        if (args.len == 1 and args[0] == .starred) {
            const starred = args[0].starred;
            try self.emit("    const __frames = ");
            try self.genExpr(starred.value.*);
            try self.emit(";\n");
            // Poll all frames until all are done
            try self.emit("    var __remaining = __frames.items.len;\n");
            try self.emit("    var __done = try __global_allocator.alloc(bool, __frames.items.len);\n");
            try self.emit("    defer __global_allocator.free(__done);\n");
            try self.emit("    @memset(__done, false);\n");
            try self.emit("    try __results.ensureTotalCapacity(__global_allocator, __frames.items.len);\n");
            try self.emit("    for (0..__frames.items.len) |_| try __results.append(__global_allocator, 0);\n");
            try self.emit("    while (__remaining > 0) {\n");
            try self.emit("        runtime.netpoller.poll(1_000_000); // 1ms poll\n");
            try self.emit("        for (__frames.items, 0..) |__frame, __idx| {\n");
            try self.emit("            if (!__done[__idx]) {\n");
            try self.emit("                if (worker_poll(__frame)) |__r| {\n");
            try self.emit("                    __results.items[__idx] = __r;\n");
            try self.emit("                    __done[__idx] = true;\n");
            try self.emit("                    __remaining -= 1;\n");
            try self.emit("                    __global_allocator.destroy(__frame);\n");
            try self.emit("                }\n");
            try self.emit("            }\n");
            try self.emit("        }\n");
            try self.emit("    }\n");
        } else {
            // Direct args - not commonly used with state machines
            try self.emit("    // Direct gather args not yet implemented for state machines\n");
        }
        try self.emit("    break :__gather_blk __results;\n");
        try self.emit("}");
    } else {
        // Thread-based approach
        try self.emit("__gather_blk: {\n");
        try self.emit("    var __threads: std.ArrayList(*runtime.GreenThread) = .{};\n");
        try self.emit("    defer __threads.deinit(__global_allocator);\n");

        // Handle starred expression (asyncio.gather(*tasks))
        if (args.len == 1 and args[0] == .starred) {
            const starred = args[0].starred;
            try self.emit("    for (");
            try self.genExpr(starred.value.*);
            try self.emit(".items) |__item| {\n");
            try self.emit("        try __threads.append(__global_allocator, __item);\n");
            try self.emit("    }\n");
        } else {
            // Direct args: asyncio.gather(task1, task2, ...)
            for (args) |arg| {
                try self.emit("    try __threads.append(__global_allocator, ");
                try self.genExpr(arg);
                try self.emit(");\n");
            }
        }

        // Wait for all and collect results
        try self.emit("    var __results: std.ArrayList(i64) = .{};\n");
        try self.emit("    for (__threads.items) |__t| {\n");
        try self.emit("        runtime.scheduler.wait(__t);\n");
        try self.emit("        if (__t.result) |__r| {\n");
        try self.emit("            try __results.append(__global_allocator, @as(*i64, @ptrCast(@alignCast(__r))).*);\n");
        try self.emit("        }\n");
        try self.emit("    }\n");
        try self.emit("    break :__gather_blk __results;\n");
        try self.emit("}");
    }
}

/// Generate code for asyncio.create_task(coro)
/// Maps to: spawn goroutine, return handle
pub fn genAsyncioCreateTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("null");
        return;
    }

    // The arg should be a coroutine call like worker(i)
    // We need to spawn it and return the thread handle
    try self.genExpr(args[0]);
}

/// Generate code for asyncio.sleep(seconds)
/// Uses runtime.sleep which yields to other goroutines while waiting
pub fn genAsyncioSleep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("{}");
        return;
    }

    // Use runtime.sleep which does chunked sleeping with yields
    // Use labeled block expression that returns void to avoid trailing ; issues
    try self.emit("__sleep_blk: {\n");
    try self.emit("    const __sleep_secs: f64 = try @as(anyerror!f64, ");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emit("    runtime.sleep(__sleep_secs);\n");
    try self.emit("    break :__sleep_blk;\n");
    try self.emit("}");
}

/// Generate code for asyncio.Queue(maxsize)
/// Maps to: runtime.asyncio.Queue backed by channel
pub fn genAsyncioQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("try runtime.asyncio.Queue(runtime.PyValue).init(__global_allocator, ");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("0");
    }

    try self.emit(")");
}

/// Generate code for await expression
/// For now, just execute synchronously (simplified)
pub fn genAwait(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    // For await on a coroutine call like `await worker(i)`:
    // Spawn as goroutine and wait for result
    if (expr == .call) {
        const call = expr.call;

        // Check for asyncio.sleep - emit inline, no thread/wait
        if (call.func.* == .attribute) {
            const attr = call.func.*.attribute;
            if (attr.value.* == .name) {
                const mod_name = attr.value.*.name.id;
                if (std.mem.eql(u8, mod_name, "asyncio") and std.mem.eql(u8, attr.attr, "sleep")) {
                    // Just emit the sleep directly - it's not a spawned task
                    try genAsyncioSleep(self, call.args);
                    return;
                }
            }
        }

        if (call.func.* == .name) {
            const func_name = call.func.*.name.id;

            // Query function_traits for async strategy
            if (self.shouldUseStateMachineAsync(func_name)) {
                // State machine approach: create frame and poll until done
                try self.emit("__await_blk: {\n");
                try self.emit("    const __frame = try ");
                try self.emit(func_name);
                try self.emit("_async(");
                // Pass arguments
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try self.genExpr(arg);
                }
                try self.emit(");\n");
                try self.emit("    defer __global_allocator.destroy(__frame);\n");
                try self.emit("    while (true) {\n");
                try self.emit("        if (");
                try self.emit(func_name);
                try self.emit("_poll(__frame)) |__result| {\n");
                try self.emit("            break :__await_blk __result;\n");
                try self.emit("        }\n");
                try self.emit("        std.Thread.yield() catch {};\n");
                try self.emit("    }\n");
                try self.emit("}");
            } else {
                // Thread-based approach: spawn and wait
                try self.emit("blk: {\n");
                try self.emit("    const __thread = try ");
                try self.emit(func_name);
                try self.emit("_async(");
                // Pass arguments
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try self.genExpr(arg);
                }
                try self.emit(");\n");
                try self.emit("    runtime.scheduler.wait(__thread);\n");
                try self.emit("    break :blk if (__thread.result) |__r| @as(*i64, @ptrCast(@alignCast(__r))).* else 0;\n");
                try self.emit("}");
            }
            return;
        }
    }

    // Fallback: just execute
    try self.genExpr(expr);
}

/// Generate async function definition
/// Converts `async def foo(args):` to two functions:
/// 1. foo_async(args) -> spawns goroutine, returns GreenThread
/// 2. foo_impl(args) -> actual implementation
pub fn genAsyncFunctionDef(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Use function_traits to determine async strategy
    if (self.shouldUseStateMachineAsync(func.name)) {
        return state_machine.genAsyncStateMachine(self, func);
    }

    // Fallback: thread-based approach (blocking)
    const name = func.name;

    // 1. Generate _async spawner function
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_async(");
    // Parameters
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.arg);
        try self.emit(": i64");
    }
    try self.emit(") !*runtime.GreenThread {\n");
    try self.emit("    return try runtime.scheduler.spawn(");
    try self.emit(name);
    try self.emit("_impl, .{");
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.arg);
    }
    try self.emit("});\n");
    try self.emit("}\n\n");

    // 2. Generate _impl function
    try self.emit("fn ");
    try self.emit(name);
    try self.emit("_impl(");
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.arg);
        try self.emit(": i64");
    }
    try self.emit(") !i64 {\n");
    try self.emit("    const allocator = __global_allocator; _ = allocator;\n");

    // Generate body
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Default return if needed
    try self.emit("    return 0;\n");
    try self.emit("}\n");
}
