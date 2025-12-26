/// ZigBuilder - Structured Zig code generation
///
/// This is the core abstraction that replaces emit()/emitFmt() with
/// type-safe, scope-aware code generation APIs.
///
/// Key features:
/// - Type-safe value handling (ZigValue)
/// - Automatic scope management (RAII-style handles)
/// - Context-aware emission (parens, error handling)
/// - Integrated name generation (NameGen internal)
/// - Local variable reuse (LocalAllocator)
/// - Multi-section output (preamble, types, header, body)
///
/// Usage pattern:
///   var builder = try ZigBuilder.init(allocator);
///   defer builder.deinit();
///
///   // Declare variables
///   const x = try builder.declareConst("x", pool.i64_(), ZigValue.int(42));
///
///   // Binary operations
///   const y = try builder.binOp(.add, ZigValue.fromLocal(x), ZigValue.int(1));
///
///   // Control flow
///   const if_handle = try builder.beginIf(ZigValue.boolean(true));
///   try builder.assign("result", ZigValue.int(1));
///   try builder.endIf(if_handle);
///
///   // Get output
///   const code = try builder.finish();
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const ZigValue = @import("zig_value.zig").ZigValue;
const LocalIndex = @import("zig_value.zig").LocalIndex;
const TypeConfidence = @import("zig_value.zig").TypeConfidence;
const BinOp = @import("zig_value.zig").BinOp;

const ZigType = @import("zig_type.zig").ZigType;
const TypePool = @import("zig_type.zig").TypePool;

const EmitContext = @import("emit_context.zig").EmitContext;
const EmitConfig = @import("emit_context.zig").EmitConfig;
const ErrorMode = @import("emit_context.zig").ErrorMode;
const ScopeKind = @import("emit_context.zig").ScopeKind;
const ScopeContext = @import("emit_context.zig").ScopeContext;
const ScopeHandle = @import("emit_context.zig").ScopeHandle;

const LocalAllocator = @import("local_allocator.zig").LocalAllocator;

/// Import NameGen for unified ID generation
const name_gen_mod = @import("codegen.name_gen");
pub const NameGen = name_gen_mod.NameGen;

