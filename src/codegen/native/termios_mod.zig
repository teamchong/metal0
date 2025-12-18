/// Python termios module - POSIX style tty control
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "tcgetattr", genTcgetattr },
    .{ "tcsetattr", genTcsetattr },
    .{ "tcsendbreak", genTcsendbreak },
    .{ "tcdrain", genTcdrain },
    .{ "tcflush", genTcflush },
    .{ "tcflow", genTcflow },
    .{ "tcgetwinsize", genTcgetwinsize },
    .{ "tcsetwinsize", genTcsetwinsize },
    .{ "TCSANOW", genTcsanow },
    .{ "TCSADRAIN", genTcsadrain },
    .{ "TCSAFLUSH", genTcsaflush },
    .{ "TCIFLUSH", genTciflush },
    .{ "TCOFLUSH", genTcoflush },
    .{ "TCIOFLUSH", genTcioflush },
    .{ "TCOOFF", genTcooff },
    .{ "TCOON", genTcoon },
    .{ "TCIOFF", genTcioff },
    .{ "TCION", genTcion },
    .{ "ECHO", genEcho },
    .{ "ECHOE", genEchoe },
    .{ "ECHOK", genEchok },
    .{ "ECHONL", genEchonl },
    .{ "ICANON", genIcanon },
    .{ "ISIG", genIsig },
    .{ "IEXTEN", genIexten },
    .{ "ICRNL", genIcrnl },
    .{ "IXON", genIxon },
    .{ "IXOFF", genIxoff },
    .{ "OPOST", genOpost },
    .{ "ONLCR", genOnlcr },
    .{ "CS8", genCs8 },
    .{ "CREAD", genCread },
    .{ "CLOCAL", genClocal },
    .{ "B9600", genB9600 },
    .{ "B19200", genB19200 },
    .{ "B38400", genB38400 },
    .{ "B57600", genB57600 },
    .{ "B115200", genB115200 },
    .{ "VMIN", genVmin },
    .{ "VTIME", genVtime },
    .{ "NCCS", genNccs },
});

fn genTcgetattr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u32{ 0, 0, 0, 0, 0, 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genTcsetattr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcsendbreak(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcdrain(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcflush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcflow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcgetwinsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(u16, 24), @as(u16, 80) }"), builder_mod.EmitConfig.forExpression());
}

fn genTcsetwinsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTcsanow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genTcsadrain(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genTcsaflush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genTciflush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genTcoflush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genTcioflush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genTcooff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genTcoon(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genTcioff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genTcion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genEcho(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000008)"), builder_mod.EmitConfig.forExpression());
}

fn genEchoe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000002)"), builder_mod.EmitConfig.forExpression());
}

fn genEchok(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000004)"), builder_mod.EmitConfig.forExpression());
}

fn genEchonl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000010)"), builder_mod.EmitConfig.forExpression());
}

fn genIcanon(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000100)"), builder_mod.EmitConfig.forExpression());
}

fn genIsig(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000080)"), builder_mod.EmitConfig.forExpression());
}

fn genIexten(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000400)"), builder_mod.EmitConfig.forExpression());
}

fn genIcrnl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000100)"), builder_mod.EmitConfig.forExpression());
}

fn genIxon(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000200)"), builder_mod.EmitConfig.forExpression());
}

fn genIxoff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000400)"), builder_mod.EmitConfig.forExpression());
}

fn genOpost(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000001)"), builder_mod.EmitConfig.forExpression());
}

fn genOnlcr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000002)"), builder_mod.EmitConfig.forExpression());
}

fn genCs8(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000300)"), builder_mod.EmitConfig.forExpression());
}

fn genCread(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00000800)"), builder_mod.EmitConfig.forExpression());
}

fn genClocal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x00008000)"), builder_mod.EmitConfig.forExpression());
}

fn genB9600(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 9600)"), builder_mod.EmitConfig.forExpression());
}

fn genB19200(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 19200)"), builder_mod.EmitConfig.forExpression());
}

fn genB38400(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 38400)"), builder_mod.EmitConfig.forExpression());
}

fn genB57600(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 57600)"), builder_mod.EmitConfig.forExpression());
}

fn genB115200(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 115200)"), builder_mod.EmitConfig.forExpression());
}

fn genVmin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 16)"), builder_mod.EmitConfig.forExpression());
}

fn genVtime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 17)"), builder_mod.EmitConfig.forExpression());
}

fn genNccs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 20)"), builder_mod.EmitConfig.forExpression());
}
