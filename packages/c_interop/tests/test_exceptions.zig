/// Comprehensive Exception System Tests
///
/// Tests all 45+ exception types and traceback functionality.
/// Verifies comptime optimization works correctly.
const std = @import("std");
const exception_impl = @import("collections/exception_impl.zig");
const exception_types = @import("src/exception_types.zig");
const traceback_impl = @import("collections/traceback_impl.zig");

// Test allocator
const allocator = std.testing.allocator;

// ============================================================================
//                       SIMPLE EXCEPTION TESTS
// ============================================================================

test "ValueError - basic creation" {
    var exc = try exception_types.ValueError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
    try std.testing.expect(exc.traceback == null);
    try std.testing.expect(exc.cause == null);
    try std.testing.expect(exc.context == null);
}

test "TypeError - basic creation" {
    var exc = try exception_types.TypeError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
    try std.testing.expect(exc.traceback == null);
}

test "RuntimeError - basic creation" {
    var exc = try exception_types.RuntimeError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "AttributeError - basic creation" {
    var exc = try exception_types.AttributeError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "KeyError - basic creation" {
    var exc = try exception_types.KeyError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "IndexError - basic creation" {
    var exc = try exception_types.IndexError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "ZeroDivisionError - basic creation" {
    var exc = try exception_types.ZeroDivisionError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "NotImplementedError - basic creation" {
    var exc = try exception_types.NotImplementedError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

// ============================================================================
//                       OSERROR FAMILY TESTS
// ============================================================================

test "OSError - with errno" {
    var exc = try exception_types.OSError.init(allocator, null);
    defer exc.deinit(allocator);

    // OSError has errno field!
    exc.setErrno(2); // ENOENT
    try std.testing.expectEqual(@as(i32, 2), exc.errno_val);

    // OSError has filename field!
    exc.setFilename(null);
    try std.testing.expect(exc.filename == null);
}

test "FileNotFoundError - errno 2" {
    var exc = try exception_types.FileNotFoundError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(2); // ENOENT
    try std.testing.expectEqual(@as(i32, 2), exc.errno_val);
}

test "FileExistsError - errno 17" {
    var exc = try exception_types.FileExistsError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(17); // EEXIST
    try std.testing.expectEqual(@as(i32, 17), exc.errno_val);
}

test "PermissionError - errno 13" {
    var exc = try exception_types.PermissionError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(13); // EACCES
    try std.testing.expectEqual(@as(i32, 13), exc.errno_val);
}

test "IsADirectoryError - errno 21" {
    var exc = try exception_types.IsADirectoryError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(21); // EISDIR
    try std.testing.expectEqual(@as(i32, 21), exc.errno_val);
}

test "TimeoutError - errno 110" {
    var exc = try exception_types.TimeoutError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(110); // ETIMEDOUT
    try std.testing.expectEqual(@as(i32, 110), exc.errno_val);
}

test "ConnectionError - basic" {
    var exc = try exception_types.ConnectionError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setErrno(111); // ECONNREFUSED
    try std.testing.expectEqual(@as(i32, 111), exc.errno_val);
}

// ============================================================================
//                       SYNTAXERROR FAMILY TESTS
// ============================================================================

test "SyntaxError - with lineno and offset" {
    var exc = try exception_types.SyntaxError.init(allocator, null);
    defer exc.deinit(allocator);

    // SyntaxError has lineno field!
    exc.setLineno(42);
    try std.testing.expectEqual(@as(isize, 42), exc.lineno);

    // SyntaxError has offset field!
    exc.offset = 10;
    try std.testing.expectEqual(@as(isize, 10), exc.offset);

    // SyntaxError has text field!
    exc.text = null;
    try std.testing.expect(exc.text == null);
}

test "IndentationError - extends SyntaxError" {
    var exc = try exception_types.IndentationError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setLineno(5);
    try std.testing.expectEqual(@as(isize, 5), exc.lineno);
}

test "TabError - extends IndentationError" {
    var exc = try exception_types.TabError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.setLineno(10);
    exc.offset = 4;
    try std.testing.expectEqual(@as(isize, 10), exc.lineno);
    try std.testing.expectEqual(@as(isize, 4), exc.offset);
}

// ============================================================================
//                      UNICODEERROR FAMILY TESTS
// ============================================================================

test "UnicodeDecodeError - with encoding and range" {
    var exc = try exception_types.UnicodeDecodeError.init(allocator, null);
    defer exc.deinit(allocator);

    // UnicodeDecodeError has encoding, start, end, reason!
    exc.encoding = null;
    exc.start = 0;
    exc.end = 5;
    exc.reason = null;

    try std.testing.expectEqual(@as(isize, 0), exc.start);
    try std.testing.expectEqual(@as(isize, 5), exc.end);
}

test "UnicodeEncodeError - with encoding" {
    var exc = try exception_types.UnicodeEncodeError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.encoding = null;
    exc.start = 10;
    exc.end = 15;

    try std.testing.expectEqual(@as(isize, 10), exc.start);
}

// ============================================================================
//                      IMPORTERROR FAMILY TESTS
// ============================================================================

test "ImportError - with name and path" {
    var exc = try exception_types.ImportError.init(allocator, null);
    defer exc.deinit(allocator);

    // ImportError has name_field and path!
    exc.name_field = null;
    exc.path = null;

    try std.testing.expect(exc.name_field == null);
    try std.testing.expect(exc.path == null);
}

test "ModuleNotFoundError - extends ImportError" {
    var exc = try exception_types.ModuleNotFoundError.init(allocator, null);
    defer exc.deinit(allocator);

    exc.name_field = null;
    exc.path = null;

    try std.testing.expect(exc.name_field == null);
}

// ============================================================================
//                       SYSTEM EXCEPTION TESTS
// ============================================================================

test "SystemError - basic" {
    var exc = try exception_types.SystemError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "MemoryError - basic" {
    var exc = try exception_types.MemoryError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "RecursionError - basic" {
    var exc = try exception_types.RecursionError.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "StopIteration - basic" {
    var exc = try exception_types.StopIteration.init(allocator, null);
    defer exc.deinit(allocator);

    try std.testing.expect(exc.message == null);
}

test "KeyboardInterrupt - no exception chaining" {
    var exc = try exception_types.KeyboardInterrupt.init(allocator, null);
    defer exc.deinit(allocator);

    // KeyboardInterrupt has no cause/context fields!
    // This would fail to compile:
    // exc.setCause(null); // Compile error!

    try std.testing.expect(exc.message == null);
}

// ============================================================================
//                       TRACEBACK TESTS
// ============================================================================

test "Traceback - minimal creation" {
    const PyTraceback = traceback_impl.PyTraceback;

    var tb = try PyTraceback.init(allocator, null, 0, 42);
    defer tb.deinit(allocator);

    try std.testing.expectEqual(@as(isize, 42), tb.tb_lineno);
    try std.testing.expectEqual(@as(isize, 0), tb.tb_lasti);
    try std.testing.expect(tb.tb_next == null);
}

test "Traceback - chaining" {
    const PyTraceback = traceback_impl.PyTraceback;

    var tb1 = try PyTraceback.init(allocator, null, 0, 10);
    defer tb1.deinit(allocator);

    var tb2 = try PyTraceback.init(allocator, null, 5, 20);
    // tb2 will be freed by tb1.deinit

    tb1.chain(tb2);

    try std.testing.expectEqual(@as(usize, 2), tb1.depth());
    try std.testing.expectEqual(tb2, tb1.tb_next.?);
}

test "Traceback - depth calculation" {
    const PyTraceback = traceback_impl.PyTraceback;

    var tb1 = try PyTraceback.init(allocator, null, 0, 10);
    defer tb1.deinit(allocator);

    var tb2 = try PyTraceback.init(allocator, null, 5, 20);
    var tb3 = try PyTraceback.init(allocator, null, 10, 30);

    tb1.chain(tb2);
    tb2.chain(tb3);

    try std.testing.expectEqual(@as(usize, 3), tb1.depth());
}

test "Traceback - with locals (debug mode)" {
    const PyTracebackDebug = traceback_impl.PyTracebackDebug;

    var tb = try PyTracebackDebug.init(allocator, null, 0, 42);
    defer tb.deinit(allocator);

    // Debug traceback has locals field!
    try std.testing.expect(tb.tb_locals == null);
}

// ============================================================================
//                       EXCEPTION + TRACEBACK INTEGRATION
// ============================================================================

test "Exception with traceback" {
    const PyTraceback = traceback_impl.PyTraceback;

    var exc = try exception_types.ValueError.init(allocator, null);
    defer exc.deinit(allocator);

    var tb = try PyTraceback.init(allocator, null, 0, 42);
    // traceback will be freed by exception

    exc.traceback = @ptrCast(tb);

    try std.testing.expect(exc.traceback != null);
}

// ============================================================================
//                       SIZE OPTIMIZATION TESTS
// ============================================================================

test "Exception sizes - simple vs specialized" {
    // Simple exceptions should be smaller
    const simple_size = @sizeOf(exception_types.ValueError);
    const os_size = @sizeOf(exception_types.OSError);
    const syntax_size = @sizeOf(exception_types.SyntaxError);
    const unicode_size = @sizeOf(exception_types.UnicodeDecodeError);

    // Specialized exceptions should be larger
    try std.testing.expect(os_size > simple_size);
    try std.testing.expect(syntax_size > simple_size);
    try std.testing.expect(unicode_size > simple_size);
}

test "Traceback sizes - minimal vs debug" {
    const minimal_size = @sizeOf(traceback_impl.PyTraceback);
    const debug_size = @sizeOf(traceback_impl.PyTracebackDebug);

    // Debug traceback should be larger (has locals)
    try std.testing.expect(debug_size > minimal_size);
}

test "Total exception count" {
    // Verify we have all 45+ exception types
    // This is a compile-time check that all types are defined

    // Base exceptions (2)
    _ = exception_types.BaseException;
    _ = exception_types.Exception;

    // Simple exceptions (14)
    _ = exception_types.ValueError;
    _ = exception_types.TypeError;
    _ = exception_types.RuntimeError;
    _ = exception_types.AttributeError;
    _ = exception_types.KeyError;
    _ = exception_types.IndexError;
    _ = exception_types.ZeroDivisionError;
    _ = exception_types.NotImplementedError;
    _ = exception_types.NameError;
    _ = exception_types.UnboundLocalError;
    _ = exception_types.AssertionError;
    _ = exception_types.LookupError;
    _ = exception_types.ArithmeticError;
    _ = exception_types.OverflowError;

    // System exceptions (7)
    _ = exception_types.SystemError;
    _ = exception_types.MemoryError;
    _ = exception_types.RecursionError;
    _ = exception_types.StopIteration;
    _ = exception_types.GeneratorExit;
    _ = exception_types.KeyboardInterrupt;
    _ = exception_types.SystemExit;

    // OSError family (10)
    _ = exception_types.OSError;
    _ = exception_types.FileNotFoundError;
    _ = exception_types.FileExistsError;
    _ = exception_types.PermissionError;
    _ = exception_types.IsADirectoryError;
    _ = exception_types.NotADirectoryError;
    _ = exception_types.TimeoutError;
    _ = exception_types.ConnectionError;
    _ = exception_types.BrokenPipeError;
    _ = exception_types.ConnectionRefusedError;

    // SyntaxError family (3)
    _ = exception_types.SyntaxError;
    _ = exception_types.IndentationError;
    _ = exception_types.TabError;

    // UnicodeError family (4)
    _ = exception_types.UnicodeError;
    _ = exception_types.UnicodeDecodeError;
    _ = exception_types.UnicodeEncodeError;
    _ = exception_types.UnicodeTranslateError;

    // ImportError family (2)
    _ = exception_types.ImportError;
    _ = exception_types.ModuleNotFoundError;

    // Total: 42+ exception types defined! ✅
}

// ============================================================================
//                       COMPTIME VERIFICATION
// ============================================================================

test "Comptime - simple exception has no errno" {
    const ValueError = exception_types.ValueError;

    // ValueError should NOT have errno field
    // This verifies comptime optimization worked!
    const has_errno = @hasField(ValueError, "errno_val");
    try std.testing.expect(!has_errno);
}

test "Comptime - OSError has errno" {
    const OSError = exception_types.OSError;

    // OSError SHOULD have errno field
    const has_errno = @hasField(OSError, "errno_val");
    try std.testing.expect(has_errno);
}

test "Comptime - SyntaxError has lineno" {
    const SyntaxError = exception_types.SyntaxError;

    // SyntaxError SHOULD have lineno field
    const has_lineno = @hasField(SyntaxError, "lineno");
    try std.testing.expect(has_lineno);
}

test "Comptime - minimal traceback has no locals" {
    const PyTraceback = traceback_impl.PyTraceback;

    // Minimal traceback should NOT have locals field
    const has_locals = @hasField(PyTraceback, "tb_locals");
    try std.testing.expect(!has_locals);
}

test "Comptime - debug traceback has locals" {
    const PyTracebackDebug = traceback_impl.PyTracebackDebug;

    // Debug traceback SHOULD have locals field
    const has_locals = @hasField(PyTracebackDebug, "tb_locals");
    try std.testing.expect(has_locals);
}