/// Main builder struct for Zig code generation
pub const ZigBuilder = struct {
    allocator: Allocator,

    // ============================================
    // Output buffers (multi-section emission)
    // ============================================

    /// Import statements and module-level declarations (Zig 0.15: empty ArrayList)
    preamble: std.ArrayList(u8),

    /// Struct/enum/union type definitions
    types: std.ArrayList(u8),

    /// Function signatures (for forward declarations)
    header: std.ArrayList(u8),

    /// Main code body
    body: std.ArrayList(u8),

    // ============================================
    // State management
    // ============================================

    /// Type pool for deduplication
    type_pool: TypePool,

    /// Local variable allocator
    locals: LocalAllocator,

    /// Scope stack
    scope_stack: std.ArrayList(ScopeContext),

    /// Current indent level
    indent_level: usize,

    /// External name generator (shared with NativeCodegen for unified IDs)
    /// When null, uses internal fallback counter
    name_gen: ?*NameGen,

    /// Internal fallback counter (only used when name_gen is null, e.g., in tests)
    internal_counter: usize,

    /// Line counter for debug info
    line_counter: usize,

    /// Whether we're inside a function
    in_function: bool,

    /// Whether current function returns error
    function_returns_error: bool,

    /// Named bindings in current scope (name -> type)
    bindings: std.StringHashMap(ZigType),

    // ============================================
    // Initialization
    // ============================================

    /// Initialize builder with external NameGen (for integration with NativeCodegen)
    pub fn initWithNameGen(allocator: Allocator, name_gen: *NameGen) !ZigBuilder {
        var builder = ZigBuilder{
            .allocator = allocator,
            // Zig 0.15: ArrayList is empty struct, allocator passed to methods
            .preamble = .{},
            .types = .{},
            .header = .{},
            .body = .{},
            .type_pool = TypePool.init(allocator),
            .locals = LocalAllocator.init(allocator),
            .scope_stack = .{},
            .indent_level = 0,
            .name_gen = name_gen,
            .internal_counter = 0,
            .line_counter = 1,
            .in_function = false,
            .function_returns_error = false,
            .bindings = std.StringHashMap(ZigType).init(allocator),
        };

        // Start with module scope (Zig 0.15: pass allocator)
        try builder.scope_stack.append(allocator, ScopeContext.module());

        return builder;
    }

    /// Initialize builder standalone (for tests or independent use)
    pub fn init(allocator: Allocator) !ZigBuilder {
        var builder = ZigBuilder{
            .allocator = allocator,
            // Zig 0.15: ArrayList is empty struct, allocator passed to methods
            .preamble = .{},
            .types = .{},
            .header = .{},
            .body = .{},
            .type_pool = TypePool.init(allocator),
            .locals = LocalAllocator.init(allocator),
            .scope_stack = .{},
            .indent_level = 0,
            .name_gen = null,
            .internal_counter = 0,
            .line_counter = 1,
            .in_function = false,
            .function_returns_error = false,
            .bindings = std.StringHashMap(ZigType).init(allocator),
        };

        // Start with module scope (Zig 0.15: pass allocator)
        try builder.scope_stack.append(allocator, ScopeContext.module());

        return builder;
    }

    pub fn deinit(self: *ZigBuilder) void {
        // Zig 0.15: pass allocator to deinit
        self.preamble.deinit(self.allocator);
        self.types.deinit(self.allocator);
        self.header.deinit(self.allocator);
        self.body.deinit(self.allocator);
        self.type_pool.deinit();
        self.locals.deinit();
        // Free any remaining scope labels before deiniting the stack
        for (self.scope_stack.items) |scope| {
            if (scope.break_label) |label| {
                self.allocator.free(label);
            }
        }
        self.scope_stack.deinit(self.allocator);
        self.bindings.deinit();
    }

    // ============================================
    // Output helpers
    // ============================================

    /// Write to the body buffer
    pub fn write(self: *ZigBuilder, s: []const u8) !void {
        // Zig 0.15: pass allocator to appendSlice
        try self.body.appendSlice(self.allocator, s);
        for (s) |c| {
            if (c == '\n') self.line_counter += 1;
        }
    }

    /// Write formatted to body buffer
    pub fn writeFmt(self: *ZigBuilder, comptime fmt: []const u8, args: anytype) !void {
        const start = self.body.items.len;
        // Zig 0.15: pass allocator to writer
        try self.body.writer(self.allocator).print(fmt, args);
        for (self.body.items[start..]) |c| {
            if (c == '\n') self.line_counter += 1;
        }
    }

    /// Write to preamble
    fn writePreamble(self: *ZigBuilder, s: []const u8) !void {
        // Zig 0.15: pass allocator
        try self.preamble.appendSlice(self.allocator, s);
    }

    /// Write to types section
    fn writeTypes(self: *ZigBuilder, s: []const u8) !void {
        // Zig 0.15: pass allocator
        try self.types.appendSlice(self.allocator, s);
    }

    /// Static indent strings for O(1) lookup
    const INDENT_STRINGS = [_][]const u8{
        "",
        "    ",
        "        ",
        "            ",
        "                ",
        "                    ",
        "                        ",
        "                            ",
        "                                ",
        "                                    ",
    };

    /// Write current indentation
    pub fn writeIndent(self: *ZigBuilder) !void {
        const level = @min(self.indent_level, INDENT_STRINGS.len - 1);
        try self.write(INDENT_STRINGS[level]);
    }

    /// Increase indent
    pub fn indent(self: *ZigBuilder) void {
        self.indent_level += 1;
    }

    /// Decrease indent
    pub fn dedent(self: *ZigBuilder) void {
        if (self.indent_level > 0) self.indent_level -= 1;
    }

    /// Generate a unique ID (uses external NameGen if available, fallback to internal counter)
    fn nextId(self: *ZigBuilder) usize {
        if (self.name_gen) |ng| {
            return ng.nextId();
        }
        const id = self.internal_counter;
        self.internal_counter += 1;
        return id;
    }

    /// Generate a unique name using the unified naming scheme
    /// Uses external NameGen if available, otherwise uses internal counter
    pub fn freshName(self: *ZigBuilder, hint: []const u8) ![]const u8 {
        if (self.name_gen) |ng| {
            return ng.fresh(hint);
        }
        const id = self.internal_counter;
        self.internal_counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_{s}", .{ id, hint });
    }

    /// Generate a unique block label
    pub fn freshBlockLabel(self: *ZigBuilder) ![]const u8 {
        if (self.name_gen) |ng| {
            return ng.blockLabel();
        }
        const id = self.internal_counter;
        self.internal_counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_b", .{id});
    }

    /// Generate a unique temp name
    pub fn freshTemp(self: *ZigBuilder) ![]const u8 {
        if (self.name_gen) |ng| {
            return ng.temp();
        }
        const id = self.internal_counter;
        self.internal_counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_t", .{id});
    }

    /// Get the raw ID for use with emitFmt (for gradual migration)
    pub fn getNextId(self: *ZigBuilder) usize {
        return self.nextId();
    }

    /// Get current scope
    fn currentScope(self: *ZigBuilder) *ScopeContext {
        return &self.scope_stack.items[self.scope_stack.items.len - 1];
    }

    // ============================================
    // Value emission
    // ============================================

    /// Emit a value in the given context
    pub fn emitValue(self: *ZigBuilder, value: ZigValue, config: EmitConfig) !void {
        const needs_parens = config.force_parens or
            (config.context.needsParens() and self.valueNeedsParens(value));

        if (needs_parens) try self.write("(");

        // Handle error wrapping if needed
        const needs_try = config.error_mode == .propagate and
            config.context.needsErrorHandling() and
            self.valueCanError(value);
        const needs_catch = config.error_mode == .catch_default and self.valueCanError(value);

        if (needs_try) try self.write("try ");
        if (needs_catch) try self.write("(");

        // Emit the actual value
        try self.emitValueCore(value);

        // Close error handling
        if (needs_catch) {
            try self.write(" catch ");
            if (config.catch_default) |default| {
                try self.write(default);
            } else {
                try self.write("unreachable");
            }
            try self.write(")");
        }

        if (needs_parens) try self.write(")");
    }

    /// Emit an expression as a complete statement (adds semicolon and newline)
    /// Handles:
    /// - Automatic `_ =` prefix for value-returning expressions
    /// - Proper semicolon placement
    /// - No semicolon for complete if statements
    pub fn emitExprStmt(self: *ZigBuilder, value: ZigValue) !void {
        // Check if this is a complete if statement (doesn't need semicolon)
        const is_if_stmt = switch (value) {
            .raw => |r| std.mem.startsWith(u8, r, "if ("),
            else => false,
        };

        if (is_if_stmt) {
            // Complete if statement - just emit with newline, no semicolon
            try self.emitValue(value, EmitConfig.forStatement());
            try self.write("\n");
            return;
        }

        // For value-returning expressions, add `_ =` prefix
        const needs_discard = self.valueReturnsValue(value);
        if (needs_discard) {
            try self.write("_ = ");
        }

        try self.emitValue(value, EmitConfig.forStatement());
        try self.write(";\n");
    }

    /// Check if a value returns a value that needs to be discarded
    fn valueReturnsValue(self: *ZigBuilder, value: ZigValue) bool {
        _ = self;
        return switch (value) {
            .call => true, // Most calls return values
            .raw => |r| blk: {
                // Check for value-returning patterns
                if (std.mem.startsWith(u8, r, "try runtime.") or
                    std.mem.startsWith(u8, r, "try unittest."))
                {
                    break :blk std.mem.indexOf(u8, r, "(") != null;
                }
                break :blk false;
            },
            else => false,
        };
    }

    /// Core value emission (no wrapping)
    fn emitValueCore(self: *ZigBuilder, value: ZigValue) !void {
        switch (value) {
            .none => try self.write("{}"),
            .local => |idx| {
                if (self.locals.getName(idx)) |name| {
                    try self.write(name);
                } else {
                    try self.writeFmt("__local_{d}", .{idx});
                }
            },
            .local_ref => |idx| {
                try self.write("&");
                if (self.locals.getName(idx)) |name| {
                    try self.write(name);
                } else {
                    try self.writeFmt("__local_{d}", .{idx});
                }
            },
            .named => |name| try self.write(name),
            .param => |idx| try self.writeFmt("__param_{d}", .{idx}),
            .certain_int => |v| try self.writeFmt("{d}", .{v}),
            .certain_float => |v| {
                // Handle special float values
                if (std.math.isNan(v)) {
                    try self.write("std.math.nan(f64)");
                } else if (std.math.isInf(v)) {
                    if (v > 0) {
                        try self.write("std.math.inf(f64)");
                    } else {
                        try self.write("-std.math.inf(f64)");
                    }
                } else {
                    try self.writeFmt("{d}", .{v});
                }
            },
            .certain_bool => |v| try self.write(if (v) "true" else "false"),
            .certain_str => |s| {
                try self.write("\"");
                try self.writeEscapedString(s);
                try self.write("\"");
            },
            .certain_null => try self.write("null"),
            .uncertain_pyvalue => |_| {
                // Uncertain values need runtime wrapping
                try self.write("runtime.PyValue.none()");
            },
            .raw_expr => |expr| try self.write(expr),
            .bigint => |_| try self.write("runtime.BigInt.zero()"), // TODO: proper BigInt emission
            .unified_int => |_| try self.write("runtime.UnifiedInt{ .small = 0 }"), // TODO
            .array => |arr| {
                try self.write(".{ ");
                for (arr.elements, 0..) |elem, i| {
                    if (i > 0) try self.write(", ");
                    try self.emitValueCore(elem);
                }
                try self.write(" }");
            },
            .struct_literal => |s| {
                try self.write(s.type_name);
                try self.write("{ ");
                for (s.fields, 0..) |field, i| {
                    if (i > 0) try self.write(", ");
                    try self.writeFmt(".{s} = ", .{field.name});
                    try self.emitValueCore(field.value);
                }
                try self.write(" }");
            },
            .method_result => |m| {
                try self.emitValueCore(m.receiver.*);
                try self.writeFmt(".{s}(", .{m.method});
                for (m.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.emitValueCore(arg);
                }
                try self.write(")");
            },
            .binop_result => |b| {
                try self.emitValueCore(b.lhs.*);
                try self.write(" ");
                try self.write(binOpStr(b.op));
                try self.write(" ");
                try self.emitValueCore(b.rhs.*);
            },
            .field_access => |f| {
                try self.emitValueCore(f.obj.*);
                try self.writeFmt(".{s}", .{f.field});
            },
            .subscript => |s| {
                try self.emitValueCore(s.container.*);
                try self.write("[");
                try self.emitValueCore(s.index.*);
                try self.write("]");
            },
        }
    }

    fn writeEscapedString(self: *ZigBuilder, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '\n' => try self.write("\\n"),
                '\r' => try self.write("\\r"),
                '\t' => try self.write("\\t"),
                '\\' => try self.write("\\\\"),
                '"' => try self.write("\\\""),
                else => {
                    if (c < 32 or c > 126) {
                        try self.writeFmt("\\x{x:0>2}", .{c});
                    } else {
                        // Zig 0.15: pass allocator
                        try self.body.append(self.allocator, c);
                    }
                },
            }
        }
    }

    fn valueNeedsParens(self: *ZigBuilder, value: ZigValue) bool {
        _ = self;
        return switch (value) {
            .binop_result => true,
            else => false,
        };
    }

    fn valueCanError(self: *ZigBuilder, value: ZigValue) bool {
        _ = self;
        return switch (value) {
            .method_result => true, // Method calls may return errors
            else => false,
        };
    }

    fn binOpStr(op: BinOp) []const u8 {
        return switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .floor_div => "/", // TODO: Use @divFloor
            .mod => "%",
            .pow => "**", // Not valid Zig, needs runtime call
            .bit_and => "&",
            .bit_or => "|",
            .bit_xor => "^",
            .lshift => "<<",
            .rshift => ">>",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .@"and" => "and",
            .@"or" => "or",
            .in, .not_in, .is, .is_not => "==", // Needs runtime call
        };
    }

    // ============================================
    // Declaration API
    // ============================================

    /// Declare a constant: const name: type = value;
    pub fn declareConst(self: *ZigBuilder, name: []const u8, ty: *const ZigType, value: ZigValue) !LocalIndex {
        try self.writeIndent();
        try self.writeFmt("const {s}", .{name});

        // Emit type annotation if not inferred
        if (ty.* != .any) {
            try self.write(": ");
            // Zig 0.15: ArrayList empty struct
            var type_buf: std.ArrayList(u8) = .{};
            defer type_buf.deinit(self.allocator);
            try ty.emit(type_buf.writer(self.allocator));
            try self.write(type_buf.items);
        }

        try self.write(" = ");
        try self.emitValue(value, EmitConfig.forInit());
        try self.write(";\n");

        // Track binding
        try self.bindings.put(name, ty.*);

        // Allocate local for tracking
        return try self.locals.allocNamed(ty.*, name);
    }

    /// Declare a variable: var name: type = value;
    pub fn declareVar(self: *ZigBuilder, name: []const u8, ty: *const ZigType, value: ZigValue) !LocalIndex {
        try self.writeIndent();
        try self.writeFmt("var {s}", .{name});

        if (ty.* != .any) {
            try self.write(": ");
            // Zig 0.15: ArrayList empty struct
            var type_buf: std.ArrayList(u8) = .{};
            defer type_buf.deinit(self.allocator);
            try ty.emit(type_buf.writer(self.allocator));
            try self.write(type_buf.items);
        }

        try self.write(" = ");
        try self.emitValue(value, EmitConfig.forInit());
        try self.write(";\n");

        try self.bindings.put(name, ty.*);
        return try self.locals.allocNamed(ty.*, name);
    }

    /// Declare an uninitialized variable: var name: type = undefined;
    pub fn declareUndef(self: *ZigBuilder, name: []const u8, ty: *const ZigType) !LocalIndex {
        try self.writeIndent();
        try self.writeFmt("var {s}: ", .{name});

        // Zig 0.15: ArrayList empty struct
        var type_buf: std.ArrayList(u8) = .{};
        defer type_buf.deinit(self.allocator);
        try ty.emit(type_buf.writer(self.allocator));
        try self.write(type_buf.items);

        try self.write(" = undefined;\n");

        try self.bindings.put(name, ty.*);
        return try self.locals.allocNamed(ty.*, name);
    }

    /// Allocate a temporary local
    pub fn allocTemp(self: *ZigBuilder, ty: *const ZigType) !LocalIndex {
        return try self.locals.alloc(ty.*);
    }

    /// Free a temporary local
    pub fn freeTemp(self: *ZigBuilder, idx: LocalIndex) !void {
        try self.locals.free(idx);
    }

    // ============================================
    // Assignment API
    // ============================================

    /// Assign to a named variable: name = value;
    pub fn assign(self: *ZigBuilder, name: []const u8, value: ZigValue) !void {
        try self.writeIndent();
        try self.write(name);
        try self.write(" = ");
        try self.emitValue(value, EmitConfig.forInit());
        try self.write(";\n");
    }

    /// Assign to a local: local = value;
    pub fn assignLocal(self: *ZigBuilder, idx: LocalIndex, value: ZigValue) !void {
        try self.writeIndent();
        if (self.locals.getName(idx)) |name| {
            try self.write(name);
        } else {
            try self.writeFmt("__local_{d}", .{idx});
        }
        try self.write(" = ");
        try self.emitValue(value, EmitConfig.forInit());
        try self.write(";\n");
        self.locals.markAssigned(idx);
    }

    // ============================================
    // Binary operations API
    // ============================================

    /// Create a binary operation value (deferred evaluation)
    pub fn binOp(self: *ZigBuilder, op: BinOp, lhs: ZigValue, rhs: ZigValue) !ZigValue {
        // Allocate storage for operands
        const lhs_ptr = try self.allocator.create(ZigValue);
        lhs_ptr.* = lhs;
        const rhs_ptr = try self.allocator.create(ZigValue);
        rhs_ptr.* = rhs;

        // Determine result confidence
        const confidence: TypeConfidence = if (lhs.needsPyValue() or rhs.needsPyValue())
            .uncertain
        else
            .certain;

        return .{ .binop_result = .{
            .op = op,
            .lhs = lhs_ptr,
            .rhs = rhs_ptr,
            .confidence = confidence,
        } };
    }

    /// Emit a binary operation as a statement (for compound expressions)
    pub fn emitBinOpStmt(self: *ZigBuilder, target: []const u8, op: BinOp, lhs: ZigValue, rhs: ZigValue) !void {
        try self.writeIndent();
        try self.write(target);
        try self.write(" = ");
        try self.emitValue(lhs, EmitConfig.forExpression().withParens());
        try self.writeFmt(" {s} ", .{binOpStr(op)});
        try self.emitValue(rhs, EmitConfig.forExpression().withParens());
        try self.write(";\n");
    }

    // ============================================
    // Control flow API
    // ============================================

    /// Begin an if statement
    pub fn beginIf(self: *ZigBuilder, condition: ZigValue) !ScopeHandle {
        try self.writeIndent();
        try self.write("if (");
        try self.emitValue(condition, EmitConfig.forCondition());
        try self.write(") {\n");

        const id = self.nextId();
        const scope = ScopeContext.conditional(id, self.currentScope());
        // Zig 0.15: pass allocator
        try self.scope_stack.append(self.allocator, scope);
        self.indent();

        return ScopeHandle{
            .id = id,
            .kind = .conditional,
            .start_pos = self.body.items.len,
        };
    }

    /// Begin an else branch
    pub fn beginElse(self: *ZigBuilder) !void {
        self.dedent();
        try self.writeIndent();
        try self.write("} else {\n");
        self.indent();
    }

    /// Begin an else-if branch
    pub fn beginElseIf(self: *ZigBuilder, condition: ZigValue) !void {
        self.dedent();
        try self.writeIndent();
        try self.write("} else if (");
        try self.emitValue(condition, EmitConfig.forCondition());
        try self.write(") {\n");
        self.indent();
    }

    /// End an if statement
    pub fn endIf(self: *ZigBuilder, handle: ScopeHandle) !void {
        _ = handle;
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
        // Zig 0.15: pop() returns ?T
        _ = self.scope_stack.pop();
    }

    /// Begin a while loop
    pub fn beginWhile(self: *ZigBuilder, condition: ZigValue) !ScopeHandle {
        const id = self.nextId();
        const label = try std.fmt.allocPrint(self.allocator, "while_{d}", .{id});

        try self.writeIndent();
        try self.write(label);
        try self.write(": while (");
        try self.emitValue(condition, EmitConfig.forCondition());
        try self.write(") {\n");

        const scope = ScopeContext.loop(id, self.currentScope(), label);
        // Zig 0.15: pass allocator
        try self.scope_stack.append(self.allocator, scope);
        self.indent();

        return ScopeHandle{
            .id = id,
            .kind = .loop,
            .start_pos = self.body.items.len,
        };
    }

    /// End a while loop
    pub fn endWhile(self: *ZigBuilder, handle: ScopeHandle) !void {
        _ = handle;
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
        // Zig 0.15: pop() returns ?T
        if (self.scope_stack.pop()) |scope| {
            // Free the allocated label
            if (scope.break_label) |label| {
                self.allocator.free(label);
            }
        }
    }

    /// Begin a for loop
    pub fn beginFor(self: *ZigBuilder, iterable: ZigValue, capture: []const u8) !ScopeHandle {
        const id = self.nextId();
        const label = try std.fmt.allocPrint(self.allocator, "for_{d}", .{id});

        try self.writeIndent();
        try self.write(label);
        try self.write(": for (");
        try self.emitValue(iterable, EmitConfig.forExpression());
        try self.writeFmt(") |{s}| {{\n", .{capture});

        const scope = ScopeContext.loop(id, self.currentScope(), label);
        // Zig 0.15: pass allocator
        try self.scope_stack.append(self.allocator, scope);
        self.indent();

        return ScopeHandle{
            .id = id,
            .kind = .loop,
            .start_pos = self.body.items.len,
        };
    }

    /// End a for loop
    pub fn endFor(self: *ZigBuilder, handle: ScopeHandle) !void {
        _ = handle;
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
        // Zig 0.15: pop() returns ?T
        if (self.scope_stack.pop()) |scope| {
            // Free the allocated label
            if (scope.break_label) |label| {
                self.allocator.free(label);
            }
        }
    }

    /// Emit a break statement
    pub fn emitBreak(self: *ZigBuilder) !void {
        try self.writeIndent();
        if (self.currentScope().break_label) |label| {
            try self.writeFmt("break :{s};\n", .{label});
        } else {
            try self.write("break;\n");
        }
    }

    /// Emit a continue statement
    pub fn emitContinue(self: *ZigBuilder) !void {
        try self.writeIndent();
        if (self.currentScope().break_label) |label| {
            try self.writeFmt("continue :{s};\n", .{label});
        } else {
            try self.write("continue;\n");
        }
    }

    /// Emit a return statement
    pub fn emitReturn(self: *ZigBuilder, value: ?ZigValue) !void {
        try self.writeIndent();
        try self.write("return");
        if (value) |v| {
            try self.write(" ");
            try self.emitValue(v, EmitConfig.forReturn());
        }
        try self.write(";\n");
    }

    // ============================================
    // Labeled blocks API
    // ============================================

    /// Begin a labeled block
    pub fn beginBlock(self: *ZigBuilder, label: []const u8) !ScopeHandle {
        const id = self.nextId();

        try self.writeIndent();
        try self.write(label);
        try self.write(": {\n");

        const scope = ScopeContext.labeledBlock(id, self.currentScope(), label);
        // Zig 0.15: pass allocator
        try self.scope_stack.append(self.allocator, scope);
        self.indent();

        return ScopeHandle{
            .id = id,
            .kind = .labeled_block,
            .start_pos = self.body.items.len,
        };
    }

    /// End a labeled block
    pub fn endBlock(self: *ZigBuilder, handle: ScopeHandle) !void {
        _ = handle;
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
        // Zig 0.15: pop() returns ?T
        _ = self.scope_stack.pop();
    }

    /// Emit a break with value from labeled block
    pub fn emitBreakWithValue(self: *ZigBuilder, label: []const u8, value: ZigValue) !void {
        try self.writeIndent();
        try self.writeFmt("break :{s} ", .{label});
        try self.emitValue(value, EmitConfig.forExpression());
        try self.write(";\n");
    }

    // ============================================
    // Inline Block Expression API
    // ============================================
    //
    // These APIs emit labeled blocks as expressions (wrapped in parentheses),
    // suitable for use within larger expressions. Unlike beginBlock/endBlock
    // which emit statement-style blocks with newlines.
    //
    // Example output: (__m0_blk: { const x = 1; break :__m0_blk x + 1; })

    /// Generate a fresh label for an inline block expression
    /// Use this with emitInlineBlockStart/emitInlineBlockBreak/emitInlineBlockEnd
    pub fn freshInlineLabel(self: *ZigBuilder, hint: []const u8) ![]const u8 {
        if (self.name_gen) |ng| {
            return ng.fresh(hint);
        }
        const id = self.internal_counter;
        self.internal_counter += 1;
        return std.fmt.allocPrint(self.allocator, "__m{d}_{s}", .{ id, hint });
    }

    /// Start an inline block expression: (__m{id}_{hint}: {
    /// Returns the label for use with emitInlineBlockBreak
    pub fn emitInlineBlockStart(self: *ZigBuilder, hint: []const u8) ![]const u8 {
        const label = try self.freshInlineLabel(hint);
        try self.writeFmt("({s}: {{ ", .{label});
        return label;
    }

    /// Emit break with value for inline block: break :label value;
    /// Note: No indent/newline - this is inline
    pub fn emitInlineBlockBreak(self: *ZigBuilder, label: []const u8, value: ZigValue) !void {
        try self.writeFmt("break :{s} ", .{label});
        try self.emitValue(value, EmitConfig.forExpression());
        try self.write("; ");
    }

    /// End an inline block expression: })
    pub fn emitInlineBlockEnd(self: *ZigBuilder) !void {
        try self.write("})");
    }

    /// Emit a complete inline block expression with a single break value
    /// Output: (__m{id}_{hint}: { body break :__m{id}_{hint} result; })
    pub fn emitInlineBlock(self: *ZigBuilder, hint: []const u8, body: []const u8, result: ZigValue) !void {
        const label = try self.freshInlineLabel(hint);
        try self.writeFmt("({s}: {{ {s} break :{s} ", .{ label, body, label });
        try self.emitValue(result, EmitConfig.forExpression());
        try self.write("; })");
    }

    /// Emit a complete inline block with raw body and raw result (for migration)
    pub fn emitInlineBlockRaw(self: *ZigBuilder, hint: []const u8, body: []const u8, result: []const u8) !void {
        const label = try self.freshInlineLabel(hint);
        try self.writeFmt("({s}: {{ {s} break :{s} {s}; }})", .{ label, body, label, result });
    }

    // ============================================
    // Function API
    // ============================================

    /// Begin a function definition
    pub fn beginFunction(self: *ZigBuilder, name: []const u8, params: []const FuncParam, return_type: ?*const ZigType) !ScopeHandle {
        const id = self.nextId();

        try self.writeIndent();
        try self.writeFmt("pub fn {s}(", .{name});

        for (params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            try self.write(param.name);
            try self.write(": ");
            // Zig 0.15: ArrayList empty struct
            var type_buf: std.ArrayList(u8) = .{};
            defer type_buf.deinit(self.allocator);
            try param.type_.emit(type_buf.writer(self.allocator));
            try self.write(type_buf.items);
        }

        try self.write(") ");

        if (return_type) |rt| {
            // Zig 0.15: ArrayList empty struct
            var type_buf: std.ArrayList(u8) = .{};
            defer type_buf.deinit(self.allocator);
            try rt.emit(type_buf.writer(self.allocator));
            try self.write(type_buf.items);
        } else {
            try self.write("void");
        }

        try self.write(" {\n");

        const scope = ScopeContext.function(id, self.currentScope());
        // Zig 0.15: pass allocator
        try self.scope_stack.append(self.allocator, scope);
        self.indent();
        self.in_function = true;

        return ScopeHandle{
            .id = id,
            .kind = .function,
            .start_pos = self.body.items.len,
        };
    }

    /// End a function definition
    pub fn endFunction(self: *ZigBuilder, handle: ScopeHandle) !void {
        _ = handle;
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
        // Zig 0.15: pop() returns ?T
        _ = self.scope_stack.pop();
        self.in_function = false;
    }

    // ============================================
    // Expression statements API
    // ============================================

    /// Emit a function call as statement
    pub fn emitCall(self: *ZigBuilder, func: []const u8, args: []const ZigValue) !void {
        try self.writeIndent();
        try self.write(func);
        try self.write("(");
        for (args, 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.emitValue(arg, EmitConfig.forArg());
        }
        try self.write(");\n");
    }

    /// Emit a method call as statement
    pub fn emitMethodCall(self: *ZigBuilder, receiver: ZigValue, method: []const u8, args: []const ZigValue) !void {
        try self.writeIndent();
        try self.emitValue(receiver, EmitConfig.forExpression());
        try self.writeFmt(".{s}(", .{method});
        for (args, 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.emitValue(arg, EmitConfig.forArg());
        }
        try self.write(");\n");
    }

    /// Emit a raw statement
    pub fn emitRaw(self: *ZigBuilder, code: []const u8) !void {
        try self.writeIndent();
        try self.write(code);
        try self.write("\n");
    }

    /// Emit a raw line (no indent, no newline auto-add)
    pub fn emitRawLine(self: *ZigBuilder, code: []const u8) !void {
        try self.write(code);
    }

    // ============================================
    // Comment API
    // ============================================

    /// Emit a comment
    pub fn emitComment(self: *ZigBuilder, comment: []const u8) !void {
        try self.writeIndent();
        try self.write("// ");
        try self.write(comment);
        try self.write("\n");
    }

    /// Emit a blank line
    pub fn emitBlankLine(self: *ZigBuilder) !void {
        try self.write("\n");
    }

    // ============================================
    // Import API
    // ============================================

    /// Add an import to preamble
    pub fn addImport(self: *ZigBuilder, name: []const u8, path: []const u8) !void {
        // Zig 0.15: pass allocator to writer
        try self.preamble.writer(self.allocator).print("const {s} = @import(\"{s}\");\n", .{ name, path });
    }

    // ============================================
    // Output API
    // ============================================

    /// Get the complete generated code
    pub fn finish(self: *ZigBuilder) ![]const u8 {
        // Zig 0.15: ArrayList is empty struct, pass allocator to methods
        var result: std.ArrayList(u8) = .{};

        // Preamble (imports)
        if (self.preamble.items.len > 0) {
            try result.appendSlice(self.allocator, self.preamble.items);
            try result.append(self.allocator, '\n');
        }

        // Type definitions
        if (self.types.items.len > 0) {
            try result.appendSlice(self.allocator, self.types.items);
            try result.append(self.allocator, '\n');
        }

        // Header (forward declarations)
        if (self.header.items.len > 0) {
            try result.appendSlice(self.allocator, self.header.items);
            try result.append(self.allocator, '\n');
        }

        // Main body
        try result.appendSlice(self.allocator, self.body.items);

        return result.toOwnedSlice(self.allocator);
    }

    /// Get current body content (for inspection)
    pub fn getBody(self: *ZigBuilder) []const u8 {
        return self.body.items;
    }

    /// Get current body content and clear the buffer
    /// Use this when flushing builder output to another buffer
    ///
    /// CRITICAL: This method is called by emitConst() which immediately appends
    /// the returned slice to self.output. The slice MUST remain valid until
    /// appendSlice() completes. Since clearRetainingCapacity() keeps the buffer
    /// allocated and subsequent write() calls may reuse it, we MUST ensure
    /// the slice remains valid.
    ///
    /// The current implementation returns self.body.items directly, which is
    /// safe because:
    /// 1. The caller (emitConst) calls appendSlice() immediately
    /// 2. appendSlice() copies the bytes before returning
    /// 3. The buffer is not modified between getBodyAndClear() and appendSlice()
    ///
    /// However, if multiple emitConst() calls happen in quick succession, the
    /// buffer may be reused before appendSlice() completes, causing corruption.
    pub fn getBodyAndClear(self: *ZigBuilder) []const u8 {
        const result = self.body.items;
        self.body.clearRetainingCapacity();
        return result;
    }

    /// Clear the body buffer without returning content
    pub fn clearBody(self: *ZigBuilder) void {
        self.body.clearRetainingCapacity();
    }

    /// Get type pool reference
    pub fn getTypePool(self: *ZigBuilder) *TypePool {
        return &self.type_pool;
    }

    // ============================================
    // Context manager (with statement) helpers
    // ============================================

    /// Emit a context manager with defer cleanup (callback style)
    ///
    /// Example usage:
    ///   try b.withContextManager("ctx", args, struct {
    ///       fn emit(builder: *ZigBuilder, ctx_name: []const u8, a: []ast.Node) !void {
    ///           try builder.writeIndent();
    ///           try builder.writeFmt("const {s} = ", .{ctx_name});
    ///           // ... emit context manager expression ...
    ///           try builder.write(";\n");
    ///
    ///           try builder.writeIndent();
    ///           try builder.writeFmt("defer {s}.__exit__(null, null, null);\n", .{ctx_name});
    ///
    ///           // ... emit body ...
    ///       }
    ///   }.emit);
    ///
    /// Features:
    /// - Callback style - can't forget to close
    /// - Context manager name is managed for you
    /// - Handles defer cleanup automatically
    pub fn withContextManager(self: *ZigBuilder, hint: []const u8, context: anytype, body_fn: anytype) !void {
        const id = self.nextId();
        const ctx_name = try std.fmt.allocPrint(self.allocator, "__{s}{d}", .{ hint, id });
        defer self.allocator.free(ctx_name);

        // Call body with context manager name
        try body_fn(self, ctx_name, context);
    }

    /// While loop with callback style (can't forget to close)
    pub fn withWhile(self: *ZigBuilder, condition: ZigValue, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.write("while (");
        try self.emitValue(condition, .{});
        try self.write(") {\n");
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// While loop with automatic bool conversion for Python truthiness semantics
    /// Use this when the condition may not be a boolean type (e.g., integers, strings)
    /// The caller provides the bool conversion prefix/suffix (from bool_conv module)
    /// Example prefixes/suffixes:
    /// - int: "(" / ") != 0"
    /// - float: "(" / ") != 0.0"
    /// - string: "(" / ").len > 0"
    /// - bool: "(" / ")" (passthrough)
    pub fn withWhileBool(self: *ZigBuilder, condition: ZigValue, bool_prefix: []const u8, bool_suffix: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.write("while (");
        try self.emitAsBool(condition, bool_prefix, bool_suffix);
        try self.write(") {\n");
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Emit a value with Python truthiness bool conversion
    /// Wraps the value with the provided prefix/suffix strings
    pub fn emitAsBool(self: *ZigBuilder, value: ZigValue, prefix: []const u8, suffix: []const u8) !void {
        try self.write(prefix);
        try self.emitValue(value, .{});
        try self.write(suffix);
    }

    /// Emit with Python truthiness bool conversion using a callback for the inner expression
    /// Use this when generating expressions inline (via genExpr) rather than captured values
    /// Example: withAsBool("(", ")", fn) emits "(expr)" for bool type, "((expr) != 0)" for int
    pub fn withAsBool(self: *ZigBuilder, prefix: []const u8, suffix: []const u8, body_fn: anytype, context: anytype) !void {
        try self.write(prefix);
        try body_fn(self, context);
        try self.write(suffix);
    }

    /// For loop with callback style
    pub fn withFor(self: *ZigBuilder, iterable: ZigValue, capture: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.write("for (");
        try self.emitValue(iterable, .{});
        try self.writeFmt(") |{s}| {{\n", .{capture});
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// If statement with callback style
    pub fn withIf(self: *ZigBuilder, condition: ZigValue, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.write("if (");
        try self.emitValue(condition, .{});
        try self.write(") {\n");
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Generic block with callback style
    pub fn withBlock(self: *ZigBuilder, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.write("{\n");
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    // ============================================
    // Callback-Based Auto-Closing APIs (Phase 1)
    // ============================================
    //
    // These methods guarantee proper closing of braces.
    // The callback pattern makes it impossible to forget closing braces.

    /// Struct definition with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withStruct("MyTuple", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write("x: i64,\n");
    ///           try b.writeIndent();
    ///           try b.write("y: f64,\n");
    ///       }
    ///   }.emit, {});
    ///
    /// Generates:
    ///   const MyTuple = struct {
    ///       x: i64,
    ///       y: f64,
    ///   };
    pub fn withStruct(self: *ZigBuilder, name: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("const {s} = struct {{\n", .{name});
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("};\n");
    }

    /// Anonymous struct literal with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withAnonStruct(struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.write(".x = 1, .y = 2");
    ///       }
    ///   }.emit, {});
    ///
    /// Generates: .{ .x = 1, .y = 2 }
    pub fn withAnonStruct(self: *ZigBuilder, body_fn: anytype, context: anytype) !void {
        try self.write(".{ ");
        try body_fn(self, context);
        try self.write(" }");
    }

    /// Inline for loop with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withInlineFor("fields", "|field|", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write("// process field\n");
    ///       }
    ///   }.emit, {});
    ///
    /// Generates:
    ///   inline for (fields) |field| {
    ///       // process field
    ///   }
    pub fn withInlineFor(self: *ZigBuilder, iterable: []const u8, capture: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("inline for ({s}) {s} {{\n", .{ iterable, capture });
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// For loop with raw string iterable (auto-close guaranteed)
    ///
    /// Use this when you have a pre-rendered expression string.
    /// For ZigValue iterables, use withFor() instead.
    pub fn withForRaw(self: *ZigBuilder, iterable: []const u8, capture: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("for ({s}) |{s}| {{\n", .{ iterable, capture });
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// For loop with index (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withForIndexed("items", "item", "i", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           // body
    ///       }
    ///   }.emit, {});
    ///
    /// Generates:
    ///   for (items, 0..) |item, i| {
    ///       // body
    ///   }
    pub fn withForIndexed(self: *ZigBuilder, iterable: []const u8, capture: []const u8, index_name: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("for ({s}, 0..) |{s}, {s}| {{\n", .{ iterable, capture, index_name });
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Try block with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withTryBlock(struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write("try riskyOperation();\n");
    ///       }
    ///   }.emit, {});
    ///
    /// Note: In Zig, try doesn't create a block. This is for semantic grouping.
    /// For actual error handling, use withTryCatch.
    pub fn withTryExpr(self: *ZigBuilder, expr_fn: anytype, context: anytype) !void {
        try self.write("try ");
        try expr_fn(self, context);
    }

    /// If-else expression with callbacks (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withIfElse("condition", thenFn, elseFn, ctx);
    ///
    /// Generates:
    ///   if (condition) {
    ///       // then body
    ///   } else {
    ///       // else body
    ///   }
    pub fn withIfElse(self: *ZigBuilder, condition: []const u8, then_fn: anytype, else_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("if ({s}) {{\n", .{condition});
        self.indent();

        try then_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("} else {\n");
        self.indent();

        try else_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// If with optional else (auto-close guaranteed)
    ///
    /// Use this when else is optional. Pass null for no else branch.
    pub fn withIfOpt(self: *ZigBuilder, condition: []const u8, then_fn: anytype, else_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("if ({s}) {{\n", .{condition});
        self.indent();

        try then_fn(self, context);

        self.dedent();

        const TypeInfo = @typeInfo(@TypeOf(else_fn));
        const is_null = TypeInfo == .null;

        if (!is_null) {
            try self.writeIndent();
            try self.write("} else {\n");
            self.indent();
            try else_fn(self, context);
            self.dedent();
        }

        try self.writeIndent();
        try self.write("}\n");
    }

    /// Labeled block expression with callback (auto-close guaranteed)
    ///
    /// Returns a LabeledBlockScope that provides breakWith() for returning values.
    ///
    /// Example:
    ///   const scope = try builder.beginLabeledBlockExpr("result");
    ///   // ... generate body ...
    ///   try scope.breakWith(ZigValue.int(42));
    ///   try builder.endLabeledBlockExpr(scope);
    ///
    /// Generates:
    ///   result: {
    ///       // body
    ///       break :result 42;
    ///   }
    pub const LabeledBlockScope = struct {
        builder: *ZigBuilder,
        label: []const u8,
        owns_label: bool,

        /// Break with a ZigValue
        pub fn breakWith(self: *LabeledBlockScope, value: ZigValue) !void {
            try self.builder.writeIndent();
            try self.builder.writeFmt("break :{s} ", .{self.label});
            try self.builder.emitValue(value, EmitConfig.forExpression());
            try self.builder.write(";\n");
        }

        /// Break with a raw expression string
        pub fn breakWithRaw(self: *LabeledBlockScope, expr: []const u8) !void {
            try self.builder.writeIndent();
            try self.builder.writeFmt("break :{s} {s};\n", .{ self.label, expr });
        }

        /// Continue to the labeled loop
        pub fn continueLoop(self: *LabeledBlockScope) !void {
            try self.builder.writeIndent();
            try self.builder.writeFmt("continue :{s};\n", .{self.label});
        }

        /// Get the label for use in nested code
        pub fn getLabel(self: *LabeledBlockScope) []const u8 {
            return self.label;
        }
    };

    /// Begin a labeled block expression
    pub fn beginLabeledBlockExpr(self: *ZigBuilder, label: []const u8) !LabeledBlockScope {
        try self.writeIndent();
        try self.writeFmt("{s}: {{\n", .{label});
        self.indent();

        return LabeledBlockScope{
            .builder = self,
            .label = label,
            .owns_label = false,
        };
    }

    /// Begin a labeled block expression with auto-generated label
    pub fn beginLabeledBlockExprAuto(self: *ZigBuilder, hint: []const u8) !LabeledBlockScope {
        const label = try self.freshBlockLabel();
        _ = hint;

        try self.writeIndent();
        try self.writeFmt("{s}: {{\n", .{label});
        self.indent();

        return LabeledBlockScope{
            .builder = self,
            .label = label,
            .owns_label = true,
        };
    }

    /// End a labeled block expression
    pub fn endLabeledBlockExpr(self: *ZigBuilder, scope: LabeledBlockScope) !void {
        self.dedent();
        try self.writeIndent();
        try self.write("}\n");

        if (scope.owns_label) {
            self.allocator.free(scope.label);
        }
    }

    /// Labeled block with callback (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withLabeledBlock("blk", struct {
    ///       fn emit(b: *ZigBuilder, scope: *LabeledBlockScope, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write("if (cond) ");
    ///           try scope.breakWithRaw("value");
    ///       }
    ///   }.emit, {});
    pub fn withLabeledBlock(self: *ZigBuilder, label: []const u8, body_fn: anytype, context: anytype) !void {
        var scope = try self.beginLabeledBlockExpr(label);
        try body_fn(self, &scope, context);
        try self.endLabeledBlockExpr(scope);
    }

    /// Function definition with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withFnDef("add", "x: i64, y: i64", "i64", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write("return x + y;\n");
    ///       }
    ///   }.emit, {});
    ///
    /// Generates:
    ///   fn add(x: i64, y: i64) i64 {
    ///       return x + y;
    ///   }
    pub fn withFnDef(self: *ZigBuilder, name: []const u8, params: []const u8, return_type: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("fn {s}({s}) {s} {{\n", .{ name, params, return_type });
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Public function definition with callback body (auto-close guaranteed)
    pub fn withPubFnDef(self: *ZigBuilder, name: []const u8, params: []const u8, return_type: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("pub fn {s}({s}) {s} {{\n", .{ name, params, return_type });
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Const declaration with callback for value (auto-semicolon guaranteed)
    ///
    /// Example:
    ///   try builder.withConstDecl("x", "i64", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.write("compute()");
    ///       }
    ///   }.emit, {});
    ///
    /// Generates: const x: i64 = compute();
    pub fn withConstDecl(self: *ZigBuilder, name: []const u8, type_annotation: ?[]const u8, value_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("const {s}", .{name});
        if (type_annotation) |ty| {
            try self.writeFmt(": {s}", .{ty});
        }
        try self.write(" = ");
        try value_fn(self, context);
        try self.write(";\n");
    }

    /// Var declaration with callback for value (auto-semicolon guaranteed)
    pub fn withVarDecl(self: *ZigBuilder, name: []const u8, type_annotation: ?[]const u8, value_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("var {s}", .{name});
        if (type_annotation) |ty| {
            try self.writeFmt(": {s}", .{ty});
        }
        try self.write(" = ");
        try value_fn(self, context);
        try self.write(";\n");
    }

    /// While loop with raw condition string (auto-close guaranteed)
    pub fn withWhileRaw(self: *ZigBuilder, condition: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("while ({s}) {{\n", .{condition});
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Switch statement with callback body (auto-close guaranteed)
    ///
    /// Example:
    ///   try builder.withSwitch("value", struct {
    ///       fn emit(b: *ZigBuilder, _: void) !void {
    ///           try b.writeIndent();
    ///           try b.write(".foo => doFoo(),\n");
    ///           try b.writeIndent();
    ///           try b.write("else => {},\n");
    ///       }
    ///   }.emit, {});
    pub fn withSwitch(self: *ZigBuilder, value: []const u8, body_fn: anytype, context: anytype) !void {
        try self.writeIndent();
        try self.writeFmt("switch ({s}) {{\n", .{value});
        self.indent();

        try body_fn(self, context);

        self.dedent();
        try self.writeIndent();
        try self.write("}\n");
    }

    /// Discard expression: _ = &expr;
    /// Used for unused parameters/variables
    pub fn emitDiscard(self: *ZigBuilder, expr: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("_ = &{s};\n", .{expr});
    }

    /// Emit const declaration with raw value
    pub fn emitConstRaw(self: *ZigBuilder, name: []const u8, value: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("const {s} = {s};\n", .{ name, value });
    }

    /// Emit const declaration with type and raw value
    pub fn emitConstTypedRaw(self: *ZigBuilder, name: []const u8, type_str: []const u8, value: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("const {s}: {s} = {s};\n", .{ name, type_str, value });
    }

    /// Emit var declaration with raw value
    pub fn emitVarRaw(self: *ZigBuilder, name: []const u8, type_str: ?[]const u8, value: []const u8) !void {
        try self.writeIndent();
        if (type_str) |ts| {
            try self.writeFmt("var {s}: {s} = {s};\n", .{ name, ts, value });
        } else {
            try self.writeFmt("var {s} = {s};\n", .{ name, value });
        }
    }

    /// Emit assignment with raw expressions
    pub fn emitAssignRaw(self: *ZigBuilder, target: []const u8, value: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("{s} = {s};\n", .{ target, value });
    }

    /// Emit return with raw expression
    pub fn emitReturnRaw(self: *ZigBuilder, value: ?[]const u8) !void {
        try self.writeIndent();
        if (value) |v| {
            try self.writeFmt("return {s};\n", .{v});
        } else {
            try self.write("return;\n");
        }
    }

    /// Emit defer statement
    pub fn emitDefer(self: *ZigBuilder, expr: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("defer {s};\n", .{expr});
    }

    /// Emit errdefer statement
    pub fn emitErrdefer(self: *ZigBuilder, expr: []const u8) !void {
        try self.writeIndent();
        try self.writeFmt("errdefer {s};\n", .{expr});
    }

    // ============================================
    // Statement-level callbacks (auto-semicolon)
    // ============================================

    /// Generate a statement with automatic semicolon handling (callback style)
    /// The callback receives the builder and context, and should emit the statement expression.
    /// This automatically adds:
    /// - Indentation
    /// - Semicolon and newline after the statement
    /// - Optional `_ = ` prefix for value-returning expressions (if add_discard = true)
    ///
    /// Example:
    ///   try builder.withStatement(struct {
    ///       fn emit(b: *ZigBuilder, ctx: void) !void {
    ///           try b.write("try unittest.assertEqual(x, y)");
    ///       }
    ///   }.emit, {}, .{ .add_discard = false });
    ///
    /// Generates: `    try unittest.assertEqual(x, y);\n`
    pub fn withStatement(self: *ZigBuilder, body_fn: anytype, context: anytype, opts: struct {
        add_discard: bool = false,
        skip_semicolon: bool = false, // For complete statements like if/while
    }) !void {
        try self.writeIndent();

        if (opts.add_discard) {
            try self.write("_ = ");
        }

        try body_fn(self, context);

        if (!opts.skip_semicolon) {
            try self.write(";\n");
        } else {
            try self.write("\n");
        }
    }
};

/// Function parameter info
pub const FuncParam = struct {
    name: []const u8,
    type_: ZigType,
};

// ============================================
// Tests
// ============================================

test "ZigBuilder basic declaration" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const pool = builder.getTypePool();
    _ = try builder.declareConst("x", pool.i64_(), ZigValue.int(42));

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "const x: i64 = 42;") != null);
}

test "ZigBuilder if statement" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const handle = try builder.beginIf(ZigValue.boolean(true));
    try builder.assign("result", ZigValue.int(1));
    try builder.endIf(handle);

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "if (true)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "result = 1;") != null);
}

test "ZigBuilder while loop" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const handle = try builder.beginWhile(ZigValue.boolean(true));
    try builder.emitBreak();
    try builder.endWhile(handle);

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "while (true)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "break") != null);
}

test "ZigBuilder function" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const pool = builder.getTypePool();
    const params = [_]FuncParam{
        .{ .name = "x", .type_ = .i64 },
        .{ .name = "y", .type_ = .i64 },
    };

    const handle = try builder.beginFunction("add", &params, pool.i64_());
    try builder.emitReturn(ZigValue.raw("x + y"));
    try builder.endFunction(handle);

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn add(x: i64, y: i64) i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "return x + y;") != null);
}

test "ZigBuilder comment and blank line" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitComment("This is a test");
    try builder.emitBlankLine();

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "// This is a test") != null);
}

test "ZigBuilder string escaping" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const pool = builder.getTypePool();
    _ = try builder.declareConst("s", try pool.string(), ZigValue.string("hello\nworld"));

    const output = builder.getBody();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"hello\\nworld\"") != null);
}

test "ZigBuilder finish combines sections" {
    var builder = try ZigBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addImport("std", "std");
    try builder.emitComment("main code");

    const output = try builder.finish();
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "@import(\"std\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "// main code") != null);
}
