/// Profile Translator
/// Converts system profiler output (perf, sample) to Python-level profiles
/// using .metal0.dbg.json source maps
const std = @import("std");
const format = @import("format.zig");

/// Debug info from .metal0.dbg.json
pub const DebugInfo = struct {
    source_file: []const u8,
    source_hash: []const u8,
    symbols: []const Symbol,
    mappings: []const Mapping,

    pub const Symbol = struct {
        name: []const u8,
        kind: []const u8, // "function", "variable", "parameter"
        line: u32,
        column: u32,
        parent: ?u32 = null,
        type_hint: ?[]const u8 = null,
    };

    pub const Mapping = struct {
        py_line: u32,
        zig_line: u32,
    };

    pub fn deinit(self: *DebugInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        allocator.free(self.source_hash);
        for (self.symbols) |s| {
            allocator.free(s.name);
            allocator.free(s.kind);
            if (s.type_hint) |t| allocator.free(t);
        }
        allocator.free(self.symbols);
        allocator.free(self.mappings);
    }
};

/// Sample from profiler output
pub const Sample = struct {
    /// Address or symbol name
    symbol: []const u8,
    /// Number of samples at this location
    count: u64,
    /// Call stack (from callee to caller)
    stack: []const []const u8,
};

/// Translator state
pub const Translator = struct {
    allocator: std.mem.Allocator,
    debug_infos: std.StringHashMap(DebugInfo),

    pub fn init(allocator: std.mem.Allocator) Translator {
        return .{
            .allocator = allocator,
            .debug_infos = std.StringHashMap(DebugInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Translator) void {
        var iter = self.debug_infos.iterator();
        while (iter.next()) |entry| {
            var info = entry.value_ptr.*;
            info.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.debug_infos.deinit();
    }

    /// Load debug info from .metal0.dbg.json file
    pub fn loadDebugInfo(self: *Translator, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        const info = try parseDebugJson(self.allocator, content);
        const key = try self.allocator.dupe(u8, info.source_file);
        try self.debug_infos.put(key, info);
    }

    /// Translate a Zig symbol name to Python function name
    pub fn translateSymbol(self: *Translator, zig_symbol: []const u8) ?[]const u8 {
        // Skip runtime functions
        if (std.mem.startsWith(u8, zig_symbol, "runtime.") or
            std.mem.startsWith(u8, zig_symbol, "std."))
        {
            return null;
        }

        // Look for function in debug info
        var iter = self.debug_infos.valueIterator();
        while (iter.next()) |info| {
            for (info.symbols) |sym| {
                if (std.mem.eql(u8, sym.kind, "function")) {
                    if (std.mem.indexOf(u8, zig_symbol, sym.name)) |_| {
                        return sym.name;
                    }
                }
            }
        }

        // Try to extract function name from mangled symbol
        if (std.mem.lastIndexOf(u8, zig_symbol, ".")) |dot_pos| {
            return zig_symbol[dot_pos + 1 ..];
        }

        return zig_symbol;
    }

    /// Get Python line number from Zig line number
    pub fn getPythonLine(self: *Translator, source_file: []const u8, zig_line: u32) ?u32 {
        if (self.debug_infos.get(source_file)) |info| {
            var best_match: ?u32 = null;
            var best_zig_line: u32 = 0;

            for (info.mappings) |m| {
                if (m.zig_line <= zig_line and m.zig_line > best_zig_line) {
                    best_match = m.py_line;
                    best_zig_line = m.zig_line;
                }
            }

            return best_match;
        }
        return null;
    }

    /// Parse macOS sample output
    pub fn parseMacOSSample(self: *Translator, content: []const u8) ![]Sample {
        var samples = std.ArrayList(Sample){};
        errdefer {
            for (samples.items) |s| {
                self.allocator.free(s.symbol);
                for (s.stack) |frame| self.allocator.free(frame);
                self.allocator.free(s.stack);
            }
            samples.deinit(self.allocator);
        }

        var current_stack = std.ArrayList([]const u8){};
        defer {
            for (current_stack.items) |frame| self.allocator.free(frame);
            current_stack.deinit(self.allocator);
        }

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_call_graph = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (std.mem.startsWith(u8, trimmed, "Call graph:")) {
                in_call_graph = true;
                continue;
            }

            if (!in_call_graph) continue;
            if (trimmed.len == 0) {
                in_call_graph = false;
                continue;
            }

            if (std.mem.indexOf(u8, line, "+")) |plus_pos| {
                const after_plus = std.mem.trim(u8, line[plus_pos + 1 ..], " \t");
                var parts = std.mem.splitScalar(u8, after_plus, ' ');

                if (parts.next()) |count_str| {
                    const count = std.fmt.parseInt(u64, count_str, 10) catch continue;

                    if (parts.next()) |symbol| {
                        var stack_copy = try self.allocator.alloc([]const u8, current_stack.items.len);
                        for (current_stack.items, 0..) |frame, i| {
                            stack_copy[i] = try self.allocator.dupe(u8, frame);
                        }

                        try samples.append(self.allocator, .{
                            .symbol = try self.allocator.dupe(u8, symbol),
                            .count = count,
                            .stack = stack_copy,
                        });

                        const indent = plus_pos;
                        while (current_stack.items.len > indent / 2) {
                            const popped = current_stack.pop();
                            if (popped) |p| self.allocator.free(p);
                        }
                        try current_stack.append(self.allocator, try self.allocator.dupe(u8, symbol));
                    }
                }
            }
        }

        return samples.toOwnedSlice(self.allocator);
    }

    /// Parse Linux perf script output
    pub fn parsePerfScript(self: *Translator, content: []const u8) ![]Sample {
        var samples = std.ArrayList(Sample){};
        errdefer {
            for (samples.items) |s| {
                self.allocator.free(s.symbol);
                for (s.stack) |frame| self.allocator.free(frame);
                self.allocator.free(s.stack);
            }
            samples.deinit(self.allocator);
        }

        var sample_counts = std.StringHashMap(u64).init(self.allocator);
        defer {
            var iter = sample_counts.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            sample_counts.deinit();
        }

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (trimmed.len > 0 and (trimmed[0] >= '0' and trimmed[0] <= '9' or
                trimmed[0] >= 'a' and trimmed[0] <= 'f'))
            {
                var parts = std.mem.splitScalar(u8, trimmed, ' ');
                _ = parts.next(); // Skip address

                if (parts.next()) |symbol_with_offset| {
                    const symbol = if (std.mem.indexOf(u8, symbol_with_offset, "+")) |plus|
                        symbol_with_offset[0..plus]
                    else
                        symbol_with_offset;

                    if (std.mem.eql(u8, symbol, "[unknown]")) continue;

                    const existing = sample_counts.get(symbol) orelse 0;
                    if (existing == 0) {
                        const new_key = try self.allocator.dupe(u8, symbol);
                        try sample_counts.put(new_key, 1);
                    } else {
                        if (sample_counts.getPtr(symbol)) |ptr| {
                            ptr.* = existing + 1;
                        }
                    }
                }
            }
        }

        var iter = sample_counts.iterator();
        while (iter.next()) |entry| {
            try samples.append(self.allocator, .{
                .symbol = try self.allocator.dupe(u8, entry.key_ptr.*),
                .count = entry.value_ptr.*,
                .stack = &[_][]const u8{},
            });
        }

        return samples.toOwnedSlice(self.allocator);
    }

    /// Translate raw samples to Python profile
    pub fn translateToProfile(self: *Translator, samples: []const Sample, source_file: []const u8) !format.Profile {
        var function_samples = std.StringHashMap(u64).init(self.allocator);
        defer {
            var iter = function_samples.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            function_samples.deinit();
        }

        var total_samples: u64 = 0;

        for (samples) |sample| {
            total_samples += sample.count;

            if (self.translateSymbol(sample.symbol)) |py_func| {
                const existing = function_samples.get(py_func) orelse 0;
                if (existing == 0) {
                    const new_key = try self.allocator.dupe(u8, py_func);
                    try function_samples.put(new_key, sample.count);
                } else {
                    if (function_samples.getPtr(py_func)) |ptr| {
                        ptr.* = existing + sample.count;
                    }
                }
            }
        }

        var functions = std.ArrayList(format.FunctionProfile){};
        errdefer {
            for (functions.items) |f| {
                self.allocator.free(f.name);
                self.allocator.free(f.file);
            }
            functions.deinit(self.allocator);
        }

        var hot_functions = std.ArrayList([]const u8){};
        errdefer {
            for (hot_functions.items) |h| {
                self.allocator.free(h);
            }
            hot_functions.deinit(self.allocator);
        }

        var iter = function_samples.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const func_samples = entry.value_ptr.*;
            const percentage = if (total_samples > 0)
                @as(f32, @floatFromInt(func_samples)) / @as(f32, @floatFromInt(total_samples)) * 100.0
            else
                0.0;
            const is_hot = percentage >= 5.0;

            var line: u32 = 0;
            if (self.debug_infos.get(source_file)) |info| {
                for (info.symbols) |sym| {
                    if (std.mem.eql(u8, sym.kind, "function") and std.mem.eql(u8, sym.name, name)) {
                        line = sym.line;
                        break;
                    }
                }
            }

            try functions.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, name),
                .file = try self.allocator.dupe(u8, source_file),
                .line = line,
                .samples = func_samples,
                .percentage = percentage,
                .hot = is_hot,
                .children = &[_]format.CallEdge{},
            });

            if (is_hot) {
                try hot_functions.append(self.allocator, try self.allocator.dupe(u8, name));
            }
        }

        std.mem.sort(format.FunctionProfile, functions.items, {}, struct {
            fn lessThan(_: void, a: format.FunctionProfile, b: format.FunctionProfile) bool {
                return a.samples > b.samples;
            }
        }.lessThan);

        return format.Profile{
            .source_file = try self.allocator.dupe(u8, source_file),
            .total_samples = total_samples,
            .duration_ms = 0,
            .functions = try functions.toOwnedSlice(self.allocator),
            .hot_functions = try hot_functions.toOwnedSlice(self.allocator),
        };
    }
};

