/// DWARF Debug Info Emitter
///
/// Generates DWARF debug sections for metal0 compiled binaries.
/// Focus on .debug_line for line number info (enables step debugging).
///
/// DWARF 5 format: https://dwarfstd.org/doc/DWARF5.pdf
///
const std = @import("std");
const debug_info = @import("debug_info.zig");

/// DWARF line number program opcodes (standard)
const DW_LNS = struct {
    const copy: u8 = 1;
    const advance_pc: u8 = 2;
    const advance_line: u8 = 3;
    const set_file: u8 = 4;
    const set_column: u8 = 5;
    const negate_stmt: u8 = 6;
    const set_basic_block: u8 = 7;
    const const_add_pc: u8 = 8;
    const fixed_advance_pc: u8 = 9;
    const set_prologue_end: u8 = 10;
    const set_epilogue_begin: u8 = 11;
    const set_isa: u8 = 12;
};

/// Extended opcodes
const DW_LNE = struct {
    const end_sequence: u8 = 1;
    const set_address: u8 = 2;
    const define_file: u8 = 3;
    const set_discriminator: u8 = 4;
};

/// Line number info header (DWARF 5)
pub const LineNumberHeader = struct {
    unit_length: u32 = 0, // Will be filled in
    version: u16 = 5,
    address_size: u8 = 8, // 64-bit
    segment_selector_size: u8 = 0,
    header_length: u32 = 0, // Will be filled in
    minimum_instruction_length: u8 = 1,
    maximum_ops_per_instruction: u8 = 1,
    default_is_stmt: u8 = 1,
    line_base: i8 = -5,
    line_range: u8 = 14,
    opcode_base: u8 = 13,
};

/// A line number entry in the program
pub const LineEntry = struct {
    address: u64,
    file: u32,
    line: u32,
    column: u32 = 0,
    is_stmt: bool = true,
    basic_block: bool = false,
    end_sequence: bool = false,
    prologue_end: bool = false,
    epilogue_begin: bool = false,
};

