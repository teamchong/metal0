/// Pre-Codegen Type Analysis for Variable Declarations
///
/// This module provides a lightweight type inference pass that scans a function
/// body BEFORE code generation to collect type information about local variables.
///
/// This solves the forward-reference problem in variable hoisting:
///
/// Problem:
///   def test():
///       floats = (INF, -INF, 0.0, 1.0, NAN)  # floats assigned here
///       for f in floats:                       # f needs type from floats
///           use(f)
///
/// Without pre-scan, when hoisting `f`, we can't use @TypeOf(floats[0])
/// because floats is declared AFTER the hoisted variable.
///
/// Solution:
///   1. Scan function body BEFORE emitting hoisted declarations
///   2. Record: floats -> element_type: f64 (from tuple literal analysis)
///   3. When hoisting f for "for f in floats:", look up floats -> f64
///   4. Emit: var f: f64 = undefined;
///
/// Usage:
/// ```zig
/// var ctx = VarTypeContext.init(allocator);
/// defer ctx.deinit();
/// ctx.scanFunctionBody(func_body);
/// const elem_type = ctx.getIteratorElementType("floats"); // Returns "f64"
/// ```

const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");

/// Information about a variable's type, derived from its assignment
pub const VarTypeInfo = struct {
    /// The Zig type string for the variable itself
    zig_type: []const u8,
    /// For containers, the element type (for iteration)
    element_type: ?[]const u8,
    /// Source expression (for debugging)
    source: VarSource,
};

pub const VarSource = enum {
    tuple_literal,
    list_literal,
    dict_literal,
    set_literal,
    range_call,
    other_call,
    constant,
    unknown,
};

pub const VarTypeContext = struct {
    allocator: std.mem.Allocator,
    /// Maps variable name -> type info
    var_types: hashmap_helper.StringHashMap(VarTypeInfo),

    pub fn init(allocator: std.mem.Allocator) VarTypeContext {
        return .{
            .allocator = allocator,
            .var_types = hashmap_helper.StringHashMap(VarTypeInfo).init(allocator),
        };
    }

    pub fn deinit(self: *VarTypeContext) void {
        self.var_types.deinit();
    }

    /// Scan a function body to collect variable type information
    pub fn scanFunctionBody(self: *VarTypeContext, body: []const ast.Node) void {
        for (body) |stmt| {
            self.scanStmt(stmt);
        }
    }

    /// Scan a single statement
    fn scanStmt(self: *VarTypeContext, stmt: ast.Node) void {
        switch (stmt) {
            .assign => |a| {
                // Handle: x = (1, 2, 3) or x = [1, 2, 3]
                for (a.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        const info = self.analyzeExpr(a.value.*);
                        self.var_types.put(var_name, info) catch {};
                    }
                }
            },
            .ann_assign => |a| {
                // Handle: x: list[int] = [1, 2, 3]
                if (a.target.* == .name) {
                    const var_name = a.target.name.id;
                    if (a.value) |val| {
                        const info = self.analyzeExpr(val.*);
                        self.var_types.put(var_name, info) catch {};
                    }
                }
            },
            .if_stmt => |i| {
                // Scan both branches
                self.scanFunctionBody(i.body);
                self.scanFunctionBody(i.else_body);
            },
            .for_stmt => |f| {
                self.scanFunctionBody(f.body);
                if (f.orelse_body) |orelse_body| {
                    self.scanFunctionBody(orelse_body);
                }
            },
            .while_stmt => |w| {
                self.scanFunctionBody(w.body);
                if (w.orelse_body) |orelse_body| {
                    self.scanFunctionBody(orelse_body);
                }
            },
            .try_stmt => |t| {
                self.scanFunctionBody(t.body);
                for (t.handlers) |h| {
                    self.scanFunctionBody(h.body);
                }
                self.scanFunctionBody(t.else_body);
                self.scanFunctionBody(t.finalbody);
            },
            .with_stmt => |w| {
                self.scanFunctionBody(w.body);
            },
            .match_stmt => |m| {
                for (m.cases) |case| {
                    self.scanFunctionBody(case.body);
                }
            },
            else => {},
        }
    }

    /// Analyze an expression to determine its type info
    fn analyzeExpr(self: *VarTypeContext, expr: ast.Node) VarTypeInfo {
        _ = self;
        return switch (expr) {
            .tuple => |t| .{
                .zig_type = "runtime.PyValue",
                .element_type = analyzeCollectionElements(t.elts),
                .source = .tuple_literal,
            },
            .list => |l| .{
                .zig_type = "runtime.NativeList",
                .element_type = analyzeCollectionElements(l.elts),
                .source = .list_literal,
            },
            .dict => .{
                .zig_type = "runtime.PyValue",
                .element_type = null, // Dict iteration yields keys
                .source = .dict_literal,
            },
            .set => |s| .{
                .zig_type = "runtime.PyValue",
                .element_type = analyzeCollectionElements(s.elts),
                .source = .set_literal,
            },
            .call => |c| {
                // Check for range() call
                if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "range")) {
                    return .{
                        .zig_type = "[]i64",
                        .element_type = "i64",
                        .source = .range_call,
                    };
                }
                return .{
                    .zig_type = "runtime.PyValue",
                    .element_type = null,
                    .source = .other_call,
                };
            },
            .constant => |c| .{
                .zig_type = switch (c.value) {
                    .int => "i64",
                    .float => "f64",
                    .string => "[]const u8",
                    .bool => "bool",
                    else => "runtime.PyValue",
                },
                .element_type = null,
                .source = .constant,
            },
            else => .{
                .zig_type = "runtime.PyValue",
                .element_type = null,
                .source = .unknown,
            },
        };
    }

    /// Get the element type for iterating over a variable
    /// Returns null if unknown
    pub fn getIteratorElementType(self: *const VarTypeContext, var_name: []const u8) ?[]const u8 {
        if (self.var_types.get(var_name)) |info| {
            return info.element_type;
        }
        return null;
    }

    /// Get the Zig type for a variable
    pub fn getVarType(self: *const VarTypeContext, var_name: []const u8) ?[]const u8 {
        if (self.var_types.get(var_name)) |info| {
            return info.zig_type;
        }
        return null;
    }
};

