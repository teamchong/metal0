/// PyFile - Python file object implementation
/// Wraps std.fs.File with Python-like API: read(), write(), close()
const std = @import("std");
const runtime = @import("runtime.zig");

pub const PyFile = struct {
    handle: std.fs.File,
    mode: []const u8,
    closed: bool,
    allocator: std.mem.Allocator,

    /// Create a new PyFile wrapping a std.fs.File
    pub fn create(allocator: std.mem.Allocator, file: std.fs.File, mode: []const u8) !*runtime.PyObject {
        const obj = try allocator.create(runtime.PyObject);
        const file_data = try allocator.create(PyFile);

        file_data.* = .{
            .handle = file,
            .mode = mode,
            .closed = false,
            .allocator = allocator,
        };

        obj.* = runtime.PyObject{
            .ref_count = 1,
            .type_id = .file,
            .data = file_data,
        };
        return obj;
    }

    /// Read entire file contents as string
    pub fn read(obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
        std.debug.assert(obj.type_id == .file);
        const data: *PyFile = @ptrCast(@alignCast(obj.data));

        if (data.closed) {
            return error.ValueError; // File is closed
        }

        const content = try data.handle.readToEndAlloc(allocator, std.math.maxInt(usize));
        return try runtime.PyString.createOwned(allocator, content);
    }

    /// Read n bytes (or all if n is null)
    pub fn readN(obj: *runtime.PyObject, allocator: std.mem.Allocator, n: ?usize) !*runtime.PyObject {
        std.debug.assert(obj.type_id == .file);
        const data: *PyFile = @ptrCast(@alignCast(obj.data));

        if (data.closed) {
            return error.ValueError;
        }

        if (n) |bytes| {
            const buf = try allocator.alloc(u8, bytes);
            const read_len = try data.handle.read(buf);
            if (read_len < bytes) {
                const result = try allocator.realloc(buf, read_len);
                return try runtime.PyString.createOwned(allocator, result);
            }
            return try runtime.PyString.createOwned(allocator, buf);
        } else {
            const content = try data.handle.readToEndAlloc(allocator, std.math.maxInt(usize));
            return try runtime.PyString.createOwned(allocator, content);
        }
    }

    /// Write string to file
    pub fn write(obj: *runtime.PyObject, content: *runtime.PyObject) !usize {
        std.debug.assert(obj.type_id == .file);
        const data: *PyFile = @ptrCast(@alignCast(obj.data));

        if (data.closed) {
            return error.ValueError;
        }

        const str_data: *runtime.PyString = @ptrCast(@alignCast(content.data));
        return try data.handle.write(str_data.data);
    }

    /// Close the file
    pub fn close(obj: *runtime.PyObject) void {
        std.debug.assert(obj.type_id == .file);
        const data: *PyFile = @ptrCast(@alignCast(obj.data));

        if (!data.closed) {
            data.handle.close();
            data.closed = true;
        }
    }

    /// Destructor - close file and free memory
    pub fn deinit(obj: *runtime.PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(obj.type_id == .file);
        const data: *PyFile = @ptrCast(@alignCast(obj.data));

        if (!data.closed) {
            data.handle.close();
        }
        allocator.destroy(data);
        allocator.destroy(obj);
    }
};
