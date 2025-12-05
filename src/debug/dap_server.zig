/// Debug Adapter Protocol (DAP) Server
///
/// Implements the DAP specification for debugging metal0 compiled binaries.
/// Reference: https://microsoft.github.io/debug-adapter-protocol/
///
/// The DAP server communicates via JSON-RPC over stdin/stdout with the IDE.
///
const std = @import("std");
const debug_info = @import("debug_info.zig");

/// DAP message types
pub const MessageType = enum {
    request,
    response,
    event,
};

/// Base protocol message
pub const ProtocolMessage = struct {
    seq: u32,
    type: []const u8,
};

/// DAP Request
pub const Request = struct {
    seq: u32,
    type: []const u8 = "request",
    command: []const u8,
    arguments: ?std.json.Value = null,
};

/// DAP Response
pub const Response = struct {
    seq: u32,
    type: []const u8 = "response",
    request_seq: u32,
    success: bool,
    command: []const u8,
    message: ?[]const u8 = null,
    body: ?std.json.Value = null,
};

/// DAP Event
pub const Event = struct {
    seq: u32,
    type: []const u8 = "event",
    event: []const u8,
    body: ?std.json.Value = null,
};

/// Breakpoint information
pub const Breakpoint = struct {
    id: u32,
    verified: bool,
    source_path: []const u8,
    line: u32,
    condition: ?[]const u8 = null,
    hit_count: u32 = 0,
};

/// Stack frame information
pub const StackFrame = struct {
    id: u32,
    name: []const u8,
    source_path: ?[]const u8,
    line: u32,
    column: u32 = 0,
};

/// Variable scope
pub const Scope = struct {
    name: []const u8,
    variables_reference: u32,
    expensive: bool = false,
};

/// Variable information
pub const Variable = struct {
    name: []const u8,
    value: []const u8,
    type: ?[]const u8 = null,
    variables_reference: u32 = 0, // Non-zero if has children
};

/// DAP Server State
pub const ServerState = enum {
    uninitialized,
    initialized,
    running,
    stopped,
    terminated,
};

