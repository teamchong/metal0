//! Binary plist support - load and dump binary format plists

const std = @import("std");
const types = @import("types.zig");
const hashmap_helper = @import("utils.hashmap_helper");

const PlistValue = types.PlistValue;

// ============================================================================
// Binary Plist Support
// ============================================================================

pub fn loadBinary(allocator: std.mem.Allocator, data: []const u8) !PlistValue {
    // Binary plist format: bplist00 header + objects + offset table + trailer
    if (data.len < 32) return error.InvalidFormat;

    // Check magic header
    if (!std.mem.startsWith(u8, data, "bplist0")) return error.InvalidFormat;

    // Parse trailer (last 32 bytes)
    const trailer = data[data.len - 32 ..];
    // Trailer format: 6 unused bytes, offset_int_size (1), object_ref_size (1),
    //                 num_objects (8), top_object_ref (8), offset_table_offset (8)
    const offset_int_size = trailer[6];
    const object_ref_size = trailer[7];
    const num_objects = std.mem.readInt(u64, trailer[8..16], .big);
    const top_object_ref = std.mem.readInt(u64, trailer[16..24], .big);
    const offset_table_offset = std.mem.readInt(u64, trailer[24..32], .big);

    if (offset_int_size == 0 or offset_int_size > 8) return error.InvalidFormat;
    if (object_ref_size == 0 or object_ref_size > 8) return error.InvalidFormat;
    if (num_objects == 0) return PlistValue{ .dict = hashmap_helper.StringHashMap(PlistValue).init(allocator) };

    // Read offset table
    const offset_table_end = data.len - 32;
    if (offset_table_offset >= offset_table_end) return error.InvalidFormat;

    const offset_table = data[@intCast(offset_table_offset)..offset_table_end];

    // Parse objects
    var objects = try allocator.alloc(PlistValue, @intCast(num_objects));
    defer allocator.free(objects);

    var i: usize = 0;
    while (i < num_objects) : (i += 1) {
        const offset_pos = i * offset_int_size;
        if (offset_pos + offset_int_size > offset_table.len) return error.InvalidFormat;

        const obj_offset = readVarInt(offset_table[offset_pos..], offset_int_size);
        objects[i] = try parseBinaryObject(allocator, data, @intCast(obj_offset), object_ref_size, objects);
    }

    // Return top-level object
    if (top_object_ref >= num_objects) return error.InvalidFormat;
    return objects[@intCast(top_object_ref)];
}

fn readVarInt(data: []const u8, size: u8) u64 {
    var result: u64 = 0;
    for (0..size) |i| {
        result = (result << 8) | data[i];
    }
    return result;
}

