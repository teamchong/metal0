/// I/O builtins (print, input, breakpoint)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const pyint = @import("../../Objects/intobject.zig");
const pystring = @import("../../Objects/unicodeobject.zig");
const repr = @import("repr.zig");

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
    } else if (info == .pointer and info.pointer.size == .one) {
        // Handle string literals (*const [N:0]u8) and other pointers-to-arrays
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            output.appendSlice(allocator, value) catch unreachable;
            return;
        }
        // For other pointers, use {any} formatting
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
        return;
    } else if (T == PyBytes) {
        output.appendSlice(allocator, repr.bytesRepr(allocator, value.data) catch "b''") catch unreachable;
    } else if (info == .int or info == .comptime_int) {
        var buf: [32]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    } else if (info == .float or info == .comptime_float) {
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
    } else if (T == *PyObject) {
        if (value.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(value.data));
            output.appendSlice(allocator, str_obj.data) catch unreachable;
        } else if (value.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(value.data));
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{int_obj.value}) catch return;
            output.appendSlice(allocator, formatted) catch unreachable;
        } else {
            output.appendSlice(allocator, "<object>") catch unreachable;
        }
    } else {
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch unreachable;
    }
}