/// Parse .metal0.dbg.json content
fn parseDebugJson(allocator: std.mem.Allocator, content: []const u8) !DebugInfo {
    var info = DebugInfo{
        .source_file = "",
        .source_hash = "",
        .symbols = &[_]DebugInfo.Symbol{},
        .mappings = &[_]DebugInfo.Mapping{},
    };

    // Find sourceFile
    if (std.mem.indexOf(u8, content, "\"sourceFile\":")) |pos| {
        const start = std.mem.indexOf(u8, content[pos..], "\"") orelse return info;
        const start2 = std.mem.indexOf(u8, content[pos + start + 1 ..], "\"") orelse return info;
        const end = std.mem.indexOf(u8, content[pos + start + start2 + 2 ..], "\"") orelse return info;
        info.source_file = try allocator.dupe(u8, content[pos + start + start2 + 2 .. pos + start + start2 + 2 + end]);
    }

    // Find sourceHash
    if (std.mem.indexOf(u8, content, "\"sourceHash\":")) |pos| {
        const start = std.mem.indexOf(u8, content[pos..], "\"") orelse return info;
        const start2 = std.mem.indexOf(u8, content[pos + start + 1 ..], "\"") orelse return info;
        const end = std.mem.indexOf(u8, content[pos + start + start2 + 2 ..], "\"") orelse return info;
        info.source_hash = try allocator.dupe(u8, content[pos + start + start2 + 2 .. pos + start + start2 + 2 + end]);
    }

    // Parse symbols array
    var symbols = std.ArrayList(DebugInfo.Symbol){};
    errdefer {
        for (symbols.items) |s| {
            allocator.free(s.name);
            allocator.free(s.kind);
            if (s.type_hint) |t| allocator.free(t);
        }
        symbols.deinit(allocator);
    }

    if (std.mem.indexOf(u8, content, "\"symbols\":")) |symbols_start| {
        var pos = symbols_start;
        while (std.mem.indexOf(u8, content[pos..], "{\"name\":")) |obj_start| {
            pos = pos + obj_start;

            const obj_end = std.mem.indexOf(u8, content[pos..], "}") orelse break;
            const obj_content = content[pos .. pos + obj_end + 1];

            var sym = DebugInfo.Symbol{
                .name = "",
                .kind = "",
                .line = 0,
                .column = 0,
            };

            if (extractJsonString(obj_content, "\"name\":")) |name| {
                sym.name = try allocator.dupe(u8, name);
            }
            if (extractJsonString(obj_content, "\"kind\":")) |kind| {
                sym.kind = try allocator.dupe(u8, kind);
            }
            if (extractJsonNumber(obj_content, "\"line\":")) |line| {
                sym.line = @intCast(line);
            }
            if (extractJsonNumber(obj_content, "\"column\":")) |col| {
                sym.column = @intCast(col);
            }
            if (extractJsonString(obj_content, "\"type\":")) |t| {
                sym.type_hint = try allocator.dupe(u8, t);
            }

            try symbols.append(allocator, sym);
            pos = pos + obj_end + 1;
        }
    }
    info.symbols = try symbols.toOwnedSlice(allocator);

    // Parse mappings array
    var mappings = std.ArrayList(DebugInfo.Mapping){};
    errdefer mappings.deinit(allocator);

    if (std.mem.indexOf(u8, content, "\"mappings\":")) |mappings_start| {
        var pos = mappings_start;
        while (std.mem.indexOf(u8, content[pos..], "{\"pyLine\":")) |obj_start| {
            pos = pos + obj_start;

            const obj_end = std.mem.indexOf(u8, content[pos..], "}") orelse break;
            const obj_content = content[pos .. pos + obj_end + 1];

            var mapping = DebugInfo.Mapping{
                .py_line = 0,
                .zig_line = 0,
            };

            if (extractJsonNumber(obj_content, "\"pyLine\":")) |py| {
                mapping.py_line = @intCast(py);
            }
            if (extractJsonNumber(obj_content, "\"zigLine\":")) |zig| {
                mapping.zig_line = @intCast(zig);
            }

            try mappings.append(allocator, mapping);
            pos = pos + obj_end + 1;
        }
    }
    info.mappings = try mappings.toOwnedSlice(allocator);

    return info;
}

/// Extract string value from JSON
fn extractJsonString(content: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, content, key) orelse return null;
    const after_key = content[key_pos + key.len ..];
    const quote1 = std.mem.indexOf(u8, after_key, "\"") orelse return null;
    const quote2 = std.mem.indexOf(u8, after_key[quote1 + 1 ..], "\"") orelse return null;
    return after_key[quote1 + 1 .. quote1 + 1 + quote2];
}

/// Extract number value from JSON
fn extractJsonNumber(content: []const u8, key: []const u8) ?i64 {
    const key_pos = std.mem.indexOf(u8, content, key) orelse return null;
    const after_key = std.mem.trim(u8, content[key_pos + key.len ..], " ");

    var end: usize = 0;
    while (end < after_key.len) : (end += 1) {
        const c = after_key[end];
        if (c == ',' or c == '}' or c == ' ' or c == '\n' or c == '\r') break;
    }

    return std.fmt.parseInt(i64, after_key[0..end], 10) catch null;
}
