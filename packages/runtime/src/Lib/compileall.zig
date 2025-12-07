//! CPython source: Lib/compileall.py
//!
//! Provides utilities to compile Python source files to bytecode.
//!
//! Mirrors: CPython Lib/compileall.py

const std = @import("std");

// ============================================================================
// Compilation Options
// ============================================================================

pub const CompileOptions = struct {
    /// Force recompilation even if timestamps are current
    force: bool = false,
    /// Recursion limit for directories (0 = unlimited)
    maxlevels: usize = 10,
    /// Destination directory for compiled files
    ddir: ?[]const u8 = null,
    /// Strip directory prefix for error messages
    stripdir: ?[]const u8 = null,
    /// Prepend path prefix for error messages
    prependdir: ?[]const u8 = null,
    /// Optimization level (0, 1, or 2)
    optimize: i32 = -1,
    /// Number of workers for parallel compilation
    workers: usize = 1,
    /// Invalidation mode for __pycache__
    invalidation_mode: InvalidationMode = .timestamp,
    /// Whether to write bytecode files
    quiet: u8 = 0, // 0 = verbose, 1 = quiet, 2 = very quiet
    /// Include hidden files/directories
    include_hidden: bool = false,
};

/// Bytecode invalidation mode
pub const InvalidationMode = enum {
    timestamp,
    checked_hash,
    unchecked_hash,
};

// ============================================================================
// Compilation Result
// ============================================================================

pub const CompileResult = struct {
    success: bool,
    files_compiled: usize,
    files_failed: usize,
    errors: std.ArrayList(CompileError),

    pub fn init(allocator: std.mem.Allocator) CompileResult {
        return .{
            .success = true,
            .files_compiled = 0,
            .files_failed = 0,
            .errors = std.ArrayList(CompileError).init(allocator),
        };
    }

    pub fn deinit(self: *CompileResult) void {
        self.errors.deinit();
    }
};

pub const CompileError = struct {
    file: []const u8,
    message: []const u8,
    lineno: ?usize,
};

// ============================================================================
// compile_file - Compile a single Python file
// ============================================================================

/// Compile a single Python source file
pub fn compile_file(
    allocator: std.mem.Allocator,
    fullname: []const u8,
    options: CompileOptions,
) !bool {
    // Check if file exists and is a .py file
    if (!std.mem.endsWith(u8, fullname, ".py")) {
        return false;
    }

    const file = std.fs.openFileAbsolute(fullname, .{}) catch |err| {
        if (options.quiet < 2) {
            std.debug.print("Can't open {s}: {}\n", .{ fullname, err });
        }
        return false;
    };
    defer file.close();

    // Get source file stats
    const stat = file.stat() catch return false;

    // Determine output path
    const cfile = try getCachePath(allocator, fullname, options.optimize);
    defer allocator.free(cfile);

    // Check if recompilation is needed
    if (!options.force) {
        if (checkTimestamp(cfile, stat.mtime)) {
            // Up to date
            return true;
        }
    }

    // Print compilation message
    if (options.quiet == 0) {
        std.debug.print("Compiling {s}...\n", .{fullname});
    }

    // Actual compilation would happen here
    // For now, we just create a placeholder .pyc file
    const cache_dir = std.fs.path.dirname(cfile) orelse return false;

    // Create __pycache__ directory if needed
    std.fs.makeDirAbsolute(cache_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            if (options.quiet < 2) {
                std.debug.print("Can't create {s}: {}\n", .{ cache_dir, err });
            }
            return false;
        }
    };

    // Write placeholder bytecode (in real impl, would compile Python)
    const outfile = std.fs.createFileAbsolute(cfile, .{}) catch |err| {
        if (options.quiet < 2) {
            std.debug.print("Can't write {s}: {}\n", .{ cfile, err });
        }
        return false;
    };
    defer outfile.close();

    // Write magic number and timestamp (simplified)
    const header = [_]u8{
        0x61, 0x0d, 0x0d, 0x0a, // Magic number (Python 3.11)
        0x00, 0x00, 0x00, 0x00, // Flags
        0x00, 0x00, 0x00, 0x00, // Timestamp
        0x00, 0x00, 0x00, 0x00, // Source size
    };
    outfile.writeAll(&header) catch return false;

    return true;
}

