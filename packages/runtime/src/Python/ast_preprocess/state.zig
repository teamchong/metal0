/// AST Preprocess State
/// State management for AST preprocessing

const std = @import("std");
const Allocator = std.mem.Allocator;
const control_flow = @import("control_flow.zig");
const diagnostics = @import("diagnostics.zig");

/// AST preprocessing state
pub const PreprocessState = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Source filename
    filename: []const u8,
    /// Module name
    module_name: ?[]const u8 = null,
    /// Optimization level (0-2)
    optimize: u8 = 0,
    /// Future features flags
    ff_features: u32 = 0,
    /// Syntax check only mode
    syntax_check_only: bool = false,
    /// Enable warnings
    enable_warnings: bool = true,
    /// Control flow context stack
    cf_context: control_flow.ContextStack,
    /// Collected warnings
    warnings: std.ArrayList(diagnostics.Warning),
    /// Collected errors
    errors: std.ArrayList(diagnostics.PreprocessError),

    pub fn init(allocator: Allocator, filename: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filename = filename,
            .cf_context = control_flow.ContextStack.init(allocator),
            .warnings = std.ArrayList(diagnostics.Warning).init(allocator),
            .errors = std.ArrayList(diagnostics.PreprocessError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cf_context.deinit();
        self.warnings.deinit();
        self.errors.deinit();
    }

    /// Enter finally block
    pub fn enterFinally(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = true,
            .in_funcdef = false,
            .in_loop = false,
        });
    }

    /// Exit finally block
    pub fn exitFinally(self: *Self) void {
        self.cf_context.pop();
    }

    /// Enter function body
    pub fn enterFuncBody(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = false,
            .in_funcdef = true,
            .in_loop = false,
        });
    }

    /// Exit function body
    pub fn exitFuncBody(self: *Self) void {
        self.cf_context.pop();
    }

    /// Enter loop body
    pub fn enterLoopBody(self: *Self) !void {
        try self.cf_context.push(.{
            .in_finally = false,
            .in_funcdef = false,
            .in_loop = true,
        });
    }

    /// Exit loop body
    pub fn exitLoopBody(self: *Self) void {
        self.cf_context.pop();
    }

    /// Check before return statement
    pub fn beforeReturn(self: *Self, lineno: u32, col_offset: u32) !void {
        if (!self.enable_warnings or self.cf_context.isEmpty()) return;
        if (self.cf_context.top()) |ctx| {
            if (ctx.in_finally and !ctx.in_funcdef) {
                try self.addWarning(.return_in_finally, lineno, col_offset);
            }
        }
    }

    /// Check before break/continue
    pub fn beforeLoopExit(self: *Self, keyword: []const u8, lineno: u32, col_offset: u32) !void {
        if (!self.enable_warnings or self.cf_context.isEmpty()) return;
        if (self.cf_context.top()) |ctx| {
            if (ctx.in_finally and !ctx.in_loop) {
                const kind: diagnostics.WarningKind = if (std.mem.eql(u8, keyword, "break"))
                    .break_in_finally
                else
                    .continue_in_finally;
                try self.addWarning(kind, lineno, col_offset);
            }
        }
    }

    /// Add warning
    fn addWarning(self: *Self, kind: diagnostics.WarningKind, lineno: u32, col_offset: u32) !void {
        try self.warnings.append(.{
            .kind = kind,
            .lineno = lineno,
            .col_offset = col_offset,
            .filename = self.filename,
        });
    }

    /// Add error
    pub fn addError(self: *Self, kind: diagnostics.ErrorKind, message: []const u8, lineno: u32, col_offset: u32) !void {
        try self.errors.append(.{
            .kind = kind,
            .message = message,
            .lineno = lineno,
            .col_offset = col_offset,
            .filename = self.filename,
        });
    }

    /// Check if errors occurred
    pub fn hasErrors(self: *const Self) bool {
        return self.errors.items.len > 0;
    }

    /// Get warning count
    pub fn warningCount(self: *const Self) usize {
        return self.warnings.items.len;
    }
};