fn parseBinaryObject(allocator: std.mem.Allocator, data: []const u8, offset: usize, ref_size: u8, objects: []PlistValue) !PlistValue {
    if (offset >= data.len) return error.InvalidFormat;

    const marker = data[offset];
    const obj_type = marker >> 4;
    const obj_info = marker & 0x0F;

    switch (obj_type) {
        0x0 => {
            // Singleton: null, bool, fill
            switch (obj_info) {
                0x0 => return PlistValue{ .boolean = false }, // null treated as false
                0x8 => return PlistValue{ .boolean = false },
                0x9 => return PlistValue{ .boolean = true },
                else => return PlistValue{ .boolean = false },
            }
        },
        0x1 => {
            // Integer
            const int_size: usize = @as(usize, 1) << @intCast(obj_info);
            if (offset + 1 + int_size > data.len) return error.InvalidFormat;
            const int_data = data[offset + 1 .. offset + 1 + int_size];
            var val: i64 = 0;
            for (int_data) |b| {
                val = (val << 8) | b;
            }
            return PlistValue{ .integer = val };
        },
        0x2 => {
            // Real (float)
            const float_size: usize = @as(usize, 1) << @intCast(obj_info);
            if (offset + 1 + float_size > data.len) return error.InvalidFormat;
            if (float_size == 4) {
                const bits = std.mem.readInt(u32, data[offset + 1 ..][0..4], .big);
                return PlistValue{ .real = @bitCast(bits) };
            } else if (float_size == 8) {
                const bits = std.mem.readInt(u64, data[offset + 1 ..][0..8], .big);
                return PlistValue{ .real = @bitCast(bits) };
            }
            return error.InvalidFormat;
        },
        0x3 => {
            // Date
            if (offset + 9 > data.len) return error.InvalidFormat;
            const bits = std.mem.readInt(u64, data[offset + 1 ..][0..8], .big);
            const timestamp: f64 = @bitCast(bits);
            return PlistValue{ .date = @intFromFloat(timestamp) };
        },
        0x4 => {
            // Data (binary)
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len > data.len) return error.InvalidFormat;
            return PlistValue{ .data = try allocator.dupe(u8, data[start .. start + len]) };
        },
        0x5 => {
            // ASCII string
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len > data.len) return error.InvalidFormat;
            return PlistValue{ .string = try allocator.dupe(u8, data[start .. start + len]) };
        },
        0x6 => {
            // Unicode string (UTF-16BE)
            const len = try getBinaryLength(data, offset, obj_info);
            const start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            if (start + len * 2 > data.len) return error.InvalidFormat;
            // Simplified: just store raw bytes, proper impl would convert UTF-16
            return PlistValue{ .string = try allocator.dupe(u8, data[start .. start + len * 2]) };
        },
        0xA => {
            // Array
            const count = try getBinaryLength(data, offset, obj_info);
            const refs_start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            var items = try allocator.alloc(PlistValue, count);
            for (0..count) |idx| {
                const ref_offset = refs_start + idx * ref_size;
                const ref = readVarInt(data[ref_offset..], ref_size);
                if (ref < objects.len) {
                    items[idx] = objects[ref];
                } else {
                    items[idx] = PlistValue{ .boolean = false };
                }
            }
            return PlistValue{ .array = items };
        },
        0xD => {
            // Dictionary
            const count = try getBinaryLength(data, offset, obj_info);
            const refs_start = offset + 1 + (if (obj_info == 0xF) @as(usize, 1) + (@as(usize, 1) << @intCast(data[offset + 1] & 0xF)) else 0);
            var dict = hashmap_helper.StringHashMap(PlistValue).init(allocator);
            for (0..count) |idx| {
                const key_ref = readVarInt(data[refs_start + idx * ref_size ..], ref_size);
                const val_ref = readVarInt(data[refs_start + (count + idx) * ref_size ..], ref_size);
                if (key_ref < objects.len and val_ref < objects.len) {
                    const key_obj = objects[key_ref];
                    if (key_obj == .string) {
                        try dict.put(try allocator.dupe(u8, key_obj.string), objects[val_ref]);
                    }
                }
            }
            return PlistValue{ .dict = dict };
        },
        else => return PlistValue{ .boolean = false },
    }
}

fn getBinaryLength(data: []const u8, offset: usize, info: u4) !usize {
    if (info != 0xF) return @intCast(info);
    // Extended length
    if (offset + 2 > data.len) return error.InvalidFormat;
    const ext_marker = data[offset + 1];
    const int_type = ext_marker & 0xF;
    const int_size: usize = @as(usize, 1) << @intCast(int_type);
    if (offset + 2 + int_size > data.len) return error.InvalidFormat;
    return @intCast(readVarInt(data[offset + 2 ..], @intCast(int_size)));
}

