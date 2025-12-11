/// Command-Line Arguments Parser
/// Mirrors cpython/Python/initconfig.c - argument parsing
///
/// This module handles parsing of Python command-line arguments:
/// - Standard options (-b, -B, -c, -E, -i, -I, -m, -O, -P, -q, -s, -S, -u, -v, -V)
/// - Extended options (-X faulthandler, -X tracemalloc, etc.)
/// - Warning options (-W)

const std = @import("std");
const PyConfig = @import("config.zig").PyConfig;

/// Read configuration from command-line arguments
pub fn readArgs(config: *PyConfig, args: []const []const u8) !void {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-b")) {
            config.bytes_warning += 1;
        } else if (std.mem.eql(u8, arg, "-B")) {
            config.write_bytecode = false;
        } else if (std.mem.eql(u8, arg, "-c")) {
            if (i + 1 < args.len) {
                i += 1;
                config.run_command = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-E")) {
            config.use_environment = false;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            // Help requested
        } else if (std.mem.eql(u8, arg, "-i")) {
            config.inspect = true;
            config.interactive = true;
        } else if (std.mem.eql(u8, arg, "-I")) {
            config.isolated = true;
            config.use_environment = false;
            config.site_import = false;
        } else if (std.mem.eql(u8, arg, "-m")) {
            if (i + 1 < args.len) {
                i += 1;
                config.run_module = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-O")) {
            config.optimization_level = @min(config.optimization_level + 1, 2);
        } else if (std.mem.eql(u8, arg, "-OO")) {
            config.optimization_level = 2;
        } else if (std.mem.eql(u8, arg, "-P")) {
            config.safe_path = true;
        } else if (std.mem.eql(u8, arg, "-q")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "-s")) {
            // Skip user site
        } else if (std.mem.eql(u8, arg, "-S")) {
            config.site_import = false;
        } else if (std.mem.eql(u8, arg, "-u")) {
            config.buffered_stdio = false;
        } else if (std.mem.eql(u8, arg, "-v")) {
            config.verbose += 1;
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            // Version requested
        } else if (std.mem.startsWith(u8, arg, "-W")) {
            // Warning option
        } else if (std.mem.startsWith(u8, arg, "-X")) {
            // Extended option
            if (i + 1 < args.len) {
                i += 1;
                const xopt = args[i];
                try parseXOption(config, xopt);
            }
        }
    }
}

/// Parse -X option
pub fn parseXOption(config: *PyConfig, opt: []const u8) !void {
    if (std.mem.eql(u8, opt, "faulthandler")) {
        config.faulthandler = true;
    } else if (std.mem.startsWith(u8, opt, "tracemalloc")) {
        if (std.mem.indexOf(u8, opt, "=")) |eq_pos| {
            const val = opt[eq_pos + 1 ..];
            config.tracemalloc = std.fmt.parseInt(i32, val, 10) catch 1;
        } else {
            config.tracemalloc = 1;
        }
    } else if (std.mem.eql(u8, opt, "importtime")) {
        config.import_time = true;
    } else if (std.mem.eql(u8, opt, "dev")) {
        // Dev mode
        config.faulthandler = true;
    } else if (std.mem.eql(u8, opt, "utf8")) {
        // UTF-8 mode
    } else if (std.mem.eql(u8, opt, "no_debug_ranges")) {
        config.code_debug_ranges = false;
    } else if (std.mem.eql(u8, opt, "perf")) {
        config.perf_profiling = true;
    } else if (std.mem.startsWith(u8, opt, "frozen_modules")) {
        if (std.mem.indexOf(u8, opt, "=")) |eq_pos| {
            const val = opt[eq_pos + 1 ..];
            if (std.mem.eql(u8, val, "on")) {
                config.use_frozen_modules = 1;
            } else if (std.mem.eql(u8, val, "off")) {
                config.use_frozen_modules = 0;
            }
        }
    }
}
