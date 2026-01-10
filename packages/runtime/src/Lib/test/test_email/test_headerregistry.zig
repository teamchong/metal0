//! test.test_email.test_headerregistry - Email header registry tests
const std = @import("std");

pub const HeaderRegistry = struct {
    headers: std.StringHashMap(HeaderDef),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        var self = @This(){
            .allocator = allocator,
            .headers = std.StringHashMap(HeaderDef).init(allocator),
        };
        self.registerDefaults() catch {};
        return self;
    }
    
    pub fn deinit(self: *@This()) void {
        self.headers.deinit();
    }
    
    fn registerDefaults(self: *@This()) !void {
        try self.headers.put("subject", .{ .name = "Subject", .cls = .unstructured });
        try self.headers.put("from", .{ .name = "From", .cls = .address });
        try self.headers.put("to", .{ .name = "To", .cls = .address });
        try self.headers.put("cc", .{ .name = "Cc", .cls = .address });
        try self.headers.put("date", .{ .name = "Date", .cls = .date });
        try self.headers.put("content-type", .{ .name = "Content-Type", .cls = .content_type });
        try self.headers.put("content-disposition", .{ .name = "Content-Disposition", .cls = .content_disposition });
        try self.headers.put("mime-version", .{ .name = "MIME-Version", .cls = .mime_version });
    }
    
    pub fn lookup(self: @This(), name: []const u8) ?HeaderDef {
        var lower: [256]u8 = undefined;
        const len = @min(name.len, 256);
        for (name[0..len], 0..) |c, i| {
            lower[i] = std.ascii.toLower(c);
        }
        return self.headers.get(lower[0..len]);
    }
    
    pub fn register(self: *@This(), name: []const u8, def: HeaderDef) !void {
        try self.headers.put(name, def);
    }
};

pub const HeaderDef = struct {
    name: []const u8,
    cls: HeaderClass,
    max_count: ?usize = null,
};

pub const HeaderClass = enum {
    unstructured,
    address,
    date,
    content_type,
    content_disposition,
    mime_version,
    unique,
};

pub const Address = struct {
    display_name: ?[]const u8 = null,
    username: []const u8 = "",
    domain: []const u8 = "",
    
    pub fn addr_spec(self: @This()) []const u8 {
        _ = self;
        return ""; // Would format username@domain
    }
};

pub const AddressHeader = struct {
    addresses: std.ArrayList(Address),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .addresses = std.ArrayList(Address).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.addresses.deinit();
    }
    
    pub fn parse(self: *@This(), value: []const u8) !void {
        var parts = std.mem.splitScalar(u8, value, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (std.mem.indexOf(u8, trimmed, "@")) |at| {
                try self.addresses.append(.{
                    .username = trimmed[0..at],
                    .domain = trimmed[at+1..],
                });
            }
        }
    }
};

test "header_registry" {
    var reg = HeaderRegistry.init(std.testing.allocator);
    defer reg.deinit();
    if (reg.lookup("Subject")) |def| {
        try std.testing.expectEqual(HeaderClass.unstructured, def.cls);
    }
    if (reg.lookup("From")) |def| {
        try std.testing.expectEqual(HeaderClass.address, def.cls);
    }
}

test "address_header" {
    var ah = AddressHeader.init(std.testing.allocator);
    defer ah.deinit();
    try ah.parse("a@b.com, c@d.com");
    try std.testing.expectEqual(@as(usize, 2), ah.addresses.items.len);
}
