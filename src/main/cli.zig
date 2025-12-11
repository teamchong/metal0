/// CLI argument parsing and main entry point
/// Drop-in replacement for python3 AND pip3 with compile superpowers
const std = @import("std");
const c_interop = @import("c_interop");

// Import submodules
const common = @import("cli/common.zig");
const pkg_commands = @import("cli/pkg_commands.zig");
const profile_commands = @import("cli/profile_commands.zig");
const server_commands = @import("cli/server_commands.zig");
const build_commands = @import("cli/build_commands.zig");
const test_commands = @import("cli/test_commands.zig");
const python_compat = @import("cli/python_compat.zig");
const daemon = @import("cli/daemon.zig");
const dev_commands = @import("cli/dev_commands.zig");

// Re-export common utilities for external use
pub const Color = common.Color;
pub const printSuccess = common.printSuccess;
pub const printError = common.printError;
pub const printInfo = common.printInfo;
pub const printWarn = common.printWarn;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try c_interop.initGlobalRegistry(allocator);
    defer c_interop.deinitGlobalRegistry(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try python_compat.printUsage();
        return;
    }

    const command = args[1];

    // Python-compatible flags (drop-in replacement for python3)
    if (std.mem.eql(u8, command, "-c")) {
        try python_compat.cmdExecCode(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "-m")) {
        try python_compat.cmdRunModule(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "-")) {
        try python_compat.cmdReadStdin(allocator);
    } else if (std.mem.eql(u8, command, "-V") or std.mem.eql(u8, command, "--version")) {
        python_compat.cmdVersion();
    } else if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help")) {
        try python_compat.printUsage();
    } else if (std.mem.eql(u8, command, "-u")) {
        // Unbuffered output - skip flag, run next arg as file
        if (args.len > 2) {
            try build_commands.cmdRunFile(allocator, args[2..]);
        }
    } else if (std.mem.eql(u8, command, "-O") or std.mem.eql(u8, command, "-OO")) {
        // Optimize - we always optimize, skip flag
        if (args.len > 2) {
            try build_commands.cmdRunFile(allocator, args[2..]);
        }
    }
    // pip-compatible commands
    else if (std.mem.eql(u8, command, "install")) {
        try pkg_commands.cmdInstall(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "uninstall") or std.mem.eql(u8, command, "remove")) {
        try pkg_commands.cmdUninstall(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "freeze")) {
        try pkg_commands.cmdFreeze(allocator);
    } else if (std.mem.eql(u8, command, "list")) {
        try pkg_commands.cmdList(allocator);
    } else if (std.mem.eql(u8, command, "show")) {
        try pkg_commands.cmdShow(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "download")) {
        try pkg_commands.cmdDownload(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "check")) {
        try pkg_commands.cmdCheck(allocator);
    } else if (std.mem.eql(u8, command, "cache")) {
        try pkg_commands.cmdCache(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build")) {
        try build_commands.cmdBuild(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "deploy")) {
        build_commands.cmdDeploy(args[2..]);
    } else if (std.mem.eql(u8, command, "run")) {
        try build_commands.cmdRun(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "test")) {
        try test_commands.cmdTest(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "codegen")) {
        try build_commands.cmdCodegen(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build-fast")) {
        try build_commands.cmdBuildFast(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build-runtime")) {
        try build_commands.cmdBuildRuntime(allocator);
    } else if (std.mem.eql(u8, command, "build-objects")) {
        try build_commands.cmdBuildObjects(allocator);
    } else if (std.mem.eql(u8, command, "setup-runtime")) {
        try build_commands.cmdSetupRuntime(allocator);
    } else if (std.mem.eql(u8, command, "profile")) {
        try profile_commands.cmdProfile(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "server")) {
        try server_commands.cmdServer(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "daemon")) {
        try daemon.cmdDaemon(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "dev")) {
        try dev_commands.cmdDev(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "version")) {
        python_compat.cmdVersion();
    } else if (std.mem.eql(u8, command, "help")) {
        try python_compat.printUsage();
    } else if (std.mem.endsWith(u8, command, ".py") or std.mem.endsWith(u8, command, ".ipynb")) {
        try build_commands.cmdRunFile(allocator, args[1..]);
    } else {
        printError("Unknown command: {s}", .{command});
        std.debug.print("\nRun {s}metal0 --help{s} for usage.\n", .{ Color.bold, Color.reset });
    }
}
