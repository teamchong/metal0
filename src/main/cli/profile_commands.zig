/// Profile commands: wrapper for system profilers and profile translation
/// Commands: profile run, profile translate, profile show
const std = @import("std");
const Color = @import("common.zig").Color;
const printSuccess = @import("common.zig").printSuccess;
const printError = @import("common.zig").printError;
const printInfo = @import("common.zig").printInfo;
const printWarn = @import("common.zig").printWarn;

/// Profile command: wrapper for system profilers and profile translation
/// Usage:
///   metal0 profile run ./binary         - Profile with perf (Linux) or sample (macOS)
///   metal0 profile translate data.perf  - Convert profile to Python symbols
///   metal0 profile show profile.json    - Show Python-level profile summary
pub fn cmdProfile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print(
            \\{s}Profile commands:{s}
            \\
            \\  {s}metal0 profile run <binary>{s}       Profile a compiled binary
            \\  {s}metal0 profile translate <file>{s}   Convert perf/sample data to Python symbols
            \\  {s}metal0 profile show <file.json>{s}   Show Python-level profile summary
            \\
            \\{s}Workflow:{s}
            \\  1. Compile your Python file:     metal0 build -b app.py
            \\  2. Profile with run subcommand:  metal0 profile run ./build/.../app
            \\  3. Translate to Python symbols:  metal0 profile translate profile.data
            \\  4. Rebuild with profile:         metal0 build -b app.py --pgo-use=profile.json
            \\
        , .{
            Color.bold, Color.reset,
            Color.cyan, Color.reset,
            Color.cyan, Color.reset,
            Color.cyan, Color.reset,
            Color.bold, Color.reset,
        });
        return;
    }

    const subcmd = args[0];
    if (std.mem.eql(u8, subcmd, "run")) {
        try cmdProfileRun(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "translate")) {
        try cmdProfileTranslate(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcmd, "show")) {
        try cmdProfileShow(allocator, args[1..]);
    } else {
        printError("Unknown profile command: {s}", .{subcmd});
    }
}

/// Profile run: wrapper for system profilers
fn cmdProfileRun(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No binary specified", .{});
        std.debug.print("\nUsage: metal0 profile run <binary>\n", .{});
        return;
    }

    const binary_path = args[0];
    const builtin = @import("builtin");

    // Check if binary exists
    std.fs.cwd().access(binary_path, .{}) catch |err| {
        printError("Cannot access binary '{s}': {any}", .{ binary_path, err });
        return;
    };

    // Use platform-appropriate profiler
    if (builtin.os.tag == .macos) {
        std.debug.print("{s}Profiling with macOS sample tool...{s}\n", .{ Color.dim, Color.reset });
        std.debug.print("  Output: profile.txt (text format)\n\n", .{});

        // macOS: Use 'sample' command (built-in, no Instruments required)
        // sample <pid|name> <duration> -file <output>
        var child = std.process.Child.init(&[_][]const u8{
            "sample",
            binary_path,
            "5", // 5 seconds of profiling
            "-file",
            "profile.txt",
        }, allocator);
        child.spawn() catch |err| {
            printError("Failed to start profiler: {any}", .{err});
            return;
        };

        // Also start the binary
        var binary_child = std.process.Child.init(&[_][]const u8{binary_path}, allocator);
        binary_child.stdin_behavior = .Inherit;
        binary_child.stdout_behavior = .Inherit;
        binary_child.stderr_behavior = .Inherit;
        binary_child.spawn() catch |err| {
            printError("Failed to run binary: {any}", .{err});
            return;
        };

        // Wait for binary to finish
        _ = binary_child.wait() catch {};
        _ = child.wait() catch {};

        printSuccess("Profile written to profile.txt", .{});
        std.debug.print("Next: metal0 profile translate profile.txt\n", .{});
    } else if (builtin.os.tag == .linux) {
        std.debug.print("{s}Profiling with perf...{s}\n", .{ Color.dim, Color.reset });
        std.debug.print("  Output: perf.data\n\n", .{});

        // Linux: Use 'perf record'
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "perf",
                "record",
                "-g", // Call graphs
                "-o",
                "perf.data",
                "--",
                binary_path,
            },
        }) catch |err| {
            printError("Failed to run perf: {any}", .{err});
            std.debug.print("\nMake sure perf is installed: sudo apt install linux-tools-generic\n", .{});
            return;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code == 0) {
                    printSuccess("Profile written to perf.data", .{});
                    std.debug.print("Next: metal0 profile translate perf.data\n", .{});
                } else {
                    printError("perf failed: {s}", .{result.stderr});
                }
            },
            else => printError("perf terminated abnormally: {s}", .{result.stderr}),
        }
    } else {
        printError("Profile run not supported on this platform", .{});
        std.debug.print("Supported: Linux (perf), macOS (sample)\n", .{});
    }
}

