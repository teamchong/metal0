/// Async/await support - async def, await, asyncio
/// MIGRATED TO ZIGBUILDER
/// Compiles Python asyncio to state machine frames for true non-blocking I/O
///
/// Strategy: Transform async functions into pollable state machines:
///   async def worker(id):        ->  const WorkerFrame = struct { ... };
///       await asyncio.sleep(x)       fn worker_poll(frame) -> ?i64 { ... }
///       return id                    fn worker_async(id) -> *WorkerFrame { ... }
///
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const bridge = @import("stdlib_bridge.zig");
const state_machine = @import("async_state_machine.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


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
        try emitConst(self,"{}");
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
                const label = try self.emitInlineBlockStart("asyncio_run");
                try emitConst(self,"    const __main_frame = try ");
                try emitConst(self,actual_name);
                try emitConst(self,"_async();\n");
                try emitConst(self,"    defer __global_allocator.destroy(__main_frame);\n");
                try emitConst(self,"    while (");
                try emitConst(self,actual_name);
                try emitConst(self,"_poll(__main_frame) == null) {\n");
                try emitConst(self,"        // Yield to allow other work\n");
                try emitConst(self,"        std.Thread.yield() catch {{}};\n");
                try emitConst(self,"    }\n");
                try emitFmtConst(self, "    break :{s};\n", .{label});
                try self.emitInlineBlockEnd();
            } else {
                // Thread-based approach: spawn and wait
                const label = try self.emitInlineBlockStart("asyncio_run");
                try emitConst(self,"    if (!runtime.scheduler_initialized) {\n");
                try emitConst(self,"        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
                try emitConst(self,"        runtime.scheduler = try runtime.Scheduler.init(__global_allocator, __num_threads);\n");
                try emitConst(self,"        try runtime.scheduler.?.start();\n");
                try emitConst(self,"        runtime.scheduler_initialized = true;\n");
                try emitConst(self,"    }\n");
                try emitConst(self,"    const __main_thread = try ");
                try emitConst(self,actual_name);
                try emitConst(self,"_async();\n");
                try emitConst(self,"    runtime.scheduler.?.wait(__main_thread);\n");
                try emitFmtConst(self, "    break :{s};\n", .{label});
                try self.emitInlineBlockEnd();
            }
            return;
        }
    }

    try emitConst(self,"{}");
}

/// Generate code for asyncio.gather(*tasks)
/// When passed a list, spawn all items as goroutines and collect results
pub fn genAsyncioGather(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Use state machine for I/O-bound (high concurrency, single thread)
    // Use thread pool for CPU-bound (parallel execution across cores)
    if (self.anyAsyncHasIO()) { // State machine for I/O operations
        // State machine: poll all frames concurrently using netpoller
        const label = try self.emitInlineBlockStart("gather");
        try emitConst(self,"    var __results: std.ArrayListUnmanaged(i64) = .{{}};\n");

        // Handle starred expression (asyncio.gather(*tasks))
        if (args.len == 1 and args[0] == .starred) {
            const starred = args[0].starred;
            try emitConst(self,"    const __frames = ");
            try self.genExpr(starred.value.*);
            try emitConst(self,";\n");
            // Poll all frames until all are done
            try emitConst(self,"    var __remaining = __frames.items.len;\n");
            try emitConst(self,"    var __done = try __global_allocator.alloc(bool, __frames.items.len);\n");
            try emitConst(self,"    defer __global_allocator.free(__done);\n");
            try emitConst(self,"    @memset(__done, false);\n");
            try emitConst(self,"    try __results.ensureTotalCapacity(__global_allocator, __frames.items.len);\n");
            try emitConst(self,"    for (0..__frames.items.len) |_| try __results.append(__global_allocator, 0);\n");
            try emitConst(self,"    while (__remaining > 0) {\n");
            try emitConst(self,"        runtime.netpoller.poll(1_000_000); // 1ms poll\n");
            try emitConst(self,"        for (__frames.items, 0..) |__frame, __idx| {\n");
            try emitConst(self,"            if (!__done[__idx]) {\n");
            try emitConst(self,"                if (worker_poll(__frame)) |__r| {\n");
            try emitConst(self,"                    __results.items[__idx] = __r;\n");
            try emitConst(self,"                    __done[__idx] = true;\n");
            try emitConst(self,"                    __remaining -= 1;\n");
            try emitConst(self,"                    __global_allocator.destroy(__frame);\n");
            try emitConst(self,"                }\n");
            try emitConst(self,"            }\n");
            try emitConst(self,"        }\n");
            try emitConst(self,"    }\n");
        } else {
            // Direct args - not commonly used with state machines
            try emitConst(self,"    // Direct gather args not yet implemented for state machines\n");
        }
        try emitFmtConst(self, "    break :{s} __results;\n", .{label});
        try self.emitInlineBlockEnd();
    } else {
        // Thread-based approach
        const label = try self.emitInlineBlockStart("gather");
        try emitConst(self,"    var __threads: std.ArrayListUnmanaged(*runtime.GreenThread) = .{{}};\n");
        try emitConst(self,"    defer __threads.deinit(__global_allocator);\n");

        // Handle starred expression (asyncio.gather(*tasks))
        if (args.len == 1 and args[0] == .starred) {
            const starred = args[0].starred;
            try emitConst(self,"    for (");
            try self.genExpr(starred.value.*);
            try emitConst(self,".items) |__item| {\n");
            try emitConst(self,"        try __threads.append(__global_allocator, __item);\n");
            try emitConst(self,"    }\n");
        } else {
            // Direct args: asyncio.gather(task1, task2, ...)
            for (args) |arg| {
                try emitConst(self,"    try __threads.append(__global_allocator, ");
                try self.genExpr(arg);
                try emitConst(self,");\n");
            }
        }

        // Wait for all and collect results
        try emitConst(self,"    var __results: std.ArrayListUnmanaged(i64) = .{{}};\n");
        try emitConst(self,"    for (__threads.items) |__t| {\n");
        try emitConst(self,"        runtime.scheduler.?.wait(__t);\n");
        try emitConst(self,"        if (__t.result) |__r| {\n");
            try emitConst(self,"            try __results.append(__global_allocator, @as(*i64, @ptrCast(@alignCast(__r))).*);\n");
        try emitConst(self,"        }\n");
        try emitConst(self,"    }\n");
        try emitFmtConst(self, "    break :{s} __results;\n", .{label});
        try self.emitInlineBlockEnd();
    }
}

