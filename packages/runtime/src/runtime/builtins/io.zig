/// I/O builtins (print, input, breakpoint)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const cpython = @import("../../cpython.zig");
const pyint = @import("../../Objects/intobject.zig");
const pystring = @import("../../Objects/unicodeobject.zig");
const repr = @import("repr.zig");
const PyValue = @import("../../Objects/object.zig").PyValue;
const type_predicates = @import("../type_predicates.zig");

const PyObject = runtime_core.PyObject;
const PyInt = pyint.PyInt;
const PyString = pystring.PyString;
const PyBytes = repr.PyBytes;

/// input([prompt]) - read line from stdin
pub fn input(allocator: std.mem.Allocator, prompt: []const u8) []const u8 {
    if (prompt.len > 0) {
        _ = std.posix.write(std.posix.STDOUT_FILENO, prompt) catch unreachable;
    }

    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    var stdin_buf: [4096]u8 = undefined;
    const stdin = stdin_file.reader(&stdin_buf);
    const line = stdin.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |err| {
        if (err == error.EndOfStream) {
            return "";
        }
        return "";
    };

    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

/// breakpoint() - drop into debugger
pub fn breakpoint() void {
    if (@import("builtin").mode == .Debug) {
        @breakpoint();
    }
}

/// print(*args) - print values to stdout
pub fn print(allocator: std.mem.Allocator, args: anytype) void {
    printWithOptions(allocator, args, " ", "\n", null);
}

/// print(*args, sep=" ", end="\n", file=None) - print values to file/stdout
/// sep: separator between values (default: " ")
/// end: string appended after last value (default: "\n")
/// file: file handle (null = stdout)
pub fn printWithOptions(
    allocator: std.mem.Allocator,
    args: anytype,
    sep: []const u8,
    end: []const u8,
    file: ?std.fs.File,
) void {
    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info == .pointer and args_info.pointer.size == .slice) {
        // Slice of values
        for (args, 0..) |arg, i| {
            if (i > 0) output.appendSlice(allocator, sep) catch unreachable;
            printValueToList(&output, arg, allocator);
        }
    } else if (args_info == .pointer and args_info.pointer.size == .one) {
        // Pointer to tuple (codegen produces &.{...})
        const child_info = @typeInfo(args_info.pointer.child);
        if (child_info == .@"struct" and child_info.@"struct".is_tuple) {
            inline for (child_info.@"struct".fields, 0..) |field, i| {
                if (i > 0) output.appendSlice(allocator, sep) catch unreachable;
                printValueToList(&output, @field(args.*, field.name), allocator);
            }
        }
    } else if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
        // Direct tuple
        inline for (args_info.@"struct".fields, 0..) |field, i| {
            if (i > 0) output.appendSlice(allocator, sep) catch unreachable;
            printValueToList(&output, @field(args, field.name), allocator);
        }
    }
    output.appendSlice(allocator, end) catch unreachable;

    // Write to file or stdout
    const handle = if (file) |f| f.handle else std.posix.STDOUT_FILENO;
    _ = std.posix.write(handle, output.items) catch unreachable;
}