/// DWARF Line Number Program Emitter
pub const DwarfLineEmitter = struct {
    allocator: std.mem.Allocator,

    /// Output buffer for .debug_line section
    output: std.ArrayList(u8),

    /// Source files table
    files: std.ArrayList([]const u8),

    /// Include directories table
    directories: std.ArrayList([]const u8),

    /// Line number entries
    entries: std.ArrayList(LineEntry),

    /// Current state machine registers
    address: u64 = 0,
    file: u32 = 1,
    line: u32 = 1,
    column: u32 = 0,
    is_stmt: bool = true,

    pub fn init(allocator: std.mem.Allocator) DwarfLineEmitter {
        return .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .files = std.ArrayList([]const u8){},
            .directories = std.ArrayList([]const u8){},
            .entries = std.ArrayList(LineEntry){},
        };
    }

    pub fn deinit(self: *DwarfLineEmitter) void {
        self.output.deinit(self.allocator);
        for (self.files.items) |f| self.allocator.free(f);
        self.files.deinit(self.allocator);
        for (self.directories.items) |d| self.allocator.free(d);
        self.directories.deinit(self.allocator);
        self.entries.deinit(self.allocator);
    }

    /// Add a source file to the file table
    pub fn addFile(self: *DwarfLineEmitter, path: []const u8) !u32 {
        const idx: u32 = @intCast(self.files.items.len + 1); // 1-indexed
        const copy = try self.allocator.dupe(u8, path);
        try self.files.append(self.allocator, copy);
        return idx;
    }

    /// Add a directory to the directory table
    pub fn addDirectory(self: *DwarfLineEmitter, path: []const u8) !u32 {
        const idx: u32 = @intCast(self.directories.items.len);
        const copy = try self.allocator.dupe(u8, path);
        try self.directories.append(self.allocator, copy);
        return idx;
    }

    /// Add a line number entry
    pub fn addLine(self: *DwarfLineEmitter, entry: LineEntry) !void {
        try self.entries.append(self.allocator, entry);
    }

    /// Generate DWARF .debug_line section from Python->Zig mappings
    pub fn generateFromMappings(
        self: *DwarfLineEmitter,
        source_file: []const u8,
        mappings: []const debug_info.CodeMapping,
        base_address: u64,
    ) !void {
        // Add the source file
        const file_idx = try self.addFile(source_file);

        // Convert mappings to line entries
        // Note: We use Python lines since that's what the user cares about
        for (mappings) |m| {
            try self.addLine(.{
                .address = base_address + @as(u64, m.zig_line) * 4, // Approximate: 4 bytes per "line"
                .file = file_idx,
                .line = m.py_line,
                .is_stmt = true,
            });
        }

        // Add end sequence
        if (self.entries.items.len > 0) {
            const last = self.entries.items[self.entries.items.len - 1];
            try self.addLine(.{
                .address = last.address + 4,
                .file = file_idx,
                .line = last.line,
                .end_sequence = true,
            });
        }
    }

    /// Emit the complete .debug_line section
    pub fn emit(self: *DwarfLineEmitter) ![]const u8 {
        // Clear output buffer
        self.output.clearRetainingCapacity();

        // Build header
        const header_start = self.output.items.len;

        // unit_length placeholder (4 bytes)
        try self.emitU32(0);
        const after_length = self.output.items.len;

        // version (2 bytes) - DWARF 5
        try self.emitU16(5);

        // address_size (1 byte)
        try self.emitU8(8);

        // segment_selector_size (1 byte)
        try self.emitU8(0);

        // header_length placeholder (4 bytes)
        const header_length_pos = self.output.items.len;
        try self.emitU32(0);
        const after_header_length = self.output.items.len;

        // minimum_instruction_length (1 byte)
        try self.emitU8(1);

        // maximum_operations_per_instruction (1 byte)
        try self.emitU8(1);

        // default_is_stmt (1 byte)
        try self.emitU8(1);

        // line_base (1 byte signed)
        try self.emitI8(-5);

        // line_range (1 byte)
        try self.emitU8(14);

        // opcode_base (1 byte)
        try self.emitU8(13);

        // standard_opcode_lengths (opcode_base - 1 entries)
        const std_opcode_lengths = [_]u8{ 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1 };
        try self.output.appendSlice(self.allocator, &std_opcode_lengths);

        // directory_entry_format_count (DWARF 5)
        try self.emitU8(1);
        // DW_LNCT_path, DW_FORM_string
        try self.emitULEB128(1); // DW_LNCT_path
        try self.emitULEB128(8); // DW_FORM_string

        // directories_count
        try self.emitULEB128(@intCast(self.directories.items.len + 1)); // +1 for implicit current dir

        // Current directory (empty string for ".")
        try self.emitString(".");

        // Additional directories
        for (self.directories.items) |dir| {
            try self.emitString(dir);
        }

        // file_name_entry_format_count (DWARF 5)
        try self.emitU8(2);
        // DW_LNCT_path, DW_FORM_string
        try self.emitULEB128(1); // DW_LNCT_path
        try self.emitULEB128(8); // DW_FORM_string
        // DW_LNCT_directory_index, DW_FORM_udata
        try self.emitULEB128(2); // DW_LNCT_directory_index
        try self.emitULEB128(15); // DW_FORM_udata

        // file_names_count
        try self.emitULEB128(@intCast(self.files.items.len));

        // File entries
        for (self.files.items) |file| {
            try self.emitString(file);
            try self.emitULEB128(0); // directory index (0 = current)
        }

        // Fix up header_length
        const header_end = self.output.items.len;
        const header_length: u32 = @intCast(header_end - after_header_length);
        std.mem.writeInt(u32, self.output.items[header_length_pos..][0..4], header_length, .little);

        // Emit line number program
        try self.emitLineProgram();

        // Fix up unit_length
        const unit_length: u32 = @intCast(self.output.items.len - after_length);
        std.mem.writeInt(u32, self.output.items[header_start..][0..4], unit_length, .little);

        return self.output.items;
    }

    /// Emit the line number program bytecode
    fn emitLineProgram(self: *DwarfLineEmitter) !void {
        // Reset state machine
        self.address = 0;
        self.file = 1;
        self.line = 1;
        self.column = 0;
        self.is_stmt = true;

        for (self.entries.items) |entry| {
            // Handle end sequence
            if (entry.end_sequence) {
                // Extended opcode: end_sequence
                try self.emitU8(0); // Extended opcode marker
                try self.emitULEB128(1); // Length
                try self.emitU8(DW_LNE.end_sequence);

                // Reset state
                self.address = 0;
                self.file = 1;
                self.line = 1;
                continue;
            }

            // Set address if first entry or big jump
            if (self.address == 0 or entry.address < self.address) {
                try self.emitSetAddress(entry.address);
            } else if (entry.address > self.address) {
                // Advance PC
                const delta = entry.address - self.address;
                try self.emitAdvancePC(delta);
            }

            // Set file if changed
            if (entry.file != self.file) {
                try self.emitU8(DW_LNS.set_file);
                try self.emitULEB128(entry.file);
                self.file = entry.file;
            }

            // Advance line
            if (entry.line != self.line) {
                const line_delta: i64 = @as(i64, @intCast(entry.line)) - @as(i64, @intCast(self.line));
                try self.emitAdvanceLine(line_delta);
            }

            // Set column if non-zero
            if (entry.column != self.column and entry.column > 0) {
                try self.emitU8(DW_LNS.set_column);
                try self.emitULEB128(entry.column);
                self.column = entry.column;
            }

            // Emit copy (creates a row in the line table)
            try self.emitU8(DW_LNS.copy);
        }
    }

    /// Emit set_address extended opcode
    fn emitSetAddress(self: *DwarfLineEmitter, address: u64) !void {
        try self.emitU8(0); // Extended opcode marker
        try self.emitULEB128(9); // Length: 1 (opcode) + 8 (address)
        try self.emitU8(DW_LNE.set_address);
        try self.emitU64(address);
        self.address = address;
    }

    /// Emit advance_pc opcode
    fn emitAdvancePC(self: *DwarfLineEmitter, delta: u64) !void {
        try self.emitU8(DW_LNS.advance_pc);
        try self.emitULEB128(delta);
        self.address += delta;
    }

    /// Emit advance_line opcode
    fn emitAdvanceLine(self: *DwarfLineEmitter, delta: i64) !void {
        try self.emitU8(DW_LNS.advance_line);
        try self.emitSLEB128(delta);
        self.line = @intCast(@as(i64, @intCast(self.line)) + delta);
    }

    // Low-level emit helpers

    fn emitU8(self: *DwarfLineEmitter, val: u8) !void {
        try self.output.append(self.allocator, val);
    }

    fn emitI8(self: *DwarfLineEmitter, val: i8) !void {
        try self.output.append(self.allocator, @bitCast(val));
    }

    fn emitU16(self: *DwarfLineEmitter, val: u16) !void {
        try self.output.appendSlice(self.allocator, &std.mem.toBytes(std.mem.nativeToLittle(u16, val)));
    }

    fn emitU32(self: *DwarfLineEmitter, val: u32) !void {
        try self.output.appendSlice(self.allocator, &std.mem.toBytes(std.mem.nativeToLittle(u32, val)));
    }

    fn emitU64(self: *DwarfLineEmitter, val: u64) !void {
        try self.output.appendSlice(self.allocator, &std.mem.toBytes(std.mem.nativeToLittle(u64, val)));
    }

    fn emitString(self: *DwarfLineEmitter, str: []const u8) !void {
        try self.output.appendSlice(self.allocator, str);
        try self.output.append(self.allocator, 0); // null terminator
    }

    fn emitULEB128(self: *DwarfLineEmitter, val: u64) !void {
        var value = val;
        while (true) {
            var byte: u8 = @truncate(value & 0x7f);
            value >>= 7;
            if (value != 0) {
                byte |= 0x80; // More bytes follow
            }
            try self.output.append(self.allocator, byte);
            if (value == 0) break;
        }
    }

    fn emitSLEB128(self: *DwarfLineEmitter, val: i64) !void {
        var value = val;
        var more = true;
        while (more) {
            var byte: u8 = @truncate(@as(u64, @bitCast(value)) & 0x7f);
            value >>= 7;

            // Check if more bytes needed
            if ((value == 0 and (byte & 0x40) == 0) or
                (value == -1 and (byte & 0x40) != 0))
            {
                more = false;
            } else {
                byte |= 0x80;
            }
            try self.output.append(self.allocator, byte);
        }
    }
};

