/// builder - Symbol Table Builder
/// Constructs symbol tables from AST with error checking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const table_mod = @import("table.zig");

pub const SymbolFlags = types.SymbolFlags;
pub const SourceLocation = types.SourceLocation;
pub const ErrorMessages = types.ErrorMessages;
pub const SymbolTable = table_mod.SymbolTable;
pub const SymbolTableEntry = table_mod.SymbolTableEntry;

// ============================================================================
// Symbol Table Builder
// ============================================================================

/// Builder for constructing symbol tables from AST
pub const SymbolTableBuilder = struct {
    allocator: Allocator,
    table: *SymbolTable,
    errors: std.ArrayList(Error),

    pub const Error = struct {
        message: []const u8,
        location: SourceLocation,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, filename: []const u8) !Self {
        return .{
            .allocator = allocator,
            .table = try SymbolTable.init(allocator, filename),
            .errors = std.ArrayList(Error).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
    }

    /// Add an error
    pub fn addError(self: *Self, comptime fmt: []const u8, args: anytype, location: SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.errors.append(self.allocator, .{
            .message = message,
            .location = location,
        });
    }

    /// Check for errors
    pub fn hasErrors(self: *Self) bool {
        return self.errors.items.len > 0;
    }

    /// Enter module scope
    pub fn enterModule(self: *Self) !*SymbolTableEntry {
        return self.table.enterBlock("<module>", .module, SourceLocation.NO_LOCATION);
    }

    /// Enter function scope
    pub fn enterFunction(self: *Self, name: []const u8, location: SourceLocation) !*SymbolTableEntry {
        return self.table.enterBlock(name, .function, location);
    }

    /// Enter class scope
    pub fn enterClass(self: *Self, name: []const u8, location: SourceLocation) !*SymbolTableEntry {
        try self.table.setPrivate(name);
        return self.table.enterBlock(name, .class, location);
    }

    /// Exit current scope
    pub fn exitBlock(self: *Self) void {
        if (self.table.current) |cur| {
            if (cur.block_type == .class) {
                self.table.setPrivate(null) catch {};
            }
        }
        self.table.exitBlock();
    }

    /// Add a name binding
    pub fn addDef(self: *Self, name: []const u8, flags: SymbolFlags, location: SourceLocation) !void {
        const sym_entry = self.table.current orelse return;

        // Check for conflicts
        if (sym_entry.symbols.get(name)) |existing| {
            // Check global/param conflict
            if (flags.global and existing.flags.param) {
                try self.addError(ErrorMessages.GLOBAL_PARAM, .{name}, location);
                return;
            }

            // Check nonlocal/param conflict
            if (flags.nonlocal and existing.flags.param) {
                try self.addError(ErrorMessages.NONLOCAL_PARAM, .{name}, location);
                return;
            }

            // Check global after assignment
            if (flags.global and existing.flags.local) {
                try self.addError(ErrorMessages.GLOBAL_AFTER_ASSIGN, .{name}, location);
                return;
            }

            // Check nonlocal after assignment
            if (flags.nonlocal and existing.flags.local) {
                try self.addError(ErrorMessages.NONLOCAL_AFTER_ASSIGN, .{name}, location);
                return;
            }
        }

        try self.table.addName(name, flags, location);
    }

    /// Record a name use
    pub fn addUse(self: *Self, name: []const u8, location: SourceLocation) !void {
        try self.table.addName(name, .{ .used = true }, location);
    }

    /// Add a parameter
    pub fn addParameter(self: *Self, name: []const u8, location: SourceLocation) !void {
        const sym_entry = self.table.current orelse return;

        // Check for duplicate parameter
        for (sym_entry.varnames.items) |existing| {
            if (std.mem.eql(u8, existing, name)) {
                try self.addError(ErrorMessages.DUPLICATE_PARAMETER, .{name}, location);
                return;
            }
        }

        try sym_entry.addParameter(name, location);
    }

    /// Mark current function as generator
    pub fn setGenerator(self: *Self) void {
        if (self.table.current) |sym_entry| {
            sym_entry.generator = true;
        }
    }

    /// Mark current function as coroutine
    pub fn setCoroutine(self: *Self) void {
        if (self.table.current) |sym_entry| {
            sym_entry.coroutine = true;
        }
    }

    /// Finalize and return the symbol table
    pub fn build(self: *Self) !*SymbolTable {
        try self.table.analyze();
        return self.table;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "builder basic" {
    const allocator = std.testing.allocator;

    var builder = try SymbolTableBuilder.init(allocator, "test.py");
    defer builder.deinit();

    _ = try builder.enterModule();

    // Add a function
    _ = try builder.enterFunction("foo", .{ .lineno = 1, .col_offset = 0, .end_lineno = 5, .end_col_offset = 0 });
    try builder.addParameter("x", .{ .lineno = 1, .col_offset = 8 });
    try builder.addDef("y", .{ .local = true }, .{ .lineno = 2 });
    builder.exitBlock();

    const table = try builder.build();
    defer table.deinit();

    try std.testing.expect(!builder.hasErrors());
    try std.testing.expect(table.top != null);
}
