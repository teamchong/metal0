/// Python venv module - Virtual environment creation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "EnvBuilder", genEnvBuilder },
    .{ "create", genCreate },
    .{ "ENV_CFG", genEnvCfg },
    .{ "BIN_NAME", genBinName },
});

fn genEnvBuilder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .system_site_packages = false, .clear = false, .symlinks = false, .upgrade = false, .with_pip = false, .prompt = @as(?[]const u8, null), .upgrade_deps = false }"), builder_mod.EmitConfig.forExpression());
}

fn genCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genEnvCfg(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("pyvenv.cfg"), builder_mod.EmitConfig.forExpression());
}

fn genBinName(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("bin"), builder_mod.EmitConfig.forExpression());
}
