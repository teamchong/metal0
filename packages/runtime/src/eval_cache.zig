/// Cached eval() with bytecode compilation
/// Comptime target selection: WASM vs Native
const std = @import("std");
const builtin = @import("builtin");
const ast_executor = @import("ast_executor.zig");
const bytecode = @import("bytecode.zig");
const PyObject = @import("runtime.zig").PyObject;

/// Global eval cache - maps source code to compiled bytecode
var eval_cache: ?std.StringHashMap(bytecode.BytecodeProgram) = null;
var cache_mutex: std.Thread.Mutex = .{};

/// Initialize eval cache (call once at startup)
pub fn initCache(allocator: std.mem.Allocator) !void {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (eval_cache == null) {
        eval_cache = std.StringHashMap(bytecode.BytecodeProgram).init(allocator);
    }
}

/// Cached eval() - compiles once, executes many times
pub fn evalCached(allocator: std.mem.Allocator, source: []const u8) !*PyObject {
    // Ensure cache is initialized
    if (eval_cache == null) {
        try initCache(allocator);
    }

    // Check cache first (thread-safe)
    cache_mutex.lock();
    const cached = if (eval_cache.?.get(source)) |program| program else null;
    cache_mutex.unlock();

    if (cached) |program| {
        // Cache hit - execute bytecode
        return executeTarget(allocator, &program);
    }

    // Cache miss - parse and compile
    const ast = try parseSource(source, allocator);
    defer allocator.destroy(ast);

    var compiler = bytecode.Compiler.init(allocator);
    defer compiler.deinit();

    const program = try compiler.compile(ast);

    // Store in cache (thread-safe)
    cache_mutex.lock();
    try eval_cache.?.put(try allocator.dupe(u8, source), program);
    cache_mutex.unlock();

    return executeTarget(allocator, &program);
}

/// Comptime target selection - WASM vs Native
fn executeTarget(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    if (builtin.target.isWasm()) {
        // WASM: Use bytecode VM (no JIT possible)
        return executeWasm(allocator, program);
    } else {
        // Native: Use bytecode VM for now
        // Future: Could JIT to machine code here
        return executeNative(allocator, program);
    }
}

/// WASM bytecode execution
fn executeWasm(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Native bytecode execution (same as WASM for now)
fn executeNative(allocator: std.mem.Allocator, program: *const bytecode.BytecodeProgram) !*PyObject {
    var vm = bytecode.VM.init(allocator);
    defer vm.deinit();
    return vm.execute(program);
}

/// Parse source code to AST (MVP: hardcoded patterns)
fn parseSource(source: []const u8, allocator: std.mem.Allocator) !*ast_executor.Node {
    // For MVP: hardcoded pattern matching
    // Full implementation would use actual lexer/parser

    // Pattern: integer constant "42"
    if (std.mem.eql(u8, source, "42")) {
        const node = try allocator.create(ast_executor.Node);
        node.* = .{ .constant = .{ .value = .{ .int = 42 } } };
        return node;
    }

    // Pattern: "1 + 2"
    if (std.mem.eql(u8, source, "1 + 2")) {
        const left = try allocator.create(ast_executor.Node);
        left.* = .{ .constant = .{ .value = .{ .int = 1 } } };

        const right = try allocator.create(ast_executor.Node);
        right.* = .{ .constant = .{ .value = .{ .int = 2 } } };

        const node = try allocator.create(ast_executor.Node);
        node.* = .{
            .binop = .{
                .left = left,
                .op = .Add,
                .right = right,
            },
        };
        return node;
    }

    // Pattern: "1 + 2 * 3"
    if (std.mem.eql(u8, source, "1 + 2 * 3")) {
        const two = try allocator.create(ast_executor.Node);
        two.* = .{ .constant = .{ .value = .{ .int = 2 } } };

        const three = try allocator.create(ast_executor.Node);
        three.* = .{ .constant = .{ .value = .{ .int = 3 } } };

        const mult = try allocator.create(ast_executor.Node);
        mult.* = .{
            .binop = .{
                .left = two,
                .op = .Mult,
                .right = three,
            },
        };

        const one = try allocator.create(ast_executor.Node);
        one.* = .{ .constant = .{ .value = .{ .int = 1 } } };

        const node = try allocator.create(ast_executor.Node);
        node.* = .{
            .binop = .{
                .left = one,
                .op = .Add,
                .right = mult,
            },
        };
        return node;
    }

    return error.NotImplemented;
}

/// Clear eval cache (for testing)
pub fn clearCache() void {
    cache_mutex.lock();
    defer cache_mutex.unlock();

    if (eval_cache) |*cache| {
        var it = cache.iterator();
        while (it.next()) |entry| {
            var program = entry.value_ptr.*;
            program.deinit();
        }
        cache.clearAndFree();
    }
}
