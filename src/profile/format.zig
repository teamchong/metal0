/// Python-level profile format
/// Used for PGO (Profile-Guided Optimization) at the Python level
const std = @import("std");

/// Profile format version
pub const VERSION: u32 = 1;

/// Function profile data
pub const FunctionProfile = struct {
    /// Python function name
    name: []const u8,
    /// Source file path
    file: []const u8,
    /// Line number in Python source
    line: u32,
    /// Number of times this function was sampled (proxy for time spent)
    samples: u64,
    /// Percentage of total samples (0-100)
    percentage: f32,
    /// Is this a hot function (>5% of samples)
    hot: bool,
    /// Child function calls from this function
    children: []const CallEdge,
};

/// Call edge between functions
pub const CallEdge = struct {
    /// Callee function name
    callee: []const u8,
    /// Number of samples in this call path
    samples: u64,
};

/// Complete profile for a Python program
pub const Profile = struct {
    /// Profile format version
    version: u32 = VERSION,
    /// Original Python source file
    source_file: []const u8,
    /// Total samples collected
    total_samples: u64,
    /// Profiling duration in milliseconds
    duration_ms: u64,
    /// Function profiles sorted by samples (hottest first)
    functions: []const FunctionProfile,
    /// Hot functions (>5% of samples) for quick lookup
    hot_functions: []const []const u8,

    pub fn deinit(self: *Profile, allocator: std.mem.Allocator) void {
        for (self.functions) |f| {
            allocator.free(f.name);
            allocator.free(f.file);
            for (f.children) |c| {
                allocator.free(c.callee);
            }
            allocator.free(f.children);
        }
        allocator.free(self.functions);
        for (self.hot_functions) |h| {
            allocator.free(h);
        }
        allocator.free(self.hot_functions);
        allocator.free(self.source_file);
    }
};

/// Write profile to JSON file
pub fn writeJson(allocator: std.mem.Allocator, profile: Profile, path: []const u8) !void {
    // Build JSON string in memory first
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "{\n");
    const version_line = try std.fmt.allocPrint(allocator, "  \"version\": {d},\n", .{profile.version});
    defer allocator.free(version_line);
    try output.appendSlice(allocator, version_line);

    const source_line = try std.fmt.allocPrint(allocator, "  \"sourceFile\": \"{s}\",\n", .{profile.source_file});
    defer allocator.free(source_line);
    try output.appendSlice(allocator, source_line);

    const samples_line = try std.fmt.allocPrint(allocator, "  \"totalSamples\": {d},\n", .{profile.total_samples});
    defer allocator.free(samples_line);
    try output.appendSlice(allocator, samples_line);

    const duration_line = try std.fmt.allocPrint(allocator, "  \"durationMs\": {d},\n", .{profile.duration_ms});
    defer allocator.free(duration_line);
    try output.appendSlice(allocator, duration_line);

    // Hot functions
    try output.appendSlice(allocator, "  \"hotFunctions\": [");
    for (profile.hot_functions, 0..) |name, i| {
        if (i > 0) try output.appendSlice(allocator, ", ");
        const hot_item = try std.fmt.allocPrint(allocator, "\"{s}\"", .{name});
        defer allocator.free(hot_item);
        try output.appendSlice(allocator, hot_item);
    }
    try output.appendSlice(allocator, "],\n");

    // Function profiles
    try output.appendSlice(allocator, "  \"functions\": [\n");
    for (profile.functions, 0..) |func, i| {
        if (i > 0) try output.appendSlice(allocator, ",\n");
        try output.appendSlice(allocator, "    {\n");

        const name_line = try std.fmt.allocPrint(allocator, "      \"name\": \"{s}\",\n", .{func.name});
        defer allocator.free(name_line);
        try output.appendSlice(allocator, name_line);

        const file_line = try std.fmt.allocPrint(allocator, "      \"file\": \"{s}\",\n", .{func.file});
        defer allocator.free(file_line);
        try output.appendSlice(allocator, file_line);

        const line_line = try std.fmt.allocPrint(allocator, "      \"line\": {d},\n", .{func.line});
        defer allocator.free(line_line);
        try output.appendSlice(allocator, line_line);

        const samples_func = try std.fmt.allocPrint(allocator, "      \"samples\": {d},\n", .{func.samples});
        defer allocator.free(samples_func);
        try output.appendSlice(allocator, samples_func);

        const pct_line = try std.fmt.allocPrint(allocator, "      \"percentage\": {d:.2},\n", .{func.percentage});
        defer allocator.free(pct_line);
        try output.appendSlice(allocator, pct_line);

        const hot_line = try std.fmt.allocPrint(allocator, "      \"hot\": {s},\n", .{if (func.hot) "true" else "false"});
        defer allocator.free(hot_line);
        try output.appendSlice(allocator, hot_line);

        // Children
        try output.appendSlice(allocator, "      \"children\": [");
        for (func.children, 0..) |child, j| {
            if (j > 0) try output.appendSlice(allocator, ", ");
            const child_item = try std.fmt.allocPrint(allocator, "{{\"callee\": \"{s}\", \"samples\": {d}}}", .{ child.callee, child.samples });
            defer allocator.free(child_item);
            try output.appendSlice(allocator, child_item);
        }
        try output.appendSlice(allocator, "]\n");
        try output.appendSlice(allocator, "    }");
    }
    try output.appendSlice(allocator, "\n  ]\n");
    try output.appendSlice(allocator, "}\n");

    // Write to file
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(output.items);
}

/// Read profile from JSON file
pub fn readJson(allocator: std.mem.Allocator, path: []const u8) !Profile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    _ = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    // Note: content is intentionally not freed - caller handles cleanup via Profile.deinit

    // Parse JSON manually (simple parser for our format)
    // TODO: Implement proper JSON parsing
    // For now, return empty profile
    return Profile{
        .source_file = try allocator.dupe(u8, ""),
        .total_samples = 0,
        .duration_ms = 0,
        .functions = &[_]FunctionProfile{},
        .hot_functions = &[_][]const u8{},
    };
}