/// Profile translate: convert system profiler output to Python symbols
fn cmdProfileTranslate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const profile_mod = @import("../../profile/translator.zig");
    const profile_format = @import("../../profile/format.zig");

    if (args.len == 0) {
        printError("No profile data specified", .{});
        std.debug.print("\nUsage: metal0 profile translate <perf.data|profile.txt>\n", .{});
        return;
    }

    const input_path = args[0];

    // Check if input exists
    std.fs.cwd().access(input_path, .{}) catch |err| {
        printError("Cannot access profile data '{s}': {any}", .{ input_path, err });
        return;
    };

    // Look for debug info files
    const dbg_files = findDebugInfoFiles(allocator) catch |err| {
        printError("Cannot find debug info files: {any}", .{err});
        std.debug.print("\nMake sure to compile with --debug flag first\n", .{});
        return;
    };
    defer {
        for (dbg_files) |f| allocator.free(f);
        allocator.free(dbg_files);
    }

    if (dbg_files.len == 0) {
        printWarn("No .metal0.dbg.json files found", .{});
        std.debug.print("Compile with --debug to generate debug info\n", .{});
        return;
    }

    printInfo("Found {d} debug info files", .{dbg_files.len});

    // Initialize translator
    var translator = profile_mod.Translator.init(allocator);
    defer translator.deinit();

    // Load all debug info files
    for (dbg_files) |dbg_path| {
        translator.loadDebugInfo(dbg_path) catch |err| {
            printWarn("Failed to load {s}: {any}", .{ dbg_path, err });
        };
    }

    // Read profile data
    const profile_file = std.fs.cwd().openFile(input_path, .{}) catch |err| {
        printError("Cannot open profile data: {any}", .{err});
        return;
    };
    defer profile_file.close();

    const profile_content = profile_file.readToEndAlloc(allocator, 50 * 1024 * 1024) catch |err| {
        printError("Cannot read profile data: {any}", .{err});
        return;
    };
    defer allocator.free(profile_content);

    // Detect profile format and parse
    const builtin = @import("builtin");
    const samples = blk: {
        if (builtin.os.tag == .macos or std.mem.indexOf(u8, input_path, "sample") != null or
            std.mem.indexOf(u8, input_path, ".txt") != null)
        {
            printInfo("Parsing macOS sample format...", .{});
            break :blk translator.parseMacOSSample(profile_content) catch |err| {
                printError("Failed to parse sample output: {any}", .{err});
                return;
            };
        } else {
            printInfo("Parsing Linux perf format...", .{});
            break :blk translator.parsePerfScript(profile_content) catch |err| {
                printError("Failed to parse perf output: {any}", .{err});
                return;
            };
        }
    };
    defer {
        for (samples) |s| {
            allocator.free(s.symbol);
            for (s.stack) |frame| allocator.free(frame);
            allocator.free(s.stack);
        }
        allocator.free(samples);
    }

    printInfo("Parsed {d} samples", .{samples.len});

    // Get source file from first debug info
    var source_file: []const u8 = "unknown";
    const dbg_values = translator.debug_infos.values();
    if (dbg_values.len > 0) {
        source_file = dbg_values[0].source_file;
    }

    // Translate to Python profile
    var profile = translator.translateToProfile(samples, source_file) catch |err| {
        printError("Failed to translate profile: {any}", .{err});
        return;
    };
    defer profile.deinit(allocator);

    // Write output
    const output_path = "profile.json";
    profile_format.writeJson(allocator, profile, output_path) catch |err| {
        printError("Failed to write profile: {any}", .{err});
        return;
    };

    printSuccess("Profile written to {s}", .{output_path});
    std.debug.print("\n{s}Summary:{s}\n", .{ Color.bold, Color.reset });
    std.debug.print("  Total samples: {d}\n", .{profile.total_samples});
    std.debug.print("  Functions: {d}\n", .{profile.functions.len});
    std.debug.print("  Hot functions (>5%%): {d}\n", .{profile.hot_functions.len});

    if (profile.hot_functions.len > 0) {
        std.debug.print("\n{s}Hot functions:{s}\n", .{ Color.bold, Color.reset });
        for (profile.functions) |func| {
            if (func.hot) {
                std.debug.print("  {s}{s}{s} ({d:.1}%% - {d} samples)\n", .{
                    Color.yellow,
                    func.name,
                    Color.reset,
                    func.percentage,
                    func.samples,
                });
            }
        }
    }

    std.debug.print("\nNext: metal0 build -b <file.py> --pgo-use={s}\n", .{output_path});
}

