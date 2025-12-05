/// Debug Info Module
///
/// External debug information for metal0 compiled binaries.
/// Follows industry patterns (.pdb, .dSYM, DWARF) - separate from release binary.
///
/// File format: .metal0.dbg (binary) or .metal0.dbg.json (human-readable)
///
/// Design principles:
/// - Zero overhead in release builds (AST unchanged)
/// - Generated alongside compilation when --debug flag set
/// - Indexed by token/parse order for O(1) lookup
/// - Supports incremental updates (hash-based invalidation)
///
const std = @import("std");

// Re-export DWARF emitter for convenience
pub const dwarf = @import("dwarf_emitter.zig");

/// Source location in Python file
pub const SourceLoc = struct {
    line: u32, // 1-indexed
    column: u32, // 1-indexed, 0 = unknown
    end_line: u32 = 0, // End line (0 = same as start)
    end_column: u32 = 0, // End column (0 = unknown)

    pub const unknown: SourceLoc = .{ .line = 0, .column = 0 };

    pub fn isKnown(self: SourceLoc) bool {
        return self.line > 0;
    }

    /// Single line location
    pub fn single(line: u32, column: u32) SourceLoc {
        return .{ .line = line, .column = column };
    }

    /// Range spanning multiple lines
    pub fn range(start_line: u32, start_col: u32, end_line: u32, end_col: u32) SourceLoc {
        return .{
            .line = start_line,
            .column = start_col,
            .end_line = end_line,
            .end_column = end_col,
        };
    }
};

/// Symbol types in debug info
pub const SymbolKind = enum(u8) {
    function = 0,
    class = 1,
    method = 2,
    variable = 3,
    parameter = 4,
    module = 5,
    import = 6,
    lambda = 7,
    comprehension = 8,
};

/// A debug symbol entry
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    loc: SourceLoc,
    /// Parent symbol index (for nested functions/classes), null for top-level
    parent: ?u32 = null,
    /// Type annotation if available
    type_hint: ?[]const u8 = null,
};

/// Statement location entry - maps statement index to source location
pub const StmtLoc = struct {
    /// Index in parse order (matches AST traversal order)
    stmt_index: u32,
    /// Source location
    loc: SourceLoc,
    /// Symbol scope (index into symbols array)
    scope: ?u32 = null,
};

/// Generated code mapping - Python line to Zig line
pub const CodeMapping = struct {
    py_line: u32,
    zig_line: u32,
    /// Binary offset (filled after Zig compilation)
    binary_offset: ?u64 = null,
};

/// Debug info file header
pub const Header = struct {
    /// Magic bytes: "M0DB" (Metal0 DeBug)
    magic: [4]u8 = .{ 'M', '0', 'D', 'B' },
    /// Format version
    version: u32 = 1,
    /// Source file hash (for invalidation)
    source_hash: u64,
    /// Timestamp
    timestamp: i64,
    /// Counts
    symbol_count: u32,
    stmt_count: u32,
    mapping_count: u32,
};

/// Complete debug info for a source file
pub const DebugInfo = struct {
    header: Header,
    /// Source file path
    source_file: []const u8,
    /// Generated Zig file path
    generated_file: ?[]const u8 = null,
    /// Symbol table
    symbols: []const Symbol,
    /// Statement locations
    stmt_locs: []const StmtLoc,
    /// Code mappings (Python -> Zig -> Binary)
    mappings: []const CodeMapping,

    pub fn deinit(self: *DebugInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.source_file);
        if (self.generated_file) |gf| allocator.free(gf);
        for (self.symbols) |sym| {
            allocator.free(sym.name);
            if (sym.type_hint) |th| allocator.free(th);
        }
        allocator.free(self.symbols);
        allocator.free(self.stmt_locs);
        allocator.free(self.mappings);
    }
};

