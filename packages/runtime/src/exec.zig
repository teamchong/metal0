/// Python exec() - Execute Python code dynamically
///
/// Uses eval_cache for bytecode compilation and execution.
/// Statements are compiled via metal0 subprocess fallback.
///
/// Architecture:
/// 1. Try to parse as expression (simple cases)
/// 2. Fallback to metal0 subprocess for statements/complex code
/// 3. Execute bytecode VM
const std = @import("std");
const eval_cache = @import("eval_cache.zig");
const runtime = @import("runtime.zig");

/// exec() - Execute Python code string (no return value)
///
/// Python signature: exec(source) or exec(source, globals, locals)
///
/// Example:
///   exec("print(42)")  # Prints 42
///   exec("x = 1 + 2")  # Assigns 3 to x
///
/// Implementation:
/// Uses eval_cache's bytecode VM and subprocess compilation.
/// For simple expressions, returns the result (like Python's exec with expr).
/// For statements, executes and returns None.
pub fn exec(
    allocator: std.mem.Allocator,
    source: []const u8,
) anyerror!void {
    // Use eval_cache which handles both expressions and statements
    // via bytecode VM and subprocess fallback
    const result = eval_cache.evalCached(allocator, source) catch |err| {
        // For statements that don't return a value, this is expected
        if (err == error.NotImplemented or err == error.UnexpectedToken) {
            // Try subprocess compilation for full Python syntax
            const program = eval_cache.compileViaSubprocess(allocator, source) catch {
                return error.NotImplemented;
            };
            defer {
                var mutable_program = program;
                mutable_program.deinit();
            }

            // Execute the compiled program
            const bytecode_mod = @import("bytecode.zig");
            var vm = bytecode_mod.VM.init(allocator);
            defer vm.deinit();

            // Execute and ignore result (exec doesn't return)
            _ = vm.execute(&program) catch |exec_err| {
                // NoReturnValue is OK for statements
                if (exec_err == error.NoReturnValue) return;
                return exec_err;
            };
            return;
        }
        return err;
    };

    // exec() doesn't return a value - decref result if any
    runtime.decref(result, allocator);
}

/// exec() with globals and locals (simplified - ignores scope for now)
///
/// Python signature: exec(source, globals, locals)
///
/// Note: Full scope support requires runtime module integration.
/// Currently executes in isolation.
pub fn execWithScope(
    allocator: std.mem.Allocator,
    source: []const u8,
    _globals: ?*runtime.PyObject,
    _locals: ?*runtime.PyObject,
) anyerror!void {
    // TODO: Pass globals/locals to bytecode VM when scope support is added
    _ = _globals;
    _ = _locals;
    return exec(allocator, source);
}
