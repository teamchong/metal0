//! email.iterators - Various email iterators
//! Reference: cpython/Lib/email/iterators.py
//!
//! CPython __all__: ['body_line_iterator', 'typed_subpart_iterator', 'walk']

const std = @import("std");
const Message = @import("message.zig").Message;
const MessageIterator = @import("message.zig").MessageIterator;

// Re-export walk from message module (DRY)
pub const walk = Message.walk;

/// Iterate over all text lines in a message body
/// CPython: def body_line_iterator(msg, decode=False)
pub fn body_line_iterator(msg: *const Message) BodyLineIterator {
    return BodyLineIterator.init(msg);
}

/// Iterate over all subparts of a specific type
/// CPython: def typed_subpart_iterator(msg, maintype='text', subtype=None)
pub fn typed_subpart_iterator(msg: *Message, maintype: []const u8, subtype: ?[]const u8) TypedSubpartIterator {
    return TypedSubpartIterator.init(msg, maintype, subtype);
}

/// Iterator over body lines
pub const BodyLineIterator = struct {
    payload: ?[]const u8,
    pos: usize = 0,

    pub fn init(msg: *const Message) BodyLineIterator {
        return .{ .payload = msg.getPayload() };
    }

    pub fn next(self: *BodyLineIterator) ?[]const u8 {
        const payload = self.payload orelse return null;
        if (self.pos >= payload.len) return null;

        // Find end of line
        var end = self.pos;
        while (end < payload.len and payload[end] != '\n') {
            end += 1;
        }

        const line = payload[self.pos..end];
        self.pos = if (end < payload.len) end + 1 else payload.len;

        return line;
    }
};

/// Iterator over typed subparts
pub const TypedSubpartIterator = struct {
    walker: MessageIterator,
    maintype: []const u8,
    subtype: ?[]const u8,

    pub fn init(msg: *Message, maintype: []const u8, subtype: ?[]const u8) TypedSubpartIterator {
        return .{
            .walker = msg.walk(),
            .maintype = maintype,
            .subtype = subtype,
        };
    }

    pub fn deinit(self: *TypedSubpartIterator) void {
        self.walker.deinit();
    }

    pub fn next(self: *TypedSubpartIterator) ?*Message {
        while (self.walker.next()) |part| {
            const main = part.getContentMainType();
            if (!std.mem.eql(u8, main, self.maintype)) continue;

            if (self.subtype) |sub| {
                const part_sub = part.getContentSubtype();
                if (!std.mem.eql(u8, part_sub, sub)) continue;
            }

            return part;
        }
        return null;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Get all payloads from a message tree
pub fn _structure(msg: *Message, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};
    var walker = msg.walk();
    defer walker.deinit();

    while (walker.next()) |part| {
        try result.append(allocator, part.getContentType());
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "BodyLineIterator" {
    const allocator = std.testing.allocator;
    var msg = Message.init(allocator);
    defer msg.deinit();

    try msg.setPayload("Line 1\nLine 2\nLine 3");

    var iter = body_line_iterator(&msg);
    try std.testing.expectEqualStrings("Line 1", iter.next().?);
    try std.testing.expectEqualStrings("Line 2", iter.next().?);
    try std.testing.expectEqualStrings("Line 3", iter.next().?);
    try std.testing.expect(iter.next() == null);
}
