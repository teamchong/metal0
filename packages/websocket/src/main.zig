// WebSocket Module for metal0
// Maps to Python's websockets library

pub const protocol = @import("protocol.zig");
pub const client = @import("client.zig");

pub const Opcode = protocol.Opcode;
pub const WebSocketHeader = protocol.WebSocketHeader;
pub const CloseCode = protocol.CloseCode;

pub const WebSocketClient = client.WebSocketClient;
pub const WebSocketError = client.WebSocketError;
pub const State = client.State;
pub const Message = client.Message;

pub const connect = client.connect;

test {
    _ = protocol;
    _ = client;
}
