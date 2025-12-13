/// Python-compatible commands (drop-in replacement for python3)
/// Commands: -c, -m, -, -V/--version, -h/--help
const std = @import("std");
const pkg = @import("pkg");
const CompileOptions = @import("../../main.zig").CompileOptions;
const compile_mod = @import("../compile.zig");
const Color = @import("common.zig").Color;
const printError = @import("common.zig").printError;
const pkg_commands = @import("pkg_commands.zig");

pub fn cmdExecCode(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No code to execute", .{});
        std.debug.print("\nUsage: metal0 -c \"print('hello')\"\n", .{});
        return;
    }

    const code = args[0];

    // Write code to temp file
    const tmp_path = "/tmp/metal0_exec.py";
    const file = try std.fs.cwd().createFile(tmp_path, .{});
    defer file.close();
    try file.writeAll(code);

    // Compile and run
    const opts = CompileOptions{ .input_file = tmp_path, .mode = "run", .force = true };
    try compile_mod.compileFile(allocator, opts);
}

pub fn cmdRunModule(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No module specified", .{});
        std.debug.print("\nUsage: metal0 -m module_name\n", .{});
        return;
    }

    const module_name = args[0];

    // Common Python modules we can handle
    if (std.mem.eql(u8, module_name, "pip")) {
        // Redirect to our pip-compatible install
        if (args.len > 1) {
            if (std.mem.eql(u8, args[1], "install")) {
                try pkg_commands.cmdInstall(allocator, args[2..]);
                return;
            } else if (std.mem.eql(u8, args[1], "list")) {
                try pkg_commands.cmdList(allocator);
                return;
            } else if (std.mem.eql(u8, args[1], "show")) {
                try pkg_commands.cmdShow(allocator, args[2..]);
                return;
            }
        }
        try printUsage();
        return;
    }

    // Try to find module as a file
    const module_path = try std.fmt.allocPrint(allocator, "{s}.py", .{module_name});
    defer allocator.free(module_path);

    if (std.fs.cwd().access(module_path, .{})) |_| {
        const opts = CompileOptions{ .input_file = module_path, .mode = "run" };
        try compile_mod.compileFile(allocator, opts);
    } else |_| {
        // Try as package/__main__.py
        const pkg_path = try std.fmt.allocPrint(allocator, "{s}/__main__.py", .{module_name});
        defer allocator.free(pkg_path);

        if (std.fs.cwd().access(pkg_path, .{})) |_| {
            const opts = CompileOptions{ .input_file = pkg_path, .mode = "run" };
            try compile_mod.compileFile(allocator, opts);
        } else |_| {
            printError("No module named '{s}'", .{module_name});
        }
    }
}

pub fn cmdReadStdin(allocator: std.mem.Allocator) !void {
    // Read Python code from stdin (cross-platform)
    const stdin_file = std.fs.File.stdin();
    const code = try stdin_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(code);

    // Write to temp file
    const tmp_path = "/tmp/metal0_stdin.py";
    const file = try std.fs.cwd().createFile(tmp_path, .{});
    defer file.close();
    try file.writeAll(code);

    // Compile and run
    const opts = CompileOptions{ .input_file = tmp_path, .mode = "run", .force = true };
    try compile_mod.compileFile(allocator, opts);
}

pub fn cmdVersion() void {
    std.debug.print("{s}metal0{s} 0.1.0\n", .{ Color.bold_cyan, Color.reset });
    std.debug.print("{s}30x faster than CPython{s}\n", .{ Color.dim, Color.reset });
}

pub fn printUsage() !void {
    std.debug.print(
        \\{s}metal0{s} - AOT Python compiler (30x faster than CPython)
        \\
        \\{s}USAGE (python3-compatible):{s}
        \\   metal0 <file.py>              # Compile and run
        \\   metal0 -c "code"              # Execute code string
        \\   metal0 -m module              # Run module as script
        \\   metal0 -                      # Read from stdin
        \\
        \\{s}PACKAGE COMMANDS (pip-compatible):{s}
        \\   install      Install packages from PyPI
        \\   uninstall    Uninstall packages
        \\   freeze       Output installed packages
        \\   list         List installed packages
        \\   show         Show package info
        \\   cache        Manage cache (dir, info, purge)
        \\
        \\{s}BUILD COMMANDS:{s}
        \\   build        Compile Python to native code
        \\   run          Compile and run a Python file
        \\   test         Run test suite
        \\   profile      Profile and optimize (run, translate, show)
        \\   server  Start WasmEdge-based eval() server
        \\   deploy       Deploy to remote server (WIP)
        \\
        \\{s}BUILD OPTIONS:{s}
        \\   --target <t>      Cross-compile target:
        \\                     native (default), wasm-browser, wasm-edge,
        \\                     linux-x64, linux-arm64, macos-x64, macos-arm64, windows-x64
        \\   --debug, -g       Emit debug info (.metal0.dbg.json)
        \\   --pgo-generate    Build with PGO instrumentation (generates profile data)
        \\   --pgo-use=<file>  Build optimized using profile data from <file>
        \\
        \\{s}EXAMPLES:{s}
        \\   metal0 app.py                        # Run Python file (30x faster)
        \\   metal0 -c "print('hi')"              # Execute code string
        \\   metal0 -m pip install requests       # Use pip through metal0
        \\   metal0 install requests              # Install packages
        \\   metal0 build -b app.py               # Compile to binary
        \\   metal0 build --target wasm-edge app.py  # Compile to WASM for edge
        \\
    , .{
        Color.bold_cyan, Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
        Color.bold,      Color.reset,
    });
}
