/// server - Debug Server
/// TCP server for remote debugger connections.

const std = @import("std");
const Allocator = std.mem.Allocator;
const DebugSession = @import("session.zig").DebugSession;

// ============================================================================
// Debug Server
// ============================================================================

/// Debug server configuration
pub const ServerConfig = struct {
    /// Listen address
    address: []const u8 = "127.0.0.1",
    /// Listen port
    port: u16 = 5678,
    /// Wait for debugger on start
    wait_on_start: bool = false,
    /// Break on exception
    break_on_exception: bool = true,
    /// Log level
    log_level: u8 = 0,
};

/// Debug server
pub const DebugServer = struct {
    const Self = @This();

    /// Configuration
    config: ServerConfig,
    /// Active session
    session: ?DebugSession = null,
    /// Is listening
    listening: bool = false,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: ServerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.session) |*s| {
            s.deinit();
        }
    }

    /// Start server
    pub fn start(self: *Self) !void {
        // Would start TCP server listening on config.address:config.port
        self.listening = true;

        if (self.config.wait_on_start) {
            // Block until debugger connects
            try self.waitForConnection();
        }
    }

    /// Stop server
    pub fn stop(self: *Self) void {
        if (self.session) |*s| {
            s.disconnect();
        }
        self.listening = false;
    }

    /// Wait for debugger connection
    fn waitForConnection(self: *Self) !void {
        // Would block until client connects
        self.session = DebugSession.init(self.allocator);
        self.session.?.connect();
    }

    /// Check if debugger is connected
    pub fn isConnected(self: *const Self) bool {
        if (self.session) |s| {
            return s.isAttached();
        }
        return false;
    }
};
