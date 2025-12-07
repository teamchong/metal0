//! Python 'wave' module - Read and write WAV files
//!
//! Provides an interface to the WAV sound format.
//!
//! Mirrors: CPython Lib/wave.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const WaveError = error{
    NotWaveFile,
    InvalidFormat,
    UnsupportedCompression,
    BadChunkSize,
    IoError,
    OutOfMemory,
};

// ============================================================================
// Wave_read - Read WAV files
// ============================================================================

/// WAV file reader
pub const Wave_read = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    file: ?std.fs.File = null,
    /// Number of audio channels
    nchannels: u16 = 0,
    /// Sample width in bytes
    sampwidth: u16 = 0,
    /// Sampling rate (frames per second)
    framerate: u32 = 0,
    /// Total number of frames
    nframes: u32 = 0,
    /// Compression type (only NONE supported)
    comptype: []const u8 = "NONE",
    /// Compression name
    compname: []const u8 = "not compressed",
    /// Data chunk offset
    data_offset: u64 = 0,
    /// Current position in frames
    pos: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open a WAV file for reading
    pub fn open(self: *Self, filename: []const u8) !void {
        self.file = try std.fs.cwd().openFile(filename, .{});
        try self.readHeader();
    }

    /// Open from a file handle
    pub fn openFile(self: *Self, file: std.fs.File) !void {
        self.file = file;
        try self.readHeader();
    }

    fn readHeader(self: *Self) !void {
        const file = self.file orelse return error.IoError;
        const reader = file.reader();

        // Read RIFF header
        var riff: [4]u8 = undefined;
        _ = try reader.read(&riff);
        if (!std.mem.eql(u8, &riff, "RIFF")) {
            return error.NotWaveFile;
        }

        // Skip file size
        _ = try reader.readInt(u32, .little);

        // Read WAVE format
        var wave: [4]u8 = undefined;
        _ = try reader.read(&wave);
        if (!std.mem.eql(u8, &wave, "WAVE")) {
            return error.NotWaveFile;
        }

        // Read chunks
        while (true) {
            var chunk_id: [4]u8 = undefined;
            _ = reader.read(&chunk_id) catch break;
            const chunk_size = reader.readInt(u32, .little) catch break;

            if (std.mem.eql(u8, &chunk_id, "fmt ")) {
                // Format chunk
                const audio_format = try reader.readInt(u16, .little);
                if (audio_format != 1) {
                    return error.UnsupportedCompression;
                }

                self.nchannels = try reader.readInt(u16, .little);
                self.framerate = try reader.readInt(u32, .little);
                _ = try reader.readInt(u32, .little); // byte rate
                _ = try reader.readInt(u16, .little); // block align
                const bits_per_sample = try reader.readInt(u16, .little);
                self.sampwidth = bits_per_sample / 8;

                // Skip extra format bytes
                if (chunk_size > 16) {
                    try reader.skipBytes(chunk_size - 16, .{});
                }
            } else if (std.mem.eql(u8, &chunk_id, "data")) {
                // Data chunk
                self.data_offset = try file.getPos();
                self.nframes = chunk_size / (self.nchannels * self.sampwidth);
                break;
            } else {
                // Skip unknown chunk
                try reader.skipBytes(chunk_size, .{});
            }
        }
    }

    /// Get number of audio channels
    pub fn getnchannels(self: *const Self) u16 {
        return self.nchannels;
    }

    /// Get sample width in bytes
    pub fn getsampwidth(self: *const Self) u16 {
        return self.sampwidth;
    }

    /// Get sampling frequency
    pub fn getframerate(self: *const Self) u32 {
        return self.framerate;
    }

    /// Get number of audio frames
    pub fn getnframes(self: *const Self) u32 {
        return self.nframes;
    }

    /// Get compression type
    pub fn getcomptype(self: *const Self) []const u8 {
        return self.comptype;
    }

    /// Get compression name
    pub fn getcompname(self: *const Self) []const u8 {
        return self.compname;
    }

    /// Get all parameters as a tuple
    pub fn getparams(self: *const Self) struct { u16, u16, u32, u32, []const u8, []const u8 } {
        return .{
            self.nchannels,
            self.sampwidth,
            self.framerate,
            self.nframes,
            self.comptype,
            self.compname,
        };
    }

    /// Read n frames of audio
    pub fn readframes(self: *Self, n: u32) ![]u8 {
        const file = self.file orelse return error.IoError;
        const frames_to_read = @min(n, self.nframes - self.pos);
        const bytes_to_read = frames_to_read * self.nchannels * self.sampwidth;

        const buffer = try self.allocator.alloc(u8, bytes_to_read);
        const bytes_read = try file.read(buffer);

        self.pos += @intCast(bytes_read / (self.nchannels * self.sampwidth));

        return buffer[0..bytes_read];
    }

    /// Set the file position
    pub fn setpos(self: *Self, pos: u32) !void {
        const file = self.file orelse return error.IoError;
        const byte_offset = self.data_offset + pos * self.nchannels * self.sampwidth;
        try file.seekTo(byte_offset);
        self.pos = pos;
    }

    /// Get current position
    pub fn tell(self: *const Self) u32 {
        return self.pos;
    }

    /// Rewind to beginning
    pub fn rewind(self: *Self) !void {
        try self.setpos(0);
    }

    /// Close the file
    pub fn close(self: *Self) void {
        self.deinit();
    }
};