/// Get the cache path for a compiled file
fn getCachePath(allocator: std.mem.Allocator, source_path: []const u8, optimize: i32) ![]u8 {
    const dirname = std.fs.path.dirname(source_path) orelse ".";
    const basename = std.fs.path.basename(source_path);

    // Remove .py extension
    const name = if (std.mem.endsWith(u8, basename, ".py"))
        basename[0 .. basename.len - 3]
    else
        basename;

    // Optimization suffix
    const opt_suffix = switch (optimize) {
        1 => ".opt-1",
        2 => ".opt-2",
        else => "",
    };

    // Build __pycache__/<name>.cpython-<version><opt>.pyc
    return std.fmt.allocPrint(
        allocator,
        "{s}/__pycache__/{s}.cpython-311{s}.pyc",
        .{ dirname, name, opt_suffix },
    );
}

/// Check if cached file is up to date
fn checkTimestamp(cache_path: []const u8, source_mtime: i128) bool {
    const file = std.fs.openFileAbsolute(cache_path, .{}) catch return false;
    defer file.close();

    const stat = file.stat() catch return false;
    return stat.mtime >= source_mtime;
}

// ============================================================================
// compile_dir - Compile all files in a directory
// ============================================================================

/// Compile all Python files in a directory
pub fn compile_dir(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    options: CompileOptions,
) !CompileResult {
    var result = CompileResult.init(allocator);

    try compileDirectory(allocator, dir_path, options, &result, 0);

    result.success = result.files_failed == 0;
    return result;
}

fn compileDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    options: CompileOptions,
    result: *CompileResult,
    depth: usize,
) !void {
    // Check recursion limit
    if (options.maxlevels > 0 and depth >= options.maxlevels) {
        return;
    }

    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
        if (options.quiet < 2) {
            std.debug.print("Can't list {s}: {}\n", .{ dir_path, err });
        }
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Skip hidden files unless requested
        if (!options.include_hidden and entry.name[0] == '.') {
            continue;
        }

        // Skip __pycache__ directories
        if (std.mem.eql(u8, entry.name, "__pycache__")) {
            continue;
        }

        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".py")) {
                    const success = compile_file(allocator, full_path, options) catch false;
                    if (success) {
                        result.files_compiled += 1;
                    } else {
                        result.files_failed += 1;
                    }
                }
            },
            .directory => {
                try compileDirectory(allocator, full_path, options, result, depth + 1);
            },
            else => {},
        }
    }
}

// ============================================================================
// compile_path - Compile files along a path
// ============================================================================

/// Compile files in all directories on a path
pub fn compile_path(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
    options: CompileOptions,
) !CompileResult {
    var result = CompileResult.init(allocator);

    for (paths) |path| {
        // Check if path is a file or directory
        const stat = std.fs.cwd().statFile(path) catch continue;

        if (stat.kind == .file) {
            const success = compile_file(allocator, path, options) catch false;
            if (success) {
                result.files_compiled += 1;
            } else {
                result.files_failed += 1;
            }
        } else if (stat.kind == .directory) {
            const dir_result = try compile_dir(allocator, path, options);
            defer @constCast(&dir_result).errors.deinit();
            result.files_compiled += dir_result.files_compiled;
            result.files_failed += dir_result.files_failed;
        }
    }

    result.success = result.files_failed == 0;
    return result;
}

// ============================================================================
// Worker Pool for Parallel Compilation
// ============================================================================

const WorkerPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    workers: []std.Thread,
    queue: std.ArrayList([]const u8),
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    done: bool,
    options: CompileOptions,
    result: *CompileResult,

    pub fn init(
        allocator: std.mem.Allocator,
        num_workers: usize,
        options: CompileOptions,
        result: *CompileResult,
    ) !Self {
        var self = Self{
            .allocator = allocator,
            .workers = try allocator.alloc(std.Thread, num_workers),
            .queue = std.ArrayList([]const u8).init(allocator),
            .mutex = .{},
            .cond = .{},
            .done = false,
            .options = options,
            .result = result,
        };

        // Start worker threads
        for (self.workers) |*worker| {
            worker.* = try std.Thread.spawn(.{}, workerFn, .{&self});
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Signal workers to stop
        self.mutex.lock();
        self.done = true;
        self.cond.broadcast();
        self.mutex.unlock();

        // Wait for workers
        for (self.workers) |worker| {
            worker.join();
        }

        self.allocator.free(self.workers);
        self.queue.deinit();
    }

    pub fn addFile(self: *Self, path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.queue.append(path);
        self.cond.signal();
    }

    fn workerFn(self: *Self) void {
        while (true) {
            self.mutex.lock();

            while (self.queue.items.len == 0 and !self.done) {
                self.cond.wait(&self.mutex);
            }

            if (self.done and self.queue.items.len == 0) {
                self.mutex.unlock();
                return;
            }

            const path = self.queue.pop();
            self.mutex.unlock();

            // Compile the file
            const success = compile_file(self.allocator, path, self.options) catch false;

            self.mutex.lock();
            if (success) {
                self.result.files_compiled += 1;
            } else {
                self.result.files_failed += 1;
            }
            self.mutex.unlock();
        }
    }
};

// ============================================================================
// Module-level convenience function
// ============================================================================

/// Main entry point - compile all Python files in specified locations
pub fn main(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !CompileResult {
    var options = CompileOptions{};
    var paths = std.ArrayList([]const u8).init(allocator);
    defer paths.deinit();

    // Parse command-line arguments (simplified)
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
            options.quiet = 1;
        } else if (std.mem.eql(u8, arg, "-qq")) {
            options.quiet = 2;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursion")) {
            i += 1;
            if (i < args.len) {
                options.maxlevels = std.fmt.parseInt(usize, args[i], 10) catch 10;
            }
        } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--workers")) {
            i += 1;
            if (i < args.len) {
                options.workers = std.fmt.parseInt(usize, args[i], 10) catch 1;
            }
        } else if (arg[0] != '-') {
            try paths.append(arg);
        }
    }

    // Default to current directory if no paths given
    if (paths.items.len == 0) {
        try paths.append(".");
    }

    return compile_path(allocator, paths.items, options);
}

// ============================================================================
// Tests
// ============================================================================

test "CompileOptions defaults" {
    const options = CompileOptions{};
    try std.testing.expect(!options.force);
    try std.testing.expectEqual(@as(usize, 10), options.maxlevels);
    try std.testing.expectEqual(@as(u8, 0), options.quiet);
}

test "CompileResult init" {
    const allocator = std.testing.allocator;
    var result = CompileResult.init(allocator);
    defer result.deinit();

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 0), result.files_compiled);
    try std.testing.expectEqual(@as(usize, 0), result.files_failed);
}

test "getCachePath" {
    const allocator = std.testing.allocator;

    const path1 = try getCachePath(allocator, "/path/to/module.py", -1);
    defer allocator.free(path1);
    try std.testing.expect(std.mem.indexOf(u8, path1, "__pycache__") != null);
    try std.testing.expect(std.mem.endsWith(u8, path1, ".pyc"));

    const path2 = try getCachePath(allocator, "/path/to/module.py", 1);
    defer allocator.free(path2);
    try std.testing.expect(std.mem.indexOf(u8, path2, ".opt-1") != null);
}

test "InvalidationMode enum" {
    const mode = InvalidationMode.timestamp;
    try std.testing.expectEqual(InvalidationMode.timestamp, mode);
}