/// DAP Server
pub const DapServer = struct {
    allocator: std.mem.Allocator,

    /// Current state
    state: ServerState = .uninitialized,

    /// Sequence number for outgoing messages
    seq: u32 = 1,

    /// Breakpoints by source file
    breakpoints: std.StringHashMap(std.ArrayList(Breakpoint)),

    /// Next breakpoint ID
    next_breakpoint_id: u32 = 1,

    /// Debug info reader (loaded from .metal0.dbg file)
    debug_reader: ?debug_info.DebugInfoReader = null,

    /// Current stack frames (populated when stopped)
    stack_frames: std.ArrayList(StackFrame),

    /// Variables by reference ID
    variables: std.AutoHashMap(u32, std.ArrayList(Variable)),
    next_var_ref: u32 = 1,

    /// Read buffer
    read_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) DapServer {
        return .{
            .allocator = allocator,
            .breakpoints = std.StringHashMap(std.ArrayList(Breakpoint)).init(allocator),
            .stack_frames = std.ArrayList(StackFrame){},
            .variables = std.AutoHashMap(u32, std.ArrayList(Variable)).init(allocator),
            .read_buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *DapServer) void {
        // Clean up breakpoints
        var bp_iter = self.breakpoints.iterator();
        while (bp_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.breakpoints.deinit();

        self.stack_frames.deinit(self.allocator);

        // Clean up variables
        var var_iter = self.variables.iterator();
        while (var_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.variables.deinit();

        if (self.debug_reader) |*dr| {
            dr.deinit();
        }

        self.read_buffer.deinit(self.allocator);
    }

    /// Run the DAP server main loop (reads from stdin, writes to stdout)
    pub fn run(self: *DapServer) !void {
        const stdin_file = std.fs.cwd().openFile("/dev/stdin", .{}) catch return error.StdinNotAvailable;
        defer stdin_file.close();

        while (self.state != .terminated) {
            const message = self.readMessageFromFile(stdin_file) catch |err| {
                if (err == error.EndOfStream) {
                    self.state = .terminated;
                    break;
                }
                return err;
            };
            defer self.allocator.free(message);

            try self.handleMessage(message);
        }
    }

    /// Read a DAP message from a file handle
    /// Format: Content-Length: <length>\r\n\r\n<JSON content>
    fn readMessageFromFile(self: *DapServer, file: std.fs.File) ![]const u8 {
        var reader = file.reader();

        // Read headers
        var content_length: ?usize = null;
        while (true) {
            const line = try reader.readUntilDelimiterAlloc(self.allocator, '\n', 4096);
            defer self.allocator.free(line);

            // Remove trailing \r if present
            const trimmed = if (line.len > 0 and line[line.len - 1] == '\r')
                line[0 .. line.len - 1]
            else
                line;

            // Empty line signals end of headers
            if (trimmed.len == 0) break;

            // Parse Content-Length header
            if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                content_length = try std.fmt.parseInt(usize, trimmed[16..], 10);
            }
        }

        // Read content
        const length = content_length orelse return error.MissingContentLength;
        const content = try self.allocator.alloc(u8, length);
        const bytes_read = try reader.readAll(content);
        if (bytes_read != length) {
            self.allocator.free(content);
            return error.IncompleteMessage;
        }

        return content;
    }

    /// Send a DAP message to stdout
    fn sendMessage(_: *DapServer, json: []const u8) !void {
        const formatted = std.fmt.allocPrint(std.heap.page_allocator, "Content-Length: {d}\r\n\r\n{s}", .{ json.len, json }) catch return;
        defer std.heap.page_allocator.free(formatted);
        _ = std.posix.write(std.posix.STDOUT_FILENO, formatted) catch {};
    }

    /// Send a response
    fn sendResponse(self: *DapServer, request_seq: u32, command: []const u8, success: bool, body: ?std.json.Value) !void {
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);

        var jw = std.json.writeStream(json_buf.writer(self.allocator), .{});
        try jw.beginObject();

        try jw.objectField("seq");
        try jw.write(self.seq);
        self.seq += 1;

        try jw.objectField("type");
        try jw.write("response");

        try jw.objectField("request_seq");
        try jw.write(request_seq);

        try jw.objectField("success");
        try jw.write(success);

        try jw.objectField("command");
        try jw.write(command);

        if (body) |b| {
            try jw.objectField("body");
            try jw.write(b);
        }

        try jw.endObject();

        try self.sendMessage(json_buf.items);
    }

    /// Send an event
    fn sendEvent(self: *DapServer, event_name: []const u8, body: ?std.json.Value) !void {
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);

        var jw = std.json.writeStream(json_buf.writer(self.allocator), .{});
        try jw.beginObject();

        try jw.objectField("seq");
        try jw.write(self.seq);
        self.seq += 1;

        try jw.objectField("type");
        try jw.write("event");

        try jw.objectField("event");
        try jw.write(event_name);

        if (body) |b| {
            try jw.objectField("body");
            try jw.write(b);
        }

        try jw.endObject();

        try self.sendMessage(json_buf.items);
    }

    /// Handle an incoming message
    fn handleMessage(self: *DapServer, message: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, message, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const msg_type = root.object.get("type") orelse return error.MissingType;

        if (std.mem.eql(u8, msg_type.string, "request")) {
            try self.handleRequest(root);
        }
    }

    /// Handle a request
    fn handleRequest(self: *DapServer, root: std.json.Value) !void {
        const seq = @as(u32, @intCast(root.object.get("seq").?.integer));
        const command = root.object.get("command").?.string;
        const arguments = root.object.get("arguments");

        if (std.mem.eql(u8, command, "initialize")) {
            try self.handleInitialize(seq, arguments);
        } else if (std.mem.eql(u8, command, "launch")) {
            try self.handleLaunch(seq, arguments);
        } else if (std.mem.eql(u8, command, "attach")) {
            try self.handleAttach(seq, arguments);
        } else if (std.mem.eql(u8, command, "disconnect")) {
            try self.handleDisconnect(seq, arguments);
        } else if (std.mem.eql(u8, command, "setBreakpoints")) {
            try self.handleSetBreakpoints(seq, arguments);
        } else if (std.mem.eql(u8, command, "configurationDone")) {
            try self.handleConfigurationDone(seq);
        } else if (std.mem.eql(u8, command, "threads")) {
            try self.handleThreads(seq);
        } else if (std.mem.eql(u8, command, "stackTrace")) {
            try self.handleStackTrace(seq, arguments);
        } else if (std.mem.eql(u8, command, "scopes")) {
            try self.handleScopes(seq, arguments);
        } else if (std.mem.eql(u8, command, "variables")) {
            try self.handleVariables(seq, arguments);
        } else if (std.mem.eql(u8, command, "continue")) {
            try self.handleContinue(seq);
        } else if (std.mem.eql(u8, command, "next")) {
            try self.handleNext(seq);
        } else if (std.mem.eql(u8, command, "stepIn")) {
            try self.handleStepIn(seq);
        } else if (std.mem.eql(u8, command, "stepOut")) {
            try self.handleStepOut(seq);
        } else if (std.mem.eql(u8, command, "pause")) {
            try self.handlePause(seq);
        } else if (std.mem.eql(u8, command, "evaluate")) {
            try self.handleEvaluate(seq, arguments);
        } else {
            // Unknown command - send error response
            try self.sendResponse(seq, command, false, null);
        }
    }

    /// Handle initialize request
    fn handleInitialize(self: *DapServer, seq: u32, _: ?std.json.Value) !void {
        self.state = .initialized;

        // Build capabilities response
        var body = std.json.ObjectMap.init(self.allocator);
        defer body.deinit();

        // Supported capabilities
        try body.put("supportsConfigurationDoneRequest", .{ .bool = true });
        try body.put("supportsFunctionBreakpoints", .{ .bool = false });
        try body.put("supportsConditionalBreakpoints", .{ .bool = true });
        try body.put("supportsHitConditionalBreakpoints", .{ .bool = false });
        try body.put("supportsEvaluateForHovers", .{ .bool = true });
        try body.put("supportsStepBack", .{ .bool = false });
        try body.put("supportsSetVariable", .{ .bool = false });
        try body.put("supportsRestartFrame", .{ .bool = false });
        try body.put("supportsGotoTargetsRequest", .{ .bool = false });
        try body.put("supportsStepInTargetsRequest", .{ .bool = false });
        try body.put("supportsCompletionsRequest", .{ .bool = false });
        try body.put("supportsModulesRequest", .{ .bool = false });
        try body.put("supportsExceptionOptions", .{ .bool = false });
        try body.put("supportsValueFormattingOptions", .{ .bool = false });
        try body.put("supportsExceptionInfoRequest", .{ .bool = false });
        try body.put("supportTerminateDebuggee", .{ .bool = true });
        try body.put("supportsDelayedStackTraceLoading", .{ .bool = false });
        try body.put("supportsLoadedSourcesRequest", .{ .bool = false });

        try self.sendResponse(seq, "initialize", true, .{ .object = body });

        // Send initialized event
        try self.sendEvent("initialized", null);
    }

    /// Handle launch request
    fn handleLaunch(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        _ = arguments; // TODO: Parse program path, args, etc.

        self.state = .running;
        try self.sendResponse(seq, "launch", true, null);

        // TODO: Actually launch the debuggee process
    }

    /// Handle attach request
    fn handleAttach(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        _ = arguments; // TODO: Parse pid or other attach info

        self.state = .running;
        try self.sendResponse(seq, "attach", true, null);
    }

    /// Handle disconnect request
    fn handleDisconnect(self: *DapServer, seq: u32, _: ?std.json.Value) !void {
        self.state = .terminated;
        try self.sendResponse(seq, "disconnect", true, null);
        try self.sendEvent("terminated", null);
    }

    /// Handle setBreakpoints request
    fn handleSetBreakpoints(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        const args = arguments orelse {
            try self.sendResponse(seq, "setBreakpoints", false, null);
            return;
        };

        const source = args.object.get("source") orelse {
            try self.sendResponse(seq, "setBreakpoints", false, null);
            return;
        };

        const source_path = source.object.get("path").?.string;
        const breakpoints_json = args.object.get("breakpoints") orelse .{ .array = std.json.Array.init(self.allocator) };

        // Clear existing breakpoints for this file
        if (self.breakpoints.getPtr(source_path)) |bp_list| {
            bp_list.clearRetainingCapacity();
        } else {
            try self.breakpoints.put(source_path, std.ArrayList(Breakpoint){});
        }

        var bp_list = self.breakpoints.getPtr(source_path).?;

        // Add new breakpoints
        var result_breakpoints = std.ArrayList(std.json.Value){};
        defer result_breakpoints.deinit(self.allocator);

        for (breakpoints_json.array.items) |bp_json| {
            const line = @as(u32, @intCast(bp_json.object.get("line").?.integer));
            const condition = if (bp_json.object.get("condition")) |c| c.string else null;

            const bp = Breakpoint{
                .id = self.next_breakpoint_id,
                .verified = true, // TODO: Verify against debug info
                .source_path = source_path,
                .line = line,
                .condition = condition,
            };
            self.next_breakpoint_id += 1;

            try bp_list.append(self.allocator, bp);

            // Build response breakpoint
            var bp_obj = std.json.ObjectMap.init(self.allocator);
            try bp_obj.put("id", .{ .integer = bp.id });
            try bp_obj.put("verified", .{ .bool = bp.verified });
            try bp_obj.put("line", .{ .integer = bp.line });
            try result_breakpoints.append(self.allocator, .{ .object = bp_obj });
        }

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("breakpoints", .{ .array = result_breakpoints });

        try self.sendResponse(seq, "setBreakpoints", true, .{ .object = body });
    }

    /// Handle configurationDone request
    fn handleConfigurationDone(self: *DapServer, seq: u32) !void {
        try self.sendResponse(seq, "configurationDone", true, null);
    }

    /// Handle threads request
    fn handleThreads(self: *DapServer, seq: u32) !void {
        // For now, report a single thread
        var threads = std.ArrayList(std.json.Value){};
        defer threads.deinit(self.allocator);

        var thread_obj = std.json.ObjectMap.init(self.allocator);
        try thread_obj.put("id", .{ .integer = 1 });
        try thread_obj.put("name", .{ .string = "main" });
        try threads.append(self.allocator, .{ .object = thread_obj });

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("threads", .{ .array = threads });

        try self.sendResponse(seq, "threads", true, .{ .object = body });
    }

    /// Handle stackTrace request
    fn handleStackTrace(self: *DapServer, seq: u32, _: ?std.json.Value) !void {
        var frames = std.ArrayList(std.json.Value){};
        defer frames.deinit(self.allocator);

        for (self.stack_frames.items, 0..) |frame, i| {
            var frame_obj = std.json.ObjectMap.init(self.allocator);
            try frame_obj.put("id", .{ .integer = @intCast(i) });
            try frame_obj.put("name", .{ .string = frame.name });
            try frame_obj.put("line", .{ .integer = frame.line });
            try frame_obj.put("column", .{ .integer = frame.column });

            if (frame.source_path) |path| {
                var source_obj = std.json.ObjectMap.init(self.allocator);
                try source_obj.put("path", .{ .string = path });
                try frame_obj.put("source", .{ .object = source_obj });
            }

            try frames.append(self.allocator, .{ .object = frame_obj });
        }

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("stackFrames", .{ .array = frames });
        try body.put("totalFrames", .{ .integer = @intCast(self.stack_frames.items.len) });

        try self.sendResponse(seq, "stackTrace", true, .{ .object = body });
    }

    /// Handle scopes request
    fn handleScopes(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        _ = arguments; // TODO: Use frame ID

        var scopes = std.ArrayList(std.json.Value){};
        defer scopes.deinit(self.allocator);

        // Local scope
        var local_scope = std.json.ObjectMap.init(self.allocator);
        try local_scope.put("name", .{ .string = "Locals" });
        try local_scope.put("variablesReference", .{ .integer = 1 });
        try local_scope.put("expensive", .{ .bool = false });
        try scopes.append(self.allocator, .{ .object = local_scope });

        // Global scope
        var global_scope = std.json.ObjectMap.init(self.allocator);
        try global_scope.put("name", .{ .string = "Globals" });
        try global_scope.put("variablesReference", .{ .integer = 2 });
        try global_scope.put("expensive", .{ .bool = false });
        try scopes.append(self.allocator, .{ .object = global_scope });

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("scopes", .{ .array = scopes });

        try self.sendResponse(seq, "scopes", true, .{ .object = body });
    }

    /// Handle variables request
    fn handleVariables(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        const args = arguments orelse {
            try self.sendResponse(seq, "variables", false, null);
            return;
        };

        const var_ref = @as(u32, @intCast(args.object.get("variablesReference").?.integer));

        var vars = std.ArrayList(std.json.Value){};
        defer vars.deinit(self.allocator);

        if (self.variables.get(var_ref)) |var_list| {
            for (var_list.items) |v| {
                var var_obj = std.json.ObjectMap.init(self.allocator);
                try var_obj.put("name", .{ .string = v.name });
                try var_obj.put("value", .{ .string = v.value });
                if (v.type) |t| {
                    try var_obj.put("type", .{ .string = t });
                }
                try var_obj.put("variablesReference", .{ .integer = v.variables_reference });
                try vars.append(self.allocator, .{ .object = var_obj });
            }
        }

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("variables", .{ .array = vars });

        try self.sendResponse(seq, "variables", true, .{ .object = body });
    }

    /// Handle continue request
    fn handleContinue(self: *DapServer, seq: u32) !void {
        self.state = .running;
        try self.sendResponse(seq, "continue", true, null);
        // TODO: Actually continue execution
    }

    /// Handle next (step over) request
    fn handleNext(self: *DapServer, seq: u32) !void {
        try self.sendResponse(seq, "next", true, null);
        // TODO: Implement step over
        try self.sendEvent("stopped", null); // For now, immediately stop
    }

    /// Handle stepIn request
    fn handleStepIn(self: *DapServer, seq: u32) !void {
        try self.sendResponse(seq, "stepIn", true, null);
        // TODO: Implement step in
        try self.sendEvent("stopped", null);
    }

    /// Handle stepOut request
    fn handleStepOut(self: *DapServer, seq: u32) !void {
        try self.sendResponse(seq, "stepOut", true, null);
        // TODO: Implement step out
        try self.sendEvent("stopped", null);
    }

    /// Handle pause request
    fn handlePause(self: *DapServer, seq: u32) !void {
        self.state = .stopped;
        try self.sendResponse(seq, "pause", true, null);
        try self.sendEvent("stopped", null);
    }

    /// Handle evaluate request
    fn handleEvaluate(self: *DapServer, seq: u32, arguments: ?std.json.Value) !void {
        const args = arguments orelse {
            try self.sendResponse(seq, "evaluate", false, null);
            return;
        };

        const expression = args.object.get("expression").?.string;
        _ = expression; // TODO: Actually evaluate

        var body = std.json.ObjectMap.init(self.allocator);
        try body.put("result", .{ .string = "<evaluation not implemented>" });
        try body.put("variablesReference", .{ .integer = 0 });

        try self.sendResponse(seq, "evaluate", true, .{ .object = body });
    }

    /// Load debug info from a .metal0.dbg file
    pub fn loadDebugInfo(self: *DapServer, path: []const u8) !void {
        self.debug_reader = debug_info.DebugInfoReader.init(self.allocator);
        try self.debug_reader.?.loadBinary(path);
    }

    /// Add a stack frame (called when debuggee stops)
    pub fn pushStackFrame(self: *DapServer, name: []const u8, source_path: ?[]const u8, line: u32) !void {
        try self.stack_frames.append(self.allocator, .{
            .id = @intCast(self.stack_frames.items.len),
            .name = name,
            .source_path = source_path,
            .line = line,
        });
    }

    /// Clear stack frames (called when continuing)
    pub fn clearStackFrames(self: *DapServer) void {
        self.stack_frames.clearRetainingCapacity();
    }

    /// Add a variable to a scope
    pub fn addVariable(self: *DapServer, scope_ref: u32, name: []const u8, value: []const u8, var_type: ?[]const u8) !void {
        var var_list = self.variables.getPtr(scope_ref) orelse blk: {
            try self.variables.put(scope_ref, std.ArrayList(Variable){});
            break :blk self.variables.getPtr(scope_ref).?;
        };

        try var_list.append(self.allocator, .{
            .name = name,
            .value = value,
            .type = var_type,
        });
    }
};

/// Entry point for running the DAP server
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = DapServer.init(allocator);
    defer server.deinit();

    try server.run();
}

// ============================================================================
// Tests
// ============================================================================

test "DAP server initialization" {
    const allocator = std.testing.allocator;

    var server = DapServer.init(allocator);
    defer server.deinit();

    try std.testing.expectEqual(ServerState.uninitialized, server.state);
}

test "breakpoint management" {
    const allocator = std.testing.allocator;

    var server = DapServer.init(allocator);
    defer server.deinit();

    // Manually add a breakpoint
    try server.breakpoints.put("test.py", std.ArrayList(Breakpoint){});
    var bp_list = server.breakpoints.getPtr("test.py").?;
    try bp_list.append(allocator, .{
        .id = 1,
        .verified = true,
        .source_path = "test.py",
        .line = 10,
    });

    try std.testing.expectEqual(@as(usize, 1), bp_list.items.len);
    try std.testing.expectEqual(@as(u32, 10), bp_list.items[0].line);
}
