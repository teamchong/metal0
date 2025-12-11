/// table - Symbol Table
/// Complete symbol table for a module with scope analysis.

const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const entry_mod = @import("entry.zig");

pub const BlockType = types.BlockType;
pub const SymbolFlags = types.SymbolFlags;
pub const SourceLocation = types.SourceLocation;
pub const FutureFeatures = types.FutureFeatures;
pub const SymbolTableEntry = entry_mod.SymbolTableEntry;

// ============================================================================
// Symbol Table
// ============================================================================

/// Complete symbol table for a module
pub const SymbolTable = struct {
    allocator: Allocator,

    // File info
    filename: []const u8,

    // Entries
    top: ?*SymbolTableEntry = null, // Module-level entry
    current: ?*SymbolTableEntry = null, // Currently active entry
    entries: std.AutoHashMap(usize, *SymbolTableEntry), // All entries by ID

    // State
    stack: std.ArrayList(*SymbolTableEntry), // Scope stack
    next_id: usize = 0,

    // Settings
    future: FutureFeatures = .{},
    private: ?[]const u8 = null, // Current class name for mangling

    const Self = @This();

    pub fn init(allocator: Allocator, filename: []const u8) !*Self {
        const table = try allocator.create(Self);
        table.* = .{
            .allocator = allocator,
            .filename = try allocator.dupe(u8, filename),
            .entries = std.AutoHashMap(usize, *SymbolTableEntry).init(allocator),
            .stack = std.ArrayList(*SymbolTableEntry).init(allocator),
        };
        return table;
    }

    pub fn deinit(self: *Self) void {
        // Free all entries
        var it = self.entries.valueIterator();
        while (it.next()) |entry_ptr| {
            entry_ptr.*.deinit();
            self.allocator.destroy(entry_ptr.*);
        }
        self.entries.deinit();

        self.stack.deinit(self.allocator);
        self.allocator.free(self.filename);
        if (self.private) |p| self.allocator.free(p);
        self.allocator.destroy(self);
    }

    /// Enter a new scope
    pub fn enterBlock(
        self: *Self,
        name: []const u8,
        block_type: BlockType,
        location: SourceLocation,
    ) !*SymbolTableEntry {
        const id = self.next_id;
        self.next_id += 1;

        const sym_entry = try SymbolTableEntry.init(self.allocator, name, block_type, id);
        sym_entry.location = location;
        sym_entry.table = self;

        try self.entries.put(id, sym_entry);

        // Add as child of current scope
        if (self.current) |cur| {
            try cur.addChild(sym_entry);
        }

        // Set as top if module
        if (block_type == .module) {
            self.top = sym_entry;
        }

        // Push onto stack
        try self.stack.append(self.allocator, sym_entry);
        self.current = sym_entry;

        return sym_entry;
    }

    /// Exit current scope
    pub fn exitBlock(self: *Self) void {
        if (self.stack.items.len > 0) {
            _ = self.stack.pop();
            self.current = if (self.stack.items.len > 0)
                self.stack.items[self.stack.items.len - 1]
            else
                null;
        }
    }

    /// Lookup entry by ID
    pub fn lookup(self: *Self, id: usize) ?*SymbolTableEntry {
        return self.entries.get(id);
    }

    /// Add a name to current scope
    pub fn addName(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        if (self.current) |cur| {
            try cur.addSymbol(name, flags, location);
        }
    }

    /// Analyze and resolve all scopes
    pub fn analyze(self: *Self) !void {
        if (self.top) |t| {
            try self.analyzeBlock(t, null);
        }
    }

    fn analyzeBlock(self: *Self, sym_entry: *SymbolTableEntry, parent_free: ?*hashmap_helper.StringHashMap(void)) !void {
        // Collect free variables from this scope
        var local_free = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer local_free.deinit(self.allocator);

        // First pass: determine initial scopes
        var it = sym_entry.symbols.iterator();
        while (it.next()) |sym| {
            const name = sym.key_ptr.*;
            const info = sym.value_ptr;

            // Global takes precedence
            if (info.flags.global) {
                info.scope = .global_explicit;
                continue;
            }

            // Nonlocal
            if (info.flags.nonlocal) {
                info.scope = .free;
                try local_free.put(self.allocator, name, {});
                continue;
            }

            // Bound locally
            if (info.flags.isBound()) {
                info.scope = .local;
                continue;
            }

            // Will be resolved later
            info.scope = .unknown;
        }

        // Analyze children first
        for (sym_entry.children.items) |child| {
            try self.analyzeBlock(child, &local_free);
        }

        // Second pass: resolve unknowns and determine cells
        it = sym_entry.symbols.iterator();
        while (it.next()) |sym| {
            const name = sym.key_ptr.*;
            const info = sym.value_ptr;

            if (info.scope == .unknown) {
                // Check if it's free from child
                if (local_free.contains(name)) {
                    info.scope = .cell;
                } else if (parent_free != null and self.lookupInParent(sym_entry, name)) {
                    // It's free in this scope too
                    info.scope = .free;
                    try parent_free.?.put(self.allocator, name, {});
                } else {
                    // Implicit global
                    info.scope = .global_implicit;
                }
            } else if (info.scope == .local and local_free.contains(name)) {
                // Local is also needed by child - make it a cell
                info.scope = .cell;
            }
        }
    }

    fn lookupInParent(self: *Self, sym_entry: *SymbolTableEntry, name: []const u8) bool {
        _ = self;
        var parent = sym_entry.parent;
        while (parent) |p| {
            if (p.symbols.get(name)) |info| {
                if (info.flags.isBound() or info.scope == .cell or info.scope == .free) {
                    return true;
                }
            }
            parent = p.parent;
        }
        return false;
    }

    /// Set the current class name for name mangling
    pub fn setPrivate(self: *Self, class_name: ?[]const u8) !void {
        if (self.private) |p| {
            self.allocator.free(p);
            self.private = null;
        }
        if (class_name) |cn| {
            self.private = try self.allocator.dupe(u8, cn);
        }
    }

    /// Mangle a private name
    pub fn mangleName(self: *Self, name: []const u8) ![]const u8 {
        if (self.private) |class_name| {
            if (name.len >= 2 and std.mem.startsWith(u8, name, "__") and
                !std.mem.endsWith(u8, name, "__"))
            {
                // Strip leading underscores from class name
                var stripped = class_name;
                while (stripped.len > 0 and stripped[0] == '_') {
                    stripped = stripped[1..];
                }
                if (stripped.len > 0) {
                    return std.fmt.allocPrint(self.allocator, "_{s}{s}", .{ class_name, name });
                }
            }
        }
        return self.allocator.dupe(u8, name);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "symbol table scopes" {
    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator, "test.py");
    defer table.deinit();

    // Enter module
    _ = try table.enterBlock("<module>", .module, SourceLocation.NO_LOCATION);

    // Add some module-level names
    try table.addName("global_var", .{ .local = true }, SourceLocation.NO_LOCATION);

    // Enter function
    const func_entry = try table.enterBlock("my_func", .function, SourceLocation.NO_LOCATION);

    // Add function parameters and locals
    try func_entry.addParameter("arg", SourceLocation.NO_LOCATION);
    try table.addName("local_var", .{ .local = true }, SourceLocation.NO_LOCATION);

    // Exit function
    table.exitBlock();

    try std.testing.expect(table.current != null);
    try std.testing.expect(table.top != null);
}

test "name mangling" {
    const allocator = std.testing.allocator;

    const table = try SymbolTable.init(allocator, "test.py");
    defer table.deinit();

    try table.setPrivate("MyClass");

    // Should mangle
    const mangled = try table.mangleName("__private");
    defer allocator.free(mangled);
    try std.testing.expectEqualStrings("_MyClass__private", mangled);

    // Should not mangle (dunder)
    const not_mangled = try table.mangleName("__init__");
    defer allocator.free(not_mangled);
    try std.testing.expectEqualStrings("__init__", not_mangled);

    // Should not mangle (no leading __)
    const public = try table.mangleName("public");
    defer allocator.free(public);
    try std.testing.expectEqualStrings("public", public);
}