/// Writer for building debug info during parsing/codegen
pub const DebugInfoWriter = struct {
    allocator: std.mem.Allocator,
    source_file: []const u8,
    source_hash: u64,

    symbols: std.ArrayList(Symbol),
    stmt_locs: std.ArrayList(StmtLoc),
    mappings: std.ArrayList(CodeMapping),

    /// Current scope stack (for nested functions/classes)
    scope_stack: std.ArrayList(u32),

    /// Current statement index
    current_stmt_index: u32 = 0,

    /// Current Zig line being generated
    current_zig_line: u32 = 1,

    pub fn init(allocator: std.mem.Allocator, source_file: []const u8, source_content: []const u8) DebugInfoWriter {
        return .{
            .allocator = allocator,
            .source_file = source_file,
            .source_hash = computeHash(source_content),
            .symbols = std.ArrayList(Symbol){},
            .stmt_locs = std.ArrayList(StmtLoc){},
            .mappings = std.ArrayList(CodeMapping){},
            .scope_stack = std.ArrayList(u32){},
        };
    }

    pub fn deinit(self: *DebugInfoWriter) void {
        for (self.symbols.items) |sym| {
            self.allocator.free(sym.name);
            if (sym.type_hint) |th| self.allocator.free(th);
        }
        self.symbols.deinit(self.allocator);
        self.stmt_locs.deinit(self.allocator);
        self.mappings.deinit(self.allocator);
        self.scope_stack.deinit(self.allocator);
    }

    /// Add a symbol (function, class, variable, etc.)
    pub fn addSymbol(self: *DebugInfoWriter, name: []const u8, kind: SymbolKind, loc: SourceLoc) !u32 {
        const index: u32 = @intCast(self.symbols.items.len);
        const name_copy = try self.allocator.dupe(u8, name);

        try self.symbols.append(self.allocator, .{
            .name = name_copy,
            .kind = kind,
            .loc = loc,
            .parent = if (self.scope_stack.items.len > 0) self.scope_stack.getLast() else null,
        });

        return index;
    }

    /// Enter a scope (function/class)
    pub fn enterScope(self: *DebugInfoWriter, symbol_index: u32) !void {
        try self.scope_stack.append(self.allocator, symbol_index);
    }

    /// Exit current scope
    pub fn exitScope(self: *DebugInfoWriter) void {
        if (self.scope_stack.items.len > 0) {
            _ = self.scope_stack.pop();
        }
    }

    /// Record a statement location (called during parsing)
    pub fn recordStmt(self: *DebugInfoWriter, loc: SourceLoc) !void {
        try self.stmt_locs.append(self.allocator, .{
            .stmt_index = self.current_stmt_index,
            .loc = loc,
            .scope = if (self.scope_stack.items.len > 0) self.scope_stack.getLast() else null,
        });
        self.current_stmt_index += 1;
    }

    /// Record a code mapping (called during codegen)
    pub fn recordMapping(self: *DebugInfoWriter, py_line: u32, zig_line: u32) !void {
        // Avoid duplicate mappings for same Python line
        if (self.mappings.items.len > 0) {
            const last = &self.mappings.items[self.mappings.items.len - 1];
            if (last.py_line == py_line) {
                return; // Already have mapping for this line
            }
        }

        try self.mappings.append(self.allocator, .{
            .py_line = py_line,
            .zig_line = zig_line,
        });
    }

    /// Increment Zig line counter (call when emitting newline)
    pub fn incrementZigLine(self: *DebugInfoWriter) void {
        self.current_zig_line += 1;
    }

    /// Build final debug info
    pub fn build(self: *DebugInfoWriter) !DebugInfo {
        return .{
            .header = .{
                .source_hash = self.source_hash,
                .timestamp = std.time.timestamp(),
                .symbol_count = @intCast(self.symbols.items.len),
                .stmt_count = @intCast(self.stmt_locs.items.len),
                .mapping_count = @intCast(self.mappings.items.len),
            },
            .source_file = try self.allocator.dupe(u8, self.source_file),
            .symbols = try self.allocator.dupe(Symbol, self.symbols.items),
            .stmt_locs = try self.allocator.dupe(StmtLoc, self.stmt_locs.items),
            .mappings = try self.allocator.dupe(CodeMapping, self.mappings.items),
        };
    }

    /// Write debug info to binary file
    pub fn writeBinary(self: *DebugInfoWriter, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Build binary data in memory, then write all at once
        var data = std.ArrayList(u8){};
        defer data.deinit(self.allocator);

        // Write header
        const header = Header{
            .source_hash = self.source_hash,
            .timestamp = std.time.timestamp(),
            .symbol_count = @intCast(self.symbols.items.len),
            .stmt_count = @intCast(self.stmt_locs.items.len),
            .mapping_count = @intCast(self.mappings.items.len),
        };
        try data.appendSlice(self.allocator, &header.magic);
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.version));
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.source_hash));
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.timestamp));
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.symbol_count));
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.stmt_count));
        try data.appendSlice(self.allocator, &std.mem.toBytes(header.mapping_count));

        // Write source file path length + data
        const source_len: u32 = @intCast(self.source_file.len);
        try data.appendSlice(self.allocator, &std.mem.toBytes(source_len));
        try data.appendSlice(self.allocator, self.source_file);

        // Write symbols
        for (self.symbols.items) |sym| {
            const name_len: u32 = @intCast(sym.name.len);
            try data.appendSlice(self.allocator, &std.mem.toBytes(name_len));
            try data.appendSlice(self.allocator, sym.name);
            try data.append(self.allocator, @intFromEnum(sym.kind));
            try data.appendSlice(self.allocator, &std.mem.toBytes(sym.loc.line));
            try data.appendSlice(self.allocator, &std.mem.toBytes(sym.loc.column));
            const parent_val: u32 = sym.parent orelse std.math.maxInt(u32);
            try data.appendSlice(self.allocator, &std.mem.toBytes(parent_val));
        }

        // Write statement locations
        for (self.stmt_locs.items) |sl| {
            try data.appendSlice(self.allocator, &std.mem.toBytes(sl.stmt_index));
            try data.appendSlice(self.allocator, &std.mem.toBytes(sl.loc.line));
            try data.appendSlice(self.allocator, &std.mem.toBytes(sl.loc.column));
            const scope_val: u32 = sl.scope orelse std.math.maxInt(u32);
            try data.appendSlice(self.allocator, &std.mem.toBytes(scope_val));
        }

        // Write mappings
        for (self.mappings.items) |m| {
            try data.appendSlice(self.allocator, &std.mem.toBytes(m.py_line));
            try data.appendSlice(self.allocator, &std.mem.toBytes(m.zig_line));
        }

        // Write all data at once
        try file.writeAll(data.items);
    }

    /// Write debug info to JSON file (human-readable)
    pub fn writeJson(self: *DebugInfoWriter, writer: anytype) !void {
        try writer.writeAll("{\n");
        try writer.print("  \"version\": 1,\n", .{});
        try writer.print("  \"sourceFile\": \"{s}\",\n", .{self.source_file});
        try writer.print("  \"sourceHash\": \"{x}\",\n", .{self.source_hash});

        // Symbols
        try writer.writeAll("  \"symbols\": [\n");
        for (self.symbols.items, 0..) |sym, i| {
            try writer.writeAll("    {");
            try writer.print("\"name\": \"{s}\", ", .{sym.name});
            try writer.print("\"kind\": \"{s}\", ", .{@tagName(sym.kind)});
            try writer.print("\"line\": {d}, \"column\": {d}", .{ sym.loc.line, sym.loc.column });
            if (sym.parent) |p| {
                try writer.print(", \"parent\": {d}", .{p});
            }
            try writer.writeAll("}");
            if (i < self.symbols.items.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ],\n");

        // Statement locations
        try writer.writeAll("  \"statements\": [\n");
        for (self.stmt_locs.items, 0..) |sl, i| {
            try writer.print("    {{\"index\": {d}, \"line\": {d}, \"column\": {d}", .{
                sl.stmt_index,
                sl.loc.line,
                sl.loc.column,
            });
            if (sl.scope) |s| {
                try writer.print(", \"scope\": {d}", .{s});
            }
            try writer.writeAll("}");
            if (i < self.stmt_locs.items.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ],\n");

        // Mappings
        try writer.writeAll("  \"mappings\": [\n");
        for (self.mappings.items, 0..) |m, i| {
            try writer.print("    {{\"pyLine\": {d}, \"zigLine\": {d}}}", .{ m.py_line, m.zig_line });
            if (i < self.mappings.items.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ]\n");

        try writer.writeAll("}\n");
    }
};

/// Reader for loading debug info
pub const DebugInfoReader = struct {
    allocator: std.mem.Allocator,
    debug_info: ?DebugInfo = null,

    /// Line lookup cache (sorted by Python line for binary search)
    py_to_zig: ?[]const CodeMapping = null,

    pub fn init(allocator: std.mem.Allocator) DebugInfoReader {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DebugInfoReader) void {
        if (self.debug_info) |*di| {
            di.deinit(self.allocator);
        }
    }

    /// Load debug info from binary file
    pub fn loadBinary(self: *DebugInfoReader, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var reader = file.reader();

        // Read and verify header
        var magic: [4]u8 = undefined;
        _ = try reader.readAll(&magic);
        if (!std.mem.eql(u8, &magic, "M0DB")) {
            return error.InvalidDebugInfo;
        }

        const version = try reader.readInt(u32, .little);
        if (version != 1) {
            return error.UnsupportedVersion;
        }

        const source_hash = try reader.readInt(u64, .little);
        const timestamp = try reader.readInt(i64, .little);
        const symbol_count = try reader.readInt(u32, .little);
        const stmt_count = try reader.readInt(u32, .little);
        const mapping_count = try reader.readInt(u32, .little);

        // Read source file path
        const source_len = try reader.readInt(u32, .little);
        const source_file = try self.allocator.alloc(u8, source_len);
        _ = try reader.readAll(source_file);

        // Read symbols
        const symbols = try self.allocator.alloc(Symbol, symbol_count);
        for (symbols) |*sym| {
            const name_len = try reader.readInt(u32, .little);
            const name = try self.allocator.alloc(u8, name_len);
            _ = try reader.readAll(name);

            sym.* = .{
                .name = name,
                .kind = @enumFromInt(try reader.readByte()),
                .loc = .{
                    .line = try reader.readInt(u32, .little),
                    .column = try reader.readInt(u32, .little),
                },
                .parent = blk: {
                    const p = try reader.readInt(u32, .little);
                    break :blk if (p == std.math.maxInt(u32)) null else p;
                },
            };
        }

        // Read statement locations
        const stmt_locs = try self.allocator.alloc(StmtLoc, stmt_count);
        for (stmt_locs) |*sl| {
            sl.* = .{
                .stmt_index = try reader.readInt(u32, .little),
                .loc = .{
                    .line = try reader.readInt(u32, .little),
                    .column = try reader.readInt(u32, .little),
                },
                .scope = blk: {
                    const s = try reader.readInt(u32, .little);
                    break :blk if (s == std.math.maxInt(u32)) null else s;
                },
            };
        }

        // Read mappings
        const mappings = try self.allocator.alloc(CodeMapping, mapping_count);
        for (mappings) |*m| {
            m.* = .{
                .py_line = try reader.readInt(u32, .little),
                .zig_line = try reader.readInt(u32, .little),
            };
        }

        self.debug_info = .{
            .header = .{
                .source_hash = source_hash,
                .timestamp = timestamp,
                .symbol_count = symbol_count,
                .stmt_count = stmt_count,
                .mapping_count = mapping_count,
            },
            .source_file = source_file,
            .symbols = symbols,
            .stmt_locs = stmt_locs,
            .mappings = mappings,
        };
    }

    /// Lookup Python line from Zig line (for stack traces)
    pub fn zigToPython(self: *DebugInfoReader, zig_line: u32) ?SourceLoc {
        const di = self.debug_info orelse return null;

        // Find closest mapping <= zig_line
        var best: ?CodeMapping = null;
        for (di.mappings) |m| {
            if (m.zig_line <= zig_line) {
                if (best == null or m.zig_line > best.?.zig_line) {
                    best = m;
                }
            }
        }

        if (best) |b| {
            return SourceLoc.single(b.py_line, 0);
        }
        return null;
    }

    /// Lookup Zig line from Python line (for breakpoints)
    pub fn pythonToZig(self: *DebugInfoReader, py_line: u32) ?u32 {
        const di = self.debug_info orelse return null;

        for (di.mappings) |m| {
            if (m.py_line == py_line) {
                return m.zig_line;
            }
        }
        return null;
    }

    /// Get symbol at a given line
    pub fn getSymbolAtLine(self: *DebugInfoReader, line: u32) ?Symbol {
        const di = self.debug_info orelse return null;

        // Find innermost symbol containing this line
        var best: ?Symbol = null;
        for (di.symbols) |sym| {
            if (sym.loc.line <= line) {
                if (best == null or sym.loc.line > best.?.loc.line) {
                    best = sym;
                }
            }
        }
        return best;
    }

    /// Check if debug info is valid for given source
    pub fn isValid(self: *DebugInfoReader, source_content: []const u8) bool {
        const di = self.debug_info orelse return false;
        return di.header.source_hash == computeHash(source_content);
    }
};

/// Compute hash of source content for invalidation
fn computeHash(content: []const u8) u64 {
    // FNV-1a hash
    var hash: u64 = 0xcbf29ce484222325;
    for (content) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

// ============================================================================
// Tests
// ============================================================================

test "debug info writer basic" {
    const allocator = std.testing.allocator;

    var writer = DebugInfoWriter.init(allocator, "test.py", "x = 1\ny = 2\n");
    defer writer.deinit();

    // Add module symbol
    const mod_idx = try writer.addSymbol("test", .module, SourceLoc.single(1, 1));
    try writer.enterScope(mod_idx);

    // Add function
    const fn_idx = try writer.addSymbol("main", .function, SourceLoc.single(5, 1));
    try writer.enterScope(fn_idx);

    // Add variable
    _ = try writer.addSymbol("x", .variable, SourceLoc.single(6, 5));

    // Record statements
    try writer.recordStmt(SourceLoc.single(6, 5));
    try writer.recordStmt(SourceLoc.single(7, 5));

    // Record mappings
    try writer.recordMapping(6, 100);
    try writer.recordMapping(7, 105);

    writer.exitScope();
    writer.exitScope();

    // Build and verify
    var info = try writer.build();
    defer info.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 3), info.header.symbol_count);
    try std.testing.expectEqual(@as(u32, 2), info.header.stmt_count);
    try std.testing.expectEqual(@as(u32, 2), info.header.mapping_count);
}

test "debug info json export" {
    const allocator = std.testing.allocator;

    var writer = DebugInfoWriter.init(allocator, "example.py", "def foo(): pass\n");
    defer writer.deinit();

    _ = try writer.addSymbol("foo", .function, SourceLoc.single(1, 1));
    try writer.recordStmt(SourceLoc.single(1, 1));
    try writer.recordMapping(1, 50);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try writer.writeJson(output.writer(allocator));

    const json = output.items;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"sourceFile\": \"example.py\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\": \"foo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"pyLine\": 1") != null);
}

test "debug info hash invalidation" {
    const content1 = "x = 1";
    const content2 = "x = 2";

    const hash1 = computeHash(content1);
    const hash2 = computeHash(content2);

    try std.testing.expect(hash1 != hash2);
    try std.testing.expectEqual(hash1, computeHash(content1)); // Same content = same hash
}