/// Get the Zig type string for a constant value
fn getConstantType(node: ast.Node) []const u8 {
    return switch (node) {
        .constant => |c| switch (c.value) {
            .int => "i64",
            .float => "f64",
            .string => "[]const u8",
            .bool => "bool",
            else => "runtime.PyValue",
        },
        .unaryop => |u| {
            // Handle -INF, -0.0, -1.0, etc.
            if (u.operand.* == .constant) {
                return switch (u.operand.constant.value) {
                    .float => "f64",
                    .int => "i64",
                    else => "runtime.PyValue",
                };
            }
            // Handle -INF, -NAN (unary minus on name)
            if (u.operand.* == .name) {
                const name = u.operand.name.id;
                if (std.mem.eql(u8, name, "INF") or std.mem.eql(u8, name, "NAN")) {
                    return "f64";
                }
            }
            return "runtime.PyValue";
        },
        .name => |n| {
            // Handle special float constants: INF, NAN
            if (std.mem.eql(u8, n.id, "INF") or std.mem.eql(u8, n.id, "NAN")) {
                return "f64";
            }
            return "runtime.PyValue";
        },
        .call => |c| {
            // Handle known builtin function return types
            if (c.func.* == .name) {
                const fn_name = c.func.name.id;
                // round() with no second arg returns int
                if (std.mem.eql(u8, fn_name, "round")) {
                    // Check if has 1 or 2 args - round(x) returns int, round(x, n) returns float
                    if (c.args.len == 1) {
                        return "i64"; // round(x) returns int
                    }
                }
                // int() returns int
                if (std.mem.eql(u8, fn_name, "int")) {
                    return "i64";
                }
                // float() returns float
                if (std.mem.eql(u8, fn_name, "float")) {
                    return "f64";
                }
            }
            return "runtime.PyValue";
        },
        else => "runtime.PyValue",
    };
}

/// Analyze collection literal elements and return consistent element type
fn analyzeCollectionElements(elements: []const ast.Node) ?[]const u8 {
    if (elements.len == 0) return null;

    // Check first element type
    const first_type = getConstantType(elements[0]);
    if (std.mem.eql(u8, first_type, "runtime.PyValue")) return null;

    // Verify all elements have same type
    for (elements[1..]) |elem| {
        if (!std.mem.eql(u8, getConstantType(elem), first_type)) {
            return null; // Mixed types
        }
    }
    return first_type;
}

test "analyzeCollectionElements - homogeneous float tuple" {
    // Would test (INF, -INF, 0.0, 1.0, NAN) if we could construct AST nodes easily
}
