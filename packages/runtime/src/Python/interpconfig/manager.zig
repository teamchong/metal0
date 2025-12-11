/// manager - Interpreter Manager
/// Mirrors cpython/Python/interpconfig.c (manager section)
///
/// Manages multiple Python interpreters:
/// - Creation and destruction of main and sub-interpreters
/// - Thread-safe linked list of all active interpreters
/// - Unique ID allocation
/// - Lookup by ID
/// - Main interpreter singleton tracking

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const state_mod = @import("state.zig");
const config_mod = @import("config.zig");

/// Manages multiple interpreters
pub const InterpreterManager = struct {
    /// Head of interpreter list
    head: ?*state_mod.InterpreterState,
    /// Main interpreter
    main: ?*state_mod.InterpreterState,
    /// Next interpreter ID
    next_id: Atomic(u64),
    /// Lock for list operations
    lock: std.Thread.Mutex,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .head = null,
            .main = null,
            .next_id = Atomic(u64).init(1),
            .lock = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lock.lock();
        defer self.lock.unlock();

        var current = self.head;
        while (current) |interp| {
            const next = interp.next;
            self.allocator.destroy(interp);
            current = next;
        }
        self.head = null;
        self.main = null;
    }

    /// Create main interpreter
    pub fn createMain(self: *Self) !*state_mod.InterpreterState {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.main != null) {
            return error.MainAlreadyExists;
        }

        const cfg = config_mod.PyInterpreterConfig.initLegacy();
        const interp = try self.allocator.create(state_mod.InterpreterState);
        interp.* = state_mod.InterpreterState.create(0, cfg, true);

        self.head = interp;
        self.main = interp;

        return interp;
    }

    /// Create sub-interpreter
    pub fn createSubInterpreter(self: *Self, cfg: config_mod.PyInterpreterConfig) !*state_mod.InterpreterState {
        try cfg.validate();

        self.lock.lock();
        defer self.lock.unlock();

        const id = self.next_id.fetchAdd(1, .monotonic);
        const interp = try self.allocator.create(state_mod.InterpreterState);
        interp.* = state_mod.InterpreterState.create(id, cfg, false);

        // Add to list
        interp.next = self.head;
        if (self.head) |head| {
            head.prev = interp;
        }
        self.head = interp;

        return interp;
    }

    /// Destroy interpreter
    pub fn destroyInterpreter(self: *Self, interp: *state_mod.InterpreterState) !void {
        if (interp.is_main) {
            return error.CannotDestroyMain;
        }

        self.lock.lock();
        defer self.lock.unlock();

        // Remove from list
        if (interp.prev) |prev| {
            prev.next = interp.next;
        } else {
            self.head = interp.next;
        }
        if (interp.next) |next| {
            next.prev = interp.prev;
        }

        interp.finalized = true;
        if (interp.decref() == 0) {
            self.allocator.destroy(interp);
        }
    }

    /// Get interpreter by ID
    pub fn getById(self: *Self, id: state_mod.InterpId) ?*state_mod.InterpreterState {
        self.lock.lock();
        defer self.lock.unlock();

        var current = self.head;
        while (current) |interp| {
            if (interp.id == id) {
                return interp;
            }
            current = interp.next;
        }
        return null;
    }

    /// Get interpreter count
    pub fn count(self: *Self) usize {
        self.lock.lock();
        defer self.lock.unlock();

        var n: usize = 0;
        var current = self.head;
        while (current) |interp| {
            n += 1;
            current = interp.next;
        }
        return n;
    }

    /// Get main interpreter
    pub fn getMain(self: *Self) ?*state_mod.InterpreterState {
        return self.main;
    }
};