/// Write DWARF sections to an ELF/Mach-O object file
/// This is a simplified version - real implementation would need to handle
/// the specific object file format
pub fn writeDwarfToFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    source_file: []const u8,
    mappings: []const debug_info.CodeMapping,
) !void {
    var emitter = DwarfLineEmitter.init(allocator);
    defer emitter.deinit();

    try emitter.generateFromMappings(source_file, mappings, 0x1000);
    const debug_line = try emitter.emit();

    // Write raw .debug_line section to file
    // In practice, this would be embedded in the binary via linker
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(debug_line);
}

// ============================================================================
// Tests
// ============================================================================

test "DWARF line emitter basic" {
    const allocator = std.testing.allocator;

    var emitter = DwarfLineEmitter.init(allocator);
    defer emitter.deinit();

    const file_idx = try emitter.addFile("test.py");
    try std.testing.expectEqual(@as(u32, 1), file_idx);

    try emitter.addLine(.{ .address = 0x1000, .file = 1, .line = 1 });
    try emitter.addLine(.{ .address = 0x1010, .file = 1, .line = 5 });
    try emitter.addLine(.{ .address = 0x1020, .file = 1, .line = 10, .end_sequence = true });

    const debug_line = try emitter.emit();

    // Should have produced some output
    try std.testing.expect(debug_line.len > 0);

    // Check DWARF 5 version
    try std.testing.expectEqual(@as(u16, 5), std.mem.readInt(u16, debug_line[4..6], .little));
}

test "DWARF from mappings" {
    const allocator = std.testing.allocator;

    const mappings = [_]debug_info.CodeMapping{
        .{ .py_line = 1, .zig_line = 10 },
        .{ .py_line = 5, .zig_line = 20 },
        .{ .py_line = 10, .zig_line = 30 },
    };

    var emitter = DwarfLineEmitter.init(allocator);
    defer emitter.deinit();

    try emitter.generateFromMappings("example.py", &mappings, 0x1000);
    const debug_line = try emitter.emit();

    try std.testing.expect(debug_line.len > 0);
}

test "ULEB128 encoding" {
    const allocator = std.testing.allocator;

    var emitter = DwarfLineEmitter.init(allocator);
    defer emitter.deinit();

    // Test small value
    try emitter.emitULEB128(0);
    try std.testing.expectEqual(@as(u8, 0), emitter.output.items[0]);

    emitter.output.clearRetainingCapacity();

    // Test value requiring multiple bytes
    try emitter.emitULEB128(300);
    try std.testing.expectEqual(@as(usize, 2), emitter.output.items.len);
    try std.testing.expectEqual(@as(u8, 0xac), emitter.output.items[0]);
    try std.testing.expectEqual(@as(u8, 0x02), emitter.output.items[1]);
}