pub fn dumpBinary(allocator: std.mem.Allocator, value: PlistValue) ![]u8 {
    var result: std.ArrayList(u8) = .{};

    // Magic header
    try result.appendSlice(allocator, "bplist00");

    // Collect all objects for serialization
    var objects: std.ArrayList(PlistValue) = .{};
    defer objects.deinit(allocator);
    try collectObjects(allocator, &objects, value);

    // Write objects and track offsets
    var offsets: std.ArrayList(u64) = .{};
    defer offsets.deinit(allocator);

    for (objects.items) |obj| {
        try offsets.append(allocator, @intCast(result.items.len));
        try writeBinaryObject(allocator, &result, obj);
    }

    // Write offset table
    const offset_table_offset = result.items.len;
    for (offsets.items) |off| {
        try result.append(allocator, @intCast((off >> 24) & 0xFF));
        try result.append(allocator, @intCast((off >> 16) & 0xFF));
        try result.append(allocator, @intCast((off >> 8) & 0xFF));
        try result.append(allocator, @intCast(off & 0xFF));
    }

    // Write trailer
    try result.appendNTimes(allocator, 0, 6); // unused
    try result.append(allocator, 4); // offset int size
    try result.append(allocator, 4); // object ref size
    var writer = result.writer(allocator);
    try writer.writeInt(u64, @intCast(objects.items.len), .big);
    try writer.writeInt(u64, 0, .big); // top object
    try writer.writeInt(u64, @intCast(offset_table_offset), .big);

    return result.toOwnedSlice(allocator);
}

fn collectObjects(allocator: std.mem.Allocator, objects: *std.ArrayList(PlistValue), value: PlistValue) !void {
    try objects.append(allocator, value);
    switch (value) {
        .array => |arr| {
            for (arr) |item| try collectObjects(allocator, objects, item);
        },
        .dict => |dict| {
            var it = dict.iterator();
            while (it.next()) |entry| {
                try objects.append(allocator, PlistValue{ .string = entry.key_ptr.* });
                try collectObjects(allocator, objects, entry.value_ptr.*);
            }
        },
        else => {},
    }
}

fn writeBinaryObject(allocator: std.mem.Allocator, result: *std.ArrayList(u8), obj: PlistValue) !void {
    switch (obj) {
        .boolean => |b| try result.append(allocator, if (b) 0x09 else 0x08),
        .integer => |i| {
            try result.append(allocator, 0x10); // 1-byte int
            try result.append(allocator, @intCast(@as(u8, @truncate(@as(u64, @bitCast(i))))));
        },
        .real => |r| {
            try result.append(allocator, 0x23); // 8-byte float
            var writer = result.writer(allocator);
            try writer.writeInt(u64, @bitCast(r), .big);
        },
        .string => |s| {
            if (s.len < 15) {
                try result.append(allocator, 0x50 | @as(u8, @intCast(s.len)));
            } else {
                try result.append(allocator, 0x5F);
                try result.append(allocator, 0x10);
                try result.append(allocator, @intCast(s.len));
            }
            try result.appendSlice(allocator, s);
        },
        .data => |d| {
            if (d.len < 15) {
                try result.append(allocator, 0x40 | @as(u8, @intCast(d.len)));
            } else {
                try result.append(allocator, 0x4F);
                try result.append(allocator, 0x10);
                try result.append(allocator, @intCast(d.len));
            }
            try result.appendSlice(allocator, d);
        },
        .date => |timestamp| {
            try result.append(allocator, 0x33);
            const f: f64 = @floatFromInt(timestamp);
            var writer = result.writer(allocator);
            try writer.writeInt(u64, @bitCast(f), .big);
        },
        .array => |arr| {
            if (arr.len < 15) {
                try result.append(allocator, 0xA0 | @as(u8, @intCast(arr.len)));
            } else {
                try result.append(allocator, 0xAF);
                try result.append(allocator, 0x10);
                try result.append(allocator, @intCast(arr.len));
            }
            // Object refs would go here - simplified
        },
        .dict => |dict| {
            const count = dict.count();
            if (count < 15) {
                try result.append(allocator, 0xD0 | @as(u8, @intCast(count)));
            } else {
                try result.append(allocator, 0xDF);
                try result.append(allocator, 0x10);
                try result.append(allocator, @intCast(count));
            }
            // Key/value refs would go here - simplified
        },
        .uid => |u| {
            try result.append(allocator, 0x80);
            try result.append(allocator, @intCast(u.data & 0xFF));
        },
    }
}