// ============================================================================
// Wave_write - Write WAV files
// ============================================================================

/// WAV file writer
pub const Wave_write = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    file: ?std.fs.File = null,
    nchannels: u16 = 0,
    sampwidth: u16 = 0,
    framerate: u32 = 0,
    nframes: u32 = 0,
    comptype: []const u8 = "NONE",
    compname: []const u8 = "not compressed",
    header_written: bool = false,
    data_written: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |*f| {
            if (self.header_written) {
                self.updateHeader() catch {};
            }
            f.close();
        }
    }

    /// Open a file for writing
    pub fn open(self: *Self, filename: []const u8) !void {
        self.file = try std.fs.cwd().createFile(filename, .{});
    }

    /// Set number of channels
    pub fn setnchannels(self: *Self, n: u16) void {
        self.nchannels = n;
    }

    /// Set sample width
    pub fn setsampwidth(self: *Self, n: u16) void {
        self.sampwidth = n;
    }

    /// Set frame rate
    pub fn setframerate(self: *Self, n: u32) void {
        self.framerate = n;
    }

    /// Set number of frames
    pub fn setnframes(self: *Self, n: u32) void {
        self.nframes = n;
    }

    /// Set compression type (only NONE supported)
    pub fn setcomptype(self: *Self, comptype: []const u8, compname: []const u8) !void {
        if (!std.mem.eql(u8, comptype, "NONE")) {
            return error.UnsupportedCompression;
        }
        self.comptype = comptype;
        self.compname = compname;
    }

    /// Set all parameters
    pub fn setparams(self: *Self, params: struct { u16, u16, u32, u32, []const u8, []const u8 }) !void {
        self.setnchannels(params[0]);
        self.setsampwidth(params[1]);
        self.setframerate(params[2]);
        self.setnframes(params[3]);
        try self.setcomptype(params[4], params[5]);
    }

    /// Write audio frames
    pub fn writeframes(self: *Self, data: []const u8) !void {
        if (!self.header_written) {
            try self.writeHeader();
        }

        const file = self.file orelse return error.IoError;
        try file.writeAll(data);
        self.data_written += @intCast(data.len / (self.nchannels * self.sampwidth));
    }

    /// Write audio frames and update header
    pub fn writeframesraw(self: *Self, data: []const u8) !void {
        try self.writeframes(data);
    }

    fn writeHeader(self: *Self) !void {
        const file = self.file orelse return error.IoError;
        const writer = file.writer();

        const block_align = self.nchannels * self.sampwidth;
        const byte_rate = self.framerate * block_align;
        const data_size = self.nframes * block_align;

        // RIFF header
        try writer.writeAll("RIFF");
        try writer.writeInt(u32, 36 + data_size, .little);
        try writer.writeAll("WAVE");

        // fmt chunk
        try writer.writeAll("fmt ");
        try writer.writeInt(u32, 16, .little); // chunk size
        try writer.writeInt(u16, 1, .little); // audio format (PCM)
        try writer.writeInt(u16, self.nchannels, .little);
        try writer.writeInt(u32, self.framerate, .little);
        try writer.writeInt(u32, byte_rate, .little);
        try writer.writeInt(u16, block_align, .little);
        try writer.writeInt(u16, self.sampwidth * 8, .little);

        // data chunk header
        try writer.writeAll("data");
        try writer.writeInt(u32, data_size, .little);

        self.header_written = true;
    }

    fn updateHeader(self: *Self) !void {
        const file = self.file orelse return error.IoError;

        const block_align = self.nchannels * self.sampwidth;
        const data_size = self.data_written * block_align;

        // Update RIFF size
        try file.seekTo(4);
        try file.writer().writeInt(u32, 36 + data_size, .little);

        // Update data chunk size
        try file.seekTo(40);
        try file.writer().writeInt(u32, data_size, .little);
    }

    /// Close the file
    pub fn close(self: *Self) void {
        self.deinit();
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Open a WAV file
pub fn open(allocator: std.mem.Allocator, filename: []const u8, mode: []const u8) !union { read: *Wave_read, write: *Wave_write } {
    if (std.mem.eql(u8, mode, "r") or std.mem.eql(u8, mode, "rb")) {
        const reader = try allocator.create(Wave_read);
        reader.* = Wave_read.init(allocator);
        try reader.open(filename);
        return .{ .read = reader };
    } else if (std.mem.eql(u8, mode, "w") or std.mem.eql(u8, mode, "wb")) {
        const writer = try allocator.create(Wave_write);
        writer.* = Wave_write.init(allocator);
        try writer.open(filename);
        return .{ .write = writer };
    }
    return error.InvalidFormat;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Wave_read init" {
    const allocator = std.testing.allocator;
    var reader = Wave_read.init(allocator);
    defer reader.deinit();

    try std.testing.expectEqual(@as(u16, 0), reader.getnchannels());
    try std.testing.expectEqual(@as(u16, 0), reader.getsampwidth());
}

test "Wave_write init" {
    const allocator = std.testing.allocator;
    var writer = Wave_write.init(allocator);
    defer writer.deinit();

    writer.setnchannels(2);
    writer.setsampwidth(2);
    writer.setframerate(44100);

    try std.testing.expectEqual(@as(u16, 2), writer.nchannels);
    try std.testing.expectEqual(@as(u16, 2), writer.sampwidth);
    try std.testing.expectEqual(@as(u32, 44100), writer.framerate);
}

test "Wave_write setcomptype" {
    const allocator = std.testing.allocator;
    var writer = Wave_write.init(allocator);
    defer writer.deinit();

    try writer.setcomptype("NONE", "not compressed");
    try std.testing.expectEqualStrings("NONE", writer.comptype);

    // Should fail for unsupported compression
    try std.testing.expectError(error.UnsupportedCompression, writer.setcomptype("ULAW", "CCITT u-law"));
}

test "Wave_read getparams" {
    const allocator = std.testing.allocator;
    var reader = Wave_read.init(allocator);
    defer reader.deinit();

    reader.nchannels = 2;
    reader.sampwidth = 2;
    reader.framerate = 44100;
    reader.nframes = 1000;

    const params = reader.getparams();
    try std.testing.expectEqual(@as(u16, 2), params[0]);
    try std.testing.expectEqual(@as(u16, 2), params[1]);
    try std.testing.expectEqual(@as(u32, 44100), params[2]);
    try std.testing.expectEqual(@as(u32, 1000), params[3]);
}