/// Generate code for asyncio.create_task(coro)
/// Maps to: spawn goroutine, return handle
pub fn genAsyncioCreateTask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self,"null");
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
        try emitConst(self,"{}");
        return;
    }

    // Use runtime.sleep which does chunked sleeping with yields
    // Use labeled block expression that returns void to avoid trailing ; issues
    const label = try self.emitInlineBlockStart("sleep");
    try emitConst(self,"    const __sleep_secs: f64 = try @as(anyerror!f64, ");
    try self.genExpr(args[0]);
    try emitConst(self,");\n");
    try emitConst(self,"    runtime.sleep(__sleep_secs);\n");
    try emitFmtConst(self, "    break :{s};\n", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for asyncio.Queue(maxsize)
/// Maps to: runtime.asyncio.Queue backed by channel
pub fn genAsyncioQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try emitConst(self,"try runtime.asyncio.Queue(runtime.PyValue).init(__global_allocator, ");

    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try emitConst(self,"0");
    }

    try emitConst(self,")");
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
                const label = try self.emitInlineBlockStart("await");
                try emitConst(self,"    const __frame = try ");
                try emitConst(self,func_name);
                try emitConst(self,"_async(");
                // Pass arguments
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try self.genExpr(arg);
                }
                try emitConst(self,");\n");
                try emitConst(self,"    defer __global_allocator.destroy(__frame);\n");
                try emitConst(self,"    while (true) {\n");
                try emitConst(self,"        if (");
                try emitConst(self,func_name);
                try emitConst(self,"_poll(__frame)) |__result| {\n");
                try emitFmtConst(self, "            break :{s} __result;\n", .{label});
                try emitConst(self,"        }\n");
                try emitConst(self,"        std.Thread.yield() catch {{}};\n");
                try emitConst(self,"    }\n");
                try self.emitInlineBlockEnd();
            } else {
                // Thread-based approach: spawn and wait
                const label = try self.emitInlineBlockStart("await");
                try emitConst(self,"    const __thread = try ");
                try emitConst(self,func_name);
                try emitConst(self,"_async(");
                // Pass arguments
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try self.genExpr(arg);
                }
                try emitConst(self,");\n");
                try emitConst(self,"    runtime.scheduler.?.wait(__thread);\n");
                try emitFmtConst(self, "    break :{s} if (__thread.result) |__r| @as(*i64, @ptrCast(@alignCast(__r))).* else 0;\n", .{label});
                try self.emitInlineBlockEnd();
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
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_async(");
    // Parameters
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try emitConst(self,arg.arg);
        try emitConst(self,": i64");
    }
    try emitConst(self,") !*runtime.GreenThread {\n");
    try emitConst(self,"    return try runtime.scheduler.?.spawn(");
    try emitConst(self,name);
    try emitConst(self,"_impl, .{");
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try emitConst(self,arg.arg);
    }
    try emitConst(self,"});\n");
    try emitConst(self,"}\n\n");

    // 2. Generate _impl function
    try emitConst(self,"fn ");
    try emitConst(self,name);
    try emitConst(self,"_impl(");
    for (func.params.args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try emitConst(self,arg.arg);
        try emitConst(self,": i64");
    }
    try emitConst(self,") !i64 {\n");
    try emitConst(self,"    const allocator = __global_allocator; _ = allocator;\n");

    // Generate body
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Default return if needed
    try emitConst(self,"    return 0;\n");
    try emitConst(self,"}\n");
}
