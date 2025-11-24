/// CLI argument parsing and main entry point
const std = @import("std");
const c_interop = @import("c_interop");
const CompileOptions = @import("../main.zig").CompileOptions;
const utils = @import("utils.zig");
const compile = @import("compile.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize C library mapping registry
    try c_interop.initGlobalRegistry(allocator);
    defer c_interop.deinitGlobalRegistry(allocator);

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try utils.printUsage();
        return;
    }

    var opts = CompileOptions{
        .input_file = undefined,
        .mode = "run",
    };

    var i: usize = 1;
    var is_build_command = false;

    // Parse command (build/test or direct file)
    if (std.mem.eql(u8, args[1], "build")) {
        is_build_command = true;
        opts.mode = "build";
        i = 2;
    } else if (std.mem.eql(u8, args[1], "test")) {
        // Run pytest for now (bridge to Python)
        std.debug.print("Running tests (bridge to Python)...\n", .{});
        _ = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "pytest", "-v" },
        });
        return;
    }

    // Parse flags and input file
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--binary") or std.mem.eql(u8, arg, "-b")) {
            opts.binary = true;
        } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            opts.force = true;
        } else if (std.mem.eql(u8, arg, "--emit-bytecode")) {
            opts.emit_bytecode = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("Unknown flag: {s}\n", .{arg});
            try utils.printUsage();
            return;
        } else {
            // First non-flag is input file, second is output file
            if (input_file == null) {
                input_file = arg;
            } else if (output_file == null) {
                output_file = arg;
            } else {
                std.debug.print("Too many arguments\n", .{});
                try utils.printUsage();
                return;
            }
        }
    }

    // If no input file and in build mode, build all .py in current directory
    if (input_file == null and is_build_command) {
        try utils.buildDirectory(allocator, ".", opts);
        return;
    }

    if (input_file == null) {
        std.debug.print("Error: Missing input file\n", .{});
        try utils.printUsage();
        return;
    }

    // Check if input is a directory
    const stat = std.fs.cwd().statFile(input_file.?) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: File not found: {s}\n", .{input_file.?});
            return;
        }
        return err;
    };

    if (stat.kind == .directory) {
        try utils.buildDirectory(allocator, input_file.?, opts);
        return;
    }

    opts.input_file = input_file.?;
    opts.output_file = output_file;

    try compile.compileFile(allocator, opts);
}