/// Profile show: display Python-level profile summary
fn cmdProfileShow(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printError("No profile file specified", .{});
        std.debug.print("\nUsage: metal0 profile show <profile.json>\n", .{});
        return;
    }

    const profile_path = args[0];

    // Check if file exists
    std.fs.cwd().access(profile_path, .{}) catch |err| {
        printError("Cannot access profile '{s}': {any}", .{ profile_path, err });
        return;
    };

    // Read and parse profile JSON
    const file = std.fs.cwd().openFile(profile_path, .{}) catch |err| {
        printError("Cannot open profile: {any}", .{err});
        return;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        printError("Cannot read profile: {any}", .{err});
        return;
    };
    defer allocator.free(content);

    // Simple JSON display (parse key values)
    std.debug.print("\n{s}Profile: {s}{s}\n\n", .{ Color.bold, profile_path, Color.reset });

    // Extract and display summary
    if (extractJsonStringValue(content, "\"sourceFile\":")) |source| {
        std.debug.print("Source: {s}\n", .{source});
    }
    if (extractJsonNumberValue(content, "\"totalSamples\":")) |samples| {
        std.debug.print("Total samples: {d}\n", .{samples});
    }

    // Display hot functions
    if (std.mem.indexOf(u8, content, "\"hotFunctions\":")) |_| {
        std.debug.print("\n{s}Hot functions (>5%%):{s}\n", .{ Color.bold, Color.reset });

        // Find functions array
        if (std.mem.indexOf(u8, content, "\"functions\":")) |funcs_start| {
            var pos = funcs_start;
            var count: usize = 0;

            while (std.mem.indexOf(u8, content[pos..], "\"hot\": true")) |hot_pos| {
                // Find this function's details
                const search_start = pos + hot_pos;

                // Look backwards for function name
                var name_search = search_start;
                while (name_search > 0 and content[name_search] != '{') : (name_search -= 1) {}

                if (name_search > 0) {
                    const func_obj = content[name_search .. search_start + 20];
                    if (extractJsonStringValue(func_obj, "\"name\":")) |name| {
                        const percentage = extractJsonNumberValue(func_obj, "\"percentage\":") orelse 0;
                        const samples_val = extractJsonNumberValue(func_obj, "\"samples\":") orelse 0;

                        std.debug.print("  {s}{s}{s} ({d}%% - {d} samples)\n", .{
                            Color.yellow,
                            name,
                            Color.reset,
                            percentage,
                            samples_val,
                        });
                        count += 1;
                    }
                }

                pos = search_start + 10;
                if (count >= 10) break; // Limit output
            }

            if (count == 0) {
                std.debug.print("  (no hot functions found)\n", .{});
            }
        }
    }

    std.debug.print("\nUse --pgo-use={s} when rebuilding to optimize hot paths.\n", .{profile_path});
}

fn extractJsonStringValue(content: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, content, key) orelse return null;
    const after_key = content[key_pos + key.len ..];
    const quote1 = std.mem.indexOf(u8, after_key, "\"") orelse return null;
    const quote2 = std.mem.indexOf(u8, after_key[quote1 + 1 ..], "\"") orelse return null;
    return after_key[quote1 + 1 .. quote1 + 1 + quote2];
}

fn extractJsonNumberValue(content: []const u8, key: []const u8) ?i64 {
    const key_pos = std.mem.indexOf(u8, content, key) orelse return null;
    const after_key = std.mem.trim(u8, content[key_pos + key.len ..], " ");

    var end: usize = 0;
    while (end < after_key.len) : (end += 1) {
        const c = after_key[end];
        if (c == ',' or c == '}' or c == ' ' or c == '\n' or c == '\r' or c == '.') break;
    }

    return std.fmt.parseInt(i64, after_key[0..end], 10) catch null;
}

/// Find all .metal0.dbg.json files in build directory
fn findDebugInfoFiles(allocator: std.mem.Allocator) ![][]const u8 {
    var files = std.ArrayList([]const u8){};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    // Search in build/ directory
    var dir = std.fs.cwd().openDir("build", .{ .iterate = true }) catch {
        return files.toOwnedSlice(allocator);
    };
    defer dir.close();

    var walker = dir.walk(allocator) catch {
        return files.toOwnedSlice(allocator);
    };
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".metal0.dbg.json")) {
            const path = try std.fmt.allocPrint(allocator, "build/{s}", .{entry.path});
            try files.append(allocator, path);
        }
    }

    return files.toOwnedSlice(allocator);
}
