/// PyFile - Python file object implementation (CPython-compatible)
/// Wraps std.fs.File with Python-like API: read(), write(), close()
const std = @import("std");
const runtime = @import("runtime.zig");

/// PyFileObject - CPython-compatible file object
/// Extends PyObject with file-specific data
pub const PyFileObject = extern struct {
    ob_base: runtime.PyObject,
    // File-specific fields stored as opaque pointer to avoid extern struct issues
    file_data: ?*anyopaque,
};

/// Internal file data structure
pub const PyFileData = struct {
    handle: std.fs.File,
    mode: []const u8,
    closed: bool,
    allocator: std.mem.Allocator,
};

pub const PyFile = struct {
    /// Create a new PyFile wrapping a std.fs.File
    pub fn create(allocator: std.mem.Allocator, file: std.fs.File, mode: []const u8) !*runtime.PyObject {
        const file_obj = try allocator.create(PyFileObject);
        const file_data = try allocator.create(PyFileData);

        file_data.* = .{
            .handle = file,
            .mode = mode,
            .closed = false,
            .allocator = allocator,
        };

        file_obj.* = PyFileObject{
            .ob_base = runtime.PyObject{
                .ob_refcnt = 1,
                .ob_type = undefined, // TODO: set proper type object
            },
            .file_data = file_data,
        };
        return @ptrCast(file_obj);
    }

    /// Read entire file contents as string
    pub fn read(obj: *runtime.PyObject, allocator: std.mem.Allocator) !*runtime.PyObject {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return error.ValueError));

        if (data.closed) {
            return error.ValueError; // File is closed
        }

        const content = try data.handle.readToEndAlloc(allocator, std.math.maxInt(usize));
        return try runtime.PyString.createOwned(allocator, content);
    }

    /// Read n bytes (or all if n is null)
    pub fn readN(obj: *runtime.PyObject, allocator: std.mem.Allocator, n: ?usize) !*runtime.PyObject {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return error.ValueError));

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
    pub fn write(obj: *runtime.PyObject, content: []const u8) !usize {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return error.ValueError));

        if (data.closed) {
            return error.ValueError;
        }

        return try data.handle.write(content);
    }

    /// Close the file
    pub fn close(obj: *runtime.PyObject) void {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return));

        if (!data.closed) {
            data.handle.close();
            data.closed = true;
        }
    }

    /// Get the closed status of the file
    pub fn getClosed(obj: *runtime.PyObject) bool {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return true));
        return data.closed;
    }

    /// Destructor - close file and free memory
    pub fn deinit(obj: *runtime.PyObject, allocator: std.mem.Allocator) void {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return));

        if (!data.closed) {
            data.handle.close();
        }
        allocator.destroy(data);
        allocator.destroy(file_obj);
    }

    /// Read all lines from file as ArrayList of strings
    /// Used for Python's `for line in file:` iteration
    pub fn readlines(obj: *runtime.PyObject, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return error.ValueError));

        if (data.closed) {
            return error.ValueError;
        }

        // Read entire file content
        const content = try data.handle.readToEndAlloc(allocator, std.math.maxInt(usize));

        // Split into lines
        var lines = std.ArrayList([]const u8){};
        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            // Include the newline character like Python does (except for last line if no trailing newline)
            const line_with_newline = if (iter.peek() != null)
                try std.fmt.allocPrint(allocator, "{s}\n", .{line})
            else if (line.len > 0)
                try allocator.dupe(u8, line)
            else
                continue; // Skip empty last line
            try lines.append(allocator, line_with_newline);
        }

        return lines;
    }

    /// Iterator for line-by-line file reading (lazy iteration)
    pub const LineIterator = struct {
        reader: std.fs.File.Reader,
        allocator: std.mem.Allocator,
        done: bool = false,

        pub fn next(self: *LineIterator) !?[]const u8 {
            if (self.done) return null;

            var line_buffer = std.ArrayList(u8){};
            self.reader.streamUntilDelimiter(line_buffer.writer(self.allocator), '\n', null) catch |err| {
                if (err == error.EndOfStream) {
                    self.done = true;
                    if (line_buffer.items.len > 0) {
                        return line_buffer.items;
                    }
                    return null;
                }
                return err;
            };
            // Add the newline back (Python includes it)
            try line_buffer.append(self.allocator, '\n');
            return line_buffer.items;
        }
    };

    /// Get a line iterator for the file
    pub fn lineIterator(obj: *runtime.PyObject, allocator: std.mem.Allocator) !LineIterator {
        const file_obj: *PyFileObject = @ptrCast(@alignCast(obj));
        const data: *PyFileData = @ptrCast(@alignCast(file_obj.file_data orelse return error.ValueError));

        if (data.closed) {
            return error.ValueError;
        }

        return LineIterator{
            .reader = data.handle.reader(),
            .allocator = allocator,
        };
    }
};