fn printValueToList(output: *std.ArrayListUnmanaged(u8), value: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle PyValue tagged union (from c_interop, eval, etc.)
    if (T == PyValue) {
        switch (value) {
            .int => |i| {
                var buf: [32]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return;
                output.appendSlice(allocator, formatted) catch unreachable;
            },
            .float => |f| {
                if (std.math.isNan(f)) {
                    output.appendSlice(allocator, "nan") catch unreachable;
                } else if (std.math.isInf(f)) {
                    output.appendSlice(allocator, if (f < 0) "-inf" else "inf") catch unreachable;
                } else {
                    var buf: [64]u8 = undefined;
                    const formatted = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return;
                    output.appendSlice(allocator, formatted) catch unreachable;
                }
            },
            .string => |s| output.appendSlice(allocator, s) catch unreachable,
            .bool => |b| output.appendSlice(allocator, if (b) "True" else "False") catch unreachable,
            .none => output.appendSlice(allocator, "None") catch unreachable,
            .bytes => |b| output.appendSlice(allocator, repr.bytesRepr(allocator, b.data) catch "b''") catch unreachable,
            .ptr => {
                var buf: [64]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "<object at {*}>", .{value.ptr}) catch return;
                output.appendSlice(allocator, formatted) catch unreachable;
            },
            else => {
                var buf: [256]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
                output.appendSlice(allocator, formatted) catch unreachable;
            },
        }
        return;
    }

    // Handle null (Python's None) - check optional types
    if (info == .optional or info == .null) {
        if (info == .null or value == null) {
            output.appendSlice(allocator, "None") catch unreachable;
            return;
        }
        // Unwrap optional and recurse
        printValueToList(output, value.?, allocator);
        return;
    }

    if (T == []const u8 or T == []u8) {
        output.appendSlice(allocator, value) catch unreachable;
    } else if (T == PyBytes) {
        output.appendSlice(allocator, repr.bytesRepr(allocator, value.data) catch "b''") catch unreachable;
    } else if (type_predicates.isIntInfo(info)) {
        var buf: [32]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    } else if (type_predicates.isFloatInfo(info)) {
        if (std.math.isNan(value)) {
            output.appendSlice(allocator, "nan") catch unreachable;
        } else if (std.math.isInf(value)) {
            output.appendSlice(allocator, if (value < 0) "-inf" else "inf") catch unreachable;
        } else {
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            output.appendSlice(allocator, formatted) catch unreachable;
        }
    } else if (info == .bool) {
        output.appendSlice(allocator, if (value) "True" else "False") catch unreachable;
    } else if (info == .pointer and info.pointer.size == .one) {
        // Check if this is a pointer to a struct with ob_refcnt and ob_type fields (CPython PyObject)
        const ChildT = info.pointer.child;
        const child_info = @typeInfo(ChildT);
        const is_pyobject = child_info == .@"struct" and
            @hasField(ChildT, "ob_refcnt") and
            @hasField(ChildT, "ob_type");

        if (is_pyobject) {
            // This is a *PyObject - use cpython type check functions
            const obj: *cpython.PyObject = @ptrCast(@alignCast(value));

            if (cpython.PyFloat_Check(obj)) {
                const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(obj));
                const fval = float_obj.ob_fval;
                if (std.math.isNan(fval)) {
                    output.appendSlice(allocator, "nan") catch unreachable;
                } else if (std.math.isInf(fval)) {
                    output.appendSlice(allocator, if (fval < 0) "-inf" else "inf") catch unreachable;
                } else {
                    var buf: [64]u8 = undefined;
                    const formatted = std.fmt.bufPrint(&buf, "{d}", .{fval}) catch return;
                    output.appendSlice(allocator, formatted) catch unreachable;
                }
            } else if (cpython.PyLong_Check(obj)) {
                const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(obj));
                var buf: [32]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "{d}", .{int_obj.getValue()}) catch return;
                output.appendSlice(allocator, formatted) catch unreachable;
            } else if (cpython.PyUnicode_Check(obj)) {
                const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(obj));
                const len: usize = @intCast(str_obj.length);
                output.appendSlice(allocator, str_obj.data[0..len]) catch unreachable;
            } else if (cpython.PyBool_Check(obj)) {
                const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(obj));
                output.appendSlice(allocator, if (bool_obj.getValue()) "True" else "False") catch unreachable;
            } else {
                output.appendSlice(allocator, "<unknown pyobject type>") catch unreachable;
            }
            return;
        }

        // Not a PyObject pointer - handle string literals and other pointers-to-arrays
        const child_is_array = child_info == .array and child_info.array.child == u8;
        if (child_is_array) {
            output.appendSlice(allocator, value) catch unreachable;
            return;
        }

        // For other pointers, use {any} formatting
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    } else if (info == .pointer and info.pointer.size == .slice) {
        // Already handled by T == []const u8 check above, but include for completeness
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    } else {
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    }
}
