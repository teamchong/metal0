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
        _ = std.posix.write(std.posix.STDOUT_FILENO, prompt) catch {};
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
    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info == .pointer and args_info.pointer.size == .slice) {
        for (args, 0..) |arg, i| {
            if (i > 0) output.append(allocator, ' ') catch {};
            printValueToList(&output, arg, allocator);
        }
    } else if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
        inline for (args_info.@"struct".fields, 0..) |field, i| {
            if (i > 0) output.append(allocator, ' ') catch {};
            printValueToList(&output, @field(args, field.name), allocator);
        }
    }
    output.append(allocator, '\n') catch {};
    _ = std.posix.write(std.posix.STDOUT_FILENO, output.items) catch {};
}

fn printValueToList(output: *std.ArrayListUnmanaged(u8), value: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (T == []const u8 or T == []u8) {
        output.appendSlice(allocator, value) catch {};
    } else if (T == PyBytes) {
        output.appendSlice(allocator, repr.bytesRepr(allocator, value.data) catch "b''") catch {};
    } else if (info == .int or info == .comptime_int) {
        var buf: [32]u8 = undefined;
        const int_len = std.fmt.formatIntBuf(&buf, value, 10, .lower, .{});
        output.appendSlice(allocator, buf[0..int_len]) catch {};
    } else if (info == .float or info == .comptime_float) {
        if (std.math.isNan(value)) {
            output.appendSlice(allocator, "nan") catch {};
        } else if (std.math.isInf(value)) {
            output.appendSlice(allocator, if (value < 0) "-inf" else "inf") catch {};
        } else {
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            output.appendSlice(allocator, formatted) catch {};
        }
    } else if (info == .bool) {
        output.appendSlice(allocator, if (value) "True" else "False") catch {};
    } else if (T == *PyObject) {
        if (value.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(value.data));
            output.appendSlice(allocator, str_obj.data) catch {};
        } else if (value.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(value.data));
            var buf: [32]u8 = undefined;
            const pyint_len = std.fmt.formatIntBuf(&buf, int_obj.value, 10, .lower, .{});
            output.appendSlice(allocator, buf[0..pyint_len]) catch {};
        } else {
            output.appendSlice(allocator, "<object>") catch {};
        }
    } else {
        var buf: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{value}) catch return;
        output.appendSlice(allocator, formatted) catch {};
    }
}
