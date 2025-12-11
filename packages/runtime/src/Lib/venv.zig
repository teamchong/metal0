//! Python 'venv' module - Virtual environment creation
//!
//! Provides support for creating lightweight virtual environments.
//!
//! Mirrors: CPython Lib/venv/

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Error Types
// ============================================================================

pub const VenvError = error{
    PermissionDenied,
    DirectoryExists,
    PythonNotFound,
    IoError,
    OutOfMemory,
};

// ============================================================================
// EnvBuilder
// ============================================================================

/// Virtual environment builder
pub const EnvBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Install pip into the environment
    with_pip: bool = false,
    /// Don't install pip
    without_pip: bool = false,
    /// Create symlinks instead of copies
    symlinks: bool = false,
    /// Upgrade core dependencies
    upgrade: bool = false,
    /// Give access to system site-packages
    system_site_packages: bool = false,
    /// Clear existing environment
    clear: bool = false,
    /// Upgrade pip and setuptools
    upgrade_deps: bool = false,
    /// Custom prompt
    prompt: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .symlinks = switch (builtin.os.tag) {
                .windows => false,
                else => true,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Create a virtual environment
    pub fn create(self: *Self, env_dir: []const u8) !void {
        // Create directory structure
        try self.ensureDirectories(env_dir);

        // Create configuration file
        try self.createConfiguration(env_dir);

        // Create scripts/activation files
        try self.setupScripts(env_dir);

        // Install pip if requested
        if (self.with_pip and !self.without_pip) {
            try self.setupPip(env_dir);
        }
    }

    fn ensureDirectories(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;

        // Clear existing if requested
        if (self.clear) {
            std.fs.cwd().deleteTree(env_dir) catch {};
        }

        // Create main directory
        std.fs.cwd().makeDir(env_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {
                if (!self.clear and !self.upgrade) {
                    return error.DirectoryExists;
                }
            },
            else => return error.IoError,
        };

        // Create subdirectories
        const subdirs = switch (builtin.os.tag) {
            .windows => &[_][]const u8{ "Scripts", "Lib", "Lib\\site-packages", "Include" },
            else => &[_][]const u8{ "bin", "lib", "lib/python3.12", "lib/python3.12/site-packages", "include" },
        };

        for (subdirs) |subdir| {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ env_dir, subdir });
            defer allocator.free(path);
            std.fs.cwd().makePath(path) catch {};
        }
    }

    fn createConfiguration(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;

        const config_path = try std.fmt.allocPrint(allocator, "{s}/pyvenv.cfg", .{env_dir});
        defer allocator.free(config_path);

        const file = try std.fs.cwd().createFile(config_path, .{});
        defer file.close();

        const writer = file.writer();

        // Get Python executable path
        const home = std.posix.getenv("PYTHONHOME") orelse "/usr";

        try writer.print("home = {s}\n", .{home});
        try writer.print("include-system-site-packages = {s}\n", .{
            if (self.system_site_packages) "true" else "false",
        });
        try writer.print("version = 3.12.0\n", .{});

        if (self.prompt) |prompt| {
            try writer.print("prompt = {s}\n", .{prompt});
        }
    }

    fn setupScripts(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;

        switch (builtin.os.tag) {
            .windows => {
                try self.createActivateBat(env_dir);
                try self.createActivatePs1(env_dir);
            },
            else => {
                try self.createActivateSh(env_dir);
                try self.createActivateFish(env_dir);
                try self.createActivateCsh(env_dir);
            },
        }

        // Create python symlink/copy
        const python_src = std.posix.getenv("PYTHONEXECUTABLE") orelse "/usr/bin/python3";
        const python_dst = switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(allocator, "{s}/Scripts/python.exe", .{env_dir}),
            else => try std.fmt.allocPrint(allocator, "{s}/bin/python", .{env_dir}),
        };
        defer allocator.free(python_dst);

        if (self.symlinks) {
            std.posix.symlink(python_src, python_dst) catch {};
        } else {
            std.fs.cwd().copyFile(python_src, std.fs.cwd(), python_dst, .{}) catch {};
        }
    }

    fn createActivateSh(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;
        const path = try std.fmt.allocPrint(allocator, "{s}/bin/activate", .{env_dir});
        defer allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const prompt = self.prompt orelse std.fs.path.basename(env_dir);

        try file.writeAll(
            \\# This file must be used with "source bin/activate" *from bash*
            \\# you cannot run it directly
            \\
            \\deactivate () {
            \\    if [ -n "${_OLD_VIRTUAL_PATH:-}" ] ; then
            \\        PATH="${_OLD_VIRTUAL_PATH:-}"
            \\        export PATH
            \\        unset _OLD_VIRTUAL_PATH
            \\    fi
            \\    if [ -n "${_OLD_VIRTUAL_PS1:-}" ] ; then
            \\        PS1="${_OLD_VIRTUAL_PS1:-}"
            \\        export PS1
            \\        unset _OLD_VIRTUAL_PS1
            \\    fi
            \\    unset VIRTUAL_ENV
            \\    unset VIRTUAL_ENV_PROMPT
            \\    if [ ! "${1:-}" = "nondestructive" ] ; then
            \\        unset -f deactivate
            \\    fi
            \\}
            \\
            \\deactivate nondestructive
            \\
            \\
        );
        try file.writer().print("VIRTUAL_ENV=\"{s}\"\nexport VIRTUAL_ENV\n\n", .{env_dir});
        try file.writer().print("VIRTUAL_ENV_PROMPT=\"{s}\"\nexport VIRTUAL_ENV_PROMPT\n\n", .{prompt});
        try file.writeAll(
            \\_OLD_VIRTUAL_PATH="$PATH"
            \\PATH="$VIRTUAL_ENV/bin:$PATH"
            \\export PATH
            \\
            \\_OLD_VIRTUAL_PS1="${PS1:-}"
            \\PS1="(${VIRTUAL_ENV_PROMPT}) ${PS1:-}"
            \\export PS1
            \\
        );
    }

    fn createActivateFish(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;
        const path = try std.fmt.allocPrint(allocator, "{s}/bin/activate.fish", .{env_dir});
        defer allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const prompt = self.prompt orelse std.fs.path.basename(env_dir);

        try file.writeAll("# Fish shell activation script\n\n");
        try file.writer().print("set -gx VIRTUAL_ENV \"{s}\"\n", .{env_dir});
        try file.writer().print("set -gx VIRTUAL_ENV_PROMPT \"{s}\"\n\n", .{prompt});
        try file.writeAll("set -gx _OLD_VIRTUAL_PATH $PATH\nset -gx PATH $VIRTUAL_ENV/bin $PATH\n");
    }

    fn createActivateCsh(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;
        const path = try std.fmt.allocPrint(allocator, "{s}/bin/activate.csh", .{env_dir});
        defer allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writer().print("setenv VIRTUAL_ENV \"{s}\"\n", .{env_dir});
        try file.writeAll("set _OLD_VIRTUAL_PATH=\"$PATH\"\nsetenv PATH \"$VIRTUAL_ENV/bin:$PATH\"\n");
    }

    fn createActivateBat(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;
        const path = try std.fmt.allocPrint(allocator, "{s}/Scripts/activate.bat", .{env_dir});
        defer allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const prompt = self.prompt orelse std.fs.path.basename(env_dir);

        try file.writeAll("@echo off\r\n\r\n");
        try file.writer().print("set \"VIRTUAL_ENV={s}\"\r\n", .{env_dir});
        try file.writer().print("set \"VIRTUAL_ENV_PROMPT={s}\"\r\n\r\n", .{prompt});
        try file.writeAll("set \"_OLD_VIRTUAL_PATH=%PATH%\"\r\nset \"PATH=%VIRTUAL_ENV%\\Scripts;%PATH%\"\r\n");
    }

    fn createActivatePs1(self: *Self, env_dir: []const u8) !void {
        const allocator = self.allocator;
        const path = try std.fmt.allocPrint(allocator, "{s}/Scripts/Activate.ps1", .{env_dir});
        defer allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writer().print("$env:VIRTUAL_ENV = \"{s}\"\n", .{env_dir});
        try file.writeAll("$env:_OLD_VIRTUAL_PATH = $env:PATH\n$env:PATH = \"$env:VIRTUAL_ENV\\Scripts;$env:PATH\"\n");
    }

    fn setupPip(self: *Self, env_dir: []const u8) !void {
        // Use ensurepip to install pip in the virtual environment
        const ensurepip = @import("ensurepip.zig");

        // Set VIRTUAL_ENV so ensurepip knows where to install
        // Note: In real implementation, would set env var and run ensurepip.bootstrap
        _ = env_dir;

        // Bootstrap pip installation
        ensurepip.bootstrap(self.allocator, .{
            .root = null,
            .upgrade = false,
            .user = false,
            .altinstall = false,
            .default_pip = true,
            .verbosity = 0,
        }) catch |err| {
            // Log error but don't fail venv creation
            const stderr = std.io.getStdErr().writer();
            stderr.print("Warning: pip installation failed: {}\n", .{err}) catch {};
        };
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Create a virtual environment
pub fn create(allocator: std.mem.Allocator, env_dir: []const u8, options: struct {
    system_site_packages: bool = false,
    clear: bool = false,
    symlinks: bool = true,
    with_pip: bool = false,
    prompt: ?[]const u8 = null,
}) !void {
    var builder = EnvBuilder.init(allocator);
    defer builder.deinit();

    builder.system_site_packages = options.system_site_packages;
    builder.clear = options.clear;
    builder.symlinks = options.symlinks;
    builder.with_pip = options.with_pip;
    builder.prompt = options.prompt;

    try builder.create(env_dir);
}

/// Main entry point for command-line usage
pub fn main(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len < 1) {
        std.debug.print("Usage: venv [OPTIONS] ENV_DIR\n", .{});
        std.debug.print("\nOptions:\n", .{});
        std.debug.print("  --system-site-packages  Give access to system site-packages\n", .{});
        std.debug.print("  --symlinks              Use symlinks instead of copies\n", .{});
        std.debug.print("  --copies                Use copies instead of symlinks\n", .{});
        std.debug.print("  --clear                 Clear existing environment\n", .{});
        std.debug.print("  --upgrade               Upgrade environment\n", .{});
        std.debug.print("  --without-pip           Skip pip installation\n", .{});
        std.debug.print("  --prompt PROMPT         Custom prompt for environment\n", .{});
        return 2;
    }

    var builder = EnvBuilder.init(allocator);
    defer builder.deinit();

    var env_dir: ?[]const u8 = null;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--system-site-packages")) {
            builder.system_site_packages = true;
        } else if (std.mem.eql(u8, arg, "--symlinks")) {
            builder.symlinks = true;
        } else if (std.mem.eql(u8, arg, "--copies")) {
            builder.symlinks = false;
        } else if (std.mem.eql(u8, arg, "--clear")) {
            builder.clear = true;
        } else if (std.mem.eql(u8, arg, "--upgrade")) {
            builder.upgrade = true;
        } else if (std.mem.eql(u8, arg, "--without-pip")) {
            builder.without_pip = true;
        } else if (std.mem.eql(u8, arg, "--prompt")) {
            i += 1;
            if (i < args.len) {
                builder.prompt = args[i];
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            env_dir = arg;
        }
    }

    if (env_dir) |dir| {
        builder.create(dir) catch |err| {
            std.debug.print("Error creating venv: {}\n", .{err});
            return 1;
        };
        return 0;
    }

    std.debug.print("Error: ENV_DIR is required\n", .{});
    return 1;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "EnvBuilder init" {
    const allocator = std.testing.allocator;
    var builder = EnvBuilder.init(allocator);
    defer builder.deinit();

    try std.testing.expect(!builder.with_pip);
    try std.testing.expect(!builder.system_site_packages);
}

test "EnvBuilder symlinks default" {
    const allocator = std.testing.allocator;
    var builder = EnvBuilder.init(allocator);
    defer builder.deinit();

    // On Unix, symlinks should be true by default
    switch (builtin.os.tag) {
        .windows => try std.testing.expect(!builder.symlinks),
        else => try std.testing.expect(builder.symlinks),
    }
}
