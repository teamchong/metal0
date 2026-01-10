//! Pass 3: Emit
//!
//! Converts IR to Zig source code, using mutation analysis to determine
//! whether variables should be declared as `const` or `var`.

const std = @import("std");
const ir = @import("../ir.zig");
const pass_analysis = @import("analysis.zig");

pub const ZigIR = ir.ZigIR;
pub const ZigIRExpr = ir.ZigIRExpr;
pub const ZigIRType = ir.ZigIRType;
pub const MutationAnalysis = pass_analysis.MutationAnalysis;
pub const AnalysisResult = pass_analysis.AnalysisResult;

/// Emitter state
pub const Emitter = struct {
    output: *std.ArrayList(u8),
    indent_level: usize = 0,
    analysis: *const MutationAnalysis,
    allocator: std.mem.Allocator,

    const INDENT = "    ";

    pub fn init(
        output: *std.ArrayList(u8),
        analysis: *const MutationAnalysis,
        allocator: std.mem.Allocator,
    ) Emitter {
        return .{
            .output = output,
            .analysis = analysis,
            .allocator = allocator,
        };
    }

    /// Write indentation
    fn emitIndent(self: *Emitter) !void {
        for (0..self.indent_level) |_| {
            try self.output.appendSlice(self.allocator, INDENT);
        }
    }

    /// Write raw string
    fn emit(self: *Emitter, s: []const u8) !void {
        try self.output.appendSlice(self.allocator, s);
    }

    /// Write formatted string
    fn emitFmt(self: *Emitter, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print(fmt, args);
    }

    /// Emit a statement
    pub fn emitStmt(self: *Emitter, stmt: ZigIR) !void {
        switch (stmt) {
            .const_decl => |cd| {
                try self.emitIndent();
                if (cd.is_pub) try self.emit("pub ");
                try self.emit("const ");
                try self.emit(cd.name);
                if (cd.type_) |t| {
                    try self.emit(": ");
                    try self.emitType(t);
                }
                try self.emit(" = ");
                try self.emitExpr(cd.init);
                try self.emit(";\n");
            },

            .var_decl => |vd| {
                try self.emitIndent();
                if (vd.is_pub) try self.emit("pub ");

                // Use mutation analysis to decide const vs var
                if (self.analysis.shouldBeConst(vd.name)) {
                    try self.emit("const ");
                } else {
                    try self.emit("var ");
                }

                try self.emit(vd.name);
                if (vd.type_) |t| {
                    try self.emit(": ");
                    try self.emitType(t);
                }
                try self.emit(" = ");
                try self.emitExpr(vd.init);
                try self.emit(";\n");
            },

            .var_undef => |vu| {
                try self.emitIndent();
                try self.emit("var ");
                try self.emit(vu.name);
                try self.emit(": ");
                try self.emitType(vu.type_);
                try self.emit(" = undefined;\n");
            },

            .assign => |a| {
                try self.emitIndent();
                try self.emitExpr(a.target);
                try self.emit(" = ");
                try self.emitExpr(a.value);
                try self.emit(";\n");
            },

            .aug_assign => |aa| {
                try self.emitIndent();
                try self.emitExpr(aa.target);
                try self.emit(switch (aa.op) {
                    .add => " += ",
                    .sub => " -= ",
                    .mul => " *= ",
                    .div => " /= ",
                    .mod => " %= ",
                    .bit_and => " &= ",
                    .bit_or => " |= ",
                    .bit_xor => " ^= ",
                    .lshift => " <<= ",
                    .rshift => " >>= ",
                });
                try self.emitExpr(aa.value);
                try self.emit(";\n");
            },

            .if_stmt => |i| {
                try self.emitIndent();
                try self.emit("if (");
                try self.emitExpr(i.condition);
                try self.emit(") {\n");

                self.indent_level += 1;
                for (i.then_body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                for (i.else_ifs) |elif| {
                    try self.emitIndent();
                    try self.emit("} else if (");
                    try self.emitExpr(elif.condition);
                    try self.emit(") {\n");

                    self.indent_level += 1;
                    for (elif.body) |s| {
                        try self.emitStmt(s);
                    }
                    self.indent_level -= 1;
                }

                if (i.else_body) |eb| {
                    try self.emitIndent();
                    try self.emit("} else {\n");

                    self.indent_level += 1;
                    for (eb) |s| {
                        try self.emitStmt(s);
                    }
                    self.indent_level -= 1;
                }

                try self.emitIndent();
                try self.emit("}\n");
            },

            .while_loop => |w| {
                try self.emitIndent();
                try self.emit("while (");
                try self.emitExpr(w.condition);
                try self.emit(") {\n");

                self.indent_level += 1;
                for (w.body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                if (w.else_body) |eb| {
                    try self.emitIndent();
                    try self.emit("} else {\n");

                    self.indent_level += 1;
                    for (eb) |s| {
                        try self.emitStmt(s);
                    }
                    self.indent_level -= 1;
                }

                try self.emitIndent();
                try self.emit("}\n");
            },

            .for_loop => |f| {
                try self.emitIndent();
                try self.emit("for (");
                try self.emitExpr(f.iter);
                try self.emit(") |");
                try self.emit(f.target);
                try self.emit("| {\n");

                self.indent_level += 1;
                for (f.body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                if (f.else_body) |eb| {
                    try self.emitIndent();
                    try self.emit("} else {\n");

                    self.indent_level += 1;
                    for (eb) |s| {
                        try self.emitStmt(s);
                    }
                    self.indent_level -= 1;
                }

                try self.emitIndent();
                try self.emit("}\n");
            },

            .inline_for => |f| {
                try self.emitIndent();
                try self.emit("inline for (");
                try self.emitExpr(f.iter);
                try self.emit(") |");
                try self.emit(f.target);
                try self.emit("| {\n");

                self.indent_level += 1;
                for (f.body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                try self.emitIndent();
                try self.emit("}\n");
            },

            .function => |func| {
                try self.emitIndent();
                if (func.is_pub) try self.emit("pub ");
                if (func.is_inline) try self.emit("inline ");
                try self.emit("fn ");
                try self.emit(func.name);
                try self.emit("(");

                for (func.params, 0..) |param, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emit(param.name);
                    if (param.type_) |t| {
                        try self.emit(": ");
                        try self.emitType(t);
                    }
                }

                try self.emit(")");
                if (func.return_type) |rt| {
                    try self.emit(" ");
                    try self.emitType(rt);
                }
                try self.emit(" {\n");

                self.indent_level += 1;
                for (func.body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                try self.emitIndent();
                try self.emit("}\n");
            },

            .return_ => |r| {
                try self.emitIndent();
                try self.emit("return");
                if (r.value) |v| {
                    try self.emit(" ");
                    try self.emitExpr(v);
                }
                try self.emit(";\n");
            },

            .break_ => |b| {
                try self.emitIndent();
                try self.emit("break");
                if (b.label) |l| {
                    try self.emit(" :");
                    try self.emit(l);
                }
                if (b.value) |v| {
                    try self.emit(" ");
                    try self.emitExpr(v);
                }
                try self.emit(";\n");
            },

            .continue_ => |c| {
                try self.emitIndent();
                try self.emit("continue");
                if (c.label) |l| {
                    try self.emit(" :");
                    try self.emit(l);
                }
                try self.emit(";\n");
            },

            .expr_stmt => |e| {
                try self.emitIndent();
                try self.emitExpr(e.expr);
                try self.emit(";\n");
            },

            .block => |b| {
                try self.emitIndent();
                if (b.label) |l| {
                    try self.emit(l);
                    try self.emit(": ");
                }
                try self.emit("{\n");

                self.indent_level += 1;
                for (b.body) |s| {
                    try self.emitStmt(s);
                }
                self.indent_level -= 1;

                try self.emitIndent();
                try self.emit("}\n");
            },

            .defer_ => |d| {
                try self.emitIndent();
                try self.emit("defer ");
                try self.emitExpr(d.expr);
                try self.emit(";\n");
            },

            .errdefer_ => |e| {
                try self.emitIndent();
                try self.emit("errdefer ");
                try self.emitExpr(e.expr);
                try self.emit(";\n");
            },

            .discard => |d| {
                try self.emitIndent();
                try self.emit("_ = ");
                try self.emitExpr(d.expr);
                try self.emit(";\n");
            },

            .comment => |c| {
                try self.emitIndent();
                try self.emit("// ");
                try self.emit(c.text);
                try self.emit("\n");
            },

            .blank => {
                try self.emit("\n");
            },

            .raw => |r| {
                try self.emitIndent();
                try self.emit(r);
                try self.emit("\n");
            },
        }
    }

    /// Emit an expression
    pub fn emitExpr(self: *Emitter, expr: *const ZigIRExpr) !void {
        switch (expr.*) {
            .int => |i| try self.emitFmt("{d}", .{i}),
            .float => |f| try self.emitFmt("{d}", .{f}),
            .bool_ => |b| try self.emit(if (b) "true" else "false"),
            .string => |s| {
                try self.emit("\"");
                try self.emit(s);
                try self.emit("\"");
            },
            .null_ => try self.emit("null"),
            .undefined => try self.emit("undefined"),
            .name => |n| try self.emit(n),

            .field_access => |fa| {
                try self.emitExpr(fa.object);
                try self.emit(".");
                try self.emit(fa.field);
            },

            .subscript => |s| {
                try self.emitExpr(s.object);
                try self.emit("[");
                try self.emitExpr(s.index);
                try self.emit("]");
            },

            .slice => |s| {
                try self.emitExpr(s.object);
                try self.emit("[");
                if (s.start) |start| try self.emitExpr(start);
                try self.emit("..");
                if (s.end) |end| try self.emitExpr(end);
                try self.emit("]");
            },

            .call => |c| {
                try self.emitExpr(c.func);
                try self.emit("(");
                for (c.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitExpr(arg);
                }
                try self.emit(")");
            },

            .binop => |b| {
                try self.emit("(");
                try self.emitExpr(b.left);
                try self.emit(switch (b.op) {
                    .add => " + ",
                    .sub => " - ",
                    .mul => " * ",
                    .div => " / ",
                    .mod => " % ",
                    .bit_and => " & ",
                    .bit_or => " | ",
                    .bit_xor => " ^ ",
                    .lshift => " << ",
                    .rshift => " >> ",
                    .eq => " == ",
                    .ne => " != ",
                    .lt => " < ",
                    .le => " <= ",
                    .gt => " > ",
                    .ge => " >= ",
                    .concat => " ++ ",
                });
                try self.emitExpr(b.right);
                try self.emit(")");
            },

            .unaryop => |u| {
                try self.emit(switch (u.op) {
                    .neg => "-",
                    .bit_not => "~",
                    .logic_not => "!",
                });
                try self.emitExpr(u.operand);
            },

            .boolop => |bo| {
                try self.emit("(");
                for (bo.operands, 0..) |op, i| {
                    if (i > 0) {
                        try self.emit(switch (bo.op) {
                            .@"and" => " and ",
                            .@"or" => " or ",
                        });
                    }
                    try self.emitExpr(op);
                }
                try self.emit(")");
            },

            .ternary => |t| {
                try self.emit("if (");
                try self.emitExpr(t.condition);
                try self.emit(") ");
                try self.emitExpr(t.then_expr);
                try self.emit(" else ");
                try self.emitExpr(t.else_expr);
            },

            .array => |a| {
                if (a.is_slice) try self.emit("&");
                try self.emit("[_]");
                if (a.elem_type) |et| {
                    try self.emitType(et);
                } else {
                    try self.emit("_");
                }
                try self.emit("{ ");
                for (a.elements, 0..) |elem, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitExpr(elem);
                }
                try self.emit(" }");
            },

            .tuple => |t| {
                try self.emit(".{ ");
                for (t.elements, 0..) |elem, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitExpr(elem);
                }
                try self.emit(" }");
            },

            .struct_init => |si| {
                if (si.type_name) |tn| {
                    try self.emit(tn);
                }
                try self.emit("{ ");
                for (si.fields, 0..) |field, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emit(".");
                    try self.emit(field.name);
                    try self.emit(" = ");
                    try self.emitExpr(field.value);
                }
                try self.emit(" }");
            },

            .cast => |c| {
                try self.emit("@as(");
                try self.emitType(c.type_);
                try self.emit(", ");
                try self.emitExpr(c.value);
                try self.emit(")");
            },

            .builtin => |b| {
                try self.emit("@");
                try self.emit(b.name);
                try self.emit("(");
                for (b.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitExpr(arg);
                }
                try self.emit(")");
            },

            .try_ => |t| {
                try self.emit("try ");
                try self.emitExpr(t.expr);
            },

            .catch_ => |c| {
                try self.emitExpr(c.expr);
                try self.emit(" catch ");
                if (c.capture) |cap| {
                    try self.emit("|");
                    try self.emit(cap);
                    try self.emit("| ");
                }
                try self.emitExpr(c.handler);
            },

            .orelse_ => |o| {
                try self.emitExpr(o.expr);
                try self.emit(" orelse ");
                try self.emitExpr(o.default);
            },

            .address_of => |a| {
                try self.emit("&");
                try self.emitExpr(a.expr);
            },

            .deref => |d| {
                try self.emitExpr(d.expr);
                try self.emit(".*");
            },

            .raw => |r| try self.emit(r),
        }
    }

    /// Emit a type
    pub fn emitType(self: *Emitter, t: *const ZigIRType) !void {
        switch (t.*) {
            .i8_ => try self.emit("i8"),
            .i16_ => try self.emit("i16"),
            .i32_ => try self.emit("i32"),
            .i64_ => try self.emit("i64"),
            .i128_ => try self.emit("i128"),
            .u8_ => try self.emit("u8"),
            .u16_ => try self.emit("u16"),
            .u32_ => try self.emit("u32"),
            .u64_ => try self.emit("u64"),
            .u128_ => try self.emit("u128"),
            .usize_ => try self.emit("usize"),
            .f32_ => try self.emit("f32"),
            .f64_ => try self.emit("f64"),
            .bool_ => try self.emit("bool"),
            .void_ => try self.emit("void"),
            .noreturn_ => try self.emit("noreturn"),
            .type_ => try self.emit("type"),
            .comptime_int => try self.emit("comptime_int"),
            .comptime_float => try self.emit("comptime_float"),

            .array => |a| {
                try self.emit("[");
                if (a.size) |s| {
                    try self.emitFmt("{d}", .{s});
                }
                try self.emit("]");
                try self.emitType(a.elem_type);
            },

            .pointer => |p| {
                if (p.is_many) {
                    try self.emit("[*]");
                } else {
                    try self.emit("*");
                }
                if (p.is_const) {
                    try self.emit("const ");
                }
                try self.emitType(p.child);
            },

            .optional => |o| {
                try self.emit("?");
                try self.emitType(o.child);
            },

            .error_union => |eu| {
                if (eu.error_set) |es| {
                    try self.emit(es);
                }
                try self.emit("!");
                try self.emitType(eu.value);
            },

            .named => |n| try self.emit(n),

            .function => |f| {
                try self.emit("fn(");
                for (f.params, 0..) |param, i| {
                    if (i > 0) try self.emit(", ");
                    try self.emitType(param);
                }
                try self.emit(") ");
                try self.emitType(f.return_type);
            },

            .type_of => |e| {
                try self.emit("@TypeOf(");
                try self.emitExpr(e);
                try self.emit(")");
            },

            .anytype_ => try self.emit("anytype"),
        }
    }
};

/// Emit IR statements to output buffer
pub fn emit(
    statements: []const ZigIR,
    analysis: *const MutationAnalysis,
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    var emitter = Emitter.init(output, analysis, allocator);

    for (statements) |stmt| {
        try emitter.emitStmt(stmt);
    }
}
